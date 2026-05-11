#!/bin/bash
# =============================================================================
# vplatform K8s - Headlamp Deployment Script (Fixed)
# =============================================================================

set -euo pipefail

# --- Ensure variables are set (inherited from main script) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
source "$PROJECT_ROOT/config.src"

# Fail if run as root
if [[ "$EUID" -eq 0 ]]; then
  log_error "This script should NOT be run with sudo. Please run as a normal user."
fi

# Ensure Kubeconfig exists
if [ ! -f "$LOCAL_KUBECONFIG_PATH" ]; then
    log_error "Kubeconfig not found at $LOCAL_KUBECONFIG_PATH. Please deploy the cluster first."
fi

# Export KUBECONFIG for helm and kubectl
export KUBECONFIG="$LOCAL_KUBECONFIG_PATH"

# =============================================================================
# Persistence: Update .bashrc as the Real User
# =============================================================================
log_step "Updating $REAL_USER .bashrc for persistence"
BASHRC_FILE="$REAL_HOME/.bashrc"
EXPORT_LINE="export KUBECONFIG=$LOCAL_KUBECONFIG_PATH"

if ! grep -qF "$EXPORT_LINE" "$BASHRC_FILE"; then
    echo -e "\n# vplatform K8s Kubeconfig\n$EXPORT_LINE" >> "$BASHRC_FILE"
    log_success "Kubeconfig export added to $BASHRC_FILE"
else
    log_info "Kubeconfig export already exists in $BASHRC_FILE"
fi

# =============================================================================
# Headlamp Deployment & Ingress
# =============================================================================
log_step "Deploying Headlamp UI"

HEADLAMP_DIR="$PROJECT_ROOT/$HEADLAMP_NAMESPACE"
SERVICE_FILE="$HEADLAMP_DIR/service.yaml"
SERVICE_ADMIN_FILE="$HEADLAMP_DIR/service-admin.yaml"
DEPLOYMENT_FILE="$HEADLAMP_DIR/deployment.yaml"
INGRESS_FILE="$HEADLAMP_DIR/ingress.yaml"

if [ ! -f "$SERVICE_FILE" ]; then
    log_error "Headlamp service file not found at $SERVICE_FILE"
fi

# Ensure Helm is available (should be installed by setup-host.sh)
if ! command -v helm &> /dev/null; then
    log_error "Helm is not installed. Please run setup-host.sh first."
fi

log_info "Installing Headlamp chart..."
helm repo add "$HEADLAMP_NAMESPACE" https://kubernetes-sigs.github.io/headlamp/ --force-update
helm repo update
helm upgrade --install "$HEADLAMP_NAMESPACE" headlamp/headlamp \
    --namespace "$HEADLAMP_NAMESPACE" --create-namespace \
    -f "$DEPLOYMENT_FILE" -f "$SERVICE_FILE" \
    --wait

# =============================================================================
# Access Token Generation
# =============================================================================
log_info "Creating Headlamp access token..."

# Apply RBAC configuration and Ingress
kubectl apply -f "$INGRESS_FILE"
kubectl apply -f "$SERVICE_ADMIN_FILE"

TOKEN_FILE_PATH="$OUTPUT_DIR/$HEADLAMP_NAMESPACE-output.txt"
TOKEN=$(kubectl create token "$HEADLAMP_NAMESPACE-admin" -n "$HEADLAMP_NAMESPACE" --duration=8760h)

# Fetch the external IP of the Contour Envoy service (should be available after install_contour_ingress.sh)
ENVOY_EXTERNAL_IP=$(kubectl get svc "$CONTOUR_ENVOY_SERVICE" -n "$CONTOUR_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$ENVOY_EXTERNAL_IP" ]; then
    log_error "Contour Envoy service external IP not found. Ensure install_contour_ingress.sh ran successfully and the Envoy service obtained an IP."
fi
log_info "Contour Envoy external IP: $ENVOY_EXTERNAL_IP"

# Update /etc/hosts with the Headlamp Ingress Hostname and Envoy's External IP
log_info "Checking if $HEADLAMP_INGRESS_HOSTNAME already exists in $HOSTS_FILE..."
if grep -qw "$HEADLAMP_INGRESS_HOSTNAME" "$HOSTS_FILE"; then
    log_info "$HEADLAMP_INGRESS_HOSTNAME already exists in $HOSTS_FILE"
else
    log_info "Adding $HEADLAMP_INGRESS_HOSTNAME to $HOSTS_FILE..."
    echo "$ENVOY_EXTERNAL_IP  $HEADLAMP_INGRESS_HOSTNAME" | sudo tee -a "$HOSTS_FILE" > /dev/null
    if [ $? -eq 0 ]; then
        log_success "Successfully added $HEADLAMP_INGRESS_HOSTNAME"
    else
        log_error "Failed to update $HOSTS_FILE"
    fi
fi

# Save detailed access information and the token to the specific output file
{
    echo "-------------------------------------------------------"
    echo "KUBERNETES HEADLAMP ACCESS DETAILS"
    echo "Generated on: $(date)"
    echo "-------------------------------------------------------"
    echo "Envoy External IP: $ENVOY_EXTERNAL_IP"
    echo "Ingress Host:      $HEADLAMP_INGRESS_HOSTNAME"
    echo ""
    echo "Access URL:        http://$HEADLAMP_INGRESS_HOSTNAME"
    echo "-------------------------------------------------------"
    echo "REQUIRED /etc/hosts ENTRY:"
    echo "$ENVOY_EXTERNAL_IP $HEADLAMP_INGRESS_HOSTNAME"
    echo "-------------------------------------------------------"
    echo "AUTH TOKEN:"
    echo "$TOKEN"
    echo "-------------------------------------------------------"
} > "$TOKEN_FILE_PATH"

HEADLAMP_SUMMARY_PLAIN=$(cat <<EOF

=============================================================
  Headlamp UI is ready!
  Generated on:   $(date)
=============================================================
  Headlamp URL:   http://$HEADLAMP_INGRESS_HOSTNAME
  Access Token:   $TOKEN_FILE_PATH
  Kubeconfig:     $LOCAL_KUBECONFIG_PATH
=============================================================
EOF
)

CLUSTER_INFO_FILE="$OUTPUT_DIR/cluster-info.txt"
echo "$HEADLAMP_SUMMARY_PLAIN" >> "$CLUSTER_INFO_FILE"

echo -e "\n${GREEN}=============================================================${NC}"
cat "$CLUSTER_INFO_FILE"

log_info "Access details and token have been captured in: $TOKEN_FILE_PATH"