provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------------------------
# Módulo de RECRIAÇÃO de VM (troca de SO mantendo IP externo reservado e IP
# interno fixo). Diferente do main.tf da raiz, este módulo NÃO cria um IP
# externo novo — ele reaproveita um endereço estático já reservado no GCP
# (passado via var.existing_static_ip), que deve continuar existindo e livre
# (desassociado da VM antiga) no momento do apply.
#
# Pré-requisito obrigatório antes do apply: a VM antiga já deve ter sido
# excluída (upgrade_vm.sh cuida disso), liberando o IP interno desejado.
# O disco antigo não é tocado por este módulo — ele é uma etapa manual
# (snapshot/preservação) feita pelo upgrade_vm.sh antes do apply.
# ------------------------------------------------------------------------------

resource "google_compute_instance" "vm_instance" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  enable_display = true

  tags = var.tags

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network
    network_ip = var.network_ip
    access_config {
      nat_ip = var.existing_static_ip
    }
  }

  metadata = {
    ssh-keys = var.ssh_key
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]

    # Mesma trava de segurança do módulo raiz: garante que o workspace ativo
    # é o mesmo declarado em workspace_name no terraform.tfvars.
    precondition {
      condition     = terraform.workspace == var.workspace_name
      error_message = "Workspace ativo ('${terraform.workspace}') difere de 'workspace_name' no terraform.tfvars ('${var.workspace_name}'). Rode 'terraform workspace select ${var.workspace_name}' (o upgrade_vm.sh faz isso automaticamente) antes de aplicar."
    }
  }
}
