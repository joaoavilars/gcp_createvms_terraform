<#
.SYNOPSIS
Configura Snapshots Automáticos no GCP para uma VM

.DESCRIPTION
Cria e aplica políticas de snapshot schedule nas VMs do GCP.
Suporta frequências: diária, semanal, horária, personalizada.

MODO DE USO:
  1. Edite as variáveis abaixo (VM_NAME, PROJECT_ID, etc)
  2. Execute o script
  3. Pronto! Snapshots automáticos ativados.

REFERÊNCIA GCP:
  https://cloud.google.com/compute/docs/disks/scheduled-snapshots
#>

# ================================================================================
# CONFIGURAÇÕES - EDITE AQUI
# ================================================================================

# Nome da VM alvo
$VM_NAME        = "sidicom1"

# Projeto GCP
$PROJECT_ID     = "sidicom-453519"

# Zona da VM
$ZONE           = "us-east1-c"

# Nome da política (identificador no GCP)
$POLICY_NAME    = "snap-${VM_NAME}-diario"

# Descrição para identificação
$POLICY_DESC    = "Snapshot automático diário da VM ${VM_NAME} - retenção 7 dias"

# ================================================================================
# FREQUÊNCIA - Escolha UMA das opções abaixo (descomente a desejada)
# ================================================================================

# OPCIONAL: Descomente para configurar snapshot programado
# Parâmetros: (interval_hours, start_time, days_of_cycle)
#   - interval_hours: 6, 12, 24 (mínimo 1, mas 1 = caro em storage)
#   - start_time: hora de início no formato HH:MM (horário local)
#   - days_of_cycle: dias da semana ou mês (vazio=todos os dias)

# ---- DIÁRIO (1x por dia, às 02:00) - RECOMENDADO ----
$SCHEDULE_CONFIG = @{
    interval_hours = 24
    start_time     = "02:00"
    days_of_cycle  = @()  # vazio = todos os dias
}

# ---- A CADA 12 HORAS (2x por dia, às 07:00 e 19:00) ----
# Descomente para usar:
# $SCHEDULE_CONFIG = @{
#     interval_hours = 12
#     start_time     = "07:00"
#     days_of_cycle  = @()
# }

# ---- A CADA 6 HORAS (4x por dia) ----
# Descomente para usar:
# $SCHEDULE_CONFIG = @{
#     interval_hours = 6
#     start_time     = "00:00"
#     days_of_cycle  = @()
# }

# ---- SEMANAL (aos domingos) ----
# Descomente para usar:
# $SCHEDULE_CONFIG = @{
#     interval_hours = 24
#     start_time     = "03:00"
#     days_of_cycle  = @("sunday")
# }

# ================================================================================
# RETENÇÃO (quanto tempo manter os snapshots)
# ================================================================================
# Opções: 3, 7, 14, 30 dias
$MAX_RETENTION_DAYS     = 7
# Máximo de snapshots mantidos (0 = sem limite, usa apenas max_retention_days)
$MAX_SNAPSHOTS_KEPT     = 0

# ================================================================================
# RÓTULOS (labels) para organização
# ================================================================================
$LABELS = @{
    vm        = $VM_NAME
    managed   = "snapshot-policy"
    retention = "${MAX_RETENTION_DAYS}dias"
}

# ================================================================================
# FIM DAS CONFIGURAÇÕES
# ================================================================================

$RED    = "`e[31m"
$GREEN  = "`e[32m"
$YELLOW = "`e[33m"
$CYAN   = "`e[36m"
$NC     = "`e[0m"

Write-Host "${YELLOW}================================================${NC}"
Write-Host "${YELLOW}CONFIGURAÇÃO DE SNAPSHOTS AUTOMÁTICOS${NC}"
Write-Host "${YELLOW}================================================${NC}"

# Validar gcloud
$gcloudCheck = gcloud --version 2>$null
if (-not $gcloudCheck) {
    Write-Host "${RED}[ERRO] gcloud CLI não encontrado. Instale e autentique primeiro.${NC}"
    exit 1
}

# Verificar autenticação
$authCheck = gcloud auth application-default print-access-token 2>$null
if (-not $authCheck) {
    Write-Host "${RED}[ERRO] Execute 'gcloud auth application-default login' primeiro.${NC}"
    exit 1
}

Write-Host "`n${CYAN}Dados da configuração:${NC}"
Write-Host "  VM:     ${GREEN}$VM_NAME${NC}"
Write-Host "  Projeto:${GREEN}$PROJECT_ID${NC}"
Write-Host "  Zona:   ${GREEN}$ZONE${NC}"
Write-Host "  Política:${GREEN}$POLICY_NAME${NC}"
Write-Host "  Frequência: ${GREEN}a cada $($SCHEDULE_CONFIG.interval_hours) horas${NC}"
Write-Host "  Início: ${GREEN}$($SCHEDULE_CONFIG.start_time)${NC}"
Write-Host "  Retenção: ${GREEN}$MAX_RETENTION_DAYS dias${NC}"

