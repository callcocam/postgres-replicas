#!/bin/bash
# Script para configurar PostgreSQL Primário - Projeto Plannerate
# Para máquinas Ubuntu NOVAS
# Execute como root ou com sudo

set -e

echo "================================================"
echo "  PLANNERATE - Configuração PostgreSQL Primário"
echo "================================================"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações
PG_VERSION="15"
PROJECT_NAME="plannerate"

# Gerar senhas seguras aleatórias
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-24
}

POSTGRES_ADMIN_PASS=$(generate_password)
REPLICATOR_PASS=$(generate_password)
PROD_USER_PASS=$(generate_password)
STAGING_USER_PASS=$(generate_password)

# Databases
DB_PRODUCTION="${PROJECT_NAME}_production"
DB_STAGING="${PROJECT_NAME}_staging"
USER_PRODUCTION="${PROJECT_NAME}_prod"
USER_STAGING="${PROJECT_NAME}_staging"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERRO: Execute como root ou com sudo${NC}"
    exit 1
fi

echo -e "${YELLOW}Projeto: Plannerate${NC}"
echo -e "${YELLOW}Databases que serão criados:${NC}"
echo "  - ${DB_PRODUCTION} (produção)"
echo "  - ${DB_STAGING} (homologação/teste)"
echo ""
read -p "Deseja continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Instalação cancelada."
    exit 1
fi

# 1. Atualizar sistema
echo ""
echo -e "${GREEN}[1/10] Atualizando sistema...${NC}"
apt update -qq
apt upgrade -y -qq

# 2. Instalar pacotes essenciais
echo -e "${GREEN}[2/10] Instalando pacotes essenciais...${NC}"
apt install -y wget curl gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common openssl

# 3. Adicionar repositório PostgreSQL
echo -e "${GREEN}[3/10] Adicionando repositório PostgreSQL...${NC}"
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# 4. Atualizar lista
echo -e "${GREEN}[4/10] Atualizando lista de pacotes...${NC}"
apt update -qq

# 5. Instalar PostgreSQL
echo -e "${GREEN}[5/10] Instalando PostgreSQL $PG_VERSION...${NC}"
apt install -y postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-client-$PG_VERSION

sleep 3

# 6. Parar para configuração
echo -e "${GREEN}[6/10] Configurando PostgreSQL...${NC}"
systemctl stop postgresql

# Configurar postgresql.conf
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
cp $PG_CONF ${PG_CONF}.backup

cat >> $PG_CONF <<EOF

#==========================================
# PLANNERATE - CONFIGURAÇÕES DE REPLICAÇÃO
#==========================================

# WAL
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 2GB

# Hot Standby
hot_standby = on

# Archive
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/$PG_VERSION/main/archive/%f && cp %p /var/lib/postgresql/$PG_VERSION/main/archive/%f'

# Conexões
listen_addresses = '*'
max_connections = 200

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'mod'
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Performance para Laravel
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
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
EOF

# Criar diretório archive
mkdir -p /var/lib/postgresql/$PG_VERSION/main/archive
chown -R postgres:postgres /var/lib/postgresql/$PG_VERSION/main/archive
chmod 700 /var/lib/postgresql/$PG_VERSION/main/archive

# Configurar pg_hba.conf
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
cp $PG_HBA ${PG_HBA}.backup

cat >> $PG_HBA <<EOF

#==========================================
# PLANNERATE - AUTENTICAÇÃO
#==========================================
# Replicação
host    replication     replicator      0.0.0.0/0               scram-sha-256
# Databases de aplicação
host    ${DB_PRODUCTION}    ${USER_PRODUCTION}    0.0.0.0/0     scram-sha-256
host    ${DB_STAGING}       ${USER_STAGING}       0.0.0.0/0     scram-sha-256
# Admin
host    all             postgres        0.0.0.0/0               scram-sha-256
# Qualquer outro
host    all             all             0.0.0.0/0               scram-sha-256
EOF

# 7. Iniciar PostgreSQL
echo -e "${GREEN}[7/10] Iniciando PostgreSQL...${NC}"
systemctl start postgresql
systemctl enable postgresql

sleep 5

if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}ERRO: PostgreSQL não iniciou${NC}"
    journalctl -u postgresql -n 50
    exit 1
fi

# 8. Criar estrutura de databases
echo -e "${GREEN}[8/10] Criando databases e usuários...${NC}"
sudo -u postgres psql <<EOF
-- Alterar senha do postgres
ALTER USER postgres WITH PASSWORD '$POSTGRES_ADMIN_PASS';

