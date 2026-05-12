#!/bin/bash
# =============================================================================
# vplatform K8s - Ingress Health Check
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/config.src"

log_step "Checking Ingress Connectivity"

# 1. Check Host Nginx
log_info "Verifying Host Nginx status..."
systemctl is-active --quiet nginx && log_success "Nginx is running" || log_error "Nginx is stopped"

# 2. Check VM Network Reachability
log_info "Pinging Master VM ($MASTER_IP)..."
ping -c 1 -W 2 "$MASTER_IP" >/dev/null 2>&1 && log_success "Master is reachable" || log_warn "Master is unreachable"

# 3. Check Kubernetes Ingress Service
if [ -f "$LOCAL_KUBECONFIG_PATH" ]; then
    export KUBECONFIG="$LOCAL_KUBECONFIG_PATH"
    log_info "Fetching Envoy External IP..."
    ENVOY_IP=$(kubectl get svc -n "$CONTOUR_NAMESPACE" "$CONTOUR_ENVOY_SERVICE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "NONE")
    
    if [[ "$ENVOY_IP" != "NONE" ]]; then
        log_success "Envoy Ingress is alive at $ENVOY_IP"
    else
        log_warn "Envoy Ingress has no External IP yet."
    fi
fi