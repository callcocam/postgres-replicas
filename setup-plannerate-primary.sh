#!/bin/bash
# ============================================
# PLANNERATE - PostgreSQL Primary Setup
# ============================================
# Script para configurar servidor PostgreSQL PRIMÁRIO
# para o projeto Plannerate com 3 databases
#
# Autor: Plannerate Team
# Versão: 1.0
# Data: 2025-01-09
# ============================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   PLANNERATE - PostgreSQL Primary Setup${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ ERRO: Execute como root ou com sudo${NC}"
    echo -e "   Exemplo: ${YELLOW}sudo bash setup-plannerate-primary.sh${NC}"
    exit 1
fi

# ============================================
# CONFIGURAÇÕES FIXAS DO PLANNERATE
# ============================================
PG_VERSION="17"
PRIMARY_IP="192.168.2.106"

# Usuários
ADMIN_USER="plannerate_admin"
REPLICATOR_USER="plannerate_replicator"

# Databases
DB_DEV="laravel"
DB_STAGING="plannerate_staging"
DB_PRODUCTION="plannerate_production"

# Slot de replicação
REPLICA_SLOT="plannerate_replica_slot"

# ============================================
# FUNÇÕES AUXILIARES
# ============================================

# Gerar senha segura (32 caracteres alfanuméricos)
generate_password() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
}

# Exibir banner de progresso
progress() {
    echo ""
    echo -e "${GREEN}[$1/$2] $3${NC}"
}

# ============================================
# GERAR SENHAS SEGURAS
# ============================================
echo -e "${YELLOW}🔐 Gerando senhas seguras...${NC}"
ADMIN_PASSWORD=$(generate_password)
REPLICATOR_PASSWORD=$(generate_password)
POSTGRES_PASSWORD=$(generate_password)

echo -e "${GREEN}✅ Senhas geradas com sucesso!${NC}"

# ============================================
# CONFIRMAÇÃO
# ============================================
echo ""
echo -e "${YELLOW}📋 Configuração do Servidor Primário:${NC}"
echo ""
echo -e "  ${CYAN}IP do Servidor:${NC} $PRIMARY_IP"
echo -e "  ${CYAN}PostgreSQL:${NC} v$PG_VERSION"
echo ""
echo -e "${YELLOW}👤 Usuários:${NC}"
echo -e "  • ${CYAN}Admin:${NC} $ADMIN_USER (senha gerada)"
echo -e "  • ${CYAN}Replicação:${NC} $REPLICATOR_USER (senha gerada)"
echo -e "  • ${CYAN}Postgres:${NC} postgres (senha gerada)"
echo ""
echo -e "${YELLOW}🗄️  Databases:${NC}"
echo -e "  • ${CYAN}Development:${NC} $DB_DEV"
echo -e "  • ${CYAN}Staging:${NC} $DB_STAGING"
echo -e "  • ${CYAN}Production:${NC} $DB_PRODUCTION"
echo ""
echo -e "${YELLOW}⚙️  Replicação:${NC}"
echo -e "  • ${CYAN}Slot:${NC} $REPLICA_SLOT"
echo -e "  • ${CYAN}Máx Réplicas:${NC} 3"
echo ""
echo -e "${YELLOW}📝 Este script irá:${NC}"
echo "  1. Atualizar o sistema"
echo "  2. Instalar PostgreSQL $PG_VERSION"
echo "  3. Criar 3 databases (dev, staging, production)"
echo "  4. Configurar replicação streaming"
echo "  5. Criar usuários com senhas seguras"
echo "  6. Salvar credenciais em arquivo seguro"
echo "  7. Configurar firewall (UFW)"
echo ""
echo -e "${RED}⚠️  ATENÇÃO:${NC}"
echo -e "  • Este script irá ${RED}PARAR e RECONFIGURAR${NC} o PostgreSQL se já existir"
echo -e "  • Certifique-se de ter ${YELLOW}backup dos dados${NC} antes de continuar"
echo ""
read -p "Deseja continuar? (Digite 'SIM' em maiúsculas): " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    echo ""
    echo -e "${YELLOW}⏸️  Instalação cancelada pelo usuário.${NC}"
    echo ""
    exit 0
