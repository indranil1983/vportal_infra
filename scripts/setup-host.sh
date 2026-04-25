#!/bin/bash
# =============================================================================
# Homelab K8s - Host Setup Script
# Ubuntu 24.04 LTS
# Installs: KVM/libvirt, OpenTofu, Ansible, Kubespray dependencies
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

OPENTOFU_VERSION="1.7.1"
PYTHON_MIN="3.10"

# =============================================================================
# 0. Root check
# =============================================================================
if [[ "$EUID" -ne 0 ]]; then
  log_error "Please run as root: sudo bash setup-host.sh"
fi

# =============================================================================
# 1. System update
# =============================================================================
log_info "Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq
log_success "System updated"

# =============================================================================
# 2. KVM / libvirt
# =============================================================================
log_info "Installing KVM and libvirt..."
apt-get install -y -qq \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  virt-manager \
  bridge-utils \
  cpu-checker \
  genisoimage \
  cloud-image-utils

systemctl enable --now libvirtd

# Add current sudo user to libvirt + kvm groups
SUDO_USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "$SUDO_USER_NAME" ]]; then
  usermod -aG libvirt,kvm "$SUDO_USER_NAME"
  log_success "Added $SUDO_USER_NAME to libvirt and kvm groups"
fi

# Verify KVM
if kvm-ok &>/dev/null; then
  log_success "KVM acceleration available"
else
  log_warn "KVM acceleration not available — VMs will run without hardware acceleration"
fi

# =============================================================================
# 3. OpenTofu
# =============================================================================
log_info "Installing OpenTofu ${OPENTOFU_VERSION}..."

curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
chmod +x /tmp/install-opentofu.sh
/tmp/install-opentofu.sh --install-method deb
rm -f /tmp/install-opentofu.sh

INSTALLED_TOFU=$(tofu version | head -1)
log_success "OpenTofu installed: ${INSTALLED_TOFU}"

# =============================================================================
# 4. Python 3 + pip + venv
# =============================================================================
log_info "Installing Python 3 and pip..."
apt-get install -y -qq \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  libffi-dev \
  libssl-dev \
  build-essential

log_success "Python $(python3 --version) installed"

# =============================================================================
# 5. Ansible + Kubespray dependencies (isolated venv)
# =============================================================================
VENV_DIR="/opt/kubespray-venv"
log_info "Creating Python venv at ${VENV_DIR}..."
python3 -m venv "$VENV_DIR"

log_info "Installing Ansible and Kubespray Python requirements..."
"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install -q \
  ansible \
  ansible-core \
  jinja2 \
  netaddr \
  pbr \
  jmespath \
  ruamel.yaml \
  cryptography \
  cffi \
  paramiko

log_success "Ansible $("$VENV_DIR/bin/ansible" --version | head -1) installed in venv"

# Symlink ansible into /usr/local/bin for convenience
ln -sf "$VENV_DIR/bin/ansible"         /usr/local/bin/ansible
ln -sf "$VENV_DIR/bin/ansible-playbook" /usr/local/bin/ansible-playbook
ln -sf "$VENV_DIR/bin/ansible-inventory" /usr/local/bin/ansible-inventory

# =============================================================================
# 6. Additional tools
# =============================================================================
log_info "Installing additional tools (git, jq, curl, sshpass, kubectl)..."
apt-get install -y -qq git jq curl wget sshpass netcat-openbsd

# kubectl (matching latest stable)
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl
log_success "kubectl ${KUBECTL_VERSION} installed"

# =============================================================================
# 7. SSH key (for Ansible → VM communication)
# =============================================================================
SSH_KEY_PATH="/root/.ssh/homelab_k8s"
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  log_info "Generating SSH keypair at ${SSH_KEY_PATH}..."
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "homelab-k8s"
  log_success "SSH keypair generated"
else
  log_warn "SSH keypair already exists at ${SSH_KEY_PATH}, skipping"
fi

# Copy to sudo user's home if available
if [[ -n "$SUDO_USER_NAME" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6)
  mkdir -p "$USER_HOME/.ssh"
  cp "${SSH_KEY_PATH}" "$USER_HOME/.ssh/homelab_k8s"
  cp "${SSH_KEY_PATH}.pub" "$USER_HOME/.ssh/homelab_k8s.pub"
  chown -R "$SUDO_USER_NAME:$SUDO_USER_NAME" "$USER_HOME/.ssh"
  log_success "SSH key copied to $USER_HOME/.ssh/"
fi

# =============================================================================
# 8. Clone Kubespray
# =============================================================================
KUBESPRAY_DIR="/opt/kubespray"
if [[ ! -d "$KUBESPRAY_DIR" ]]; then
  log_info "Cloning Kubespray..."
  git clone --depth=1 https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
  "$VENV_DIR/bin/pip" install -q -r "$KUBESPRAY_DIR/requirements.txt"
  log_success "Kubespray cloned to ${KUBESPRAY_DIR}"
else
  log_warn "Kubespray already exists at ${KUBESPRAY_DIR}, skipping clone"
fi

# =============================================================================
# 9. libvirt network — ensure default network is active
# =============================================================================
log_info "Ensuring libvirt default NAT network is active..."
if ! virsh net-info default &>/dev/null; then
  virsh net-define /usr/share/libvirt/networks/default.xml
fi
virsh net-autostart default
virsh net-start default 2>/dev/null || true
log_success "libvirt default network active"

# =============================================================================
# 10. Summary
# =============================================================================
echo ""
echo -e "${GREEN}=============================================================${NC}"
echo -e "${GREEN}  Host setup complete!${NC}"
echo -e "${GREEN}=============================================================${NC}"
echo ""
echo -e "  KVM/libvirt : $(virsh version --daemon 2>/dev/null | grep 'Running' | awk '{print $NF}')"
echo -e "  OpenTofu    : $(tofu version | head -1 | awk '{print $2}')"
echo -e "  Ansible     : $("$VENV_DIR/bin/ansible" --version | head -1 | awk '{print $NF}' | tr -d ']')"
echo -e "  kubectl     : $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
echo -e "  Kubespray   : ${KUBESPRAY_DIR}"
echo -e "  SSH Key     : ${SSH_KEY_PATH}.pub"
echo -e "  Venv        : ${VENV_DIR}"
echo ""
echo -e "${YELLOW}  IMPORTANT: Log out and back in for group membership to take effect${NC}"
echo -e "${YELLOW}  Then run: cd homelab-k8s && tofu init && tofu apply${NC}"
echo ""
