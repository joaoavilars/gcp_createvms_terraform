# 🔄 RESTAURAÇÃO DE VM A PARTIR DE SNAPSHOT

Script para restaurar VM do GCP a partir de snapshot usando Terraform.

## 📋 PRÉ-REQUISITOS

1. **gcloud CLI autenticado:**
   ```powershell
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project sidicom-453519
   ```

2. **Snapshot existe no GCP:**
   ```powershell
   # Listar snapshots disponíveis
   gcloud compute snapshots list --project=sidicom-453519
   ```

3. **Terraform instalado** (já deve ter se está usando o projeto pai)

---

## 🚀 COMO USAR

### **Passo 1: Revisar `terraform.tfvars`**

Verifique se os dados estão corretos:
- `snapshot_name = "sidicom1-migration-snapshot"`
- `vm_name = "sidicom2"`
- `project_id = "sidicom-453519"`
- Configurações de máquina (CPUs, RAM, disco)

### **Passo 2: Inicializar Terraform**

```powershell
cd restore_vm
terraform init
```

### **Passo 3: Executar restauração**

**PowerShell (Windows):**
```powershell
.\restore_vm.ps1
```

**Bash (WSL/Linux):**
```bash
./restore_vm.sh
```

### **Passo 4: Confirmar**

O script mostra:
- Projeto, VM e snapshot
- Plano detalhado do Terraform
- Recursos que serão criados

Digite `RESTAURAR` para confirmar.

---

## 🛠️ O QUE O SCRIPT FAZ

1. **Cria disco de boot** a partir do snapshot `sidicom1-migration-snapshot`
2. **Cria IP estático** (tenta reutilizar `sidicom2-static-ip` se disponível)
3. **Provisiona VM** `sidicom2` usando o disco restaurado
4. **Configura rede, SSH e firewall** (http-server, https-server)
5. **Envia notificações** via Telegram (se habilitado)

---

## 📊 DADOS DA VM RESTAURADA

Após sucesso, o script exibe:
```
vm_name              = "sidicom2"
vm_static_ip         = "34.73.175.28"
vm_zone              = "us-east1-c"
boot_disk_from_snapshot = "sidicom2-boot"
```

---

## ⚠️ ATENÇÕES

### **IP Estático**
O script reutiliza o IP fixo existente `sidicom1ipfixo - 34.148.145.64`.

**IMPORTANTE:** Se esse IP estiver atualmente anexado a outra VM, você precisa:

**Opção 1 - Desanexar da VM antiga:**
```powershell
# Deletar a VM antiga que está usando o IP (se existir)
gcloud compute instances delete <vm-antiga> --zone=us-east1-c --project=sidicom-453519
```

**Opção 2 - Usar IP diferente:**
Edite `terraform.tfvars` linha 15:
```hcl
static_ip_name = "sidicom2-ip-novo"
```
E crie o IP novo antes:
```powershell
gcloud compute addresses create sidicom2-ip-novo --region=us-east1 --project=sidicom-453519
```

### **Conflito de nome de VM**
Se já existe VM chamada `sidicom2` rodando:

**Opção 1 - Deletar VM antiga:**
```powershell
gcloud compute instances delete sidicom2 --zone=us-east1-c --project=sidicom-453519
```

**Opção 2 - Restaurar com nome diferente:**
Edite `terraform.tfvars` linha 11:
```hcl
vm_name = "sidicom2-restored"
```

---

## 🔍 VERIFICAÇÃO PÓS-RESTAURAÇÃO

```powershell
# Verificar VM está rodando
gcloud compute instances list --project=sidicom-453519

# Testar SSH
ssh softmovel@34.73.175.28

# Verificar serviços dentro da VM
sudo systemctl status <seu-servico>
```

---

## 🆘 PROBLEMAS COMUNS

### **Erro: Snapshot não encontrada**
```
Error: Error creating disk: googleapi: Error 404: The resource 'projects/sidicom-453519/global/snapshots/sidicom1-migration-snapshot' was not found
```

**Solução:** Verificar nome correto:
```powershell
gcloud compute snapshots list --project=sidicom-453519
```

### **Erro: Região incompatível**
Snapshots são globais, mas discos são zonais. Se snapshot foi feita em zona diferente, pode dar problema.

**Solução:** Edite `terraform.tfvars` e ajuste `zone` para mesma zona original da VM.

### **Erro: Tipo de disco incompatível**
Se snapshot era `pd-ssd` e está tentando criar `pd-balanced`.

**Solução:** Edite `terraform.tfvars` linha 27:
```hcl
boot_disk_type = "pd-ssd"  # Mesmo tipo da snapshot
```

---

## 🧹 LIMPEZA (SE NECESSÁRIO)

Se precisar reverter restauração:

```powershell
cd restore_vm
terraform destroy

# Confirma digitando 'yes'
```

**ATENÇÃO:** Isso deleta a VM restaurada E o disco criado do snapshot!

---

## 📞 PRÓXIMOS PASSOS

Após VM restaurada com sucesso:

1. **Teste conectividade:** SSH, HTTP, aplicações
2. **Verifique dados:** Confirme que dados do snapshot de 15/05 estão presentes
3. **Atualize DNS/registros** se IP mudou
4. **Configure backups automáticos** para evitar perda futura:
   ```powershell
   # Criar snapshot schedule
   gcloud compute resource-policies create snapshot-schedule daily-backup \
       --max-retention-days=7 \
       --on-source-disk-delete=keep-auto-snapshots \
       --daily-schedule \
       --start-time=03:00 \
       --region=us-east1 \
       --project=sidicom-453519
   
   # Aplicar à VM
   gcloud compute disks add-resource-policies sidicom2-boot \
       --resource-policies=daily-backup \
       --zone=us-east1-c \
       --project=sidicom-453519
   ```
