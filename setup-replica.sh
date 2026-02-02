#!/bin/bash
# Script para configurar PostgreSQL Réplica - Projeto Plannerate
# Para máquinas Ubuntu NOVAS
# Execute como root ou com sudo

set -e

echo "================================================"
echo "  PLANNERATE - Configuração PostgreSQL Réplica"
echo "================================================"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERRO: Execute como root ou com sudo${NC}"
    exit 1
fi

# Procurar arquivo de configuração
CONFIG_FILE=""
if [ -f "./replica-config.txt" ]; then
    CONFIG_FILE="./replica-config.txt"
elif [ -f "/root/replica-config.txt" ]; then
    CONFIG_FILE="/root/replica-config.txt"
elif [ -f "/tmp/replica-config.txt" ]; then
    CONFIG_FILE="/tmp/replica-config.txt"
fi

if [ -z "$CONFIG_FILE" ]; then
    echo -e "${RED}ERRO: Arquivo replica-config.txt não encontrado!${NC}"
    echo ""
    echo "O arquivo deve estar em um destes locais:"
    echo "  - ./replica-config.txt (diretório atual)"
    echo "  - /root/replica-config.txt"
    echo "  - /tmp/replica-config.txt"
    echo ""
    echo "Copie o arquivo replica-config.txt do servidor primário e tente novamente."
    exit 1
fi

echo -e "${GREEN}✓ Arquivo de configuração encontrado: $CONFIG_FILE${NC}"
echo ""

# Ler configurações do arquivo
source $CONFIG_FILE

# Validar variáveis
if [ -z "$PRIMARY_IP" ] || [ -z "$REPLICATOR_PASSWORD" ] || [ -z "$REPLICA_SLOT" ]; then
    echo -e "${RED}ERRO: Arquivo de configuração inválido!${NC}"
    echo "Verifique se o arquivo contém:"
    echo "  - PRIMARY_IP"
    echo "  - REPLICATOR_PASSWORD"
    echo "  - REPLICA_SLOT"
    exit 1
fi

echo -e "${YELLOW}Configuração lida do arquivo:${NC}"
echo "  Servidor Primário: $PRIMARY_IP"
echo "  Replication Slot: $REPLICA_SLOT"
echo "  PostgreSQL Version: $PG_VERSION"
echo ""
read -p "Confirma e deseja continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Configuração cancelada."
    exit 1
fi

# 1. Atualizar sistema
echo ""
echo -e "${GREEN}[1/10] Atualizando sistema...${NC}"
apt update -qq
apt upgrade -y -qq

# 2. Instalar pacotes essenciais
echo -e "${GREEN}[2/10] Instalando pacotes essenciais...${NC}"
apt install -y wget curl gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common

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

# 6. Parar PostgreSQL
echo -e "${GREEN}[6/10] Parando PostgreSQL...${NC}"
systemctl stop postgresql

