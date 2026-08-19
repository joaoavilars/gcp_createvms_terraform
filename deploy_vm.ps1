<#
.SYNOPSIS
Script para provisionar VMs no GCP via Terraform e notificar via Telegram.

.DESCRIPTION
Le as variaveis (incluindo workspace_name) do arquivo terraform.tfvars,
seleciona/cria o Terraform Workspace correspondente (isolando o state
desta VM do state de qualquer outra), gera um plano e SO aplica se o
plano for 100% criacao de recursos novos. Alteracoes/exclusoes exigem
a flag -AllowDestructive e uma confirmacao explicita digitada.

.PARAMETER AllowDestructive
Permite prosseguir mesmo se o plano contiver updates/deletes, mediante
confirmacao explicita digitada no terminal.
#>

param(
    [switch]$AllowDestructive
)

$tfvarsPath = "terraform.tfvars"

if (!(Test-Path $tfvarsPath)) {
    Write-Host "Arquivo $tfvarsPath nao encontrado!" -ForegroundColor Red
    exit 1
}

foreach ($cmd in @("terraform")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "Erro: comando '$cmd' nao encontrado no PATH." -ForegroundColor Red
        exit 1
    }
}

# Extrair as variaveis do Telegram e do Workspace
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

$workspaceName = ""
try {
    $workspaceName = (Select-String -Path $tfvarsPath -Pattern '(?im)^\s*workspace_name\s*=\s*"([^"]+)"').Matches.Groups[1].Value
} catch {}

if ([string]::IsNullOrWhiteSpace($workspaceName)) {
    Write-Host "Erro: 'workspace_name' nao definido em $tfvarsPath." -ForegroundColor Red
    Write-Host "Defina um nome unico de workspace para esta VM (ou 'default' para a VM classica ja existente)." -ForegroundColor Red
    exit 1
}

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

Write-Host "Selecionando workspace do Terraform: $workspaceName" -ForegroundColor Cyan
& terraform workspace select $workspaceName 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Workspace '$workspaceName' nao existe ainda. Criando (state isolado, nao afeta outras VMs)..." -ForegroundColor Yellow
    & terraform workspace new $workspaceName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro ao criar o workspace '$workspaceName'." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Iniciando provisionamento..." -ForegroundColor Cyan
Send-TelegramAlert -Message "🚀 <b>GCP:</b> Inicio do processo de provisionamento (workspace: <b>$workspaceName</b>)..."

$planFile = New-TemporaryFile
$planJsonFile = New-TemporaryFile

try {
    Write-Host "Calculando plano (terraform plan)..." -ForegroundColor Cyan
    & terraform plan -input=false -out=$planFile.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro ao gerar o plano do Terraform." -ForegroundColor Red
        Send-TelegramAlert -Message "❌ <b>GCP:</b> Erro ao gerar o plano do Terraform (workspace: $workspaceName)."
        exit 1
    }

    & terraform show -json $planFile.FullName | Out-File -Encoding utf8 $planJsonFile.FullName
    $planData = Get-Content $planJsonFile.FullName -Raw | ConvertFrom-Json

    $destructive = @()
    foreach ($rc in $planData.resource_changes) {
        if ($rc.change.actions -contains "update" -or $rc.change.actions -contains "delete") {
            $destructive += "  - $($rc.address) ($($rc.change.actions -join ','))"
        }
    }

    if ($destructive.Count -gt 0) {
        Write-Host "------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "TRAVA DE SEGURANCA: o plano contem alteracao(oes) ou exclusao(oes):" -ForegroundColor Yellow
        $destructive | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
        Write-Host "------------------------------------------------------" -ForegroundColor Yellow

        if (-not $AllowDestructive) {
            Write-Host "Este script e apenas para CRIACAO. Apply cancelado." -ForegroundColor Red
            Write-Host "Se for intencional, rode novamente com -AllowDestructive." -ForegroundColor Red
            Send-TelegramAlert -Message "🛑 <b>GCP:</b> Apply BLOQUEADO (workspace: $workspaceName) -- plano tentava alterar/excluir recursos."
            exit 1
        }

        $confirmation = Read-Host "Digite CONFIRMAR para prosseguir com estas alteracoes/exclusoes"
        if ($confirmation -ne "CONFIRMAR") {
            Write-Host "Confirmacao nao recebida. Apply cancelado." -ForegroundColor Red
            Send-TelegramAlert -Message "🛑 <b>GCP:</b> Apply cancelado pelo usuario na confirmacao (workspace: $workspaceName)."
            exit 1
        }
        Send-TelegramAlert -Message "⚠️ <b>GCP:</b> Apply com alteracoes/exclusoes CONFIRMADO manualmente (workspace: $workspaceName)."
    }

    Write-Host "Executando terraform apply..." -ForegroundColor Cyan
    & terraform apply -input=false $planFile.FullName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Terraform finalizado com sucesso." -ForegroundColor Green
        Send-TelegramAlert -Message "✅ <b>GCP:</b> Sucesso! Criacao/atualizacao concluida (workspace: $workspaceName)."
    } else {
        Write-Host "Ocorreram erros durante o Terraform." -ForegroundColor Red
        Send-TelegramAlert -Message "❌ <b>GCP:</b> Erro! Ocorreram erros durante o apply (workspace: $workspaceName)."
        exit $LASTEXITCODE
    }
} finally {
    Remove-Item -Force $planFile.FullName, $planJsonFile.FullName -ErrorAction SilentlyContinue
}
