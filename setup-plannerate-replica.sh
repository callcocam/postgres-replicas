#!/bin/bash
# ============================================
# PLANNERATE - PostgreSQL Replica Setup
# ============================================
# Script para configurar servidor PostgreSQL RÉPLICA
# para o projeto Plannerate
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
echo -e "${CYAN}   PLANNERATE - PostgreSQL Replica Setup${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ ERRO: Execute como root ou com sudo${NC}"
    echo -e "   Exemplo: ${YELLOW}sudo bash setup-plannerate-replica.sh${NC}"
    exit 1
fi

# ============================================
# VERIFICAR ARQUIVO DE CREDENCIAIS
# ============================================
CREDENTIALS_FILE="$(dirname "$0")/.plannerate-credentials.txt"

if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo -e "${RED}❌ ERRO: Arquivo de credenciais não encontrado!${NC}"
    echo ""
    echo -e "${YELLOW}O arquivo ${CYAN}$CREDENTIALS_FILE${YELLOW} não existe.${NC}"
    echo ""
    echo -e "${YELLOW}Você precisa:${NC}"
    echo -e "  1. Executar ${GREEN}setup-plannerate-primary.sh${NC} no servidor primário primeiro"
    echo -e "  2. Copiar o arquivo ${CYAN}.plannerate-credentials.txt${NC} do primário para esta máquina"
    echo -e "  3. Colocar o arquivo na mesma pasta deste script"
    echo ""
    echo -e "${YELLOW}Exemplo de como copiar:${NC}"
    echo -e "  ${GREEN}scp root@192.168.2.106:/caminho/.plannerate-credentials.txt .${NC}"
    echo ""
    exit 1
fi

# ============================================
# CARREGAR CREDENCIAIS
# ============================================
echo -e "${YELLOW}🔐 Carregando credenciais do arquivo...${NC}"
source "$CREDENTIALS_FILE"

# Validar variáveis essenciais
if [ -z "$PRIMARY_IP" ] || [ -z "$REPLICATOR_USER" ] || [ -z "$REPLICATOR_PASSWORD" ]; then
    echo -e "${RED}❌ ERRO: Arquivo de credenciais inválido!${NC}"
    echo -e "   Variáveis obrigatórias: PRIMARY_IP, REPLICATOR_USER, REPLICATOR_PASSWORD"
    exit 1
fi

echo -e "${GREEN}✅ Credenciais carregadas com sucesso!${NC}"

# ============================================
# ESCOLHER NÚMERO DA RÉPLICA
# ============================================
echo ""
echo -e "${YELLOW}📝 Qual o número desta réplica?${NC}"
echo -e "  ${CYAN}1${NC} - Primeira réplica (usa slot: ${REPLICA_SLOT}_1)"
echo -e "  ${CYAN}2${NC} - Segunda réplica (usa slot: ${REPLICA_SLOT}_2)"
echo -e "  ${CYAN}3${NC} - Terceira réplica (usa slot: ${REPLICA_SLOT}_3)"
echo ""
while true; do
    read -p "Digite o número [1-3]: " REPLICA_NUMBER
    if [[ "$REPLICA_NUMBER" =~ ^[1-3]$ ]]; then
        break
    else
        echo -e "${RED}Erro: Digite apenas 1, 2 ou 3${NC}"
    fi
done

# Atualizar nome do slot com o número da réplica
REPLICA_SLOT="${REPLICA_SLOT}_${REPLICA_NUMBER}"

echo -e "${GREEN}✅ Configurado como Réplica $REPLICA_NUMBER (slot: $REPLICA_SLOT)${NC}"

# ============================================
# CONFIGURAÇÕES
# ============================================
PG_VERSION="17"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"

