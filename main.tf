provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Criação do IP Externo Fixo
resource "google_compute_address" "static_ip" {
  name   = "${var.vm_name}-static-ip"
  region = var.region
}

# Criação da VM
resource "google_compute_instance" "vm_instance" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  # Dispositivo de exibição ativado
  enable_display = true

  # Firewall: Regras Padrões Iniciais (Global)
  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
    # Mantido o default behavior de Terraform para não associar resource_policies (sem política de backup)
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  metadata = {
    ssh-keys = var.ssh_key
  }

  # Conta de serviço segue a padrão (Compute Engine default service account), então o bloco 'service_account' é omitido

  # Ignorar alterações de chaves SSH para não recriar a máquina via pipeline inadvertidamente
  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
  }
}