fi

# ============================================
# INÍCIO DA INSTALAÇÃO
# ============================================
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Iniciando Instalação...${NC}"
echo -e "${CYAN}============================================${NC}"

# ============================================
# 1. ATUALIZAR SISTEMA
# ============================================
progress "1" "10" "Atualizando sistema..."
apt update -qq > /dev/null 2>&1
apt upgrade -y -qq > /dev/null 2>&1
echo -e "${GREEN}   ✓ Sistema atualizado${NC}"

# ============================================
# 2. INSTALAR PACOTES ESSENCIAIS
# ============================================
progress "2" "10" "Instalando pacotes essenciais..."
apt install -y -qq wget curl gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common > /dev/null 2>&1
echo -e "${GREEN}   ✓ Pacotes instalados${NC}"

# ============================================
# 3. ADICIONAR REPOSITÓRIO POSTGRESQL
# ============================================
progress "3" "10" "Adicionando repositório PostgreSQL..."
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - > /dev/null 2>&1
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt update -qq > /dev/null 2>&1
echo -e "${GREEN}   ✓ Repositório adicionado${NC}"

# ============================================
# 4. INSTALAR POSTGRESQL
# ============================================
progress "4" "10" "Instalando PostgreSQL $PG_VERSION..."

# Verificar se já está instalado
if systemctl is-active --quiet postgresql 2>/dev/null; then
    echo -e "${YELLOW}   ⚠️  PostgreSQL já instalado. Parando serviço...${NC}"
    systemctl stop postgresql
fi

apt install -y -qq postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-client-$PG_VERSION > /dev/null 2>&1
echo -e "${GREEN}   ✓ PostgreSQL instalado${NC}"

# ============================================
# 5. CRIAR E CONFIGURAR CLUSTER POSTGRESQL
# ============================================
progress "5" "10" "Configurando PostgreSQL..."

# Caminhos de configuração
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
PG_DATA="/var/lib/postgresql/$PG_VERSION/main"

# Verificar se cluster existe, se não, criar
if [ ! -d "/etc/postgresql/$PG_VERSION/main" ]; then
    echo -e "${YELLOW}   Criando cluster PostgreSQL...${NC}"
    pg_createcluster $PG_VERSION main --start > /dev/null 2>&1 || true
    sleep 3
fi

# Parar para configurar
systemctl stop postgresql

# Backup dos arquivos originais
if [ -f "$PG_CONF" ]; then
    cp $PG_CONF ${PG_CONF}.backup.$(date +%Y%m%d_%H%M%S)
fi
if [ -f "$PG_HBA" ]; then
    cp $PG_HBA ${PG_HBA}.backup.$(date +%Y%m%d_%H%M%S)
fi

# Configurar postgresql.conf
cat >> $PG_CONF <<EOF

#==========================================
# PLANNERATE - CONFIGURAÇÕES DE REPLICAÇÃO
#==========================================
# Data: $(date)
# Servidor: PRIMÁRIO
# IP: $PRIMARY_IP
#==========================================

# WAL (Write-Ahead Logging)
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 2GB

# Hot Standby
hot_standby = on

# Archive (desabilitado para simplificar)
archive_mode = off

# Conexões
listen_addresses = '*'
max_connections = 200

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'mod'
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_min_duration_statement = 1000

# Performance Tuning para Plannerate
shared_buffers = 512MB
effective_cache_size = 2GB
maintenance_work_mem = 128MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 8MB
min_wal_size = 2GB
max_wal_size = 8GB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# Autovacuum otimizado
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 30s
EOF

echo -e "${GREEN}   ✓ postgresql.conf configurado${NC}"

# Configurar pg_hba.conf
cat >> $PG_HBA <<EOF

