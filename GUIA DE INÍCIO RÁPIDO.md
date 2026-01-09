# 🚀 GUIA DE INÍCIO RÁPIDO - Replicação PostgreSQL

Para 3 máquinas Ubuntu NOVAS sem nada instalado.

## 📋 Pré-requisitos

- 3 máquinas com Ubuntu 20.04 ou 22.04 (novas, sem PostgreSQL)
- Acesso SSH com usuário root ou sudo
- Conectividade de rede entre as máquinas
- Mínimo 2GB RAM por máquina

## ⚡ Instalação em 3 Passos

### PASSO 1: Servidor Primário (Máquina 1)

```bash
# 1. Conectar via SSH na primeira máquina
ssh root@IP_MAQUINA_1

# 2. Baixar o script
wget -O setup-primary.sh https://raw.githubusercontent.com/callcocam/postgres-replicas/main/setup-primary.sh
# OU copiar manualmente o conteúdo do script

# 3. Dar permissão
chmod +x setup-primary.sh

# 4. Executar
./setup-primary.sh
```

**✅ IMPORTANTE:** Anote o IP exibido ao final! Exemplo: `192.168.1.100`

---

### PASSO 2: Primeira Réplica (Máquina 2)

```bash
# 1. Conectar via SSH na segunda máquina
ssh root@IP_MAQUINA_2

# 2. Baixar o script
wget -O setup-replica.sh https://raw.githubusercontent.com/callcocam/postgres-replicas/main/setup-replica.sh
# OU copiar manualmente o conteúdo do script

# 3. Dar permissão
chmod +x setup-replica.sh

# 4. EDITAR o script ANTES de executar
nano setup-replica.sh

# 5. Modificar estas linhas:
#    PRIMARY_IP="192.168.1.100"  <<< IP do primário (do passo 1)
#    REPLICA_SLOT="replica1_slot"  <<< manter como está

# 6. Salvar (Ctrl+O) e sair (Ctrl+X)

# 7. Executar
./setup-replica.sh
```

---

### PASSO 3: Segunda Réplica (Máquina 3)

```bash
# 1. Conectar via SSH na terceira máquina
ssh root@IP_MAQUINA_3

# 2. Baixar o script
wget -O setup-replica.sh https://raw.githubusercontent.com/callcocam/postgres-replicas/main/setup-replica.sh
# OU copiar manualmente o conteúdo do script

# 3. Dar permissão
chmod +x setup-replica.sh

# 4. EDITAR o script ANTES de executar
nano setup-replica.sh

# 5. Modificar estas linhas:
#    PRIMARY_IP="192.168.1.100"  <<< IP do primário (mesmo do passo 2)
#    REPLICA_SLOT="replica2_slot"  <<< ATENÇÃO: replica2_slot (diferente!)

# 6. Salvar (Ctrl+O) e sair (Ctrl+X)

# 7. Executar
./setup-replica.sh
```

---

## ✅ Verificação Rápida

### No Servidor Primário:

```bash
# Ver réplicas conectadas
sudo -u postgres psql -d testdb -c "SELECT application_name, client_addr, state FROM pg_stat_replication;"
```

Deve mostrar 2 réplicas conectadas!

### Nas Réplicas:

```bash
# Verificar se está em modo réplica (deve retornar 't')
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Ver dados replicados
sudo -u postgres psql -d testdb -c "SELECT * FROM test_replication;"
```

---

## 🧪 Teste Rápido de Replicação

### 1. No Primário - Inserir dados:

```bash
sudo -u postgres psql -d testdb -c "
INSERT INTO test_replication (data, hostname, ip_address) 
VALUES ('Teste de replicação - $(date)', '$(hostname)', '$(hostname -I | awk "{print \$1}")');"
```

### 2. Nas Réplicas - Verificar dados:

```bash
sudo -u postgres psql -d testdb -c "SELECT * FROM test_replication ORDER BY id DESC LIMIT 3;"
```

Os dados devem aparecer em **tempo real**! 🎉

---

## 🔥 Teste de Carga

### No Primário:

```bash
# Inserir 1000 registros
sudo -u postgres psql -d testdb -c "
INSERT INTO test_replication (data, hostname, ip_address)
SELECT 
    'Teste carga #' || generate_series(1, 1000),
    '$(hostname)',
    '$(hostname -I | awk "{print \$1}")');"

# Contar total
sudo -u postgres psql -d testdb -c "SELECT COUNT(*) FROM test_replication;"
```

### Nas Réplicas:

```bash
# Verificar se sincronizou (deve ter o mesmo total)
sudo -u postgres psql -d testdb -c "SELECT COUNT(*) FROM test_replication;"

# Ver lag de replicação
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"
```

---

## 📊 Informações das Máquinas

Após instalação, você terá:

| Máquina | Função | IP Exemplo | Modo |
|---------|--------|------------|------|
| Máquina 1 | Primário | 192.168.1.100 | Leitura + Escrita |
| Máquina 2 | Réplica 1 | 192.168.1.101 | Somente Leitura |
| Máquina 3 | Réplica 2 | 192.168.1.102 | Somente Leitura |

**Credenciais:**
- Usuário: `replicator`
- Senha: `replicator_password`
- Database: `testdb`

---

## 🆘 Problemas Comuns

### Réplica não conecta ao primário:

```bash
# No primário - verificar se PostgreSQL aceita conexões remotas
sudo -u postgres psql -c "SHOW listen_addresses;"
# Deve mostrar: *

# Verificar firewall
sudo ufw status
sudo ufw allow 5432/tcp
```

### Réplica não está em recovery mode:

```bash
# Verificar arquivo standby.signal
ls -la /var/lib/postgresql/15/main/standby.signal

# Se não existir, criar:
sudo touch /var/lib/postgresql/15/main/standby.signal
sudo chown postgres:postgres /var/lib/postgresql/15/main/standby.signal
sudo systemctl restart postgresql
```

### Ver logs de erro:

```bash
# Logs do PostgreSQL
sudo tail -100 /var/log/postgresql/postgresql-15-main.log

# Logs do sistema
sudo journalctl -u postgresql -n 50
```

---

## 📞 Próximos Passos

Depois de configurado, você pode:

1. **Testar Failover** - Promover uma réplica a primário
2. **Monitorar Performance** - Usar pgAdmin ou scripts de monitoramento
3. **Distribuir Leitura** - Conectar aplicações às réplicas para leitura
4. **Backup Automático** - Configurar backups regulares
5. **Alta Disponibilidade** - Adicionar Pgpool-II ou Patroni

---

## 📚 Comandos Úteis

```bash
# Status do PostgreSQL
systemctl status postgresql

# Reiniciar PostgreSQL
sudo systemctl restart postgresql

# Ver processos
ps aux | grep postgres

# Espaço em disco
df -h /var/lib/postgresql

# Conectar ao database
sudo -u postgres psql -d testdb

# Ver tabelas
sudo -u postgres psql -d testdb -c "\dt"
```

---

## ✨ Pronto!

Seu cluster PostgreSQL com replicação streaming está funcionando!

- ✅ 1 Servidor Primário (leitura/escrita)
- ✅ 2 Réplicas (somente leitura)
- ✅ Sincronização em tempo real
- ✅ Failover pronto

**Dúvidas?** Verifique os logs ou consulte a documentação completa no README.md