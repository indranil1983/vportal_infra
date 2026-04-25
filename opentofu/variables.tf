variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "pool_name" {
  description = "Libvirt storage pool name"
  type        = string
  default     = "homelab-pool"
}

variable "pool_path" {
  description = "Path on host for VM disk storage"
  type        = string
  default     = "/home/echindr/project/vportal_hdd"
}

variable "ubuntu_image_url" {
  description = "Ubuntu 24.04 LTS cloud image URL"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "vm_user" {
  description = "Default user created inside VMs"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key injected into VMs"
  type        = string
  default     = "/home/echindr/.ssh/id_rsa.pub"
}

variable "libvirt_network" {
  description = "Libvirt network name"
  type        = string
  default     = "default"
}

variable "gateway" {
  description = "Default gateway for VMs"
  type        = string
  default     = "192.168.122.1"
}

variable "dns_server" {
  description = "DNS server for VMs"
  type        = string
  default     = "8.8.8.8"
}

variable "vms" {
  description = "Map of VM definitions"
  type = map(object({
    vcpu      = number
    memory_mb = number
    disk_size = number
    ip        = string
    role      = string
  }))
  default = {
    "k8s-master" = {
      vcpu      = 1
      memory_mb = 3072
      disk_size = 21474836480   # 20GB in bytes
      ip        = "192.168.122.10"
      role      = "master"
    }
    "k8s-worker-1" = {
      vcpu      = 1
      memory_mb = 3072
      disk_size = 21474836480
      ip        = "192.168.122.11"
      role      = "worker"
    }
    "k8s-worker-2" = {
      vcpu      = 1
      memory_mb = 3072
      disk_size = 21474836480
      ip        = "192.168.122.12"
      role      = "worker"
    }
  }
}
