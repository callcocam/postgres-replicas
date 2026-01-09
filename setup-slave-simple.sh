#!/bin/bash
# Script SIMPLES e FUNCIONAL para criar réplica PostgreSQL 17

set -e

echo "=========================================="
echo "  SETUP SIMPLES - RÉPLICA POSTGRESQL 17"
echo "=========================================="
echo ""

# Verificar root
if [ "$EUID" -ne 0 ]; then 
    echo "ERRO: Execute com sudo"
    exit 1
fi

# Configurações
PRIMARY_IP="192.168.2.106"
REPLICATOR_PASSWORD="dKcvdhT7OV4FKLBdyCLkTH8f2y8agRXH"
SLOT_NAME="plannerate_replica_slot_1"

echo "Master: $PRIMARY_IP"
echo "Slot: $SLOT_NAME"
echo ""
read -p "Continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    exit 0
fi

# 1. Instalar PostgreSQL 17
echo ""
echo "[1/7] Instalando PostgreSQL 17..."
apt update -qq
apt install -y postgresql-17 postgresql-contrib-17 > /dev/null 2>&1
echo "✓ Instalado"

# 2. Parar PostgreSQL
echo ""
echo "[2/7] Parando PostgreSQL..."
systemctl stop postgresql
echo "✓ Parado"

# 3. Remover cluster existente se houver
echo ""
echo "[3/7] Limpando clusters antigos..."
pg_dropcluster --stop 17 main 2>/dev/null || true
rm -rf /var/lib/postgresql/17/main
rm -rf /etc/postgresql/17
echo "✓ Limpo"

# 4. Criar arquivo .pgpass
echo ""
echo "[4/7] Configurando autenticação..."
cat > /var/lib/postgresql/.pgpass <<EOF
$PRIMARY_IP:5432:replication:plannerate_replicator:$REPLICATOR_PASSWORD
EOF
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 600 /var/lib/postgresql/.pgpass
echo "✓ Configurado"

# 5. Sincronizar dados do master
echo ""
echo "[5/7] Sincronizando dados do master..."
echo "Isso pode demorar alguns minutos..."
sudo -u postgres pg_basebackup -h $PRIMARY_IP -U plannerate_replicator \
    -D /var/lib/postgresql/17/main -P -Xs -c fast -R -S $SLOT_NAME
echo "✓ Sincronizado"

# 6. Criar cluster a partir dos dados sincronizados
echo ""
echo "[6/7] Criando cluster PostgreSQL..."
pg_createcluster 17 main -d /var/lib/postgresql/17/main
echo "✓ Cluster criado"

# 7. Iniciar PostgreSQL
echo ""
echo "[7/7] Iniciando PostgreSQL..."
systemctl start postgresql@17-main
systemctl enable postgresql@17-main > /dev/null 2>&1
sleep 3
echo "✓ Iniciado"

# Verificações
echo ""
echo "=========================================="
echo "  VERIFICANDO..."
echo "=========================================="
echo ""

# Ver cluster
echo "Cluster:"
pg_lsclusters

# Verificar recovery
echo ""
echo "Recovery Mode:"
sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'

# Ver conexão
echo ""
echo "Conexão com Master:"
sudo -u postgres psql -c 'SELECT status FROM pg_stat_wal_receiver;' 2>/dev/null || echo "Aguardando conexão..."

echo ""
echo "=========================================="
echo "  ✅ CONCLUÍDO!"
echo "=========================================="
echo ""
echo "Comandos úteis:"
echo "  sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'"
echo "  sudo -u postgres psql -d laravel -c 'SELECT * FROM healthcheck;'"
echo ""

