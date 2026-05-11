#!/bin/bash
# =============================================================================
# vplatform K8s - MetalLB & Contour Ingress Installation Script
# =============================================================================

set -euo pipefail

# --- Determine Paths & Load Config ---
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

# Ensure Helm is available
if ! command -v helm &> /dev/null; then
    log_error "Helm is not installed. Please run setup-host.sh first."
fi

# =============================================================================
# Step 1: Install MetalLB (Load Balancer Provider)
# =============================================================================
log_step "Installing MetalLB Load Balancer"

helm repo add metallb https://metallb.github.io/metallb
helm repo update

log_info "Deploying MetalLB via Helm (logs to $INSTALL_LOG_FILE)..."
helm upgrade --install metallb metallb/metallb \
    --namespace "$METALLB_NAMESPACE" \
    --create-namespace \
    --wait

METALLB_CONFIG_DIR="$PROJECT_ROOT/metallb"
METALLB_IP_CONFIG_FILE="$METALLB_CONFIG_DIR/metallb-ip-config.yaml"

mkdir -p "$METALLB_CONFIG_DIR"

log_info "Configuring MetalLB IP Pool ($METALLB_IP_RANGE) using $METALLB_IP_CONFIG_FILE..."
# Use envsubst to replace variables in the YAML file before applying
METALLB_IP_RANGE="$METALLB_IP_RANGE" METALLB_NAMESPACE="$METALLB_NAMESPACE" envsubst < "$METALLB_IP_CONFIG_FILE" | kubectl apply -f -


# =============================================================================
# Step 2: Install Contour Ingress Controller
# =============================================================================
log_step "Installing Contour Ingress Controller"

helm repo add contour https://projectcontour.github.io/helm-charts/
helm repo update

log_info "Deploying Contour via Helm (logs to $INSTALL_LOG_FILE)..."
helm upgrade --install "$CONTOUR_DEPLOY_LABEL" contour/contour \
    --namespace "$CONTOUR_NAMESPACE" \
    --create-namespace \
    --set envoy.service.type=LoadBalancer \
    --wait

log_info "Waiting for Contour Envoy service to get an external IP from MetalLB..."
ENVOY_EXTERNAL_IP=""
MAX_RETRIES=60 # Wait up to 5 minutes (60 * 5 seconds)
COUNT=0
while [ -z "$ENVOY_EXTERNAL_IP" ] && [ $COUNT -lt $MAX_RETRIES ]; do
    ENVOY_EXTERNAL_IP=$(kubectl get svc "$CONTOUR_ENVOY_SERVICE" -n "$CONTOUR_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -z "$ENVOY_EXTERNAL_IP" ]; then
        echo -ne "  Waiting for Envoy external IP... ($((COUNT + 1))/$MAX_RETRIES)\r"
        sleep 5
        COUNT=$((COUNT + 1))
    fi
done

if [ -z "$ENVOY_EXTERNAL_IP" ]; then
    log_error "Failed to get external IP for Contour Envoy service after multiple attempts. Check MetalLB and Contour logs."
else
    log_success "Contour Envoy service has external IP: $ENVOY_EXTERNAL_IP"
fi

log_success "MetalLB and Contour Ingress Controller are ready."
log_info "Envoy Service IP will be allocated from $METALLB_IP_RANGE"

CONTOUR_SUMMARY=$(cat <<EOF

Get Contour's load balancer IP/hostname:

     NOTE: It may take a few minutes for this to become available.

     You can watch the status by running:

         $ kubectl get svc $CONTOUR_ENVOY_SERVICE --namespace $CONTOUR_NAMESPACE -w

     Once 'EXTERNAL-IP' is no longer '<pending>':

         $ kubectl describe svc $CONTOUR_ENVOY_SERVICE --namespace $CONTOUR_NAMESPACE | grep Ingress | awk '{print \$3}'
EOF
)

echo "$CONTOUR_SUMMARY"
echo "$CONTOUR_SUMMARY" >> "$INSTALL_LOG_FILE"