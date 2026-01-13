#!/bin/bash
# Script para atualizar docker-compose files e corrigir containers unhealthy

set -e

echo "🔧 Atualizando configurações Docker no servidor..."

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SERVER="root@148.230.78.184"

echo -e "${YELLOW}📤 Enviando arquivos docker-compose atualizados...${NC}"

# Fazer backup dos arquivos atuais
ssh $SERVER << 'EOF'
cd /opt/plannerate/production
cp docker-compose.production.yml docker-compose.production.yml.backup-$(date +%Y%m%d_%H%M%S)

cd /opt/plannerate/staging  
cp docker-compose.staging.yml docker-compose.staging.yml.backup-$(date +%Y%m%d_%H%M%S)
EOF

# Copiar novos arquivos
scp docker-compose.production.yml $SERVER:/opt/plannerate/production/
scp docker-compose.staging.new.yml $SERVER:/opt/plannerate/staging/docker-compose.staging.yml

echo -e "${YELLOW}🔄 Recriando containers com novos healthchecks...${NC}"

ssh $SERVER << 'EOF'
# Staging
cd /opt/plannerate/staging
docker compose down reverb queue scheduler
docker compose up -d

# Production
cd /opt/plannerate/production
docker compose down reverb queue scheduler
docker compose up -d

echo ""
echo "⏳ Aguardando 30 segundos para healthchecks..."
sleep 30

echo ""
echo "📊 Status dos containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep plannerate
EOF

echo -e "${GREEN}✅ Atualização concluída!${NC}"
echo ""
echo "Para verificar os logs:"
echo "  ssh $SERVER 'docker logs plannerate-reverb-staging --tail 20'"
echo "  ssh $SERVER 'docker logs plannerate-queue-staging --tail 20'"
echo "  ssh $SERVER 'docker logs plannerate-scheduler-staging --tail 20'"
