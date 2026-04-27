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

locals {
  # Instancias padrao geralmente possuem 4GB de RAM por vCPU
  is_standard = var.machine_ram == (var.machine_cpus * 4)

  # A familia n1 usa apenas o prefixo "custom", enquanto as outras usam "familia-custom"
  custom_prefix = var.machine_model_base == "n1" ? "custom" : "${var.machine_model_base}-custom"

  machine_type = local.is_standard ? "${var.machine_model_base}-standard-${var.machine_cpus}" : "${local.custom_prefix}-${var.machine_cpus}-${var.machine_ram * 1024}"
}

# Criação da VM
resource "google_compute_instance" "vm_instance" {
  name         = var.vm_name
  machine_type = local.machine_type
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

# Criação do Disco Extra (Condicional)
resource "google_compute_disk" "extra_disk" {
  count = var.create_extra_disk ? 1 : 0
  name  = "${var.vm_name}-extra-disk"
  type  = var.extra_disk_type
  size  = var.extra_disk_size
  zone  = var.zone
}

# Anexar o Disco Extra na VM (Condicional)
resource "google_compute_attached_disk" "attach_extra_disk" {
  count    = var.create_extra_disk ? 1 : 0
  disk     = google_compute_disk.extra_disk[0].id
  instance = google_compute_instance.vm_instance.id
}
