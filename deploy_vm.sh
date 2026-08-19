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

# ========================================
# VALIDAÇÕES DE SEGURANÇA
# ========================================
PROJECT_ID=$(grep -E 'project_id[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
VM_NAME=$(grep -E 'vm_name[[:space:]]*=' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')

# Verifica conflito entre state e tfvars
if [ -f "terraform.tfstate" ]; then
    STATE_PROJECT=$(python3 -c "import json,sys; d=json.load(open('terraform.tfstate')); [print(r['instances'][0]['attributes']['project']) for r in d['resources'] if r['type']=='google_compute_instance' and r['instances']]" 2>/dev/null)
    STATE_VM=$(python3 -c "import json,sys; d=json.load(open('terraform.tfstate')); [print(r['instances'][0]['attributes']['name']) for r in d['resources'] if r['type']=='google_compute_instance' and r['instances']]" 2>/dev/null)

    if [ -n "$STATE_PROJECT" ] && [ -n "$STATE_VM" ]; then
        if [ "$STATE_PROJECT" != "$PROJECT_ID" ] || [ "$STATE_VM" != "$VM_NAME" ]; then
            echo -e "\n${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║   VM ANTERIOR DETECTADA NO STATE - REMOVENDO AUTOMATICAMENTE ║${NC}"
            echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
            echo -e "\n${CYAN}State atual gerenciava:${NC}"
            echo -e "  Projeto: ${CYAN}$STATE_PROJECT${NC}"
            echo -e "  VM:      ${CYAN}$STATE_VM${NC}"
            echo -e "\n${CYAN}Nova VM solicitada:${NC}"
            echo -e "  Projeto: ${CYAN}$PROJECT_ID${NC}"
            echo -e "  VM:      ${CYAN}$VM_NAME${NC}"
            echo -e "\n${GREEN}A VM '$STATE_VM' NÃO será destruída no GCP.${NC} Ela apenas deixará de ser gerenciada pelo Terraform, liberando o state para criar a VM nova."

            BACKUP_NAME="terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)"
            cp terraform.tfstate "$BACKUP_NAME"
            echo -e "${CYAN}Backup do state salvo em: $BACKUP_NAME${NC}"

            echo -e "\n${CYAN}Removendo recursos antigos do state...${NC}"
            terraform state list | while read -r RESOURCE; do
                echo "Removendo: $RESOURCE"
                terraform state rm "$RESOURCE"
            done
            echo -e "${GREEN}State limpo. Prosseguindo para criar a VM nova.${NC}\n"
        fi
    fi
fi

echo -e "\n${YELLOW}================================================${NC}"
echo -e "${YELLOW}VERIFICAÇÃO DE SEGURANÇA - TERRAFORM PLAN${NC}"
echo -e "${YELLOW}================================================${NC}"
echo -e "Projeto destino: ${CYAN}$PROJECT_ID${NC}"
echo -e "VM destino:      ${CYAN}$VM_NAME${NC}"
echo -e "\n${CYAN}Executando terraform plan para verificar mudanças...${NC}\n"

terraform plan -out=tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERRO] Terraform plan falhou!${NC}"
    exit 1
fi

echo -e "\n${YELLOW}================================================${NC}"
echo -e "${YELLOW}CONFIRMAÇÃO MANUAL OBRIGATÓRIA${NC}"
echo -e "${YELLOW}================================================${NC}"
echo -e "${RED}ATENÇÃO: Revise o plano acima cuidadosamente!${NC}"
echo -e "${RED}Verifique se há recursos marcados para DESTRUIÇÃO (-)${NC}"
echo -e "\nProjeto: ${CYAN}$PROJECT_ID${NC}"
echo -e "VM: ${CYAN}$VM_NAME${NC}\n"

read -p "Digite 'SIM' (maiúsculo) para prosseguir com apply: " CONFIRMATION

if [ "$CONFIRMATION" != "SIM" ]; then
    echo -e "\n${YELLOW}[CANCELADO] Deploy cancelado pelo usuário.${NC}"
    rm -f tfplan
    exit 0
fi

echo -e "${CYAN}Executando terraform apply...${NC}"
if terraform apply tfplan; then
    echo -e "${GREEN}[SUCESSO] Terraform finalizado com sucesso.${NC}"
    send_telegram_alert "✅ <b>GCP:</b> Sucesso! VM '$VM_NAME' no projeto '$PROJECT_ID' criada/atualizada."
    rm -f tfplan
else
    EXIT_CODE=$?
    echo -e "${RED}[ERRO] Ocorreram erros durante o Terraform.${NC}"
    send_telegram_alert "❌ <b>GCP:</b> Erro! Falha no provisionamento da VM '$VM_NAME'."
    rm -f tfplan
    exit $EXIT_CODE
fi
