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

export KUBECONFIG='$LOCAL_KUBECONFIG_PATH'
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
