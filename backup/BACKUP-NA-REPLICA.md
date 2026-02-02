# Configurar Backups na Réplica

Guia para rodar os backups no servidor **réplica** (não no primário).

---

## Por que na réplica?

- Não sobrecarrega o primário
- Dados já estão sincronizados na réplica
- Mesmo resultado, menos impacto

---

## 1. Copiar arquivos para a réplica

**De onde você tiver o pacote** (primário, repo clonado, etc.):

```bash
# Troque IP_REPLICA pelo IP da sua réplica (ex: 72.60.240.151)
IP_REPLICA=72.60.240.151

# Copiar toda a pasta backup/ para /root/ na réplica
scp backup/*.sh root@$IP_REPLICA:/root/
scp backup/.backup-env.example root@$IP_REPLICA:/root/

# Na réplica: renomear e configurar
ssh root@$IP_REPLICA "mv /root/.backup-env.example /root/.backup-env && chmod 600 /root/.backup-env"
ssh root@$IP_REPLICA "chmod +x /root/*.sh"
```

**Importante:** Edite `/root/.backup-env` na réplica com as credenciais reais (S3 + senha Postgres). Use o mesmo `.backup-env` do primário se já tiver; só garanta que `POSTGRES_HOST=127.0.0.1`.

---

## 2. Ajustar na réplica

O `.backup-env` na réplica deve ter:

- `POSTGRES_HOST=127.0.0.1` → backup usa o PostgreSQL local (réplica)
- Mesmas credenciais S3 e senha do Postgres do primário

---

## 3. Instalar dependências na réplica

```bash
# Na réplica
apt update && apt install -y awscli
which pg_dump   # já vem com PostgreSQL
```

---

## 4. Testar backup na réplica

```bash
# Na réplica
source /root/.backup-env

/root/backup-to-s3.sh
/root/postgres-backup-tables-hours.sh
/root/postgres-backup-tables-full.sh
```

Se os três rodarem sem erro, está ok.

---

## 5. Configurar cron na réplica

**Na réplica:**

```bash
crontab -e
```

Adicionar:

```cron
# Backups na RÉPLICA (não rodar no primário)

0 * * * * source /root/.backup-env && /root/postgres-backup-tables-hours.sh >> /var/log/postgresql-backup-hourly.log 2>&1
0 3 * * * source /root/.backup-env && /root/postgres-backup-tables-full.sh >> /var/log/postgresql-backup-daily.log 2>&1
0 4 * * * source /root/.backup-env && /root/backup-to-s3.sh >> /var/log/postgresql-backup.log 2>&1
```

---

## 6. Scripts nesta pasta

| Script | O que faz | Cron |
|--------|-----------|------|
| `backup-to-s3.sh` | Backup completo .sql.gz | 4h |
| `postgres-backup-tables-hours.sh` | 6 tabelas críticas | A cada hora |
| `postgres-backup-tables-full.sh` | Todas as tabelas | 3h |
| `restore-from-s3.sh` | Restore .sql.gz | Manual |
| `restore-tables-from-s3.sh` | Restore por tabelas | Manual |

---

## 7. Logs na réplica

```bash
tail -f /var/log/postgresql-backup-hourly.log
tail -f /var/log/postgresql-backup-daily.log
tail -f /var/log/postgresql-backup.log
```

---

## Checklist

- [ ] Pasta `backup/` copiada para a réplica em `/root/`
- [ ] `.backup-env` configurado e com permissão 600
- [ ] `awscli` instalado na réplica
- [ ] Teste manual dos 3 scripts
- [ ] Cron configurado na réplica
- [ ] **Backups não rodam no primário** (sem cron de backup no primário)
