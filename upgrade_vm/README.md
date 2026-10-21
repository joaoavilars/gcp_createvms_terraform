# upgrade_vm — Recriação de VM mantendo IP externo e interno

Ferramenta para **recriar uma VM já existente** (ex.: trocar a versão do SO)
**mantendo o mesmo IP externo** (reservado) **e o mesmo IP interno**, sem
precisar atualizar DNS, firewalls, connection strings ou qualquer outra coisa
que dependa desses IPs.

Diferente da pasta raiz deste repositório (`deploy_vm.sh`/`main.tf`, usada
para **criar VMs novas do zero**, com IP externo novo), este módulo assume
que a VM **já existe** e vai ser **substituída no lugar**.

## Quando usar

- Migrar uma VM para uma versão mais nova do SO (ex.: Ubuntu 22.04 → 26.04).
- Trocar o tipo de máquina/disco de uma VM existente, sem alterar os IPs.
- Qualquer recriação onde manter o mesmo IP externo/interno é obrigatório
  (ex.: firewalls do GCP liberados só para IPs específicos, connection
  strings de outros servidores apontando para o IP interno, DNS externo
  apontando para o IP externo).

## O que a ferramenta NÃO faz

- **Não migra a aplicação.** A VM nova sobe com o SO limpo — reinstalar e
  reconfigurar Apache/Tomcat/SIVA/etc. é uma etapa manual, depois do upgrade.
- **Não apaga o disco antigo.** Ele fica preservado (desanexado, sem VM) como
  rollback — apagar é uma decisão manual, só depois de validar a VM nova.

## Pré-requisitos

- `terraform` e `gcloud` no PATH, autenticado (`gcloud auth login`) com
  permissão de Compute Admin no projeto.
- A VM antiga precisa existir e estar num projeto/zona que você tem acesso.

## Passo a passo

1. **Copie e preencha o `terraform.tfvars`:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
   Preencha `project_id`, `region`, `zone`, `vm_name` (mesmo nome da VM
   antiga — ela será excluída e recriada com esse mesmo nome),
   `workspace_name` (único, não reutilize o de outra VM), `machine_type`,
   `os_image` (o SO novo), `boot_disk_size`/`boot_disk_type`, `tags` e
   `ssh_key`. Confira os valores atuais da VM antiga com:
   ```bash
   gcloud compute instances describe <vm_name> --project=<project_id> --zone=<zone>
   ```
   **Não preencha IPs** — `existing_static_ip` e `network_ip` são
   descobertos automaticamente pelo script a partir da VM antiga.

2. **Rode o script:**
   ```bash
   ./upgrade_vm.sh
   ```
   Ele vai, nesta ordem:
   1. Descobrir o IP externo, IP interno e disco de boot da VM antiga.
   2. Conferir se o IP externo já é reservado (static). Se for efêmero,
      promove automaticamente para reservado (mesmo IP, sem downtime) —
      sem isso não há garantia de manter o mesmo IP externo na recriação.
   3. Tirar um snapshot do disco de boot antigo (pule com `--skip-snapshot`,
      não recomendado).
   4. Pedir confirmação explícita (`CONFIRMAR`, digitado) — nada acontece
      antes disso.
   5. Excluir a instância antiga (`--keep-disks=all`, disco preservado).
   6. `terraform apply` neste módulo, criando a instância nova com o SO
      novo, reaproveitando o IP externo e fixando o IP interno.

3. **Reconfigure a aplicação na VM nova** (SO limpo — nada é migrado
   automaticamente): reinstalar pacotes, redeployar a aplicação, restaurar
   configs, etc.

4. **Valide** que tudo funciona no IP/DNS de sempre.

5. **Só depois de validar**, apague o disco antigo (o script informa o nome
   exato no final da execução):
   ```bash
   gcloud compute disks delete <nome-do-disco-antigo> --project=<project_id> --zone=<zone>
   ```

## Se o `terraform apply` falhar no meio do caminho

A instância antiga já foi excluída (o disco está preservado). Corrija o
problema indicado pelo Terraform e rode de novo **só o apply**, sem repetir
o script inteiro (evita tentar excluir uma instância que já não existe):
```bash
terraform apply -var "existing_static_ip=<ip_externo>" -var "network_ip=<ip_interno>"
```
(os valores exatos aparecem na saída de erro do script)

## Rollback

Se algo der errado com a VM nova e você precisar voltar para a antiga:
1. `terraform destroy` neste workspace (remove a VM nova, mantém o IP
   externo reservado intacto — este módulo nunca gerencia esse recurso).
2. Criar uma nova instância a partir do disco antigo preservado (ou do
   snapshot), reanexando o mesmo IP externo reservado e o mesmo IP interno
   manualmente via `gcloud compute instances create` (ou adaptando este
   mesmo módulo para apontar `os_image`/disco de volta ao estado anterior).
