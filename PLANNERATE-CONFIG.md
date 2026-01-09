# 🗄️ PLANNERATE - Configuração PostgreSQL

## 📋 Visão Geral

Este documento contém todas as configurações específicas do PostgreSQL para o projeto **Plannerate**, incluindo credenciais, estrutura de databases, comandos úteis e guia de troubleshooting.

---

## 🏗️ Arquitetura do Cluster

```
┌─────────────────────────────────────────────────┐
│                                                 │
│          PLANNERATE PostgreSQL Cluster          │
│                                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────┐      ┌────────────────┐  │
│  │   PRIMÁRIO       │      │    RÉPLICA     │  │
│  │  192.168.2.106   │─────▶│   (IP dinâmico)│  │
│  │   Porta: 5432    │      │   Porta: 5432  │  │
│  │                  │      │                │  │
│  │  Read + Write    │      │   Read-Only    │  │
│  │                  │      │                │  │
│  │  • laravel       │      │  • laravel     │  │
│  │  • staging       │      │  • staging     │  │
│  │  • production    │      │  • production  │  │
│  └──────────────────┘      └────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 🖥️ Servidores

### Servidor Primário (Master)

| Propriedade | Valor |
|-------------|-------|
| **IP** | `192.168.2.106` |
| **Porta** | `5432` |
| **Função** | Leitura + Escrita |
| **PostgreSQL** | v15 |
| **SO** | Ubuntu 20.04+ |

### Servidor Réplica

| Propriedade | Valor |
|-------------|-------|
| **IP** | A definir (VM local) |
| **Porta** | `5432` |
| **Função** | Somente Leitura |
| **PostgreSQL** | v15 |
| **SO** | Ubuntu 20.04+ |

---

## 👥 Usuários e Permissões

### Usuário: postgres

```bash
Usuário: postgres
Senha: (gerada automaticamente)
Tipo: Superuser padrão
Uso: Administração do sistema
```

### Usuário: plannerate_admin

```bash
Usuário: plannerate_admin
Senha: (gerada automaticamente)
Tipo: Superuser
Uso: Aplicação Plannerate (desenvolvimento, staging, production)
Permissões: ALL PRIVILEGES em todos os databases
```

### Usuário: plannerate_replicator

```bash
Usuário: plannerate_replicator
Senha: (gerada automaticamente)
Tipo: Replication
Uso: Sincronização entre primário e réplicas
Permissões: REPLICATION, SELECT (read-only)
```

> **⚠️ IMPORTANTE**: Todas as senhas são geradas automaticamente com 32 caracteres alfanuméricos e salvas em `.plannerate-credentials.txt`

---

## 🗄️ Databases

### Development (laravel)

```bash
Database: laravel
Owner: plannerate_admin
Encoding: UTF8
Uso: Ambiente de desenvolvimento local
```

**Estrutura Padrão:**
- Extensões: `uuid-ossp`, `pg_trgm`
- Tabela: `healthcheck` (monitoramento)
- Índices automáticos para performance

### Staging (plannerate_staging)

```bash
Database: plannerate_staging
Owner: plannerate_admin
Encoding: UTF8
Uso: Ambiente de homologação/testes
```

**Estrutura Padrão:**
- Extensões: `uuid-ossp`, `pg_trgm`
- Tabela: `healthcheck` (monitoramento)
- Índices automáticos para performance

### Production (plannerate_production)

```bash
Database: plannerate_production
Owner: plannerate_admin
Encoding: UTF8
Uso: Ambiente de produção
```

**Estrutura Padrão:**
- Extensões: `uuid-ossp`, `pg_trgm`
- Tabela: `healthcheck` (monitoramento)
- Índices automáticos para performance

---

## ⚙️ Configuração de Replicação

### Tipo de Replicação

- **Método**: Streaming Replication
- **Modo**: Assíncrono
- **Hot Standby**: Habilitado (réplicas aceitam consultas SELECT)

### Slot de Replicação

```bash
Nome: plannerate_replica_slot
Tipo: Physical
Status: Ativo
```

### Configurações WAL

```ini
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 2GB
hot_standby = on
```

---

## 📁 Arquivos de Configuração

### Localização dos Arquivos

```bash
# Dados
/var/lib/postgresql/15/main/

# Configurações
/etc/postgresql/15/main/postgresql.conf
/etc/postgresql/15/main/pg_hba.conf

# Logs
/var/log/postgresql/postgresql-15-main.log

