provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# IP estático - reutiliza existente OU cria novo
data "google_compute_address" "existing_ip" {
  count  = var.static_ip_name != "" ? 1 : 0
  name   = var.static_ip_name
  region = var.region
}

resource "google_compute_address" "new_ip" {
  count  = var.static_ip_name == "" ? 1 : 0
  name   = "${var.vm_name}-static-ip"
  region = var.region
  
  lifecycle {
    prevent_destroy = true
  }
}

# Criação do disco de boot A PARTIR DA SNAPSHOT
resource "google_compute_disk" "boot_disk_from_snapshot" {
  name     = "${var.vm_name}-boot"
  type     = var.boot_disk_type
  zone     = var.zone
  snapshot = var.snapshot_name
  
  # Size opcional: se 0, usa tamanho da snapshot; se > 0, expande disco
  size = var.boot_disk_size > 0 ? var.boot_disk_size : null
  
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # Calcula machine_type igual ao main.tf original
  is_standard = var.machine_ram == (var.machine_cpus * 4)
  custom_prefix = var.machine_model_base == "n1" ? "custom" : "${var.machine_model_base}-custom"
  machine_type = local.is_standard ? "${var.machine_model_base}-standard-${var.machine_cpus}" : "${local.custom_prefix}-${var.machine_cpus}-${var.machine_ram * 1024}"
  
  # IP a usar: existente se fornecido, senão o novo criado
  static_ip = var.static_ip_name != "" ? data.google_compute_address.existing_ip[0].address : google_compute_address.new_ip[0].address
}

# Criação da VM com o disco restaurado da snapshot
resource "google_compute_instance" "vm_restored" {
  name         = var.vm_name
  machine_type = local.machine_type
  zone         = var.zone

  enable_display = true
  tags = ["http-server", "https-server"]

  # Anexa o disco criado da snapshot como boot disk
  boot_disk {
    source      = google_compute_disk.boot_disk_from_snapshot.id
    auto_delete = false  # Protege o disco de ser deletado com a VM
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = local.static_ip
    }
  }

  metadata = {
    ssh-keys = var.ssh_key
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
    prevent_destroy = true
    create_before_destroy = true
  }
}
