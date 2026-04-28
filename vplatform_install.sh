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

# Start the timer
START_TIME=$SECONDS

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

usage() {
    echo "Usage: sudo $0 [-c] [-u] [-s] [-d] [-t] [-h]"
    echo "  -c  Run cleanstlate.sh"
    echo "  -u  Run unsetup.sh"
    echo "  -s  Run setup-host.sh"
    echo "  -d  Run deploy.sh"
    echo "  -t  Run function_test.sh"
    echo "  -h  Show this help message"
    echo "  (No arguments runs all phases in order)"
    exit 1
}

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
  exit 1
fi

# 2. Permissions Check
chmod +x "$SCRIPTS_DIR"/*.sh

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
RUN_CLEAN=false
RUN_UNSETUP=false
RUN_SETUP=false
RUN_DEPLOY=false
RUN_TEST=false

while getopts "cusdth" opt; do
  case $opt in
    c) RUN_CLEAN=true ;;
    u) RUN_UNSETUP=true ;;
    s) RUN_SETUP=true ;;
    d) RUN_DEPLOY=true ;;
    t) RUN_TEST=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

# If no flags are passed, set all to true
if [ $OPTIND -eq 1 ]; then
    RUN_CLEAN=true
    RUN_UNSETUP=true
    RUN_SETUP=true
    RUN_DEPLOY=true
    RUN_TEST=true
fi

# =============================================================================
# ORDER OF OPERATIONS
# =============================================================================

# PHASE 1: CLEANSLATE
if [ "$RUN_CLEAN" = true ]; then
    log_phase "cleanstlate.sh"
    if [ -f "$SCRIPTS_DIR/cleanstlate.sh" ]; then
        bash "$SCRIPTS_DIR/cleanstlate.sh"
    else
        echo -e "${YELLOW}Warning: cleanstlate.sh not found.${NC}"
    fi
fi

# PHASE 2: UNSETUP
if [ "$RUN_UNSETUP" = true ]; then
    log_phase "unsetup.sh"
    if [ -f "$SCRIPTS_DIR/unsetup.sh" ]; then
        bash "$SCRIPTS_DIR/unsetup.sh"
    fi
fi

# PHASE 3: SETUP-HOST
if [ "$RUN_SETUP" = true ]; then
    log_phase "setup-host.sh"
    if [ -f "$SCRIPTS_DIR/setup-host.sh" ]; then
        bash "$SCRIPTS_DIR/setup-host.sh"
    fi
fi

# PHASE 4: DEPLOY
if [ "$RUN_DEPLOY" = true ]; then
    log_phase "deploy.sh"
    if [ -f "$SCRIPTS_DIR/deploy.sh" ]; then
        bash "$SCRIPTS_DIR/deploy.sh"
    fi
fi

# PHASE 5: FUNCTION TEST
if [ "$RUN_TEST" = true ]; then
    log_phase "function_test.sh"
    if [ -f "$SCRIPTS_DIR/function_test.sh" ]; then
        # Ensure config is readable by real user before test
        [ -f "$LOCAL_KUBECONFIG_PATH" ] && chown "$REAL_USER":"$REAL_USER" "$LOCAL_KUBECONFIG_PATH"
        sudo -u "$REAL_USER" bash "$SCRIPTS_DIR/function_test.sh"
    fi
fi

# =============================================================================
# TIME CALCULATION
# =============================================================================
ELAPSED_TIME=$(($SECONDS - $START_TIME))
MINUTES=$((ELAPSED_TIME / 60))
SECONDS_REMAINDER=$((ELAPSED_TIME % 60))

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}  TOTAL TIME TAKEN: ${MINUTES}m ${SECONDS_REMAINDER}s${NC}"
echo -e "${GREEN}================================================================${NC}\n"