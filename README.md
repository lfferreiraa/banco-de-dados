# MercadoNexa Marketplace Analytics

Projeto profissional de banco de dados SQL para portfolio, modelado em PostgreSQL como uma plataforma de marketplace multi-tenant com vendas, catalogo, sellers, estoque, pagamentos, auditoria, financeiro e data warehouse simplificado.

O objetivo e demonstrar dominio pratico de modelagem relacional, SQL avancado, performance, integridade, automacao, governanca e analise de dados em um cenario que parece empresa real.

![DER do projeto](/DER.png)

## Tema Escolhido

**Plataforma de Marketplace**.

Esse tema foi escolhido porque permite mostrar uma arquitetura mais rica que um e-commerce simples:

- multi-tenant
- sellers terceiros
- comissao e repasse financeiro
- pedidos com multiplos itens
- controle de estoque por armazem
- historico de precos
- auditoria
- soft delete
- views gerenciais
- procedures transacionais
- data warehouse simplificado
- consultas analiticas com KPIs reais

## Tecnologias

| Tecnologia | Uso |
| --- | --- |
| PostgreSQL 14+ | Banco principal |
| SQL / PLpgSQL | Queries, procedures, functions e triggers |
| JSONB | Auditoria e staging de eventos |
| Window Functions | Ranking, running totals, cohorts, RFM |
| CTE / Recursive CTE | Analises avancadas e hierarquia de categorias |
| BRIN / GIN / B-tree | Performance |
| Row Level Security | Isolamento multi-tenant |
| Materialized View | Dashboard mensal |

## Estrutura do Repositorio

```text
/database
    schema.sql
    inserts.sql
    procedures.sql
    triggers.sql
    views.sql
    indexes.sql
    security.sql

/queries
    analytics.sql
    business_rules.sql
    reports.sql

/docs
    DER.png
    DER.mmd
    arquitetura.md
    regras_negocio.md

README.md
```

## Modelo de Dados

O banco e organizado por schemas de dominio:

| Schema | Descricao |
| --- | --- |
| `core` | Tenants, clientes, enderecos e sellers |
| `catalog` | Categorias, produtos, historico de precos e versoes |
| `fulfillment` | Armazens, estoque e movimentacoes |
| `sales` | Pedidos, itens, pagamentos, status e devolucoes |
| `finance` | Repasses financeiros aos sellers |
| `audit` | Auditoria particionada por data |
| `staging` | Eventos brutos para ETL |
| `dw` | Data warehouse simplificado em estrela |

Principais entidades:

- `core.tenants`: empresas/marketplaces isolados por tenant.
- `core.customers`: clientes compradores.
- `core.sellers`: vendedores terceiros.
- `catalog.products`: catalogo de produtos dos sellers.
- `catalog.product_price_history`: historico temporal de preco e custo.
- `fulfillment.inventory`: estoque por produto e armazem.
- `sales.orders`: pedidos.
- `sales.order_items`: itens do pedido, resolvendo N:N entre pedidos e produtos.
- `sales.payments`: pagamentos e conciliacao.
- `sales.returns`: devolucoes.
- `finance.seller_payouts`: repasses financeiros.
- `audit.audit_log`: auditoria generica.
- `dw.fact_order_items`: fato analitica no grain de item de pedido.

Documentacao detalhada:

- [Arquitetura](docs/arquitetura.md)
- [Regras de negocio](docs/regras_negocio.md)
- [DER Mermaid](docs/DER.mmd)

## Como Executar

Pre-requisitos:

- PostgreSQL 14 ou superior
- `psql` disponivel no terminal

Execute os scripts nesta ordem:

```bash
psql -U postgres -f database/schema.sql
psql -U postgres -d mercadonexa_marketplace -f database/procedures.sql
psql -U postgres -d mercadonexa_marketplace -f database/triggers.sql
psql -U postgres -d mercadonexa_marketplace -f database/indexes.sql
psql -U postgres -d mercadonexa_marketplace -f database/views.sql
psql -U postgres -d mercadonexa_marketplace -f database/inserts.sql
psql -U postgres -d mercadonexa_marketplace -f database/security.sql
```

Observacoes:

- `schema.sql` cria o banco `mercadonexa_marketplace`.
- Se o banco ja existir, remova ou renomeie antes de rodar novamente.
- `inserts.sql` e uma carga de desenvolvimento e usa `TRUNCATE ... RESTART IDENTITY`.
- `security.sql` deve ser executado apos a carga inicial para evitar atrito com Row Level Security durante o seed.

## Volume de Dados Mockados

A carga cria dados coerentes e relacionamentos validos:

