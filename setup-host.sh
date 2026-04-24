#!/bin/bash
set -e

echo "🔧 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "🖥 Installing KVM + libvirt..."
sudo apt install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virt-manager \
  cpu-checker

echo "✅ Checking virtualization support..."
kvm-ok || echo "⚠️ KVM may not be fully supported on this machine"

echo "🚀 Enabling and starting libvirt..."
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

echo "👤 Adding user to libvirt group..."
sudo usermod -aG libvirt $USER

echo "📦 Installing Ansible..."
sudo apt install -y ansible

echo "📦 Installing OpenTofu..."

# Add OpenTofu repo (official method)
if ! command -v tofu &> /dev/null; then
  echo "Adding OpenTofu repository..."
  sudo snap install --classic opentofu
else
  echo "OpenTofu already installed"
fi

echo "🔍 Verifying installations..."

echo -n "KVM: "
lsmod | grep kvm && echo "OK" || echo "NOT LOADED"

echo -n "libvirt: "
systemctl is-active libvirtd && echo "RUNNING" || echo "NOT RUNNING"

echo -n "Ansible: "
ansible --version | head -n 1

echo -n "OpenTofu: "
tofu version

echo ""
echo "⚠️ IMPORTANT: You must log out and log back in for libvirt group changes to apply!"
echo "Then test with:"
echo "  virsh list --all"

echo ""
echo "✅ Setup complete!"
