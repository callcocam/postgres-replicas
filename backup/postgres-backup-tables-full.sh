#!/bin/bash
# postgres-backup-tables-full.sh
# Backup diário completo de todos os bancos (principal + clientes)
# Upload para S3 + limpeza local após upload
# Baseado no padrão backup-to-s3.sh

set -e

# ============================================
# CORES PARA OUTPUT
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# CARREGAR CONFIGURAÇÕES
# ============================================

# Arquivo de configuração
ENV_FILE="${ENV_FILE:-/root/.backup-env}"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo -e "${RED}❌ ERRO: Arquivo de configuração não encontrado: $ENV_FILE${NC}"
    exit 1
fi

# ============================================
# CONFIGURAÇÕES
# ============================================

# Habilitar/desabilitar backup (padrão: true)
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"

# Credenciais DigitalOcean Spaces
DO_ACCESS_KEY_ID="${DO_ACCESS_KEY_ID}"
DO_SECRET_ACCESS_KEY="${DO_SECRET_ACCESS_KEY}"
DO_ENDPOINT="${DO_ENDPOINT:-https://sfo3.digitaloceanspaces.com}"
DO_BUCKET="${DO_BUCKET:-planify}"
DO_REGION="${DO_REGION:-sfo3}"

# PostgreSQL
POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Diretório local temporário
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
BACKUP_TEMP_DIR="$BACKUP_DIR/temp_daily"

# Retenção de backups (dias)
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Tabelas a EXCLUIR do banco PRINCIPAL (production/staging)
EXCLUDE_TABLES_MAIN=(
    'cache'
    'cache_locks'
    'sessions'
    'jobs'
    'job_batches'
    'failed_jobs'
    'activity_log'
    'integration_sync_logs'
    'personal_access_tokens'
    'password_reset_tokens'
    'gondola_workflow_metrics'
    'gondola_notifications'
)

# Tabelas a EXCLUIR dos bancos de CLIENTES
EXCLUDE_TABLES_CLIENT=(
    'sales'
    'monthly_sales_summaries'
)

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_FOLDER=$(date +%Y/%m/%d)

# Contadores
BACKUP_COUNT=0
FAILED_COUNT=0
TOTAL_SIZE=0

# ============================================
# VALIDAÇÕES
# ============================================

echo "================================================"
echo -e "${BLUE}  PLANNERATE - Backup Diário Completo → S3${NC}"
echo "================================================"
echo ""

