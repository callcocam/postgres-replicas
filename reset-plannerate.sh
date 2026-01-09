#!/bin/bash
# ============================================
# PLANNERATE - PostgreSQL Reset Script
# ============================================
# Script para RESETAR completamente PostgreSQL
# ATENÇÃO: Este script é DESTRUTIVO!
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
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

clear
echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}   ⚠️  PLANNERATE - PostgreSQL RESET  ⚠️${NC}"
echo -e "${RED}============================================${NC}"
echo ""

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ ERRO: Execute como root ou com sudo${NC}"
    echo -e "   Exemplo: ${YELLOW}sudo bash reset-plannerate.sh${NC}"
    exit 1
fi

# ============================================
# CONFIGURAÇÕES
# ============================================
PG_VERSION="15"
SCRIPT_DIR="$(dirname "$0")"

# ============================================
# FUNÇÕES
# ============================================

show_menu() {
    echo -e "${YELLOW}Selecione o tipo de reset:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Reset PRIMÁRIO - Remove e recria servidor primário"
    echo -e "  ${CYAN}2)${NC} Reset RÉPLICA - Remove e recria servidor réplica"
    echo -e "  ${CYAN}3)${NC} Reset COMPLETO - Remove tudo (primário e réplica)"
    echo -e "  ${CYAN}4)${NC} Backup e Reset - Faz backup antes de resetar"
    echo -e "  ${CYAN}5)${NC} Apenas Backup - Só faz backup sem resetar"
    echo -e "  ${CYAN}0)${NC} Cancelar"
    echo ""
}

backup_postgres() {
    local BACKUP_DIR="$1"
    local PG_DATA="/var/lib/postgresql/$PG_VERSION/main"
    
    if [ ! -d "$PG_DATA" ]; then
        echo -e "${YELLOW}⚠️  Nenhum dado PostgreSQL encontrado para backup${NC}"
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}📦 Fazendo backup do PostgreSQL...${NC}"
    
    # Criar diretório de backup
    mkdir -p "$BACKUP_DIR"
    
    # Parar PostgreSQL
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        echo -e "   ${YELLOW}Parando PostgreSQL...${NC}"
        systemctl stop postgresql
    fi
    
    # Backup do diretório de dados
    echo -e "   ${CYAN}Copiando dados...${NC}"
    tar -czf "$BACKUP_DIR/pg_data_$(hostname)_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$(dirname $PG_DATA)" "$(basename $PG_DATA)" 2>/dev/null || true
    
    # Backup das configurações
    if [ -d "/etc/postgresql/$PG_VERSION" ]; then
        echo -e "   ${CYAN}Copiando configurações...${NC}"
        tar -czf "$BACKUP_DIR/pg_config_$(hostname)_$(date +%Y%m%d_%H%M%S).tar.gz" -C "/etc/postgresql" "$PG_VERSION" 2>/dev/null || true
    fi
    
    # Backup do arquivo de credenciais (se existir)
    if [ -f "$SCRIPT_DIR/.plannerate-credentials.txt" ]; then
        echo -e "   ${CYAN}Copiando credenciais...${NC}"
        cp "$SCRIPT_DIR/.plannerate-credentials.txt" "$BACKUP_DIR/plannerate-credentials_$(date +%Y%m%d_%H%M%S).txt"
    fi
    
    echo -e "${GREEN}✅ Backup concluído em: $BACKUP_DIR${NC}"
    
    # Listar arquivos de backup
    echo -e "${CYAN}Arquivos de backup criados:${NC}"
    ls -lh "$BACKUP_DIR" | tail -n +2 | awk '{print "   " $9 " (" $5 ")"}'
}

remove_postgres() {
    echo ""
    echo -e "${RED}🗑️  Removendo PostgreSQL...${NC}"
    
    # Parar serviço
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        echo -e "   ${YELLOW}Parando serviço...${NC}"
        systemctl stop postgresql 2>/dev/null || true
        systemctl disable postgresql 2>/dev/null || true
    fi
    
    # Remover pacotes
    echo -e "   ${YELLOW}Removendo pacotes...${NC}"
    apt remove --purge -y postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-client-$PG_VERSION 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    
    # Remover diretórios
    echo -e "   ${YELLOW}Removendo diretórios...${NC}"
    rm -rf /var/lib/postgresql/$PG_VERSION
    rm -rf /etc/postgresql/$PG_VERSION
    rm -rf /var/log/postgresql
    
    # Remover usuário postgres (opcional - comentado por segurança)
    # userdel -r postgres 2>/dev/null || true
    
    echo -e "${GREEN}✅ PostgreSQL removido${NC}"
}

