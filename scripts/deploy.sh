#!/bin/bash
set -e

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
