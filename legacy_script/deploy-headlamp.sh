#!/bin/bash
# =============================================================================
# vplatform K8s - Headlamp Deployment Script (Fixed)
# =============================================================================

set -euo pipefail

# --- Ensure variables are set (inherited from main script) ---
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo $USER)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
LOCAL_KUBECONFIG_PATH="${LOCAL_KUBECONFIG_PATH:-$REAL_HOME/.kube/config-vplatform}"
OUTPUT_DIR="$PROJECT_ROOT/output"
NGINX_NAMESPACE="ingress-nginx"
HEADLAMP_NS="headlamp"
HEADLAMP_INGRESS_NAME=$HEADLAMP_NS
# Configuration
HOSTS_FILE="/etc/hosts"
MASTER_IP="master" 

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

SERVICE_FILE="$PROJECT_ROOT/$HEADLAMP_NS/service.yaml"
SERVICE_ADMIN_FILE="$PROJECT_ROOT/$HEADLAMP_NS/service-admin.yaml"
DEPLOYMENT_FILE="$PROJECT_ROOT/$HEADLAMP_NS/deployment.yaml"
INGRESS_FILE="$PROJECT_ROOT/$HEADLAMP_NS/ingress.yaml"
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
    helm repo add $HEADLAMP_NS https://kubernetes-sigs.github.io/headlamp/ && \
    helm repo update && \
    helm upgrade --install $HEADLAMP_NS headlamp/headlamp \
    --namespace $HEADLAMP_NS --create-namespace -f $DEPLOYMENT_FILE -f $SERVICE_FILE"


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
TOKEN_FILE_PATH="$OUTPUT_DIR/$HEADLAMP_NS-output.txt"

# Fix: Use the local variable to redirect output OUTSIDE the sudo string
TOKEN=$(sudo -u "$REAL_USER" bash -c "export KUBECONFIG='$LOCAL_KUBECONFIG_PATH'; kubectl create token $HEADLAMP_NS-admin -n $HEADLAMP_NS --duration=8760h")


# 1. Capture the NGINX NodePorts (HTTP and HTTPS)
echo -e "config is $LOCAL_KUBECONFIG_PATH"
export KUBECONFIG="$LOCAL_KUBECONFIG_PATH"

INGRESS_HOST=$(kubectl get ingress $HEADLAMP_NS -n $HEADLAMP_NS -o jsonpath='{.spec.rules[0].host}')
HOSTNAME=$INGRESS_HOST
echo $INGRESS_HOST
##1. Check if the hostname already exists in /etc/hosts##

if grep -qw "$HOSTNAME" "$HOSTS_FILE"; then
    echo -e "[INFO]  $HOSTNAME already exists in $HOSTS_FILE"
else
    echo -e "[INFO]  Adding $HOSTNAME to $HOSTS_FILE..."
    
    # 2. Append the entry
    # Using 'printf' to ensure a newline is handled correctly
    echo "$MASTER_IP  $HOSTNAME" | sudo tee -a "$HOSTS_FILE" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "[OK]    Successfully added $HOSTNAME"
    else
        echo -e "[ERROR] Failed to update $HOSTS_FILE"
        exit 1
    fi
fi


HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n $NGINX_NAMESPACE   -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
HTTPS_PORT=$(kubectl get svc ingress-nginx-controller -n $NGINX_NAMESPACE   -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')

# 2. Capture the Internal IP of the cluster node
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 3. Capture the Ingress Hostname from your configuration
INGRESS_HOST=$(kubectl get ingress $HEADLAMP_INGRESS_NAME -n $HEADLAMP_NS -o jsonpath='{.spec.rules[0].host}')

# 5. Echo all data into the text file
{
    echo "-------------------------------------------------------"
    echo "KUBERNETES HEADLAMP ACCESS DETAILS"
    echo "Generated on: $(date)"
    echo "-------------------------------------------------------"
    echo "VM Master IP:    $NODE_IP"
    echo "Ingress Host:   $INGRESS_HOST"
    echo ""
    echo "HTTP URL:      http://$INGRESS_HOST:$HTTP_PORT"
    echo "HTTPS URL:     https://$INGRESS_HOST:$HTTPS_PORT"
    echo "-------------------------------------------------------"
    echo "REQUIRED /etc/hosts ENTRY:"
    echo "$NODE_IP $INGRESS_HOST"
    echo "-------------------------------------------------------"
    echo "AUTH TOKEN:"
    echo "$TOKEN"
    echo "-------------------------------------------------------"
} >> "$TOKEN_FILE_PATH"

# Ensure ownership is correct
chown "$REAL_USER":"$REAL_USER" "$TOKEN_FILE_PATH"

echo "Access details and token have been captured in: $TOKEN_FILE_PATH"

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