# Backup PostgreSQL para DigitalOcean Spaces (S3)

## 📋 Visão Geral

Sistema completo de backup automatizado para PostgreSQL com upload para DigitalOcean Spaces (compatível com S3). Suporta:
- ✅ Backup automático de múltiplos databases
- ✅ Upload para DigitalOcean Spaces
- ✅ Rotação automática de backups (30 dias)
- ✅ Habilitação/desabilitação por ambiente
- ✅ Restore simplificado
- ✅ Compressão gzip

## 🔧 Configuração

### 1. Instalar no Servidor PostgreSQL (72.62.139.43)

```bash
# Fazer upload dos scripts
scp postgres-replicas/backup-to-s3.sh root@72.62.139.43:/root/
scp postgres-replicas/restore-from-s3.sh root@72.62.139.43:/root/

# SSH no servidor
ssh root@72.62.139.43

# Tornar executáveis
chmod +x /root/backup-to-s3.sh
chmod +x /root/restore-from-s3.sh
```

### 2. Configurar Variáveis de Ambiente

Crie o arquivo `/root/.backup-env`:

```bash
# DigitalOcean Spaces
export DO_ACCESS_KEY_ID=""
export DO_SECRET_ACCESS_KEY=""
export DO_ENDPOINT="https://sfo3.digitaloceanspaces.com"
export DO_BUCKET="planify"
export DO_REGION="sfo3"

# PostgreSQL
export POSTGRES_HOST="127.0.0.1"
export POSTGRES_PORT="5432"
export POSTGRES_USER="postgres"
export PGPASSWORD="zzAlv1aIdbMvEtMvn6mAXWQJ"  # Sua senha real

# Databases para backup (separados por espaço)
export DATABASES="plannerate_production plannerate_staging"

# Configurações
export BACKUP_ENABLED="true"  # true para produção, false para staging
export BACKUP_DIR="/var/backups/postgresql"
export RETENTION_DAYS="30"
```

Proteger o arquivo:
```bash
chmod 600 /root/.backup-env
```

### 3. Para Staging (DESABILITADO por padrão)

No staging, crie `/root/.backup-env` com:

```bash
# STAGING - Backup desabilitado por padrão
export BACKUP_ENABLED="false"

# Credenciais (para testes)
export DO_ACCESS_KEY_ID="DO007CETKLCXD6WYKFZG"
export DO_SECRET_ACCESS_KEY="BBB2eyUrD0UUvh78bnzM00SOuzQGNX/olpRBRyQkwoA"
export DO_ENDPOINT="https://sfo3.digitaloceanspaces.com"
export DO_BUCKET="planify"
export DO_REGION="sfo3"

export POSTGRES_HOST="127.0.0.1"
export POSTGRES_PORT="5432"
export POSTGRES_USER="postgres"
export PGPASSWORD="sua_senha_staging"

export DATABASES="plannerate_staging"
export RETENTION_DAYS="7"  # Manter apenas 7 dias no staging
```

## 🚀 Uso

### Backup Manual

```bash
# Carregar variáveis de ambiente
source /root/.backup-env

# Executar backup
bash /root/backup-to-s3.sh
```

**Saída esperada:**
```
================================================
  PLANNERATE - Backup PostgreSQL → S3
================================================

✅ Validações concluídas
🔍 Testando conexão com DigitalOcean Spaces...
✅ Conexão com bucket 'planify' OK

📦 Iniciando backup: plannerate_production
  → Executando pg_dump...
  ✅ Dump criado: 245M
  → Enviando para S3...
  ✅ Upload concluído: s3://planify/backups/postgresql/2026/01/13/plannerate_production_20260113_120000.sql.gz

📦 Iniciando backup: plannerate_staging
  → Executando pg_dump...
  ✅ Dump criado: 89M
  → Enviando para S3...
  ✅ Upload concluído: s3://planify/backups/postgresql/2026/01/13/plannerate_staging_20260113_120000.sql.gz

🗑️  Limpando backups antigos (>30 dias)...

================================================
✅ Backup concluído com sucesso!
================================================

📊 Estatísticas:
  Backups bem-sucedidos: 2
  Backups com falha: 0
  Retenção: 30 dias
  Bucket: planify

📁 Últimos backups (últimos 5):
  - backups/postgresql/2026/01/13/plannerate_production_20260113_120000.sql.gz (245.32MB)
  - backups/postgresql/2026/01/13/plannerate_staging_20260113_120000.sql.gz (89.15MB)
  ...
```

### Testar no Staging

```bash
# Habilitar temporariamente no staging
export BACKUP_ENABLED="true"
source /root/.backup-env

# Rodar backup de teste
bash /root/backup-to-s3.sh

# Verificar se foi criado no S3
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/" | tail -5
```

## 📥 Restore de Backup

### Listar Backups Disponíveis

```bash
source /root/.backup-env
bash /root/restore-from-s3.sh plannerate_production --list
```

**Saída:**
```
📁 Backups disponíveis para plannerate_production:

  20260113_120000 - 245.32MB - 2026-01-13 12:00:00
  20260113_060000 - 244.98MB - 2026-01-13 06:00:00
  20260112_180000 - 243.45MB - 2026-01-12 18:00:00
  ...
```

### Restaurar Último Backup

```bash
source /root/.backup-env
bash /root/restore-from-s3.sh plannerate_production
```

### Restaurar Backup Específico

```bash
source /root/.backup-env
bash /root/restore-from-s3.sh plannerate_production 20260113_120000
```

**Processo de restore:**
1. Solicita confirmação (digite 'SIM')
2. Baixa backup do S3
3. Desconecta usuários do banco
4. Dropa e recria database
5. Restaura dados
6. Mostra estatísticas

