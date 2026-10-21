<#
.SYNOPSIS
Script para provisionar VMs no GCP via Terraform e notificar via Telegram.

.DESCRIPTION
Le as variaveis (incluindo workspace_name) do arquivo terraform.tfvars,
valida o ambiente (login do gcloud, projeto, nomes ja em uso), seleciona/cria
o Terraform Workspace correspondente (isolando o state desta VM do state de
qualquer outra), gera um plano, mostra um resumo e SEMPRE pede confirmacao
antes de aplicar. Alteracoes/exclusoes exigem a flag -AllowDestructive e
uma confirmacao explicita digitada (CONFIRMAR).

.PARAMETER AllowDestructive
Permite prosseguir mesmo se o plano contiver updates/deletes, mediante
confirmacao explicita digitada no terminal.

.PARAMETER PlanOnly
Executa as validacoes e mostra o plano resumido, mas NAO aplica nada
(nem pede confirmacao). Nao envia alertas para o Telegram.
#>

param(
    [switch]$AllowDestructive,
    [switch]$PlanOnly
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

# Le uma variavel string do tfvars (ignora linhas comentadas)
function Get-TfvarString {
    param([string]$Name)
    $m = Select-String -Path $tfvarsPath -Pattern ('(?im)^\s*' + $Name + '\s*=\s*"([^"]+)"')
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return ""
}

# Extrair as variaveis do Telegram e do Workspace
$enableAlerts = $false
try {
    $enableMatch = (Select-String -Path $tfvarsPath -Pattern '(?i)enable_telegram_alerts\s*=\s*(true|false)').Matches.Groups[1].Value
    if ($enableMatch -eq "true") { $enableAlerts = $true }
} catch {
    $enableAlerts = $false
}
# Simulacao nao deve gerar ruido no Telegram
if ($PlanOnly) { $enableAlerts = $false }

$botToken = ""
$chatId = ""
try {
    $botToken = (Select-String -Path $tfvarsPath -Pattern 'telegram_bot_token\s*=\s*"([^"]+)"').Matches.Groups[1].Value
    $chatId = (Select-String -Path $tfvarsPath -Pattern 'telegram_chat_id\s*=\s*"([^"]+)"').Matches.Groups[1].Value
} catch {}

$workspaceName = Get-TfvarString 'workspace_name'
$projectId     = Get-TfvarString 'project_id'
$vmName        = Get-TfvarString 'vm_name'

if ([string]::IsNullOrWhiteSpace($workspaceName)) {
    Write-Host "Erro: 'workspace_name' nao definido em $tfvarsPath." -ForegroundColor Red
    Write-Host "Defina um nome unico de workspace para esta VM (ou 'default' para a VM classica ja existente)." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($projectId) -or [string]::IsNullOrWhiteSpace($vmName)) {
    Write-Host "Erro: 'project_id' e 'vm_name' precisam estar definidos em $tfvarsPath." -ForegroundColor Red
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

# ----------------------------------------------------------------------
# Pre-checagens (somente leitura no GCP)
# ----------------------------------------------------------------------
$warnings = @()
$hasGcloud = [bool](Get-Command gcloud -ErrorAction SilentlyContinue)

Write-Host "Alvo: projeto '$projectId' | VM '$vmName' | workspace '$workspaceName'" -ForegroundColor Cyan

if ($hasGcloud) {
    $out = & gcloud projects describe $projectId --format="value(projectId)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro: gcloud sem acesso ao projeto '$projectId'." -ForegroundColor Red
        Write-Host "Rode 'gcloud auth login' ou confira o project_id no tfvars." -ForegroundColor Red
        ($out | Select-Object -First 3) | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        exit 1
    }
} else {
    $warnings += "gcloud nao encontrado no PATH: nao foi possivel checar projeto nem nomes ja em uso."
}

$expectedWorkspace = "$projectId-$vmName"
if ($workspaceName -ne $expectedWorkspace -and $workspaceName -ne "default") {
    $warnings += "workspace_name '$workspaceName' foge do padrao '$expectedWorkspace'. Nomes genericos podem ser reaproveitados por outra VM."
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

# Se a VM ainda nao e gerenciada por este workspace, ela nao pode existir no projeto
$alreadyManaged = (& terraform state list 2>$null) -contains 'google_compute_instance.vm_instance'
if ($hasGcloud -and -not $alreadyManaged) {
    $ipName = "$vmName-static-ip"

    $vmFound = & gcloud compute instances list --project $projectId --filter="name=$vmName" --format="value(name,zone.basename())" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro ao listar VMs do projeto '$projectId':" -ForegroundColor Red
        ($vmFound | Select-Object -First 3) | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        exit 1
    }
    if ($vmFound) {
        Write-Host "Erro: ja existe uma VM chamada '$vmName' no projeto '$projectId' ($vmFound)." -ForegroundColor Red
        Write-Host "Escolha outro vm_name. Nada foi alterado." -ForegroundColor Red
        exit 1
    }

    $ipFound = & gcloud compute addresses list --project $projectId --filter="name=$ipName" --format="value(name,region.basename())" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro ao listar IPs do projeto '$projectId':" -ForegroundColor Red
        ($ipFound | Select-Object -First 3) | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        exit 1
    }
    if ($ipFound) {
        Write-Host "Erro: ja existe um IP chamado '$ipName' no projeto '$projectId' ($ipFound)." -ForegroundColor Red
        Write-Host "Escolha outro vm_name. Nada foi alterado." -ForegroundColor Red
        exit 1
    }
}

