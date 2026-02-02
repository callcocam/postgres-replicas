# Onde usar cada parte do pacote

Separação clara: **Primário** = instalação; **Réplica** = backups.

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

- **Não** copie a pasta `backup/` para o primário para rodar backups
- **Não** configure cron de backup no primário  
→ Backups rodam só na réplica

---

## Servidor RÉPLICA (backups)

**Use a pasta `backup/` só na réplica.**

### Arquivos para a réplica (backups)

Copie **toda a pasta `backup/`** para a réplica (ex.: `/root/`):

| Arquivo | Uso |
|---------|-----|
| `backup/backup-to-s3.sh` | Backup completo .sql.gz |
| `backup/postgres-backup-tables-hours.sh` | Backup horário (6 tabelas críticas) |
| `backup/postgres-backup-tables-full.sh` | Backup diário (todas as tabelas) |
| `backup/restore-from-s3.sh` | Restore .sql.gz (manual) |
| `backup/restore-tables-from-s3.sh` | Restore por tabelas (manual) |
| `backup/.backup-env.example` | Copiar como `.backup-env` e preencher credenciais |

### Documentação de backup na réplica

- **`backup/BACKUP-NA-REPLICA.md`** → Guia para configurar backups na réplica
- **`backup/README.md`** → Detalhes dos scripts e do S3

### Resumo

1. **Primário:** instalação com `setup-primary.sh` e `setup-replica.sh` (na réplica), sem cron de backup.
2. **Réplica:** copiar `backup/` para `/root/`, configurar `.backup-env`, instalar `awscli`, testar scripts e configurar cron conforme `BACKUP-NA-REPLICA.md`.

### Backup/Restore (sem nomes fixos)

- Bancos são descobertos dinamicamente (todos exceto templates e `postgres`).
- **Principal** = banco que tem tabelas `tenants` e `clients`; **cliente** = caso contrário.
- Nome do arquivo de backup = nome do banco (ex.: `meu_banco_daily_20260202_030000.tar.gz`). Restore restaura no banco com esse nome.
- Restore de todos: `./restore-tables-from-s3.sh --all-databases --type daily`.
