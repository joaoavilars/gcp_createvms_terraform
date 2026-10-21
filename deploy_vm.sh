#!/bin/bash
set -uo pipefail

TFVARS_FILE="terraform.tfvars"
ALLOW_DESTRUCTIVE=false
PLAN_ONLY=false

show_help() {
    echo "=========================================================="
    echo "           SCRIPT DE DEPLOY - GCP TERRAFORM"
    echo "=========================================================="
    echo "Uso: ./deploy_vm.sh [OPCOES]"
    echo ""
    echo "Por padrao este script e SOMENTE PARA CRIACAO. Ele valida o"
    echo "ambiente (login do gcloud, projeto, nomes ja em uso), seleciona"
    echo "(ou cria) o Terraform Workspace definido em 'workspace_name'"
    echo "no terraform.tfvars -- isolando o state desta VM do state de"
    echo "qualquer outra --, mostra um resumo do plano e SEMPRE pede"
    echo "confirmacao (SIM) antes de aplicar."
    echo ""
    echo "Se o plano contiver qualquer 'update' ou 'delete' (alteracao"
    echo "ou exclusao de recursos ja existentes), o apply e BLOQUEADO"
    echo "automaticamente para proteger VMs ja provisionadas."
    echo ""
    echo "Opcoes:"
    echo "  --plan-only           Valida e mostra o plano resumido, mas NAO"
    echo "                        aplica nada nem envia alertas."
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
        --plan-only)
        PLAN_ONLY=true
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

# Le uma variavel string do tfvars (ignora linhas comentadas)
tfvar() {
    grep -Ei "^[[:space:]]*$1[[:space:]]*=" "$TFVARS_FILE" | head -1 | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/'
}

