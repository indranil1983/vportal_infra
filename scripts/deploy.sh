#!/bin/bash
# =============================================================================
# vplatform K8s - Full Deploy Script
# Order: SSH Key Gen → OpenTofu → Pre-flight Ansible → Kubespray
# =============================================================================

set -euo pipefail

# --- Determine Paths & Load Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config.src"
source "$CONFIG_FILE"

export ANSIBLE_SSH_KEY_PATH="$SSH_KEY_PATH"
INVENTORY_SRC="$PROJECT_ROOT/kubespray-config/inventory"
KUBESPRAY_INVENTORY="$KUBESPRAY_INSTALL_DIR/inventory/mycluster"

# Fail if run as root
if [[ "$EUID" -eq 0 ]]; then
  log_error "This script should NOT be run with sudo. Please run as a normal user."
fi

usage() {
  echo "Usage: $0 [--skip-tofu] [--skip-preflight] [--skip-kubespray] [--destroy]"
  echo ""
  echo "  --skip-tofu        Skip OpenTofu VM provisioning"
  echo "  --skip-preflight   Skip Ansible pre-flight checks"
  echo "  --skip-kubespray   Skip Kubespray K8s installation"
  echo "  --destroy          Destroy all VMs (tofu destroy)"
  exit 0
}

SKIP_TOFU=false
SKIP_PREFLIGHT=false
SKIP_KUBESPRAY=false
DESTROY=false

for arg in "$@"; do
  case $arg in
    --skip-tofu)       SKIP_TOFU=true ;;
    --skip-preflight)  SKIP_PREFLIGHT=true ;;
    --skip-kubespray)  SKIP_KUBESPRAY=true ;;
    --destroy)         DESTROY=true ;;
    --help|-h)         usage ;;
  esac
done

if [ -n "${SUDO_USER:-}" ]; then
    echo "This script is run with sudo by: $SUDO_USER"
    echo "The User ID is: $SUDO_UID"
else
    echo "This script was run normally by: $(whoami)"
fi

# =============================================================================
# Destroy mode
# =============================================================================
if $DESTROY; then
  log_warn "Destroying all VMs..."
  cd "$PROJECT_ROOT/opentofu"
  tofu destroy -auto-approve
  log_success "All VMs destroyed"
  exit 0
fi