foreach ($w in $warnings) { Write-Host "AVISO: $w" -ForegroundColor Yellow }

Write-Host "Iniciando provisionamento..." -ForegroundColor Cyan
Send-TelegramAlert -Message "🚀 <b>GCP:</b> Inicio do processo de provisionamento (workspace: <b>$workspaceName</b>)..."

$planFile = [System.IO.Path]::GetTempFileName()
$planJsonFile = [System.IO.Path]::GetTempFileName()

try {
    Write-Host "Calculando plano (terraform plan)..." -ForegroundColor Cyan
    & terraform plan -input=false "-out=$planFile"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro ao gerar o plano do Terraform." -ForegroundColor Red
        Send-TelegramAlert -Message "❌ <b>GCP:</b> Erro ao gerar o plano do Terraform (workspace: $workspaceName)."
        exit 1
    }

    & terraform show -json $planFile | Out-File -Encoding utf8 $planJsonFile
    $planData = Get-Content $planJsonFile -Raw | ConvertFrom-Json

    $creates = @()
    $destructive = @()
    foreach ($rc in $planData.resource_changes) {
        $actions = $rc.change.actions
        if ($actions -contains "update" -or $actions -contains "delete") {
            $destructive += "  - $($rc.address) ($($actions -join ','))"
        }
        if ($actions -contains "create") {
            $after = $rc.change.after
            $detail = ""
            if ($rc.type -eq "google_compute_instance") {
                $disk = $after.boot_disk[0].initialize_params[0]
                $detail = " [nome=$($after.name), tipo=$($after.machine_type), zona=$($after.zone), boot=$($disk.size)GB $($disk.type)]"
            } elseif ($rc.type -eq "google_compute_address") {
                $detail = " [nome=$($after.name), regiao=$($after.region)]"
            } elseif ($rc.type -eq "google_compute_disk") {
                $detail = " [nome=$($after.name), tamanho=$($after.size)GB, tipo=$($after.type)]"
            }
            $creates += "  + $($rc.address)$detail"
        }
    }

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "RESUMO DO PLANO  (projeto: $projectId | workspace: $workspaceName)" -ForegroundColor Cyan
    if ($creates.Count -gt 0) {
        Write-Host "Serao CRIADOS:" -ForegroundColor Green
        $creates | ForEach-Object { Write-Host $_ -ForegroundColor Green }
    }
    if ($destructive.Count -gt 0) {
        Write-Host "TRAVA DE SEGURANCA: o plano contem alteracao(oes) ou exclusao(oes):" -ForegroundColor Yellow
        $destructive | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($creates.Count -eq 0 -and $destructive.Count -eq 0) {
        Write-Host "Nenhuma mudanca no plano. Nada a aplicar." -ForegroundColor Green
        exit 0
    }

    if ($PlanOnly) {
        if ($destructive.Count -gt 0) {
            Write-Host "-PlanOnly: nada foi aplicado. Um deploy real seria BLOQUEADO sem -AllowDestructive." -ForegroundColor Yellow
        } else {
            Write-Host "-PlanOnly: nada foi aplicado." -ForegroundColor Green
        }
        exit 0
    }

    if ($destructive.Count -gt 0) {
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
    } else {
        $confirmation = Read-Host "Digite SIM (maiusculo) para criar os recursos acima"
        if ($confirmation -ne "SIM") {
            Write-Host "Confirmacao nao recebida. Apply cancelado." -ForegroundColor Red
            Send-TelegramAlert -Message "🛑 <b>GCP:</b> Apply cancelado pelo usuario na confirmacao (workspace: $workspaceName)."
            exit 1
        }
    }

    Write-Host "Executando terraform apply..." -ForegroundColor Cyan
    & terraform apply -input=false $planFile
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Terraform finalizado com sucesso." -ForegroundColor Green
        Send-TelegramAlert -Message "✅ <b>GCP:</b> Sucesso! Criacao/atualizacao concluida (workspace: $workspaceName)."
    } else {
        Write-Host "Ocorreram erros durante o Terraform." -ForegroundColor Red
        Send-TelegramAlert -Message "❌ <b>GCP:</b> Erro! Ocorreram erros durante o apply (workspace: $workspaceName)."
        exit $LASTEXITCODE
    }
} finally {
    Remove-Item -Force $planFile, $planJsonFile -ErrorAction SilentlyContinue
}
