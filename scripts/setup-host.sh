#!/bin/bash
# =============================================================================
# vplatform K8s - Host Setup Script (Official Manual Repo Method)
# =============================================================================

set -euo pipefail

# Source global configuration (PROJECT_ROOT is already defined by config.src)
source "$PROJECT_ROOT/config.src"

# Fail if run as root
if [[ "$EUID" -eq 0 ]]; then
  log_error "This script should NOT be run with sudo. Please run as a normal user."
fi

log_info "Project Root: $PROJECT_ROOT"

mkdir -p "$PROJECT_ROOT/temp"


# 1. Immediate APT Cleanup
log_info "Cleaning up old/broken repository files..."
for file in "${APT_CLEANUP_FILES[@]}"; do
    sudo rm -f "$file"
done
sudo apt-get update -qq

# 2. Install Prerequisites
log_info "Installing base utilities..."
sudo apt-get install -y -qq "${SYSTEM_PACKAGES[@]}"

# 3. OpenTofu (Manual Repository Method from Docs)
log_info "Installing OpenTofu version $OPENTOFU_VERSION..."
sudo bash "$PROJECT_ROOT/scripts/install_opentofu.sh" "$OPENTOFU_VERSION"

log_success "OpenTofu installed: $(tofu --version | head -n1)"

# 4. KVM / libvirt
log_info "Installing Virtualization Stack..."
sudo apt-get install -y -qq "${VIRT_PACKAGES[@]}"
sudo systemctl enable --now libvirtd > /dev/null 2>&1

sudo usermod -aG libvirt,kvm "$REAL_USER"

# 5. Python & Kubespray
log_info "Setting up Kubespray venv..."
sudo apt-get install -y -qq python3-pip python3-venv python3-full # KUBESPRAY_VENV_DIR and KUBESPRAY_INSTALL_DIR are exported

sudo python3 -m venv "$KUBESPRAY_VENV_DIR"
sudo "$KUBESPRAY_VENV_DIR/bin/pip" install --upgrade pip -q

if [[ ! -d "$KUBESPRAY_INSTALL_DIR" ]]; then
    sudo git clone --depth=1 https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_INSTALL_DIR"
fi

sudo "$KUBESPRAY_VENV_DIR/bin/pip" install -q -r "$KUBESPRAY_INSTALL_DIR/requirements.txt"
sudo ln -sf "$KUBESPRAY_VENV_DIR/bin/ansible" /usr/local/bin/ansible
sudo ln -sf "$KUBESPRAY_VENV_DIR/bin/ansible-playbook" /usr/local/bin/ansible-playbook

# 6. Helm
log_info "Installing Helm..."
if ! command -v helm &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_success "Helm installed: $(helm version --short)"
else
    log_info "Helm is already installed: $(helm version --short)"
fi

############ update qemu conf access ################

log_info "Configuring QEMU Permissions (Prepending to top of file)"

QEMU_CONF="$LIBVIRT_QEMU_CONF"
TEMP_CONF=$(mktemp)

# Define the lines we want to ensure exist
read -r -d '' NEW_CONFIG << EOM || true
user = "root"
group = "root"
security_driver = "none"
EOM

# Check if the configuration already exists anywhere in the file
# We check for 'security_driver = "none"' as a unique indicator
if sudo grep -q "security_driver = \"none\"" "$QEMU_CONF"; then
    log_info "QEMU permissions already configured. Skipping."
else
    log_info "Prepending root permissions to $QEMU_CONF"
    
    # Create the new file: [New Config] + [Old File Content]
    echo "$NEW_CONFIG" > "$TEMP_CONF"
    sudo cat "$QEMU_CONF" >> "$TEMP_CONF"
    
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