# Verificar se backup está habilitado
if [ "$BACKUP_ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠️  Backup desabilitado (BACKUP_ENABLED=$BACKUP_ENABLED)${NC}"
    exit 0
fi

# Verificar credenciais DO
if [ -z "$DO_ACCESS_KEY_ID" ] || [ -z "$DO_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}❌ ERRO: Credenciais DO Spaces não configuradas${NC}"
    exit 1
fi

# Verificar senha PostgreSQL
if [ -z "$PGPASSWORD" ]; then
    echo -e "${RED}❌ ERRO: Senha do PostgreSQL não configurada${NC}"
    exit 1
fi

# Verificar se pg_dump está disponível
if ! command -v pg_dump &> /dev/null; then
    echo -e "${RED}❌ ERRO: pg_dump não encontrado${NC}"
    exit 1
fi

# Verificar se aws-cli está instalado
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ ERRO: aws-cli não encontrado${NC}"
    exit 1
fi

# Criar diretório temporário
mkdir -p "$BACKUP_TEMP_DIR"

echo -e "${GREEN}✅ Validações concluídas${NC}"
echo ""

# ============================================
# CONFIGURAR AWS CLI
# ============================================

export AWS_ACCESS_KEY_ID="$DO_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DO_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$DO_REGION"

# Testar conexão com DO Spaces
echo -e "${YELLOW}🔍 Testando conexão com DigitalOcean Spaces...${NC}"
if aws s3 ls --endpoint-url="$DO_ENDPOINT" "s3://$DO_BUCKET" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Conexão com bucket '$DO_BUCKET' OK${NC}"
else
    echo -e "${RED}❌ ERRO: Não foi possível conectar ao bucket${NC}"
    exit 1
fi

echo ""

# ============================================
# FUNÇÃO: Verificar se tabela está na lista de exclusão
# ============================================
is_excluded() {
    local table=$1
    shift
    local exclude_list=("$@")
    
    for excluded in "${exclude_list[@]}"; do
        if [ "$table" = "$excluded" ]; then
            return 0  # true, está excluída
        fi
    done
    return 1  # false, não está excluída
}

# ============================================
# FUNÇÃO: Backup de um banco de dados
# ============================================
backup_database() {
    local DB=$1
    local DB_TYPE=$2  # 'main' ou 'client'
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📦 Banco: $DB ($DB_TYPE)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Criar diretório temporário para este banco
    local DB_BACKUP_DIR="$BACKUP_TEMP_DIR/${DB}_${TIMESTAMP}"
    mkdir -p "$DB_BACKUP_DIR"
    
    # Definir lista de exclusão baseada no tipo
    local EXCLUDE_LIST
    if [ "$DB_TYPE" = "main" ]; then
        EXCLUDE_LIST=("${EXCLUDE_TABLES_MAIN[@]}")
    else
        EXCLUDE_LIST=("${EXCLUDE_TABLES_CLIENT[@]}")
    fi
    
    # Listar todas as tabelas do banco
    local TABLES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DB" -t -c \
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")
    
    local TABLE_COUNT=0
    local TABLE_SUCCESS=0
    local DB_SUCCESS=true
    
    while IFS= read -r TABLE; do
        TABLE=$(echo "$TABLE" | tr -d ' ')
        
        if [ -z "$TABLE" ]; then
            continue
        fi
        
        # Verificar se a tabela está na lista de exclusão
        if is_excluded "$TABLE" "${EXCLUDE_LIST[@]}"; then
            echo -e "  ${YELLOW}⏭️  Pulando (excluída): $TABLE${NC}"
            continue
        fi
        
        TABLE_COUNT=$((TABLE_COUNT + 1))
        local BACKUP_FILE="$DB_BACKUP_DIR/${TABLE}.tar"
        
        echo -n "  → Backup $TABLE... "
        
        # Fazer dump da tabela
        if pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
            -d "$DB" -t "public.\"$TABLE\"" -F c -b -f "$BACKUP_FILE" 2>/dev/null; then
            
            local FILE_SIZE=$(du -h "$BACKUP_FILE" 2>/dev/null | cut -f1)
            echo -e "${GREEN}OK ($FILE_SIZE)${NC}"
            TABLE_SUCCESS=$((TABLE_SUCCESS + 1))
        else
            echo -e "${RED}ERRO${NC}"
            DB_SUCCESS=false
        fi
    done <<< "$TABLES"
    
    echo ""
    echo -e "  ${BLUE}Tabelas: $TABLE_SUCCESS/$TABLE_COUNT processadas${NC}"
    
    # Comprimir diretório
    echo -n "  → Comprimindo backup... "
    local TAR_FILE="$BACKUP_TEMP_DIR/${DB}_daily_${TIMESTAMP}.tar.gz"
    if tar -czf "$TAR_FILE" -C "$BACKUP_TEMP_DIR" "${DB}_${TIMESTAMP}" 2>/dev/null; then
        local TAR_SIZE=$(du -h "$TAR_FILE" | cut -f1)
        local TAR_BYTES=$(du -b "$TAR_FILE" | cut -f1)
        TOTAL_SIZE=$((TOTAL_SIZE + TAR_BYTES))
        echo -e "${GREEN}OK ($TAR_SIZE)${NC}"
        
        # Remover diretório temporário
        rm -rf "$DB_BACKUP_DIR"
    else
        echo -e "${RED}ERRO${NC}"
        DB_SUCCESS=false
        return 1
    fi
    
    # Upload para S3
    local S3_PATH="s3://$DO_BUCKET/backups/daily/$DATE_FOLDER/${DB}_daily_${TIMESTAMP}.tar.gz"
    
    echo -n "  → Upload para S3... "
    if aws s3 cp "$TAR_FILE" "$S3_PATH" \
        --endpoint-url="$DO_ENDPOINT" \
        --storage-class STANDARD \
        --metadata "database=$DB,type=daily,timestamp=$TIMESTAMP" \
        2>/dev/null; then
        
        echo -e "${GREEN}OK${NC}"
        
        # Remover arquivo local após upload bem-sucedido
        rm -f "$TAR_FILE"
        
        BACKUP_COUNT=$((BACKUP_COUNT + 1))
    else
        echo -e "${RED}ERRO${NC}"
        DB_SUCCESS=false
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    if [ "$DB_SUCCESS" = true ]; then
        echo -e "  ${GREEN}✅ Backup de $DB concluído${NC}"
    else
        echo -e "  ${RED}❌ Backup de $DB com erros${NC}"
    fi
    
    echo ""
}

# ============================================
# LISTAR TODOS OS BANCOS
# ============================================

echo -e "${YELLOW}🔍 Listando bancos plannerate_*...${NC}"

# Bancos principais
MAIN_DATABASES=('plannerate_production' 'plannerate_staging')

# Bancos de clientes
CLIENT_DATABASES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -t -c \
    "SELECT datname FROM pg_database WHERE datname LIKE 'plannerate_%' AND datname NOT IN ('plannerate_production', 'plannerate_staging') ORDER BY datname;")

# Converter para array
CLIENT_DB_ARRAY=()
while IFS= read -r line; do
    DB=$(echo "$line" | tr -d ' ')
    if [ -n "$DB" ]; then
        CLIENT_DB_ARRAY+=("$DB")
    fi
done <<< "$CLIENT_DATABASES"

