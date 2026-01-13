# PgBouncer - Connection Pooling para PostgreSQL

## 📖 O QUE É PGBOUNCER?

PgBouncer é um **connection pooler** leve para PostgreSQL. Ele fica entre a aplicação e o banco de dados, gerenciando e reutilizando conexões de forma eficiente.

## 🎯 POR QUE PRECISAMOS?

### Problema Atual
- **Laravel cria muitas conexões simultâneas**:
  - App container: 10-20 conexões
  - Queue/Horizon: 5-10 conexões
  - Scheduler: 2-5 conexões
  - Por ambiente (staging + production): **~50 conexões**

- **PostgreSQL tem limitações**:
  - Cada conexão consome memória (~10MB)
  - Limite padrão: 100 conexões
  - Overhead alto para criar/destruir conexões
  - Performance degrada com muitas conexões

### Solução com PgBouncer
- **Pool de conexões reutilizáveis**
- **Redução de overhead**: 10-50x mais rápido que criar novas conexões
- **Controle de limites**: Protege o PostgreSQL de sobrecarga
- **Transparente**: Aplicação não precisa mudar código

## 🏗️ ARQUITETURA

### Antes (Conexão Direta)
```
┌─────────────────────────────────────┐
│  VM Docker (148.230.78.184)         │
│  ├─ App (20 conexões)               │
│  ├─ Queue (10 conexões)             │
│  └─ Scheduler (5 conexões)          │
└─────────────┬───────────────────────┘
              │ 35 conexões diretas
              │ porta 5432
┌─────────────▼───────────────────────┐
│  PostgreSQL (72.62.139.43)          │
│  └─ 35 conexões ativas no banco     │
└─────────────────────────────────────┘
```

### Depois (Com PgBouncer)
```
┌─────────────────────────────────────┐
│  VM Docker (148.230.78.184)         │
│  ├─ App (20 conexões)               │
│  ├─ Queue (10 conexões)             │
│  └─ Scheduler (5 conexões)          │
└─────────────┬───────────────────────┘
              │ 35 conexões ao PgBouncer
              │ porta 6432
┌─────────────▼───────────────────────┐
│  PgBouncer (72.62.139.43:6432)      │
│  └─ Pool de 10-15 conexões          │
└─────────────┬───────────────────────┘
              │ 10-15 conexões reais
              │ porta 5432
┌─────────────▼───────────────────────┐
│  PostgreSQL (72.62.139.43:5432)     │
│  └─ Apenas 10-15 conexões ativas    │
└─────────────────────────────────────┘
```

**Benefício**: Redução de 35 → 15 conexões no PostgreSQL = ~200MB de RAM economizados + melhor performance

## ⚙️ CONFIGURAÇÃO

### Pool Modes (Modos de Pool)

PgBouncer tem 3 modos de operação:

#### 1. **Transaction Mode** (Recomendado)
- **Quando**: Conexão liberada após cada transação
- **Prós**: Máxima eficiência de pool
- **Contras**: Não suporta prepared statements, temp tables
- **Uso**: APIs REST, requisições HTTP stateless

#### 2. **Session Mode**
- **Quando**: Conexão mantida durante toda a sessão
- **Prós**: Compatibilidade total, suporta prepared statements
- **Contras**: Menor eficiência de pool
- **Uso**: Aplicações que usam prepared statements

#### 3. **Statement Mode**
- **Quando**: Conexão liberada após cada statement
- **Prós**: Máxima eficiência
- **Contras**: Muitas limitações
- **Uso**: Raramente usado

### Configuração Recomendada para Plannerate

```ini
[databases]
plannerate_production = host=127.0.0.1 port=5432 dbname=plannerate_production
plannerate_staging = host=127.0.0.1 port=5432 dbname=plannerate_staging

[pgbouncer]
# Modo de pool (transaction recomendado)
pool_mode = transaction

# Tamanhos de pool
default_pool_size = 20           # Conexões por database
max_client_conn = 200            # Máximo de clientes simultâneos
max_db_connections = 50          # Máximo total no PostgreSQL

# Timeouts
server_idle_timeout = 600        # 10 minutos
query_timeout = 0                # Sem timeout de query

# Autenticação
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

# Porta de escuta
listen_addr = 0.0.0.0
listen_port = 6432

# Admin
admin_users = postgres
stats_users = replicator
```

### Arquivo de Usuários (userlist.txt)

```
"plannerate_prod" "SENHA_HASH_MD5"
"plannerate_staging" "SENHA_HASH_MD5"
"replicator" "SENHA_HASH_MD5"
```

## 📝 IMPLEMENTAÇÃO

### Passo 1: Instalar PgBouncer no Servidor PostgreSQL

