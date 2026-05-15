#!/bin/bash
# =============================================================================
# vplatform K8s - Ingress Health Check
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/config.src"

log_step "Checking Ingress Connectivity"

# 0. Check Host IP Forwarding (Critical for MetalLB/Bridge routing)
log_info "Verifying Host IP Forwarding..."
if [[ $(cat /proc/sys/net/ipv4/ip_forward) -eq 1 ]]; then
    log_success "IP Forwarding is enabled."
else
    log_warn "IP Forwarding is DISABLED. This often causes 504 errors on host reboots."
fi

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
    ENVOY_IP=$(kubectl get svc -n "$CONTOUR_NAMESPACE" "$CONTOUR_ENVOY_SERVICE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$ENVOY_IP" ]]; then
        log_info "Checking ARP table for LoadBalancer IP $ENVOY_IP..."
        ARP_ENTRY=$(arp -n "$ENVOY_IP" | grep "$ENVOY_IP" || true)
        if echo "$ARP_ENTRY" | grep -q "..:..:..:..:..:.."; then
            MAC_ADDR=$(echo "$ARP_ENTRY" | awk '{print $3}')
            log_success "ARP entry for $ENVOY_IP is resolved to $MAC_ADDR."
        else
            log_warn "ARP entry for $ENVOY_IP is incomplete. MetalLB Speaker might be failing to announce."
        fi

        log_info "Verifying kube-proxy strictARP setting (Required for IPVS)..."
        # Search all data keys (config, config.conf, etc.) and handle case sensitivity/spacing
        STRICT_ARP_VAL=$(kubectl get configmap -n kube-system kube-proxy -o jsonpath='{.data.*}' | grep -oi "strictARP: [a-z]*" || echo "not found")
        if echo "$STRICT_ARP_VAL" | grep -qi "true"; then
            log_success "kube-proxy strictARP is enabled."
        else
            log_warn "kube-proxy strictARP is NOT enabled (Found: $STRICT_ARP_VAL). Consider running '$SCRIPT_DIR/fix-metallb-strict-arp.sh'."
        fi

        log_success "Envoy Ingress is alive at $ENVOY_IP"
        
        # Verify /etc/hosts
        if grep -q "$ENVOY_IP.*$HEADLAMP_INGRESS_HOSTNAME" /etc/hosts; then
            log_success "/etc/hosts is correctly mapped."
        else
            log_warn "/etc/hosts entry for $HEADLAMP_INGRESS_HOSTNAME might be missing or incorrect for IP $ENVOY_IP"
        fi

        # Direct Connectivity Test (Bypassing Nginx)
        log_info "Testing direct connection to Ingress..."
        CURL_OUT=$(curl -I -s --connect-timeout 3 -H "Host: $HEADLAMP_INGRESS_HOSTNAME" "http://$ENVOY_IP/" 2>&1 || true)
        if echo "$CURL_OUT" | grep -q "HTTP/1.1"; then
            log_success "Backend Ingress is responding."
        else
            log_warn "Backend Ingress is NOT responding. Error: $CURL_OUT"
        fi
    else
        log_error "Envoy Ingress has no External IP. MetalLB might not be running."
    fi

    log_info "Checking Headlamp Pod status..."
    kubectl get pods -n "$HEADLAMP_NAMESPACE"
fi