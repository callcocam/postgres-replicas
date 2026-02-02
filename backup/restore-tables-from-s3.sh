#!/bin/bash
# restore-tables-from-s3.sh
# Restauração de backups por tabelas do S3
# Suporta backups hourly e daily

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

DO_ACCESS_KEY_ID="${DO_ACCESS_KEY_ID}"
DO_SECRET_ACCESS_KEY="${DO_SECRET_ACCESS_KEY}"
DO_ENDPOINT="${DO_ENDPOINT:-https://sfo3.digitaloceanspaces.com}"
DO_BUCKET="${DO_BUCKET:-planify}"
DO_REGION="${DO_REGION:-sfo3}"

POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

RESTORE_DIR="${RESTORE_DIR:-/tmp/pg_restore}"

# Variáveis para cleanup
DOWNLOAD_FILE=""
EXTRACT_DIR=""

# ============================================
# FUNÇÃO DE LIMPEZA
# ============================================

cleanup() {
    if [ -n "$DOWNLOAD_FILE" ] && [ -f "$DOWNLOAD_FILE" ]; then
        rm -f "$DOWNLOAD_FILE"
    fi
    if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
        rm -rf "$EXTRACT_DIR"
    fi
}

trap cleanup EXIT

# ============================================
# CONFIGURAR AWS CLI
# ============================================

export AWS_ACCESS_KEY_ID="$DO_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DO_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$DO_REGION"

# ============================================
# AJUDA
# ============================================

show_help() {
    echo "================================================"
    echo -e "${BLUE}  PLANNERATE - Restore de Backups por Tabelas${NC}"
    echo "================================================"
    echo ""
    echo -e "${YELLOW}Uso:${NC}"
    echo "  $0 --list [hourly|daily]              Lista backups disponíveis"
    echo "  $0 --list-tables <backup_file>        Lista tabelas de um backup"
    echo "  $0 <database> [opções]                Restaura um banco"
    echo ""
    echo -e "${YELLOW}Opções de restauração:${NC}"
    echo "  --type <hourly|daily>    Tipo de backup (padrão: daily)"
    echo "  --timestamp <YYYYMMDD_HHMMSS>  Timestamp específico (padrão: último)"
    echo "  --tables <t1,t2,t3>      Restaurar apenas tabelas específicas"
    echo "  --all                    Restaurar todas as tabelas (padrão)"
    echo ""
    echo -e "${YELLOW}Exemplos:${NC}"
    echo "  $0 --list daily"
    echo "  $0 --list hourly"
    echo "  $0 plannerate_albert --type hourly"
    echo "  $0 plannerate_albert --type daily --timestamp 20260202_190621"
    echo "  $0 plannerate_albert --type hourly --tables planograms,gondolas"
    echo ""
    exit 0
}

# ============================================
# LISTAR BACKUPS
# ============================================

list_backups() {
    local TYPE=$1
    
    if [ -z "$TYPE" ]; then
        TYPE="daily"
    fi
    
    echo "================================================"
    echo -e "${BLUE}  Backups disponíveis (${TYPE})${NC}"
    echo "================================================"
    echo ""
    
    aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/${TYPE}/" 2>/dev/null \
        | sort -r | while read -r line; do
        FILE=$(echo "$line" | awk '{print $4}')
        SIZE=$(echo "$line" | awk '{print $3}')
        DATE=$(echo "$line" | awk '{print $1" "$2}')
        
        # Extrair nome do banco e timestamp
        BASENAME=$(basename "$FILE" .tar.gz)
        DB_NAME=$(echo "$BASENAME" | sed "s/_${TYPE}_[0-9]*_[0-9]*//")
        TIMESTAMP=$(echo "$BASENAME" | grep -oP '\d{8}_\d{6}')
        
        SIZE_MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
        
        echo -e "  ${GREEN}$DB_NAME${NC} | $TIMESTAMP | ${SIZE_MB}MB | $DATE"
    done
    
    echo ""
}

# ============================================
# LISTAR TABELAS DE UM BACKUP
# ============================================

list_tables_in_backup() {
    local BACKUP_PATH=$1
    
    echo -e "${YELLOW}🔍 Baixando backup para listar tabelas...${NC}"
    
    mkdir -p "$RESTORE_DIR"
    DOWNLOAD_FILE="$RESTORE_DIR/$(basename "$BACKUP_PATH")"
    
    if ! aws s3 cp "s3://$DO_BUCKET/$BACKUP_PATH" "$DOWNLOAD_FILE" --endpoint-url="$DO_ENDPOINT" 2>/dev/null; then
        echo -e "${RED}❌ Erro ao baixar backup${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}Tabelas no backup:${NC}"
    tar -tzf "$DOWNLOAD_FILE" | grep '\.tar$' | while read -r f; do
        TABLE=$(basename "$f" .tar)
        echo "  - $TABLE"
    done
    
    echo ""
}