-- Criar usuário de replicação
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '$REPLICATOR_PASS';

-- ========================================
-- DATABASE DE PRODUÇÃO
-- ========================================
CREATE DATABASE ${DB_PRODUCTION};
CREATE USER ${USER_PRODUCTION} WITH PASSWORD '$PROD_USER_PASS';
GRANT ALL PRIVILEGES ON DATABASE ${DB_PRODUCTION} TO ${USER_PRODUCTION};

\c ${DB_PRODUCTION}

-- Conceder privilégios no schema public
GRANT ALL ON SCHEMA public TO ${USER_PRODUCTION};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${USER_PRODUCTION};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${USER_PRODUCTION};

-- Criar extensões úteis para Laravel
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ========================================
-- DATABASE DE STAGING
-- ========================================
\c postgres
CREATE DATABASE ${DB_STAGING};
CREATE USER ${USER_STAGING} WITH PASSWORD '$STAGING_USER_PASS';
GRANT ALL PRIVILEGES ON DATABASE ${DB_STAGING} TO ${USER_STAGING};

\c ${DB_STAGING}

-- Conceder privilégios no schema public
GRANT ALL ON SCHEMA public TO ${USER_STAGING};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${USER_STAGING};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${USER_STAGING};

-- Criar extensões
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ========================================
-- SLOTS DE REPLICAÇÃO
-- ========================================
\c postgres
SELECT pg_create_physical_replication_slot('replica1_slot');

-- Verificar
SELECT slot_name, slot_type, active FROM pg_replication_slots;
EOF

# 9. Configurar firewall
echo -e "${GREEN}[9/10] Configurando firewall...${NC}"
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

ufw --force enable
ufw allow 22/tcp comment 'SSH'
ufw allow 5432/tcp comment 'PostgreSQL Plannerate'
ufw reload

# 10. Gerar arquivos de configuração
echo -e "${GREEN}[10/10] Gerando arquivos de configuração...${NC}"

IP_ADDRESS=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Criar diretório de configurações
mkdir -p /root/plannerate-config
cd /root/plannerate-config

# ========================================
# ARQUIVO 1: Configuração para Réplica
# ========================================
cat > replica-config.txt <<EOF
# ================================================
# PLANNERATE - Configuração para Réplica
# Gerado em: $TIMESTAMP
# ================================================

PRIMARY_IP=$IP_ADDRESS
REPLICATOR_PASSWORD=$REPLICATOR_PASS
REPLICA_SLOT=replica1_slot
PG_VERSION=$PG_VERSION

# INSTRUÇÕES:
# 1. Copie este arquivo para a máquina réplica
# 2. Coloque no mesmo diretório do setup-plannerate-replica.sh
# 3. Execute: ./setup-plannerate-replica.sh
EOF

# ========================================
# ARQUIVO 2: Laravel .env - PRODUÇÃO
# ========================================
cat > laravel-env-production.txt <<EOF
# ================================================
# PLANNERATE - Laravel .env (PRODUÇÃO)
# Gerado em: $TIMESTAMP
# ================================================

# Database - Produção (Primary Server - Read/Write)
DB_CONNECTION=pgsql
DB_HOST=$IP_ADDRESS
DB_PORT=5432
DB_DATABASE=${DB_PRODUCTION}
DB_USERNAME=${USER_PRODUCTION}
DB_PASSWORD=$PROD_USER_PASS

# Para usar réplica para leitura (após configurar):
# DB_READ_HOST=IP_DA_REPLICA
# DB_READ_PORT=5432

# Outras configurações PostgreSQL
DB_SCHEMA=public
DB_SSLMODE=prefer
EOF

# ========================================
# ARQUIVO 3: Laravel .env - STAGING
# ========================================
cat > laravel-env-staging.txt <<EOF
# ================================================
# PLANNERATE - Laravel .env (STAGING)
# Gerado em: $TIMESTAMP
# ================================================

# Database - Staging (Primary Server - Read/Write)
DB_CONNECTION=pgsql
DB_HOST=$IP_ADDRESS
DB_PORT=5432
DB_DATABASE=${DB_STAGING}
DB_USERNAME=${USER_STAGING}
DB_PASSWORD=$STAGING_USER_PASS

# Outras configurações PostgreSQL
DB_SCHEMA=public
DB_SSLMODE=prefer
EOF

# ========================================
# ARQUIVO 4: Laravel database.php - Configuração com Réplica
# ========================================
cat > laravel-database-config.php <<EOF
<?php
// ================================================
// PLANNERATE - database/database.php
// Configuração com suporte a réplica de leitura
// Gerado em: $TIMESTAMP
// ================================================

