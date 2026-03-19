# Provisionamento de Máquinas Virtuais no GCP via Terraform

Este repositório contém a infraestrutura como código (IaC) em Terraform para provisionar Máquinas Virtuais no Google Cloud Platform rapidamente.

## Recursos Integrados
- **Rede Padrão e Firewall global**: Atrelada à interface `default` e com as tags `http-server` e `https-server` ativadas.
- **Disco Fixo e Customizável**: Variável com suporte para discos básicos ou Hyperdisk. Os Discos não recebem políticas de backup.
- **Service Account Padrão**: Segue atrelado à conta de serviço base do Compute Engine.
- **Acesso Externo Exclusivo**: Atribuição e reserva de IP Externo Fixo (Estático).

## Guia de Início Rápido

1. **Autenticação:**
   Certifique-se de que o [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`) esteja instalado. Faça o login de aplicação pelo terminal de dentro da pasta:
   ```bash
   gcloud auth application-default login
   ```

2. **Criação das Variáveis Essenciais:**
   Duplique o arquivo modelo:
   - Linux / MacOS: `cp terraform.tfvars.example terraform.tfvars`
   - Windows: `copy terraform.tfvars.example terraform.tfvars`
   
   Após copiar, abra o arquivo `terraform.tfvars` alterando: as keys SSH, o id real de projeto do GCP (`project_id`), o modelo da máquina e casando o `boot_disk_type` correspondente à série do processador.

3. **Iniciando e Instalando Dependências:**
   ```bash
   terraform init
   ```

4. **Validando Modificações (Dry Run):**
   Veja os recursos que serão aplicados antes de cobrar ou aprovar qualquer implantação real com o comando:
   ```bash
   terraform plan
   ```

5. **Aplicar as Alterações (Deploy):**
   Para realizar o provisionamento padrão, execute:
   ```bash
   terraform apply
   ```
   *(Nota: Se você configurou os Alertas do Telegram, veja a seção abaixo sobre como utilizar os scripts wrapper na hora do deploy).*

## Alertas via Telegram (Opcional)

Você pode receber notificações automáticas no seu Telegram sempre que o processo de provisionamento iniciar, for concluído com sucesso ou apresentar falhas técnicas.

**Como configurar e executar:**
1. No seu arquivo `terraform.tfvars`, adicione as três variáveis e preencha com os dados reais do seu bot:
   ```hcl
   enable_telegram_alerts = true
   telegram_bot_token     = "SEU_TOKEN_AQUI"
   telegram_chat_id       = "SEU_CHAT_ID_AQUI"
   ```
2. Na hora do Deploy, ao invés de rodar `terraform apply` manualmente, utilize os scripts integrados na raiz do projeto. Eles se encarregam de disparar o Terraform e analisar os logs:
   - Usuários de Windows (PowerShell):
     ```powershell
     .\deploy_vm.ps1
     ```
   - Usuários de Linux, macOS, WSL ou Git Bash:
     ```bash
     bash deploy_vm.sh
     ```

## Estrutura de Diretório
- `main.tf`: Definição dos blocos do Google Compute Engine (Instância e IP Fixo).
- `variables.tf`: Especificação das propriedades exigidas.
- `terraform.tfvars.example`: Planilha visual de como formatar seus dados.
- `outputs.tf`: Onde consultamos rapidamente os labels como o Novo IP Fixo injetado.

## Dicas Úteis (CLI e Configurações API)

**1. Listar Modelos de Máquina Disponíveis**
Para listar os tipos de máquinas suportados na sua zona diretamente no terminal, use:
```bash
gcloud compute machine-types list --filter="zone:us-central1-a"
```

**2. Listar Imagens do Sistema Operacional (Ubuntu)**
Caso queira garantir o nome exato da imagem LTS mais recente do Ubuntu (ex: 22.04 LTS ou 24.04 LTS), execute:
```bash
gcloud compute images list --project ubuntu-os-cloud --no-standard-images
```

**3. Matriz de Compatibilidade de Discos x Processadores**
- **Discos Padrões** (`pd-balanced`, `pd-ssd`, etc): Compatíveis com as séries E2, N1, N2, N2D, C2, T2D, etc. *Incompatíveis com a nova geração N4, C3, M3*.
- **Discos Hyperdisk** (`hyperdisk-balanced`, etc): Compatíveis *SOMENTE* com instâncias modernas como N4, C3 e M3. *Incompatíveis com as linhas antigas (E2, N2, N1)*.

**4. Regra para Instâncias Customizadas**
O GCP permite configurações sob medida (ex: pouca CPU e muita memória).
A nomenclatura exige Megabytes na RAM. Exemplos: `e2-custom-2-12288` ou `n2-custom-4-32768`.
- Lembre-se que a família **N1** é a *única* que suporta instâncias customizadas com apenas **1 vCPU** (ex: `custom-1-12288`).
- Famílias mais modernas como **E2** e **N2** exigem no mínimo *2 vCPUs* em qualquer configuração custom.
