terraform {
  required_version = ">= 1.6.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6" 
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# =============================================================================
# Storage pool
# =============================================================================
resource "libvirt_pool" "homelab" {
  name = var.pool_name
  type = "dir"
  # In 0.7.6, path is often preferred directly or inside a simplified target
  path = var.pool_path
}

# =============================================================================
# Base image
# =============================================================================
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-base.qcow2"
  pool   = libvirt_pool.homelab.name
  source = var.ubuntu_image_url
  format = "qcow2"
}

# =============================================================================
# VM root disks
# =============================================================================
resource "libvirt_volume" "vm_disk" {
  for_each = var.vms

  name   = "${each.key}-root.qcow2"
  pool   = libvirt_pool.homelab.name
  format = "qcow2"
  size   = each.value.disk_size

  base_volume_id = libvirt_volume.ubuntu_base.id
}

# =============================================================================
# Cloud-init disk
# =============================================================================
resource "libvirt_cloudinit_disk" "vm_init" {
  for_each = var.vms
  name     = "${each.key}-cloudinit.iso"
  pool     = libvirt_pool.homelab.name

  meta_data = <<EOF
instance-id: ${each.key}
local-hostname: ${each.key}
EOF

  user_data = templatefile("${path.module}/templates/cloud-init-user-data.tftpl", {
    hostname   = each.key
    ssh_pubkey = file(var.ssh_public_key_path)
    username   = var.vm_user
  })

  network_config = templatefile("${path.module}/templates/cloud-init-network.tftpl", {
    ip_address = each.value.ip
    gateway     = var.gateway
    dns         = var.dns_server
  })
}

# =============================================================================
# VM definition
# =============================================================================
resource "libvirt_domain" "vm" {
  for_each = var.vms

  name   = each.key
  memory = each.value.memory_mb
  vcpu   = each.value.vcpu

  cpu {
    mode = "host-passthrough"
  }

  # Ensure your libvirt/QEMU support q35; otherwise use "pc"
  machine = "pc"
  type    = "kvm"

  disk {
    volume_id = libvirt_volume.vm_disk[each.key].id
  }

  disk {
    # Use the file path instead of the ID to avoid metadata mismatches
    file = "${var.pool_path}/${each.key}-cloudinit.iso"
  }

  network_interface {
    network_name   = var.libvirt_network
    wait_for_lease = false
    
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}