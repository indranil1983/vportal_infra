#!/bin/bash
# cleanSlate.sh — Wipe all libvirt and tofu state for vportal_infra
# =============================================================================

set -e

# --- Determine Paths & Load Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config.src"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Sourcing is required to load arrays (which cannot be exported to sub-shells)
source "$CONFIG_FILE"

# Fail if run as root
if [[ "$EUID" -eq 0 ]]; then
  log_error "This script should NOT be run with sudo. Please run as a normal user."
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        vportal_infra cleanSlate          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# 1. OpenTofu Infrastructure Cleanup
# =============================================================================
log_step "1/6 OpenTofu Infrastructure Cleanup"
if command -v tofu &>/dev/null && [ -d "$TOFU_ABS_DIR" ]; then
    log_info "Attempting to destroy OpenTofu managed VMs..."
    cd "$TOFU_ABS_DIR" && tofu destroy -auto-approve || log_warn "Tofu destroy failed; perhaps resources were already gone."
else
    log_info "OpenTofu directory or binary not found, skipping destroy."
fi

# =============================================================================
# 2. Destroy and undefine VMs (Direct Libvirt)
# =============================================================================
log_step "2/6 Stopping and undefining VMs"
for vm in "${VMS[@]}"; do
  if sudo virsh dominfo "$vm" &>/dev/null; then
    sudo virsh destroy "$vm" 2>/dev/null && echo "  ✓ destroyed $vm" || true
    sudo virsh undefine "$vm" 2>/dev/null && echo "  ✓ undefined $vm" || true
  else
    echo "  – $vm not found, skipping"
  fi
done

# =============================================================================
# 3. Delete libvirt volumes
# =============================================================================
log_step "3/6 Deleting libvirt volumes from pool '$POOL_NAME'"
for vol in "${VOLUMES[@]}"; do
  if sudo virsh vol-info "$vol" --pool "$POOL_NAME" &>/dev/null; then
    sudo virsh vol-delete "$vol" --pool "$POOL_NAME" && echo "  ✓ deleted volume $vol" || true
  else
    echo "  – volume $vol not in pool, skipping"
  fi
done

# =============================================================================
# 4. Remove image files on disk
# =============================================================================
log_step "4/6 Removing image files from $IMAGES_DIR"
for vol in "${VOLUMES[@]}"; do
  FILE="$IMAGES_DIR/$vol"
  if [ -f "$FILE" ]; then
    sudo rm -f "$FILE" && echo "  ✓ removed $FILE"
  fi
done

# =============================================================================
# 5. Wipe OpenTofu State
# =============================================================================
log_step "5/6 Wiping OpenTofu state files"
for f in terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl .terraform .opentofu .opentofu.lock.hcl tfplan; do
  TARGET="$TOFU_ABS_DIR/$f"
  if [ -e "$TARGET" ]; then
    rm -rf "$TARGET" && echo "  ✓ removed $TARGET"
  fi
done

# =============================================================================
# 6. Network and SSH Cleanup
# =============================================================================
log_step "6/6 Network and SSH Cleanup"
if sudo virsh net-info "$NETWORK_NAME" &>/dev/null; then
    log_info "Removing network: $NETWORK_NAME"
    sudo virsh net-destroy "$NETWORK_NAME" 2>/dev/null || true
    sudo virsh net-undefine "$NETWORK_NAME"
    log_success "Network '$NETWORK_NAME' removed"
fi

for IP in "${VM_IPS[@]}"; do
    log_info "Removing $IP from known_hosts..."
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true
done

log_success "Clean complete."