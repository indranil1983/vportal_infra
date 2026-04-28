V-Platform Infrastructure (vportal_infra)

An automated infrastructure-as-code (IaC) platform for deploying a multi-node Kubernetes cluster on Libvirt using OpenTofu (Terraform), Kubespray, and custom orchestration scripts.

## 🚀 Overview

This project provides an end-to-end automated pipeline to:
1.  **Cleanse** existing Libvirt/OpenTofu environments.
2.  **Configure** host-level virtualization settings (QEMU/Libvirtd).
3.  **Provision** Virtual Machines and Networking via OpenTofu.
4.  **Install** Kubernetes via Kubespray/Ansible.
5.  **Validate** the cluster with automated pod deployment tests.

## 📁 Project Structure

```text
.
├── main.tf                 # OpenTofu infrastructure definition
├── variables.tf            # Infrastructure variables
├── install_vplatform.sh    # Master Orchestrator
└── scripts/                # Modular logic
    ├── cleanstlate.sh      # Wipes VMs, Networks, and Tofu state
    ├── unsetup.sh          # Reverts host-level configurations
    ├── setup-host.sh       # Prepares QEMU and Libvirt
    ├── deploy.sh           # Main provisioning & Kubespray trigger
    ├── function_test.sh    # K8s "Hello World" verification
    ├── check-versions.sh   # Dependency validator
    └── install_opentofu.sh # Tooling installer
🛠 Installation
The master installer install_vplatform.sh handles the entire lifecycle. It must be run as root (sudo).

Full Installation (Default)
Runs all phases: Cleanslate → Unsetup → Setup-Host → Deploy → Test.

Bash
sudo ./install_vplatform.sh
Selective Phases (Arguments)
You can run specific parts of the pipeline using flags:

Flag	Description	Script Called
-c	Clean	cleanstlate.sh
-u	Unsetup	unsetup.sh
-s	Setup Host	setup-host.sh
-d	Deploy	deploy.sh
-t	Test	function_test.sh
Example: Refresh host settings and redeploy only:

Bash
sudo ./install_vplatform.sh -u -s -d
🔍 Validation
The function_test.sh script automatically:

Creates a test-ns namespace.

Deploys a busybox pod named hello-world.

Waits for the pod to execute and prints the logs.

Verifies cluster networking and container runtime health.

⏱ Performance Tracking
The master installer includes a built-in timer. At the end of execution, it reports the total time taken.

⚠️ Requirements
OS: Ubuntu/Debian

Virtualization: KVM/Libvirt

Tooling: OpenTofu, Ansible, Python3

Privileges: Sudo access required.

📄 License
MIT License