# Credenciais (projeto)
/caminho/postgres-replicas/.plannerate-credentials.txt
```

### Arquivo de Credenciais

O arquivo `.plannerate-credentials.txt` contém:
- IPs e portas
- Senhas de todos os usuários
- Nomes dos databases
- Nome do slot de replicação

**⚠️ Mantenha este arquivo SEGURO e NÃO commite no Git!**

---

## 🔧 Configuração dos Ambientes

### Development (.env)

```bash
DB_CONNECTION=pgsql
DB_HOST=192.168.2.106
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=plannerate_admin
DB_PASSWORD=[senha do arquivo .plannerate-credentials.txt]
```

### Staging (.env.staging)

```bash
DB_CONNECTION=pgsql
DB_HOST=192.168.2.106
DB_PORT=5432
DB_DATABASE=plannerate_staging
DB_USERNAME=plannerate_admin
DB_PASSWORD=[senha do arquivo .plannerate-credentials.txt]
```

### Production (.env.production)

```bash
DB_CONNECTION=pgsql
DB_HOST=192.168.2.106
DB_PORT=5432
DB_DATABASE=plannerate_production
DB_USERNAME=plannerate_admin
DB_PASSWORD=[senha do arquivo .plannerate-credentials.txt]
```

---

## 🚀 Scripts de Instalação

### 1. Setup do Primário

```bash
# No servidor primário (192.168.2.106)
cd /caminho/postgres-replicas
sudo bash setup-plannerate-primary.sh
```

**O que faz:**
- Instala PostgreSQL 15
- Cria 3 databases (laravel, plannerate_staging, plannerate_production)
- Cria usuários com senhas seguras
- Configura replicação
- Gera arquivo `.plannerate-credentials.txt`
- Configura firewall

### 2. Setup da Réplica

```bash
# Copiar arquivo de credenciais do primário
scp root@192.168.2.106:/caminho/.plannerate-credentials.txt .

# No servidor réplica
cd /caminho/postgres-replicas
sudo bash setup-plannerate-replica.sh
```

**O que faz:**
- Instala PostgreSQL 15
- Lê credenciais do arquivo `.plannerate-credentials.txt`
- Conecta ao primário (192.168.2.106)
- Sincroniza TODOS os dados (pg_basebackup)
- Configura como réplica read-only
- Inicia streaming replication

### 3. Reset/Recriação

```bash
# Menu interativo para resetar o cluster
sudo bash reset-plannerate.sh
```

**Opções disponíveis:**
1. Reset PRIMÁRIO - Recria servidor primário do zero
2. Reset RÉPLICA - Recria réplica do zero
3. Reset COMPLETO - Remove tudo (primário e réplica)
4. Backup + Reset - Faz backup antes de resetar
5. Apenas Backup - Só faz backup sem resetar

---

## 📊 Comandos Úteis

### Monitoramento de Replicação

#### No Servidor Primário

```bash
# Ver réplicas conectadas
sudo -u postgres psql -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;"

# Ver slots de replicação
sudo -u postgres psql -c "SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;"

# Ver lag de replicação (em bytes)
sudo -u postgres psql -c "
SELECT 
    application_name,
    client_addr,
    pg_wal_lsn_diff(sent_lsn, replay_lsn)/1024/1024 AS lag_mb
FROM pg_stat_replication;
"
```

#### Na Réplica

```bash
# Verificar se está em recovery mode (deve retornar 't')
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Ver lag de replicação (em tempo)
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"

# Ver status de conexão com primário
sudo -u postgres psql -c "SELECT status, sender_host, sender_port FROM pg_stat_wal_receiver;"
```

### Gestão de Databases

```bash
# Listar todos os databases
sudo -u postgres psql -l

# Conectar a um database específico
sudo -u postgres psql -d laravel

# Conectar remotamente
psql -h 192.168.2.106 -U plannerate_admin -d laravel

# Ver tamanho dos databases
sudo -u postgres psql -c "
SELECT 
    datname AS database,
    pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datname IN ('laravel', 'plannerate_staging', 'plannerate_production')
ORDER BY pg_database_size(datname) DESC;
"
```

### Healthcheck

```bash
# Verificar healthcheck em cada database
sudo -u postgres psql -d laravel -c "SELECT * FROM healthcheck ORDER BY last_check DESC LIMIT 5;"
sudo -u postgres psql -d plannerate_staging -c "SELECT * FROM healthcheck ORDER BY last_check DESC LIMIT 5;"
sudo -u postgres psql -d plannerate_production -c "SELECT * FROM healthcheck ORDER BY last_check DESC LIMIT 5;"

