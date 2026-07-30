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
   
   Após copiar, abra o arquivo `terraform.tfvars` alterando: as keys SSH, o id real de projeto do GCP (`project_id`), o modelo da máquina, o `boot_disk_type` correspondente à série do processador e o **`workspace_name`** (veja a seção "Múltiplas VMs / Múltiplos Projetos" abaixo — é essencial para não arriscar a VM que já está em produção).

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

## Múltiplas VMs / Múltiplos Projetos (Isolamento de State)

Este projeto foi originalmente desenhado para gerenciar **uma VM por vez** em um único arquivo de state (`terraform.tfstate`). Se você simplesmente editar `vm_name` ou `project_id` no `terraform.tfvars` para apontar para uma VM nova e rodar `apply`, o Terraform entende que a VM *já existente* mudou de nome/projeto — e como isso força a recriação do recurso, ele planeja **destruir a VM antiga e criar a nova no lugar dela**. Isso é comportamento normal do Terraform, não um bug, mas é exatamente o que você não quer ao simplesmente querer adicionar uma VM nova.

Para resolver isso, o projeto usa **[Terraform Workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces)**: cada VM/projeto tem seu próprio `workspace_name`, e cada workspace guarda um arquivo de state **fisicamente separado** (`.terraform.tfstate.d/<workspace_name>/terraform.tfstate`). Um `apply` rodado em um workspace nunca lê nem altera o state de outro.

### Como funciona na prática

1. **VM já existente (a que já estava em produção):** seu `terraform.tfvars` já vem com `workspace_name = "default"` — é o workspace clássico onde o state dela já mora. Não precisa migrar nada.
2. **Nova VM / novo projeto:** escolha um `workspace_name` **novo e único** para ela (sugestão: `"<project_id>-<vm_name>"`) e ajuste as demais variáveis (`project_id`, `vm_name`, `machine_type` etc.) normalmente.
3. Rode `bash deploy_vm.sh` (ou `deploy_vm.ps1` no Windows). O script:
   - Seleciona automaticamente o workspace de `workspace_name` (criando-o se ainda não existir);
   - Roda `terraform plan` e inspeciona o resultado;
   - **Bloqueia o apply** se o plano contiver qualquer `update` ou `delete` — este fluxo é só para criação;
   - Só aplica se o plano for 100% criação de recursos novos.

### Trava de segurança (create-only por padrão)

Por padrão, `deploy_vm.sh`/`deploy_vm.ps1` recusam aplicar qualquer plano que altere ou exclua recursos já existentes — mesmo dentro do workspace certo (ex: você mudou `machine_type` de uma VM já criada sem querer). Se a alteração/exclusão for **intencional**, rode explicitamente:

```bash
bash deploy_vm.sh --allow-destructive
```
```powershell
.\deploy_vm.ps1 -AllowDestructive
```

O script vai listar as mudanças destrutivas e pedir que você digite `CONFIRMAR` antes de prosseguir. Sem essa flag e sem essa confirmação, nada além de criação passa.

Há também uma trava a nível do próprio Terraform (`main.tf`): se o workspace ativo não bater com o `workspace_name` do `terraform.tfvars`, o `plan`/`apply` falha imediatamente com um erro explicativo — protegendo contra um `terraform apply` manual rodado sem passar pelo script, no workspace errado.

### Comandos úteis para gerenciar workspaces manualmente

```bash
terraform workspace list              # lista todos os workspaces (VMs) já criados
terraform workspace select <nome>     # muda para o workspace de uma VM específica
terraform workspace new <nome>        # cria um workspace novo (nova VM)
```

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
   > **Nota Técnica**: *Os scripts em Bash vêm aprimorados com limpezas rigorosas de CRLF (`\r`) nativo do Windows e filtros Case-Insensitive universais, evitando falhas silenciosas na extração das chaves, independente da plataforma que você ou sua equipe utilizarem.*

## Estrutura de Diretório
- `main.tf`: Definição dos blocos do Google Compute Engine (Instância e IP Fixo).
- `variables.tf`: Especificação das propriedades exigidas.
- `terraform.tfvars.example`: Planilha visual de como formatar seus dados.
- `outputs.tf`: Onde consultamos rapidamente os labels como o Novo IP Fixo injetado.
- `undeploy_vm/`: Pasta isolada para exclusão flexível e segura de VMs via CLI (gcloud), sem conflitos com o Terraform State.

---

## Destruição de Recursos (Undeploy isolado)

Caso você queira apagar uma VM específica (junto com o IP e eventuais discos remanescentes) sem depender do ciclo restrito do `terraform destroy`, você pode usar a estrutura contida na pasta `undeploy_vm/`:

1. **Configure as Variáveis:** 
   Modifique o arquivo `undeploy.conf` na raiz deste subdiretório, apontando o **projeto**, **nome exato** da VM e **Zona**.
2. **Rode o Bash Script:**
   ```bash
   cd undeploy_vm
   ./undeploy_vm.sh
   ```

Este script fará uma exclusão inteligente localizando dinamicamente primeiro qualquer disco que estava associado à CLI da nuvem, disparando a deleção completa de forma cirúrgica e limpa, e notificando a conclusão no Telegram.

### Flags de Contexto no Undeploy
Você pode injetar comandos na hora de rodar o script no terminal para poupar recursos:

- `--preserve-disk`: Deleta a VM mas aciona as apis do cloud para ignorar a conservação do disco. Pula a varredura manual de discos que sobram.
- `--preserve-ip`: Deleta a VM e Discos normalmente mas resguarda a exclusão do endereço IP Fixo (caso queira apontar para outra VM no futuro).
- `--help`: Exibe um painel completo de uso do bash script.

*Exemplo combinando flags e mantendo os dados daquela máquina vivos:*
```bash
./undeploy_vm.sh --preserve-disk --preserve-ip
```

---

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