# Extrair variaveis do terraform.tfvars
ENABLE_ALERTS=$(grep -Ei 'enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]')
BOT_TOKEN=$(grep -E 'telegram_bot_token[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
CHAT_ID=$(grep -E 'telegram_chat_id[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
WORKSPACE_NAME=$(tfvar workspace_name)
PROJECT_ID=$(tfvar project_id)
VM_NAME=$(tfvar vm_name)

# Simulacao nao deve gerar ruido no Telegram
if [ "$PLAN_ONLY" = true ]; then ENABLE_ALERTS="false"; fi

if [ -z "$WORKSPACE_NAME" ]; then
    echo "Erro: 'workspace_name' nao definido em $TFVARS_FILE."
    echo "Defina um nome unico de workspace para esta VM (ou 'default' para a VM classica ja existente)."
    exit 1
fi

if [ -z "$PROJECT_ID" ] || [ -z "$VM_NAME" ]; then
    echo "Erro: 'project_id' e 'vm_name' precisam estar definidos em $TFVARS_FILE."
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

# ----------------------------------------------------------------------
# Pre-checagens (somente leitura no GCP)
# ----------------------------------------------------------------------
WARNINGS=()
HAS_GCLOUD=false
if command -v gcloud >/dev/null 2>&1; then HAS_GCLOUD=true; fi

echo "Alvo: projeto '$PROJECT_ID' | VM '$VM_NAME' | workspace '$WORKSPACE_NAME'"

if [ "$HAS_GCLOUD" = true ]; then
    if ! OUT=$(gcloud projects describe "$PROJECT_ID" --format="value(projectId)" 2>&1); then
        echo "Erro: gcloud sem acesso ao projeto '$PROJECT_ID'."
        echo "Rode 'gcloud auth login' ou confira o project_id no tfvars."
        echo "$OUT" | head -3 | sed 's/^/  /'
        exit 1
    fi
else
    WARNINGS+=("gcloud nao encontrado no PATH: nao foi possivel checar projeto nem nomes ja em uso.")
fi

EXPECTED_WORKSPACE="$PROJECT_ID-$VM_NAME"
if [ "$WORKSPACE_NAME" != "$EXPECTED_WORKSPACE" ] && [ "$WORKSPACE_NAME" != "default" ]; then
    WARNINGS+=("workspace_name '$WORKSPACE_NAME' foge do padrao '$EXPECTED_WORKSPACE'. Nomes genericos podem ser reaproveitados por outra VM.")
fi

echo "Selecionando workspace do Terraform: $WORKSPACE_NAME"
if ! terraform workspace select "$WORKSPACE_NAME" >/dev/null 2>&1; then
    echo "Workspace '$WORKSPACE_NAME' nao existe ainda. Criando (state isolado, nao afeta outras VMs)..."
    if ! terraform workspace new "$WORKSPACE_NAME"; then
        echo "Erro ao criar o workspace '$WORKSPACE_NAME'."
        exit 1
    fi
fi

# Se a VM ainda nao e gerenciada por este workspace, ela nao pode existir no projeto
if [ "$HAS_GCLOUD" = true ] && ! terraform state list 2>/dev/null | grep -qx 'google_compute_instance.vm_instance'; then
    IP_NAME="$VM_NAME-static-ip"

    if ! VM_FOUND=$(gcloud compute instances list --project "$PROJECT_ID" --filter="name=$VM_NAME" --format="value(name,zone.basename())" 2>&1); then
        echo "Erro ao listar VMs do projeto '$PROJECT_ID':"
        echo "$VM_FOUND" | head -3 | sed 's/^/  /'
        exit 1
    fi
    if [ -n "$VM_FOUND" ]; then
        echo "Erro: ja existe uma VM chamada '$VM_NAME' no projeto '$PROJECT_ID' ($VM_FOUND)."
        echo "Escolha outro vm_name. Nada foi alterado."
        exit 1
    fi

    if ! IP_FOUND=$(gcloud compute addresses list --project "$PROJECT_ID" --filter="name=$IP_NAME" --format="value(name,region.basename())" 2>&1); then
        echo "Erro ao listar IPs do projeto '$PROJECT_ID':"
        echo "$IP_FOUND" | head -3 | sed 's/^/  /'
        exit 1
    fi
    if [ -n "$IP_FOUND" ]; then
        echo "Erro: ja existe um IP chamado '$IP_NAME' no projeto '$PROJECT_ID' ($IP_FOUND)."
        echo "Escolha outro vm_name. Nada foi alterado."
        exit 1
    fi
fi

for w in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do
    echo "AVISO: $w"
done

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

CREATE_LIST=$(jq -r '
  .resource_changes[]?
  | select(.change.actions | index("create"))
  | "  + \(.address)" + (
      if .type == "google_compute_instance" then
        " [nome=\(.change.after.name), tipo=\(.change.after.machine_type), zona=\(.change.after.zone), boot=\(.change.after.boot_disk[0].initialize_params[0].size)GB \(.change.after.boot_disk[0].initialize_params[0].type)]"
      elif .type == "google_compute_address" then
        " [nome=\(.change.after.name), regiao=\(.change.after.region)]"
      elif .type == "google_compute_disk" then
        " [nome=\(.change.after.name), tamanho=\(.change.after.size)GB, tipo=\(.change.after.type)]"
      else "" end)
' "$PLAN_JSON")

DESTRUCTIVE_LIST=$(jq -r '
  .resource_changes[]?
  | select(.change.actions | any(. == "update" or . == "delete"))
  | "  - \(.address) (\(.change.actions | join(",")))"
' "$PLAN_JSON")

echo "======================================================"
echo "RESUMO DO PLANO  (projeto: $PROJECT_ID | workspace: $WORKSPACE_NAME)"
if [ -n "$CREATE_LIST" ]; then
    echo "Serao CRIADOS:"
    echo "$CREATE_LIST"
fi
if [ -n "$DESTRUCTIVE_LIST" ]; then
    echo "TRAVA DE SEGURANCA: o plano contem alteracao(oes) ou exclusao(oes):"
    echo "$DESTRUCTIVE_LIST"
fi
echo "======================================================"

if [ -z "$CREATE_LIST" ] && [ -z "$DESTRUCTIVE_LIST" ]; then
    echo "Nenhuma mudanca no plano. Nada a aplicar."
    exit 0
fi

if [ "$PLAN_ONLY" = true ]; then
    if [ -n "$DESTRUCTIVE_LIST" ]; then
        echo "--plan-only: nada foi aplicado. Um deploy real seria BLOQUEADO sem --allow-destructive."
    else
        echo "--plan-only: nada foi aplicado."
    fi
    exit 0
fi

if [ -n "$DESTRUCTIVE_LIST" ]; then
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
else
    read -r -p "Digite SIM (maiusculo) para criar os recursos acima: " CONFIRMATION
    if [ "$CONFIRMATION" != "SIM" ]; then
        echo "Confirmacao nao recebida. Apply cancelado."
        send_telegram_alert "🛑 <b>GCP:</b> Apply cancelado pelo usuario na confirmacao (workspace: $WORKSPACE_NAME)."
        exit 1
    fi
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
