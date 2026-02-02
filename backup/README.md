# 📦 PLANNERATE - Sistema de Backup PostgreSQL → S3

Sistema completo de backup automático para PostgreSQL com upload para DigitalOcean Spaces (S3 compatível).

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                    SERVIDOR POSTGRESQL                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  plannerate_production  │  plannerate_staging       │   │
│  │  plannerate_cliente1    │  plannerate_cliente2  ... │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
         ▼                ▼                ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   HORÁRIO   │  │   DIÁRIO    │  │  COMPLETO   │
│  (1 em 1h)  │  │  (3h manhã) │  │  (4h manhã) │
│             │  │             │  │             │
│ 6 tabelas   │  │ Todas as    │  │ Banco       │
│ críticas    │  │ tabelas     │  │ completo    │
│             │  │ por tabela  │  │ .sql.gz     │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │   DigitalOcean Spaces  │
           │   (S3 compatível)      │
           │                        │
           │  /backups/hourly/      │
           │  /backups/daily/       │
           │  /backups/postgresql/  │
           └────────────────────────┘
```

## 📋 Scripts Disponíveis

| Script | Função | Frequência |
|--------|--------|------------|
| `postgres-backup-tables-hours.sh` | Backup das 6 tabelas críticas dos clientes | A cada hora |
| `postgres-backup-tables-full.sh` | Backup completo por tabelas (todos os bancos) | Diário (3h) |
| `backup-to-s3.sh` | Backup completo do banco (.sql.gz) | Diário (4h) |
| `restore-tables-from-s3.sh` | Restauração por tabelas (hourly/daily) | Manual |
| `restore-from-s3.sh` | Restauração de banco completo (.sql.gz) | Manual |

## ⚡ Instalação Rápida

### 1. Configurar Credenciais

```bash
# Copiar exemplo
cp .backup-env.example /root/.backup-env

# Editar com suas credenciais
nano /root/.backup-env

