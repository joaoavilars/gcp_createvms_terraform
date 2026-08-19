output "vm_name" {
  value = google_compute_instance.vm_restored.name
}

output "vm_static_ip" {
  value = google_compute_instance.vm_restored.network_interface[0].access_config[0].nat_ip
}

output "static_ip_name" {
  value = var.static_ip_name != "" ? var.static_ip_name : google_compute_address.new_ip[0].name
}

output "vm_zone" {
  value = google_compute_instance.vm_restored.zone
}

output "boot_disk_from_snapshot" {
  value = google_compute_disk.boot_disk_from_snapshot.name
}
