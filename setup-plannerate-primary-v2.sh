#!/bin/bash
# Script para configurar PostgreSQL PRIMÁRIO - PLANNERATE
# Baseado no setup-primary.sh que FUNCIONA
# Para máquinas Ubuntu NOVAS sem nada instalado
# Execute como root ou com sudo

set -e

echo "======================================"
echo "  POSTGRESQL PRIMÁRIO - PLANNERATE"
echo "======================================"
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Versão do PostgreSQL
PG_VERSION="17"
POSTGRES_USER="postgres"

# Gerar senhas seguras automaticamente
REPLICATOR_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
POSTGRES_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

echo -e "${YELLOW}Este script irá:${NC}"
echo "  1. Atualizar o sistema"
echo "  2. Instalar PostgreSQL 17"
echo "  3. Criar 3 bancos: laravel, plannerate_staging, plannerate_production"
echo "  4. Criar 3 slots de replicação"
echo "  5. Configurar replicação streaming"
echo "  6. Gerar senhas seguras"
echo "  7. Salvar credenciais em .plannerate-credentials.txt"
echo ""
read -p "Deseja continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Instalação cancelada."
    exit 1
fi

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERRO: Execute como root ou com sudo${NC}"
    exit 1
fi

# 1. Atualizar sistema
echo ""
echo -e "${GREEN}[1/9] Atualizando sistema...${NC}"
apt update -qq
apt upgrade -y -qq

# 2. Instalar pacotes essenciais
echo -e "${GREEN}[2/9] Instalando pacotes essenciais...${NC}"
apt install -y wget curl gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common

# 3. Adicionar repositório oficial do PostgreSQL
echo -e "${GREEN}[3/9] Adicionando repositório PostgreSQL...${NC}"
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# 4. Atualizar lista de pacotes
echo -e "${GREEN}[4/9] Atualizando lista de pacotes...${NC}"
apt update -qq

# 5. Instalar PostgreSQL
echo -e "${GREEN}[5/9] Instalando PostgreSQL $PG_VERSION...${NC}"
apt install -y postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-client-$PG_VERSION

# Aguardar PostgreSQL iniciar
sleep 3

# 6. Parar PostgreSQL para configuração
echo -e "${GREEN}[6/9] Configurando PostgreSQL...${NC}"
systemctl stop postgresql

# Configurar postgresql.conf
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

# Backup do arquivo original
cp $PG_CONF ${PG_CONF}.backup

# Adicionar configurações de replicação
cat >> $PG_CONF <<EOF

#==========================================
# CONFIGURAÇÕES DE REPLICAÇÃO - PRIMÁRIO
# PLANNERATE PROJECT
#==========================================

# WAL (Write-Ahead Logging)
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB

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

# Performance
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
EOF

# Criar diretório de archive
mkdir -p /var/lib/postgresql/$PG_VERSION/main/archive
chown -R postgres:postgres /var/lib/postgresql/$PG_VERSION/main/archive
chmod 700 /var/lib/postgresql/$PG_VERSION/main/archive

# Configurar pg_hba.conf
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
cp $PG_HBA ${PG_HBA}.backup

# Adicionar regras de autenticação
cat >> $PG_HBA <<EOF

#==========================================
# CONFIGURAÇÕES DE REPLICAÇÃO - PLANNERATE
#==========================================
# Permitir replicação de qualquer IP
host    replication     replicator      0.0.0.0/0               scram-sha-256
# Permitir conexões normais de qualquer IP
host    all             all             0.0.0.0/0               scram-sha-256
# IPv6
host    replication     replicator      ::/0                    scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF

# 7. Iniciar PostgreSQL
echo -e "${GREEN}[7/9] Iniciando PostgreSQL...${NC}"
systemctl start postgresql
systemctl enable postgresql

# Aguardar PostgreSQL iniciar completamente
sleep 5

# Verificar se está rodando
if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}ERRO: PostgreSQL não iniciou corretamente${NC}"
    echo "Verifique os logs: journalctl -u postgresql -n 50"
    exit 1
fi

# 8. Criar usuários e bancos de dados
echo -e "${GREEN}[8/9] Criando usuários, bancos e slots...${NC}"
sudo -u postgres psql <<EOF
-- Criar usuário de replicação
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '$REPLICATOR_PASSWORD';

