<#
.SYNOPSIS
Script para provisionar VMs no GCP via Terraform e notificar via Telegram.

.DESCRIPTION
Lê as variáveis do Telegram do arquivo terraform.tfvars, 
notifica o início do processo, executa o terraform apply
e notifica o sucesso ou erro.
#>

$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$CYAN = "`e[36m"
$NC = "`e[0m"

$tfvarsPath = "terraform.tfvars"

if (!(Test-Path $tfvarsPath)) {
    Write-Host "Arquivo $tfvarsPath não encontrado!" -ForegroundColor Red
    exit 1
}

# Extrair as variáveis do Telegram
$enableAlerts = $false
try {
    $enableMatch = (Select-String -Path $tfvarsPath -Pattern '(?i)enable_telegram_alerts\s*=\s*(true|false)').Matches.Groups[1].Value
    if ($enableMatch -eq "true") { $enableAlerts = $true }
} catch {
    $enableAlerts = $false
}

$botToken = ""
$chatId = ""
try {
    $botToken = (Select-String -Path $tfvarsPath -Pattern 'telegram_bot_token\s*=\s*"([^"]+)"').Matches.Groups[1].Value
    $chatId = (Select-String -Path $tfvarsPath -Pattern 'telegram_chat_id\s*=\s*"([^"]+)"').Matches.Groups[1].Value
} catch {}

function Send-TelegramAlert {
    param([string]$Message)

    if ($enableAlerts -and $botToken -and $chatId) {
        $url = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{
            chat_id = $chatId
            text = $Message
            parse_mode = "HTML"
        }
        try {
            Invoke-RestMethod -Uri $url -Method Post -Body $body > $null
        } catch {
            Write-Host "Falha ao enviar alerta para o Telegram." -ForegroundColor Yellow
        }
    }
}

Write-Host "Iniciando provisionamento..." -ForegroundColor Cyan
Send-TelegramAlert -Message "🚀 <b>GCP:</b> Início do processo de provisionamento da VM pelo Terraform..."

# ========================================
# VALIDAÇÕES DE SEGURANÇA
# ========================================

# Extrai dados do tfvars
$projectId = (Select-String -Path $tfvarsPath -Pattern 'project_id\s*=\s*"([^"]+)"').Matches.Groups[1].Value
$vmName = (Select-String -Path $tfvarsPath -Pattern 'vm_name\s*=\s*"([^"]+)"').Matches.Groups[1].Value

# Verifica se existe state anterior
if (Test-Path "terraform.tfstate") {
    $stateContent = Get-Content "terraform.tfstate" -Raw | ConvertFrom-Json
    
    # Extrai projeto e VM do state
    $stateProject = $null
    $stateVM = $null
    
    foreach ($resource in $stateContent.resources) {
        if ($resource.type -eq "google_compute_instance") {
            $stateProject = $resource.instances[0].attributes.project
            $stateVM = $resource.instances[0].attributes.name
            break
        }
    }
    
    # Se state tem VM diferente, remove automaticamente (o script só cria VMs novas)
    if ($stateProject -and $stateVM) {
        if ($stateProject -ne $projectId -or $stateVM -ne $vmName) {
            Write-Host "`n${YELLOW}================================================================${NC}"
            Write-Host "${YELLOW}  VM ANTERIOR DETECTADA NO STATE - REMOVENDO AUTOMATICAMENTE${NC}"
            Write-Host "${YELLOW}================================================================${NC}"
            Write-Host "`n${CYAN}State atual gerenciava:${NC}"
            Write-Host "  Projeto: ${CYAN}$stateProject${NC}"
            Write-Host "  VM:      ${CYAN}$stateVM${NC}"
            Write-Host "`n${CYAN}Nova VM solicitada:${NC}"
            Write-Host "  Projeto: ${CYAN}$projectId${NC}"
            Write-Host "  VM:      ${CYAN}$vmName${NC}"
            Write-Host "`n${GREEN}A VM '$stateVM' NÃO será destruída no GCP.${NC} Ela apenas deixará de ser gerenciada pelo Terraform, liberando o state para criar a VM nova."

            $backupName = "terraform.tfstate.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item "terraform.tfstate" $backupName
            Write-Host "${CYAN}Backup do state salvo em: $backupName${NC}"

            Write-Host "`n${CYAN}Removendo recursos antigos do state...${NC}"
            $oldResources = terraform state list
            foreach ($resource in $oldResources) {
                Write-Host "Removendo: $resource"
                terraform state rm $resource
            }
            Write-Host "${GREEN}State limpo. Prosseguindo para criar a VM nova.${NC}`n"
        }
    }
}

Write-Host "`n================================================" -ForegroundColor Yellow
Write-Host "VERIFICAÇÃO DE SEGURANÇA - TERRAFORM PLAN" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "Projeto destino: $projectId" -ForegroundColor Cyan
Write-Host "VM destino: $vmName" -ForegroundColor Cyan
Write-Host "`nExecutando terraform plan para verificar mudanças...`n" -ForegroundColor Cyan

# Executa plan primeiro
terraform plan -out=tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERRO] Terraform plan falhou!" -ForegroundColor Red
    exit 1
}

Write-Host "`n================================================" -ForegroundColor Yellow
Write-Host "CONFIRMAÇÃO MANUAL OBRIGATÓRIA" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "ATENÇÃO: Revise o plano acima cuidadosamente!" -ForegroundColor Red
Write-Host "Verifique se há recursos marcados para DESTRUIÇÃO (-)" -ForegroundColor Red
Write-Host "`nProjeto: $projectId" -ForegroundColor Cyan
Write-Host "VM: $vmName`n" -ForegroundColor Cyan

$confirmation = Read-Host "Digite 'SIM' (maiúsculo) para prosseguir com apply"

if ($confirmation -ne "SIM") {
    Write-Host "`n[CANCELADO] Deploy cancelado pelo usuário." -ForegroundColor Yellow
    Remove-Item tfplan -ErrorAction SilentlyContinue
    exit 0
}

# Executa o Terraform apply com o plan gerado
Write-Host "`nExecutando terraform apply..." -ForegroundColor Cyan
terraform apply tfplan

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[SUCESSO] Terraform finalizado com sucesso." -ForegroundColor Green
    Send-TelegramAlert -Message "✅ <b>GCP:</b> Sucesso! VM '$vmName' no projeto '$projectId' criada/atualizada."
    
    # Remove o arquivo de plan
    Remove-Item tfplan -ErrorAction SilentlyContinue
} else {
    Write-Host "`n[ERRO] Ocorreram erros durante o Terraform." -ForegroundColor Red
    Send-TelegramAlert -Message "❌ <b>GCP:</b> Erro! Falha no provisionamento da VM '$vmName'."
    Remove-Item tfplan -ErrorAction SilentlyContinue
    exit $LASTEXITCODE
}
