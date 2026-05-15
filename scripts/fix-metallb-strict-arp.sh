#!/bin/bash
# =============================================================================
# vplatform K8s - MetalLB Strict ARP Hotfix Script
# Enables strictARP in kube-proxy and restarts MetalLB speakers.
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

# Export KUBECONFIG for kubectl
export KUBECONFIG="$LOCAL_KUBECONFIG_PATH"

log_step "Applying MetalLB Strict ARP Hotfix"

# 1. Modify kube-proxy configuration to enable strictARP
log_info "Enabling strictARP in kube-proxy configmap..."
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -E 's/strictARP:[[:space:]]*false/strictARP: true/g' | \
kubectl apply -f - --force
log_success "kube-proxy configmap updated."

# 2. Restart kube-proxy pods to pick up the change
log_info "Restarting kube-proxy daemonset..."
kubectl rollout restart daemonset kube-proxy -n kube-system && kubectl rollout status daemonset kube-proxy -n kube-system
log_success "kube-proxy pods restarted."

# 3. Restart MetalLB speaker pods (to force re-announcement)
log_info "Restarting MetalLB speaker pods..."
kubectl delete pods -n "$METALLB_NAMESPACE" -l component=speaker || kubectl delete pods -n "$METALLB_NAMESPACE" -l app.kubernetes.io/name=metallb
log_success "MetalLB speaker pods restarted."

# 4. Flush Host ARP Cache for the LoadBalancer IP
ENVOY_IP=$(kubectl get svc -n "$CONTOUR_NAMESPACE" "$CONTOUR_ENVOY_SERVICE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$ENVOY_IP" ]]; then
    log_info "Flushing host ARP cache for $ENVOY_IP..."
    sudo ip neigh flush to "$ENVOY_IP"
    log_success "Host ARP cache flushed."
else
    log_warn "Could not determine Envoy IP to flush host ARP cache."
fi

log_success "MetalLB Strict ARP hotfix applied. Please re-run -check to verify connectivity."