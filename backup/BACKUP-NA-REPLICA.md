# Configurar Backups na Réplica

Guia para rodar os backups no servidor **réplica** (não no primário).

---

## Fluxo geral

- **setup-replica.sh** → só instala a réplica (PostgreSQL em modo réplica).
- **Backup** → configurado à parte: clonar o repositório na réplica, criar `.backup-env` e configurar o cron (ou apontar direto para `postgres-replicas/backup/`).

Os scripts ficam em `postgres-replicas/backup/` e são usados **direto** dessa pasta (não é necessário copiar para `/root/`).

---

## Por que na réplica?

- Não sobrecarrega o primário
- Dados já estão sincronizados na réplica
- Mesmo resultado, menos impacto

---

## 1. Ter o pacote na réplica

Na réplica, clone o repositório (ou copie a pasta do pacote). Exemplo:

```bash
# Na réplica
cd /root
git clone https://github.com/SEU_ORG/postgres-replicas.git
# ou: copie a pasta postgres-replicas para /root/
```

Os scripts de backup ficam em `postgres-replicas/backup/`.

---

## 2. Configurar credenciais (.backup-env)

```bash
cd /root/postgres-replicas/backup
cp .backup-env.example /root/.backup-env
nano /root/.backup-env   # preencher credenciais S3 e Postgres
chmod 600 /root/.backup-env
```

O `.backup-env` na réplica deve ter:

- `POSTGRES_HOST=127.0.0.1` → backup usa o PostgreSQL local (réplica)
- Mesmas credenciais S3 e senha do Postgres do primário

---

## 3. Instalar dependências na réplica

```bash
apt update && apt install -y awscli
which pg_dump   # já vem com PostgreSQL
```

---

## 4. Testar backup na réplica

```bash
source /root/.backup-env

/root/postgres-replicas/backup/backup-to-s3.sh
/root/postgres-replicas/backup/postgres-backup-tables-hours.sh
/root/postgres-replicas/backup/postgres-backup-tables-full.sh
```

Se os três rodarem sem erro, está ok. (Ajuste o path se o repo estiver em outro lugar.)

---

## 5. Configurar cron na réplica

Cron deve apontar **direto** para `postgres-replicas/backup/`:

```bash
crontab -e
```

Adicionar (ajuste o path se o repo não estiver em `/root/postgres-replicas`):

```cron
# Backups na RÉPLICA (não rodar no primário)
# Scripts usados direto de postgres-replicas/backup/

0 * * * * source /root/.backup-env && /root/postgres-replicas/backup/postgres-backup-tables-hours.sh >> /var/log/postgresql-backup-hourly.log 2>&1
0 3 * * * source /root/.backup-env && /root/postgres-replicas/backup/postgres-backup-tables-full.sh >> /var/log/postgresql-backup-daily.log 2>&1
0 4 * * * source /root/.backup-env && /root/postgres-replicas/backup/backup-to-s3.sh >> /var/log/postgresql-backup.log 2>&1
```

---

## 6. Scripts nesta pasta

| Script | O que faz | Cron |
|--------|-----------|------|
| `backup-to-s3.sh` | Backup completo .sql.gz | 4h |
| `postgres-backup-tables-hours.sh` | 6 tabelas críticas (só bancos cliente) | A cada hora |
| `postgres-backup-tables-full.sh` | Todas as tabelas (todos os bancos) | 3h |
| `restore-from-s3.sh` | Restore .sql.gz | Manual |
| `restore-tables-from-s3.sh` | Restore por tabelas (1 banco ou --all-databases) | Manual |

**Principal vs cliente (dinâmico):** Principal = banco com tabelas `tenants` e `clients`; caso contrário = cliente. Nenhum nome de banco é fixo. Nome do backup = nome do banco (restaurar no mesmo lugar).

---

## 7. Logs na réplica

```bash
tail -f /var/log/postgresql-backup-hourly.log
tail -f /var/log/postgresql-backup-daily.log
tail -f /var/log/postgresql-backup.log
```

---

## Checklist

- [ ] Repositório (ou pasta do pacote) disponível na réplica em `postgres-replicas/backup/`
- [ ] `.backup-env` configurado em `/root/.backup-env` e com permissão 600
- [ ] `awscli` instalado na réplica
- [ ] Teste manual dos 3 scripts de backup
- [ ] Cron configurado na réplica apontando para `postgres-replicas/backup/*.sh`
- [ ] **Backups não rodam no primário** (sem cron de backup no primário)