# =============================================================================
# Step 1: OpenTofu — Provision VMs
# =============================================================================
if ! $SKIP_TOFU; then

  # =============================================================================
  # Step 1.1: Ensure SSH Key Exists
  # =============================================================================
  log_step "Step 0 — SSH: Checking for identity keys"
  mkdir -p "$REAL_HOME/.ssh"
  chmod 700 "$REAL_HOME/.ssh"

  if [ -f "$SSH_KEY_PATH" ]; then
      log_info "SSH key already exists at: $SSH_KEY_PATH"
  else
      log_info "Generating new SSH key: $SSH_KEY_NAME for $USER_EMAIL"
      ssh-keygen -t rsa -b 4096 -C "$USER_EMAIL" -f "$SSH_KEY_PATH" -N ""
      log_success "SSH key generated successfully"
  fi

  # =============================================================================
  # Step 1.2: SETUP NW Bridge
  # =============================================================================
  # Define the network from your XML file (assuming it's saved as default.xml)
 # Check if the network is already defined
  if ! virsh net-info "$NETWORK_NAME" >/dev/null 2>&1; then
      log_info "Defining network: $NETWORK_NAME using $NETWORK_CONFIG_FILE"
      virsh net-define "$NETWORK_CONFIG_FILE"
  else
      log_info "Network $NETWORK_NAME is already defined."
  fi

  # Check if the network is active
  if [[ $(virsh net-info "$NETWORK_NAME" | grep "Active" | awk '{print $2}') == "no" ]]; then
      log_info "Starting network: $NETWORK_NAME"
      virsh net-start "$NETWORK_NAME"
      virsh net-autostart "$NETWORK_NAME"
      # Small sleep to let the bridge interface settle
      sleep 2
  else
      log_info "Network $NETWORK_NAME is already active."
  fi
  
  # =============================================================================
  # Step 1.2: Tofu Provisioning
  # =============================================================================

  log_step "Step 1/3 — OpenTofu: Provisioning VMs"

  mkdir -p "$TF_VAR_pool_path"

  cd "$PROJECT_ROOT/opentofu"
  log_info "Running: tofu init"
  tofu init -upgrade

  # --- BOOTSTRAP START ---
  log_info "Bootstrapping storage pool to prevent 'Pool Not Found' errors..."
  # We apply ONLY the pool first. This makes it exist so the next 'plan' doesn't crash.
  tofu apply -target=libvirt_pool."$POOL_NAME" -auto-approve
  # --- BOOTSTRAP END ---

  log_info "Running: tofu validate"
  tofu validate

  log_info "Running: tofu plan"
  tofu plan -out=tfplan

  log_info "Running: tofu apply"
  tofu apply tfplan

  log_success "VMs provisioned"

  # Wait for VMs to finish cloud-init
  log_info "Waiting for VMs to be reachable via SSH..."

  # Maximum number of attempts (e.g., 30 attempts * 5 seconds = 150 seconds max)
  log_step "Step 1.3 — Health Check: Verifying all Nodes"

  # Define the list of IPs from your variables.tf (or extract from tofu output)
  # VM_IPS is already exported from config.src

  for IP in "${VM_IPS[@]}"; do
      log_info "Checking Node: $IP"
      
      MAX_RETRIES=30
      COUNT=0
      SUCCESS=false

      until ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@"$IP" \
          "lsmod | grep -q 'overlay' && lsmod | grep -q 'br_netfilter' && test -f /var/lib/cloud/instance/boot-finished" 2>/dev/null; do
          
          if [ $COUNT -ge $MAX_RETRIES ]; then
              log_error "Node $IP failed health checks (SSH/Overlay/Cloud-Init) after $(($MAX_RETRIES * 5))s."
          fi          
          echo -ne "  Waiting for $IP to initialize... ($(($COUNT + 1))/$MAX_RETRIES)\r"
          sleep 10
          COUNT=$((COUNT + 1))
      done
      echo -e "\n"
      log_success "Node $IP is fully ready."
  done

log_success "All Kubernetes nodes are pre-flight ready!"

log_success "Overlay and br_netfilter are active."
else
  log_warn "Skipping OpenTofu (--skip-tofu)"
fi

# =============================================================================
# Step 2: Ansible Pre-flight
# =============================================================================
if ! $SKIP_PREFLIGHT; then
  log_step "Step 2/3 — Ansible: Pre-flight checks"

  bash -c "source $KUBESPRAY_VENV_DIR/bin/activate && ansible-playbook \
    -i "$PROJECT_ROOT/kubespray-config/inventory/hosts.yml" \
    "$PROJECT_ROOT/ansible/preflight.yml" \
    --private-key="$SSH_KEY_PATH" \
    -v"

  log_success "All nodes passed pre-flight checks"
else
  log_warn "Skipping pre-flight (--skip-preflight)"
fi

# =============================================================================
# Step 3: Kubespray — Install Kubernetes
# =============================================================================
if ! $SKIP_KUBESPRAY; then
  log_step "Step 3/3 — Kubespray: Installing Kubernetes"

  if [[ ! -d "$KUBESPRAY_INSTALL_DIR" ]]; then
    log_error "Kubespray not found at $KUBESPRAY_INSTALL_DIR. Run scripts/setup-host.sh first."
  fi

  # Copy inventory into Kubespray (using KUBESPRAY_INSTALL_DIR)
  log_info "Copying inventory to Kubespray..."
  sudo cp -r "$KUBESPRAY_INSTALL_DIR/inventory/sample" "$KUBESPRAY_INVENTORY" 2>/dev/null || true
  sudo cp "$INVENTORY_SRC/hosts.yml" "$KUBESPRAY_INVENTORY/hosts.yml"

  # Copy group_vars overrides
  sudo mkdir -p "$KUBESPRAY_INVENTORY/group_vars/k8s_cluster"
  sudo cp "$PROJECT_ROOT/kubespray-config/group_vars/k8s-cluster.yml" \
     "$KUBESPRAY_INVENTORY/group_vars/k8s_cluster/k8s-cluster.yml"
  
  log_info "Running Kubespray cluster.yml playbook..."
  cd "$KUBESPRAY_INSTALL_DIR"
  bash -c "source $KUBESPRAY_VENV_DIR/bin/activate && ansible-playbook \
    -i "$KUBESPRAY_INVENTORY/hosts.yml" \
    "$KUBESPRAY_INSTALL_DIR/cluster.yml" \
    --private-key="$SSH_KEY_PATH" \
    --become \
    --become-user=root \
    -v"

  log_success "Kubernetes cluster installed!"
