#!/bin/bash

# --- Configuration ---
# You can find the latest version at https://github.com/opentofu/opentofu/releases
TOFU_VERSION="1.11.6"
ARCH=$(dpkg --print-architecture) # Detects amd64 or arm64 automatically
DEB_FILE="tofu_${TOFU_VERSION}_${ARCH}.deb"
DOWNLOAD_URL="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/${DEB_FILE}"

echo "--- Starting OpenTofu Installation (v${TOFU_VERSION}) ---"

# 1. Clean up old or broken installations
echo "[1/5] Removing potential broken installs..."
sudo apt remove -y tofu opentofu &>/dev/null || true

# 2. Download the .deb package
echo "[2/5] Downloading: $DOWNLOAD_URL"
curl -LO "$DOWNLOAD_URL"

# 3. Install the package
echo "[3/5] Installing package..."
sudo dpkg -i "$DEB_FILE" || sudo apt-get install -f -y

# 4. Critical: Fix the 'Command Not Found' issue
echo "[4/5] Refreshing shell environment..."
# Force shell to forget the "not found" memory of tofu
hash -r

# Ensure a symlink exists (some deb packages use 'opentofu' as the binary name)
if ! command -v tofu &> /dev/null && command -v opentofu &> /dev/null; then
    sudo ln -sf $(which opentofu) /usr/local/bin/tofu
    echo "Created symlink: tofu -> opentofu"
fi

# 5. Verification
echo "[5/5] Verifying installation..."
if command -v tofu &> /dev/null; then
    echo "------------------------------------------------"
    echo "SUCCESS: $(tofu --version | head -n 1) is ready!"
    echo "------------------------------------------------"
else
    echo "ERROR: Tofu still not found in PATH."
    echo "Try running: source ~/.bashrc && hash -r"
fi

# Cleanup
rm "$DEB_FILE"