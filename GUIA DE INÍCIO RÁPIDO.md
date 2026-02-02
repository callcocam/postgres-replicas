# 🚀 PLANNERATE - Guia de Instalação PostgreSQL

Setup completo para ambiente de produção e staging com replicação.

## 📋 Arquitetura

```
┌─────────────────────────────────────────┐
│  SERVIDOR PRIMÁRIO (Read/Write)         │
│  ┌─────────────────────────────────┐   │
│  │  plannerate_production          │   │
│  │  plannerate_staging             │   │
│  └─────────────────────────────────┘   │
└─────────────┬───────────────────────────┘
              │ Replicação Streaming
              │
┌─────────────▼───────────────────────────┐
│  SERVIDOR RÉPLICA (Read-Only)           │
│  ┌─────────────────────────────────┐   │
│  │  plannerate_production (sync)   │   │
│  │  plannerate_staging (sync)      │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## ⚡ Instalação Rápida

### PASSO 1: Configurar Servidor Primário

```bash
# 1. SSH no servidor primário
ssh root@SEU_SERVIDOR_PRIMARIO

# 2. Baixar o script
wget -O setup-plannerate-primary.sh https://SEU_REPO/setup-plannerate-primary.sh
# OU copiar manualmente

# 3. Dar permissão
chmod +x setup-plannerate-primary.sh

# 4. Executar
./setup-plannerate-primary.sh
```

**Aguarde a instalação...**

### PASSO 2: Copiar Arquivos Gerados

Após a instalação do primário, acesse os arquivos:

```bash
cd /root/plannerate-config
ls -la
```

**Arquivos importantes:**

1. **`replica-config.txt`** → Copiar para servidor réplica
2. **`laravel-env-production.txt`** → Usar no .env de produção
3. **`laravel-env-staging.txt`** → Usar no .env de staging
4. **`CREDENCIAIS-COMPLETAS.txt`** → Guardar em local seguro!

**Copiar replica-config.txt para a réplica:**

```bash
# Na sua máquina local ou no servidor primário
scp /root/plannerate-config/replica-config.txt root@SEU_SERVIDOR_REPLICA:/root/
```

### PASSO 3: Configurar Servidor Réplica

```bash
# 1. SSH no servidor réplica
ssh root@SEU_SERVIDOR_REPLICA

# 2. Verificar se o arquivo replica-config.txt foi copiado
ls -la /root/replica-config.txt

# 3. Baixar o script da réplica
wget -O setup-plannerate-replica.sh https://SEU_REPO/setup-plannerate-replica.sh
# OU copiar manualmente

# 4. Dar permissão
chmod +x setup-plannerate-replica.sh

# 5. Executar (o script vai ler replica-config.txt automaticamente)
./setup-plannerate-replica.sh
```

**Pronto! A réplica vai sincronizar automaticamente!**

---

## 🔐 Configuração Laravel

### Ambiente de Produção (somente primário)

Edite o `.env` da aplicação de produção:

```bash
# Copie do arquivo: laravel-env-production.txt
DB_CONNECTION=pgsql
DB_HOST=IP_DO_SERVIDOR_PRIMARIO
DB_PORT=5432
DB_DATABASE=plannerate_production
DB_USERNAME=plannerate_prod
DB_PASSWORD=SENHA_GERADA_AUTOMATICAMENTE
```

### Ambiente de Staging (somente primário)

Edite o `.env` da aplicação de staging:

```bash
# Copie do arquivo: laravel-env-staging.txt
DB_CONNECTION=pgsql
DB_HOST=IP_DO_SERVIDOR_PRIMARIO
DB_PORT=5432
DB_DATABASE=plannerate_staging
DB_USERNAME=plannerate_staging
DB_PASSWORD=SENHA_GERADA_AUTOMATICAMENTE
```

### Usar Réplica para Leitura (Produção)

Adicione no `.env` de produção:

```bash
# Escrita no primário
DB_HOST=IP_DO_SERVIDOR_PRIMARIO
DB_PORT=5432

