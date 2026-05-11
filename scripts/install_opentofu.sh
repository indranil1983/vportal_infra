#!/bin/bash
# =============================================================================
# vplatform K8s - OpenTofu Installation Script
# =============================================================================

set -euo pipefail

# --- Determine Paths & Load Config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}" # Fallback if not set by calling script
source "$PROJECT_ROOT/config.src"

# # Fail if run as root
# if [[ "$EUID" -eq 0 ]]; then
#   log_error "This script should NOT be run with sudo. Please run as a normal user."
# fi

# Arguments
INSTALL_VERSION="${1:-$OPENTOFU_VERSION}" # Use argument if provided, else use config

# Installation parameters
TOFU_INSTALL_DIR="/usr/local/bin" # Standard binary path

# URLs
ZIP_FILE="tofu_${INSTALL_VERSION}_linux_amd64.zip"
DOWNLOAD_URL="https://github.com/opentofu/opentofu/releases/download/v${INSTALL_VERSION}/${ZIP_FILE}"
CHECKSUM_URL="https://github.com/opentofu/opentofu/releases/download/v${INSTALL_VERSION}/tofu_${INSTALL_VERSION}_SHA256SUMS"

TEMP_DIR=$(mktemp -d)

log_info "Installing OpenTofu v${INSTALL_VERSION}..."

# 1. Download OpenTofu binary
log_info "Downloading OpenTofu from ${DOWNLOAD_URL}"
wget -q -O "${TEMP_DIR}/${ZIP_FILE}" "$DOWNLOAD_URL" || log_error "Failed to download OpenTofu."

# 2. Download checksums
log_info "Downloading checksums from ${CHECKSUM_URL}"
wget -q -O "${TEMP_DIR}/tofu_SHA256SUMS" "$CHECKSUM_URL" || log_error "Failed to download OpenTofu checksums."

# 3. Verify checksum
log_info "Verifying checksum..."
if ! (cd "$TEMP_DIR" && grep "$ZIP_FILE" tofu_SHA256SUMS | sha256sum -c -); then
    log_error "Checksum verification failed for OpenTofu."
fi
log_success "Checksum verified."

# 4. Unzip and install
log_info "Unzipping OpenTofu..."
unzip -q "${TEMP_DIR}/${ZIP_FILE}" -d "$TEMP_DIR" || log_error "Failed to unzip OpenTofu."

log_info "Moving OpenTofu to ${TOFU_INSTALL_DIR}"
mv "${TEMP_DIR}/tofu" "$TOFU_INSTALL_DIR/tofu" || log_error "Failed to move OpenTofu binary."
chmod +x "$TOFU_INSTALL_DIR/tofu" || log_error "Failed to set execute permissions for OpenTofu."

# 5. Clean up
log_info "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

log_success "OpenTofu v${INSTALL_VERSION} installed successfully to $TOFU_INSTALL_DIR/tofu."