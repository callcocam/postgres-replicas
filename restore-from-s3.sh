#!/bin/bash
# Script de restore de backup PostgreSQL do DigitalOcean Spaces
# Execute no servidor PostgreSQL: 72.62.139.43

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# VALIDAÇÃO DE PARÂMETROS
# ============================================

if [ $# -lt 1 ]; then
    echo -e "${RED}Uso: $0 <database> [timestamp]${NC}"
    echo ""
    echo "Exemplos:"
    echo "  $0 plannerate_production                    # Restaura último backup"
    echo "  $0 plannerate_production 20260113_120000    # Restaura backup específico"
    echo "  $0 plannerate_production --list             # Lista backups disponíveis"
    echo ""
    exit 1
fi

DATABASE=$1
TIMESTAMP=$2

# ============================================
# CONFIGURAÇÕES
# ============================================

DO_ACCESS_KEY_ID="${DO_ACCESS_KEY_ID}"
DO_SECRET_ACCESS_KEY="${DO_SECRET_ACCESS_KEY}"
DO_ENDPOINT="${DO_ENDPOINT:-https://sfo3.digitaloceanspaces.com}"
DO_BUCKET="${DO_BUCKET:-planify}"
DO_REGION="${DO_REGION:-sfo3}"

POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
PGPASSWORD="${PGPASSWORD}"

RESTORE_DIR="${RESTORE_DIR:-/tmp/pg_restore}"

# ============================================
# VALIDAÇÕES
# ============================================

echo "================================================"
echo -e "${BLUE}  PLANNERATE - Restore PostgreSQL ← S3${NC}"
echo "================================================"
echo ""

# Verificar credenciais
if [ -z "$DO_ACCESS_KEY_ID" ] || [ -z "$DO_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}❌ ERRO: Credenciais DO Spaces não configuradas${NC}"
    exit 1
fi

if [ -z "$PGPASSWORD" ]; then
    echo -e "${RED}❌ ERRO: Senha do PostgreSQL não configurada${NC}"
    exit 1
fi

# Configurar AWS CLI
export AWS_ACCESS_KEY_ID="$DO_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DO_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$DO_REGION"

# ============================================
# LISTAR BACKUPS
# ============================================

if [ "$TIMESTAMP" = "--list" ]; then
    echo -e "${YELLOW}📁 Backups disponíveis para $DATABASE:${NC}"
    echo ""
    
    aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/postgresql/" \
        | grep "$DATABASE" | sort -r | while read -r line; do
        FILE=$(echo "$line" | awk '{print $4}')
        SIZE=$(echo "$line" | awk '{print $3}')
        DATE=$(echo "$line" | awk '{print $1" "$2}')
        SIZE_MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
        
        # Extrair timestamp do nome do arquivo
        BACKUP_TS=$(echo "$FILE" | grep -oP '\d{8}_\d{6}')
        
        echo -e "  ${GREEN}$BACKUP_TS${NC} - ${SIZE_MB}MB - $DATE"
    done
    
    echo ""
    exit 0
fi

# ============================================
# BUSCAR BACKUP
# ============================================

echo -e "${YELLOW}🔍 Buscando backup...${NC}"

if [ -z "$TIMESTAMP" ]; then
    # Buscar último backup
    echo "  → Procurando último backup de $DATABASE..."
    
    BACKUP_FILE=$(aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/postgresql/" \
        | grep "$DATABASE" | sort -r | head -1 | awk '{print $4}')
    
    if [ -z "$BACKUP_FILE" ]; then
        echo -e "${RED}❌ Nenhum backup encontrado para $DATABASE${NC}"
        exit 1
    fi
    
    TIMESTAMP=$(echo "$BACKUP_FILE" | grep -oP '\d{8}_\d{6}')
    echo -e "  ${GREEN}✅ Último backup: $TIMESTAMP${NC}"
else
    # Buscar backup específico
    echo "  → Procurando backup $TIMESTAMP de $DATABASE..."
    
    BACKUP_FILE=$(aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/postgresql/" \
        | grep "$DATABASE" | grep "$TIMESTAMP" | head -1 | awk '{print $4}')
    
    if [ -z "$BACKUP_FILE" ]; then
        echo -e "${RED}❌ Backup não encontrado: ${DATABASE}_${TIMESTAMP}${NC}"
        echo ""
        echo "Use --list para ver backups disponíveis:"
        echo "  $0 $DATABASE --list"
        exit 1
    fi
    
    echo -e "  ${GREEN}✅ Backup encontrado${NC}"
fi

S3_PATH="s3://$DO_BUCKET/$BACKUP_FILE"
LOCAL_FILE="$RESTORE_DIR/$(basename $BACKUP_FILE)"

echo ""

# ============================================
# CONFIRMAÇÃO
# ============================================

echo -e "${YELLOW}⚠️  ATENÇÃO: Esta operação vai SOBRESCREVER o banco $DATABASE${NC}"
echo ""
echo -e "${BLUE}Detalhes:${NC}"
echo "  Database: $DATABASE"
echo "  Backup: $TIMESTAMP"
echo "  Arquivo: $BACKUP_FILE"
echo ""

read -p "Deseja continuar? (digite 'SIM' para confirmar): " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    echo -e "${YELLOW}❌ Operação cancelada${NC}"
    exit 0
fi

echo ""

# ============================================
# DOWNLOAD DO BACKUP
# ============================================

echo -e "${YELLOW}📥 Baixando backup do S3...${NC}"

mkdir -p "$RESTORE_DIR"

if aws s3 cp "$S3_PATH" "$LOCAL_FILE" --endpoint-url="$DO_ENDPOINT"; then
    FILE_SIZE=$(du -h "$LOCAL_FILE" | cut -f1)
    echo -e "${GREEN}✅ Download concluído: $FILE_SIZE${NC}"
else
    echo -e "${RED}❌ Erro ao baixar backup${NC}"
    exit 1
fi

echo ""

# ============================================
# RESTAURAR BACKUP
# ============================================

echo -e "${YELLOW}🔄 Desconectando usuários do banco...${NC}"

# Terminar conexões ativas
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres << EOF
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = '$DATABASE'
  AND pid <> pg_backend_pid();
EOF

echo ""
echo -e "${YELLOW}🗑️  Recriando database...${NC}"

# Drop e recriar database
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres << EOF
DROP DATABASE IF EXISTS "$DATABASE";
CREATE DATABASE "$DATABASE";
EOF

echo ""
echo -e "${YELLOW}📦 Restaurando dados...${NC}"

# Restaurar backup
if gunzip -c "$LOCAL_FILE" | psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" -d "$DATABASE" > /tmp/restore.log 2>&1; then
    
    echo -e "${GREEN}✅ Restore concluído com sucesso!${NC}"
else
    echo -e "${RED}❌ Erro durante restore${NC}"
    echo "Verifique o log: /tmp/restore.log"
    exit 1
fi

# ============================================
# LIMPEZA
# ============================================

echo ""
echo -e "${YELLOW}🗑️  Limpando arquivos temporários...${NC}"
rm -f "$LOCAL_FILE"

# ============================================
# RESUMO
# ============================================

echo ""
echo "================================================"
echo -e "${GREEN}✅ Restore concluído com sucesso!${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}📊 Informações:${NC}"
echo "  Database: $DATABASE"
echo "  Backup: $TIMESTAMP"
echo "  Servidor: $POSTGRES_HOST:$POSTGRES_PORT"
echo ""

# Mostrar estatísticas do banco
echo -e "${BLUE}📈 Estatísticas do banco restaurado:${NC}"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DATABASE" -c "
SELECT 
    schemaname,
    COUNT(*) as tables,
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))::bigint) as size
FROM pg_tables 
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname;
"

echo ""
echo -e "${GREEN}✅ Database $DATABASE restaurado com sucesso!${NC}"
echo ""