# Leitura na réplica
DB_READ_HOST=IP_DO_SERVIDOR_REPLICA
DB_READ_PORT=5432
```

Atualize `config/database.php` (use o arquivo `laravel-database-config.php` gerado):

```php
'pgsql' => [
    'driver' => 'pgsql',
    'read' => [
        'host' => [
            env('DB_READ_HOST', env('DB_HOST', '127.0.0.1')),
        ],
    ],
    'write' => [
        'host' => [
            env('DB_HOST', '127.0.0.1'),
        ],
    ],
    'sticky' => true,
    'port' => env('DB_PORT', '5432'),
    'database' => env('DB_DATABASE', 'forge'),
    'username' => env('DB_USERNAME', 'forge'),
    'password' => env('DB_PASSWORD', ''),
    // ... resto da config
],
```

---

## ✅ Verificação

### No Servidor Primário:

```bash
# Ver réplicas conectadas
sudo -u postgres psql -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;"

# Listar databases
sudo -u postgres psql -l | grep plannerate

# Conectar produção
sudo -u postgres psql -d plannerate_production
```

### No Servidor Réplica:

```bash
# Verificar modo réplica (deve retornar 't')
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Verificar lag
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"

# Ver databases
sudo -u postgres psql -l | grep plannerate
```

---

## 🧪 Teste de Replicação

### 1. No Laravel (Produção) - Rodar migrations:

```bash
php artisan migrate
```

### 2. No Servidor Primário - Verificar tabelas:

```bash
sudo -u postgres psql -d plannerate_production -c "\dt"
```

### 3. No Servidor Réplica - Ver mesmas tabelas:

```bash
sudo -u postgres psql -d plannerate_production -c "\dt"
```

Deve mostrar as mesmas tabelas! ✅

### 4. Teste de Insert:

**No Laravel:**
```php
// No tinker ou código
use App\Models\User;
User::create(['name' => 'Test', 'email' => 'test@plannerate.com', 'password' => bcrypt('secret')]);
```

**Na Réplica:**
```bash
sudo -u postgres psql -d plannerate_production -c "SELECT * FROM users;"
```

---

## 📁 Estrutura de Arquivos Gerados

### Servidor Primário (`/root/plannerate-config/`)

```
replica-config.txt              ← Copiar para réplica
laravel-env-production.txt      ← Config Laravel produção
laravel-env-staging.txt         ← Config Laravel staging
laravel-database-config.php     ← Config database.php
CREDENCIAIS-COMPLETAS.txt       ← Todas as senhas (GUARDAR!)
```

### Servidor Réplica (`/root/plannerate-config/`)

```
replica-info.txt                ← Informações da réplica
```

---

## 🔥 Comandos Úteis

### Ver todas as credenciais:

```bash
# No servidor primário
cat /root/plannerate-config/CREDENCIAIS-COMPLETAS.txt
```

### Status dos serviços:

```bash
# PostgreSQL
systemctl status postgresql

# Ver logs
journalctl -u postgresql -f
```

### Backup manual:

```bash
# Produção
pg_dump -h IP_PRIMARIO -U plannerate_prod plannerate_production > backup_prod.sql

# Staging
pg_dump -h IP_PRIMARIO -U plannerate_staging plannerate_staging > backup_staging.sql
```

### Conectar remotamente:

```bash
# Do seu computador local
psql -h IP_PRIMARIO -U plannerate_prod -d plannerate_production
```

---

## 🏗️ Ambiente Local (Desenvolvimento)

Para desenvolvimento local, você pode:

### Opção 1: PostgreSQL Local

```bash
# Instalar PostgreSQL
sudo apt install postgresql-15

# Criar database local
sudo -u postgres createdb plannerate_local

# No .env local
DB_HOST=127.0.0.1
DB_DATABASE=plannerate_local
DB_USERNAME=postgres
```

### Opção 2: Docker

```yaml
# docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: plannerate_local
      POSTGRES_USER: plannerate
      POSTGRES_PASSWORD: secret
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

---

## 🆘 Troubleshooting

### Réplica não conecta:

```bash
# No primário - verificar firewall
sudo ufw status
sudo ufw allow from IP_DA_REPLICA to any port 5432

# Testar conectividade da réplica
ping IP_DO_PRIMARIO
telnet IP_DO_PRIMARIO 5432
```

