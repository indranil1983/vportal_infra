output "vm_ips" {
  description = "IP addresses of provisioned VMs"
  value = {
    for name, vm in var.vms : name => vm.ip
  }
}

output "master_ip" {
  description = "Kubernetes master node IP"
  value = [
    for name, vm in var.vms : vm.ip if vm.role == "master"
  ][0]
}

output "worker_ips" {
  description = "Kubernetes worker node IPs"
  value = [
    for name, vm in var.vms : vm.ip if vm.role == "worker"
  ]
}

output "ssh_connect_commands" {
  description = "SSH commands to connect to each VM"
  value = {
    for name, vm in var.vms :
    name => "ssh -i ${var.ssh_key_path} ubuntu@${vm.ip}"
  }
}
