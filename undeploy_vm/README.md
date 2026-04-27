# Undeploy VM - GCP Terraform

Script para remover uma VM e seus recursos associados (discos e IP fixo) no GCP.

## Pré-requisitos

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) instalado e autenticado
- [Terraform](https://developer.hashicorp.com/terraform/downloads) instalado (caso precise de referência de estado)
- Acesso ao projeto GCP com permissões de Compute Admin

## Configuração

Antes de executar, edite o arquivo `undeploy.conf` na mesma pasta do script:

```conf
project_id              = "seu-project-id"
vm_name                 = "nome-da-vm"
region                  = "us-east1"
zone                    = "us-east1-c"
enable_telegram_alerts  = true
telegram_bot_token      = "seu-bot-token"
telegram_chat_id        = "seu-chat-id"
```

| Campo | Obrigatório | Descrição |
|---|---|---|
| `project_id` | Sim | ID do projeto no GCP |
| `vm_name` | Sim | Nome exato da VM a ser removida |
| `region` | Sim | Região onde o IP fixo está alocado |
| `zone` | Sim | Zona onde a VM está alocada |
| `enable_telegram_alerts` | Não | `true` para receber notificações no Telegram |
| `telegram_bot_token` | Não | Token do bot do Telegram |
| `telegram_chat_id` | Não | ID do chat do Telegram |

## Uso

```bash
# Remoção completa (VM + discos + IP fixo)
./undeploy_vm.sh

# Remover a VM, mas preservar os discos
./undeploy_vm.sh --preserve-disk

# Remover a VM, mas preservar o IP fixo
./undeploy_vm.sh --preserve-ip

# Remover a VM, mas preservar discos E IP fixo
./undeploy_vm.sh --preserve-disk --preserve-ip

# Ajuda
./undeploy_vm.sh --help
```

## Opções

| Opção | Descrição |
|---|---|
| `--preserve-disk` | Remove a VM, mas **não** remove os discos associados |
| `--preserve-ip` | Remove a VM, mas **não** remove o IP fixo associado |
| `--help` | Exibe a mensagem de ajuda |

As opções podem ser combinadas. Exemplo: `--preserve-disk --preserve-ip` preserva ambos.

## O que o script faz

1. **Lê a configuração** do arquivo `undeploy.conf`
2. **Envia alerta de início** para o Telegram (se habilitado)
3. **Busca os discos** anexados à instância antes da remoção
4. **Deleta a instância da VM** via `gcloud compute instances delete`
   - Se `--preserve-disk` **não** estiver ativo, também força a exclusão dos discos
5. **Deleta o IP fixo** (nome padrão: `{vm_name}-static-ip`) via `gcloud compute addresses delete`
   - Se `--preserve-ip` estiver ativo, pula esta etapa
6. **Envia alerta de conclusão** para o Telegram (se habilitado)

## Alertas no Telegram

Quando `enable_telegram_alerts = true`, o script envia notificações para:

- Início do processo de undeploy
- Falha ao deletar a instância
- Falha ao deletar o IP fixo
- Conclusão do undeploy

Se o envio falhar, um aviso amarelo é exibido no console.