#==========================================
# PLANNERATE - AUTENTICAÇÃO E REPLICAÇÃO
#==========================================
# Data: $(date)
# Servidor: PRIMÁRIO
#==========================================

# Permitir replicação de qualquer IP (rede local)
host    replication     $REPLICATOR_USER      0.0.0.0/0               scram-sha-256
host    replication     $REPLICATOR_USER      ::/0                    scram-sha-256

# Permitir conexões normais de qualquer IP (rede local)
host    all             all                   0.0.0.0/0               scram-sha-256
host    all             all                   ::/0                    scram-sha-256

# Conexão local
local   all             all                                           scram-sha-256
host    all             all                   127.0.0.1/32            scram-sha-256
host    all             all                   ::1/128                 scram-sha-256
EOF

echo -e "${GREEN}   ✓ pg_hba.conf configurado${NC}"

# ============================================
# 6. INICIAR POSTGRESQL
# ============================================
progress "6" "10" "Iniciando PostgreSQL..."

systemctl start postgresql
systemctl enable postgresql > /dev/null 2>&1

# Aguardar inicialização completa
sleep 5

# Verificar se está rodando
if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}   ❌ ERRO: PostgreSQL não iniciou${NC}"
    echo -e "${YELLOW}   Verifique os logs: journalctl -u postgresql -n 50${NC}"
    exit 1
fi

echo -e "${GREEN}   ✓ PostgreSQL iniciado${NC}"

# ============================================
# 7. CRIAR USUÁRIOS
# ============================================
progress "7" "10" "Criando usuários..."

sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF > /dev/null 2>&1
-- Alterar senha do usuário postgres
ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';

-- Criar usuário admin
CREATE ROLE $ADMIN_USER WITH LOGIN PASSWORD '$ADMIN_PASSWORD' SUPERUSER CREATEDB CREATEROLE;

-- Criar usuário de replicação
CREATE ROLE $REPLICATOR_USER WITH REPLICATION LOGIN PASSWORD '$REPLICATOR_PASSWORD';
EOF

echo -e "${GREEN}   ✓ Usuários criados${NC}"

# ============================================
# 8. CRIAR DATABASES E ESTRUTURAS
# ============================================
progress "8" "10" "Criando databases..."

# Função para criar database com estrutura base
create_database() {
    local DB_NAME=$1
    local DB_DESC=$2
    
    echo -e "   📦 Criando database: ${CYAN}$DB_NAME${NC} ($DB_DESC)"
    
    sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF > /dev/null 2>&1
-- Criar database
CREATE DATABASE $DB_NAME OWNER $ADMIN_USER;

-- Conectar ao database
\c $DB_NAME

-- Extensões úteis
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Conceder permissões ao replicator para leitura
GRANT CONNECT ON DATABASE $DB_NAME TO $REPLICATOR_USER;
GRANT USAGE ON SCHEMA public TO $REPLICATOR_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $REPLICATOR_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO $REPLICATOR_USER;

-- Tabela de healthcheck
CREATE TABLE IF NOT EXISTS healthcheck (
    id SERIAL PRIMARY KEY,
    service VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    last_check TIMESTAMP DEFAULT NOW(),
    message TEXT
);

-- Inserir registro inicial
INSERT INTO healthcheck (service, status, message) 
VALUES ('plannerate', 'healthy', 'Database initialized on $PRIMARY_IP');

-- Índices
CREATE INDEX IF NOT EXISTS idx_healthcheck_service ON healthcheck(service);
CREATE INDEX IF NOT EXISTS idx_healthcheck_last_check ON healthcheck(last_check);
EOF
    
    echo -e "      ${GREEN}✓ $DB_NAME criado${NC}"
}

# Criar os 3 databases
create_database "$DB_DEV" "Development"
create_database "$DB_STAGING" "Staging"
create_database "$DB_PRODUCTION" "Production"

# ============================================
# 9. CRIAR SLOT DE REPLICAÇÃO
# ============================================
progress "9" "10" "Configurando replicação..."

sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF > /dev/null 2>&1
-- Criar slots de replicação físicos (até 3 réplicas)
SELECT pg_create_physical_replication_slot('${REPLICA_SLOT}_1');
SELECT pg_create_physical_replication_slot('${REPLICA_SLOT}_2');
SELECT pg_create_physical_replication_slot('${REPLICA_SLOT}_3');
EOF

echo -e "${GREEN}   ✓ Slots de replicação criados:${NC}"
echo -e "      • ${REPLICA_SLOT}_1"
echo -e "      • ${REPLICA_SLOT}_2"
echo -e "      • ${REPLICA_SLOT}_3"

# ============================================
# 10. CONFIGURAR FIREWALL
# ============================================
progress "10" "10" "Configurando firewall..."

# Instalar UFW se não estiver instalado
if ! command -v ufw &> /dev/null; then
    apt install -y ufw > /dev/null 2>&1
fi

# Configurar regras
ufw --force enable > /dev/null 2>&1
ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
ufw allow 5432/tcp comment 'PostgreSQL Plannerate' > /dev/null 2>&1
ufw reload > /dev/null 2>&1

echo -e "${GREEN}   ✓ Firewall configurado${NC}"

# ============================================
# SALVAR CREDENCIAIS
# ============================================
CREDENTIALS_FILE="$(dirname "$0")/.plannerate-credentials.txt"
CREDENTIALS_ENV="$(dirname "$0")/.plannerate-env-example"

cat > $CREDENTIALS_FILE <<EOF
# ============================================
# PLANNERATE - PostgreSQL Credentials
# ============================================
# Gerado em: $(date)
# Servidor: $PRIMARY_IP:5432
# ============================================

# IMPORTANTE: Mantenha este arquivo SEGURO!
# NÃO COMMITE no Git!

# Servidor
PRIMARY_IP=$PRIMARY_IP
PRIMARY_PORT=5432

# Usuários e Senhas
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

ADMIN_USER=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASSWORD

REPLICATOR_USER=$REPLICATOR_USER
REPLICATOR_PASSWORD=$REPLICATOR_PASSWORD

# Databases
DB_DEV=$DB_DEV
DB_STAGING=$DB_STAGING
DB_PRODUCTION=$DB_PRODUCTION

# Replicação
REPLICA_SLOT=$REPLICA_SLOT
EOF

chmod 600 $CREDENTIALS_FILE

# Criar exemplo para .env
cat > $CREDENTIALS_ENV <<EOF
# ============================================
# PLANNERATE - Exemplo de configuração .env
# ============================================
# Copie estas configurações para seus arquivos .env

# ===== DEVELOPMENT (.env) =====
DB_CONNECTION=pgsql
DB_HOST=$PRIMARY_IP
DB_PORT=5432
DB_DATABASE=$DB_DEV
DB_USERNAME=$ADMIN_USER
DB_PASSWORD=$ADMIN_PASSWORD

# ===== STAGING (.env.staging) =====
DB_CONNECTION=pgsql
DB_HOST=$PRIMARY_IP
DB_PORT=5432
DB_DATABASE=$DB_STAGING
DB_USERNAME=$ADMIN_USER
DB_PASSWORD=$ADMIN_PASSWORD

# ===== PRODUCTION (.env.production) =====
DB_CONNECTION=pgsql
DB_HOST=$PRIMARY_IP
DB_PORT=5432
DB_DATABASE=$DB_PRODUCTION
DB_USERNAME=$ADMIN_USER
DB_PASSWORD=$ADMIN_PASSWORD
EOF

chmod 644 $CREDENTIALS_ENV

