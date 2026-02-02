# 🐘 PLANNERATE - PostgreSQL com Replicação e Backup

Pacote completo para configurar PostgreSQL com:
- ✅ Replicação Streaming (Primary + Replica)
- ✅ Backup automático para S3 (DigitalOcean Spaces)
- ✅ Restore por tabelas ou banco completo
- ✅ Configuração otimizada para Laravel

## 📁 Estrutura do Pacote

```
postgres-replicas/
├── ONDE-USAR.md                  # Primário vs Réplica (leia primeiro)
├── setup-primary.sh              # PRIMÁRIO: setup do servidor primário
├── setup-replica.sh              # RÉPLICA: setup de replicação (uma vez)
├── GUIA DE INÍCIO RÁPIDO.md      # Guia completo de instalação
├── backup/                       # RÉPLICA: copiar esta pasta para a réplica
│   ├── BACKUP-NA-REPLICA.md      # Guia: configurar backups na réplica
│   ├── README.md                 # Documentação dos scripts
│   ├── .backup-env.example       # Exemplo de configuração
│   ├── backup-to-s3.sh           # Backup completo .sql.gz
│   ├── postgres-backup-tables-hours.sh   # Backup horário
│   ├── postgres-backup-tables-full.sh    # Backup diário
│   ├── restore-from-s3.sh        # Restore completo
│   └── restore-tables-from-s3.sh # Restore por tabelas
└── .credentials.example          # Exemplo de credenciais
```

**Separação:** Primário = só instalação. Réplica = instalação + **backups** (cron só na réplica).

## ⚡ Quick Start

### 1. Configurar Servidor Primário

```bash
ssh root@SEU_SERVIDOR_PRIMARIO
wget -O setup-primary.sh https://SEU_REPO/setup-primary.sh
chmod +x setup-primary.sh
./setup-primary.sh
```

### 2. Configurar Servidor Réplica

```bash
# Copiar replica-config.txt do primário para a réplica
scp /root/plannerate-config/replica-config.txt root@SEU_SERVIDOR_REPLICA:/root/

# Na réplica
ssh root@SEU_SERVIDOR_REPLICA
wget -O setup-replica.sh https://SEU_REPO/setup-replica.sh
chmod +x setup-replica.sh
./setup-replica.sh
```

### 3. Configurar Backups (somente na RÉPLICA)

Backups **não** rodam no primário. Use a pasta `backup/` **na réplica**:

```bash
# Na réplica: copiar pasta backup/ para /root/, configurar .backup-env e cron
# Ver: backup/BACKUP-NA-REPLICA.md
```

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                     SERVIDOR PRIMÁRIO                            │
│                    (Read/Write - 5432)                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ plannerate_production │ plannerate_staging │ clientes...  │ │
│  └───────────────────────────────────────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────┘
                             │
            ┌────────────────┴────────────────┐
            │     Replicação Streaming        │
            │                                 │
            ▼                                 ▼
┌───────────────────────┐        ┌────────────────────────┐
│   SERVIDOR RÉPLICA    │        │   DigitalOcean Spaces  │
│  (Read-Only - 5432)   │        │        (Backup)        │
│                       │        │                        │
│  • Leitura            │        │  • hourly/ (48h)       │
│  • Analytics          │        │  • daily/ (30d)        │
│  • Reports            │        │  • postgresql/ (30d)   │
└───────────────────────┘        └────────────────────────┘
```

## 📊 Estratégia de Backup

| Tipo | Frequência | Conteúdo | Retenção |
|------|------------|----------|----------|
| **Horário** | A cada hora | 6 tabelas críticas (planograms, gondolas, sections, shelves, segments, layers) | 48 horas |
| **Diário** | 3h manhã | Todas as tabelas por arquivo | 30 dias |
| **Completo** | 4h manhã | Banco completo (.sql.gz) | 30 dias |

## 🔧 Comandos Úteis

### Verificar Replicação (no Primário)

```bash
sudo -u postgres psql -c "SELECT application_name, client_addr, state FROM pg_stat_replication;"
```

### Verificar Lag (na Réplica)

```bash
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"
```

### Listar Backups

```bash
./restore-tables-from-s3.sh --list daily
./restore-tables-from-s3.sh --list hourly
```

### Restaurar Banco

```bash
# Restaurar último backup diário
./restore-tables-from-s3.sh plannerate_albert --type daily

# Restaurar tabelas específicas do backup horário
./restore-tables-from-s3.sh plannerate_albert --type hourly --tables planograms,gondolas
```

## 📚 Documentação

- **[ONDE-USAR.md](ONDE-USAR.md)** - O que usar no primário vs na réplica
- **[GUIA DE INÍCIO RÁPIDO.md](GUIA%20DE%20INÍCIO%20RÁPIDO.md)** - Instalação passo a passo
- **[backup/BACKUP-NA-REPLICA.md](backup/BACKUP-NA-REPLICA.md)** - Configurar backups na réplica
- **[backup/README.md](backup/README.md)** - Detalhes dos scripts de backup

## 🔐 Segurança

- ⚠️ Mantenha `CREDENCIAIS-COMPLETAS.txt` em local seguro
- ⚠️ Use `chmod 600` em arquivos de credenciais
- ⚠️ Não commite `.backup-env` ou credenciais no Git
- ⚠️ Configure firewall para permitir apenas IPs necessários

## 📋 Checklist de Implantação

- [ ] Servidor Primário configurado (sem cron de backup)
- [ ] Servidor Réplica sincronizando
- [ ] Backups configurados **na réplica** (cron só na réplica)
- [ ] Laravel com read/write split (opcional)
- [ ] Restore testado
- [ ] Credenciais armazenadas com segurança

## 🆘 Suporte

Em caso de problemas:

1. Verifique os logs: `tail -f /var/log/postgresql/postgresql-*.log`
2. Verifique status: `systemctl status postgresql`
3. Consulte a documentação detalhada nos arquivos `.md`

---

**Plannerate Team** 🚀
