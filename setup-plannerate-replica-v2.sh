#!/bin/bash
# Script para configurar PostgreSQL RÉPLICA - PLANNERATE
# Baseado no setup-replica.sh que FUNCIONA
# Para máquinas Ubuntu NOVAS sem nada instalado
# Execute como root ou com sudo

set -e

echo "======================================"
echo "  POSTGRESQL RÉPLICA - PLANNERATE"
echo "======================================"
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Versão do PostgreSQL
PG_VERSION="17"

#==========================================
# LER CREDENCIAIS DO ARQUIVO
#==========================================
# Procurar arquivo em múltiplos locais
CREDENTIALS_FILE=""

# 1. No diretório atual
if [ -f "./.plannerate-credentials.txt" ]; then
    CREDENTIALS_FILE="./.plannerate-credentials.txt"
# 2. No home do usuário que chamou sudo
elif [ -n "$SUDO_USER" ] && [ -f "/home/$SUDO_USER/.plannerate-credentials.txt" ]; then
    CREDENTIALS_FILE="/home/$SUDO_USER/.plannerate-credentials.txt"
# 3. No home do usuário atual
elif [ -f "$HOME/.plannerate-credentials.txt" ]; then
    CREDENTIALS_FILE="$HOME/.plannerate-credentials.txt"
# 4. No diretório do script
elif [ -f "$(dirname "$0")/.plannerate-credentials.txt" ]; then
    CREDENTIALS_FILE="$(dirname "$0")/.plannerate-credentials.txt"
fi

if [ -z "$CREDENTIALS_FILE" ]; then
    echo -e "${RED}ERRO: Arquivo de credenciais não encontrado!${NC}"
    echo ""
    echo "Procurei em:"
    echo "  - $(pwd)/.plannerate-credentials.txt"
    if [ -n "$SUDO_USER" ]; then
        echo "  - /home/$SUDO_USER/.plannerate-credentials.txt"
    fi
    echo "  - $HOME/.plannerate-credentials.txt"
    echo ""
    echo "Você precisa copiar o arquivo .plannerate-credentials.txt"
    echo "do servidor PRIMÁRIO para esta máquina."
    echo ""
    echo "Execute no PRIMÁRIO:"
    echo "  scp ~/.plannerate-credentials.txt user@$(hostname -I | awk '{print $1}'):~/"
    echo ""
    exit 1
fi

echo -e "${GREEN}Arquivo encontrado: $CREDENTIALS_FILE${NC}"

echo -e "${GREEN}Carregando credenciais...${NC}"
source $CREDENTIALS_FILE

# Validar variáveis obrigatórias
if [[ -z "$PRIMARY_IP" ]] || [[ -z "$REPLICATOR_USER" ]] || [[ -z "$REPLICATOR_PASSWORD" ]]; then
    echo -e "${RED}ERRO: Arquivo de credenciais inválido!${NC}"
    echo "Variáveis obrigatórias: PRIMARY_IP, REPLICATOR_USER, REPLICATOR_PASSWORD"
    exit 1
fi

#==========================================
# SELECIONAR SLOT DE REPLICAÇÃO
#==========================================
echo ""
echo -e "${YELLOW}Escolha o número desta réplica:${NC}"
echo "  1 - Primeira réplica (slot: plannerate_replica_slot_1)"
echo "  2 - Segunda réplica (slot: plannerate_replica_slot_2)"
echo "  3 - Terceira réplica (slot: plannerate_replica_slot_3)"
echo ""

while true; do
    read -p "Digite o número da réplica [1-3]: " REPLICA_NUM
    if [[ "$REPLICA_NUM" =~ ^[1-3]$ ]]; then
        break
    else
        echo -e "${RED}Erro: Digite apenas 1, 2 ou 3${NC}"
    fi
done

REPLICA_SLOT="plannerate_replica_slot_${REPLICA_NUM}"

# Exibir configuração
echo ""
echo -e "${YELLOW}Configuração:${NC}"
echo "  Servidor Primário: $PRIMARY_IP"
echo "  Replication Slot: $REPLICA_SLOT"
echo "  PostgreSQL Version: $PG_VERSION"
echo ""
echo -e "${YELLOW}Este script irá:${NC}"
echo "  1. Atualizar o sistema"
echo "  2. Instalar PostgreSQL 17"
echo "  3. Sincronizar dados do primário"
echo "  4. Configurar streaming replication"
echo "  5. Iniciar como réplica read-only"
echo ""
read -p "Confirma as configurações acima? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Configuração cancelada."
    exit 1
