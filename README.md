# Ambiente de Testes - Replicação PostgreSQL (Máquinas Físicas/VMs)

Este guia configura um cluster PostgreSQL com 1 servidor primário e 2 réplicas para testes de replicação streaming em máquinas Linux (Ubuntu/Debian).

## 📋 Requisitos

- 3 máquinas Linux (Ubuntu 20.04+ ou Debian 11+)
- Acesso root ou sudo em todas as máquinas
- Conectividade de rede entre as máquinas
- Mínimo 2GB RAM por máquina (recomendado 4GB+)
- Mínimo 20GB de disco por máquina

## 🚀 Passo a Passo

### 1️⃣ Configurar Servidor Primário

Na **primeira máquina** (que será o primário):

```bash
# Baixar e executar o script
wget https://seu-servidor.com/setup-primary.sh
chmod +x setup-primary.sh
sudo ./setup-primary.sh
```

**IMPORTANTE:** Anote o IP do servidor primário exibido ao final!

### 2️⃣ Configurar Primeira Réplica

Na **segunda máquina** (primeira réplica):

```bash
# Baixar o script
wget https://seu-servidor.com/setup-replica.sh
chmod +x setup-replica.sh

# EDITAR O SCRIPT antes de executar
nano setup-replica.sh
# Configurar:
#   PRIMARY_IP="IP_DO_PRIMARIO"  (IP anotado no passo 1)
#   REPLICA_SLOT="replica1_slot"

# Executar
sudo ./setup-replica.sh
```

### 3️⃣ Configurar Segunda Réplica

Na **terceira máquina** (segunda réplica):

```bash
# Baixar o script
wget https://seu-servidor.com/setup-replica.sh
chmod +x setup-replica.sh

# EDITAR O SCRIPT antes de executar
nano setup-replica.sh
# Configurar:
#   PRIMARY_IP="IP_DO_PRIMARIO"  (mesmo IP do passo 1)
#   REPLICA_SLOT="replica2_slot"  (DIFERENTE da réplica 1!)

# Executar
sudo ./setup-replica.sh
```

## 📊 Informações dos Servidores

| Servidor | Função | Porta | Descrição |
|----------|--------|-------|-----------|
| Máquina 1 | Primário | 5432 | Leitura e Escrita |
| Máquina 2 | Réplica 1 | 5432 | Somente Leitura |
| Máquina 3 | Réplica 2 | 5432 | Somente Leitura |

## 🔑 Credenciais

**PostgreSQL (todas as máquinas):**
- Usuário: `replicator`
- Senha: `replicator_password`
- Database: `testdb`

**Conexão SSH:**
- Use as credenciais de cada máquina

## 🧪 Testando a Replicação

### 1. Conectar ao servidor primário

```bash
# No servidor primário
sudo -u postgres psql -d testdb
```

### 2. Verificar status de replicação

No servidor primário:
```sql
-- Ver réplicas conectadas
SELECT * FROM pg_stat_replication;

-- Ver slots de replicação
SELECT * FROM pg_replication_slots;

-- Ver estatísticas detalhadas
SELECT 
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

### 3. Inserir dados no primário

```sql
INSERT INTO test_replication (data, hostname) 
VALUES ('Novo registro - ' || NOW(), 'primario');

SELECT * FROM test_replication ORDER BY id DESC LIMIT 5;
```

### 4. Verificar dados nas réplicas

**Na Réplica 1:**
```bash
# SSH na máquina réplica 1
sudo -u postgres psql -d testdb -c "SELECT * FROM test_replication ORDER BY id DESC LIMIT 5;"
```

**Na Réplica 2:**
```bash
# SSH na máquina réplica 2
sudo -u postgres psql -d testdb -c "SELECT * FROM test_replication ORDER BY id DESC LIMIT 5;"
```

### 5. Verificar se está em modo recovery (réplicas)

```bash
# Deve retornar 't' (true) nas réplicas
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
```

## 🔍 Monitoramento

### Verificar logs do PostgreSQL

```bash
# Ver últimas 50 linhas
tail -50 /var/log/postgresql/postgresql-15-main.log

# Seguir logs em tempo real
tail -f /var/log/postgresql/postgresql-15-main.log
```

### Verificar status do serviço

```bash
systemctl status postgresql
```

### Verificar lag de replicação (nas réplicas)

```bash
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

### Monitoramento contínuo (primário)

