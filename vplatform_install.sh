#!/bin/bash
set -e

# =============================================================================
# GLOBAL ENVIRONMENT & PATHS
# =============================================================================
export REAL_USER=${SUDO_USER:-$USER}
export REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
export CURR_PWD_LOC=$(pwd)
export SCRIPTS_DIR="$CURR_PWD_LOC/scripts"

# Exporting shared variables for sub-scripts
export SSH_KEY_PATH="$REAL_HOME/.ssh/id_rsa"
export LOCAL_KUBECONFIG_PATH="$REAL_HOME/.kube/config-vplatform"

# UI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_phase() {
    echo -e "\n${CYAN}================================================================${NC}"
    echo -e "${CYAN}  EXECUTING: $1 ${NC}"
    echo -e "${CYAN}================================================================${NC}\n"
}

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
  exit 1
fi

# 2. Permissions Check
chmod +x "$SCRIPTS_DIR"/*.sh

# =============================================================================
# ORDER OF OPERATIONS
# =============================================================================

# PHASE 1: CLEANSLATE
# Responsibility: Destroy VMs, Networks, and clear Tofu state.
log_phase "cleanstlate.sh"
if [ -f "$SCRIPTS_DIR/cleanstlate.sh" ]; then
    bash "$SCRIPTS_DIR/cleanstlate.sh"
else
    echo -e "${YELLOW}Warning: cleanstlate.sh not found.${NC}"
fi

# PHASE 2: UNSETUP
# Responsibility: Revert host-level changes (firewalls, bridge cleanup).
log_phase "unsetup.sh"
if [ -f "$SCRIPTS_DIR/unsetup.sh" ]; then
    bash "$SCRIPTS_DIR/unsetup.sh"
fi

# PHASE 3: SETUP-HOST
# Responsibility: Apply QEMU configs, start libvirt, prepare system.
log_phase "setup-host.sh"
if [ -f "$SCRIPTS_DIR/setup-host.sh" ]; then
    bash "$SCRIPTS_DIR/setup-host.sh"
fi

# PHASE 4: DEPLOY
# Responsibility: Tofu apply, SSH waits, and triggering Ansible.
log_phase "deploy.sh"
if [ -f "$SCRIPTS_DIR/deploy.sh" ]; then
    bash "$SCRIPTS_DIR/deploy.sh"
fi

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}  INSTALLATION COMPLETE: V-PLATFORM IS LIVE ${NC}"
echo -e "${GREEN}================================================================${NC}\n"