| Entidade | Volume aproximado |
| --- | ---: |
| Tenants | 2 |
| Sellers | 20 |
| Clientes | 120 |
| Enderecos | 120 |
| Categorias | 18 |
| Produtos | 220 |
| Posicoes de estoque | 880 |
| Pedidos | 620 |
| Itens de pedido | 1.500+ |
| Pagamentos | 620 |
| Devolucoes | 80+ |
| Eventos staging | 200 |
| Fatos DW | 1.000+ |

Os dados simulam datas entre 2025 e 2026, valores financeiros variados, status operacionais, pagamentos, devolucoes, estoque e repasses.

## Recursos SQL Demonstrados

- `INNER JOIN`, `LEFT JOIN`, `RIGHT JOIN`, `FULL JOIN`, `CROSS JOIN`, `SELF JOIN`
- `UNION` e `UNION ALL`
- `GROUP BY` e `HAVING`
- `CASE`
- `EXISTS` e `NOT EXISTS`
- Subqueries correlacionadas
- CTEs
- Recursive CTE
- Window Functions
- `DENSE_RANK`, `NTILE`, `LAG`, `FIRST_VALUE`
- Running totals
- Analise temporal
- Cohort retention
- RFM
- Curva ABC/Pareto
- KPIs executivos

## Exemplos de Queries

Relatorios principais:

```bash
psql -U postgres -d mercadonexa_marketplace -f queries/reports.sql
```

Consultas avancadas:

```bash
psql -U postgres -d mercadonexa_marketplace -f queries/analytics.sql
```

Regras de negocio e rotinas transacionais:

```bash
psql -U postgres -d mercadonexa_marketplace -f queries/business_rules.sql
```

Exemplo de faturamento mensal:

```sql
SELECT
    date_trunc('month', order_date)::date AS month_start,
    count(*) AS orders,
    round(sum(total_amount), 2) AS revenue,
    round(avg(total_amount), 2) AS avg_ticket
FROM sales.orders
WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY date_trunc('month', order_date)::date
ORDER BY month_start;
```

Exemplo de ranking de sellers:

```sql
SELECT
    dense_rank() OVER (ORDER BY sum(oi.gross_amount) DESC) AS seller_rank,
    s.seller_name,
    round(sum(oi.gross_amount), 2) AS gmv,
    round(sum(oi.commission_amount), 2) AS commission
FROM core.sellers s
JOIN sales.order_items oi ON oi.seller_id = s.seller_id
JOIN sales.orders o ON o.order_id = oi.order_id
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY s.seller_name
ORDER BY seller_rank;
```

## Relatorios Gerenciais Incluidos

O arquivo `queries/reports.sql` contem:

- faturamento mensal
- produtos mais vendidos
- clientes mais ativos
- ticket medio
- crescimento mensal
- ranking de vendedores
- churn
- retencao
- KPIs executivos
- dashboard diario com media movel
- estoque critico
- exemplo com `EXPLAIN (ANALYZE, BUFFERS)`

## Automacoes

### Procedures

| Procedure | Objetivo |
| --- | --- |
| `sales.sp_place_order` | Cria pedido transacional com validacao e baixa de estoque |
| `sales.sp_update_order_status` | Atualiza status com regras de transicao |
| `finance.sp_generate_seller_payouts` | Calcula repasses por seller e periodo |
| `dw.sp_refresh_sales_mart` | Atualiza dimensoes e fatos do DW |

### Functions

| Function | Objetivo |
| --- | --- |
| `core.fn_touch_updated_at` | Atualiza `updated_at` automaticamente |
| `audit.fn_log_row_change` | Gera auditoria generica |
| `catalog.fn_version_product` | Versiona alteracoes de produto |
| `sales.fn_recalculate_order_totals` | Recalcula totais do pedido |
| `fulfillment.fn_available_stock` | Retorna estoque disponivel |
| `sales.fn_customer_lifetime_value` | Calcula LTV do cliente |

### Triggers

- atualizacao automatica de `updated_at`
- auditoria em tabelas criticas
- versionamento de produto
- fechamento de preco corrente anterior
- validacao de seller/produto no item do pedido
- recalculo automatico de totais
- historico de status do pedido

## Performance

O projeto inclui:

- indices B-tree compostos para filtros por tenant, data e status
- indice BRIN para `sales.orders.order_date`
- indices GIN para busca textual e JSONB
- indices parciais para preco corrente, pedidos pagos e estoque critico
- materialized view para dashboard mensal
- particionamento da auditoria por data

Exemplo de analise:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    date_trunc('month', order_date)::date AS month_start,
    sum(total_amount) AS revenue
FROM sales.orders
WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
  AND order_date >= date '2026-01-01'
  AND order_date < date '2026-06-01'
  AND order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY date_trunc('month', order_date)::date;