TOTAL_DBS=$((${#MAIN_DATABASES[@]} + ${#CLIENT_DB_ARRAY[@]}))
echo -e "${GREEN}✅ Encontrados $TOTAL_DBS bancos (${#MAIN_DATABASES[@]} principais + ${#CLIENT_DB_ARRAY[@]} clientes)${NC}"
echo ""

# ============================================
# REALIZAR BACKUPS
# ============================================

START_TIME=$(date +%s)

# Backup dos bancos principais
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  BANCOS PRINCIPAIS${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

for DB in "${MAIN_DATABASES[@]}"; do
    # Verificar se o banco existe
    DB_EXISTS=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -t -c \
        "SELECT 1 FROM pg_database WHERE datname = '$DB';" 2>/dev/null | tr -d ' ')
    
    if [ "$DB_EXISTS" = "1" ]; then
        backup_database "$DB" "main"
    else
        echo -e "${YELLOW}⚠️  Banco $DB não encontrado, pulando...${NC}"
        echo ""
    fi
done

# Backup dos bancos de clientes
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  BANCOS DE CLIENTES${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

for DB in "${CLIENT_DB_ARRAY[@]}"; do
    backup_database "$DB" "client"
done

# ============================================
# LIMPEZA - REMOVER BACKUPS ANTIGOS NO S3
# ============================================

echo -e "${YELLOW}🗑️  Limpando backups antigos (>${RETENTION_DAYS} dias)...${NC}"

# Calcular data de corte
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)

# Listar e remover backups antigos
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/daily/" 2>/dev/null \
    | awk '{print $4}' | while read -r FILE; do
    
    # Extrair data do caminho (formato: backups/daily/YYYY/MM/DD/file.tar.gz)
    FILE_DATE=$(echo "$FILE" | grep -oP '\d{4}/\d{2}/\d{2}' | head -1)
    
    if [ -n "$FILE_DATE" ]; then
        # Converter para formato YYYY-MM-DD
        FILE_DATE_NORMALIZED=$(echo "$FILE_DATE" | tr '/' '-')
        
        if [[ "$FILE_DATE_NORMALIZED" < "$CUTOFF_DATE" ]]; then
            echo "  → Removendo: $FILE"
            aws s3 rm --endpoint-url="$DO_ENDPOINT" "s3://$DO_BUCKET/$FILE" 2>/dev/null || true
        fi
    fi
done

echo ""

# ============================================
# LIMPEZA LOCAL - REMOVER ARQUIVOS TEMPORÁRIOS
# ============================================

echo -e "${YELLOW}🗑️  Limpando arquivos temporários locais...${NC}"
rm -rf "$BACKUP_TEMP_DIR"/*
echo -e "${GREEN}✅ Limpeza local concluída${NC}"

echo ""

# ============================================
# RESUMO
# ============================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Converter tamanho total para formato legível
if [ $TOTAL_SIZE -gt 1073741824 ]; then
    TOTAL_SIZE_FMT="$(echo "scale=2; $TOTAL_SIZE / 1073741824" | bc)GB"
elif [ $TOTAL_SIZE -gt 1048576 ]; then
    TOTAL_SIZE_FMT="$(echo "scale=2; $TOTAL_SIZE / 1048576" | bc)MB"
else
    TOTAL_SIZE_FMT="$(echo "scale=2; $TOTAL_SIZE / 1024" | bc)KB"
fi

echo "================================================"
if [ $FAILED_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ Backup diário concluído com sucesso!${NC}"
else
    echo -e "${YELLOW}⚠️  Backup diário concluído com erros${NC}"
fi
echo "================================================"
echo ""
echo -e "${BLUE}📊 Estatísticas:${NC}"
echo "  Bancos processados: $TOTAL_DBS"
echo "  Backups bem-sucedidos: $BACKUP_COUNT"
echo "  Backups com falha: $FAILED_COUNT"
echo "  Tamanho total: $TOTAL_SIZE_FMT"
echo "  Tempo total: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
echo "  Retenção: $RETENTION_DAYS dias"
echo "  Bucket: $DO_BUCKET/backups/daily/"
echo ""

# Tabelas excluídas
echo -e "${BLUE}🚫 Tabelas excluídas (principal):${NC}"
echo "  ${EXCLUDE_TABLES_MAIN[*]}"
echo ""
echo -e "${BLUE}🚫 Tabelas excluídas (clientes):${NC}"
echo "  ${EXCLUDE_TABLES_CLIENT[*]}"
echo ""

# Listar backups recentes
echo -e "${BLUE}📁 Últimos backups diários (5):${NC}"
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/daily/" 2>/dev/null \
    | sort -r | head -5 | while read -r line; do
    FILE=$(echo "$line" | awk '{print $4}')
    SIZE=$(echo "$line" | awk '{print $3}')
    SIZE_MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
    echo "  - $FILE (${SIZE_MB}MB)"
done

echo ""

# Retornar código de erro se houver falhas
if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
fi

exit 0
