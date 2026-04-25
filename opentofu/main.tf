terraform {
  required_version = ">= 1.6.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# =============================================================================
# Storage pool  (v0.9: path lives inside target = { path = "..." })
# =============================================================================
resource "libvirt_pool" "homelab" {
  name = var.pool_name
  type = "dir"

  target = {
    path = var.pool_path
  }
}

# =============================================================================
# Base OS image  (v0.9: source URL goes in create.content.url)
# =============================================================================
resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-24.04-base.qcow2"
  pool = libvirt_pool.homelab.name

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.ubuntu_image_url
    }
  }
}

# =============================================================================
# Per-VM root disks  (v0.9: backing_store replaces base_volume_id)
# =============================================================================
resource "libvirt_volume" "vm_disk" {
  for_each = var.vms

  name     = "${each.key}-root.qcow2"
  pool     = libvirt_pool.homelab.name
  capacity = each.value.disk_size   # bytes

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

# =============================================================================
# cloud-init seed ISO  (v0.9: meta_data required; pool arg removed)
# =============================================================================
resource "libvirt_cloudinit_disk" "vm_init" {
  for_each = var.vms

  name = "${each.key}-init"

  meta_data = <<-EOF
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
    gateway    = var.gateway
    dns        = var.dns_server
  })
}

# =============================================================================
# cloud-init volume (v0.9: mount cloudinit ISO path as a volume)
# =============================================================================
resource "libvirt_volume" "vm_cloudinit" {
  for_each = var.vms

  name = "${each.key}-cloudinit.iso"
  pool = libvirt_pool.homelab.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.vm_init[each.key].path
    }
  }
}

# =============================================================================
# Virtual Machines  (v0.9 schema: attribute-style, type required)
# =============================================================================
resource "libvirt_domain" "vm" {
  for_each = var.vms

  name        = each.key
  type        = "kvm"
  vcpu        = each.value.vcpu
  memory      = each.value.memory_mb
  memory_unit = "MiB"

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_pool.homelab.name
            volume = libvirt_volume.vm_disk[each.key].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        source = {
          volume = {
            pool   = libvirt_pool.homelab.name
            volume = libvirt_volume.vm_cloudinit[each.key].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
        readonly = true
      }
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    # graphics = [
    #   {
    #     type = "none"
    #   }
    # ]

    interfaces = [
      {
        source = {
          network = {
            network = var.libvirt_network
          }
        }
        model = {
          type = "virtio"
        }
      }
    ]
  }

  provisioner "local-exec" {
    command = "echo 'VM ${each.key} provisioned (IP: ${each.value.ip})'"
  }
}