# Confirmar
$confirm = Read-Host "`nDigite 'SIM' para criar a política de snapshots"

if ($confirm -ne "SIM") {
    Write-Host "${YELLOW}[CANCELADO]${NC}"
    exit 0
}

Write-Host "`n${CYAN}Criando política de snapshot...${NC}"

# Monta o comando gcloud
$daysArg = ""
if ($SCHEDULE_CONFIG.days_of_cycle.Count -gt 0) {
    $daysArg = "--days-of-cycle=$($SCHEDULE_CONFIG.days_of_cycle -join ',')"
}

$snapshotCountArg = ""
if ($MAX_SNAPSHOTS_KEPT -gt 0) {
    $snapshotCountArg = "--max-snapshot-count=$MAX_SNAPSHOTS_KEPT"
}

$cmd = "gcloud compute resource-policies create snapshot-schedule $POLICY_NAME " +
       "--project=$PROJECT_ID " +
       "--region=$($ZONE.Substring(0, $ZONE.LastIndexOf('-'))) " +
       "--description=`"$POLICY_DESC`" " +
       "--snapshot-labels=vm=$VM_NAME,retention=${MAX_RETENTION_DAYS}dias " +
       "--max-retention-days=$MAX_RETENTION_DAYS " +
       "$snapshotCountArg " +
       "--start-time=$($SCHEDULE_CONFIG.start_time):00 " +
       "--hourly-schedule=$($SCHEDULE_CONFIG.interval_hours) $daysArg"

Write-Host "`n${YELLOW}Comando:${NC}"
Write-Host "$cmd`n"

Invoke-Expression $cmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "${GREEN}[OK] Política criada com sucesso!${NC}"
} else {
    Write-Host "${RED}[ERRO] Falha ao criar política. Pode já existir. Verifique:${NC}"
    Write-Host "${YELLOW}gcloud compute resource-policies list --project=$PROJECT_ID${NC}"
}

# Descobre o disco de boot da VM
Write-Host "`n${CYAN}Descobrindo disco da VM $VM_NAME...${NC}"
$diskInfo = gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT_ID --format="json" 2>$null | ConvertFrom-Json

if (-not $diskInfo) {
    Write-Host "${RED}[ERRO] VM '$VM_NAME' não encontrada ou sem permissão.${NC}"
    Write-Host "${YELLOW}Verifique o nome e projeto.${NC}"
    exit 1
}

$bootDiskName = $diskInfo.disks[0].source -split '/' | Select-Object -Last 1
Write-Host "  Disco de boot: ${GREEN}$bootDiskName${NC}"

Write-Host "`n${CYAN}Aplicando política ao disco...${NC}"
gcloud compute disks add-resource-policies $bootDiskName `
    --resource-policies=$POLICY_NAME `
    --zone=$ZONE `
    --project=$PROJECT_ID

if ($LASTEXITCODE -eq 0) {
    Write-Host "${GREEN}[OK] Política aplicada ao disco '$bootDiskName'!${NC}"
} else {
    Write-Host "${RED}[ERRO] Falha ao aplicar política.${NC}"
    exit 1
}

# ================================================================================
# RESUMO FINAL
# ================================================================================
Write-Host "`n${GREEN}================================================${NC}"
Write-Host "${GREEN}✅ SNAPSHOTS AUTOMÁTICOS CONFIGURADOS!${NC}"
Write-Host "${GREEN}================================================${NC}"
Write-Host "VM:          ${CYAN}$VM_NAME${NC}"
Write-Host "Disco:       ${CYAN}$bootDiskName${NC}"
Write-Host "Frequência:  ${CYAN}a cada $($SCHEDULE_CONFIG.interval_hours) horas${NC}"
Write-Host "Início:      ${CYAN}$($SCHEDULE_CONFIG.start_time)${NC}"
Write-Host "Retenção:    ${CYAN}$MAX_RETENTION_DAYS dias${NC}"
Write-Host "Política:    ${CYAN}$POLICY_NAME${NC}"

Write-Host "`n${YELLOW}COMANDOS ÚTEIS:${NC}"
Write-Host "  Listar políticas:       gcloud compute resource-policies list --project=$PROJECT_ID"
Write-Host "  Listar snapshots:       gcloud compute snapshots list --project=$PROJECT_ID --filter=vm=$VM_NAME"
Write-Host "  Remover política:       gcloud compute disks remove-resource-policies $bootDiskName --resource-policies=$POLICY_NAME --zone=$ZONE --project=$PROJECT_ID"
Write-Host "  Descrever snapshot:     gcloud compute snapshots describe NOME-DO-SNAPSHOT --project=$PROJECT_ID"

Write-Host "`n${GREEN}Pronto! Os snapshots serão gerados automaticamente.${NC}"
