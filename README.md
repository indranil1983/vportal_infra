# Homelab Kubernetes — Automated Deployment

Automated 3-node Kubernetes homelab using **OpenTofu + KVM/libvirt + cloud-init + Ansible + Kubespray** on Ubuntu 24.04 LTS.

## Architecture

```
Host (Ubuntu 24.04 LTS)
└── KVM / libvirt
    ├── k8s-master   (2 vCPU, 3072 MB) — 192.168.122.10
    ├── k8s-worker-1 (2 vCPU, 3072 MB) — 192.168.122.11
    └── k8s-worker-2 (2 vCPU, 3072 MB) — 192.168.122.12
```

## Stack

| Layer        | Tool                    | Purpose                        |
|--------------|-------------------------|--------------------------------|
| Hypervisor   | KVM + libvirt           | Run VMs on Ubuntu host         |
| IaC          | OpenTofu                | Declare & provision VMs        |
| Bootstrap    | cloud-init              | First-boot VM configuration    |
| Config Mgmt  | Ansible                 | Pre-flight node validation     |
| K8s Install  | Kubespray               | Full upstream Kubernetes       |
| K8s Distro   | kubeadm (via Kubespray) | Standard upstream K8s v1.30    |
| CNI          | Calico                  | Pod networking                 |
| CRI          | containerd              | Container runtime              |

## Prerequisites

- Ubuntu 24.04 LTS host
- CPU with hardware virtualisation (Intel VT-x / AMD-V)
- Minimum 16 GB RAM on host (3× 3 GB VMs + host overhead)
- Minimum 80 GB free disk space
- Internet access

## Quick Start

### 1. Run host setup

```bash
sudo bash scripts/setup-host.sh
# Log out and back in after this step
```

### 2. Deploy everything

```bash
bash scripts/deploy.sh
```

### 3. Use the cluster

```bash
export KUBECONFIG=~/.kube/config-homelab
kubectl get nodes -o wide
```

## Project Structure

```
homelab-k8s/
├── opentofu/
│   ├── main.tf                        # VM resource definitions
│   ├── variables.tf                   # Configurable parameters
│   ├── outputs.tf                     # IP addresses, SSH commands
│   └── templates/
│       ├── cloud-init-user-data.tftpl # cloud-init user config
│       └── cloud-init-network.tftpl   # cloud-init static IP config
├── ansible/
│   └── preflight.yml                  # Node validation playbook
├── kubespray-config/
│   ├── inventory/
│   │   └── hosts.yml                  # Kubespray host inventory
│   └── group_vars/
│       └── k8s-cluster.yml            # Kubernetes configuration
└── scripts/
    ├── setup-host.sh                  # Install all host dependencies
    └── deploy.sh                      # Full deployment orchestrator
```

## Deploy Options

```bash
# Full deployment (default)
bash scripts/deploy.sh

# Skip VM provisioning (VMs already exist)
bash scripts/deploy.sh --skip-tofu

# Skip pre-flight checks
bash scripts/deploy.sh --skip-preflight

# Only provision VMs, skip K8s install
bash scripts/deploy.sh --skip-preflight --skip-kubespray

# Destroy all VMs
bash scripts/deploy.sh --destroy
```

## Customisation

Edit `opentofu/variables.tf` to change:
- VM resource allocation (vCPU, RAM, disk)
- IP addresses
- Storage pool path
- SSH key path

Edit `kubespray-config/group_vars/k8s-cluster.yml` to change:
- Kubernetes version
- CNI plugin (calico, flannel, cilium)
- Enable/disable Helm, ingress-nginx, metrics-server, dashboard
- Pod and service CIDRs

## Networking

VMs use **static IPs** on libvirt's default NAT network (`192.168.122.0/24`).
The host can reach VMs directly; VMs reach the internet via NAT.

| VM            | IP               | Role               |
|---------------|------------------|--------------------|
| k8s-master    | 192.168.122.10   | Control plane + etcd |
| k8s-worker-1  | 192.168.122.11   | Worker node        |
| k8s-worker-2  | 192.168.122.12   | Worker node        |

## SSH Access

```bash
ssh -i ~/.ssh/id_rsa ubuntu@192.168.122.10   # master
ssh -i ~/.ssh/id_rsa ubuntu@192.168.122.11   # worker-1
ssh -i ~/.ssh/id_rsa ubuntu@192.168.122.12   # worker-2
```
