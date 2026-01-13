#!/bin/bash

###############################################################################
# PLANNERATE - Instalação de Exporters para Prometheus
# Este script instala os exporters necessários no servidor PostgreSQL
###############################################################################

set -e

echo "======================================================"
echo "PLANNERATE - Instalação de Exporters Prometheus"
echo "======================================================"
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função de log
log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script precisa ser executado como root"
   exit 1
fi

# Variáveis
POSTGRES_PASSWORD=$(grep "^postgres:" /root/.postgres-credentials | cut -d: -f2 | xargs)
if [ -z "$POSTGRES_PASSWORD" ]; then
    log_error "Senha do PostgreSQL não encontrada em /root/.postgres-credentials"
    exit 1
fi

echo "======================================================"
echo "1. Instalando Node Exporter (Métricas do Sistema)"
echo "======================================================"
echo ""

# Criar usuário para os exporters
if ! id "prometheus" &>/dev/null; then
    useradd --no-create-home --shell /bin/false prometheus
    log_info "Usuário 'prometheus' criado"
else
    log_info "Usuário 'prometheus' já existe"
fi

# Download e instalação do Node Exporter
NODE_EXPORTER_VERSION="1.8.2"
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/node_exporter
rm -rf node_exporter-${NODE_EXPORTER_VERSION}*

log_info "Node Exporter instalado: $(/usr/local/bin/node_exporter --version | head -1)"

# Criar serviço systemd para Node Exporter
cat > /etc/systemd/system/node-exporter.service <<'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes \
    --collector.interrupts \
    --web.listen-address=:9100

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node-exporter
systemctl restart node-exporter

log_info "Node Exporter service criado e iniciado"

echo ""
echo "======================================================"
echo "2. Instalando PostgreSQL Exporter"
echo "======================================================"
echo ""

# Download e instalação do PostgreSQL Exporter
POSTGRES_EXPORTER_VERSION="0.15.0"
cd /tmp
wget -q https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz
cp postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64/postgres_exporter /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/postgres_exporter
rm -rf postgres_exporter-${POSTGRES_EXPORTER_VERSION}*

log_info "PostgreSQL Exporter instalado: $(/usr/local/bin/postgres_exporter --version 2>&1 | head -1)"

# Criar arquivo de credenciais PostgreSQL para o exporter
cat > /etc/postgres_exporter.env <<EOF
DATA_SOURCE_NAME=postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/postgres?sslmode=disable
EOF

chmod 600 /etc/postgres_exporter.env
chown prometheus:prometheus /etc/postgres_exporter.env

log_info "Credenciais PostgreSQL configuradas"

# Criar serviço systemd para PostgreSQL Exporter
cat > /etc/systemd/system/postgres-exporter.service <<'EOF'
[Unit]
Description=PostgreSQL Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
EnvironmentFile=/etc/postgres_exporter.env
ExecStart=/usr/local/bin/postgres_exporter \
    --web.listen-address=:9187 \
    --log.level=info

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable postgres-exporter
systemctl restart postgres-exporter

log_info "PostgreSQL Exporter service criado e iniciado"

echo ""
echo "======================================================"
echo "3. Instalando PgBouncer Exporter"
echo "======================================================"
echo ""

# Download e instalação do PgBouncer Exporter
PGBOUNCER_EXPORTER_VERSION="0.9.0"
cd /tmp
wget -q https://github.com/prometheus-community/pgbouncer_exporter/releases/download/v${PGBOUNCER_EXPORTER_VERSION}/pgbouncer_exporter-${PGBOUNCER_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf pgbouncer_exporter-${PGBOUNCER_EXPORTER_VERSION}.linux-amd64.tar.gz
cp pgbouncer_exporter-${PGBOUNCER_EXPORTER_VERSION}.linux-amd64/pgbouncer_exporter /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/pgbouncer_exporter
rm -rf pgbouncer_exporter-${PGBOUNCER_EXPORTER_VERSION}*

log_info "PgBouncer Exporter instalado: $(/usr/local/bin/pgbouncer_exporter --version 2>&1 | head -1)"

# Criar arquivo de credenciais PgBouncer para o exporter
cat > /etc/pgbouncer_exporter.env <<EOF
PGBOUNCER_EXPORTER_CONNECTION_STRING=postgresql://postgres:${POSTGRES_PASSWORD}@localhost:6432/pgbouncer?sslmode=disable
EOF

chmod 600 /etc/pgbouncer_exporter.env
chown prometheus:prometheus /etc/pgbouncer_exporter.env

log_info "Credenciais PgBouncer configuradas"

# Criar serviço systemd para PgBouncer Exporter
cat > /etc/systemd/system/pgbouncer-exporter.service <<'EOF'
[Unit]
Description=PgBouncer Exporter
Wants=network-online.target
After=network-online.target pgbouncer.service

[Service]
User=prometheus
Group=prometheus
Type=simple
EnvironmentFile=/etc/pgbouncer_exporter.env
ExecStart=/usr/local/bin/pgbouncer_exporter \
    --web.listen-address=:9127 \
    --log.level=info

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pgbouncer-exporter
systemctl restart pgbouncer-exporter

log_info "PgBouncer Exporter service criado e iniciado"

echo ""
echo "======================================================"
echo "4. Configurando Firewall"
echo "======================================================"
echo ""

# Abrir portas apenas para o servidor Docker
DOCKER_SERVER="148.230.78.184"

ufw allow from $DOCKER_SERVER to any port 9100 comment "Prometheus Node Exporter"
ufw allow from $DOCKER_SERVER to any port 9187 comment "Prometheus PostgreSQL Exporter"
ufw allow from $DOCKER_SERVER to any port 9127 comment "Prometheus PgBouncer Exporter"

log_info "Firewall configurado - portas abertas apenas para $DOCKER_SERVER"

echo ""
echo "======================================================"
echo "5. Verificando Status dos Services"
echo "======================================================"
echo ""

sleep 3

services=("node-exporter" "postgres-exporter" "pgbouncer-exporter")

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        log_info "$service: ATIVO"
    else
        log_error "$service: INATIVO ou COM ERRO"
        systemctl status $service --no-pager -l
    fi
done

echo ""
echo "======================================================"
echo "6. Testando Endpoints"
echo "======================================================"
echo ""

# Testar cada endpoint
endpoints=(
    "9100"
    "9187"
    "9127"
)

names=(
    "Node Exporter"
    "PostgreSQL Exporter"
    "PgBouncer Exporter"
)

for i in "${!endpoints[@]}"; do
    port="${endpoints[$i]}"
    name="${names[$i]}"
    
    if curl -s http://localhost:$port/metrics > /dev/null; then
        log_info "$name (port $port): OK"
    else
        log_error "$name (port $port): FALHOU"
    fi
done

echo ""
echo "======================================================"
echo "✅ INSTALAÇÃO COMPLETA!"
echo "======================================================"
echo ""
echo "Exporters instalados e rodando:"
echo "  • Node Exporter:       http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo "  • PostgreSQL Exporter: http://$(hostname -I | awk '{print $1}'):9187/metrics"
echo "  • PgBouncer Exporter:  http://$(hostname -I | awk '{print $1}'):9127/metrics"
echo ""
echo "Próximos passos:"
echo "  1. No servidor Docker (148.230.78.184), subir o stack de monitoramento"
echo "  2. Acessar Grafana: https://grafana.plannerate.com.br"
echo "  3. Adicionar dashboards (IDs recomendados: 1860, 9628, 455)"
echo ""
echo "======================================================"
