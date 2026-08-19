<#
.SYNOPSIS
Script para RESTAURAR VM a partir de snapshot do GCP via Terraform.

.DESCRIPTION
Este script cria um disco de boot a partir da snapshot especificada
e provisiona uma VM nova usando esse disco restaurado.

Proteções de segurança incluídas:
- Validação pré-flight com terraform plan
- Confirmação manual obrigatória
- Notificações via Telegram
#>

$tfvarsPath = "terraform.tfvars"

if (!(Test-Path $tfvarsPath)) {
    Write-Host "Arquivo $tfvarsPath não encontrado!" -ForegroundColor Red
    exit 1
}

# Extrai variáveis do telegram
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

# Extrai dados do tfvars
$projectId = (Select-String -Path $tfvarsPath -Pattern 'project_id\s*=\s*"([^"]+)"').Matches.Groups[1].Value
$vmName = (Select-String -Path $tfvarsPath -Pattern 'vm_name\s*=\s*"([^"]+)"').Matches.Groups[1].Value
$snapshotName = (Select-String -Path $tfvarsPath -Pattern 'snapshot_name\s*=\s*"([^"]+)"').Matches.Groups[1].Value

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "RESTAURAÇÃO DE VM A PARTIR DE SNAPSHOT" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Projeto:  $projectId" -ForegroundColor Yellow
Write-Host "VM:       $vmName" -ForegroundColor Yellow
Write-Host "Snapshot: $snapshotName" -ForegroundColor Yellow
Write-Host "`nExecutando terraform plan...`n" -ForegroundColor Cyan

Send-TelegramAlert -Message "🔄 <b>GCP Restore:</b> Iniciando restauração da VM '$vmName' do snapshot '$snapshotName'..."

# Executa plan primeiro
terraform plan -out=tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERRO] Terraform plan falhou!" -ForegroundColor Red
    Send-TelegramAlert -Message "❌ <b>GCP Restore:</b> Erro no terraform plan para '$vmName'."
    exit 1
}

Write-Host "`n================================================" -ForegroundColor Yellow
Write-Host "CONFIRMAÇÃO MANUAL OBRIGATÓRIA" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "ATENÇÃO: Revise o plano acima!" -ForegroundColor Red
Write-Host "`nProjeto:  $projectId" -ForegroundColor Cyan
Write-Host "VM:       $vmName" -ForegroundColor Cyan
Write-Host "Snapshot: $snapshotName`n" -ForegroundColor Cyan

$confirmation = Read-Host "Digite 'RESTAURAR' (maiúsculo) para prosseguir"

if ($confirmation -ne "RESTAURAR") {
    Write-Host "`n[CANCELADO] Restauração cancelada." -ForegroundColor Yellow
    Remove-Item tfplan -ErrorAction SilentlyContinue
    exit 0
}

# Executa terraform apply
Write-Host "`nExecutando terraform apply..." -ForegroundColor Cyan
terraform apply tfplan

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[SUCESSO] VM restaurada com sucesso!" -ForegroundColor Green
    Send-TelegramAlert -Message "✅ <b>GCP Restore:</b> Sucesso! VM '$vmName' restaurada do snapshot '$snapshotName'."
    
    # Mostra outputs
    Write-Host "`n================================================" -ForegroundColor Green
    Write-Host "INFORMAÇÕES DA VM RESTAURADA" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    terraform output
    
    Remove-Item tfplan -ErrorAction SilentlyContinue
} else {
    Write-Host "`n[ERRO] Falha na restauração." -ForegroundColor Red
    Send-TelegramAlert -Message "❌ <b>GCP Restore:</b> Erro ao restaurar VM '$vmName'."
    Remove-Item tfplan -ErrorAction SilentlyContinue
    exit $LASTEXITCODE
}