# Proteger arquivo
chmod 600 /root/.backup-env
```

### 2. Copiar Scripts

```bash
# Copiar para /root
cp *.sh /root/
chmod +x /root/*.sh
```

### 3. Testar

```bash
# Testar backup horário
/root/postgres-backup-tables-hours.sh

# Testar backup diário
/root/postgres-backup-tables-full.sh

# Testar backup completo
/root/backup-to-s3.sh
```

### 4. Configurar Cron

```bash
# Editar cron
crontab -e

# Adicionar:
# Backup horário (tabelas críticas) - a cada hora
0 * * * * source /root/.backup-env && /root/postgres-backup-tables-hours.sh >> /var/log/postgresql-backup-hourly.log 2>&1

# Backup diário completo (todas as tabelas) - às 3h
0 3 * * * source /root/.backup-env && /root/postgres-backup-tables-full.sh >> /var/log/postgresql-backup-daily.log 2>&1

# Backup completo do banco (.sql.gz) - às 4h
0 4 * * * source /root/.backup-env && /root/backup-to-s3.sh >> /var/log/postgresql-backup.log 2>&1
```

## 🔄 Estratégia de Backup

### Backup Horário (Tabelas Críticas)

Apenas as 6 tabelas mais importantes dos bancos de clientes:
- `planograms`
- `gondolas`
- `sections`
- `shelves`
- `segments`
- `layers`

**Retenção:** 48 horas

### Backup Diário (Por Tabelas)

Todas as tabelas de todos os bancos, exceto:

**Banco Principal (production/staging):**
- `cache`, `cache_locks`, `sessions`
- `jobs`, `job_batches`, `failed_jobs`
- `activity_log`, `integration_sync_logs`
- `personal_access_tokens`, `password_reset_tokens`
- `gondola_workflow_metrics`, `gondola_notifications`

**Bancos de Clientes:**
- `sales`
- `monthly_sales_summaries`

**Retenção:** 30 dias

### Backup Completo (.sql.gz)

Dump completo do banco em formato SQL comprimido.

**Retenção:** 30 dias

## 📁 Estrutura no S3

```
s3://seu-bucket/backups/
├── hourly/                              # Backup horário
│   └── 2026/02/02/
│       ├── plannerate_albert_hourly_20260202_100000.tar.gz
│       ├── plannerate_bruda_hourly_20260202_100000.tar.gz
│       └── ...
├── daily/                               # Backup diário
│   └── 2026/02/02/
│       ├── plannerate_production_daily_20260202_030000.tar.gz
│       ├── plannerate_staging_daily_20260202_030000.tar.gz
│       └── ...
└── postgresql/                          # Backup completo
    └── 2026/02/02/
        ├── plannerate_production_20260202_040000.sql.gz
        └── plannerate_staging_20260202_040000.sql.gz
```

## 🔧 Comandos de Restauração

### Listar Backups Disponíveis

```bash
# Listar backups horários
./restore-tables-from-s3.sh --list hourly

# Listar backups diários
./restore-tables-from-s3.sh --list daily
```

### Restaurar Backup de Tabelas

```bash
# Restaurar último backup diário completo
./restore-tables-from-s3.sh plannerate_albert --type daily

# Restaurar backup horário (só tabelas críticas)
./restore-tables-from-s3.sh plannerate_albert --type hourly

# Restaurar apenas tabelas específicas
./restore-tables-from-s3.sh plannerate_albert --type hourly --tables planograms,gondolas

# Restaurar backup específico por timestamp
./restore-tables-from-s3.sh plannerate_albert --type daily --timestamp 20260202_030000
```

### Restaurar Backup Completo (.sql.gz)

```bash
# Listar backups disponíveis
./restore-from-s3.sh plannerate_production --list

# Restaurar último backup
./restore-from-s3.sh plannerate_production

# Restaurar backup específico
./restore-from-s3.sh plannerate_production 20260202_040000
```

## 📊 Monitoramento

### Ver Logs

```bash
# Backup horário
tail -f /var/log/postgresql-backup-hourly.log

# Backup diário
tail -f /var/log/postgresql-backup-daily.log

# Backup completo
tail -f /var/log/postgresql-backup.log
```

### Verificar Último Backup

```bash
# Via AWS CLI
source /root/.backup-env
export AWS_ACCESS_KEY_ID="$DO_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DO_SECRET_ACCESS_KEY"

# Listar últimos backups horários
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/hourly/" | sort -r | head -10

# Listar últimos backups diários
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/daily/" | sort -r | head -10
```

## 🚨 Troubleshooting

### Erro de Credenciais

```bash
# Verificar se variáveis estão configuradas
source /root/.backup-env
echo "DO_ACCESS_KEY_ID: ${DO_ACCESS_KEY_ID:+configurado}"
echo "PGPASSWORD: ${PGPASSWORD:+configurado}"
```

### Erro de Conexão com S3

```bash
# Testar conexão
source /root/.backup-env
export AWS_ACCESS_KEY_ID="$DO_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DO_SECRET_ACCESS_KEY"
aws s3 ls --endpoint-url="$DO_ENDPOINT" "s3://$DO_BUCKET"
```

### Erro de Conexão com PostgreSQL

```bash
# Testar conexão
source /root/.backup-env
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -c "SELECT 1;"
```

### Backup Não Executando no Cron

```bash
# Verificar cron
crontab -l

# Verificar logs do sistema
grep CRON /var/log/syslog | tail -20

# Executar manualmente para ver erros
source /root/.backup-env && /root/postgres-backup-tables-hours.sh
```

## 📈 Boas Práticas

1. **Teste os restores regularmente** - Um backup que não pode ser restaurado é inútil
2. **Monitore os logs** - Configure alertas para falhas de backup
3. **Mantenha as credenciais seguras** - Use `chmod 600` no arquivo `.backup-env`
4. **Verifique o espaço no S3** - Monitore o uso de storage
5. **Documente as exclusões** - Saiba quais tabelas não estão no backup

## 🔐 Segurança

- ⚠️ **NUNCA** commite `.backup-env` no Git
- ⚠️ **NUNCA** compartilhe as credenciais S3
- ⚠️ Use permissões `600` nos arquivos de credenciais
- ⚠️ Configure backups em bucket privado
- ⚠️ Habilite versionamento no bucket S3 se possível