# Inserir novo registro de healthcheck
sudo -u postgres psql -d laravel -c "INSERT INTO healthcheck (service, status, message) VALUES ('plannerate', 'healthy', 'Manual check at $(date)');"
```

### Performance e Estatísticas

```bash
# Ver conexões ativas
sudo -u postgres psql -c "
SELECT 
    datname,
    usename,
    application_name,
    client_addr,
    state,
    query
FROM pg_stat_activity
WHERE datname IN ('laravel', 'plannerate_staging', 'plannerate_production');
"

# Ver queries lentas
sudo -u postgres psql -c "
SELECT 
    pid,
    now() - query_start AS duration,
    query,
    state
FROM pg_stat_activity
WHERE state != 'idle' 
  AND now() - query_start > interval '1 second'
ORDER BY duration DESC;
"

# Ver índices não utilizados
sudo -u postgres psql -d laravel -c "
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0 
  AND indexrelname NOT LIKE '%_pkey'
ORDER BY pg_relation_size(indexrelid) DESC;
"
```

### Backup e Restore

```bash
# Backup de um database específico
pg_dump -h 192.168.2.106 -U plannerate_admin -d laravel -F c -f /backup/laravel_$(date +%Y%m%d).dump

# Backup de todos os databases
pg_dumpall -h 192.168.2.106 -U plannerate_admin -f /backup/all_databases_$(date +%Y%m%d).sql

# Restore de um database
pg_restore -h 192.168.2.106 -U plannerate_admin -d laravel -c /backup/laravel_20250109.dump

# Backup usando script interno
sudo bash reset-plannerate.sh
# Escolha opção 5: Apenas Backup
```

### Gestão de Serviço

```bash
# Status do serviço
systemctl status postgresql

# Iniciar/Parar/Reiniciar
systemctl start postgresql
systemctl stop postgresql
systemctl restart postgresql

# Ver logs em tempo real
tail -f /var/log/postgresql/postgresql-15-main.log

# Ver últimas linhas do log
journalctl -u postgresql -n 50

# Ver logs com filtro
journalctl -u postgresql --since "1 hour ago"
```

---

## 🔒 Segurança

### Firewall (UFW)

```bash
# Ver status
sudo ufw status

# Regras configuradas automaticamente
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 5432/tcp  # PostgreSQL
```

### Autenticação

- **Método**: `scram-sha-256` (mais seguro que MD5)
- **Conexões Locais**: Trust para usuário postgres
- **Conexões Remotas**: Senha obrigatória

### Arquivo pg_hba.conf

```bash
# Replicação
host    replication     plannerate_replicator      0.0.0.0/0               scram-sha-256

# Databases
host    all             all                        0.0.0.0/0               scram-sha-256

# Local
local   all             all                                                 peer
```

---

## 🐛 Troubleshooting

### Réplica não conecta ao primário

**Sintomas:**
- Réplica não aparece em `pg_stat_replication`
- Erro de conexão nos logs

**Soluções:**

```bash
# 1. Verificar se primário está acessível
ping 192.168.2.106

# 2. Testar conexão PostgreSQL
psql -h 192.168.2.106 -U plannerate_replicator -d postgres

# 3. Verificar firewall no primário
sudo ufw status

# 4. Verificar logs da réplica
tail -100 /var/log/postgresql/postgresql-15-main.log

# 5. Verificar arquivo .pgpass na réplica
cat /var/lib/postgresql/.pgpass
# Deve conter: 192.168.2.106:5432:replication:plannerate_replicator:senha

# 6. Recriar réplica
sudo bash reset-plannerate.sh
# Escolha opção 2: Reset RÉPLICA
```

### Lag de replicação alto

**Sintomas:**
- Dados demoram para aparecer na réplica
- Lag > 10 segundos

**Soluções:**

```bash
# 1. Verificar lag
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"

# 2. Verificar network entre primário e réplica
ping 192.168.2.106

# 3. Verificar se há queries lentas no primário
sudo -u postgres psql -c "SELECT pid, now() - query_start AS duration, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;"

# 4. Aumentar WAL keep size (no primário)
# Editar /etc/postgresql/15/main/postgresql.conf
# wal_keep_size = 4GB  # aumentar de 2GB
sudo systemctl restart postgresql
```

### Erro "too many connections"

**Sintomas:**
- Aplicação não consegue conectar
- Erro: "FATAL: remaining connection slots are reserved"

**Soluções:**

```bash
# 1. Ver conexões atuais
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"

# 2. Ver max_connections
sudo -u postgres psql -c "SHOW max_connections;"

# 3. Matar conexões idle
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND query_start < NOW() - INTERVAL '10 minutes';"