else
  log_warn "Skipping Kubespray (--skip-kubespray)"
fi
  # =============================================================================
  # Fetch kubeconfig
  # =============================================================================
  log_step "Fetching kubeconfig from master"
  
  if ! command -v kubectl &> /dev/null; then
    log_warn "kubectl not found. Installing now..."
    
    # Download the latest stable release binary
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
    
    # Install it to /usr/local/bin
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Clean up the downloaded file
    rm kubectl
    log_success "kubectl version ${K8S_VERSION} installed successfully."
  else
      log_info "kubectl is already installed ($(kubectl version --client --short 2>/dev/null || echo 'version unknown'))"
  fi


  mkdir -p "$LOCAL_KUBE_DIR"

  # Use SSH to stream config. If home-dir file missing, use sudo to get admin.conf
  if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ubuntu@"$MASTER_IP" \
     "sudo cat /etc/kubernetes/admin.conf 2>/dev/null || cat ~/.kube/config 2>/dev/null" > "$LOCAL_KUBECONFIG_PATH"; then
      
      sed -i "s/127.0.0.1/$MASTER_IP/g" "$LOCAL_KUBECONFIG_PATH"
      sed -i "s/localhost/$MASTER_IP/g" "$LOCAL_KUBECONFIG_PATH"
      log_success "Kubeconfig saved to $LOCAL_KUBECONFIG_PATH"
  else
      log_warn "Could not fetch kubeconfig automatically. You may need to fetch it manually."
  fi

  # =============================================================================
  # Test deployment of pods
  # =============================================================================

  log_info "Testing cluster connectivity..."
  log_info "Running test as local user  $REAL_USER..."
  KUBECONFIG="$LOCAL_KUBECONFIG_PATH" kubectl get nodes -o wide
  
  if [ -f "$SCRIPTS_DIR/function_test.sh" ]; then
      bash "$SCRIPTS_DIR/function_test.sh"
  fi



  # =============================================================================
  # Print summary in output folder
  # =============================================================================

  SSH_COMMANDS_PLAIN=""
  for IP in "${VM_IPS[@]}"; do
      SSH_COMMANDS_PLAIN+="  ssh -i $SSH_KEY_PATH ubuntu@$IP\n"
  done

  K8S_SUMMARY_PLAIN=$(cat <<EOF
=============================================================
  Kubernetes cluster is ready!
  Generated on: $(date)
=============================================================

  To use kubectl:
  export KUBECONFIG=$LOCAL_KUBECONFIG_PATH
  kubectl get nodes

  To SSH into the VMs:
${SSH_COMMANDS_PLAIN}
  To see your VM configuration and state use: cd opentofu && tofu show
EOF
)

  # The console output is now handled by printing the file content at the end.

  # Save access summary to cluster-info.txt
  CLUSTER_INFO_FILE="$OUTPUT_DIR/cluster-info.txt"
  mkdir -p "$OUTPUT_DIR"
  echo "$K8S_SUMMARY_PLAIN" > "$CLUSTER_INFO_FILE"

  log_info "Cluster summary also saved to: $CLUSTER_INFO_FILE"

  # Print the contents of the cluster-info file to the console
  echo -e "\n${GREEN}=============================================================${NC}"
  cat "$CLUSTER_INFO_FILE"