return [
    'default' => env('DB_CONNECTION', 'pgsql'),

    'connections' => [
        'pgsql' => [
            'driver' => 'pgsql',
            'read' => [
                'host' => [
                    env('DB_READ_HOST', env('DB_HOST', '127.0.0.1')),
                ],
            ],
            'write' => [
                'host' => [
                    env('DB_HOST', '127.0.0.1'),
                ],
            ],
            'sticky' => true,
            'port' => env('DB_PORT', '5432'),
            'database' => env('DB_DATABASE', 'forge'),
            'username' => env('DB_USERNAME', 'forge'),
            'password' => env('DB_PASSWORD', ''),
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => 'public',
            'sslmode' => 'prefer',
        ],
    ],
];
EOF

# ========================================
# ARQUIVO 5: Todas as Credenciais
# ========================================
cat > CREDENCIAIS-COMPLETAS.txt <<EOF
================================================
PLANNERATE - CREDENCIAIS COMPLETAS
Servidor: $HOSTNAME
IP: $IP_ADDRESS
Gerado em: $TIMESTAMP
================================================

⚠️  MANTENHA ESTE ARQUIVO SEGURO ⚠️

========================================
POSTGRESQL ADMIN
========================================
Host: $IP_ADDRESS
Port: 5432
User: postgres
Password: $POSTGRES_ADMIN_PASS

========================================
REPLICAÇÃO
========================================
User: replicator
Password: $REPLICATOR_PASS
Slot: replica1_slot

========================================
PRODUÇÃO
========================================
Database: ${DB_PRODUCTION}
User: ${USER_PRODUCTION}
Password: $PROD_USER_PASS

Connection String:
postgresql://${USER_PRODUCTION}:$PROD_USER_PASS@$IP_ADDRESS:5432/${DB_PRODUCTION}

========================================
STAGING
========================================
Database: ${DB_STAGING}
User: ${USER_STAGING}
Password: $STAGING_USER_PASS

Connection String:
postgresql://${USER_STAGING}:$STAGING_USER_PASS@$IP_ADDRESS:5432/${DB_STAGING}

========================================
COMANDOS ÚTEIS
========================================

# Conectar ao database de produção
psql -h $IP_ADDRESS -U ${USER_PRODUCTION} -d ${DB_PRODUCTION}

# Conectar ao database de staging
psql -h $IP_ADDRESS -U ${USER_STAGING} -d ${DB_STAGING}

# Ver réplicas conectadas
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Backup produção
pg_dump -h $IP_ADDRESS -U ${USER_PRODUCTION} ${DB_PRODUCTION} > backup_production.sql

# Backup staging
pg_dump -h $IP_ADDRESS -U ${USER_STAGING} ${DB_STAGING} > backup_staging.sql
EOF

# Proteger arquivos
chmod 600 *.txt *.php

# Exibir resumo
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${BLUE}📁 Arquivos criados em: /root/plannerate-config/${NC}"
echo ""
echo -e "${YELLOW}Arquivos gerados:${NC}"
echo "  ✅ replica-config.txt              (copiar para réplica)"
echo "  ✅ laravel-env-production.txt      (copiar para .env produção)"
echo "  ✅ laravel-env-staging.txt         (copiar para .env staging)"
echo "  ✅ laravel-database-config.php     (config/database.php)"
echo "  ✅ CREDENCIAIS-COMPLETAS.txt       (MANTER SEGURO!)"
echo ""
echo -e "${YELLOW}Informações:${NC}"
echo "  Servidor: $HOSTNAME"
echo "  IP: $IP_ADDRESS"
echo "  Porta: 5432"
echo ""
echo -e "${YELLOW}Databases criados:${NC}"
echo "  📦 ${DB_PRODUCTION} (produção)"
echo "  📦 ${DB_STAGING} (staging)"
echo ""
echo -e "${YELLOW}Para configurar a réplica:${NC}"
echo "  1. Copie o arquivo replica-config.txt para a máquina réplica"
echo "  2. Execute: ${GREEN}./setup-plannerate-replica.sh${NC}"
echo ""
echo -e "${YELLOW}Ver os arquivos gerados:${NC}"
echo "  ${GREEN}cd /root/plannerate-config${NC}"
echo "  ${GREEN}ls -la${NC}"
echo ""
echo -e "${YELLOW}Ver credenciais:${NC}"
echo "  ${GREEN}cat /root/plannerate-config/CREDENCIAIS-COMPLETAS.txt${NC}"
echo ""
echo -e "${GREEN}Servidor primário pronto! 🚀${NC}"
echo ""