# 7. Limpar dados
echo -e "${GREEN}[7/10] Limpando diretório de dados...${NC}"
rm -rf /var/lib/postgresql/$PG_VERSION/main/*

# 8. Configurar autenticação
echo -e "${GREEN}[8/10] Configurando autenticação...${NC}"
cat > /var/lib/postgresql/.pgpass <<EOF
$PRIMARY_IP:5432:replication:replicator:$REPLICATOR_PASSWORD
*:5432:*:replicator:$REPLICATOR_PASSWORD
EOF
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 0600 /var/lib/postgresql/.pgpass

# Testar conectividade
echo -e "${GREEN}[9/10] Testando conectividade com primário...${NC}"
echo "Servidor primário: $PRIMARY_IP"

if ! ping -c 2 $PRIMARY_IP &> /dev/null; then
    echo -e "${YELLOW}⚠ Aviso: Não foi possível pingar o servidor primário${NC}"
fi

echo "Testando conexão PostgreSQL..."
if ! sudo -u postgres PGPASSWORD=$REPLICATOR_PASSWORD psql -h $PRIMARY_IP -U replicator -d postgres -c "SELECT 1;" &> /dev/null; then
    echo -e "${RED}ERRO: Não foi possível conectar ao servidor primário!${NC}"
    echo ""
    echo "Verifique:"
    echo "  1. Servidor primário está rodando?"
    echo "  2. IP está correto? $PRIMARY_IP"
    echo "  3. Firewall permite porta 5432?"
    echo "  4. Senha está correta no replica-config.txt?"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Conexão com primário: OK!${NC}"

# 10. Sincronizar com pg_basebackup
echo -e "${GREEN}[10/10] Sincronizando dados do primário...${NC}"
echo "Isso pode demorar alguns minutos..."
echo ""

sudo -u postgres PGPASSWORD=$REPLICATOR_PASSWORD pg_basebackup \
    -h $PRIMARY_IP \
    -D /var/lib/postgresql/$PG_VERSION/main \
    -U replicator \
    -v \
    -P \
    -X stream \
    -c fast \
    -R \
    -S $REPLICA_SLOT

if [ $? -ne 0 ]; then
    echo -e "${RED}ERRO: Sincronização falhou!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Sincronização concluída!${NC}"

# Configurar postgresql.conf
PG_CONF="/var/lib/postgresql/$PG_VERSION/main/postgresql.conf"

cat >> $PG_CONF <<EOF

#==========================================
# PLANNERATE - CONFIGURAÇÕES DE RÉPLICA
#==========================================
hot_standby = on
hot_standby_feedback = on
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
wal_retrieve_retry_interval = 5s

# Permitir conexões remotas
listen_addresses = '*'
max_connections = 200
EOF

# Configurar primary_conninfo
cat > /var/lib/postgresql/$PG_VERSION/main/postgresql.auto.conf <<EOF
# Configuração automática de réplica - Plannerate
primary_conninfo = 'host=$PRIMARY_IP port=5432 user=replicator password=$REPLICATOR_PASSWORD application_name=$(hostname) sslmode=prefer'
primary_slot_name = '$REPLICA_SLOT'
EOF

# Garantir standby.signal
touch /var/lib/postgresql/$PG_VERSION/main/standby.signal

# Ajustar permissões
chown -R postgres:postgres /var/lib/postgresql/$PG_VERSION/main
chmod 700 /var/lib/postgresql/$PG_VERSION/main

# Configurar pg_hba.conf
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
cp $PG_HBA ${PG_HBA}.backup

cat > $PG_HBA <<EOF
# Plannerate - Réplica - Configuração de Autenticação
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local
local   all             all                                     peer
local   all             all                                     md5

# IPv4
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256

# IPv6
host    all             all             ::1/128                 scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF

# Configurar firewall
echo "Configurando firewall..."
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

ufw --force enable
ufw allow 22/tcp comment 'SSH'
ufw allow 5432/tcp comment 'PostgreSQL Plannerate Replica'
ufw reload

# Iniciar PostgreSQL
echo "Iniciando PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

sleep 5

if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}ERRO: PostgreSQL não iniciou${NC}"
    journalctl -u postgresql -n 50
    exit 1
fi

sleep 3

# Verificar status
RECOVERY_STATUS=$(sudo -u postgres psql -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | xargs)

IP_ADDRESS=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Criar arquivo de informações
mkdir -p /root/plannerate-config
cat > /root/plannerate-config/replica-info.txt <<EOF
================================================
PLANNERATE - Informações da Réplica
Gerado em: $TIMESTAMP
================================================

Hostname: $HOSTNAME
IP: $IP_ADDRESS
Porta: 5432
Modo: READ-ONLY (Réplica)

Conectada ao Primário: $PRIMARY_IP
Slot de Replicação: $REPLICA_SLOT

Recovery Mode: $RECOVERY_STATUS (deve ser 't')

========================================
PARA USAR NO LARAVEL
========================================

Adicione no .env para leitura na réplica:

# Leitura na Réplica
DB_READ_HOST=$IP_ADDRESS
DB_READ_PORT=5432

========================================
COMANDOS ÚTEIS
========================================

# Verificar modo recovery
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Verificar lag
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"

# Ver databases
sudo -u postgres psql -l

# Conectar produção (read-only)
sudo -u postgres psql -d plannerate_production

# Conectar staging (read-only)
sudo -u postgres psql -d plannerate_staging

# Status do serviço
systemctl status postgresql
EOF

chmod 600 /root/plannerate-config/replica-info.txt

# Exibir resumo
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Informações da Réplica:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP_ADDRESS"
echo "  Porta: 5432"
echo "  Modo: READ-ONLY (Réplica)"
echo ""
echo -e "${YELLOW}Status:${NC}"
echo "  Conectada ao: $PRIMARY_IP"
echo "  Slot: $REPLICA_SLOT"
echo "  Recovery Mode: $RECOVERY_STATUS $([ "$RECOVERY_STATUS" = "t" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"
echo ""
echo -e "${YELLOW}Databases replicados:${NC}"
echo "  📦 plannerate_production (read-only)"
echo "  📦 plannerate_staging (read-only)"
echo ""
echo -e "${YELLOW}Para usar no Laravel:${NC}"
echo "  Adicione no .env:"
echo "  ${GREEN}DB_READ_HOST=$IP_ADDRESS${NC}"
echo "  ${GREEN}DB_READ_PORT=5432${NC}"
echo ""
echo -e "${YELLOW}Arquivo de informações:${NC}"
echo "  ${GREEN}cat /root/plannerate-config/replica-info.txt${NC}"
echo ""
echo -e "${YELLOW}Verificar sincronização:${NC}"
echo "  ${GREEN}sudo -u postgres psql -d plannerate_production -c 'SELECT COUNT(*) FROM migrations;'${NC}"
echo ""
echo -e "${GREEN}Réplica pronta e sincronizando! 🚀${NC}"
echo ""