```

## Seguranca

O arquivo `database/security.sql` implementa:

- roles por perfil
- revogacao de acesso publico
- grants por schema
- Row Level Security
- isolamento por `tenant_id`
- funcao `core.current_tenant_id()`

Exemplo:

```sql
SET app.current_tenant_id = '11111111-1111-1111-1111-111111111111';
SELECT * FROM sales.orders;
```

## Prints Simulados

### Dashboard Executivo

| KPI | Exemplo |
| --- | ---: |
| Pedidos pagos | 580+ |
| Receita total | R$ 500k+ |
| Ticket medio | R$ 800+ |
| Sellers ativos | 18 |
| Produtos no catalogo | 220 |
| Posicoes de estoque | 880 |

### Ranking de Sellers

| Rank | Seller | GMV | Comissao |
| ---: | --- | ---: | ---: |
| 1 | TechNova Store | R$ 40k+ | R$ 5k+ |
| 2 | SmartZone | R$ 38k+ | R$ 4k+ |
| 3 | Alpha Eletronicos | R$ 35k+ | R$ 4k+ |

### Estoque Critico

| Produto | CD | Status | Sugestao |
| --- | --- | --- | ---: |
| SKU-MNX-00042 | SP-GRU-01 | reorder | 48 |
| SKU-MNX-00109 | PR-CWB-01 | reorder | 31 |

## Diferenciais Tecnicos

- Projeto multi-schema, proximo de arquitetura corporativa.
- Multi-tenant com RLS.
- Soft delete.
- Auditoria particionada.
- Historico de precos.
- Versionamento de produto.
- Controle de estoque por armazem.
- Procedure de checkout com controle transacional.
- Data Warehouse simplificado.
- Staging com JSONB.
- Materialized view para dashboard.
- Consultas avancadas com analise de negocio.
- Scripts modulares e organizados para GitHub.

## Compatibilidade com MySQL e SQL Server

O projeto foi escrito para PostgreSQL. Adaptacoes:

| PostgreSQL | MySQL | SQL Server |
| --- | --- | --- |
| `generate_series` | Recursive CTE ou tabela auxiliar | Tally table/sequence |
| `JSONB` | `JSON` | JSON em `NVARCHAR` |
| `CITEXT` | collation case-insensitive | collation case-insensitive |
| Partial index | generated column + index | filtered index |
| BRIN | sem equivalente direto | columnstore/partition |
| RLS | views/procedures | Row-Level Security nativo |
| PL/pgSQL | stored routines | T-SQL |

## Possiveis Melhorias

- Criar Docker Compose com PostgreSQL e pgAdmin.
- Adicionar testes SQL com pgTAP.
- Criar pipeline dbt para camada analitica.
- Implementar SCD tipo 2 completo para dimensoes.
- Adicionar tabelas de frete, transportadora e tracking.
- Criar particionamento mensal em `sales.orders`.
- Criar CI no GitHub Actions para validar scripts SQL.
- Adicionar dashboards em Power BI, Metabase ou Superset.

## Como Publicar no GitHub

```bash
git init
git add .
git commit -m "Create professional PostgreSQL marketplace portfolio project"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/mercadonexa-marketplace-analytics.git
git push -u origin main
```

Sugestao de descricao do repositorio:

```text
Professional PostgreSQL marketplace database project with OLTP model, analytics queries, stored procedures, triggers, audit, RLS, indexing and simplified data warehouse.
```

Topicos sugeridos:

```text
postgresql, sql, database-design, data-modeling, data-engineering, business-intelligence, portfolio-project
```

## Como Colocar no Curriculo

Sugestao:

```text
Projeto de Banco de Dados PostgreSQL - Marketplace Multi-tenant
Modelei e implementei um banco relacional completo para marketplace, com normalizacao, constraints, procedures, triggers, auditoria, controle de estoque, seguranca com RLS, indices de performance, consultas analiticas avancadas e data warehouse simplificado.
```

## Como Explicar em Entrevista

Pontos fortes para mencionar:

- "Escolhi marketplace porque traz problemas reais de produto, vendas, financeiro, estoque e BI."
- "Separei o banco em schemas por dominio para aproximar de uma arquitetura corporativa."
- "Usei historico de preco porque preco atual nao pode sobrescrever o preco de uma venda passada."
- "A procedure de checkout bloqueia estoque com `SELECT FOR UPDATE`, evitando overselling."
- "A auditoria e particionada por data para manter rastreabilidade sem degradar consultas."
- "Criei uma camada DW para nao depender do OLTP em dashboards pesados."
- "Usei RLS para demonstrar isolamento multi-tenant."
- "As queries mostram cohort retention, RFM, Pareto, ranking, running totals e crescimento mensal."

## Status

Projeto pronto para portfolio e evolucao. A base foi desenhada para parecer um sistema real, com preocupacoes de integridade, performance, seguranca e analise de negocio.