# ============================================
# EXIBIR CONFIGURAÇÃO
# ============================================
echo ""
echo -e "${YELLOW}📋 Configuração da Réplica:${NC}"
echo ""
echo -e "  ${CYAN}Servidor Primário:${NC} $PRIMARY_IP:$PRIMARY_PORT"
echo -e "  ${CYAN}Usuário Replicação:${NC} $REPLICATOR_USER"
echo -e "  ${CYAN}Slot de Replicação:${NC} $REPLICA_SLOT"
echo -e "  ${CYAN}PostgreSQL:${NC} v$PG_VERSION"
echo ""
echo -e "${YELLOW}📝 Este script irá:${NC}"
echo "  1. Atualizar o sistema"
echo "  2. Instalar PostgreSQL $PG_VERSION"
echo "  3. Parar PostgreSQL e limpar dados"
echo "  4. Conectar ao primário ($PRIMARY_IP)"
echo "  5. Sincronizar TODOS os dados (pg_basebackup)"
echo "  6. Configurar como réplica read-only"
echo "  7. Iniciar streaming replication"
echo ""
echo -e "${RED}⚠️  ATENÇÃO:${NC}"
echo -e "  • Este script irá ${RED}APAGAR TODOS OS DADOS${NC} do PostgreSQL local"
echo -e "  • A réplica será ${YELLOW}SOMENTE LEITURA${NC} (read-only)"
echo -e "  • Certifique-se de ter ${YELLOW}backup${NC} antes de continuar"
echo ""
read -p "Deseja continuar? (Digite 'SIM' em maiúsculas): " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    echo ""
    echo -e "${YELLOW}⏸️  Instalação cancelada pelo usuário.${NC}"
    echo ""
    exit 0
fi

# ============================================
# TESTAR CONEXÃO COM O PRIMÁRIO
# ============================================
echo ""
echo -e "${YELLOW}🔍 Testando conexão com o servidor primário...${NC}"

if ! ping -c 1 -W 2 $PRIMARY_IP > /dev/null 2>&1; then
    echo -e "${RED}❌ ERRO: Não foi possível alcançar o servidor primário ($PRIMARY_IP)${NC}"
    echo -e "   Verifique:"
    echo -e "   • O IP está correto?"
    echo -e "   • O servidor primário está ligado?"
    echo -e "   • Há conexão de rede?"
    exit 1
fi

echo -e "${GREEN}✅ Servidor primário alcançável!${NC}"

# ============================================
# INÍCIO DA INSTALAÇÃO
# ============================================
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Iniciando Instalação...${NC}"
echo -e "${CYAN}============================================${NC}"

# Função para exibir progresso
progress() {
    echo ""
    echo -e "${GREEN}[$1/$2] $3${NC}"
}

# ============================================
# 1. ATUALIZAR SISTEMA
# ============================================
progress "1" "9" "Atualizando sistema..."
apt update -qq > /dev/null 2>&1
apt upgrade -y -qq > /dev/null 2>&1
echo -e "${GREEN}   ✓ Sistema atualizado${NC}"

# ============================================
# 2. INSTALAR PACOTES ESSENCIAIS
# ============================================
progress "2" "9" "Instalando pacotes essenciais..."
apt install -y -qq wget curl gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common > /dev/null 2>&1
echo -e "${GREEN}   ✓ Pacotes instalados${NC}"

# ============================================
# 3. ADICIONAR REPOSITÓRIO POSTGRESQL
# ============================================
progress "3" "9" "Adicionando repositório PostgreSQL..."
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - > /dev/null 2>&1
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt update -qq > /dev/null 2>&1
echo -e "${GREEN}   ✓ Repositório adicionado${NC}"

# ============================================
# 4. INSTALAR POSTGRESQL
# ============================================
progress "4" "9" "Instalando PostgreSQL $PG_VERSION..."

# Parar serviço se estiver rodando
systemctl stop postgresql 2>/dev/null || true

apt install -y -qq postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-client-$PG_VERSION > /dev/null 2>&1
echo -e "${GREEN}   ✓ PostgreSQL instalado${NC}"

# Iniciar uma vez para criar estrutura de diretórios
systemctl start postgresql 2>/dev/null || true
sleep 5

# ============================================
# 5. PARAR E LIMPAR POSTGRESQL
# ============================================
progress "5" "9" "Preparando diretório de dados..."

systemctl stop postgresql

PG_DATA="/var/lib/postgresql/$PG_VERSION/main"

# Backup do diretório antigo (se existir)
if [ -d "$PG_DATA" ] && [ "$(ls -A $PG_DATA 2>/dev/null)" ]; then
    BACKUP_DIR="${PG_DATA}.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "   ${YELLOW}⚠️  Fazendo backup do diretório antigo...${NC}"
    mv $PG_DATA $BACKUP_DIR
    echo -e "   ${GREEN}✓ Backup salvo em: $BACKUP_DIR${NC}"
