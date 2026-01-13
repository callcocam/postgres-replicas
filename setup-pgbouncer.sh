#!/bin/bash
# Script para instalar e configurar PgBouncer no servidor PostgreSQL
# Execute no servidor: 72.62.139.43
# Como: root ou com sudo

set -e

echo "================================================"
echo "  PLANNERATE - Instalação PgBouncer"
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

# Configurações
PGBOUNCER_PORT=6432
POSTGRES_PORT=5432
DOCKER_VM_IP="148.230.78.184"

# Databases
DB_PRODUCTION="plannerate_production"
DB_STAGING="plannerate_staging"

echo -e "${YELLOW}📦 Instalando PgBouncer...${NC}"
apt update
apt install -y pgbouncer

echo ""
echo -e "${YELLOW}🔍 Versão instalada:${NC}"
pgbouncer --version

echo ""
echo -e "${YELLOW}⚙️  Criando arquivo de configuração...${NC}"

# Backup da configuração original
if [ -f /etc/pgbouncer/pgbouncer.ini ]; then
    cp /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini.backup-$(date +%Y%m%d_%H%M%S)
fi

# Criar pgbouncer.ini
cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
;; PgBouncer configuration for Plannerate
;; Database definitions

[databases]
plannerate_production = host=127.0.0.1 port=5432 dbname=plannerate_production
plannerate_staging = host=127.0.0.1 port=5432 dbname=plannerate_staging

;; Alias for pgbouncer admin database
pgbouncer = host=127.0.0.1 port=5432 dbname=pgbouncer

[pgbouncer]

;;;
;;; Administrative settings
;;;

logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid

;;;
;;; Where to wait for clients
;;;

listen_addr = 0.0.0.0
listen_port = 6432

;;;
;;; Authentication settings
;;;

auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

;;;
;;; Users allowed into database 'pgbouncer'
;;;

admin_users = postgres, replicator
stats_users = replicator, plannerate_prod, plannerate_staging

;;;
;;; Pooler personality questions
;;;

# Transaction: conexão liberada após cada transação (recomendado)
# Session: conexão mantida durante sessão (se usar prepared statements)
# Statement: conexão liberada após cada statement
pool_mode = transaction

# Timeouts
server_reset_query = DISCARD ALL
server_reset_query_always = 0

server_check_delay = 30
server_check_query = select 1

# Idle timeout for server connections (seconds)
server_idle_timeout = 600

# Idle timeout for client connections (seconds)
client_idle_timeout = 0

# Query timeout (0 = disabled)
query_timeout = 0

# Quando client perde conexão, quanto tempo esperar antes de fechar server connection
query_wait_timeout = 120

;;;
;;; Connection limits
;;;

# Total de conexões permitidas
max_client_conn = 200

# Conexões default por database
default_pool_size = 20

# Mínimo de conexões no pool (sempre mantidas)
min_pool_size = 5

# Máximo de conexões extras quando pool está cheio
reserve_pool_size = 5

# Timeout para conseguir conexão do pool (segundos)
reserve_pool_timeout = 3

# Máximo total de conexões ao PostgreSQL
max_db_connections = 50

# Máximo de user+database pairs
max_user_connections = 50

;;;
;;; Logging
;;;

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
log_stats = 1

# Stats são logados a cada X segundos
stats_period = 60

# Nível de verbosidade (0 = quiet, 1 = normal, 2 = verbose)
verbose = 0

;;;
;;; Console access control
;;;

unix_socket_dir = /var/run/postgresql
unix_socket_mode = 0777
unix_socket_group =

;;;
;;; Dangerous timeouts
;;;

# Como criar novas conexões server (pode demorar se PostgreSQL ocupado)
server_connect_timeout = 15

# Quanto tempo esperar dados do server
server_login_retry = 15

# Fechar server connections que não respondem por X segundos
# (0 = desabilitado)
server_lifetime = 3600

# Fechar conexões server idle por mais de X segundos
# (0 = desabilitado)
server_idle_timeout = 600

;;;
;;; TLS settings (conexão ao PostgreSQL - local, sem TLS)
;;;

server_tls_sslmode = disable

;;;
;;; TLS settings (conexão dos clientes - sem TLS por enquanto)
;;;

client_tls_sslmode = disable
EOF

echo -e "${GREEN}✅ pgbouncer.ini criado${NC}"

echo ""
echo -e "${YELLOW}🔐 Solicitando senhas dos usuários...${NC}"

# Função para gerar hash MD5
generate_md5() {
    local user=$1
    local pass=$2
    echo -n "md5"
    echo -n "${pass}${user}" | md5sum | cut -d' ' -f1
}

