#!/bin/bash
# =============================================================================
# vplatform K8s - Environment Stop Script
# Gracefully shuts down VMs using ACPI signals
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

log_step "Stopping vplatform Infrastructure"

# 1. Iterate through the VMs defined in config.src and send shutdown signal
for vm in "${VMS[@]}"; do
    if virsh domstate "$vm" | grep -q "running"; then
        log_info "Sending graceful shutdown signal to $vm..."
        virsh shutdown "$vm" > /dev/null
    else
        log_info "VM $vm is already stopped or in an inactive state."
    fi
done

log_success "Shutdown signals sent to all nodes. The cluster will power off shortly."
log_info "Note: To check status, use: virsh list --all"