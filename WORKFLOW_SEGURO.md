# 🛡️ WORKFLOW SEGURO - Terraform GCP VMs

## ⚠️ PROTEÇÕES IMPLEMENTADAS

### 1. **Isolamento de state por Terraform Workspace**
- Cada VM/projeto usa um `workspace_name` próprio (definido em `terraform.tfvars`)
- `deploy_vm.ps1` / `deploy_vm.sh` selecionam (ou criam) esse workspace automaticamente
- O state de uma VM fica isolado do state de qualquer outra: um apply nunca lê nem
  substitui o state de outro projeto/VM
- `main.tf` tem uma `precondition` que bloqueia o apply se o workspace ativo não
  bater com o `workspace_name` declarado no `tfvars`

### 2. **Bloqueio automático de alterações/exclusões**
- Os scripts são **somente para criação** por padrão
- Sempre rodam `terraform plan` antes de qualquer apply
- Se o plano contiver qualquer `update` ou `delete` em recursos já existentes,
  o apply é **bloqueado automaticamente** — nada é aplicado
- Para prosseguir mesmo assim, é preciso rodar com `--allow-destructive`
  (`.sh`) ou `-AllowDestructive` (`.ps1`) **e** digitar `CONFIRMAR` no terminal

### 3. **Validação e alertas**
- Scripts exigem `terraform`/`jq` (ou `terraform` no PowerShell) no PATH
- Notificam início, bloqueio, confirmação manual e resultado via Telegram
  (se `enable_telegram_alerts = true` no `tfvars`)

---

## 📋 WORKFLOW CORRETO

### **Cenário 1: Criar uma VM nova**

```powershell
# 1. Copie terraform.tfvars.example para terraform.tfvars
# 2. Preencha project_id, vm_name e um workspace_name ÚNICO
#    (sugestão: "<project_id>-<vm_name>")
# 3. Execute o deploy
.\deploy_vm.ps1

# O script seleciona/cria o workspace, gera o plan e, como é
# 100% criação, aplica direto.
```

```bash
./deploy_vm.sh
```

---

### **Cenário 2: Criar outra VM (projeto/VM diferente)**

```powershell
# 1. Edite terraform.tfvars com os dados da NOVA VM e um workspace_name
#    diferente do usado pela VM anterior
project_id     = "consigaz-270221"
vm_name        = "consigazprod"
workspace_name = "consigaz-270221-consigazprod"

# 2. Execute o deploy normalmente
.\deploy_vm.ps1
```

> Como cada VM tem seu próprio workspace, não existe risco de o apply de uma VM
> nova mexer no state de uma VM já existente — cada uma vive em seu state isolado.
> Não é necessário rodar nenhum script de limpeza de state entre uma VM e outra.

---

### **Cenário 3: Modificar VM EXISTENTE (mesmo workspace)**

```powershell
# 1. Selecione/garanta o mesmo workspace_name já usado por essa VM
# 2. Edite terraform.tfvars alterando as configs desejadas (RAM, disco, etc)
# 3. Execute o deploy
.\deploy_vm.ps1

# Como o plano vai conter "update" na VM existente, o script BLOQUEIA
# automaticamente e pede para rodar de novo com -AllowDestructive
.\deploy_vm.ps1 -AllowDestructive
# Digite CONFIRMAR quando solicitado
```

---

## 🔍 COMO LER O PLAN

```
Terraform will perform the following actions:

  # google_compute_instance.vm_instance will be created
  + resource "google_compute_instance" "vm_instance" {
      ✅ SEGURO - VM será CRIADA (aplica direto, sem flag extra)

  # google_compute_instance.vm_instance will be updated in-place
  ~ resource "google_compute_instance" "vm_instance" {
      ⚠️ BLOQUEADO por padrão - exige --allow-destructive/-AllowDestructive + CONFIRMAR

  # google_compute_instance.vm_instance will be destroyed
  - resource "google_compute_instance" "vm_instance" {
      ⚠️ BLOQUEADO por padrão - exige --allow-destructive/-AllowDestructive + CONFIRMAR

  # google_compute_instance.vm_instance must be replaced
-/+ resource "google_compute_instance" "vm_instance" {
      ⚠️ BLOQUEADO por padrão - exige --allow-destructive/-AllowDestructive + CONFIRMAR
```

---

## 🛠️ COMANDOS ÚTEIS

### Verificar workspace e state atual
```powershell
terraform workspace list
terraform workspace show
terraform state list
terraform show
```

### Listar VMs no GCP
```powershell
gcloud compute instances list --project=SEU-PROJETO
```

### Soltar uma VM do controle do Terraform sem destruí-la (uso manual/pontual)
```powershell
.\reset_state.ps1   # ou ./reset_state.sh no Linux
```
> Continua disponível para casos em que você queira remover recursos do state
> do workspace atual sem rodar um novo apply em seguida (faz backup do state
> antes de remover). No fluxo normal, como cada VM já tem seu workspace
> isolado, isso raramente é necessário.

---

## 📞 EMERGÊNCIA: VM FOI DESTRUÍDA

1. **Verifique backups automáticos do GCP** (se configurado)
2. **Verifique snapshots de disco** no console GCP (veja `snapshot_config/`)
3. **Restaure a partir de snapshot** usando o módulo `restore_vm/`
4. **Entre em contato com suporte GCP** para possível recuperação

**Lição:** Sempre configure snapshots automáticos para VMs críticas!

---

## ✅ CHECKLIST PRÉ-DEPLOY

- [ ] `workspace_name` no `terraform.tfvars` é único para esta VM/projeto
- [ ] Li o `terraform plan` completamente
- [ ] Se o plano só mostra `+` (criação), pode aplicar direto
- [ ] Se o plano mostra `~`, `-` ou `-/+`, confirmei que é intencional antes
      de rodar com `--allow-destructive`/`-AllowDestructive`
- [ ] Tenho snapshot/backup da VM atual (se aplicável)

**Só digite `CONFIRMAR` se TODOS os itens estiverem ✅**
