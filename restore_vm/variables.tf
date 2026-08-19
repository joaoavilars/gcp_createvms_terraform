variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região do GCP"
  type        = string
}

variable "zone" {
  description = "Zona do GCP"
  type        = string
}

variable "vm_name" {
  description = "Nome da VM a ser restaurada"
  type        = string
}

variable "static_ip_name" {
  description = "Nome do IP estático existente a reutilizar"
  type        = string
}

variable "snapshot_name" {
  description = "Nome da snapshot a usar para restauração"
  type        = string
}

variable "machine_model_base" {
  description = "Família da máquina (e2, n2, n4, t2d, etc)"
  type        = string
}

variable "machine_cpus" {
  description = "Número de vCPUs"
  type        = number
}

variable "machine_ram" {
  description = "RAM em GB"
  type        = number
}

variable "boot_disk_size" {
  description = "Tamanho do disco de boot em GB"
  type        = number
}

variable "boot_disk_type" {
  description = "Tipo do disco (pd-standard, pd-balanced, pd-ssd)"
  type        = string
}

variable "ssh_key" {
  description = "Chave SSH para acesso"
  type        = string
}

variable "enable_telegram_alerts" {
  description = "Habilitar alertas do Telegram"
  type        = bool
  default     = false
}

variable "telegram_bot_token" {
  description = "Token do bot do Telegram"
  type        = string
  default     = ""
}

variable "telegram_chat_id" {
  description = "Chat ID do Telegram"
  type        = string
  default     = ""
}
