#!/bin/bash
# Script para redefinir senhas do PostgreSQL (postgres e replicator)
# Execute no servidor PostgreSQL: 72.62.139.43
# Como: root ou com sudo

set -e

echo "================================================"
echo "  PLANNERATE - Reset de Senhas PostgreSQL"
echo "================================================"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função para gerar senha segura
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-24
}

echo -e "${YELLOW}🔐 Gerando novas senhas seguras...${NC}"

# Gerar senhas
POSTGRES_PASS=$(generate_password)
REPLICATOR_PASS=$(generate_password)

echo ""
echo -e "${YELLOW}🔄 Atualizando senha do usuário 'postgres'...${NC}"
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASS';"

echo -e "${YELLOW}🔄 Atualizando senha do usuário 'replicator'...${NC}"
sudo -u postgres psql -c "ALTER USER replicator PASSWORD '$REPLICATOR_PASS';"

echo ""
echo -e "${GREEN}✅ Senhas atualizadas com sucesso!${NC}"
echo ""

# Salvar credenciais
CRED_FILE="/root/.postgres-credentials"
cat > "$CRED_FILE" << EOF
# ==============================================
# PLANNERATE - Credenciais PostgreSQL
# Gerado em: $(date)
# ==============================================

# Superusuário
POSTGRES_USER=postgres
POSTGRES_PASS=$POSTGRES_PASS

# Replicação
REPLICATOR_USER=replicator
REPLICATOR_PASS=$REPLICATOR_PASS

# Aplicação Production
PROD_USER=plannerate_prod
PROD_PASS=FsXREh0SMiFcMJWoLI7gze5d

# Aplicação Staging
STAGING_USER=plannerate_staging
STAGING_PASS=okLt0cpuIFkDEfvnp2ul1SPQ

# ==============================================
# IMPORTANTE: Guarde estas credenciais em local seguro!
# ==============================================
EOF

chmod 600 "$CRED_FILE"

echo "================================================"
echo -e "${GREEN}✅ Credenciais salvas em: $CRED_FILE${NC}"
echo "================================================"
echo ""
echo -e "${BLUE}📋 CREDENCIAIS:${NC}"
echo ""
cat "$CRED_FILE"
echo ""
echo "================================================"
echo -e "${YELLOW}⚠️  PRÓXIMO PASSO:${NC}"
echo "  Use estas senhas para executar: bash setup-pgbouncer.sh"
echo ""
echo -e "${YELLOW}📝 Dica:${NC}"
echo "  cat $CRED_FILE"
echo ""
