<#
.SYNOPSIS
Script para provisionar VMs no GCP via Terraform e notificar via Telegram.

.DESCRIPTION
Lê as variáveis do Telegram do arquivo terraform.tfvars, 
notifica o início do processo, executa o terraform apply
e notifica o sucesso ou erro.
#>

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

# Executa o Terraform
Write-Host "Executando terraform apply..." -ForegroundColor Cyan
$terraformProcess = Start-Process -FilePath "terraform" -ArgumentList "apply", "-auto-approve" -Wait -NoNewWindow -PassThru

if ($terraformProcess.ExitCode -eq 0) {
    Write-Host "Terraform finalizado com sucesso." -ForegroundColor Green
    Send-TelegramAlert -Message "✅ <b>GCP:</b> Sucesso! Criação e início da VM concluídos com êxito."
} else {
    Write-Host "Ocorreram erros durante o Terraform." -ForegroundColor Red
    Send-TelegramAlert -Message "❌ <b>GCP:</b> Erro! Ocorreram erros durante o provisionamento ou criação da VM."
    exit $terraformProcess.ExitCode
}
