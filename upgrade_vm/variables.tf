variable "project_id" {
  description = "Cód/ID do Projeto no Google Cloud"
  type        = string
}

variable "region" {
  description = "Região para a instância"
  type        = string
}

variable "zone" {
  description = "Zona para a instância"
  type        = string
}

variable "vm_name" {
  description = "Nome da nova VM (pode ser igual ao nome antigo, já que a antiga terá sido excluída antes do apply)"
  type        = string
}

variable "machine_type" {
  description = "Tipo de maquina, predefinição, CPUs, RAM (ex: e2-standard-4, n4-standard-4, ou custo: e2-custom-2-4096)"
  type        = string
}

variable "os_image" {
  description = "Imagem do Sistema Operacional novo (ex: ubuntu-os-cloud/ubuntu-2604-lts-amd64)"
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

variable "tags" {
  description = "Tags de firewall/rede da instância"
  type        = list(string)
  default     = ["http-server", "https-server"]
}

variable "network" {
  description = "Rede VPC onde a instância será criada"
  type        = string
  default     = "default"
}

variable "existing_static_ip" {
  description = "IP externo RESERVADO já existente (o mesmo endereço estático que a VM antiga usava). Este módulo NÃO cria nem gerencia esse recurso — ele só o referencia diretamente, então o endereço reservado precisa continuar existindo no GCP (não é apagado pelo upgrade_vm.sh, apenas desassociado da VM antiga)."
  type        = string
}

variable "network_ip" {
  description = "IP interno fixo a ser atribuído à nova instância (o mesmo IP interno que a VM antiga usava, ex: 10.158.0.5). Só funciona se esse IP estiver livre no momento do apply — ou seja, a VM antiga precisa já ter sido excluída."
  type        = string
}

variable "workspace_name" {
  description = "Nome do Terraform Workspace usado para isolar o state desta VM/projeto das demais (mesma convenção da pasta raiz)."
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