fi

# Recriar diretório vazio
rm -rf $PG_DATA
mkdir -p $PG_DATA
chown -R postgres:postgres $PG_DATA
chmod 700 $PG_DATA

echo -e "${GREEN}   ✓ Diretório preparado${NC}"

# ============================================
# 6. CRIAR ARQUIVO .pgpass
# ============================================
progress "6" "9" "Configurando autenticação..."

PGPASS_FILE="/var/lib/postgresql/.pgpass"

cat > $PGPASS_FILE <<EOF
$PRIMARY_IP:$PRIMARY_PORT:replication:$REPLICATOR_USER:$REPLICATOR_PASSWORD
EOF

chown postgres:postgres $PGPASS_FILE
chmod 600 $PGPASS_FILE

echo -e "${GREEN}   ✓ Arquivo .pgpass criado${NC}"

# ============================================
# 7. SINCRONIZAR DADOS (pg_basebackup)
# ============================================
progress "7" "9" "Sincronizando dados do servidor primário..."
echo -e "   ${YELLOW}⏳ Isso pode levar alguns minutos...${NC}"

# Executar pg_basebackup
sudo -u postgres pg_basebackup \
    -h $PRIMARY_IP \
    -p $PRIMARY_PORT \
    -U $REPLICATOR_USER \
    -D $PG_DATA \
    -P \
    -Xs \
    -c fast \
    -R \
    -S $REPLICA_SLOT \
    2>&1 | while IFS= read -r line; do
        echo -e "   ${CYAN}$line${NC}"
    done

if [ $? -ne 0 ]; then
    echo -e "${RED}   ❌ ERRO ao sincronizar dados!${NC}"
    echo -e "   Verifique:"
    echo -e "   • As credenciais estão corretas?"
    echo -e "   • O servidor primário está acessível?"
    echo -e "   • O slot de replicação existe no primário?"
    echo -e "   • O firewall está configurado corretamente?"
    exit 1
fi

echo -e "${GREEN}   ✓ Dados sincronizados com sucesso!${NC}"

# ============================================
# 8. CONFIGURAR POSTGRESQL.CONF DA RÉPLICA
# ============================================
progress "8" "9" "Configurando PostgreSQL..."

PG_CONF="$PG_DATA/postgresql.conf"

# Adicionar configurações específicas da réplica
cat >> $PG_CONF <<EOF

#==========================================
# PLANNERATE - CONFIGURAÇÕES DA RÉPLICA
#==========================================
# Data: $(date)
# Servidor: RÉPLICA
# Primário: $PRIMARY_IP
#==========================================

# Hot Standby (permitir consultas na réplica)
hot_standby = on
hot_standby_feedback = on

# Performance para réplicas (mesmas configurações do primário)
max_connections = 200
shared_buffers = 512MB
effective_cache_size = 2GB
work_mem = 8MB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'none'
log_line_prefix = '[REPLICA] %t [%p]: user=%u,db=%d '
EOF

echo -e "${GREEN}   ✓ Configuração aplicada${NC}"

# ============================================
# 9. INICIAR POSTGRESQL COMO RÉPLICA
# ============================================
progress "9" "9" "Iniciando PostgreSQL como réplica..."

systemctl start postgresql
systemctl enable postgresql > /dev/null 2>&1

# Aguardar inicialização
sleep 5

# Verificar se está rodando
if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}   ❌ ERRO: PostgreSQL não iniciou${NC}"
    echo -e "${YELLOW}   Verifique os logs: journalctl -u postgresql -n 50${NC}"
    exit 1
fi

echo -e "${GREEN}   ✓ PostgreSQL iniciado${NC}"

# Aguardar conexão com primário
echo -e "   ${YELLOW}⏳ Aguardando conexão com o primário...${NC}"
sleep 3

