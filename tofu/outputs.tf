output "master_ip" {
  value = libvirt_domain.vm[0].network_interface[0].addresses[0]
}

output "worker_ips" {
  value = [
    for i in range(1, length(libvirt_domain.vm)) :
    libvirt_domain.vm[i].network_interface[0].addresses[0]
  ]
}

output "all_ips" {
  value = libvirt_domain.vm[*].network_interface[0].addresses[0]
}