fi

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERRO: Execute como root ou com sudo${NC}"
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

# 3. Adicionar repositório oficial do PostgreSQL
echo -e "${GREEN}[3/10] Adicionando repositório PostgreSQL...${NC}"
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# 4. Atualizar lista de pacotes
echo -e "${GREEN}[4/10] Atualizando lista de pacotes...${NC}"
apt update -qq

# 5. Instalar PostgreSQL
echo -e "${GREEN}[5/10] Instalando PostgreSQL $PG_VERSION...${NC}"
apt install -y postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-client-$PG_VERSION

# 6. Parar PostgreSQL
echo -e "${GREEN}[6/10] Parando PostgreSQL...${NC}"
systemctl stop postgresql

# 7. Limpar diretório de dados
echo -e "${GREEN}[7/10] Limpando diretório de dados...${NC}"
rm -rf /var/lib/postgresql/$PG_VERSION/main/*

# 8. Configurar autenticação
echo -e "${GREEN}[8/10] Configurando autenticação...${NC}"
cat > /var/lib/postgresql/.pgpass <<EOF
$PRIMARY_IP:5432:replication:$REPLICATOR_USER:$REPLICATOR_PASSWORD
*:5432:*:$REPLICATOR_USER:$REPLICATOR_PASSWORD
EOF
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 0600 /var/lib/postgresql/.pgpass

# 9. Testar conectividade com primário
echo -e "${GREEN}[9/10] Testando conectividade com primário...${NC}"
echo "Verificando se o servidor primário está acessível..."

# Testar ping
if ! ping -c 2 $PRIMARY_IP &> /dev/null; then
    echo -e "${YELLOW}AVISO: Não foi possível pingar o servidor primário${NC}"
    echo "Tentando continuar mesmo assim..."
fi

# Testar conexão PostgreSQL
echo "Testando conexão PostgreSQL com o primário..."
if ! sudo -u postgres PGPASSWORD=$REPLICATOR_PASSWORD psql -h $PRIMARY_IP -U $REPLICATOR_USER -d postgres -c "SELECT 1;" &> /dev/null; then
    echo -e "${RED}ERRO: Não foi possível conectar ao servidor primário!${NC}"
    echo ""
    echo "Verifique:"
    echo "  1. O servidor primário está rodando?"
    echo "  2. O IP está correto? $PRIMARY_IP"
    echo "  3. O firewall está permitindo porta 5432?"
    echo "  4. A senha está correta?"
    echo ""
    echo "Teste manual:"
    echo "  sudo -u postgres PGPASSWORD=$REPLICATOR_PASSWORD psql -h $PRIMARY_IP -U $REPLICATOR_USER -d postgres -c 'SELECT 1;'"
    exit 1
fi

echo -e "${GREEN}Conexão com primário: OK!${NC}"

# 10. Executar pg_basebackup
echo -e "${GREEN}[10/10] Sincronizando dados do primário...${NC}"
echo "Isso pode demorar alguns minutos dependendo do tamanho do database..."
echo ""

sudo -u postgres PGPASSWORD=$REPLICATOR_PASSWORD pg_basebackup \
    -h $PRIMARY_IP \
    -D /var/lib/postgresql/$PG_VERSION/main \
    -U $REPLICATOR_USER \
    -v \
    -P \
    -X stream \
    -c fast \
    -R \
    -S $REPLICA_SLOT

if [ $? -ne 0 ]; then
    echo -e "${RED}ERRO: pg_basebackup falhou!${NC}"
    exit 1
fi

echo -e "${GREEN}Sincronização concluída!${NC}"

# Configurar postgresql.conf adicional
echo "Configurando parâmetros adicionais..."
PG_CONF="/var/lib/postgresql/$PG_VERSION/main/postgresql.conf"

cat >> $PG_CONF <<EOF

#==========================================
# CONFIGURAÇÕES DE RÉPLICA - PLANNERATE
#==========================================
hot_standby = on
hot_standby_feedback = on
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
wal_retrieve_retry_interval = 5s
max_connections = 200

# Permitir conexões remotas
listen_addresses = '*'
EOF

# Configurar primary_conninfo em postgresql.auto.conf
cat > /var/lib/postgresql/$PG_VERSION/main/postgresql.auto.conf <<EOF
# Configuração automática de réplica - PLANNERATE
primary_conninfo = 'host=$PRIMARY_IP port=5432 user=$REPLICATOR_USER password=$REPLICATOR_PASSWORD application_name=$(hostname) sslmode=prefer'
primary_slot_name = '$REPLICA_SLOT'
EOF

# Garantir que standby.signal existe
touch /var/lib/postgresql/$PG_VERSION/main/standby.signal

# Ajustar permissões
chown -R postgres:postgres /var/lib/postgresql/$PG_VERSION/main
chmod 700 /var/lib/postgresql/$PG_VERSION/main

# Configurar pg_hba.conf para permitir conexões locais e remotas
# Após pg_basebackup, o pg_hba.conf está no data directory, não em /etc
PG_HBA="/var/lib/postgresql/$PG_VERSION/main/pg_hba.conf"

# Fazer backup do arquivo original copiado do master
if [ -f "$PG_HBA" ]; then
    cp $PG_HBA ${PG_HBA}.backup.$(date +%Y%m%d_%H%M%S)
fi

cat > $PG_HBA <<EOF
# PostgreSQL Client Authentication Configuration File - REPLICA
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             all                                     peer
local   all             all                                     md5

# IPv4 local connections
host    all             all             127.0.0.1/32            scram-sha-256

# IPv4 remote connections (para acessar réplica remotamente)
host    all             all             0.0.0.0/0               scram-sha-256

# IPv6 connections
host    all             all             ::1/128                 scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF

# Configurar firewall
echo "Configurando firewall..."

# Instalar UFW se não estiver instalado
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

ufw --force enable
ufw allow 22/tcp comment 'SSH'
ufw allow 5432/tcp comment 'PostgreSQL'
ufw reload

# Iniciar PostgreSQL
echo "Iniciando PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Aguardar PostgreSQL iniciar
sleep 5

# Verificar se está rodando
if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}ERRO: PostgreSQL não iniciou corretamente${NC}"
    echo "Verifique os logs: journalctl -u postgresql -n 50"
    exit 1
fi

# Aguardar mais um pouco para garantir que está pronto
sleep 3

# Verificar status
echo "Verificando status da replicação..."

# Verificar se está em recovery mode
RECOVERY_STATUS=$(sudo -u postgres psql -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | xargs)

if [ "$RECOVERY_STATUS" != "t" ]; then
    echo -e "${RED}AVISO: Réplica não está em modo recovery!${NC}"
    echo "Status: $RECOVERY_STATUS (esperado: t)"
else
    echo -e "${GREEN}Modo recovery: OK!${NC}"
fi

# Obter informações da máquina
IP_ADDRESS=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

# Exibir resumo
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Informações da Réplica:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP_ADDRESS"
echo "  Porta: 5432"
echo "  Conectada ao primário: $PRIMARY_IP"
echo "  Slot de replicação: $REPLICA_SLOT"
echo "  Modo: READ-ONLY (Réplica)"
echo ""
echo -e "${YELLOW}Verificações:${NC}"
echo "  Recovery Mode: $RECOVERY_STATUS (deve ser 't')"
echo ""
echo -e "${YELLOW}Bancos Replicados:${NC}"
echo "  - laravel"
echo "  - plannerate_staging"
echo "  - plannerate_production"
echo ""
echo -e "${YELLOW}Comandos Úteis:${NC}"
echo ""
echo "  Verificar se está em recovery (réplica):"
echo "    ${GREEN}sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'${NC}"
echo ""
echo "  Verificar lag de replicação:"
echo "    ${GREEN}sudo -u postgres psql -c \"SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;\"${NC}"
echo ""
echo "  Ver bancos:"
echo "    ${GREEN}sudo -u postgres psql -c '\l'${NC}"
echo ""
echo "  Status do serviço:"
echo "    ${GREEN}systemctl status postgresql${NC}"
echo ""
echo "  Ver logs:"
echo "    ${GREEN}tail -f /var/log/postgresql/postgresql-$PG_VERSION-main.log${NC}"
echo ""
echo -e "${GREEN}Réplica configurada e sincronizando com o primário!${NC}"
echo ""

