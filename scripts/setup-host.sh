#!/bin/bash
# =============================================================================
# vplatform K8s - Host Setup Script (Official Manual Repo Method)
# =============================================================================

set -euo pipefail


CURR_PWD_LOC=$(pwd)

echo "Current work location is $CURR_PWD_LOC"

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

mkdir -p $CURR_PWD_LOC/temp

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

bash "$CURR_PWD_LOC"/scripts/install_opentofu.sh

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

############ update qemu conf access ################

log_step "Configuring QEMU Permissions (Prepending to top of file)"

QEMU_CONF="/etc/libvirt/qemu.conf"
TEMP_CONF=$(mktemp)

# Define the lines we want to ensure exist
read -r -d '' NEW_CONFIG << EOM || true
user = "root"
group = "root"
security_driver = "none"
EOM

# Check if the configuration already exists anywhere in the file
# We check for 'security_driver = "none"' as a unique indicator
if grep -q "security_driver = \"none\"" "$QEMU_CONF"; then
    log_info "QEMU permissions already configured. Skipping."
else
    log_info "Prepending root permissions to $QEMU_CONF"
    
    # Create the new file: [New Config] + [Old File Content]
    echo "$NEW_CONFIG" > "$TEMP_CONF"
    cat "$QEMU_CONF" >> "$TEMP_CONF"
    
    # Move temp file to actual config with correct permissions
    sudo cp "$TEMP_CONF" "$QEMU_CONF"
    sudo chmod 644 "$QEMU_CONF"
    
    log_info "Restarting libvirtd to apply changes..."
    sudo systemctl restart libvirtd
    log_success "QEMU is now running as root with security drivers disabled."
fi

rm -f "$TEMP_CONF"

##################################################################################

log_success "Setup complete! Please log out and back in."