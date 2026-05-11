#!/bin/bash
set -euo pipefail

# --- Load Config ---
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.src"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

usage() {
    echo "Usage: $0 [-c] [-u] [-d] [-i] [-l] [-t] [-h]"
    echo "  -c  Run cleanslate.sh"
    echo "  -u  Run unsetup.sh"
    echo "  -d  Run deploy.sh"
    echo "  -i  Run install_contour_ingress.sh"
    echo "  -l  Run deploy-headlamp.sh"
    echo "  -t  Run setup-headlamp-tailscale-proxy.sh"
    echo "  -h  Show this help message"
    exit 1
}

# --- Argument Parsing ---
RUN_CLEAN=false
RUN_UNSETUP=false
RUN_DEPLOY=false
RUN_CONTOUR=false
RUN_HEADLAMP=false
RUN_TAILSCALE_PROXY=false

while getopts "cudilh" opt; do
  case $opt in
    c) RUN_CLEAN=true ;;
    u) RUN_UNSETUP=true ;;
    d) RUN_DEPLOY=true ;;
    i) RUN_CONTOUR=true ;;
    l) RUN_HEADLAMP=true ;;
    t) RUN_TAILSCALE_PROXY=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

# If no arguments are provided, do nothing
if [ $OPTIND -eq 1 ]; then
    echo "No arguments provided. Nothing to run."
    usage
fi

# --- Execution Logic ---
if [ "$RUN_CLEAN" = true ]; then
    log_phase "cleanslate.sh"
    bash "$SCRIPTS_DIR/cleanslate.sh"
fi

if [ "$RUN_UNSETUP" = true ]; then
    log_phase "unsetup.sh"
    bash "$SCRIPTS_DIR/unsetup.sh"
fi

if [ "$RUN_DEPLOY" = true ]; then
    log_phase "deploy.sh"
    bash "$SCRIPTS_DIR/deploy.sh"
fi

if [ "$RUN_CONTOUR" = true ]; then
    log_phase "install_contour_ingress.sh"
    bash "$SCRIPTS_DIR/install_contour_ingress.sh"
fi

if [ "$RUN_HEADLAMP" = true ]; then
    log_phase "deploy-headlamp.sh"
    bash "$SCRIPTS_DIR/deploy-headlamp.sh"
fi

if [ "$RUN_TAILSCALE_PROXY" = true ]; then
    log_phase "setup-headlamp-tailscale-proxy.sh"
    bash "$SCRIPTS_DIR/setup-headlamp-tailscale-proxy.sh"
fi