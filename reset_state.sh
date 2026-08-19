#!/bin/bash

# Script para REMOVER uma VM do controle do Terraform sem destruí-la no GCP
#
# ATENÇÃO: Use APENAS quando:
# - A VM atual já foi criada e está funcionando
# - Você quer criar/gerenciar uma VM DIFERENTE
# - Você NÃO quer mais que o Terraform gerencie a VM atual
#
# Após executar este script, o Terraform NÃO conseguirá mais modificar
# ou destruir a VM antiga. Ela ficará "órfã" no GCP.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}RESET DO STATE - REMOVER VM DO CONTROLE TERRAFORM${NC}"
echo -e "${YELLOW}================================================${NC}"

# Verifica se existe state
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${GREEN}Nenhum state encontrado. Terraform já está limpo.${NC}"
    exit 0
fi

# Mostra o que está no state atual
echo -e "\n${CYAN}Recursos atualmente gerenciados pelo Terraform:${NC}\n"
terraform state list

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERRO] Falha ao listar state.${NC}"
    exit 1
fi

# Extrai informações do state
CURRENT_PROJECT=$(grep -o '"project":[[:space:]]*"[^"]*"' terraform.tfstate | head -1 | sed 's/"project":[[:space:]]*"\([^"]*\)"/\1/')
CURRENT_VM=$(grep -o '"name":[[:space:]]*"[^"]*"' terraform.tfstate | grep -v "static-ip" | head -1 | sed 's/"name":[[:space:]]*"\([^"]*\)"/\1/')

if [ -n "$CURRENT_PROJECT" ] && [ -n "$CURRENT_VM" ]; then
    echo -e "\n${YELLOW}VM atual no state:${NC}"
    echo -e "  Projeto: ${CYAN}$CURRENT_PROJECT${NC}"
    echo -e "  VM:      ${CYAN}$CURRENT_VM${NC}"
fi

echo -e "\n${RED}ATENÇÃO:${NC}"
echo -e "- A VM ${CYAN}$CURRENT_VM${NC} ${RED}NÃO será destruída no GCP${NC}"
echo -e "- Ela apenas ${RED}DEIXARÁ de ser gerenciada${NC} pelo Terraform"
echo -e "- Você ${RED}NÃO conseguirá modificar/destruir${NC} esta VM via Terraform depois"
echo -e "- O Terraform ficará ${GREEN}livre para criar/gerenciar VM nova${NC}"

BACKUP_NAME="terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)"
echo -e "\n${YELLOW}Backup do state será criado em: $BACKUP_NAME${NC}"

read -p $'\nDigite \'REMOVER\' (maiúsculo) para confirmar a remoção do state: ' CONFIRMATION

if [ "$CONFIRMATION" != "REMOVER" ]; then
    echo -e "${YELLOW}[CANCELADO] Operação cancelada.${NC}"
    exit 0
fi

# Faz backup do state atual
cp terraform.tfstate "$BACKUP_NAME"
echo -e "${GREEN}Backup criado: $BACKUP_NAME${NC}"

# Remove todos os recursos do state
echo -e "\n${CYAN}Removendo recursos do state...${NC}"
terraform state list | while read RESOURCE; do
    echo "Removendo: $RESOURCE"
    terraform state rm "$RESOURCE"
done

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}STATE LIMPO COM SUCESSO!${NC}"
echo -e "${GREEN}================================================${NC}"
echo "Próximos passos:"
echo -e "1. Edite ${CYAN}terraform.tfvars${NC} com dados da NOVA VM"
echo -e "2. Execute ${CYAN}./deploy_vm.sh${NC} para criar a nova VM"
echo -e "\nA VM ${CYAN}$CURRENT_VM${NC} continua rodando no GCP, mas fora do controle do Terraform.${NC}"