-- Alterar senha do usuário postgres
ALTER USER postgres WITH PASSWORD '$POSTGRES_ADMIN_PASSWORD';

-- Criar os 3 bancos do Plannerate
CREATE DATABASE laravel;
CREATE DATABASE plannerate_staging;
CREATE DATABASE plannerate_production;

-- Criar slots de replicação físicos (3 para até 3 réplicas)
SELECT pg_create_physical_replication_slot('plannerate_replica_slot_1');
SELECT pg_create_physical_replication_slot('plannerate_replica_slot_2');
SELECT pg_create_physical_replication_slot('plannerate_replica_slot_3');

-- Verificar slots criados
SELECT slot_name, slot_type, active FROM pg_replication_slots;

-- Verificar configurações
SELECT name, setting FROM pg_settings 
WHERE name IN ('wal_level', 'max_wal_senders', 'max_replication_slots', 'listen_addresses', 'max_connections');
EOF

# 9. Configurar firewall
echo -e "${GREEN}[9/9] Configurando firewall...${NC}"

# Instalar UFW se não estiver instalado
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

# Configurar regras
ufw --force enable
ufw allow 22/tcp comment 'SSH'
ufw allow 5432/tcp comment 'PostgreSQL'
ufw reload

# Obter informações da máquina
IP_ADDRESS=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

# Salvar credenciais
CREDENTIALS_FILE="$HOME/.plannerate-credentials.txt"
cat > $CREDENTIALS_FILE <<EOF
#==========================================
# CREDENCIAIS POSTGRESQL - PLANNERATE
# Gerado automaticamente em: $(date)
#==========================================

# IP do servidor primário
PRIMARY_IP=$IP_ADDRESS

# Credenciais de replicação
REPLICATOR_USER=replicator
REPLICATOR_PASSWORD=$REPLICATOR_PASSWORD

# Credenciais admin PostgreSQL
POSTGRES_USER=postgres
POSTGRES_ADMIN_PASSWORD=$POSTGRES_ADMIN_PASSWORD

# Bancos de dados
DB_DEV=laravel
DB_STAGING=plannerate_staging
DB_PRODUCTION=plannerate_production

# Slots de replicação
SLOT_1=plannerate_replica_slot_1
SLOT_2=plannerate_replica_slot_2
SLOT_3=plannerate_replica_slot_3

# Versão PostgreSQL
PG_VERSION=$PG_VERSION
EOF

chmod 600 $CREDENTIALS_FILE

# Exibir resumo
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Informações do Servidor Primário:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP_ADDRESS"
echo "  Porta: 5432"
echo "  PostgreSQL: $PG_VERSION"
echo ""
echo -e "${YELLOW}Bancos de Dados Criados:${NC}"
echo "  - laravel (desenvolvimento)"
echo "  - plannerate_staging"
echo "  - plannerate_production"
echo ""
echo -e "${YELLOW}Slots de Replicação:${NC}"
echo "  - plannerate_replica_slot_1"
echo "  - plannerate_replica_slot_2"
echo "  - plannerate_replica_slot_3"
echo ""
echo -e "${YELLOW}Credenciais salvas em:${NC}"
echo "  ${GREEN}$CREDENTIALS_FILE${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANTE - Copie este arquivo para as réplicas:${NC}"
echo "  ${GREEN}scp $CREDENTIALS_FILE user@replica-ip:~/${NC}"
echo ""
echo -e "${YELLOW}Próximos Passos:${NC}"
echo "  1. Copie o arquivo de credenciais para as máquinas réplicas"
echo "  2. Execute setup-plannerate-replica-v2.sh nas réplicas"
echo ""
echo -e "${YELLOW}Comandos Úteis:${NC}"
echo "  Ver réplicas conectadas:"
echo "    ${GREEN}sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'${NC}"
echo ""
echo "  Ver bancos:"
echo "    ${GREEN}sudo -u postgres psql -c '\l'${NC}"
echo ""
echo "  Status do serviço:"
echo "    ${GREEN}systemctl status postgresql${NC}"
echo ""
echo -e "${GREEN}Servidor primário pronto para aceitar réplicas!${NC}"
echo ""