reset_primary() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
    echo -e "${MAGENTA}   RESET DO SERVIDOR PRIMÁRIO${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
    
    remove_postgres
    
    echo ""
    echo -e "${CYAN}🔄 Executando setup do primário...${NC}"
    
    if [ -f "$SCRIPT_DIR/setup-plannerate-primary.sh" ]; then
        bash "$SCRIPT_DIR/setup-plannerate-primary.sh"
    else
        echo -e "${RED}❌ ERRO: setup-plannerate-primary.sh não encontrado!${NC}"
        exit 1
    fi
}

reset_replica() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
    echo -e "${MAGENTA}   RESET DA RÉPLICA${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
    
    # Verificar arquivo de credenciais
    if [ ! -f "$SCRIPT_DIR/.plannerate-credentials.txt" ]; then
        echo -e "${RED}❌ ERRO: Arquivo de credenciais não encontrado!${NC}"
        echo -e "   ${YELLOW}Para resetar a réplica, você precisa do arquivo:${NC}"
        echo -e "   ${CYAN}.plannerate-credentials.txt${NC}"
        echo ""
        echo -e "   ${YELLOW}Copie do servidor primário com:${NC}"
        echo -e "   ${GREEN}scp root@192.168.2.106:/caminho/.plannerate-credentials.txt $SCRIPT_DIR/${NC}"
        exit 1
    fi
    
    remove_postgres
    
    echo ""
    echo -e "${CYAN}🔄 Executando setup da réplica...${NC}"
    
    if [ -f "$SCRIPT_DIR/setup-plannerate-replica.sh" ]; then
        bash "$SCRIPT_DIR/setup-plannerate-replica.sh"
    else
        echo -e "${RED}❌ ERRO: setup-plannerate-replica.sh não encontrado!${NC}"
        exit 1
    fi
}

# ============================================
# MENU PRINCIPAL
# ============================================
show_menu

read -p "Escolha uma opção [0-5]: " OPTION

