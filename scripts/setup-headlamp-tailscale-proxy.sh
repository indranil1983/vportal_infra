#!/bin/bash
# =============================================================================
# vplatform K8s - Headlamp Tailscale Web Access Setup Script
# Configures Nginx on the host as a reverse proxy and enables Tailscale Web Access.
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

# Ensure Tailscale is installed and running
if ! command -v tailscale &> /dev/null; then
    log_error "Tailscale is not installed. Please install it on your host machine first."
fi

if ! tailscale status &> /dev/null; then
    log_error "Tailscale is not running or not connected. Please ensure it's up and authenticated."
fi

log_step "Setting up Headlamp access via Tailscale Web Access"

# 1. Install Nginx if not present
if ! command -v nginx &> /dev/null; then
    log_info "Nginx not found, installing Nginx..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq nginx
    log_success "Nginx installed."
else
    log_info "Nginx is already installed."
fi

# 2. Configure Nginx as a Reverse Proxy
NGINX_CONF_FILE="/etc/nginx/sites-available/headlamp-proxy.conf"
NGINX_SYMLINK_FILE="/etc/nginx/sites-enabled/headlamp-proxy.conf"

log_info "Creating Nginx reverse proxy configuration for Headlamp at $NGINX_CONF_FILE..."
sudo bash -c "cat > '$NGINX_CONF_FILE' <<EOF
server {
    listen $HEADLAMP_PROXY_PORT;
    server_name localhost; # Listen on localhost for Tailscale to pick up

    location / {
        proxy_pass http://$HEADLAMP_INGRESS_HOSTNAME;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # WebSocket support for Headlamp
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }
}
EOF"

if [ ! -L "$NGINX_SYMLINK_FILE" ]; then
    log_info "Enabling Nginx configuration..."
    sudo ln -s "$NGINX_CONF_FILE" "$NGINX_SYMLINK_FILE"
fi

log_info "Testing Nginx configuration and restarting Nginx..."
sudo nginx -t && sudo systemctl restart nginx
log_success "Nginx reverse proxy for Headlamp configured and running on port $HEADLAMP_PROXY_PORT."

# 3. Configure Tailscale Web Access
log_info "Enabling Tailscale Web Access for Headlamp on port $HEADLAMP_PROXY_PORT..."
sudo tailscale serve --bg "$HEADLAMP_PROXY_PORT"
log_success "Tailscale Web Access configured. You will need to approve this in the Tailscale admin console."

log_info "To approve, visit: https://login.tailscale.com/admin/machines"
log_info "Find your host machine, click 'Edit route settings', and enable the 'Web Access' route for port $HEADLAMP_PROXY_PORT."
log_info "Once approved, you can access Headlamp from any Tailscale client at: http://$(hostname -f):$HEADLAMP_PROXY_PORT (or your host's Tailscale IP:$HEADLAMP_PROXY_PORT)"
log_success "Headlamp Tailscale Web Access setup complete."