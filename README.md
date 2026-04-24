# k8s-home-lab

Automated Kubernetes cluster using OpenTofu + Ansible + k3s

What to do next

Unzip it:
unzip k8s-home-lab.zip
cd k8s-home-lab
Add your SSH public key in:
tofu/cloud_init.cfg
Run:
chmod +x scripts/deploy.sh
./scripts/deploy.sh

⚠️ Before you run it

Make sure your host has:

KVM + libvirt installed and running
OpenTofu installed
Ansible installed
Your user added to libvirt group

👍 What you’ll get
3 VMs (KVM)
Auto-configured Kubernetes via k3s
Zero manual IP handling (dynamic inventory works out of the box)
