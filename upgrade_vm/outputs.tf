output "vm_name" {
  description = "Nome da Instância Criada"
  value       = google_compute_instance.vm_instance.name
}

output "vm_external_ip" {
  description = "IP Externo (reaproveitado do endereço reservado existente)"
  value       = var.existing_static_ip
}

output "vm_internal_ip" {
  description = "IP Interno Fixo"
  value       = google_compute_instance.vm_instance.network_interface[0].network_ip
}

output "vm_zone" {
  description = "Zona Alocada"
  value       = google_compute_instance.vm_instance.zone
}