```bash
# Criar script de monitoramento
sudo -u postgres psql -d testdb <<EOF
SELECT 
    application_name,
    client_addr,
    state,
    pg_wal_lsn_diff(sent_lsn, replay_lsn)/1024/1024 AS lag_mb,
    NOW() - pg_last_xact_replay_timestamp() AS time_lag
FROM pg_stat_replication;
EOF
```

## 🧹 Comandos Úteis

### Reiniciar PostgreSQL
```bash
sudo systemctl restart postgresql
```

### Parar PostgreSQL
```bash
sudo systemctl stop postgresql
```

### Iniciar PostgreSQL
```bash
sudo systemctl start postgresql
```

### Verificar conectividade entre máquinas
```bash
# Na réplica, testar conexão com primário
psql -h IP_DO_PRIMARIO -U replicator -d testdb -c "SELECT 1;"
```

### Ver processos PostgreSQL
```bash
ps aux | grep postgres
```

## 📈 Testes de Carga

### Inserir múltiplos registros
```sql
INSERT INTO test_replication (data)
SELECT 'Registro de teste #' || generate_series(1, 1000);
```

### Verificar sincronização
```sql
-- No primário
SELECT COUNT(*) FROM test_replication;

-- Nas réplicas (deve ser igual)
```

## 🚨 Troubleshooting

### Réplica não está sincronizando

1. Verificar se o primário está aceitando conexões:
```bash
# No primário
sudo -u postgres psql -c "SELECT 1;"
```

2. Verificar logs da réplica:
```bash
tail -100 /var/log/postgresql/postgresql-15-main.log
```

3. Verificar conectividade de rede:
```bash
# Na réplica
ping IP_DO_PRIMARIO
telnet IP_DO_PRIMARIO 5432
```

4. Verificar firewall:
```bash
# No primário
sudo ufw status
sudo ufw allow 5432/tcp
```

5. Verificar pg_hba.conf:
```bash
# No primário
cat /etc/postgresql/15/main/pg_hba.conf | grep replication
```

### Recriar uma réplica do zero

```bash
# Na réplica
sudo systemctl stop postgresql
sudo rm -rf /var/lib/postgresql/15/main/*
sudo ./setup-replica.sh
```

### Erro de autenticação

```bash
# Verificar senha no .pgpass
cat /var/lib/postgresql/.pgpass

# Deve estar no formato:
# IP:5432:replication:replicator:senha
```

### Verificar se porta está aberta

```bash
# No primário
sudo netstat -tlnp | grep 5432
# ou
sudo ss -tlnp | grep 5432
```

## 📚 Conceitos Importantes

- **WAL (Write-Ahead Logging)**: Mecanismo de log que garante durabilidade das transações
- **Streaming Replication**: Réplicas recebem alterações em tempo real via streaming
- **Hot Standby**: Réplicas podem aceitar consultas de leitura enquanto replicam
- **Replication Slots**: Garantem que o primário não delete WALs necessários pelas réplicas
- **LSN (Log Sequence Number)**: Posição no log de transações

## 🎯 Cenários de Teste

### 1. Teste de Failover Manual
```bash
# Promover réplica 1 a primário
# Na réplica 1
sudo -u postgres pg_ctl promote -D /var/lib/postgresql/15/main
```

### 2. Teste de Lag
```bash
# No primário - inserir muitos dados
sudo -u postgres psql -d testdb -c "
INSERT INTO test_replication (data, hostname)
SELECT 'Teste de lag #' || generate_series(1, 10000), '$(hostname)';
"

# Na réplica - verificar lag
sudo -u postgres psql -c "
SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;
"
```

### 3. Distribuir Leitura Entre Réplicas
```bash
# Criar script de load balancing de leitura
# Conectar alternadamente entre réplica 1 e 2
```

### 4. Simular Falha e Recuperação
```bash
# Parar réplica
sudo systemctl stop postgresql

# Aguardar e reiniciar
sleep 60
sudo systemctl start postgresql

# Verificar recuperação automática
```

### 5. Verificar Consistência
```bash
# Contar registros no primário
sudo -u postgres psql -d testdb -c "SELECT COUNT(*) FROM test_replication;"

# Contar nas réplicas (deve ser igual)
# Na réplica 1 e 2
sudo -u postgres psql -d testdb -c "SELECT COUNT(*) FROM test_replication;"
```