# ============================================
# VERIFICAÇÕES FINAIS
# ============================================
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Executando verificações finais...${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Verificar databases
DB_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_database WHERE datname IN ('$DB_DEV', '$DB_STAGING', '$DB_PRODUCTION');" | xargs)
echo -e "  ${CYAN}Databases criados:${NC} $DB_COUNT/3"

# Verificar usuários
USER_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_roles WHERE rolname IN ('$ADMIN_USER', '$REPLICATOR_USER');" | xargs)
echo -e "  ${CYAN}Usuários criados:${NC} $USER_COUNT/2"

# Verificar slots
SLOT_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = '$REPLICA_SLOT';" | xargs)
echo -e "  ${CYAN}Slots de replicação:${NC} $SLOT_COUNT/1"

# Verificar conexões
MAX_CONN=$(sudo -u postgres psql -t -c "SHOW max_connections;" | xargs)
echo -e "  ${CYAN}Máximo de conexões:${NC} $MAX_CONN"

# ============================================
# EXIBIR RESUMO FINAL
# ============================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   ✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}📡 Informações do Servidor:${NC}"
echo -e "  • IP: ${CYAN}$PRIMARY_IP${NC}"
echo -e "  • Porta: ${CYAN}5432${NC}"
echo -e "  • PostgreSQL: ${CYAN}v$PG_VERSION${NC}"
echo ""
echo -e "${YELLOW}👤 Usuários Criados:${NC}"
echo -e "  • Admin: ${CYAN}$ADMIN_USER${NC}"
echo -e "  • Replicação: ${CYAN}$REPLICATOR_USER${NC}"
echo -e "  • Postgres: ${CYAN}postgres${NC}"
echo ""
echo -e "${YELLOW}🗄️  Databases Criados:${NC}"
echo -e "  • Development: ${CYAN}$DB_DEV${NC}"
echo -e "  • Staging: ${CYAN}$DB_STAGING${NC}"
echo -e "  • Production: ${CYAN}$DB_PRODUCTION${NC}"
echo ""
echo -e "${YELLOW}⚙️  Replicação:${NC}"
echo -e "  • Slot: ${CYAN}$REPLICA_SLOT${NC}"
echo ""
echo -e "${YELLOW}🔐 Credenciais:${NC}"
echo -e "  • Arquivo: ${CYAN}$CREDENTIALS_FILE${NC}"
echo -e "  • Exemplo .env: ${CYAN}$CREDENTIALS_ENV${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANTE:${NC}"
echo -e "  • As credenciais estão salvas em: ${YELLOW}$CREDENTIALS_FILE${NC}"
echo -e "  • ${RED}Mantenha este arquivo SEGURO!${NC}"
echo -e "  • ${RED}NÃO compartilhe ou commite no Git!${NC}"
echo ""
echo -e "${YELLOW}📝 Próximos Passos:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Copie as configurações do arquivo:"
echo -e "     ${GREEN}cat $CREDENTIALS_ENV${NC}"
echo ""
echo -e "  ${CYAN}2.${NC} Atualize seus arquivos .env:"
echo -e "     • .env (development)"
echo -e "     • .env.staging"
echo -e "     • .env.production"
echo ""
echo -e "  ${CYAN}3.${NC} Configure a réplica:"
echo -e "     ${GREEN}sudo bash setup-plannerate-replica.sh${NC}"
echo ""
echo -e "  ${CYAN}4.${NC} Teste a conexão:"
echo -e "     ${GREEN}psql -h $PRIMARY_IP -U $ADMIN_USER -d $DB_DEV${NC}"
echo ""
echo -e "${YELLOW}🔍 Comandos Úteis:${NC}"
echo ""
echo -e "  ${CYAN}Ver status de replicação:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'${NC}"
echo ""
echo -e "  ${CYAN}Ver databases:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -l${NC}"
echo ""
echo -e "  ${CYAN}Testar healthcheck:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -d $DB_DEV -c 'SELECT * FROM healthcheck;'${NC}"
echo ""
echo -e "  ${CYAN}Status do serviço:${NC}"
echo -e "     ${GREEN}systemctl status postgresql${NC}"
echo ""
echo -e "${GREEN}🎉 Servidor primário pronto para aceitar réplicas!${NC}"
echo ""

