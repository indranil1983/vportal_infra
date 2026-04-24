#!/bin/bash
set -e
sudo virsh pool-define-as default dir - - - - "/var/lib/libvirt/images"
sudo virsh pool-build default
sudo virsh pool-start default
sudo virsh pool-autostart default
virsh pool-list --all
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
