#!/bin/bash
# =============================================================================
# vplatform K8s - Host UNINSTALL Script
# Reverses all changes made by setup-host.sh
# =============================================================================

set -uo pipefail

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- User Configuration Variables ---
HOME_LOC="$REAL_HOME"
SSH_KEY_NAME="id_vportal_rsa"
USER_EMAIL="$REAL_USER@gmail.com"
MASTER_IP="192.168.122.10" 

SSH_KEY_PATH="$HOME_LOC/.ssh/$SSH_KEY_NAME"
LOCAL_KUBE_DIR="$HOME_LOC/.kube"
LOCAL_CONFIG="$LOCAL_KUBE_DIR/config-vplatform"

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
# --- Configuration ---
echo "--- Starting OpenTofu Deep Uninstall ---"

# 1. Uninstall via Package Managers
echo "[1/4] Removing packages via apt..."
sudo apt remove --purge -y tofu opentofu &>/dev/null || true
sudo apt autoremove -y &>/dev/null || true

# 2. Clean up Binaries and Symlinks
echo "[2/4] Searching for manual binaries and symlinks..."
# This targets common locations where manual installs or links might hide
FILES_TO_REMOVE=(
    "/usr/bin/tofu"
    "/usr/local/bin/tofu"
    "/usr/bin/opentofu"
    "/usr/local/bin/opentofu"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ] || [ -L "$file" ]; then
        echo "Removing: $file"
        sudo rm -f "$file"
    fi
done

# 3. Remove Local Configuration & Cache
echo "[3/4] Cleaning local data and plugins..."
# This removes provider caches (~/.terraform.d is used by Tofu for compatibility)
rm -rf "$HOME/.opentofu"
rm -rf "$HOME/.terraform.d"

# 4. Refresh Shell Environment
echo "[4/4] Finalizing shell state..."
# Force the shell to forget 'tofu' or 'opentofu' ever existed
hash -r

echo "------------------------------------------------"
echo "SUCCESS: OpenTofu has been fully removed."
echo "Check: Run 'which tofu' to verify (should be empty)."
echo "------------------------------------------------"

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
rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"

SUDO_USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "$SUDO_USER_NAME" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6)
  rm -f "$USER_HOME/.ssh/$SSH_KEY_NAME" "$USER_HOME/.ssh/$SSH_KEY_NAME.pub"
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