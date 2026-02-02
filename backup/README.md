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
| `postgres-backup-tables-hours.sh` | Backup das 6 tabelas críticas (só bancos cliente) | A cada hora |
| `postgres-backup-tables-full.sh` | Backup completo por tabelas (todos os bancos) | Diário (3h) |
| `backup-to-s3.sh` | Backup completo do banco (.sql.gz) | Diário (4h) |
| `restore-tables-from-s3.sh` | Restauração por tabelas (1 banco ou --all-databases) | Manual |
| `restore-from-s3.sh` | Restauração de banco completo (.sql.gz) | Manual |

## 🔍 Principal vs Cliente (dinâmico)

**Nenhum nome de banco é fixo.** A classificação é feita pelo conteúdo do banco:

- **Principal** = banco que tem as tabelas `tenants` e `clients` (schema `public`).
- **Cliente** = banco que não tem as duas.

Os scripts listam todos os bancos (exceto `template0`, `template1`, `postgres`) e aplicam a regra acima. Novos ou removidos bancos entram/saem sozinhos.

**Nome do backup** = nome do banco (ex.: `meu_banco_daily_20260202_030000.tar.gz`). O restore usa o nome do arquivo e restaura no mesmo banco.

## ⚡ Instalação Rápida

Os scripts são usados **direto** de `postgres-replicas/backup/` (não é necessário copiar para `/root/`). Na réplica: clone o repositório (ou tenha o pacote disponível), crie `.backup-env` e configure o cron apontando para esta pasta.

### 1. Ter o pacote na réplica

Clone o repositório na réplica (ou copie a pasta do pacote). Exemplo: `/root/postgres-replicas/`. Defina o caminho da pasta backup, por exemplo:

```bash
BACKUP_DIR=/root/postgres-replicas/backup   # ajuste se o repo estiver em outro path
```

### 2. Configurar Credenciais

```bash
cd "$BACKUP_DIR"
cp .backup-env.example /root/.backup-env
nano /root/.backup-env   # preencher credenciais S3 e Postgres
chmod 600 /root/.backup-env
```

### 3. Testar

```bash
source /root/.backup-env
"$BACKUP_DIR/postgres-backup-tables-hours.sh"
"$BACKUP_DIR/postgres-backup-tables-full.sh"
"$BACKUP_DIR/backup-to-s3.sh"
```

### 4. Configurar Cron

Cron deve apontar **direto** para os scripts em `postgres-replicas/backup/` (ajuste o path se o repo estiver em outro lugar):

```bash
crontab -e
# Adicionar (path fixo; troque /root/postgres-replicas por onde o repo estiver):
# Backup horário (tabelas críticas) - a cada hora
0 * * * * source /root/.backup-env && /root/postgres-replicas/backup/postgres-backup-tables-hours.sh >> /var/log/postgresql-backup-hourly.log 2>&1

# Backup diário completo (todas as tabelas) - às 3h
0 3 * * * source /root/.backup-env && /root/postgres-replicas/backup/postgres-backup-tables-full.sh >> /var/log/postgresql-backup-daily.log 2>&1

# Backup completo do banco (.sql.gz) - às 4h
0 4 * * * source /root/.backup-env && /root/postgres-replicas/backup/backup-to-s3.sh >> /var/log/postgresql-backup.log 2>&1
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

Execute a partir da pasta `backup/` (ou use o path completo):

```bash
cd /root/postgres-replicas/backup   # ou onde estiver o repo
# Listar backups horários
./restore-tables-from-s3.sh --list hourly

# Listar backups diários
./restore-tables-from-s3.sh --list daily
```

### Restaurar Backup de Tabelas

```bash
cd /root/postgres-replicas/backup
# Listar backups (mostra principal/cliente por banco)
./restore-tables-from-s3.sh --list daily
./restore-tables-from-s3.sh --list hourly

# Restaurar um banco (último backup)
./restore-tables-from-s3.sh NOME_DO_BANCO --type daily

# Restaurar TODOS os bancos (principal + clientes)
./restore-tables-from-s3.sh --all-databases --type daily

# Todos os bancos no mesmo timestamp
./restore-tables-from-s3.sh --all-databases --type daily --timestamp 20260202_030000

# Restaurar apenas tabelas específicas
./restore-tables-from-s3.sh NOME_DO_BANCO --type hourly --tables planograms,gondolas
```

O nome do banco no backup é o mesmo do arquivo; o restore restaura sempre no banco com esse nome.

### Restaurar Backup Completo (.sql.gz)

```bash
cd /root/postgres-replicas/backup
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
source /root/.backup-env && /root/postgres-replicas/backup/postgres-backup-tables-hours.sh
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
