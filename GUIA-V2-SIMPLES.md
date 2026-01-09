# Guia de Setup PostgreSQL 17 - PLANNERATE (V2 Simplificado)

**Scripts baseados nos que FUNCIONARAM, adaptados para o Plannerate.**

## 📋 O que esses scripts fazem

### Primary (Master)
- ✅ Instala PostgreSQL 17
- ✅ Cria 3 bancos: `laravel`, `plannerate_staging`, `plannerate_production`
- ✅ Cria 3 slots de replicação
- ✅ Gera senhas seguras automaticamente
- ✅ Salva credenciais em arquivo
- ✅ Configura firewall
- ✅ Pronto para receber réplicas

### Replica (Slave)
- ✅ Instala PostgreSQL 17
- ✅ Lê credenciais do arquivo
- ✅ Sincroniza dados com pg_basebackup
- ✅ Configura replicação streaming
- ✅ Inicia como read-only
- ✅ Conecta no slot escolhido (1, 2 ou 3)

---

## 🚀 PASSO A PASSO

### 1️⃣ Configurar o MASTER (192.168.2.106)

Na VM Master:

```bash
cd ~/postgres-replicas

# Executar script
sudo bash setup-plannerate-primary-v2.sh
```

**O que acontece:**
- Instala tudo
- Cria os 3 bancos
- Gera senhas seguras
- Salva credenciais em: `~/.plannerate-credentials.txt`

**⚠️ IMPORTANTE:** Anote o IP que aparece no final!

---

### 2️⃣ Copiar Credenciais para as Réplicas

**No MASTER**, copie o arquivo de credenciais para cada réplica:

```bash
# Para a primeira réplica (192.168.2.107)
scp ~/.plannerate-credentials.txt root@192.168.2.107:~/

# Para a segunda réplica (se tiver)
scp ~/.plannerate-credentials.txt root@192.168.2.108:~/

# Para a terceira réplica (se tiver)
scp ~/.plannerate-credentials.txt root@192.168.2.109:~/
```

---

### 3️⃣ Configurar cada RÉPLICA

**Em CADA VM Réplica:**

```bash
cd ~/postgres-replicas

# Verificar se o arquivo de credenciais está lá
ls -la ~/.plannerate-credentials.txt

# Executar script
sudo bash setup-plannerate-replica-v2.sh
```

**Durante a execução:**
- Vai pedir para escolher o número da réplica (1, 2 ou 3)
- Cada réplica deve usar um número diferente!

**Exemplo:**
- Réplica 1 (192.168.2.107) → Digite `1`
- Réplica 2 (192.168.2.108) → Digite `2`
- Réplica 3 (192.168.2.109) → Digite `3`

---

## ✅ Verificar se está funcionando

### No MASTER

```bash
# Ver réplicas conectadas
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Ver slots ativos
sudo -u postgres psql -c "SELECT slot_name, active FROM pg_replication_slots;"

# Ver bancos
sudo -u postgres psql -c "\l"
```

### Na RÉPLICA

```bash
# Verificar se está em modo recovery (deve retornar 't')
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Verificar lag
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"

# Ver bancos replicados
sudo -u postgres psql -c "\l"
```

---

## 🔑 Credenciais

Todas as credenciais estão em: `~/.plannerate-credentials.txt`

**Conteúdo:**
```
PRIMARY_IP=192.168.2.106
REPLICATOR_USER=replicator
REPLICATOR_PASSWORD=<gerada automaticamente>
POSTGRES_USER=postgres
POSTGRES_ADMIN_PASSWORD=<gerada automaticamente>
DB_DEV=laravel
DB_STAGING=plannerate_staging
DB_PRODUCTION=plannerate_production
SLOT_1=plannerate_replica_slot_1
SLOT_2=plannerate_replica_slot_2
SLOT_3=plannerate_replica_slot_3
```

---

## 🔧 Arquitetura

```
MASTER (192.168.2.106)
├── laravel
├── plannerate_staging
└── plannerate_production
    ↓ replicação streaming
    ├── SLAVE 1 (192.168.2.107) - slot_1
    ├── SLAVE 2 (192.168.2.108) - slot_2 [opcional]
    └── SLAVE 3 (192.168.2.109) - slot_3 [opcional]
```

---

## 🆘 Troubleshooting

### "Erro: Arquivo de credenciais não encontrado"
```bash
# Verificar se existe
ls -la ~/.plannerate-credentials.txt

# Se não existir, copiar do master novamente
```

### "Erro: Não foi possível conectar ao servidor primário"
```bash
# 1. Verificar se master está rodando
ssh root@192.168.2.106 "systemctl status postgresql"

# 2. Testar ping
ping -c 3 192.168.2.106

# 3. Testar porta
telnet 192.168.2.106 5432
```

### Ver logs
```bash
# Logs do PostgreSQL
tail -f /var/log/postgresql/postgresql-17-main.log

# Logs do sistema
journalctl -u postgresql@17-main -f
```

---

## 🎯 Diferenças da V1

**Removido (não funcionava):**
- ❌ `pg_createcluster`
- ❌ `pg_dropcluster`
- ❌ Comandos manuais complexos
- ❌ Scripts auxiliares

**Mantido (funcionava):**
- ✅ Instalação nativa do PostgreSQL
- ✅ `pg_basebackup` direto
- ✅ Configuração via `postgresql.conf`
- ✅ Estrutura simples e testada

---

## 📝 Notas

1. **Senhas geradas automaticamente** - mais seguras que senhas manuais
2. **Slots pré-criados** - suporta até 3 réplicas sem configuração adicional
3. **3 bancos criados** - um para cada ambiente
4. **Firewall configurado** - pronto para produção
5. **max_connections = 200** - valor adequado para o Plannerate

---

## 👨‍💻 Comandos Úteis

```bash
# Status do PostgreSQL
systemctl status postgresql

# Reiniciar PostgreSQL
sudo systemctl restart postgresql

# Ver processos
ps aux | grep postgres

# Ver conexões ativas
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"

# Ver tamanho dos bancos
sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;"
```

---

**Baseado em:** `setup-primary.sh` e `setup-replica.sh` (que funcionaram)  
**Adaptado para:** Plannerate com 3 bancos e 3 slots  
**Versão:** 2.0 - Simplificado e Funcional

