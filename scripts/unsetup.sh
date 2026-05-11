#!/bin/bash
# =============================================================================
# vplatform K8s - Host UNINSTALL Script
# Reverses all changes made by setup-host.sh
# =============================================================================

set -uo pipefail

# --- Determine Paths & Load Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"

if [ ! -f "$PROJECT_ROOT/config.src" ]; then
    echo "Error: Configuration file not found at $PROJECT_ROOT/config.src"
    exit 1
fi

source "$PROJECT_ROOT/config.src"

# Fail if run as root
if [[ "$EUID" -eq 0 ]]; then
  log_error "This script should NOT be run with sudo. Please run as a normal user."
fi

# =============================================================================
# 1. Remove Kubespray & Ansible Venv
# =============================================================================
log_info "Removing Kubespray and Python Venv..."
sudo rm -rf "$KUBESPRAY_INSTALL_DIR"
sudo rm -rf "$KUBESPRAY_VENV_DIR"
sudo rm -f /usr/local/bin/ansible
sudo rm -f /usr/local/bin/ansible-playbook
sudo rm -f /usr/local/bin/ansible-inventory
log_success "Kubespray and Ansible removed"

# =============================================================================
# 2. Remove Tools (OpenTofu, kubectl, etc.)
# =============================================================================
log_info "Removing binaries and tools..."

# 2.1 OpenTofu
log_info "Deep uninstall of OpenTofu..."
sudo apt-get remove --purge -y tofu opentofu &>/dev/null || true
sudo apt-get autoremove -y &>/dev/null || true

for binary in "${TOFU_BINARIES[@]}"; do
    if [ -f "$binary" ] || [ -L "$binary" ]; then
        log_info "Removing: $binary"
        sudo rm -f "$binary"
    fi
done

# Clean local data and plugins for root and user
sudo rm -rf /root/.opentofu /root/.terraform.d
rm -rf "$REAL_HOME/.opentofu" "$REAL_HOME/.terraform.d"

# 2.2 kubectl
sudo rm -f /usr/local/bin/kubectl

# 2.3 Support tools
log_info "Removing support packages..."
for pkg in "${CLEANUP_PACKAGES[@]}"; do
    sudo apt-get remove --purge -y "$pkg" &>/dev/null || true
done

log_success "Tools uninstalled"

# =============================================================================
# 3. Remove KVM / libvirt
# =============================================================================
log_info "Removing KVM and libvirt stack..."
sudo systemctl stop libvirtd 2>/dev/null || true

for pkg in "${VIRT_PACKAGES[@]}"; do
    sudo apt-get purge -y "$pkg" &>/dev/null || true
done

# Clean up leftover libvirt configs and networking
sudo rm -rf "$LIBVIRT_CONF_DIR"
sudo rm -rf "$LIBVIRT_DATA_DIR"
log_success "Virtualization stack removed"

# =============================================================================
# 4. Cleanup SSH Keys & Config
# =============================================================================
log_info "Removing generated SSH keys and Kubeconfig..."
rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
rm -f "$LOCAL_KUBECONFIG_PATH"

# Also check root home just in case
sudo rm -f "/root/.ssh/$SSH_KEY_NAME" "/root/.ssh/$SSH_KEY_NAME.pub"

log_success "Identity files removed"

# =============================================================================
# 5. Final System Cleanup
# =============================================================================
log_info "Finalizing cleanup..."
hash -r
sudo apt-get autoremove -y -qq
sudo apt-get autoclean -qq

echo -e "${GREEN}=============================================================${NC}"
echo -e "${GREEN}  Uninstall Complete!${NC}"
echo -e "${GREEN}=============================================================${NC}"
log_warn "Python 3 and system build-essentials were kept to avoid OS issues."
log_info "You may reboot to clear network interfaces."