# Solicitar senhas
read -sp "Digite a senha do usuário 'postgres': " POSTGRES_PASS
echo ""
read -sp "Digite a senha do usuário 'replicator': " REPLICATOR_PASS
echo ""
read -sp "Digite a senha do usuário 'plannerate_prod': " PROD_PASS
echo ""
read -sp "Digite a senha do usuário 'plannerate_staging': " STAGING_PASS
echo ""

# Gerar hashes
POSTGRES_HASH=$(generate_md5 "postgres" "$POSTGRES_PASS")
REPLICATOR_HASH=$(generate_md5 "replicator" "$REPLICATOR_PASS")
PROD_HASH=$(generate_md5 "plannerate_prod" "$PROD_PASS")
STAGING_HASH=$(generate_md5 "plannerate_staging" "$STAGING_PASS")

# Criar userlist.txt
cat > /etc/pgbouncer/userlist.txt << EOF
"postgres" "$POSTGRES_HASH"
"replicator" "$REPLICATOR_HASH"
"plannerate_prod" "$PROD_HASH"
"plannerate_staging" "$STAGING_HASH"
EOF

chmod 600 /etc/pgbouncer/userlist.txt
chown postgres:postgres /etc/pgbouncer/userlist.txt

echo -e "${GREEN}✅ userlist.txt criado${NC}"

echo ""
echo -e "${YELLOW}🔥 Configurando Firewall...${NC}"

# Verificar se UFW está instalado
if command -v ufw &> /dev/null; then
    # Liberar porta 6432 apenas para VM Docker
    ufw allow from $DOCKER_VM_IP to any port $PGBOUNCER_PORT comment 'PgBouncer para VM Docker'
    echo -e "${GREEN}✅ Firewall configurado (porta $PGBOUNCER_PORT liberada para $DOCKER_VM_IP)${NC}"
else
    echo -e "${YELLOW}⚠️  UFW não instalado. Configure o firewall manualmente.${NC}"
fi

echo ""
echo -e "${YELLOW}🚀 Iniciando PgBouncer...${NC}"

# Habilitar e iniciar serviço
systemctl enable pgbouncer
systemctl restart pgbouncer

# Aguardar inicialização
sleep 3

# Verificar status
if systemctl is-active --quiet pgbouncer; then
    echo -e "${GREEN}✅ PgBouncer está rodando!${NC}"
else
    echo -e "${RED}❌ Erro ao iniciar PgBouncer${NC}"
    echo "Verifique os logs: journalctl -u pgbouncer -n 50"
    exit 1
fi

echo ""
echo -e "${YELLOW}🧪 Testando conexão ao PgBouncer...${NC}"

# Testar conexão ao console admin
if PGPASSWORD="$REPLICATOR_PASS" psql -h 127.0.0.1 -p $PGBOUNCER_PORT -U replicator pgbouncer -c "SHOW POOLS;" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Conexão ao PgBouncer funcionando!${NC}"
else
    echo -e "${YELLOW}⚠️  Não foi possível conectar ao console admin. Verifique a configuração.${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ PgBouncer instalado e configurado com sucesso!${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}📊 Informações de Conexão:${NC}"
echo "  Porta PgBouncer: $PGBOUNCER_PORT"
echo "  Porta PostgreSQL: $POSTGRES_PORT"
echo ""
echo -e "${BLUE}🔍 Comandos Úteis:${NC}"
echo "  Ver status: systemctl status pgbouncer"
echo "  Ver logs: journalctl -u pgbouncer -f"
echo "  Reiniciar: systemctl restart pgbouncer"
echo ""
echo "  Console admin:"
echo "    psql -h 127.0.0.1 -p $PGBOUNCER_PORT -U replicator pgbouncer"
echo ""
echo "  Comandos no console:"
echo "    SHOW POOLS;    - Ver pools ativos"
echo "    SHOW STATS;    - Ver estatísticas"
echo "    SHOW CLIENTS;  - Ver clientes conectados"
echo "    SHOW SERVERS;  - Ver conexões ao PostgreSQL"
echo "    SHOW CONFIG;   - Ver configuração"
echo ""
echo -e "${YELLOW}⚠️  PRÓXIMO PASSO:${NC}"
echo "  Atualizar .env nos containers Docker para usar porta $PGBOUNCER_PORT"
echo "  Antes: DB_PORT=5432"
echo "  Depois: DB_PORT=6432"
echo ""
echo -e "${YELLOW}📝 Arquivos criados:${NC}"
echo "  - /etc/pgbouncer/pgbouncer.ini"
echo "  - /etc/pgbouncer/userlist.txt"
echo "  - /var/log/postgresql/pgbouncer.log"
echo ""
