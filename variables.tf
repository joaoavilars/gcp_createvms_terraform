variable "project_id" {
  description = "Cód/ID do Projeto no Google Cloud"
  type        = string
}

variable "region" {
  description = "Região para a instância e IP"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona para a instância"
  type        = string
  default     = "us-central1-a"
}

variable "vm_name" {
  description = "Nome da VM"
  type        = string
}

variable "machine_type" {
  description = "Tipo de maquina, predefinição, CPUs, RAM (ex: e2-standard-4, n4-standard-4, ou custo: e2-custom-2-4096)"
  type        = string
}

variable "os_image" {
  description = "Imagem do Sistema Operacional (ex: debian-cloud/debian-12)"
  type        = string
}

variable "boot_disk_size" {
  description = "Tamanho do disco de inicialização em GB"
  type        = number
  default     = 50
}

variable "boot_disk_type" {
  description = "Tipo de disco (pd-balanced ou hyperdisk-balanced para N4+)"
  type        = string
  default     = "pd-balanced"
}

variable "ssh_key" {
  description = "Chave SSH Pública a ser inserida ('usuario:ssh-rsa AAAAB3...')"
  type        = string
}

variable "enable_telegram_alerts" {
  description = "Ativar envio de alertas para o Telegram (true ou false)"
  type        = bool
  default     = false
}

variable "telegram_bot_token" {
  description = "Token do seu Bot do Telegram (gerado pelo BotFather)"
  type        = string
  default     = ""
}

variable "telegram_chat_id" {
  description = "ID do Chat/Grupo do Telegram para enviar os alertas"
  type        = string
  default     = ""
}
