#!/bin/bash
# =============================================================================
# vplatform K8s - Environment Startup Script
# Restores network and VM states after a host reboot
# =============================================================================

set -euo pipefail

# --- Determine Paths & Load Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
source "$PROJECT_ROOT/config.src"

# Fail if run as root
if [[ "$EUID" -eq 0 ]]; then
  log_error "This script should NOT be run with sudo. Please run as a normal user."
fi

log_step "Waking up vplatform Infrastructure"

# 1. Ensure the libvirt network is active
if [[ $(virsh net-info "$NETWORK_NAME" | grep "Active" | awk '{print $2}') == "no" ]]; then
    log_info "Starting network: $NETWORK_NAME"
    virsh net-start "$NETWORK_NAME"
else
    log_info "Network $NETWORK_NAME is already active."
fi

# 2. Start the VMs defined in config.src
for vm in "${VMS[@]}"; do
    log_info "Ensuring VM $vm is running..."
    virsh start "$vm" 2>/dev/null || log_info "VM $vm is already started or busy."
done

log_success "Environment startup commands sent. Kubernetes will be ready once internal services initialize."