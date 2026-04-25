#!/bin/bash
# =============================================================================
# Homelab K8s - Host UNINSTALL Script
# Reverses all changes made by setup-host.sh
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [[ "$EUID" -ne 0 ]]; then
  log_error "Please run as root: sudo bash uninstall-host.sh"
fi

# =============================================================================
# 1. OpenTofu Infrastructure Cleanup
# =============================================================================
log_info "Attempting to destroy OpenTofu managed VMs..."
# Try to run destroy if the directory exists
if command -v tofu &>/dev/null && [ -d "homelab-k8s" ]; then
    cd homelab-k8s && tofu destroy -auto-approve || log_warn "Tofu destroy failed; perhaps resources were already gone."
    cd ..
fi

# =============================================================================
# 2. Remove Kubespray & Ansible Venv
# =============================================================================
log_info "Removing Kubespray and Python Venv..."
rm -rf "/opt/kubespray"
rm -rf "/opt/kubespray-venv"
rm -f /usr/local/bin/ansible
rm -f /usr/local/bin/ansible-playbook
rm -f /usr/local/bin/ansible-inventory
log_success "Kubespray and Ansible removed"

# =============================================================================
# 3. Remove Tools (OpenTofu, kubectl, jq, etc.)
# =============================================================================
log_info "Removing binaries and tools..."
# OpenTofu
apt-get purge -y opentofu || rm -f $(which tofu)
rm -f /etc/apt/sources.list.d/opentofu.list
rm -f /etc/apt/keyrings/opentofu.gpg

# kubectl
rm -f /usr/local/bin/kubectl

# Support tools
apt-get remove --purge -y jq sshpass netcat-openbsd git
log_success "Tools uninstalled"

# =============================================================================
# 4. Remove KVM / libvirt
# =============================================================================
log_info "Removing KVM and libvirt stack..."
systemctl stop libvirtd 2>/dev/null || true
apt-get purge -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  virt-manager \
  bridge-utils \
  cpu-checker \
  genisoimage \
  cloud-image-utils

# Clean up leftover libvirt configs and networking
rm -rf /etc/libvirt/
rm -rf /var/lib/libvirt/
log_success "Virtualization stack removed"

# =============================================================================
# 5. SSH Key Cleanup
# =============================================================================
log_info "Removing generated SSH keys..."
rm -f "/root/.ssh/id_rsa" "/root/.ssh/id_rsa.pub"

SUDO_USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "$SUDO_USER_NAME" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6)
  rm -f "$USER_HOME/.ssh/id_rsa" "$USER_HOME/.ssh/id_rsa.pub"
  log_success "SSH keys removed from root and $SUDO_USER_NAME"
fi

# =============================================================================
# 6. Final System Cleanup
# =============================================================================
log_info "Finalizing cleanup..."
apt-get autoremove -y -qq
apt-get autoclean -qq

echo -e "${GREEN}=============================================================${NC}"
echo -e "${GREEN}  Uninstall Complete!${NC}"
echo -e "${GREEN}=============================================================${NC}"
echo -e "${YELLOW}Note: Python 3 and system build-essentials were kept to avoid${NC}"
echo -e "${YELLOW}breaking OS dependencies. You may reboot to clear network interfaces.${NC}"