#!/bin/bash
# =============================================================================
# Homelab K8s - Version Audit Script
# Checks installed software against the latest available upstream releases
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_version() {
    local name=$1
    local installed=$2
    local latest=$3
    
    echo -e "${BLUE}[$name]${NC}"
    echo -e "  Installed: $installed"
    echo -e "  Latest:    $latest"
    
    if [[ "$installed" == *"$latest"* ]]; then
        echo -e "  Status:    ${GREEN}Up to date${NC}"
    else
        echo -e "  Status:    ${YELLOW}Update available${NC}"
    fi
    echo ""
}

echo -e "${BLUE}--- Homelab Software Audit ---${NC}\n"

# 1. OpenTofu
if command -v tofu &> /dev/null; then
    INSTALLED_TOFU=$(tofu version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    LATEST_TOFU=$(curl -s https://api.github.com/repos/opentofu/opentofu/releases/latest | jq -r .tag_name | sed 's/^v//')
    check_version "OpenTofu" "$INSTALLED_TOFU" "$LATEST_TOFU"
else
    echo -e "${RED}[OpenTofu] Not installed${NC}\n"
fi

# 2. kubectl
if command -v kubectl &> /dev/null; then
    INSTALLED_K8S=$(kubectl version --client --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || kubectl version --client | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    LATEST_K8S=$(curl -L -s https://dl.k8s.io/release/stable.txt | sed 's/^v//')
    check_version "kubectl" "$INSTALLED_K8S" "$LATEST_K8S"
else
    echo -e "${RED}[kubectl] Not installed${NC}\n"
fi

# 3. Ansible (Inside Venv)
VENV_ANSIBLE="/opt/kubespray-venv/bin/ansible"
if [ -f "$VENV_ANSIBLE" ]; then
    INSTALLED_ANSIBLE=$($VENV_ANSIBLE --version | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    # Ansible versions vary, but we'll check against the latest 'ansible-core' on PyPI
    LATEST_ANSIBLE=$(curl -s https://pypi.org/pypi/ansible-core/json | jq -r .info.version)
    check_version "Ansible (Core)" "$INSTALLED_ANSIBLE" "$LATEST_ANSIBLE"
else
    echo -e "${RED}[Ansible] Venv not found at /opt/kubespray-venv${NC}\n"
fi

# 4. Libvirt / QEMU
if command -v virsh &> /dev/null; then
    INSTALLED_LIBVIRT=$(virsh version --daemon | grep "Using library" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    # For system packages, we check if apt thinks there's an upgrade
    UPGRADE_AVAILABLE=$(apt list --upgradable 2>/dev/null | grep libvirt-daemon-system || true)
    
    echo -e "${BLUE}[Libvirt Stack]${NC}"
    echo -e "  Installed: $INSTALLED_LIBVIRT"
    if [ -z "$UPGRADE_AVAILABLE" ]; then
        echo -e "  Status:    ${GREEN}Up to date (System)${NC}"
    else
        echo -e "  Status:    ${YELLOW}Update available via apt upgrade${NC}"
    fi
    echo ""
fi

# 5. Kubespray (Git Repo)
if [ -d "/opt/kubespray" ]; then
    echo -e "${BLUE}[Kubespray]${NC}"
    cd /opt/kubespray
    git fetch -q
    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse @{u})
    
    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        echo -e "  Status:    ${GREEN}Up to date (Master branch)${NC}"
    else
        echo -e "  Status:    ${YELLOW}Update available (git pull required)${NC}"
    fi
fi