### Erro "permission denied" ao usar psql:

```bash
# Execute de outro diretório
cd /tmp
sudo -u postgres psql -d plannerate_production
```

### Ver logs de erro:

```bash
# PostgreSQL logs
tail -100 /var/log/postgresql/postgresql-15-main.log

# Sistema
journalctl -u postgresql -n 100
```

### Recriar réplica:

```bash
# Na réplica
sudo systemctl stop postgresql
sudo rm -rf /var/lib/postgresql/15/main/*
./setup-plannerate-replica.sh
```

---

## 📊 Resumo das Senhas

Todas as senhas são geradas automaticamente e podem ser encontradas em:

```bash
/root/plannerate-config/CREDENCIAIS-COMPLETAS.txt
```

**IMPORTANTE:** 
- ✅ Faça backup deste arquivo
- ✅ Armazene em gerenciador de senhas (1Password, Bitwarden, etc)
- ✅ Não compartilhe publicamente
- ✅ Use variáveis de ambiente no Laravel (nunca hardcode)

---

---

## 📦 Configurar Backups Automáticos

### Passo 1: Configurar Credenciais S3

```bash
# Copiar exemplo
cp /root/postgres-replicas/backup/.backup-env.example /root/.backup-env

# Editar com suas credenciais
nano /root/.backup-env

# Proteger arquivo
chmod 600 /root/.backup-env
```

### Passo 2: Copiar Scripts de Backup

```bash
cp /root/postgres-replicas/backup/*.sh /root/
chmod +x /root/*.sh
```

### Passo 3: Testar Backups

```bash
# Testar backup horário (tabelas críticas)
/root/postgres-backup-tables-hours.sh

# Testar backup diário (todas tabelas)
/root/postgres-backup-tables-full.sh
```

### Passo 4: Configurar Cron

```bash
crontab -e

# Adicionar:
# Backup horário - a cada hora
0 * * * * source /root/.backup-env && /root/postgres-backup-tables-hours.sh >> /var/log/postgresql-backup-hourly.log 2>&1

# Backup diário - às 3h
0 3 * * * source /root/.backup-env && /root/postgres-backup-tables-full.sh >> /var/log/postgresql-backup-daily.log 2>&1

# Backup completo (.sql.gz) - às 4h
0 4 * * * source /root/.backup-env && /root/backup-to-s3.sh >> /var/log/postgresql-backup.log 2>&1
```

### Estratégia de Backup

| Tipo | Frequência | O que inclui | Retenção |
|------|------------|--------------|----------|
| **Horário** | A cada hora | 6 tabelas críticas (planograms, gondolas, sections, shelves, segments, layers) | 48 horas |
| **Diário** | 3h da manhã | Todas as tabelas por arquivo | 30 dias |
| **Completo** | 4h da manhã | Banco completo (.sql.gz) | 30 dias |

### Comandos de Restore

```bash
# Listar backups disponíveis
./restore-tables-from-s3.sh --list daily
./restore-tables-from-s3.sh --list hourly

# Restaurar banco completo
./restore-tables-from-s3.sh plannerate_albert --type daily

# Restaurar apenas algumas tabelas
./restore-tables-from-s3.sh plannerate_albert --type hourly --tables planograms,gondolas
```

📚 **Documentação completa:** `backup/README.md`

---

## 🎯 Checklist de Implantação

- [ ] Servidor Primário configurado
- [ ] Servidor Réplica configurado e sincronizando
- [ ] Laravel configurado com read/write split
- [ ] Backups automáticos configurados
- [ ] Restore testado e funcionando
- [ ] Monitoramento configurado (opcional)
- [ ] Alertas configurados (opcional)

---

## 🚀 Pronto!

Seu ambiente Plannerate está configurado com:

- ✅ 2 Databases (Produção + Staging)
- ✅ Replicação streaming em tempo real
- ✅ Read replicas para distribuir carga
- ✅ Senhas seguras geradas automaticamente
- ✅ Configuração Laravel pronta para usar

**Happy coding! 🎉**