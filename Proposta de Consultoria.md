# PROPOSTA TÉCNICA E COMERCIAL: CONSULTORIA DE INFRAESTRUTURA

**Projeto:** Implementação de Ambiente Escalável com Docker e Alta Disponibilidade PostgreSQL

---

## 1. Escopo do Projeto

O projeto consiste no desenho, implementação e configuração de uma infraestrutura robusta, garantindo isolamento entre a camada de aplicação e a camada de dados através de **03 (três) máquinas virtuais**.

### 1.1. Arquitetura de Servidores (VMs)

- **VM 01 (Aplicação):** Servidor dedicado para execução de serviços conteinerizados via Docker.
- **VM 02 (PostgreSQL Master):** Instância principal para escrita e leitura.
- **VM 03 (PostgreSQL Slave):** Instância de réplica para redundância e segurança.

### 1.2. Detalhamento Técnico

- **Ambiente Docker:** Instalação e atualização de pacotes e setup do motor Docker na VM de aplicação.
- **Camada de Dados:** Configuração de cluster PostgreSQL (Master/Slave) e implementação do PgBouncer para otimização de conexões.
- **Continuidade e Backup:** Script automatizado para backup e exportação segura para Buckets S3.
- **Otimização:** Tuning de performance das máquinas e configuração rigorosa de Firewall.
- **Base de Conhecimento:** Documentação técnica da arquitetura e procedimentos de operação.

---

## 2. Cronograma de Execução

| Fase | Descrição | Prazo |
|------|-----------|-------|
| **Fase 1: Setup** | Provisionamento das 3 VMs, instalação de pacotes, configuração do Docker, setup do Cluster PostgreSQL (Master/Slave) e scripts de backup S3. | Semana 1 |
| **Fase 2: Validação** | Execução de testes de stress, segurança e simulação de falhas em conjunto com o cliente, seguidos da entrega da documentação e handover. | Semana 2 |

---

## 3. Investimento

### 3.1. Implementação (Setup Inicial)

- **Esforço total:** 20 horas técnicas
- **Valor da hora:** R$ 250,00
- **Total do Projeto:** **R$ 5.000,00**

### 3.2. Suporte Mensal (Opcional)

- **Pacote de Horas:** 05 horas mensais para suporte e dúvidas
- **Valor Mensal:** **R$ 1.000,00**
- **Nota:** Valor fixo mensal (modalidade retainer), garantindo prioridade de atendimento.