# 4. Aumentar max_connections (se necessário)
# Editar /etc/postgresql/15/main/postgresql.conf
# max_connections = 300  # aumentar de 200
sudo systemctl restart postgresql
```

### Database corrompido

**Sintomas:**
- Erros ao ler dados
- PostgreSQL não inicia

**Soluções:**

```bash
# 1. Verificar integridade
sudo -u postgres pg_controldata /var/lib/postgresql/15/main

# 2. Tentar recovery
sudo -u postgres pg_resetwal -f /var/lib/postgresql/15/main

# 3. Restore do backup
sudo bash reset-plannerate.sh
# Opção 1 ou 2 dependendo do servidor

# 4. Ou restaurar backup manual
pg_restore -h 192.168.2.106 -U plannerate_admin -d laravel -c /backup/laravel_backup.dump
```

### Credenciais perdidas

**Problema:**
- Arquivo `.plannerate-credentials.txt` foi perdido
- Esqueceu as senhas

**Solução:**

```bash
# Opção 1: Recuperar do backup
ls -la backups/

# Opção 2: Resetar tudo e gerar novas credenciais
sudo bash reset-plannerate.sh
# Opção 3: Reset COMPLETO

# IMPORTANTE: Atualizar todos os arquivos .env após reset!
```

---

## 📞 Suporte

### Logs Importantes

```bash
# PostgreSQL
/var/log/postgresql/postgresql-15-main.log

# Sistema
journalctl -u postgresql

# Configurações
/etc/postgresql/15/main/postgresql.conf
/etc/postgresql/15/main/pg_hba.conf
```

### Informações para Debug

Ao reportar problemas, forneça:

```bash
# 1. Versão do PostgreSQL
psql --version

# 2. Status do serviço
systemctl status postgresql

# 3. Últimas 50 linhas do log
tail -50 /var/log/postgresql/postgresql-15-main.log

# 4. Configuração de replicação (se aplicável)
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"

# 5. Sistema operacional
lsb_release -a

# 6. Recursos disponíveis
free -h
df -h
```

---

## 📚 Recursos Adicionais

### Documentação

- [PostgreSQL 15 Official Docs](https://www.postgresql.org/docs/15/)
- [Streaming Replication](https://www.postgresql.org/docs/15/warm-standby.html)
- [High Availability](https://www.postgresql.org/docs/15/high-availability.html)

### Scripts do Projeto

- `setup-plannerate-primary.sh` - Setup do servidor primário
- `setup-plannerate-replica.sh` - Setup da réplica
- `reset-plannerate.sh` - Reset/recriação do cluster
- `.plannerate-credentials.txt` - Credenciais (gerado automaticamente)
- `.plannerate-env-example` - Exemplo de configuração .env

---

## 🎯 Checklist de Instalação

### Servidor Primário

- [ ] Executar `setup-plannerate-primary.sh`
- [ ] Verificar criação dos 3 databases
- [ ] Salvar arquivo `.plannerate-credentials.txt`
- [ ] Testar conexão: `psql -h 192.168.2.106 -U plannerate_admin -d laravel`
- [ ] Verificar firewall: `sudo ufw status`
- [ ] Verificar slot de replicação: `sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"`

### Réplica

- [ ] Copiar `.plannerate-credentials.txt` do primário
- [ ] Executar `setup-plannerate-replica.sh`
- [ ] Verificar recovery mode: `sudo -u postgres psql -c "SELECT pg_is_in_recovery();"`
- [ ] Verificar conexão com primário: `sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"`
- [ ] Testar sincronização: Inserir dados no primário e verificar na réplica

### Aplicação

- [ ] Copiar configurações do `.plannerate-env-example`
- [ ] Atualizar `.env` (development)
- [ ] Atualizar `.env.staging` (staging)
- [ ] Atualizar `.env.production` (production)
- [ ] Rodar migrations: `php artisan migrate`
- [ ] Testar conexão da aplicação
- [ ] Configurar pgAdmin (se necessário)

---

## 📝 Notas Finais

- **Backups**: O script de reset faz backups automaticamente, mas considere ter uma estratégia de backup regular
- **Senhas**: Geradas automaticamente com 32 caracteres alfanuméricos
- **Segurança**: Nunca commite o arquivo `.plannerate-credentials.txt` no Git
- **Monitoramento**: Configure alertas para lag de replicação > 30 segundos
- **Performance**: As configurações estão otimizadas para servidores com 4GB+ RAM

---

**Última atualização**: 2025-01-09  
**Versão**: 1.0  
**Projeto**: Plannerate