```bash
# No servidor 72.62.139.43
sudo apt update
sudo apt install -y pgbouncer

# Verificar instalação
pgbouncer --version
```

### Passo 2: Configurar PgBouncer

Script `setup-pgbouncer.sh` criará:
- `/etc/pgbouncer/pgbouncer.ini` - Configuração principal
- `/etc/pgbouncer/userlist.txt` - Usuários e senhas
- `/etc/default/pgbouncer` - Variáveis de ambiente
- Systemd service habilitado

### Passo 3: Atualizar Firewall

```bash
# Liberar porta 6432 para VM Docker
sudo ufw allow from 148.230.78.184 to any port 6432
```

### Passo 4: Atualizar .env nos Containers

**Antes:**
```env
DB_HOST=72.62.139.43
DB_PORT=5432
```

**Depois:**
```env
DB_HOST=72.62.139.43
DB_PORT=6432  # Porta do PgBouncer
```

### Passo 5: Reiniciar Containers

```bash
# Production
cd /opt/plannerate/production
docker compose restart app queue scheduler

# Staging
cd /opt/plannerate/staging
docker compose restart app queue scheduler
```

## 📊 MONITORAMENTO

### Comandos Úteis

```bash
# Conectar ao console admin do PgBouncer
psql -h 72.62.139.43 -p 6432 -U replicator pgbouncer

# Ver pools ativos
SHOW POOLS;

# Ver estatísticas
SHOW STATS;

# Ver configurações
SHOW CONFIG;

# Ver clientes conectados
SHOW CLIENTS;

# Ver servidores (conexões ao PostgreSQL)
SHOW SERVERS;
```

### Métricas Importantes

| Métrica | O que observar | Valor ideal |
|---------|----------------|-------------|
| `cl_active` | Clientes ativos | < 80% de max_client_conn |
| `sv_active` | Conexões PostgreSQL ativas | < default_pool_size |
| `sv_idle` | Conexões idle no pool | > 5 |
| `maxwait` | Tempo máximo de espera | 0 (sem espera) |

## 🧪 TESTES

### Teste 1: Verificar Conexão

```bash
# Conectar através do PgBouncer
psql -h 72.62.139.43 -p 6432 -U plannerate_prod -d plannerate_production

# Executar query simples
SELECT version();
```

### Teste 2: Teste de Carga

```bash
# pgbench através do PgBouncer
pgbench -h 72.62.139.43 -p 6432 -U plannerate_prod -d plannerate_production \
  -c 50 -j 4 -T 60

# Comparar com conexão direta
pgbench -h 72.62.139.43 -p 5432 -U plannerate_prod -d plannerate_production \
  -c 50 -j 4 -T 60
```

### Teste 3: Verificar Pool

```sql
-- No console admin
SHOW POOLS;
-- Deve mostrar:
--   plannerate_production | 20 conexões no pool
--   plannerate_staging    | 20 conexões no pool
```

## 🚨 TROUBLESHOOTING

### Problema: "no more connections allowed"

**Causa**: Pool esgotado, muitos clientes simultâneos

**Solução**:
```ini
# Aumentar pool size
default_pool_size = 30
max_client_conn = 300
```

### Problema: "prepared statement does not exist"

**Causa**: Pool mode é `transaction`, mas app usa prepared statements

**Solução**:
```ini
# Mudar para session mode
pool_mode = session
```

### Problema: "SSL connection required"

**Causa**: PostgreSQL requer SSL mas PgBouncer não está configurado

**Solução**:
```ini
# Desabilitar SSL no PgBouncer (conexão local)
server_tls_sslmode = disable
```

## 📈 BENEFÍCIOS ESPERADOS

### Performance
- ⚡ **Latência**: Redução de 10-30ms por query
- ⚡ **Throughput**: +50% de queries por segundo
- ⚡ **Overhead**: Redução de 10-50x no tempo de conexão

### Recursos
- 💾 **Memória**: Economia de ~200MB no PostgreSQL
- 💾 **CPU**: Redução de 10-20% no uso
- 📊 **Conexões**: De 50 → 15 conexões ativas

### Estabilidade
- ✅ Proteção contra connection storms
- ✅ Melhor previsibilidade de carga
- ✅ Facilita scaling horizontal

## 🔗 REFERÊNCIAS

- [Documentação Oficial PgBouncer](https://www.pgbouncer.org/)
- [Pool Modes Explained](https://www.pgbouncer.org/features.html)
- [Best Practices](https://www.pgbouncer.org/config.html)

---

**Status**: Pronto para implementação  
**Tempo estimado**: 1-2 horas  
**Risco**: Baixo (rollback simples mudando porta de volta para 5432)
