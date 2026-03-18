output "vm_name" {
  description = "Nome da Instância Criada"
  value       = google_compute_instance.vm_instance.name
}

output "vm_static_ip" {
  description = "IP Externo Fixo Reservado"
  value       = google_compute_address.static_ip.address
}

output "vm_zone" {
  description = "Zona Alocada"
  value       = google_compute_instance.vm_instance.zone
}
