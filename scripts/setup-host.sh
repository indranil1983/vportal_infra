#!/bin/bash
# =============================================================================
# Homelab K8s - Host Setup Script (Official Manual Repo Method)
# =============================================================================

set -euo pipefail

# --- Logging Functions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 0. Root check
if [[ "$EUID" -ne 0 ]]; then
  log_error "Please run as root: sudo bash setup-host.sh"
fi

# 1. Immediate APT Cleanup
log_info "Cleaning up old/broken repository files..."
rm -f /etc/apt/sources.list.d/opentofu.list
rm -f /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg
apt-get update -qq

# 2. Install Prerequisites
log_info "Installing base utilities..."
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release git jq wget sshpass

# 3. OpenTofu (Manual Repository Method from Docs)
log_info "Install OpenTofu..."

# Download the installer script:
wget --secure-protocol=TLSv1_2 --https-only https://get.opentofu.org/install-opentofu.sh -O install-opentofu.sh
# Alternatively: wget --secure-protocol=TLSv1_2 --https-only https://get.opentofu.org/install-opentofu.sh -O install-opentofu.sh

# Give it execution permissions:
chmod +x install-opentofu.sh

# Please inspect the downloaded script

# Run the installer:
./install-opentofu.sh --install-method deb

# Remove the installer:
rm -f install-opentofu.sh

log_success "OpenTofu installed: $(tofu --version | head -n1)"

# 4. KVM / libvirt
log_info "Installing Virtualization Stack..."
apt-get install -y -qq qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils cloud-image-utils
systemctl enable --now libvirtd

SUDO_USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "$SUDO_USER_NAME" ]]; then
  usermod -aG libvirt,kvm "$SUDO_USER_NAME"
fi

# 5. Python & Kubespray
log_info "Setting up Kubespray venv..."
apt-get install -y -qq python3-pip python3-venv python3-full
VENV_DIR="/opt/kubespray-venv"
KUBESPRAY_DIR="/opt/kubespray"

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip -q

if [[ ! -d "$KUBESPRAY_DIR" ]]; then
    git clone --depth=1 https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
fi

"$VENV_DIR/bin/pip" install -q -r "$KUBESPRAY_DIR/requirements.txt"
ln -sf "$VENV_DIR/bin/ansible" /usr/local/bin/ansible
ln -sf "$VENV_DIR/bin/ansible-playbook" /usr/local/bin/ansible-playbook

log_success "Setup complete! Please log out and back in."