#!/bin/bash

# --- Tratamento de Argumentos (Contexto) ---
PRESERVE_DISK=false
PRESERVE_IP=false

show_help() {
    echo "=========================================================="
    echo "           SCRIPT DE UNDEPLOY - GCP TERRAFORM"
    echo "=========================================================="
    echo "Uso: ./undeploy_vm.sh [OPÇÕES]"
    echo ""
    echo "Opções de Contexto:"
    echo "  --preserve-disk    Remove a VM, mas NÃO remove os discos associados."
    echo "  --preserve-ip      Remove a VM, mas NÃO remove o IP Fixo associado."
    echo "                     (Você pode usar ambas as opções juntas!)"
    echo "  --help             Exibe esta mensagem de ajuda."
    echo ""
    echo "Configuração (.conf):"
    echo "  O script lê os dados obrigatórios do arquivo 'undeploy.conf' na mesma pasta."
    echo "  Neste arquivo você deve definir:"
    echo "    project_id             -> ID do Projeto no GCP"
    echo "    vm_name                -> Nome exato da VM a ser deletada"
    echo "    region / zone          -> Localização da VM e do IP"
    echo "    enable_telegram_alerts -> true ou false"
    echo "    telegram_bot_token / telegram_chat_id -> Para alertas de processo"
    echo "=========================================================="
}

for arg in "$@"; do
    case $arg in
        --preserve-disk)
        PRESERVE_DISK=true
        shift
        ;;
        --preserve-ip)
        PRESERVE_IP=true
        shift
        ;;
        --help)
        show_help
        exit 0
        ;;
    esac
done

CONF_FILE="undeploy.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Arquivo $CONF_FILE não encontrado! Rode './undeploy_vm.sh --help' para mais informações."
    exit 1
fi

# Extrair variáveis do undeploy.conf (usando grep -i e tr -d \r para compatibilidade no Windows)
PROJECT_ID=$(grep -Ei '^project_id[[:space:]]*=[[:space:]]*' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
VM_NAME=$(grep -Ei '^vm_name[[:space:]]*=[[:space:]]*' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
ZONE=$(grep -Ei '^zone[[:space:]]*=[[:space:]]*' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
REGION=$(grep -Ei '^region[[:space:]]*=[[:space:]]*' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

ENABLE_ALERTS=$(grep -Ei '^enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]')
BOT_TOKEN=$(grep -E '^telegram_bot_token[[:space:]]*=' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
CHAT_ID=$(grep -E '^telegram_chat_id[[:space:]]*=' "$CONF_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

# Validação básica
if [ -z "$VM_NAME" ] || [ -z "$PROJECT_ID" ]; then
    echo "Erro: vm_name e project_id devem estar preenchidos no $CONF_FILE."
    exit 1
fi

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

send_telegram_alert() {
    local message="$1"
    if [ "$ENABLE_ALERTS" == "true" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            -d "text=$message" \
            -d "parse_mode=HTML")
        if [ "$HTTP_CODE" != "200" ]; then
            echo -e "${YELLOW}Falha ao enviar alerta para o Telegram.${NC}"
        fi
    fi
}

PRESERVED_INFO=""
if [ "$PRESERVE_DISK" = true ] && [ "$PRESERVE_IP" = true ]; then
    PRESERVED_INFO=" (Discos e IP preservados)"
elif [ "$PRESERVE_DISK" = true ]; then
    PRESERVED_INFO=" (Discos preservados)"
elif [ "$PRESERVE_IP" = true ]; then
    PRESERVED_INFO=" (IP preservado)"
fi

echo -e "${CYAN}Iniciando processo de Undeploy...${NC}"
echo "Projeto: $PROJECT_ID"
echo "VM a ser removida: $VM_NAME"

ALERT_MSG="🗑️ <b>GCP:</b> Início do processo de undeploy da VM <b>$VM_NAME</b>${PRESERVED_INFO}..."
send_telegram_alert "$ALERT_MSG"

# 1. Obter e Remover a Instância da VM e Discos Anexados
echo "------------------------------------------------------"
echo "Buscando discos associados à instância $VM_NAME..."
# Pega a URL dos discos (ex: https://.../disks/teste-e2-n4-hyperdisk) antes da VM sumir
DISKS_TO_DELETE=$(gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --format="value(disks[].source)" 2>/dev/null)

KEEP_DISKS_FLAG=""
if [ "$PRESERVE_DISK" = true ]; then
    KEEP_DISKS_FLAG="--keep-disks=all"
    echo "⚠️ Opção --preserve-disk ativada! Discos NÃO serão removidos."
fi

echo "Deletando instância da VM..."
if gcloud compute instances delete "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" $KEEP_DISKS_FLAG --quiet; then
    echo -e "${GREEN}Sucesso: Instância $VM_NAME deletada.${NC}"

    # Após deletar a VM, excluímos os discos atrelados caso a preservação NÃO esteja ativa
    if [ "$PRESERVE_DISK" = false ] && [ -n "$DISKS_TO_DELETE" ]; then
        # O for separa as URLs que vieram com espaço
        for disk_url in $DISKS_TO_DELETE; do
            disk_name=$(basename "$disk_url")
            echo "Forçando também a exclusão do disco: $disk_name..."
            gcloud compute disks delete "$disk_name" --project="$PROJECT_ID" --zone="$ZONE" --quiet 2>/dev/null || echo "Disco $disk_name já auto-deletado."
        done
    fi
else
    echo -e "${RED}Aviso: Falha ao deletar a instância $VM_NAME (ou ela já não existia).${NC}"
    send_telegram_alert "⚠️ <b>GCP:</b> Falha ao deletar a instância <b>$VM_NAME</b> (ou ela já não existia)."
fi

# 2. Remover IP Fixo (Sempre segue o padrão vm_name-static-ip nas vars do terraform)
if [ "$PRESERVE_IP" = true ]; then
    echo "------------------------------------------------------"
    echo "⚠️ Opção --preserve-ip ativada! IP Fixo não será removido."
else
    STATIC_IP_NAME="${VM_NAME}-static-ip"
    echo "------------------------------------------------------"
    echo "Deletando IP Fixo: $STATIC_IP_NAME..."
    if gcloud compute addresses delete "$STATIC_IP_NAME" --project="$PROJECT_ID" --region="$REGION" --quiet; then
        echo -e "${GREEN}Sucesso: IP Fixo $STATIC_IP_NAME deletado.${NC}"
    else
        echo -e "${RED}Aviso: Falha ao deletar o IP fixo $STATIC_IP_NAME (ou ele já não existia).${NC}"
        send_telegram_alert "⚠️ <b>GCP:</b> Falha ao deletar o IP fixo <b>$STATIC_IP_NAME</b> (ou ele já não existia)."
    fi
fi

echo "------------------------------------------------------"
echo -e "${GREEN}Undeploy concluído!${NC}"
send_telegram_alert "✅ <b>GCP:</b> Undeploy da VM <b>$VM_NAME</b> finalizado!${PRESERVED_INFO}"
