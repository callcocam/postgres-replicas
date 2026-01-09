#!/bin/bash
# Script para configurar PostgreSQL como servidor PRIMÁRIO
# Para máquinas Ubuntu NOVAS sem nada instalado
# Execute como root ou com sudo

set -e

echo "======================================"
echo "  CONFIGURAÇÃO POSTGRESQL PRIMÁRIO"
echo "======================================"
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#==========================================
# CONFIGURAÇÃO INTERATIVA
#==========================================
echo -e "${YELLOW}Configuração do Servidor Primário PostgreSQL${NC}"
echo ""

# Versão do PostgreSQL (fixo)
PG_VERSION="15"
POSTGRES_USER="postgres"

# Solicitar senha para o usuário replicator
echo "Senha para o usuário de replicação (replicator):"
while true; do
    read -p "Informe a senha [replicator_password]: " REPLICATOR_PASSWORD
    REPLICATOR_PASSWORD=${REPLICATOR_PASSWORD:-replicator_password}
    if [[ -z "$REPLICATOR_PASSWORD" ]]; then
        echo -e "${RED}Erro: Senha não pode estar vazia!${NC}"
    else
        break
    fi
done

# Solicitar senha para o usuário admin postgres
echo ""
echo "Senha para o usuário admin (postgres):"
while true; do
    read -p "Informe a senha [postgres_admin_password]: " POSTGRES_ADMIN_PASSWORD
    POSTGRES_ADMIN_PASSWORD=${POSTGRES_ADMIN_PASSWORD:-postgres_admin_password}
    if [[ -z "$POSTGRES_ADMIN_PASSWORD" ]]; then
        echo -e "${RED}Erro: Senha não pode estar vazia!${NC}"
    else
        break
    fi
done

# Solicitar nome do database
echo ""
read -p "Nome do database a ser criado [testdb]: " DB_NAME
DB_NAME=${DB_NAME:-testdb}

echo ""
echo -e "${YELLOW}Este script irá:${NC}"
echo "  1. Atualizar o sistema"
echo "  2. Instalar PostgreSQL 15"
echo "  3. Configurar replicação streaming"
echo "  4. Criar usuário e database de teste"
echo "  5. Configurar firewall"
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
max_connections = 100

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
# CONFIGURAÇÕES DE REPLICAÇÃO
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

# 8. Criar usuário de replicação e database
echo -e "${GREEN}[8/9] Criando usuário, database e estrutura...${NC}"
sudo -u postgres psql <<EOF
-- Criar usuário de replicação
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '$REPLICATOR_PASSWORD';

-- Alterar senha do usuário postgres para acesso remoto
ALTER USER postgres WITH PASSWORD '$POSTGRES_ADMIN_PASSWORD';

-- Criar database de teste
CREATE DATABASE $DB_NAME;

-- Conectar ao database
\c $DB_NAME

-- Criar schema e tabela de exemplo
CREATE TABLE test_replication (
    id SERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    hostname TEXT,
    ip_address TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Criar índice
CREATE INDEX idx_test_replication_created ON test_replication(created_at);

-- Inserir dados iniciais
INSERT INTO test_replication (data, hostname, ip_address) VALUES 
    ('Registro inicial 1 - Servidor Primário', '$(hostname)', '$(hostname -I | awk "{print \$1}")'),
    ('Registro inicial 2 - Servidor Primário', '$(hostname)', '$(hostname -I | awk "{print \$1}")'),
    ('Registro inicial 3 - Servidor Primário', '$(hostname)', '$(hostname -I | awk "{print \$1}")');

-- Criar função para atualizar updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS \$\$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
\$\$ language 'plpgsql';

-- Criar trigger
CREATE TRIGGER update_test_replication_updated_at BEFORE UPDATE
    ON test_replication FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Criar slots de replicação físicos
SELECT pg_create_physical_replication_slot('replica1_slot');
SELECT pg_create_physical_replication_slot('replica2_slot');

-- Verificar slots criados
SELECT slot_name, slot_type, active FROM pg_replication_slots;

-- Verificar configurações
SELECT name, setting FROM pg_settings 
WHERE name IN ('wal_level', 'max_wal_senders', 'max_replication_slots', 'listen_addresses');
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
echo ""
echo -e "${YELLOW}Credenciais PostgreSQL:${NC}"
echo "  Usuário Admin: postgres"
echo "  Senha Admin: $POSTGRES_ADMIN_PASSWORD"
echo "  Usuário Replicação: replicator"
echo "  Senha Replicação: $REPLICATOR_PASSWORD"
echo "  Database: $DB_NAME"
echo ""
echo -e "${YELLOW}Slots de Replicação Criados:${NC}"
echo "  - replica1_slot (para primeira réplica)"
echo "  - replica2_slot (para segunda réplica)"
echo ""
echo -e "${YELLOW}Próximos Passos:${NC}"
echo "  1. Anote o IP acima: ${GREEN}$IP_ADDRESS${NC}"
echo "  2. Configure as réplicas usando setup-replica.sh"
echo "  3. No setup-replica.sh, use PRIMARY_IP=\"$IP_ADDRESS\""
echo ""
echo -e "${YELLOW}Comandos Úteis:${NC}"
echo "  Ver réplicas conectadas:"
echo "    ${GREEN}sudo -u postgres psql -d $DB_NAME -c 'SELECT * FROM pg_stat_replication;'${NC}"
echo ""
echo "  Inserir dados de teste:"
echo "    ${GREEN}sudo -u postgres psql -d $DB_NAME -c \"INSERT INTO test_replication (data, hostname, ip_address) VALUES ('Teste', '$(hostname)', '$IP_ADDRESS');\"${NC}"
echo ""
echo "  Ver dados:"
echo "    ${GREEN}sudo -u postgres psql -d $DB_NAME -c 'SELECT * FROM test_replication;'${NC}"
echo ""
echo "  Status do serviço:"
echo "    ${GREEN}systemctl status postgresql${NC}"
echo ""
echo -e "${GREEN}Servidor primário pronto para aceitar réplicas!${NC}"
echo ""