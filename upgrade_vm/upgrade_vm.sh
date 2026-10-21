#!/bin/bash
set -uo pipefail

TFVARS_FILE="terraform.tfvars"
SKIP_SNAPSHOT=false

show_help() {
    echo "=========================================================="
    echo "       SCRIPT DE UPGRADE (RECRIACAO) DE VM - GCP/TERRAFORM"
    echo "=========================================================="
    echo "Uso: ./upgrade_vm.sh [OPCOES]"
    echo ""
    echo "Recria a VM definida em 'vm_name' (terraform.tfvars) com um novo"
    echo "SO (ou outra config nova), MANTENDO o mesmo IP externo reservado"
    echo "e o mesmo IP interno. Fluxo:"
    echo ""
    echo "  1. Descobre automaticamente (via gcloud) o IP externo, IP interno"
    echo "     e o disco de boot da VM ANTIGA (mesmo nome de 'vm_name')."
    echo "  2. Confere se o IP externo e reservado (static). Se for efemero,"
    echo "     promove ele a reservado automaticamente (sem trocar o IP),"
    echo "     senao a garantia de manter o mesmo IP nao existe."
    echo "  3. Tira um snapshot do disco de boot antigo (seguranca extra,"
    echo "     além do disco em si sobreviver a exclusao da instancia)."
    echo "  4. Pede confirmacao explicita (digitada) antes de qualquer"
    echo "     acao destrutiva."
    echo "  5. Exclui a instancia ANTIGA, preservando o disco (--keep-disks=all)."
    echo "  6. Roda 'terraform apply' neste modulo (upgrade_vm/), criando a"
    echo "     VM NOVA com o SO novo, reaproveitando o IP externo e fixando"
    echo "     o IP interno descobertos no passo 1."
    echo ""
    echo "IMPORTANTE: o disco antigo NAO e apagado (fica disponivel, sem"
    echo "estar anexado a nenhuma VM, como rollback). Apague-o manualmente"
    echo "depois de validar a VM nova, quando tiver certeza que nao precisa"
    echo "mais dele: 'gcloud compute disks delete <nome> --zone=<zona>'."
    echo ""
    echo "IMPORTANTE: a VM nova sobe com o SO limpo — nenhuma configuracao"
    echo "de aplicacao (Apache, Tomcat, SIVA, etc) e migrada automaticamente."
    echo "Isso precisa ser refeito manualmente apos o upgrade."
    echo ""
    echo "Opcoes:"
    echo "  --skip-snapshot   Pula a etapa de snapshot do disco antigo (nao recomendado)."
    echo "  --help            Exibe esta mensagem de ajuda."
    echo "=========================================================="
}

for arg in "$@"; do
    case $arg in
        --skip-snapshot)
        SKIP_SNAPSHOT=true
        shift
        ;;
        --help)
        show_help
        exit 0
        ;;
    esac
done

if [ ! -f "$TFVARS_FILE" ]; then
    echo "Arquivo $TFVARS_FILE nao encontrado! Copie terraform.tfvars.example para $TFVARS_FILE e preencha."
    exit 1
fi

for cmd in terraform gcloud jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Erro: comando '$cmd' nao encontrado no PATH. Instale-o para continuar."
        exit 1
    fi
done

# --- Extrair variaveis do terraform.tfvars ---
tfvar() {
    grep -Ei "^[[:space:]]*$1[[:space:]]*=" "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' | head -n1
}

PROJECT_ID=$(tfvar project_id)
REGION=$(tfvar region)
ZONE=$(tfvar zone)
VM_NAME=$(tfvar vm_name)
WORKSPACE_NAME=$(tfvar workspace_name)
ENABLE_ALERTS=$(grep -Ei 'enable_telegram_alerts[[:space:]]*=[[:space:]]*(true|false)' "$TFVARS_FILE" | tr -d '\r' | sed -E 's/.*=[[:space:]]*(true|false).*/\1/' | tr '[:upper:]' '[:lower:]')
BOT_TOKEN=$(tfvar telegram_bot_token)
CHAT_ID=$(tfvar telegram_chat_id)

for v in PROJECT_ID REGION ZONE VM_NAME WORKSPACE_NAME; do
    if [ -z "${!v}" ]; then
        echo "Erro: '$v' nao encontrado/vazio em $TFVARS_FILE."
        exit 1
    fi
