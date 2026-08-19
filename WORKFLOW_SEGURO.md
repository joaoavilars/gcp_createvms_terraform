# 🛡️ WORKFLOW SEGURO - Terraform GCP VMs

## ⚠️ PROTEÇÕES IMPLEMENTADAS

### 1. **Proteção contra destruição acidental**
- `prevent_destroy = true` em `main.tf` bloqueia destruição de VMs e IPs
- Scripts **SEMPRE** executam `terraform plan` antes de apply
- Confirmação **MANUAL OBRIGATÓRIA** digitando "SIM"

### 2. **Exibição clara do que será feito**
- Plan mostra:
  - `+` recursos que serão **CRIADOS**
  - `~` recursos que serão **MODIFICADOS**
  - `-` recursos que serão **DESTRUÍDOS** ⚠️

### 3. **Validação de projeto e VM**
- Scripts exibem projeto e VM de destino ANTES de executar
- Você confirma visualmente antes de qualquer mudança

---

## 📋 WORKFLOW CORRETO

### **Cenário 1: Criar PRIMEIRA VM**

```powershell
# 1. Edite terraform.tfvars com dados da VM
# 2. Execute deploy
.\deploy_vm.ps1

# 3. Revise o plan mostrado
# 4. Digite "SIM" para confirmar
# 5. VM criada com sucesso!
```

---

### **Cenário 2: Criar SEGUNDA VM (projeto/VM diferente)**

```powershell
# 1. Edite terraform.tfvars com dados da NOVA VM
project_id = "consigaz-270221"
vm_name = "consigazprod"
# ... outras configs

# 2. Execute deploy normalmente
.\deploy_vm.ps1

# O próprio script detecta que o state aponta para uma VM diferente e:
# - Avisa: "VM ANTERIOR DETECTADA NO STATE - REMOVENDO AUTOMATICAMENTE"
# - Faz backup do state (terraform.tfstate.backup-YYYYMMDD-HHMMSS)
# - Remove a VM antiga do state (state rm) — ela NÃO é destruída no GCP,
#   apenas deixa de ser gerenciada pelo Terraform
# - Segue para o plan/apply normalmente

# 3. Revise o plan, digite "SIM"
# 4. Nova VM criada!
```

> Não é mais necessário rodar `reset_state.ps1`/`reset_state.sh` manualmente antes de criar
> uma VM diferente — `deploy_vm` faz isso sozinho, pois o propósito do script é sempre
> criar uma VM nova. Os scripts `reset_state.*` continuam disponíveis para uso manual,
> caso você queira "soltar" uma VM do controle do Terraform sem rodar um deploy em seguida.

---

### **Cenário 3: Modificar VM EXISTENTE (mesma VM)**

```powershell
# 1. Edite terraform.tfvars alterando APENAS configs (RAM, disco, etc)
# NÃO mude project_id ou vm_name

# 2. Execute deploy
.\deploy_vm.ps1

# 3. Plan mostra "~" (modificação) na VM existente
# 4. Digite "SIM" para aplicar mudanças
```

---

## 🚨 ATENÇÃO: SITUAÇÕES DE RISCO

### ✅ **Fluxo atual:**
```powershell
# Editar tfvars com os dados da VM (nova ou existente)
.\deploy_vm.ps1    # <- detecta e limpa state antigo sozinho, se necessário
```

> Antes o processo exigia rodar `reset_state.ps1` manualmente antes de trocar de VM,
> sob risco de o `deploy_vm.ps1` tentar destruir a VM antiga. Isso não é mais necessário:
> o próprio `deploy_vm.ps1`/`.sh` remove a VM anterior do state automaticamente (com aviso
> e backup) antes de criar a nova.

---

## 🔍 COMO LER O PLAN

```
Terraform will perform the following actions:

  # google_compute_instance.vm_instance will be created
  + resource "google_compute_instance" "vm_instance" {
      ✅ SEGURO - VM será CRIADA

  # google_compute_instance.vm_instance will be updated in-place
  ~ resource "google_compute_instance" "vm_instance" {
      ✅ SEGURO - VM será MODIFICADA (sem destruir)

  # google_compute_instance.vm_instance will be destroyed
  - resource "google_compute_instance" "vm_instance" {
      ⚠️ PERIGO - VM será DESTRUÍDA
      
  # google_compute_instance.vm_instance must be replaced
-/+ resource "google_compute_instance" "vm_instance" {
      ⚠️ PERIGO - VM será DESTRUÍDA e RECRIADA
```

**Se ver `-` ou `-/+`:** CANCELE e execute `reset_state.ps1` primeiro!

---

## 🛠️ COMANDOS ÚTEIS

### Verificar state atual
```powershell
terraform state list
terraform show
```

### Listar VMs no GCP
```powershell
gcloud compute instances list --project=SEU-PROJETO
```

### Recuperar de backup do state
```powershell
# Se fez besteira, restaura backup
Copy-Item terraform.tfstate.backup-YYYYMMDD-HHMMSS terraform.tfstate -Force
```

---

## 📞 EMERGÊNCIA: VM FOI DESTRUÍDA

1. **Verifique backups automáticos do GCP** (se configurado)
2. **Verifique snapshots de disco** no console GCP
3. **Restaure de backup manual** (se tiver)
4. **Entre em contato com suporte GCP** para possível recuperação

**Lição:** Sempre configure snapshots automáticos para VMs críticas!

---

## ✅ CHECKLIST PRÉ-DEPLOY

- [ ] Li o `terraform plan` completamente
- [ ] Verifiquei se NÃO há recursos com `-` (destruição)
- [ ] Confirmei projeto e VM de destino
- [ ] Se mudei projeto/VM, executei `reset_state.ps1` ANTES
- [ ] Tenho backup da VM atual (se aplicável)

**Só digite "SIM" se TODOS os itens estiverem ✅**
