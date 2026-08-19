<#
.SYNOPSIS
Script para REMOVER uma VM do controle do Terraform sem destruí-la no GCP.

.DESCRIPTION
Este script remove recursos do terraform.tfstate, liberando o Terraform
para gerenciar uma VM DIFERENTE, mas SEM destruir a VM atual no GCP.

ATENÇÃO: Use APENAS quando:
- A VM atual já foi criada e está funcionando
- Você quer criar/gerenciar uma VM DIFERENTE
- Você NÃO quer mais que o Terraform gerencie a VM atual

Após executar este script, o Terraform NÃO conseguirá mais modificar
ou destruir a VM antiga. Ela ficará "órfã" no GCP.
#>

$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$CYAN = "`e[36m"
$NC = "`e[0m"

Write-Host "${YELLOW}================================================${NC}"
Write-Host "${YELLOW}RESET DO STATE - REMOVER VM DO CONTROLE TERRAFORM${NC}"
Write-Host "${YELLOW}================================================${NC}"

# Verifica se existe state
if (!(Test-Path "terraform.tfstate")) {
    Write-Host "${GREEN}Nenhum state encontrado. Terraform já está limpo.${NC}"
    exit 0
}

# Mostra o que está no state atual
Write-Host "`n${CYAN}Recursos atualmente gerenciados pelo Terraform:${NC}`n"
terraform state list

if ($LASTEXITCODE -ne 0) {
    Write-Host "${RED}[ERRO] Falha ao listar state.${NC}"
    exit 1
}

# Extrai informações do state
$stateContent = Get-Content "terraform.tfstate" -Raw | ConvertFrom-Json
$currentProject = $stateContent.resources | Where-Object { $_.type -eq "google_compute_instance" } | Select-Object -ExpandProperty instances -First 1 | Select-Object -ExpandProperty attributes | Select-Object -ExpandProperty project
$currentVM = $stateContent.resources | Where-Object { $_.type -eq "google_compute_instance" } | Select-Object -ExpandProperty instances -First 1 | Select-Object -ExpandProperty attributes | Select-Object -ExpandProperty name

if ($currentProject -and $currentVM) {
    Write-Host "`n${YELLOW}VM atual no state:${NC}"
    Write-Host "  Projeto: ${CYAN}$currentProject${NC}"
    Write-Host "  VM:      ${CYAN}$currentVM${NC}"
}

Write-Host "`n${RED}ATENÇÃO:${NC}"
Write-Host "- A VM ${CYAN}$currentVM${NC} ${RED}NÃO será destruída no GCP${NC}"
Write-Host "- Ela apenas ${RED}DEIXARÁ de ser gerenciada${NC} pelo Terraform"
Write-Host "- Você ${RED}NÃO conseguirá modificar/destruir${NC} esta VM via Terraform depois"
Write-Host "- O Terraform ficará ${GREEN}livre para criar/gerenciar VM nova${NC}"

Write-Host "`n${YELLOW}Backup do state será criado em: terraform.tfstate.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')${NC}"

$confirmation = Read-Host "`nDigite 'REMOVER' (maiúsculo) para confirmar a remoção do state"

if ($confirmation -ne "REMOVER") {
    Write-Host "${YELLOW}[CANCELADO] Operação cancelada.${NC}"
    exit 0
}

# Faz backup do state atual
$backupName = "terraform.tfstate.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item "terraform.tfstate" $backupName
Write-Host "${GREEN}Backup criado: $backupName${NC}"

# Remove todos os recursos do state
Write-Host "`n${CYAN}Removendo recursos do state...${NC}"
$resources = terraform state list
foreach ($resource in $resources) {
    Write-Host "Removendo: $resource"
    terraform state rm $resource
}

Write-Host "`n${GREEN}================================================${NC}"
Write-Host "${GREEN}STATE LIMPO COM SUCESSO!${NC}"
Write-Host "${GREEN}================================================${NC}"
Write-Host "Próximos passos:"
Write-Host "1. Edite ${CYAN}terraform.tfvars${NC} com dados da NOVA VM"
Write-Host "2. Execute ${CYAN}.\deploy_vm.ps1${NC} para criar a nova VM"
Write-Host "`nA VM ${CYAN}$currentVM${NC} continua rodando no GCP, mas fora do controle do Terraform.${NC}"
