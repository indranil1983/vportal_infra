#!/bin/bash
set -e
POOL_NAME="default"

echo "🔍 Checking if libvirt pool '$POOL_NAME' exists..."

if virsh pool-info "$POOL_NAME" >/dev/null 2>&1; then
    echo "✅ Pool '$POOL_NAME' already exists. Skipping creation."
else
    echo "⚙️ Pool '$POOL_NAME' not found. Creating it..."

    sudo virsh pool-define-as "$POOL_NAME" dir - - - - "/var/lib/libvirt/images"
    sudo virsh pool-build "$POOL_NAME"
    sudo virsh pool-start "$POOL_NAME"
    sudo virsh pool-autostart "$POOL_NAME"

    echo "✅ Pool '$POOL_NAME' created and started."
fi
virsh list --all
sudo virsh pool-destroy default
sudo virsh pool-delete default
echo "Creating VMs..."
cd tofu
tofu init
tofu apply -auto-approve

echo "Waiting for VMs..."
sleep 30

echo "Running Ansible..."
cd ../ansible
ansible-playbook playbook.yml

echo "Cluster ready!"