case $OPTION in
    1)
        # Reset Primário
        echo ""
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo -e "${RED}   ⚠️  ATENÇÃO - RESET DO PRIMÁRIO  ⚠️${NC}"
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}Isto irá:${NC}"
        echo -e "  • ${RED}REMOVER completamente${NC} o PostgreSQL"
        echo -e "  • ${RED}APAGAR TODOS OS DADOS${NC}"
        echo -e "  • ${GREEN}RECRIAR${NC} o servidor primário do zero"
        echo -e "  • ${GREEN}GERAR NOVAS CREDENCIAIS${NC}"
        echo ""
        echo -e "${RED}⚠️  TODAS AS RÉPLICAS PRECISARÃO SER RECONFIGURADAS!${NC}"
        echo ""
        read -p "Tem CERTEZA ABSOLUTA? Digite 'RESET PRIMARIO': " CONFIRM
        
        if [ "$CONFIRM" = "RESET PRIMARIO" ]; then
            # Fazer backup automático
            BACKUP_DIR="$SCRIPT_DIR/backups/primary_$(date +%Y%m%d_%H%M%S)"
            backup_postgres "$BACKUP_DIR"
            
            # Resetar
            reset_primary
        else
            echo -e "${YELLOW}❌ Cancelado. Texto não correspondeu.${NC}"
            exit 0
        fi
        ;;
        
    2)
        # Reset Réplica
        echo ""
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo -e "${RED}   ⚠️  ATENÇÃO - RESET DA RÉPLICA  ⚠️${NC}"
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}Isto irá:${NC}"
        echo -e "  • ${RED}REMOVER completamente${NC} o PostgreSQL"
        echo -e "  • ${RED}APAGAR TODOS OS DADOS${NC}"
        echo -e "  • ${GREEN}RECRIAR${NC} a réplica do zero"
        echo -e "  • ${GREEN}SINCRONIZAR${NC} novamente com o primário"
        echo ""
        read -p "Tem CERTEZA? Digite 'RESET REPLICA': " CONFIRM
        
        if [ "$CONFIRM" = "RESET REPLICA" ]; then
            # Fazer backup automático
            BACKUP_DIR="$SCRIPT_DIR/backups/replica_$(date +%Y%m%d_%H%M%S)"
            backup_postgres "$BACKUP_DIR"
            
            # Resetar
            reset_replica
        else
            echo -e "${YELLOW}❌ Cancelado. Texto não correspondeu.${NC}"
            exit 0
        fi
        ;;
        
    3)
        # Reset Completo
        echo ""
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo -e "${RED}   ⚠️⚠️  RESET COMPLETO  ⚠️⚠️${NC}"
        echo -e "${RED}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "${RED}PERIGO: Isto irá DESTRUIR TODO O CLUSTER!${NC}"
        echo ""
        echo -e "${YELLOW}Isto irá:${NC}"
        echo -e "  • ${RED}REMOVER TUDO${NC} (primário e réplica)"
        echo -e "  • ${RED}APAGAR TODOS OS DADOS${NC}"
        echo -e "  • ${RED}PERDER TODAS AS CONFIGURAÇÕES${NC}"
        echo ""
        echo -e "${YELLOW}Você precisará:${NC}"
        echo -e "  • Reconfigurar o primário"
        echo -e "  • Reconfigurar todas as réplicas"
        echo -e "  • Atualizar todos os .env"
        echo ""
        read -p "Digite 'DESTRUIR TUDO' para confirmar: " CONFIRM
        
        if [ "$CONFIRM" = "DESTRUIR TUDO" ]; then
            # Fazer backup
            BACKUP_DIR="$SCRIPT_DIR/backups/full_$(date +%Y%m%d_%H%M%S)"
            backup_postgres "$BACKUP_DIR"
            
            # Remover tudo
            remove_postgres
            
            echo ""
            echo -e "${GREEN}✅ PostgreSQL completamente removido!${NC}"
            echo ""
            echo -e "${YELLOW}Para recriar o cluster:${NC}"
            echo -e "  ${CYAN}1.${NC} Execute no primário: ${GREEN}bash setup-plannerate-primary.sh${NC}"
            echo -e "  ${CYAN}2.${NC} Execute na réplica: ${GREEN}bash setup-plannerate-replica.sh${NC}"
            echo ""
        else
            echo -e "${YELLOW}❌ Cancelado. Texto não correspondeu.${NC}"
            exit 0
        fi
        ;;
        
    4)
        # Backup e Reset
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${CYAN}   BACKUP + RESET${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}Escolha o tipo de servidor:${NC}"
        echo -e "  ${CYAN}1)${NC} Primário"
        echo -e "  ${CYAN}2)${NC} Réplica"
        echo ""
        read -p "Opção [1-2]: " SERVER_TYPE
        
        BACKUP_DIR="$SCRIPT_DIR/backups/manual_$(date +%Y%m%d_%H%M%S)"
        backup_postgres "$BACKUP_DIR"
        
        case $SERVER_TYPE in
            1)
                reset_primary
                ;;
            2)
                reset_replica
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                exit 1
                ;;
        esac
        ;;
        
    5)
        # Apenas Backup
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${CYAN}   BACKUP DO POSTGRESQL${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        
        BACKUP_DIR="$SCRIPT_DIR/backups/backup_$(date +%Y%m%d_%H%M%S)"
        backup_postgres "$BACKUP_DIR"
        
        # Reiniciar PostgreSQL
        if [ -d "/var/lib/postgresql/$PG_VERSION/main" ]; then
            systemctl start postgresql
            echo ""
            echo -e "${GREEN}✅ PostgreSQL reiniciado${NC}"
        fi
        ;;
        
    0)
        # Cancelar
        echo ""
        echo -e "${YELLOW}⏸️  Operação cancelada.${NC}"
        echo ""
        exit 0
        ;;
        
    *)
        echo ""
        echo -e "${RED}❌ Opção inválida!${NC}"
        exit 1
        ;;
esac

# ============================================
# FINALIZAÇÃO
# ============================================
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✅ OPERAÇÃO CONCLUÍDA!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# Mostrar informações de backup se existir
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
    echo -e "${CYAN}📦 Backup disponível:${NC}"
    echo -e "   Local: ${YELLOW}$BACKUP_DIR${NC}"
    echo -e "   Tamanho: ${YELLOW}$BACKUP_SIZE${NC}"
    echo ""
fi

# Verificar status do PostgreSQL
if systemctl is-active --quiet postgresql 2>/dev/null; then
    echo -e "${GREEN}✅ PostgreSQL está rodando${NC}"
    echo ""
    echo -e "${YELLOW}Status do serviço:${NC}"
    systemctl status postgresql --no-pager | head -n 10
else
    echo -e "${YELLOW}⚠️  PostgreSQL não está rodando${NC}"
fi

echo ""

