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
sudo virsh pool-refresh "$POOL_NAME" && echo "  ✓ pool refreshed"

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

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "✅ Clean complete. Current libvirt state:"
echo ""
sudo virsh list --all
echo ""
sudo virsh vol-list --pool "$POOL_NAME"
echo ""
echo "👉 Ready to run: ./scripts/deploy.sh"
echo ""