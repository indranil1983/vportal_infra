#!/bin/bash
# =============================================================================
# vplatform K8s - Full Deploy Script
# Order: SSH Key Gen → OpenTofu → Pre-flight Ansible → Kubespray
# =============================================================================

set -euo pipefail

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)


# --- User Configuration Variables ---
HOME_LOC="$REAL_HOME"
SSH_KEY_NAME="id_vportal_rsa"
USER_EMAIL="$REAL_USER@gmail.com"
MASTER_IP="192.168.122.10" 
CURR_PWD_LOC=$(pwd)
IMAGES_DIR="$REAL_HOME"/virtual_machines/disks

SSH_KEY_PATH="$HOME_LOC/.ssh/$SSH_KEY_NAME"
LOCAL_KUBE_DIR="$HOME_LOC/.kube"
LOCAL_KUBECONFIG_PATH="$LOCAL_KUBE_DIR/config-vplatform"
# ------------------------------------

export TF_VAR_ssh_key_path="$SSH_KEY_PATH"
export TF_VAR_ssh_public_key_path="$SSH_KEY_PATH".pub
export TF_VAR_pool_path="$IMAGES_DIR"
export ANSIBLE_SSH_KEY_PATH="$SSH_KEY_PATH"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KUBESPRAY_DIR="/opt/kubespray"
VENV="/opt/kubespray-venv"
INVENTORY_SRC="$PROJECT_ROOT/kubespray-config/inventory"
KUBESPRAY_INVENTORY="$KUBESPRAY_DIR/inventory/mycluster"

log_step()    { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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
  mkdir -p "$HOME_LOC/.ssh"
  chmod 700 "$HOME_LOC/.ssh"

  if [ -f "$SSH_KEY_PATH" ]; then
      log_info "SSH key already exists at: $SSH_KEY_PATH"
  else
      log_info "Generating new SSH key: $SSH_KEY_NAME"
      ssh-keygen -t rsa -b 4096 -C "$USER_EMAIL" -f "$SSH_KEY_PATH" -N ""
      # FIX: Change ownership to the real user
      chown "$REAL_USER":"$REAL_USER" "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
      chmod 600 "$SSH_KEY_PATH"
      chmod 644 "$SSH_KEY_PATH.pub"
      log_success "SSH key generated successfully"

  fi

  # =============================================================================
  # Step 1.2: SETUP NW Bridge
  # =============================================================================
  # Define the network from your XML file (assuming it's saved as default.xml)
 # Check if the network is already defined
  if ! virsh net-info vplatform_nw >/dev/null 2>&1; then
      log_info "Defining network: vplatform_nw"
      virsh net-define "$CURR_PWD_LOC"/scripts/vplatform_nw.xml
  else
      log_info "Network vplatform_nw is already defined."
  fi

  # Check if the network is active
  if [[ $(virsh net-info vplatform_nw | grep "Active" | awk '{print $2}') == "no" ]]; then
      log_info "Starting network: vplatform_nw"
      virsh net-start vplatform_nw
      virsh net-autostart vplatform_nw
      # Small sleep to let the bridge interface settle
      sleep 2
  else
      log_info "Network vplatform_nw is already active."
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
  tofu apply -target=libvirt_pool.vplatform_pool -auto-approve
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
  VM_IPS=($MASTER_IP "192.168.122.11" "192.168.122.12")

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

  source "$VENV/bin/activate"

  # Note: Ensure your hosts.yml uses the correct private_key_file path
  ansible-playbook \
    -i "$PROJECT_ROOT/kubespray-config/inventory/hosts.yml" \
    "$PROJECT_ROOT/ansible/preflight.yml" \
    --private-key="$SSH_KEY_PATH" \
    -v

  log_success "All nodes passed pre-flight checks"
  deactivate
else
  log_warn "Skipping pre-flight (--skip-preflight)"
fi

# =============================================================================
# Step 3: Kubespray — Install Kubernetes
# =============================================================================
if ! $SKIP_KUBESPRAY; then
  log_step "Step 3/3 — Kubespray: Installing Kubernetes"

  if [[ ! -d "$KUBESPRAY_DIR" ]]; then
    log_error "Kubespray not found at $KUBESPRAY_DIR. Run scripts/setup-host.sh first."
  fi

  # Copy inventory into Kubespray
  log_info "Copying inventory to Kubespray..."
  cp -r "$KUBESPRAY_DIR/inventory/sample" "$KUBESPRAY_INVENTORY" 2>/dev/null || true
  cp "$INVENTORY_SRC/hosts.yml" "$KUBESPRAY_INVENTORY/hosts.yml"

  # Copy group_vars overrides
  mkdir -p "$KUBESPRAY_INVENTORY/group_vars/k8s_cluster"
  cp "$PROJECT_ROOT/kubespray-config/group_vars/k8s-cluster.yml" \
     "$KUBESPRAY_INVENTORY/group_vars/k8s_cluster/k8s-cluster.yml"

  source "$VENV/bin/activate"

  log_info "Running Kubespray cluster.yml playbook..."
  cd /opt/kubespray
  ansible-playbook \
    -i "$KUBESPRAY_INVENTORY/hosts.yml" \
    "$KUBESPRAY_DIR/cluster.yml" \
    --private-key="$SSH_KEY_PATH" \
    --become \
    --become-user=root \
    -v

  deactivate
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
      
      # Correct the API server IP (replace 127.0.0.1 with the actual Master VM IP)
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
  su - "$SUDO_USER" -c "export KUBECONFIG=$LOCAL_KUBECONFIG_PATH && kubectl get nodes -o wide"
  

  log() { echo -e "${CYAN}[TEST]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Pre-flight Check ---
if [ ! -f "$LOCAL_KUBECONFIG_PATH" ]; then
    error "Kubeconfig not found at $LOCAL_KUBECONFIG_PATH. Please run deploy.sh first."
else 
    su - "$SUDO_USER" -c "bash $CURR_PWD_LOC/scripts/function_test.sh"
fi

  echo ""
  echo -e "${GREEN}=============================================================${NC}"
  echo -e "${GREEN}  🎉 Kubernetes cluster is ready!${NC}"
  echo -e "${GREEN}=============================================================${NC}"
  echo ""
  echo -e "  To use kubectl:"
  echo -e "  ${YELLOW}export KUBECONFIG=$LOCAL_KUBECONFIG_PATH${NC}"
  echo -e "  ${YELLOW}kubectl get nodes${NC}"
  echo -e "  To see your VM configuration and state use: cd opentofu && tofu show"