# ============================================
# RESTAURAR BACKUP
# ============================================

restore_backup() {
    local DATABASE=$1
    local TYPE=$2
    local TIMESTAMP=$3
    local TABLES=$4
    
    echo "================================================"
    echo -e "${BLUE}  PLANNERATE - Restore de Backup${NC}"
    echo "================================================"
    echo ""
    
    # Validações
    if [ -z "$DO_ACCESS_KEY_ID" ] || [ -z "$DO_SECRET_ACCESS_KEY" ]; then
        echo -e "${RED}❌ ERRO: Credenciais DO Spaces não configuradas${NC}"
        exit 1
    fi
    
    if [ -z "$PGPASSWORD" ]; then
        echo -e "${RED}❌ ERRO: Senha do PostgreSQL não configurada${NC}"
        exit 1
    fi
    
    # Buscar backup
    echo -e "${YELLOW}🔍 Buscando backup...${NC}"
    
    if [ -z "$TIMESTAMP" ]; then
        # Buscar último backup
        echo "  → Procurando último backup $TYPE de $DATABASE..."
        
        BACKUP_FILE=$(aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/${TYPE}/" 2>/dev/null \
            | grep "${DATABASE}_${TYPE}_" | sort -r | head -1 | awk '{print $4}')
        
        if [ -z "$BACKUP_FILE" ]; then
            echo -e "${RED}❌ Nenhum backup encontrado para $DATABASE${NC}"
            echo ""
            echo "Use --list para ver backups disponíveis:"
            echo "  $0 --list $TYPE"
            exit 1
        fi
        
        TIMESTAMP=$(echo "$BACKUP_FILE" | grep -oP '\d{8}_\d{6}')
        echo -e "  ${GREEN}✅ Último backup: $TIMESTAMP${NC}"
    else
        # Buscar backup específico
        echo "  → Procurando backup $TIMESTAMP de $DATABASE..."
        
        BACKUP_FILE=$(aws s3 ls --endpoint-url="$DO_ENDPOINT" --recursive "s3://$DO_BUCKET/backups/${TYPE}/" 2>/dev/null \
            | grep "${DATABASE}_${TYPE}_${TIMESTAMP}" | head -1 | awk '{print $4}')
        
        if [ -z "$BACKUP_FILE" ]; then
            echo -e "${RED}❌ Backup não encontrado: ${DATABASE}_${TYPE}_${TIMESTAMP}${NC}"
            exit 1
        fi
        
        echo -e "  ${GREEN}✅ Backup encontrado${NC}"
    fi
    
    S3_PATH="s3://$DO_BUCKET/$BACKUP_FILE"
    
    echo ""
    
    # Confirmação
    echo -e "${YELLOW}⚠️  ATENÇÃO: Esta operação vai MODIFICAR o banco $DATABASE${NC}"
    echo ""
    echo -e "${BLUE}Detalhes:${NC}"
    echo "  Database: $DATABASE"
    echo "  Tipo: $TYPE"
    echo "  Timestamp: $TIMESTAMP"
    echo "  Arquivo: $BACKUP_FILE"
    if [ -n "$TABLES" ]; then
        echo "  Tabelas: $TABLES"
    else
        echo "  Tabelas: TODAS"
    fi
    echo ""
    
    read -p "Deseja continuar? (digite 'SIM' para confirmar): " CONFIRM
    
    if [ "$CONFIRM" != "SIM" ]; then
        echo -e "${YELLOW}❌ Operação cancelada${NC}"
        exit 0
    fi
    
    echo ""
    
    # Download do backup
    echo -e "${YELLOW}📥 Baixando backup do S3...${NC}"
    
    mkdir -p "$RESTORE_DIR"
    DOWNLOAD_FILE="$RESTORE_DIR/$(basename "$BACKUP_FILE")"
    
    if aws s3 cp "$S3_PATH" "$DOWNLOAD_FILE" --endpoint-url="$DO_ENDPOINT"; then
        FILE_SIZE=$(du -h "$DOWNLOAD_FILE" | cut -f1)
        echo -e "${GREEN}✅ Download concluído: $FILE_SIZE${NC}"
    else
        echo -e "${RED}❌ Erro ao baixar backup${NC}"
        exit 1
    fi
    
    echo ""
    
    # Extrair backup
    echo -e "${YELLOW}📦 Extraindo backup...${NC}"
    
    EXTRACT_DIR="$RESTORE_DIR/extract_$$"
    mkdir -p "$EXTRACT_DIR"
    
    if tar -xzf "$DOWNLOAD_FILE" -C "$EXTRACT_DIR"; then
        echo -e "${GREEN}✅ Extração concluída${NC}"
    else
        echo -e "${RED}❌ Erro ao extrair backup${NC}"
        exit 1
    fi
    
    # Encontrar diretório extraído
    BACKUP_DIR=$(find "$EXTRACT_DIR" -type d -name "${DATABASE}_*" | head -1)
    
    if [ -z "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Diretório de backup não encontrado${NC}"
        exit 1
    fi
    
    echo ""
    
    # Restaurar tabelas
    echo -e "${YELLOW}🔄 Restaurando tabelas...${NC}"
    echo ""
    
    RESTORE_COUNT=0
    FAILED_COUNT=0
    
    # Se tabelas específicas foram informadas
    if [ -n "$TABLES" ]; then
        IFS=',' read -ra TABLE_LIST <<< "$TABLES"
    else
        # Todas as tabelas
        TABLE_LIST=($(ls "$BACKUP_DIR"/*.tar 2>/dev/null | xargs -n1 basename | sed 's/\.tar$//'))
    fi
    
    for TABLE in "${TABLE_LIST[@]}"; do
        TABLE_FILE="$BACKUP_DIR/${TABLE}.tar"
        
        if [ ! -f "$TABLE_FILE" ]; then
            echo -e "  ${YELLOW}⚠️  Tabela '$TABLE' não encontrada no backup${NC}"
            continue
        fi
        
        echo -n "  → Restaurando $TABLE... "
        
        # Dropar tabela existente
        psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DATABASE" \
            -c "DROP TABLE IF EXISTS public.\"$TABLE\" CASCADE;" > /dev/null 2>&1
        
        # Restaurar tabela
        if pg_restore -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" \
            -d "$DATABASE" --no-owner --no-privileges "$TABLE_FILE" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
            RESTORE_COUNT=$((RESTORE_COUNT + 1))
        else
            # pg_restore pode retornar erro mesmo quando funciona (warnings)
            # Verificar se a tabela existe
            TABLE_EXISTS=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DATABASE" -t -c \
                "SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = '$TABLE';" 2>/dev/null | tr -d ' ')
            
            if [ "$TABLE_EXISTS" = "1" ]; then
                echo -e "${GREEN}OK${NC}"
                RESTORE_COUNT=$((RESTORE_COUNT + 1))
            else
                echo -e "${RED}ERRO${NC}"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
    done
    
    echo ""
    
    # Resumo
    echo "================================================"
    if [ $FAILED_COUNT -eq 0 ]; then
        echo -e "${GREEN}✅ Restore concluído com sucesso!${NC}"
    else
        echo -e "${YELLOW}⚠️  Restore concluído com erros${NC}"
    fi
    echo "================================================"
    echo ""
    echo -e "${BLUE}📊 Estatísticas:${NC}"
    echo "  Database: $DATABASE"
    echo "  Tabelas restauradas: $RESTORE_COUNT"
    echo "  Tabelas com erro: $FAILED_COUNT"
    echo "  Timestamp do backup: $TIMESTAMP"
    echo ""
    
    # Mostrar estatísticas do banco
    echo -e "${BLUE}📈 Estatísticas do banco:${NC}"
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DATABASE" -c "
SELECT 
    COUNT(*) as total_tables,
    pg_size_pretty(pg_database_size('$DATABASE')) as database_size
FROM pg_tables 
WHERE schemaname = 'public';
" 2>/dev/null
    
    echo ""
}

# ============================================
# MAIN
# ============================================

# Sem argumentos, mostrar ajuda
if [ $# -eq 0 ]; then
    show_help
fi

# Parsear argumentos
ACTION=""
DATABASE=""
TYPE="daily"
TIMESTAMP=""
TABLES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --list)
            ACTION="list"
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                TYPE="$2"
                shift
            fi
            shift
            ;;
        --list-tables)
            ACTION="list-tables"
            BACKUP_PATH="$2"
            shift 2
            ;;
        --type)
            TYPE="$2"
            shift 2
            ;;
        --timestamp)
            TIMESTAMP="$2"
            shift 2
            ;;
        --tables)
            TABLES="$2"
            shift 2
            ;;
        --all)
            TABLES=""
            shift
            ;;
        *)
            if [ -z "$DATABASE" ]; then
                DATABASE="$1"
            fi
            shift
            ;;
    esac
done

# Executar ação
case $ACTION in
    list)
        list_backups "$TYPE"
        ;;
    list-tables)
        list_tables_in_backup "$BACKUP_PATH"
        ;;
    *)
        if [ -z "$DATABASE" ]; then
            echo -e "${RED}❌ ERRO: Database não informado${NC}"
            echo ""
            show_help
        fi
        restore_backup "$DATABASE" "$TYPE" "$TIMESTAMP" "$TABLES"
        ;;
esac
