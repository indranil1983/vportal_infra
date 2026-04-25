#!/bin/bash
# =============================================================================
# Homelab K8s - Full Deploy Script
# Order: OpenTofu → Pre-flight Ansible → Kubespray
# =============================================================================

set -euo pipefail

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

SKIP_TOFU=true
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
  log_step "Step 1/3 — OpenTofu: Provisioning VMs"

  cd "$PROJECT_ROOT/opentofu"
  log_info "Running: tofu init"
  tofu init -upgrade

  log_info "Running: tofu validate"
  tofu validate

  log_info "Running: tofu plan"
  tofu plan -out=tfplan

  log_info "Running: tofu apply"
  tofu apply tfplan

  log_success "VMs provisioned"

  # Wait for VMs to finish cloud-init
  log_info "Waiting 60s for cloud-init to complete on VMs..."
  sleep 90
else
  log_warn "Skipping OpenTofu (--skip-tofu)"
fi

# =============================================================================
# Step 2: Ansible Pre-flight
# =============================================================================
if ! $SKIP_PREFLIGHT; then
  log_step "Step 2/3 — Ansible: Pre-flight checks"

  source "$VENV/bin/activate"

  ansible-playbook \
    -i "$PROJECT_ROOT/kubespray-config/inventory/hosts.yml" \
    "$PROJECT_ROOT/ansible/preflight.yml" \
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
    --become \
    --become-user=root \
    -v

  deactivate
  log_success "Kubernetes cluster installed!"

  # =============================================================================
  # Fetch kubeconfig
  # =============================================================================
  log_step "Fetching kubeconfig from master"
  MASTER_IP="192.168.122.10"
  mkdir -p ~/.kube

  scp -i ~/.ssh/id_rsa \
      -o StrictHostKeyChecking=no \
      ubuntu@"$MASTER_IP":/home/ubuntu/.kube/config \
      ~/.kube/config-homelab 2>/dev/null || \
  scp -i ~/.ssh/id_rsa \
      -o StrictHostKeyChecking=no \
      ubuntu@"$MASTER_IP":/etc/kubernetes/admin.conf \
      ~/.kube/config-homelab

  export KUBECONFIG=~/.kube/config-homelab
  log_info "Testing cluster connectivity..."
  kubectl get nodes -o wide

  echo ""
  echo -e "${GREEN}=============================================================${NC}"
  echo -e "${GREEN}  🎉 Kubernetes cluster is ready!${NC}"
  echo -e "${GREEN}=============================================================${NC}"
  echo ""
  echo -e "  To use kubectl:"
  echo -e "  ${YELLOW}export KUBECONFIG=~/.kube/config-homelab${NC}"
  echo -e "  ${YELLOW}kubectl get nodes${NC}"
  echo ""
else
  log_warn "Skipping Kubespray (--skip-kubespray)"
fi
