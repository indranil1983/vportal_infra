#!/bin/bash
# =============================================================================
# vplatform K8s - Headlamp Deployment Script (Fixed)
# =============================================================================

set -euo pipefail

# --- Ensure variables are set (inherited from main script) ---
REAL_USER="${REAL_USER:-$(logname 2>/dev/null || echo $USER)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
LOCAL_KUBECONFIG_PATH="${LOCAL_KUBECONFIG_PATH:-$REAL_HOME/.kube/config-vplatform}"
OUTPUT_DIR="$PROJECT_ROOT/output"
# Configuration
IP_ADDR="127.0.0.1"
HOSTNAME="headlamp.local"
HOSTS_FILE="/etc/hosts"

echo -e "PROJECT_ROOT = $PROJECT_ROOT"

# UI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step()    { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# Persistence: Update .bashrc as the Real User
# =============================================================================
log_step "Updating $REAL_USER .bashrc for persistence"
BASHRC_FILE="$REAL_HOME/.bashrc"
EXPORT_LINE="export KUBECONFIG=$LOCAL_KUBECONFIG_PATH"

if ! grep -qF "$EXPORT_LINE" "$BASHRC_FILE"; then
    # Fix: Append as the user to avoid permission/lock issues
    sudo -u "$REAL_USER" bash -c "echo -e '\n# vplatform K8s Kubeconfig\n$EXPORT_LINE' >> '$BASHRC_FILE'"
    log_success "Kubeconfig export added to $BASHRC_FILE"
else
    log_info "Kubeconfig export already exists in $BASHRC_FILE"
fi

# =============================================================================
# Headlamp Deployment & Ingress
# =============================================================================
log_step "Step 4 — Headlamp: UI Deployment"

SERVICE_FILE="$PROJECT_ROOT/headlamp/service.yaml"
SERVICE_ADMIN_FILE="$PROJECT_ROOT/headlamp/service-admin.yaml"
DEPLOYMENT_FILE="$PROJECT_ROOT/headlamp/deployment.yaml"
INGRESS_FILE="$PROJECT_ROOT/headlamp/ingress.yaml"
# Fix: Corrected syntax for file check
if [ ! -f "$SERVICE_FILE" ]; then
    log_error "Ingress file not found at $SERVICE_FILE"
fi

# Ensure Helm is installed
if ! command -v helm &> /dev/null; then
    log_info "Installing Helm..."
    curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

log_info "Installing Headlamp chart..."
# Fix: Using sudo -u with explicitly passed variables to preserve environment
sudo -u "$REAL_USER" bash -c "export KUBECONFIG='$LOCAL_KUBECONFIG_PATH'; \
    helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ && \
    helm repo update && \
    helm upgrade --install headlamp headlamp/headlamp \
    --namespace headlamp --create-namespace -f $DEPLOYMENT_FILE -f $SERVICE_FILE"


# =============================================================================
# Access Token Generation
# =============================================================================
log_info "Creating Headlamp access token..."
mkdir -p "$OUTPUT_DIR"


# Apply RBAC configuration
sudo -u "$REAL_USER" bash -c "export KUBECONFIG='$LOCAL_KUBECONFIG_PATH'; kubectl apply -f '$INGRESS_FILE'"

# Apply RBAC configuration
sudo -u "$REAL_USER" bash -c "export KUBECONFIG='$LOCAL_KUBECONFIG_PATH'; kubectl apply -f '$SERVICE_ADMIN_FILE'"

# Define the file path locally first
TOKEN_FILE_PATH="$OUTPUT_DIR/headlamp-token.txt"

# Fix: Use the local variable to redirect output OUTSIDE the sudo string
sudo -u "$REAL_USER" bash -c "export KUBECONFIG='$LOCAL_KUBECONFIG_PATH'; \
    kubectl create token headlamp-admin -n headlamp --duration=24h" > "$TOKEN_FILE_PATH"

if [ ! -s "$TOKEN_FILE_PATH" ]; then
    log_error "Failed to generate access token."
fi

# Ensure ownership is correct
chown "$REAL_USER":"$REAL_USER" "$TOKEN_FILE_PATH"

chown "$REAL_USER":"$REAL_USER" "$TOKEN_FILE_PATH"



# 1. Check if the hostname already exists in /etc/hosts
# -q: quiet mode (no output)
# -w: match the whole word (prevents matching "myheadlamp.local")

# if grep -qw "$HOSTNAME" "$HOSTS_FILE"; then
#     echo -e "[INFO]  $HOSTNAME already exists in $HOSTS_FILE"
# else
#     echo -e "[INFO]  Adding $HOSTNAME to $HOSTS_FILE..."
    
#     # 2. Append the entry
#     # Using 'printf' to ensure a newline is handled correctly
#     echo "$IP_ADDR  $HOSTNAME" | sudo tee -a "$HOSTS_FILE" > /dev/null
    
#     if [ $? -eq 0 ]; then
#         echo -e "[OK]    Successfully added $HOSTNAME"
#     else
#         echo -e "[ERROR] Failed to update $HOSTS_FILE"
#         exit 1
#     fi
# fi

# =============================================================================
# Final Summary
# =============================================================================
echo ""
echo -e "${GREEN}=============================================================${NC}"
echo -e "${GREEN}  🎉 Kubernetes & Headlamp are ready!${NC}"
echo -e "${GREEN}=============================================================${NC}"
echo -e "  Headlamp URL:   ${YELLOW}http://localhost:8081${NC}"
echo -e "  Access Token:   ${YELLOW}$TOKEN_FILE_PATH${NC}"
echo -e "  Kubeconfig:     ${YELLOW}$LOCAL_KUBECONFIG_PATH${NC}"
echo -e "${GREEN}=============================================================${NC}"