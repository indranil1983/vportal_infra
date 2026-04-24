provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "ubuntu" {
  name   = "ubuntu.qcow2"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

resource "libvirt_domain" "vm" {
  count  = 3
  name   = "k8s-node-${count.index}"
  memory = 3072
  vcpu   = 2

  disk {
    volume_id = libvirt_volume.ubuntu.id
  }

  network_interface {
    network_name = "default"
  }

  cloudinit = libvirt_cloudinit_disk.common.id
}

resource "libvirt_cloudinit_disk" "common" {
  name      = "commoninit.iso"
  user_data = file("${path.module}/cloud_init.cfg")
}
