#!/bin/bash
set -uo pipefail

TFVARS_FILE="terraform.tfvars"
ALLOW_DESTRUCTIVE=false

show_help() {
    echo "=========================================================="
    echo "           SCRIPT DE DEPLOY - GCP TERRAFORM"
    echo "=========================================================="
    echo "Uso: ./deploy_vm.sh [OPCOES]"
    echo ""
    echo "Por padrao este script e SOMENTE PARA CRIACAO. Ele seleciona"
    echo "(ou cria) o Terraform Workspace definido em 'workspace_name'"
    echo "no terraform.tfvars -- isolando o state desta VM do state de"
    echo "qualquer outra -- e so executa o apply se o plano gerado for"
    echo "100% criacao de recursos novos."
    echo ""
    echo "Se o plano contiver qualquer 'update' ou 'delete' (alteracao"
    echo "ou exclusao de recursos ja existentes), o apply e BLOQUEADO"
    echo "automaticamente para proteger VMs ja provisionadas."
    echo ""
    echo "Opcoes:"
    echo "  --allow-destructive   Permite prosseguir mesmo se o plano"
    echo "                        contiver updates/deletes. Ainda assim"
    echo "                        pede uma confirmacao explicita digitada"
    echo "                        no terminal antes de aplicar."
    echo "  --help                Exibe esta mensagem de ajuda."
    echo "=========================================================="
}

for arg in "$@"; do
    case $arg in
        --allow-destructive)
        ALLOW_DESTRUCTIVE=true
        shift
        ;;
        --help)
        show_help
        exit 0
        ;;
    esac
done

if [ ! -f "$TFVARS_FILE" ]; then
    echo "Arquivo $TFVARS_FILE nao encontrado!"
    exit 1
fi

for cmd in terraform jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Erro: comando '$cmd' nao encontrado no PATH. Instale-o para continuar."
        exit 1
    fi
done

# Extrair variaveis do terraform.tfvars
ENABLE_ALERTS=$(grep -Ei 'enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]')
BOT_TOKEN=$(grep -E 'telegram_bot_token[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
CHAT_ID=$(grep -E 'telegram_chat_id[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
WORKSPACE_NAME=$(grep -Ei '^[[:space:]]*workspace_name[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

if [ -z "$WORKSPACE_NAME" ]; then
    echo "Erro: 'workspace_name' nao definido em $TFVARS_FILE."
    echo "Defina um nome unico de workspace para esta VM (ou 'default' para a VM classica ja existente)."
    exit 1
fi

send_telegram_alert() {
    local message="$1"
    if [ "$ENABLE_ALERTS" == "true" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            -d "text=$message" \
            -d "parse_mode=HTML" > /dev/null
    fi
}

echo "Selecionando workspace do Terraform: $WORKSPACE_NAME"
if ! terraform workspace select "$WORKSPACE_NAME" >/dev/null 2>&1; then
    echo "Workspace '$WORKSPACE_NAME' nao existe ainda. Criando (state isolado, nao afeta outras VMs)..."
    if ! terraform workspace new "$WORKSPACE_NAME"; then
        echo "Erro ao criar o workspace '$WORKSPACE_NAME'."
        exit 1
    fi
fi

echo "Iniciando provisionamento..."
send_telegram_alert "🚀 <b>GCP:</b> Inicio do processo de provisionamento (workspace: <b>$WORKSPACE_NAME</b>)..."

PLAN_FILE=$(mktemp)
PLAN_JSON=$(mktemp)
cleanup() { rm -f "$PLAN_FILE" "$PLAN_JSON"; }
trap cleanup EXIT

echo "Calculando plano (terraform plan)..."
if ! terraform plan -input=false -out="$PLAN_FILE"; then
    echo "Erro ao gerar o plano do Terraform."
    send_telegram_alert "❌ <b>GCP:</b> Erro ao gerar o plano do Terraform (workspace: $WORKSPACE_NAME)."
    exit 1
fi

terraform show -json "$PLAN_FILE" > "$PLAN_JSON"

DESTRUCTIVE_LIST=$(jq -r '
  .resource_changes[]?
  | select(.change.actions | any(. == "update" or . == "delete"))
  | "  - \(.address) (\(.change.actions | join(",")))"
' "$PLAN_JSON")

if [ -n "$DESTRUCTIVE_LIST" ]; then
    echo "------------------------------------------------------"
    echo "TRAVA DE SEGURANCA: o plano contem alteracao(oes) ou exclusao(oes):"
    echo "$DESTRUCTIVE_LIST"
    echo "------------------------------------------------------"

    if [ "$ALLOW_DESTRUCTIVE" = false ]; then
        echo "Este script e apenas para CRIACAO. Apply cancelado."
        echo "Se a alteracao/exclusao acima for intencional, rode novamente com --allow-destructive."
        send_telegram_alert "🛑 <b>GCP:</b> Apply BLOQUEADO (workspace: $WORKSPACE_NAME) -- o plano tentava alterar ou excluir recursos existentes. Nenhuma mudanca foi aplicada."
        exit 1
    fi

    echo "Flag --allow-destructive detectada. Confirmacao explicita necessaria."
    read -r -p "Digite CONFIRMAR para prosseguir com estas alteracoes/exclusoes: " CONFIRMATION
    if [ "$CONFIRMATION" != "CONFIRMAR" ]; then
        echo "Confirmacao nao recebida. Apply cancelado."
        send_telegram_alert "🛑 <b>GCP:</b> Apply cancelado pelo usuario na confirmacao (workspace: $WORKSPACE_NAME)."
        exit 1
    fi
    send_telegram_alert "⚠️ <b>GCP:</b> Apply com alteracoes/exclusoes CONFIRMADO manualmente (workspace: $WORKSPACE_NAME)."
fi

echo "Executando terraform apply..."
if terraform apply -input=false "$PLAN_FILE"; then
    echo "Terraform finalizado com sucesso."
    send_telegram_alert "✅ <b>GCP:</b> Sucesso! Criacao/atualizacao concluida (workspace: $WORKSPACE_NAME)."
else
    EXIT_CODE=$?
    echo "Ocorreram erros durante o Terraform."
    send_telegram_alert "❌ <b>GCP:</b> Erro! Ocorreram erros durante o provisionamento ou criacao da VM (workspace: $WORKSPACE_NAME)."
    exit $EXIT_CODE
fi
