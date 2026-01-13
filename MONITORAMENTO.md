# 📊 MONITORAMENTO - Prometheus + Grafana

Sistema completo de monitoramento para a infraestrutura Plannerate usando Prometheus (coleta de métricas) e Grafana (visualização).

---

## 📋 ÍNDICE

1. [Visão Geral](#visão-geral)
2. [Arquitetura](#arquitetura)
3. [Componentes](#componentes)
4. [Instalação](#instalação)
5. [Configuração](#configuração)
6. [Dashboards](#dashboards)
7. [Alertas](#alertas)
8. [Acesso](#acesso)
9. [Troubleshooting](#troubleshooting)

---

## 🎯 VISÃO GERAL

### O que está sendo monitorado?

| Componente | Métricas | Exporter | Porta |
|-----------|----------|----------|-------|
| **Sistema (VM Docker)** | CPU, RAM, Disco, Rede | Node Exporter | 9100 |
| **Sistema (VM PostgreSQL)** | CPU, RAM, Disco, Rede | Node Exporter | 9100 |
| **PostgreSQL Master** | Conexões, queries, locks, replicação | PostgreSQL Exporter | 9187 |
| **PgBouncer** | Pools, clientes, queries | PgBouncer Exporter | 9127 |
| **Redis** | Memória, comandos, keyspace | Redis Exporter | 9121 |
| **Containers Docker** | CPU, memória, I/O | cAdvisor | 8080 |

### Benefícios

✅ **Visibilidade completa** da infraestrutura em tempo real  
✅ **Alertas automáticos** para problemas críticos  
✅ **Histórico de 15 dias** de métricas  
✅ **Dashboards prontos** da comunidade  
✅ **100% gratuito** e open source  
✅ **Performance mínima** (< 200MB RAM total)  

---

## 🏗️ ARQUITETURA

```
┌─────────────────────────────────────────────────────────────────┐
│                    VM DOCKER (148.230.78.184)                   │
│                                                                 │
│  ┌──────────────┐      ┌─────────────┐      ┌──────────────┐  │
│  │  Prometheus  │─────▶│   Grafana   │─────▶│ Alertmanager │  │
│  │   :9090      │      │    :3000    │      │    :9093     │  │
│  └──────┬───────┘      └─────────────┘      └──────────────┘  │
│         │                                                       │
│         │ scrape (pull)                                        │
│         │                                                       │
│         ├──────────────────────────────────────────┐           │
│         │                                           │           │
│         ▼                                           ▼           │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────────────┐│
│  │Node Exporter│  │Redis Exporter│  │      cAdvisor          ││
│  │   :9100     │  │   :9121      │  │  (Container Metrics)   ││
│  └─────────────┘  └─────────────┘  └────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ scrape (pull)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                VM POSTGRESQL (72.62.139.43)                     │
│                                                                 │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │Node Exporter│  │PostgreSQL Exporter│  │PgBouncer Exporter│  │
│  │   :9100     │  │      :9187        │  │      :9127       │  │
│  └─────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                 │
│  ┌────────────┐   ┌──────────┐                                 │
│  │ PostgreSQL │   │ PgBouncer│                                 │
│  │   :5432    │   │  :6432   │                                 │
│  └────────────┘   └──────────┘                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧩 COMPONENTES

### 1. Prometheus (Coleta de Métricas)

**Função**: Coletar e armazenar métricas em time-series database  
**Porta**: 9090  
**Acesso**: https://prometheus.plannerate.com.br (com autenticação)  
**Retenção**: 15 dias  
**Scrape Interval**: 15 segundos  

**Recursos**:
- Query language (PromQL)
- Regras de alerta
- Service discovery
- HTTP API

---

### 2. Grafana (Visualização)

**Função**: Criar dashboards e visualizações das métricas  
**Porta**: 3000  
**Acesso**: https://grafana.plannerate.com.br  
**Login**: admin / plannerate2026  

**Recursos**:
- Dashboards interativos
- Alertas visuais
- Múltiplos datasources
- Plugins e extensões

---

### 3. Alertmanager (Gerenciamento de Alertas)

**Função**: Agrupar, rotear e silenciar alertas  
**Porta**: 9093  

**Recursos**:
- Agrupamento de alertas
- Roteamento por severidade
- Silenciamento temporário
- Integração com email/Slack/Discord

---

### 4. Exporters (Coleta de Métricas)

#### Node Exporter
- **Função**: Métricas de sistema operacional
- **Porta**: 9100
- **Instalado em**: Ambos servidores
- **Métricas**: CPU, RAM, disco, rede, processos

#### PostgreSQL Exporter
- **Função**: Métricas do banco PostgreSQL
- **Porta**: 9187
- **Instalado em**: 72.62.139.43
- **Métricas**: Conexões, queries, locks, cache, tamanho

#### PgBouncer Exporter
- **Função**: Métricas do connection pool
- **Porta**: 9127
- **Instalado em**: 72.62.139.43
- **Métricas**: Pools, clientes, latência, throughput

#### Redis Exporter
- **Função**: Métricas do Redis
- **Porta**: 9121
- **Instalado em**: Container Docker
- **Métricas**: Memória, comandos, keyspace, hit rate

#### cAdvisor
- **Função**: Métricas de containers Docker
- **Porta**: 8080
- **Instalado em**: Container Docker
- **Métricas**: CPU, memória, I/O, rede por container

---

## 🚀 INSTALAÇÃO

### Passo 1: Instalar Exporters no Servidor PostgreSQL

```bash
# No servidor PostgreSQL (72.62.139.43)
cd /root
wget https://raw.githubusercontent.com/.../setup-monitoring-exporters.sh
chmod +x setup-monitoring-exporters.sh
./setup-monitoring-exporters.sh
```

O script irá:
1. ✅ Instalar Node Exporter (métricas de sistema)
2. ✅ Instalar PostgreSQL Exporter (métricas do banco)
3. ✅ Instalar PgBouncer Exporter (métricas do pool)
4. ✅ Configurar services systemd
5. ✅ Abrir portas no firewall
6. ✅ Testar endpoints

---

### Passo 2: Subir Stack de Monitoramento no Servidor Docker

```bash
# No servidor Docker (148.230.78.184)
cd /opt/plannerate

# Copiar arquivos de configuração
scp -r user@local:/path/to/monitoring /opt/plannerate/
scp user@local:/path/to/docker-compose.monitoring.yml /opt/plannerate/

# Subir os containers
docker compose -f docker-compose.monitoring.yml up -d

# Verificar status
docker compose -f docker-compose.monitoring.yml ps
```

---

### Passo 3: Configurar DNS (Traefik)

Adicionar no DNS:

```
prometheus.plannerate.com.br → 148.230.78.184
grafana.plannerate.com.br → 148.230.78.184
```

O Traefik já está configurado com labels no `docker-compose.monitoring.yml` e irá:
- ✅ Gerar certificados SSL automáticos (Let's Encrypt)
- ✅ Rotear tráfego HTTPS
- ✅ Proteger Prometheus com autenticação básica

---

## ⚙️ CONFIGURAÇÃO

### Prometheus

Arquivo: `monitoring/prometheus.yml`

**Principais configurações**:
- `scrape_interval: 15s` - Coletar métricas a cada 15 segundos
- `retention: 15d` - Manter histórico por 15 dias
- `targets` - Lista de endpoints para scraping

**Modificar targets**:
```yaml
scrape_configs:
  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['72.62.139.43:9187']
```

**Recarregar configuração**:
```bash
curl -X POST http://localhost:9090/-/reload
# ou
docker compose -f docker-compose.monitoring.yml restart prometheus
```

---

### Alertmanager

Arquivo: `monitoring/alertmanager.yml`

**Configurar Email (SMTP)**:
```yaml
global:
  smtp_from: 'alertmanager@plannerate.com.br'
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'your-email@gmail.com'
  smtp_auth_password: 'your-app-password'
  smtp_require_tls: true

receivers:
  - name: 'critical'
    email_configs:
      - to: 'admin@plannerate.com.br'
        subject: '🚨 CRÍTICO: {{ .GroupLabels.alertname }}'
```

**Configurar Slack**:
```yaml
receivers:
  - name: 'critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#alerts-critical'
        title: '🚨 {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

---

### Regras de Alerta

Arquivo: `monitoring/alerts.yml`

**Alertas configurados**:

| Alerta | Condição | Severidade | Descrição |
|--------|----------|------------|-----------|
| PostgreSQLDown | UP == 0 por 1min | 🔴 Critical | PostgreSQL offline |
| PgBouncerDown | UP == 0 por 1min | 🔴 Critical | PgBouncer offline |
| RedisDown | UP == 0 por 1min | 🔴 Critical | Redis offline |
| HighCPUUsage | CPU > 80% por 5min | 🟡 Warning | CPU alto |
| HighMemoryUsage | RAM > 90% por 5min | 🟡 Warning | Memória alta |
| DiskSpaceRunningOut | Disco < 15% | 🔴 Critical | Disco cheio |
| PostgreSQLTooManyConnections | Conexões > 80 | 🟡 Warning | Muitas conexões |
| PostgreSQLReplicationLag | Lag > 10MB por 5min | 🟡 Warning | Replicação atrasada |

**Adicionar novos alertas**:
```yaml
- alert: CustomAlert
  expr: metric_name > threshold
  for: 5m
  labels:
    severity: warning
    component: system
  annotations:
    summary: "Descrição curta"
    description: "Descrição detalhada com {{ $value }}"
```

---

## 📈 DASHBOARDS

### Dashboards Recomendados

Ver arquivo completo: `monitoring/grafana/dashboards/README.md`

**Quick Import**:

1. **Node Exporter Full** (ID: 1860)
   - CPU, memória, disco, rede
   - Para: ambos servidores

2. **PostgreSQL Database** (ID: 9628)
   - Conexões, queries, locks, cache
   - Para: servidor PostgreSQL

3. **PgBouncer Stats** (ID: 16396)
   - Pools, throughput, latência
   - Para: PgBouncer

4. **Redis Dashboard** (ID: 763)
   - Memória, comandos, keyspace
   - Para: Redis

5. **Docker Containers** (ID: 193)
   - Container metrics via cAdvisor
   - Para: servidor Docker

### Como importar

```
Grafana → + → Import Dashboard → Cole o ID → Load → Import
```

---

## 🚨 ALERTAS

### Estados de Alerta

| Estado | Descrição |
|--------|-----------|
| **Inactive** | Tudo OK, sem alertas |
| **Pending** | Condição atingida, aguardando confirmação (`for` duration) |
| **Firing** | Alerta ativo e sendo enviado |
| **Resolved** | Alerta resolvido automaticamente |

### Fluxo de Alerta

```
Prometheus detecta problema
        ↓
Aguarda tempo de confirmação (for: 5m)
        ↓
Envia para Alertmanager
        ↓
Alertmanager agrupa e roteia
        ↓
Notificação enviada (email/Slack/webhook)
```

### Silenciar Alertas

**Via UI**:
1. Acesse Alertmanager: http://148.230.78.184:9093
2. Clique no alerta
3. "Silence"
4. Defina duração
5. Adicione comentário
6. Confirme

**Via CLI**:
```bash
amtool silence add alertname="PostgreSQLDown" -d 1h -c "Manutenção programada"
```

---

## 🔐 ACESSO

### URLs

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| **Grafana** | https://grafana.plannerate.com.br | admin / plannerate2026 |
| **Prometheus** | https://prometheus.plannerate.com.br | admin / admin |
| **Alertmanager** | http://148.230.78.184:9093 | - |

### Autenticação Prometheus

Usuário: `admin`  
Senha: `admin`

Hash gerado com:
```bash
htpasswd -nb admin admin
```

**Alterar senha**:
```bash
# Gerar novo hash
htpasswd -nb admin nova_senha

# Atualizar label no docker-compose.monitoring.yml
traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$...
```

### Alterar Senha Grafana

**Via UI**:
1. Login → Profile → Change Password

**Via CLI**:
```bash
docker compose -f docker-compose.monitoring.yml exec grafana \
    grafana-cli admin reset-admin-password nova_senha
```

---

## 🔧 TROUBLESHOOTING

### Exporter não está coletando métricas

**Verificar status do service**:
```bash
ssh root@72.62.139.43
systemctl status node-exporter
systemctl status postgres-exporter
systemctl status pgbouncer-exporter
```

**Verificar logs**:
```bash
journalctl -u node-exporter -f
journalctl -u postgres-exporter -f
journalctl -u pgbouncer-exporter -f
```

**Testar endpoint manualmente**:
```bash
curl http://localhost:9100/metrics
curl http://localhost:9187/metrics
curl http://localhost:9127/metrics
```

**Reiniciar exporter**:
```bash
systemctl restart node-exporter
```

---

### Prometheus não está scraping targets

**Verificar targets no Prometheus UI**:
1. Acesse https://prometheus.plannerate.com.br
2. Status → Targets
3. Verifique se targets estão "UP"

**Causas comuns**:
- ❌ Firewall bloqueando porta
- ❌ Exporter não está rodando
- ❌ IP/hostname incorreto no prometheus.yml
- ❌ Porta incorreta

**Solução**:
```bash
# Testar conectividade do Docker para PostgreSQL
ssh root@148.230.78.184
curl http://72.62.139.43:9187/metrics

# Se falhar, verificar firewall
ssh root@72.62.139.43
ufw status | grep 9187
```

---

### Grafana não mostra dados

**Verificar datasource**:
1. Grafana → Configuration → Data Sources
2. Prometheus deve estar "Working"
3. Se não, verificar URL: `http://prometheus:9090`

**Testar query manualmente**:
1. Grafana → Explore
2. Selecionar datasource "Prometheus"
3. Executar query simples: `up`
4. Deve retornar targets

---

### Alertas não estão sendo enviados

**Verificar se alerta está firing**:
1. Prometheus → Alerts
2. Verificar estado do alerta

**Verificar Alertmanager**:
```bash
# Ver alertas ativos
curl http://localhost:9093/api/v2/alerts

# Ver logs
docker compose -f docker-compose.monitoring.yml logs alertmanager
```

**Verificar configuração de notificação**:
- Email: Verificar credenciais SMTP em `alertmanager.yml`
- Slack: Verificar webhook URL
- Testar envio manual

---

### Container usando muita memória/CPU

**Identificar container problemático**:
```bash
docker stats --no-stream
```

**Ver logs**:
```bash
docker logs prometheus --tail 100
docker logs grafana --tail 100
```

**Ajustar recursos**:

Adicionar limits no `docker-compose.monitoring.yml`:
```yaml
services:
  prometheus:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

---

### Prometheus está com disco cheio

**Verificar uso de disco**:
```bash
docker compose -f docker-compose.monitoring.yml exec prometheus \
    du -sh /prometheus
```

**Reduzir retenção**:

Editar `docker-compose.monitoring.yml`:
```yaml
command:
  - '--storage.tsdb.retention.time=7d'  # de 15d para 7d
```

**Limpar dados antigos**:
```bash
docker compose -f docker-compose.monitoring.yml stop prometheus
docker volume rm plannerate_prometheus-data
docker compose -f docker-compose.monitoring.yml up -d prometheus
```

---

## 📊 MÉTRICAS IMPORTANTES

### PostgreSQL

```promql
# Conexões ativas
pg_stat_activity_count

# Taxa de queries por segundo
rate(pg_stat_database_xact_commit[5m])

# Cache hit ratio (deve ser > 90%)
(pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)) * 100

# Replication lag (bytes)
pg_replication_lag

# Database size
pg_database_size_bytes
```

### PgBouncer

```promql
# Conexões ativas
pgbouncer_pools_cl_active

# Conexões aguardando
pgbouncer_pools_cl_waiting

# Queries por segundo
rate(pgbouncer_stats_queries_total[5m])

# Tempo médio de query
rate(pgbouncer_stats_query_time_seconds_total[5m]) / rate(pgbouncer_stats_queries_total[5m])
```

### Sistema

```promql
# CPU usage (%)
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk space (%)
(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# Disk I/O
rate(node_disk_read_bytes_total[5m])
rate(node_disk_written_bytes_total[5m])
```

---

## 🎯 PRÓXIMOS PASSOS

1. ✅ Instalar exporters no servidor PostgreSQL
2. ✅ Subir stack de monitoramento no Docker
3. ✅ Configurar DNS (prometheus/grafana subdomains)
4. ⏳ Importar dashboards recomendados
5. ⏳ Configurar notificações (email/Slack)
6. ⏳ Ajustar thresholds de alertas conforme necessário
7. ⏳ Criar dashboards customizados para métricas da aplicação

---

## 📚 REFERÊNCIAS

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [PostgreSQL Exporter](https://github.com/prometheus-community/postgres_exporter)
- [PgBouncer Exporter](https://github.com/prometheus-community/pgbouncer_exporter)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