# ============================================
# VERIFICAÇÕES FINAIS
# ============================================
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Executando verificações finais...${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Verificar se está em recovery mode
IN_RECOVERY=$(sudo -u postgres psql -t -c "SELECT pg_is_in_recovery();" 2>/dev/null | xargs)
if [ "$IN_RECOVERY" = "t" ]; then
    echo -e "  ${GREEN}✅ Modo Recovery:${NC} Ativo (réplica)"
else
    echo -e "  ${RED}❌ Modo Recovery:${NC} Inativo (ERRO!)"
    echo -e "     ${YELLOW}A réplica não está em recovery mode!${NC}"
fi

# Verificar lag de replicação
LAG=$(sudo -u postgres psql -t -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;" 2>/dev/null | xargs)
echo -e "  ${CYAN}Lag de Replicação:${NC} $LAG"

# Verificar conexão com primário
CONNECTED=$(sudo -u postgres psql -t -c "SELECT status FROM pg_stat_wal_receiver;" 2>/dev/null | xargs)
if [ "$CONNECTED" = "streaming" ]; then
    echo -e "  ${GREEN}✅ Status de Conexão:${NC} Streaming"
else
    echo -e "  ${YELLOW}⚠️  Status de Conexão:${NC} $CONNECTED"
fi

# Contar databases
DB_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_database WHERE datname IN ('$DB_DEV', '$DB_STAGING', '$DB_PRODUCTION');" 2>/dev/null | xargs)
echo -e "  ${CYAN}Databases sincronizados:${NC} $DB_COUNT/3"

# ============================================
# EXIBIR RESUMO FINAL
# ============================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   ✅ RÉPLICA CONFIGURADA COM SUCESSO!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}📡 Informações da Réplica:${NC}"
REPLICA_IP=$(hostname -I | awk '{print $1}')
echo -e "  • IP: ${CYAN}$REPLICA_IP${NC}"
echo -e "  • Porta: ${CYAN}5432${NC}"
echo -e "  • PostgreSQL: ${CYAN}v$PG_VERSION${NC}"
echo ""
echo -e "${YELLOW}🔗 Servidor Primário:${NC}"
echo -e "  • IP: ${CYAN}$PRIMARY_IP${NC}"
echo -e "  • Porta: ${CYAN}$PRIMARY_PORT${NC}"
echo -e "  • Slot: ${CYAN}$REPLICA_SLOT${NC}"
echo ""
echo -e "${YELLOW}🗄️  Databases (Read-Only):${NC}"
echo -e "  • ${CYAN}$DB_DEV${NC}"
echo -e "  • ${CYAN}$DB_STAGING${NC}"
echo -e "  • ${CYAN}$DB_PRODUCTION${NC}"
echo ""
echo -e "${YELLOW}📊 Status:${NC}"
echo -e "  • Recovery Mode: ${GREEN}$IN_RECOVERY${NC}"
echo -e "  • Conexão: ${GREEN}$CONNECTED${NC}"
echo -e "  • Lag: ${CYAN}$LAG${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANTE:${NC}"
echo -e "  • Esta réplica é ${RED}SOMENTE LEITURA${NC}"
echo -e "  • Todas as escritas devem ser feitas no ${YELLOW}primário${NC}"
echo -e "  • Os dados são sincronizados ${GREEN}automaticamente${NC}"
echo ""
echo -e "${YELLOW}🔍 Comandos Úteis:${NC}"
echo ""
echo -e "  ${CYAN}Verificar se está em recovery:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'${NC}"
echo ""
echo -e "  ${CYAN}Ver lag de replicação:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -c \"SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;\"${NC}"
echo ""
echo -e "  ${CYAN}Ver status de conexão com primário:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'${NC}"
echo ""
echo -e "  ${CYAN}Testar leitura dos dados:${NC}"
echo -e "     ${GREEN}sudo -u postgres psql -d $DB_DEV -c 'SELECT * FROM healthcheck;'${NC}"
echo ""
echo -e "  ${CYAN}Ver logs em tempo real:${NC}"
echo -e "     ${GREEN}tail -f /var/log/postgresql/postgresql-$PG_VERSION-main.log${NC}"
echo ""
echo -e "${GREEN}🎉 Réplica sincronizada e funcionando!${NC}"
echo ""
echo -e "${YELLOW}💡 Dica:${NC}"
echo -e "   Acesse o primário e insira dados para ver a sincronização em tempo real:"
echo -e "   ${GREEN}sudo -u postgres psql -h $PRIMARY_IP -U $ADMIN_USER -d $DB_DEV${NC}"
echo ""

