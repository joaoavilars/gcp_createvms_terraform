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

variable "machine_model_base" {
  description = "Familia da maquina (ex: t2d, n2, e2)"
  type        = string
}

variable "machine_cpus" {
  description = "Quantidade de CPUs da maquina"
  type        = number
}

variable "machine_ram" {
  description = "Quantidade de memoria RAM em GB"
  type        = number
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

variable "create_extra_disk" {
  description = "Define se um disco extra deve ser criado e anexado à VM"
  type        = bool
  default     = false
}

variable "extra_disk_size" {
  description = "Tamanho do disco extra em GB"
  type        = number
  default     = 50
}

variable "extra_disk_type" {
  description = "Tipo do disco extra (pd-balanced, etc)"
  type        = string
  default     = "pd-balanced"
}
