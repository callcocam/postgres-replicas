# Onde usar cada parte do pacote

Separação clara: **Primário** = instalação; **Réplica** = instalação + backups (config à parte).

---

## Servidor PRIMÁRIO (instalação)

**Use apenas para instalar/configurar PostgreSQL e replicação.**

### Arquivos para o primário

| Arquivo | Uso |
|---------|-----|
| `setup-primary.sh` | Rodar **no primário** para instalar PostgreSQL e preparar replicação |
| `setup-replica.sh` | Rodar **na réplica** (uma vez), usando o `replica-config.txt` gerado no primário |
| `GUIA DE INÍCIO RÁPIDO.md` | Passo a passo da instalação |
| `.credentials.example` | Referência de credenciais (as reais vêm dos scripts) |

### O que NÃO vai no primário

- **Não** configure cron de backup no primário  
→ Backups rodam só na réplica

---

## Servidor RÉPLICA (instalação + backup)

### Instalação da réplica

- **setup-replica.sh** → só instala a réplica (PostgreSQL em modo réplica).

### Backups (configuração à parte)

Os scripts de backup ficam em **postgres-replicas/backup/** e são usados **direto** dessa pasta (não copiar para `/root/`).

**Fluxo:** Na réplica, clonar o repositório (ou ter o pacote disponível) → criar `.backup-env` → configurar o cron apontando para `postgres-replicas/backup/`.

| Arquivo | Uso |
|---------|-----|
| `backup/backup-to-s3.sh` | Backup completo .sql.gz |
| `backup/postgres-backup-tables-hours.sh` | Backup horário (6 tabelas críticas) |
| `backup/postgres-backup-tables-full.sh` | Backup diário (todas as tabelas) |
| `backup/restore-from-s3.sh` | Restore .sql.gz (manual) |
| `backup/restore-tables-from-s3.sh` | Restore por tabelas (manual) |
| `backup/.backup-env.example` | Copiar como `/root/.backup-env` e preencher credenciais |

### Documentação de backup na réplica

- **backup/BACKUP-NA-REPLICA.md** → Guia para configurar backups na réplica
- **backup/README.md** → Detalhes dos scripts e do S3

### Resumo

1. **Primário:** instalação com `setup-primary.sh`; sem cron de backup.
2. **Réplica:** `setup-replica.sh` (instalação) + **backup à parte:** clonar repo, criar `.backup-env`, cron apontando para `postgres-replicas/backup/`.

### Backup/Restore (sem nomes fixos)

- Bancos são descobertos dinamicamente (todos exceto templates e `postgres`).
- **Principal** = banco que tem tabelas `tenants` e `clients`; **cliente** = caso contrário.
- Nome do arquivo de backup = nome do banco (ex.: `meu_banco_daily_20260202_030000.tar.gz`). Restore restaura no banco com esse nome.
- Restore de todos: `./restore-tables-from-s3.sh --all-databases --type daily`.
