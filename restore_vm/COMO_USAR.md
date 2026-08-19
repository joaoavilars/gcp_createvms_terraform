# 🚀 GUIA RÁPIDO - RESTAURAR VM DO SNAPSHOT

## ✅ PRÉ-REQUISITOS

1. **gcloud CLI autenticado:**
   ```powershell
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Snapshot existe no GCP**
3. **Terraform instalado**

---

## 📝 PASSO A PASSO

### **1. Configure o arquivo terraform.tfvars**

Edite `terraform.tfvars` e ajuste os valores:

```hcl
project_id     = "sidicom-453519"        # Seu projeto GCP
vm_name        = "sidicom2"              # Nome da VM a criar
snapshot_name  = "sidicom1-migration-snapshot"  # Snapshot de origem
static_ip_name = "sidicom1ipfixo"        # IP existente (ou "" para criar novo)

# Configurações de hardware
machine_model_base = "e2"
machine_cpus       = 2
machine_ram        = 4
boot_disk_size     = 100
boot_disk_type     = "pd-balanced"
```

**TODAS as configurações estão documentadas no arquivo `terraform.tfvars`!**

---

### **2. Inicialize o Terraform** (apenas 1ª vez)

```powershell
cd restore_vm
terraform init
```

---

### **3. Execute a restauração**

**Windows:**
```powershell
.\restore_vm.ps1
```

**Linux/WSL:**
```bash
./restore_vm.sh
```

---

### **4. Revise o plano e confirme**

O script mostra:
- ✅ Disco criado do snapshot
- ✅ VM criada com o disco
- ✅ IP anexado

**Digite `RESTAURAR` para confirmar.**

---

## 📊 RESULTADO

Após sucesso:
```
vm_name       = "sidicom2"
vm_static_ip  = "34.148.145.64"
vm_zone       = "us-east1-c"
```

**Teste SSH:**
```powershell
ssh softmovel@34.148.145.64
```

---

## ⚙️ CONFIGURAÇÕES PRINCIPAIS

### **VM já existe com esse nome?**
Edite `terraform.tfvars`:
```hcl
vm_name = "sidicom2-restored"
```

### **IP está em uso?**
Edite `terraform.tfvars`:
```hcl
static_ip_name = ""  # Deixe vazio, será criado IP novo automático
```

### **Mudar hardware da VM?**
Edite `terraform.tfvars`:
```hcl
machine_cpus = 4   # Aumentar CPUs
machine_ram  = 16  # Aumentar RAM
```

### **Snapshot de zona diferente?**
Edite `terraform.tfvars`:
```hcl
zone = "us-central1-a"  # Mesma zona da snapshot
```

---

## 🔍 COMANDOS ÚTEIS

**Listar snapshots disponíveis:**
```powershell
gcloud compute snapshots list --project=sidicom-453519
```

**Listar IPs disponíveis:**
```powershell
gcloud compute addresses list --project=sidicom-453519
```

**Ver detalhes da snapshot:**
```powershell
gcloud compute snapshots describe sidicom1-migration-snapshot --project=sidicom-453519
```

**Verificar VM criada:**
```powershell
gcloud compute instances list --project=sidicom-453519
```

---

## 🆘 PROBLEMAS COMUNS

### Erro: "Snapshot não encontrada"
```powershell
# Liste as snapshots
gcloud compute snapshots list --project=sidicom-453519

# Ajuste terraform.tfvars com nome correto
snapshot_name = "nome-correto-da-snapshot"
```

### Erro: "IP já está em uso"
```powershell
# Deixe vazio para criar IP novo
static_ip_name = ""
```

### Erro: "VM com esse nome já existe"
```powershell
# Use nome diferente
vm_name = "sidicom2-restored"
```

---

## 📚 DOCUMENTAÇÃO COMPLETA

- **terraform.tfvars** → Todas configurações documentadas linha por linha
- **README.md** → Documentação técnica detalhada
- **WORKFLOW_SEGURO.md** (pasta pai) → Proteções e boas práticas
