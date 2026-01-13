#!/bin/bash
# Script de backup automático PostgreSQL para DigitalOcean Spaces
# Execute no servidor PostgreSQL: 72.62.139.43
# Configurável via variáveis de ambiente

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# CONFIGURAÇÕES (via variáveis de ambiente)
# ============================================

# Habilitar/desabilitar backup (padrão: true)
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"

# Credenciais DigitalOcean Spaces (obrigatórias)
DO_ACCESS_KEY_ID="${DO_ACCESS_KEY_ID}"
DO_SECRET_ACCESS_KEY="${DO_SECRET_ACCESS_KEY}"
DO_ENDPOINT="${DO_ENDPOINT:-https://sfo3.digitaloceanspaces.com}"
DO_BUCKET="${DO_BUCKET:-planify}"
DO_REGION="${DO_REGION:-sfo3}"

# PostgreSQL
POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
PGPASSWORD="${PGPASSWORD}"

# Databases para backup
DATABASES="${DATABASES:-plannerate_production plannerate_staging}"

# Diretório local temporário
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgresql}"

# Retenção de backups (dias)
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_FOLDER=$(date +%Y/%m/%d)

# ============================================
# VALIDAÇÕES
# ============================================

echo "================================================"
echo -e "${BLUE}  PLANNERATE - Backup PostgreSQL → S3${NC}"
echo "================================================"
echo ""

# Verificar se backup está habilitado
if [ "$BACKUP_ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠️  Backup desabilitado (BACKUP_ENABLED=$BACKUP_ENABLED)${NC}"
    echo "Para habilitar, defina: export BACKUP_ENABLED=true"
    exit 0
fi

# Verificar credenciais
if [ -z "$DO_ACCESS_KEY_ID" ] || [ -z "$DO_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}❌ ERRO: Credenciais DO Spaces não configuradas${NC}"
    echo "Configure as variáveis:"
    echo "  export DO_ACCESS_KEY_ID='your-key'"
    echo "  export DO_SECRET_ACCESS_KEY='your-secret'"
    exit 1
fi

if [ -z "$PGPASSWORD" ]; then
    echo -e "${RED}❌ ERRO: Senha do PostgreSQL não configurada${NC}"
    echo "Configure: export PGPASSWORD='your-password'"
    exit 1
fi

# Verificar se aws-cli está instalado
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}📦 Instalando AWS CLI...${NC}"
    apt update
    apt install -y awscli
fi

# Verificar se pg_dump está disponível
if ! command -v pg_dump &> /dev/null; then
    echo -e "${RED}❌ ERRO: pg_dump não encontrado${NC}"
    exit 1
fi

# Criar diretório de backup
mkdir -p "$BACKUP_DIR"

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
# REALIZAR BACKUPS
# ============================================

BACKUP_COUNT=0
FAILED_COUNT=0

for DB in $DATABASES; do
    echo -e "${YELLOW}📦 Iniciando backup: $DB${NC}"
    
    # Nome do arquivo
    BACKUP_FILE="$BACKUP_DIR/${DB}_${TIMESTAMP}.sql.gz"
    S3_PATH="s3://$DO_BUCKET/backups/postgresql/$DATE_FOLDER/${DB}_${TIMESTAMP}.sql.gz"
    
    # Fazer dump e comprimir
    echo "  → Executando pg_dump..."
    if pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
        -d "$DB" --verbose --format=plain \
        | gzip > "$BACKUP_FILE" 2>/tmp/pg_dump_error.log; then
        
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo -e "  ${GREEN}✅ Dump criado: $BACKUP_SIZE${NC}"
        
        # Upload para S3
        echo "  → Enviando para S3..."
        if aws s3 cp "$BACKUP_FILE" "$S3_PATH" \
            --endpoint-url="$DO_ENDPOINT" \
            --storage-class STANDARD \
            --metadata "database=$DB,timestamp=$TIMESTAMP,server=$(hostname)" \
            2>/tmp/s3_upload_error.log; then
            
            echo -e "  ${GREEN}✅ Upload concluído: $S3_PATH${NC}"
            
            # Remover arquivo local após upload bem-sucedido
            rm -f "$BACKUP_FILE"
            
            ((BACKUP_COUNT++))
        else
            echo -e "  ${RED}❌ Erro no upload para S3${NC}"
            cat /tmp/s3_upload_error.log
            ((FAILED_COUNT++))
        fi
    else
        echo -e "  ${RED}❌ Erro no pg_dump${NC}"
        cat /tmp/pg_dump_error.log
        ((FAILED_COUNT++))
    fi
    
    echo ""
done

# ============================================
# LIMPEZA - REMOVER BACKUPS ANTIGOS
# ============================================

echo -e "${YELLOW}🗑️  Limpando backups antigos (>${RETENTION_DAYS} dias)...${NC}"

# Listar e remover backups antigos
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y/%m/%d)

# Listar todos os backups e filtrar os antigos
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/postgresql/" \
    | awk '{print $4}' | while read -r FILE; do
    
    # Extrair data do caminho (formato: backups/postgresql/YYYY/MM/DD/file.sql.gz)
    FILE_DATE=$(echo "$FILE" | grep -oP '\d{4}/\d{2}/\d{2}')
    
    if [ -n "$FILE_DATE" ]; then
        FILE_DATE_NORMALIZED=$(echo "$FILE_DATE" | tr '/' '-')
        
        if [[ "$FILE_DATE_NORMALIZED" < "$CUTOFF_DATE" ]]; then
            echo "  → Removendo: $FILE (data: $FILE_DATE)"
            aws s3 rm --endpoint-url="$DO_ENDPOINT" "s3://$DO_BUCKET/$FILE"
        fi
    fi
done

echo ""

# ============================================
# RESUMO
# ============================================

echo "================================================"
if [ $FAILED_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ Backup concluído com sucesso!${NC}"
else
    echo -e "${YELLOW}⚠️  Backup concluído com erros${NC}"
fi
echo "================================================"
echo ""
echo -e "${BLUE}📊 Estatísticas:${NC}"
echo "  Backups bem-sucedidos: $BACKUP_COUNT"
echo "  Backups com falha: $FAILED_COUNT"
echo "  Retenção: $RETENTION_DAYS dias"
echo "  Bucket: $DO_BUCKET"
echo ""

# Listar backups recentes
echo -e "${BLUE}📁 Últimos backups (últimos 5):${NC}"
aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/postgresql/" \
    | sort -r | head -5 | while read -r line; do
    FILE=$(echo "$line" | awk '{print $4}')
    SIZE=$(echo "$line" | awk '{print $3}')
    SIZE_MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
    echo "  - $FILE (${SIZE_MB}MB)"
done

echo ""
echo -e "${YELLOW}💡 Dica: Para restaurar um backup, use:${NC}"
echo "  bash restore-from-s3.sh <database> <timestamp>"
echo ""

# Retornar código de erro se houver falhas
if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
fi

exit 0
