#!/bin/bash
# clean-state.sh — Wipe all libvirt and tofu state for vportal_infra
# Run from the repo root: ./scripts/clean-state.sh

set -e
POOL_NAME="vplatform_pool"
IMAGES_DIR="$REAL_HOME"/virtual_machines/disks
TOFU_DIR="$(dirname "$0")/../tofu"
VMS=(k8s-master k8s-worker-1 k8s-worker-2)
VOLUMES=(ubuntu-base.qcow2 k8s-worker-2-root.qcow2 k8s-worker-1-root.qcow2 k8s-master-root.qcow2 k8s-master-cloudinit.iso k8s-worker-1-cloudinit.iso k8s-worker-2-cloudinit.iso)

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        vportal_infra clean-state         ║"
echo "╚══════════════════════════════════════════╝"
echo ""


# Add this near the top of scripts/cleanstlate.sh
log_step() { echo -e "\n\033[0;36m==== $1 ====\033[0m"; }
log_info() { echo -e "\033[1;33m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }


#=============================================================================
# 1. OpenTofu Infrastructure Cleanup
# =============================================================================
echo "Attempting to destroy OpenTofu managed VMs..."
# Try to run destroy if the directory exists
if command -v tofu &>/dev/null && [ -d "vplatform-k8s" ]; then
    cd $TOFU_DIR && tofu destroy -auto-approve || log_warn "Tofu destroy failed; perhaps resources were already gone."
    cd ..
fi


# ── 1. Destroy and undefine VMs ───────────────────────────────────────────────
echo "🔴 [1/5] Stopping and undefining VMs..."
for vm in "${VMS[@]}"; do
  if sudo virsh dominfo "$vm" &>/dev/null; then
    sudo virsh destroy "$vm" 2>/dev/null && echo "  ✓ destroyed $vm" || true
    sudo virsh undefine "$vm" 2>/dev/null && echo "  ✓ undefined $vm" || true
  else
    echo "  – $vm not found, skipping"
  fi
done

# ── 2. Delete libvirt volumes ─────────────────────────────────────────────────
echo ""
echo "🗑  [2/5] Deleting libvirt volumes from pool '$POOL_NAME'..."
for vol in "${VOLUMES[@]}"; do
  if sudo virsh vol-info "$vol" --pool "$POOL_NAME" &>/dev/null; then
    sudo virsh vol-delete "$vol" --pool "$POOL_NAME" && echo "  ✓ deleted volume $vol" || true
  else
    echo "  – volume $vol not in pool, skipping"
  fi
done

# ── 3. Remove raw image files (belt and braces) ───────────────────────────────
echo ""
echo "🧹 [3/5] Removing any leftover image files on disk..."
for vol in "${VOLUMES[@]}"; do
  FILE="$IMAGES_DIR/$vol"
  if [ -f "$FILE" ]; then
    sudo rm -f "$FILE" && echo "  ✓ removed $FILE"
  fi
done

# ── 4. Refresh pool ───────────────────────────────────────────────────────────
echo ""
echo "♻️  [4/5] Refreshing libvirt storage pool..."

if command -v virsh >/dev/null 2>&1; then
    if virsh pool-list --all --name | grep -q "^$POOL_NAME$"; then
        sudo virsh pool-refresh "$POOL_NAME" >/dev/null 2>&1
        echo "  ✓ pool $POOL_NAME refreshed"
    else
        echo "  ! pool $POOL_NAME not found, skipping refresh"
    fi
else
    echo "  ! virsh not available, skipping pool refresh"
fi

# ── 5. Wipe tofu state ────────────────────────────────────────────────────────
echo ""
echo "📄 [5/5] Wiping OpenTofu state files..."
for f in terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl; do
  FILE="$TOFU_DIR/$f"
  if [ -f "$FILE" ]; then
    rm -f "$FILE" && echo "  ✓ removed $FILE"
  fi
done

# ── 5. Wipe vm_nw ────────────────────────────────────────────────────────
NETWORK_NAME="vplatform_nw"

# 1. Stop the virtual network (Destroy the active instance)
if sudo virsh net-info "$NETWORK_NAME" &>/dev/null; then
    echo "[INFO] Stopping network: $NETWORK_NAME"
    sudo virsh net-destroy "$NETWORK_NAME" 2>/dev/null || echo "[WARN] Network already stopped."
    
    # 2. Remove the autostart flag
    echo "[INFO] Removing autostart for: $NETWORK_NAME"
    sudo virsh net-autostart --disable "$NETWORK_NAME"
    
    # 3. Undefine the network (Delete the XML definition)
    echo "[INFO] Undefining network: $NETWORK_NAME"
    sudo virsh net-undefine "$NETWORK_NAME"
    
    echo "[OK] Network '$NETWORK_NAME' has been completely removed."
else
    echo "[SKIP] Network '$NETWORK_NAME' does not exist."
fi

log_step "Cleaning up SSH known_hosts"

# Define your VM IPs
VM_IPS=("$MASTER_IP" "192.168.122.11" "192.168.122.12")

for IP in "${VM_IPS[@]}"; do
    log_info "Removing $IP from known_hosts..."

    # 1. Remove from the current user (Root, since you're running with sudo)
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true

    # 2. Remove from the Real User (the sudoer)
    # We use sudo -u to run the command as the specific user
    sudo -u "$REAL_USER" ssh-keygen -f "$REAL_HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true
done

log_success "Known hosts cleared for both root and $REAL_USER."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "✅ Clean complete. Current libvirt state:"
echo ""
if command -v virsh >/dev/null 2>&1; then
  sudo virsh list --all
  echo ""
  sudo virsh vol-list --pool "$POOL_NAME"
fi
echo ""
echo "👉 Ready to run: ./scripts/deploy.sh"
echo ""