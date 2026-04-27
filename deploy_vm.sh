#!/bin/bash

TFVARS_FILE="terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "Arquivo $TFVARS_FILE não encontrado!"
    exit 1
fi

# Extrair variáveis do terraform.tfvars
ENABLE_ALERTS=$(grep -Ei 'enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]')
BOT_TOKEN=$(grep -E 'telegram_bot_token[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
CHAT_ID=$(grep -E 'telegram_chat_id[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

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

echo -e "${CYAN}Iniciando provisionamento...${NC}"
send_telegram_alert "🚀 <b>GCP:</b> Início do processo de provisionamento da VM pelo Terraform..."

echo -e "${CYAN}Executando terraform apply...${NC}"
if terraform apply -auto-approve; then
    echo -e "${GREEN}Terraform finalizado com sucesso.${NC}"
    send_telegram_alert "✅ <b>GCP:</b> Sucesso! Criação e início da VM concluídos com êxito."
else
    EXIT_CODE=$?
    echo -e "${RED}Ocorreram erros durante o Terraform.${NC}"
    send_telegram_alert "❌ <b>GCP:</b> Erro! Ocorreram erros durante o provisionamento ou criação da VM."
    exit $EXIT_CODE
fi
