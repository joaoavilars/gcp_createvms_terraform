#!/bin/bash

# Script para RESTAURAR VM a partir de snapshot do GCP via Terraform

TFVARS_FILE="terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "Arquivo $TFVARS_FILE não encontrado!"
    exit 1
fi

# Extrai variáveis do telegram
ENABLE_ALERTS=$(grep -Ei 'enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]')
BOT_TOKEN=$(grep -E 'telegram_bot_token[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
CHAT_ID=$(grep -E 'telegram_chat_id[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Extrai dados do tfvars
PROJECT_ID=$(grep -E 'project_id[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
VM_NAME=$(grep -E 'vm_name[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
SNAPSHOT_NAME=$(grep -E 'snapshot_name[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

echo -e "\n${CYAN}================================================${NC}"
echo -e "${CYAN}RESTAURAÇÃO DE VM A PARTIR DE SNAPSHOT${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "Projeto:  ${YELLOW}$PROJECT_ID${NC}"
echo -e "VM:       ${YELLOW}$VM_NAME${NC}"
echo -e "Snapshot: ${YELLOW}$SNAPSHOT_NAME${NC}"
echo -e "\n${CYAN}Executando terraform plan...${NC}\n"

send_telegram_alert "🔄 <b>GCP Restore:</b> Iniciando restauração da VM '$VM_NAME' do snapshot '$SNAPSHOT_NAME'..."

terraform plan -out=tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERRO] Terraform plan falhou!${NC}"
    send_telegram_alert "❌ <b>GCP Restore:</b> Erro no terraform plan para '$VM_NAME'."
    exit 1
fi

echo -e "\n${YELLOW}================================================${NC}"
echo -e "${YELLOW}CONFIRMAÇÃO MANUAL OBRIGATÓRIA${NC}"
echo -e "${YELLOW}================================================${NC}"
echo -e "${RED}ATENÇÃO: Revise o plano acima!${NC}"
echo -e "\nProjeto:  ${CYAN}$PROJECT_ID${NC}"
echo -e "VM:       ${CYAN}$VM_NAME${NC}"
echo -e "Snapshot: ${CYAN}$SNAPSHOT_NAME${NC}\n"

read -p "Digite 'RESTAURAR' (maiúsculo) para prosseguir: " CONFIRMATION

if [ "$CONFIRMATION" != "RESTAURAR" ]; then
    echo -e "\n${YELLOW}[CANCELADO] Restauração cancelada.${NC}"
    rm -f tfplan
    exit 0
fi

echo -e "${CYAN}Executando terraform apply...${NC}"
if terraform apply tfplan; then
    echo -e "\n${GREEN}[SUCESSO] VM restaurada com sucesso!${NC}"
    send_telegram_alert "✅ <b>GCP Restore:</b> Sucesso! VM '$VM_NAME' restaurada do snapshot '$SNAPSHOT_NAME'."
    
    echo -e "\n${GREEN}================================================${NC}"
    echo -e "${GREEN}INFORMAÇÕES DA VM RESTAURADA${NC}"
    echo -e "${GREEN}================================================${NC}"
    terraform output
    
    rm -f tfplan
else
    EXIT_CODE=$?
    echo -e "\n${RED}[ERRO] Falha na restauração.${NC}"
    send_telegram_alert "❌ <b>GCP Restore:</b> Erro ao restaurar VM '$VM_NAME'."
    rm -f tfplan
    exit $EXIT_CODE
fi
