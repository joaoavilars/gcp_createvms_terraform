# Provisionamento de VMs no GCP via Terraform

Infraestrutura como código (IaC) para provisionar Máquinas Virtuais no Google Cloud Platform com IP externo fixo e notificações opcionais via Telegram.

---

## Recursos Provisionados

| Recurso | Descrição |
|---|---|
| `google_compute_instance` | VM com disco, SO e chave SSH configuráveis |
| `google_compute_address` | IP externo fixo (estático) reservado e associado à VM |
| Firewall | Tags `http-server` e `https-server` aplicadas (regras globais da rede `default`) |

**Comportamentos fixos:**
- Rede: interface `default` do projeto GCP
- Service Account: conta padrão do Compute Engine
- Backup: nenhuma política de backup associada ao disco
- Chaves SSH: alterações ignoradas pelo Terraform após a criação (evita recriação acidental da VM)

---

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/downloads) instalado
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`) instalado e autenticado:
  ```bash
  gcloud auth application-default login
  ```

---

## Início Rápido

### 1. Clonar e configurar variáveis

```bash
# Linux / macOS
cp terraform.tfvars.example terraform.tfvars

# Windows
copy terraform.tfvars.example terraform.tfvars
```

Edite o `terraform.tfvars` preenchendo ao menos:

| Variável | Descrição |
|---|---|
| `project_id` | ID real do seu projeto no GCP |
| `vm_name` | Nome da VM a ser criada |
| `machine_type` | Tipo de máquina (ver seção abaixo) |
| `boot_disk_type` | Tipo de disco (deve ser compatível com o `machine_type`) |
| `ssh_key` | Chave SSH pública no formato `usuario:ssh-rsa AAAA...` |

### 2. Inicializar o Terraform

```bash
terraform init
```

### 3. Validar o plano (dry run)

```bash
terraform plan
```

### 4. Provisionar

```bash
# Padrão (interativo)
terraform apply

# Com notificações via Telegram (recomendado)
bash deploy_vm.sh          # Linux / macOS / WSL / Git Bash
.\deploy_vm.ps1            # Windows (PowerShell)
```

### 5. Destruir a infraestrutura

```bash
terraform destroy
```

---

## Alertas via Telegram (Opcional)

Receba notificações de início, sucesso e falha diretamente no seu Telegram.

**Configuração no `terraform.tfvars`:**
```hcl
enable_telegram_alerts = true
telegram_bot_token     = "SEU_TOKEN_AQUI"   # gerado pelo @BotFather
telegram_chat_id       = "SEU_CHAT_ID_AQUI"
```

> Os scripts `deploy_vm.sh` e `deploy_vm.ps1` leem essas variáveis automaticamente e disparam as notificações.

---

## Referência de Variáveis

| Variável | Tipo | Padrão | Descrição |
|---|---|---|---|
| `project_id` | `string` | — | ID do projeto GCP |
| `region` | `string` | `us-central1` | Região para a instância e o IP |
| `zone` | `string` | `us-central1-a` | Zona da instância |
| `vm_name` | `string` | — | Nome da VM |
| `machine_type` | `string` | — | Tipo de máquina (predefinido ou custom) |
| `os_image` | `string` | — | Imagem do SO (ex: `ubuntu-os-cloud/ubuntu-2404-lts-amd64`) |
| `boot_disk_size` | `number` | `50` | Tamanho do disco em GB |
| `boot_disk_type` | `string` | `pd-balanced` | Tipo do disco (ver compatibilidade abaixo) |
| `ssh_key` | `string` | — | Chave SSH pública (`usuario:ssh-rsa AAAA...`) |
| `enable_telegram_alerts` | `bool` | `false` | Ativa notificações via Telegram |
| `telegram_bot_token` | `string` | `""` | Token do bot do Telegram |
| `telegram_chat_id` | `string` | `""` | ID do chat/grupo para notificações |

---

## Guia de Tipos de Máquina

### Tipos Predefinidos

```
e2-micro        → 2 vCPUs compartilhadas, 1 GB RAM
e2-standard-4   → 4 vCPUs, 16 GB RAM
n4-standard-4   → 4 vCPUs, 16 GB RAM
```

### Tipos Customizados

Formato: `<familia>-custom-<vCPUs>-<RAM_em_MB>`

```
e2-custom-2-12288  → E2, 2 vCPUs, 12 GB RAM
n2-custom-4-32768  → N2, 4 vCPUs, 32 GB RAM
custom-1-12288     → N1, 1 vCPU,  12 GB RAM  ← única família que aceita 1 vCPU
```

> **Atenção:** E2, N2 e N4 exigem no mínimo 2 vCPUs no modo custom. Para 1 vCPU custom, use a família **N1** (sintaxe sem prefixo: `custom-1-<RAM>`).

Listar tipos disponíveis na sua zona:
```bash
gcloud compute machine-types list --filter="zone:us-central1-a"
```

---

## Compatibilidade: Disco x Família de Processador

| Tipo de Disco | Famílias Compatíveis | Famílias Incompatíveis |
|---|---|---|
| `pd-standard`, `pd-balanced`, `pd-ssd` | E2, N1, N2, N2D, C2, T2D | N4, C3, M3 |
| `hyperdisk-balanced`, `hyperdisk-extreme` | N4, C3, M3 | E2, N1, N2 |

---

## Imagens de Sistema Operacional

Listar imagens Ubuntu disponíveis:
```bash
gcloud compute images list --project ubuntu-os-cloud --no-standard-images
```

Exemplos:
```
ubuntu-os-cloud/ubuntu-2404-lts-amd64   → Ubuntu 24.04 LTS
ubuntu-os-cloud/ubuntu-2204-lts         → Ubuntu 22.04 LTS
```

---

## Estrutura do Projeto

```
.
├── main.tf                    # Recursos: VM e IP fixo
├── variables.tf               # Declaração das variáveis
├── outputs.tf                 # Outputs: nome, IP e zona
├── terraform.tfvars.example   # Modelo de configuração
├── deploy_vm.sh               # Script de deploy (Linux/macOS)
└── deploy_vm.ps1              # Script de deploy (Windows)
```
