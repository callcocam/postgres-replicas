#!/bin/bash
# Script auxiliar para obter credenciais PostgreSQL necessárias para PgBouncer
# Execute no servidor PostgreSQL (72.62.139.43)

echo "=========================================="
echo "  CREDENCIAIS PARA PGBOUNCER"
echo "=========================================="
echo ""

echo "Para instalar o PgBouncer, você precisa das senhas de 4 usuários:"
echo ""

echo "1. postgres (superuser)"
echo "   Senha: [procure em /root/.pgpass ou arquivo de credenciais]"
echo ""

echo "2. replicator (usuário de replicação)"
echo "   Senha: [procure em /root/.pgpass ou arquivo de credenciais]"
echo ""

echo "3. plannerate_prod (aplicação production)"
echo "   Senha: FsXREh0SMiFcMJWoLI7gze5d"
echo ""

echo "4. plannerate_staging (aplicação staging)"
echo "   Senha: okLt0cpuIFkDEfvnp2ul1SPQ"
echo ""

echo "=========================================="
echo "  COMO ENCONTRAR AS SENHAS"
echo "=========================================="
echo ""

echo "Opção 1 - Verificar arquivo .pgpass:"
if [ -f ~/.pgpass ]; then
    echo "✅ Arquivo ~/.pgpass encontrado:"
    cat ~/.pgpass
else
    echo "❌ Arquivo ~/.pgpass não encontrado"
fi

echo ""
echo "Opção 2 - Verificar arquivos de credenciais:"
if [ -f /root/.plannerate-credentials ]; then
    echo "✅ Verificando /root/.plannerate-credentials..."
    grep -E "postgres|replicator" /root/.plannerate-credentials 2>/dev/null || echo "Senhas não encontradas neste arquivo"
else
    echo "❌ Arquivo de credenciais não encontrado"
fi

echo ""
echo "Opção 3 - Redefinir senhas (se necessário):"
echo "  sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'nova_senha_segura';\""
echo "  sudo -u postgres psql -c \"ALTER USER replicator PASSWORD 'nova_senha_segura';\""
echo ""
