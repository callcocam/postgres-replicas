# 🚀 PLANNERATE - PostgreSQL Setup Rápido

## 📦 Arquivos Disponíveis

### Scripts de Setup
- **`setup-plannerate-primary.sh`** - Instala e configura servidor primário
- **`setup-plannerate-replica.sh`** - Instala e configura réplica
- **`reset-plannerate.sh`** - Reset/recriação do cluster

### Documentação
- **`PLANNERATE-CONFIG.md`** - Documentação completa e comandos úteis
- **`.credentials.example`** - Exemplo de arquivo de credenciais

### Arquivos Gerados (não commitados)
- **`.plannerate-credentials.txt`** - Credenciais reais (gerado automaticamente)
- **`.plannerate-env-example`** - Exemplo de configuração .env
- **`backups/`** - Backups automáticos

---

## ⚡ Instalação Rápida

### 1️⃣ Servidor Primário (192.168.2.106)

```bash
# Executar no servidor primário
cd /home/call/projects/plannerate/postgres-replicas
sudo bash setup-plannerate-primary.sh
```

**Resultado:**
- ✅ PostgreSQL 15 instalado
- ✅ 3 databases criados (laravel, plannerate_staging, plannerate_production)
- ✅ Usuários criados com senhas seguras
- ✅ Credenciais salvas em `.plannerate-credentials.txt`
- ✅ Replicação configurada

**Próximo passo:** Copie o arquivo `.plannerate-credentials.txt` para usar na réplica

---

### 2️⃣ Réplica

```bash
# Copiar credenciais do primário (executar na réplica)
scp root@192.168.2.106:/home/call/projects/plannerate/postgres-replicas/.plannerate-credentials.txt .

# Executar setup da réplica
sudo bash setup-plannerate-replica.sh
```

**Resultado:**
- ✅ PostgreSQL 15 instalado
- ✅ Dados sincronizados do primário
- ✅ Configurada como read-only
- ✅ Streaming replication ativo

---

### 3️⃣ Configurar Aplicação

```bash
# Ver exemplo de configuração
cat .plannerate-env-example

# Atualizar seus arquivos .env com as credenciais
# .env (development)
# .env.staging
# .env.production
```

---

## 🔄 Reset/Recriação

```bash
sudo bash reset-plannerate.sh
```

**Opções:**
1. Reset PRIMÁRIO - Recria servidor primário do zero
2. Reset RÉPLICA - Recria réplica do zero
3. Reset COMPLETO - Remove tudo
4. Backup + Reset - Faz backup antes de resetar
5. Apenas Backup - Só backup sem resetar

---

## 📊 Verificações Rápidas

### No Primário

```bash
# Ver réplicas conectadas
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Ver databases
sudo -u postgres psql -l
```

### Na Réplica

```bash
# Verificar recovery mode (deve ser 't')
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"

# Ver lag de replicação
sudo -u postgres psql -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;"
```

---

## 🗄️ Estrutura do Cluster

```
PRIMÁRIO (192.168.2.106)     →     RÉPLICA (VM Local)
┌─────────────────────┐            ┌──────────────────┐
│ laravel             │   stream   │ laravel          │
│ plannerate_staging  │───────────→│ plannerate_staging│
│ plannerate_production│           │ plannerate_prod... │
│                     │            │                  │
│ Read + Write        │            │ Read-Only        │
└─────────────────────┘            └──────────────────┘
```

---

## 🔐 Segurança

### ⚠️ IMPORTANTE

- **NUNCA** commite `.plannerate-credentials.txt` no Git
- O arquivo já está no `.gitignore`
- Mantenha backups seguros das credenciais
- Senhas são geradas automaticamente com 32 caracteres

---

## 📚 Documentação Completa

Para informações detalhadas, comandos úteis e troubleshooting, consulte:

**[PLANNERATE-CONFIG.md](PLANNERATE-CONFIG.md)**

Contém:
- Arquitetura completa
- Todas as configurações
- 50+ comandos úteis
- Guia de troubleshooting
- Checklist de instalação

---

## 🆘 Problemas Comuns

### Réplica não conecta

```bash
# Verificar conectividade
ping 192.168.2.106

# Verificar firewall
sudo ufw status

# Ver logs
tail -50 /var/log/postgresql/postgresql-15-main.log
```

### Credenciais perdidas

```bash
# Opção 1: Recuperar do backup
ls -la backups/

# Opção 2: Resetar e gerar novas
sudo bash reset-plannerate.sh
```

---

## 📞 Suporte

Para problemas ou dúvidas:

1. Consulte **PLANNERATE-CONFIG.md** (documentação completa)
2. Verifique os logs: `tail -100 /var/log/postgresql/postgresql-15-main.log`
3. Entre em contato com a equipe Plannerate

---

## ✅ Checklist Rápido

### Primário
- [ ] Executou `setup-plannerate-primary.sh`
- [ ] Salvou `.plannerate-credentials.txt`
- [ ] Testou conexão

### Réplica
- [ ] Copiou `.plannerate-credentials.txt`
- [ ] Executou `setup-plannerate-replica.sh`
- [ ] Verificou replicação

### Aplicação
- [ ] Atualizou `.env`
- [ ] Atualizou `.env.staging`
- [ ] Atualizou `.env.production`
- [ ] Rodou migrations

---

**Versão**: 1.0  
**Data**: 2025-01-09  
**Projeto**: Plannerate

