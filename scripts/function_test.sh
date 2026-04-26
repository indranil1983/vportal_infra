#!/bin/bash
# =============================================================================
# K8s Deployment Test Script
# =============================================================================

set -euo pipefail

# --- Your Real Variables ---
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
LOCAL_KUBECONFIG_PATH="$REAL_HOME/.kube/config-vplatform"

# --- Formatting ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${CYAN}[TEST]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Pre-flight Check ---
if [ ! -f "$LOCAL_KUBECONFIG_PATH" ]; then
    error "Kubeconfig not found at $LOCAL_KUBECONFIG_PATH. Please run deploy.sh first."
fi

# =============================================================================
# Execution
# =============================================================================

log "Identifying session as: ${YELLOW}$REAL_USER${NC}"

# 1. Check current node status
log "Checking cluster connectivity..."
sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" get nodes

# 2. Create a test namespace
log "Ensuring namespace 'test-ns' exists..."
sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" create namespace test-ns \
    --dry-run=client -o yaml | sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" apply -f -

# 3. Deploy a sample Hello-World image
log "Deploying sample application (hello-kubernetes)..."
sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" apply -n test-ns -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: hello-kubernetes
        image: paulbouwer/hello-kubernetes:1.10
        ports:
        - containerPort: 8080
EOF

# 4. Wait for the Pod to be ready
log "Waiting for pod to be Ready (this may take a moment for image pull)..."
sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" wait --for=condition=Ready pod \
    -l app=hello-world \
    -n test-ns \
    --timeout=90s

# 3. Print the logs (The Hello World)
echo -e "\n${GREEN}==========================================${NC}"
echo -ne "${GREEN}  RESULT: ${NC}"
sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" -n test-ns  logs test-hello
echo -e "${GREEN}==========================================${NC}\n"

# 5. Verify and cleanup hint
echo -e "\n${GREEN}✅ TEST SUCCESSFUL${NC}"
log "Current Pods in test-ns:"
sudo -u "$REAL_USER" kubectl --kubeconfig="$LOCAL_KUBECONFIG_PATH" get pods -n test-ns

echo -e "\n${YELLOW}To cleanup, run:${NC}"

echo -e "\n${GREEN}✅ DELETING NAMESPACE${NC}"
sudo -u "$REAL_USER" kubectl --kubeconfig=$LOCAL_KUBECONFIG_PATH delete namespace test-ns