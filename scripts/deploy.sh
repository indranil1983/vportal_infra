#!/bin/bash
set -e
POOL_NAME="default"

echo "🔍 Checking if libvirt pool '$POOL_NAME' exists..."
virsh list --all
##sudo virsh pool-delete "$POOL_NAME"
##sudo virsh pool-undefine "$POOL_NAME"

for vm in k8s-node-0 k8s-node-1 k8s-node-2; do
  sudo virsh destroy $vm 2>/dev/null || true
  sudo virsh undefine $vm 2>/dev/null || true
done

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

echo "Creating VMs..."
cd tofu
tofu init
sudo chmod -R 777 /var/lib/libvirt/images/ubuntu.qcow2
sudo chmod -R 777 /var/lib/libvirt/images
tofu apply -auto-approve

echo "Waiting for VMs..."
sleep 30

echo "Running Ansible..."
cd ../ansible
ansible-playbook playbook.yml

echo "Cluster ready!"
