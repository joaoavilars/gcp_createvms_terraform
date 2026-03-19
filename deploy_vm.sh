#!/bin/bash
set -uo pipefail

TFVARS_FILE="terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "Arquivo $TFVARS_FILE não encontrado!"
    exit 1
fi

# Extrair variáveis do terraform.tfvars
ENABLE_ALERTS=$(grep -iE 'enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$TFVARS_FILE" | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]' || true)
BOT_TOKEN=$(grep -E 'telegram_bot_token[[:space:]]*=' "$TFVARS_FILE" | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)
CHAT_ID=$(grep -E 'telegram_chat_id[[:space:]]*=' "$TFVARS_FILE" | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)

send_telegram_alert() {
    local message="$1"
    if [ "$ENABLE_ALERTS" = "true" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        local response
        response=$(curl -sS -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            --data-urlencode "text=$message" \
            -d "parse_mode=HTML" 2>&1) || true
        if echo "$response" | grep -q '"ok":false'; then
            echo "Aviso: Telegram retornou erro -> $response" >&2
        fi
    fi
}

echo "Iniciando provisionamento..."
send_telegram_alert "🚀 <b>GCP:</b> Início do processo de provisionamento da VM pelo Terraform..."

echo "Executando terraform apply..."
if terraform apply -auto-approve; then
    echo "Terraform finalizado com sucesso."
    send_telegram_alert "✅ <b>GCP:</b> Sucesso! Criação e início da VM concluídos com êxito."
else
    EXIT_CODE=$?
    echo "Ocorreram erros durante o Terraform."
    send_telegram_alert "❌ <b>GCP:</b> Erro! Ocorreram erros durante o provisionamento ou criação da VM."
    exit $EXIT_CODE
fi
