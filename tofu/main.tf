terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
    }
  }
}
provider "libvirt" {
  uri = "qemu:///system"
}

# Base Ubuntu image (read-only)
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-base.qcow2"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

# Per-VM disks (IMPORTANT FIX)
resource "libvirt_volume" "disk" {
  count  = 3
  name   = "k8s-node-${count.index}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  format = "qcow2"
}

# Cloud-init
resource "libvirt_cloudinit_disk" "common" {
  name      = "cloudinit.iso"
  user_data = file("${path.module}/cloud_init.cfg")
}

# VMs
resource "libvirt_domain" "vm" {
  count  = 3
  name   = "k8s-node-${count.index}"
  memory = 3072
  vcpu   = 2

  disk {
    volume_id = libvirt_volume.disk[count.index].id
  }

  network_interface {
    network_name = "default"
  }

  cloudinit = libvirt_cloudinit_disk.common.id

 console {
  type        = "pty"
  target_type = "serial"
  target_port = 0
}
}