## ⏰ Agendar Backup Automático (Cron)

### Produção - Backup Diário às 3h da manhã

```bash
# Editar crontab
crontab -e

# Adicionar linha:
0 3 * * * source /root/.backup-env && /root/backup-to-s3.sh >> /var/log/postgresql-backup.log 2>&1
```

### Staging - Backup Semanal (Domingo às 4h)

```bash
# Editar crontab
crontab -e

# Adicionar linha (desabilitado por padrão):
# 0 4 * * 0 export BACKUP_ENABLED="true" && source /root/.backup-env && /root/backup-to-s3.sh >> /var/log/postgresql-backup-staging.log 2>&1
```

## 📁 Estrutura de Arquivos no S3

```
s3://planify/backups/postgresql/
├── 2026/
│   ├── 01/
│   │   ├── 13/
│   │   │   ├── plannerate_production_20260113_030000.sql.gz
│   │   │   ├── plannerate_staging_20260113_030000.sql.gz
│   │   │   └── ...
│   │   ├── 12/
│   │   │   └── ...
│   │   └── ...
│   └── ...
└── ...
```

**Formato do nome:**
- `{database}_{YYYYMMDD}_{HHMMSS}.sql.gz`
- Exemplo: `plannerate_production_20260113_030000.sql.gz`

## 🔐 Segurança

### Permissões de Arquivos

```bash
# Proteger arquivo de credenciais
chmod 600 /root/.backup-env

# Proteger scripts
chmod 700 /root/backup-to-s3.sh
chmod 700 /root/restore-from-s3.sh
```

### Credenciais do Bucket

As credenciais estão configuradas para o bucket `planify` no DigitalOcean Spaces (região `sfo3`):

- **Access Key**: DO007CETKLCXD6WYKFZG
- **Secret Key**: BBB2eyUrD0UUvh78bnzM00SOuzQGNX/olpRBRyQkwoA
- **Endpoint**: https://sfo3.digitaloceanspaces.com

⚠️ **IMPORTANTE**: Nunca commitar credenciais no Git!

### Política do Bucket

Certifique-se de que o bucket tem as permissões corretas:
- Leitura/escrita para os objetos em `backups/postgresql/*`
- Listagem de objetos

## 📊 Monitoramento

### Verificar Último Backup

```bash
# Ver últimos backups
aws s3 ls --endpoint-url="https://sfo3.digitaloceanspaces.com" \
  --recursive "s3://planify/backups/postgresql/" | sort -r | head -5
```

### Ver Logs

```bash
# Log do cron
tail -f /var/log/postgresql-backup.log

# Log do sistema
journalctl -u cron -f
```

### Alertas

Para ser notificado de falhas, adicione ao final do `/root/backup-to-s3.sh`:

```bash
# Enviar email em caso de falha
if [ $FAILED_COUNT -gt 0 ]; then
    echo "Backup falhou em $(date)" | mail -s "ALERTA: Backup PostgreSQL Falhou" admin@plannerate.com.br
fi
```

## 🔍 Troubleshooting

### Erro: "Credenciais DO Spaces não configuradas"

```bash
# Verificar se variáveis estão carregadas
echo $DO_ACCESS_KEY_ID
echo $DO_SECRET_ACCESS_KEY

# Recarregar
source /root/.backup-env
```

### Erro: "Não foi possível conectar ao bucket"

```bash
# Testar conexão manualmente
export AWS_ACCESS_KEY_ID="DO007CETKLCXD6WYKFZG"
export AWS_SECRET_ACCESS_KEY="BBB2eyUrD0UUvh78bnzM00SOuzQGNX/olpRBRyQkwoA"

aws s3 ls --endpoint-url="https://sfo3.digitaloceanspaces.com" s3://planify/
```

### Erro: "pg_dump: error: connection to server failed"

```bash
# Verificar se PostgreSQL está rodando
systemctl status postgresql

# Testar conexão
psql -h 127.0.0.1 -U postgres -l
```

### Backup muito lento

```bash
# Usar formato custom (mais rápido)
# Editar backup-to-s3.sh, linha do pg_dump:
pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
    -d "$DB" --verbose --format=custom | gzip > "$BACKUP_FILE"
```

## 📈 Tamanho Estimado dos Backups

| Database | Tamanho Estimado | Comprimido |
|----------|------------------|------------|
| plannerate_production | ~500MB | ~150MB |
| plannerate_staging | ~200MB | ~60MB |

**Total diário**: ~210MB  
**Total mensal** (30 dias): ~6.3GB

## 🎯 Checklist de Implantação

### Produção
- [ ] Copiar scripts para servidor PostgreSQL
- [ ] Criar `/root/.backup-env` com `BACKUP_ENABLED="true"`
- [ ] Testar backup manual
- [ ] Verificar upload no S3
- [ ] Configurar cron para backup diário (3h)
- [ ] Testar restore
- [ ] Configurar alertas de falha

### Staging
- [ ] Copiar scripts para servidor
- [ ] Criar `/root/.backup-env` com `BACKUP_ENABLED="false"`
- [ ] Testar backup manual habilitando temporariamente
- [ ] Verificar upload no S3
- [ ] Documentar como habilitar se necessário

## 📚 Referências

- [PostgreSQL pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)
- [AWS CLI S3 Commands](https://docs.aws.amazon.com/cli/latest/reference/s3/)
- [DigitalOcean Spaces](https://docs.digitalocean.com/products/spaces/)

---

**Manutenção**: Revisar mensalmente o tamanho dos backups e ajustar retenção se necessário.