done

send_telegram_alert() {
    local message="$1"
    if [ "$ENABLE_ALERTS" == "true" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            -d "text=$message" \
            -d "parse_mode=HTML" > /dev/null
    fi
}

echo "=========================================================="
echo "Projeto:     $PROJECT_ID"
echo "VM a recriar: $VM_NAME (zona: $ZONE)"
echo "=========================================================="

# --- 1. Descobrir IPs e disco da VM antiga ---
echo ""
echo "Consultando a VM antiga no GCP..."
INSTANCE_JSON=$(gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --format=json 2>/dev/null)
if [ -z "$INSTANCE_JSON" ]; then
    echo "Erro: VM '$VM_NAME' nao encontrada em $PROJECT_ID/$ZONE. Nada a recriar."
    exit 1
fi

EXTERNAL_IP=$(echo "$INSTANCE_JSON" | jq -r '.networkInterfaces[0].accessConfigs[0].natIP // empty')
INTERNAL_IP=$(echo "$INSTANCE_JSON" | jq -r '.networkInterfaces[0].networkIP // empty')
BOOT_DISK_URL=$(echo "$INSTANCE_JSON" | jq -r '[.disks[] | select(.boot==true)][0].source // empty')
BOOT_DISK_NAME=$(basename "$BOOT_DISK_URL")

if [ -z "$EXTERNAL_IP" ] || [ -z "$INTERNAL_IP" ]; then
    echo "Erro: nao foi possivel obter o IP externo/interno da VM antiga."
    exit 1
fi

if [ -z "$BOOT_DISK_URL" ] || [ "$BOOT_DISK_NAME" == "." ]; then
    echo "Erro: nao foi possivel identificar o disco de boot da VM antiga. Abortando antes de qualquer acao destrutiva."
    exit 1
fi

echo "  IP externo atual:  $EXTERNAL_IP"
echo "  IP interno atual:  $INTERNAL_IP"
echo "  Disco de boot:     $BOOT_DISK_NAME"

# --- 2. Garantir que o IP externo e reservado (static), nao efemero ---
echo ""
echo "Verificando se o IP externo ja e reservado (static)..."
ADDR_NAME=$(gcloud compute addresses list --project="$PROJECT_ID" --filter="address=$EXTERNAL_IP" --format="value(name)" 2>/dev/null | head -n1)

if [ -z "$ADDR_NAME" ]; then
    echo "  IP $EXTERNAL_IP e EFEMERO (nao reservado)."
    echo "  Promovendo para reservado (mesmo IP, sem downtime) antes de prosseguir..."
    ADDR_NAME="${VM_NAME}-static-ip"
    if ! gcloud compute addresses create "$ADDR_NAME" --project="$PROJECT_ID" --region="$REGION" --addresses="$EXTERNAL_IP" ; then
        echo "Erro: falha ao reservar o IP $EXTERNAL_IP. Abortando (sem essa reserva nao ha garantia de manter o mesmo IP externo)."
        exit 1
    fi
    echo "  IP reservado com sucesso como '$ADDR_NAME'."
else
    echo "  OK: ja reservado como '$ADDR_NAME'."
fi

# --- 3. Resumo + confirmacao ---
echo ""
echo "=========================================================="
echo "RESUMO DA OPERACAO"
echo "=========================================================="
echo "1. Snapshot do disco '$BOOT_DISK_NAME'  -> $([ "$SKIP_SNAPSHOT" = true ] && echo 'PULADO (--skip-snapshot)' || echo 'sera feito')"
echo "2. Excluir a instancia '$VM_NAME' (disco preservado, --keep-disks=all)"
echo "3. Criar instancia NOVA '$VM_NAME' via terraform (workspace: $WORKSPACE_NAME)"
echo "   reaproveitando IP externo $EXTERNAL_IP e fixando IP interno $INTERNAL_IP"
echo "=========================================================="
echo ""
read -r -p "Digite CONFIRMAR para prosseguir: " CONFIRMATION
if [ "$CONFIRMATION" != "CONFIRMAR" ]; then
    echo "Confirmacao nao recebida. Operacao cancelada. Nada foi alterado."
    exit 1
fi

send_telegram_alert "🔄 <b>GCP:</b> Inicio do upgrade (recriacao) da VM <b>$VM_NAME</b>..."

# --- 4. Snapshot do disco antigo ---
if [ "$SKIP_SNAPSHOT" = false ]; then
    echo ""
    SNAPSHOT_NAME="${BOOT_DISK_NAME}-pre-upgrade-$(date +%Y%m%d-%H%M%S)"
    echo "Criando snapshot '$SNAPSHOT_NAME'..."
    if ! gcloud compute disks snapshot "$BOOT_DISK_NAME" --project="$PROJECT_ID" --zone="$ZONE" --snapshot-names="$SNAPSHOT_NAME"; then
        echo "Erro ao criar snapshot. Abortando antes de qualquer exclusao."
        send_telegram_alert "❌ <b>GCP:</b> Upgrade de <b>$VM_NAME</b> abortado — falha ao criar snapshot do disco antigo."
        exit 1
    fi
    echo "Snapshot concluido."
fi

# --- 5. Excluir a instancia antiga, preservando o disco ---
echo ""
echo "Excluindo a instancia antiga '$VM_NAME' (disco preservado)..."
if ! gcloud compute instances delete "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --keep-disks=all --quiet; then
    echo "Erro ao excluir a instancia antiga. Abortando antes do terraform apply."
    send_telegram_alert "❌ <b>GCP:</b> Upgrade de <b>$VM_NAME</b> abortado — falha ao excluir a instancia antiga."
    exit 1
fi
echo "Instancia antiga excluida. Disco '$BOOT_DISK_NAME' preservado (desanexado, sem VM)."

# --- 6. Terraform apply (cria a VM nova) ---
echo ""
echo "Selecionando workspace do Terraform: $WORKSPACE_NAME"
if ! terraform workspace select "$WORKSPACE_NAME" >/dev/null 2>&1; then
    echo "Workspace '$WORKSPACE_NAME' nao existe ainda. Criando..."
    if ! terraform workspace new "$WORKSPACE_NAME"; then
        echo "Erro ao criar o workspace '$WORKSPACE_NAME'."
        send_telegram_alert "❌ <b>GCP:</b> Upgrade de <b>$VM_NAME</b>: instancia antiga ja foi excluida, mas falhou ao criar o workspace Terraform. Acao manual necessaria!"
        exit 1
    fi
fi

echo "Executando terraform apply (recriando a VM com o novo SO)..."
if terraform apply -input=false \
    -var "existing_static_ip=$EXTERNAL_IP" \
    -var "network_ip=$INTERNAL_IP" ; then
    echo ""
    echo "=========================================================="
    echo "Upgrade concluido com sucesso!"
    echo "VM '$VM_NAME' recriada com IP externo $EXTERNAL_IP e IP interno $INTERNAL_IP."
    echo ""
    echo "LEMBRETE: o SO esta limpo. Reinstale/reconfigure a aplicacao"
    echo "(Apache, Tomcat, SIVA, etc) antes de considerar a VM em producao."
    echo ""
    echo "Disco antigo preservado como rollback: $BOOT_DISK_NAME"
    echo "Quando tiver certeza que nao precisa mais dele:"
    echo "  gcloud compute disks delete $BOOT_DISK_NAME --project=$PROJECT_ID --zone=$ZONE"
    echo "=========================================================="
    send_telegram_alert "✅ <b>GCP:</b> Upgrade da VM <b>$VM_NAME</b> concluido! IP externo $EXTERNAL_IP e interno $INTERNAL_IP mantidos. SO limpo — reconfigurar aplicacao manualmente."
else
    EXIT_CODE=$?
    echo ""
    echo "Erro no terraform apply. A instancia antiga JA FOI EXCLUIDA (disco preservado como '$BOOT_DISK_NAME')."
    echo "Corrija o erro acima e rode 'terraform apply' novamente neste diretorio com:"
    echo "  terraform apply -var \"existing_static_ip=$EXTERNAL_IP\" -var \"network_ip=$INTERNAL_IP\""
    send_telegram_alert "❌ <b>GCP:</b> Upgrade de <b>$VM_NAME</b>: instancia antiga ja foi excluida, mas o terraform apply falhou. Acao manual necessaria (disco preservado: $BOOT_DISK_NAME)."
    exit $EXIT_CODE
fi
