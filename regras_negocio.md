# Regras de Negocio

## Contexto

O MercadoNexa representa um marketplace multi-tenant. Um tenant opera a plataforma, sellers vendem produtos, clientes compram, o sistema controla estoque, pagamentos, devolucoes, auditoria e repasses financeiros.

## Regras de Tenant

1. Todo dado operacional pertence a um `tenant_id`.
2. A aplicacao deve definir `app.current_tenant_id` no inicio da sessao.
3. Row Level Security bloqueia acesso cruzado entre tenants.
4. Usuarios analiticos podem consultar dados conforme grants definidos em `security.sql`.

## Regras de Cliente

1. E-mail deve ser unico por tenant.
2. Documento deve ser unico por tenant.
3. Clientes bloqueados nao devem gerar novos pedidos.
4. Soft delete usa `deleted_at`, preservando historico de compras e auditoria.
5. Cliente deve ter pelo menos 16 anos quando `birth_date` for informado.

## Regras de Seller

1. Seller pertence a um unico tenant.
2. `commission_rate` deve ficar entre 3% e 35%.
3. Seller pode estar em `active`, `paused`, `under_review` ou `blocked`.
4. Produtos de sellers bloqueados ou pausados devem ser ocultados na camada de aplicacao.
5. Repasses financeiros sao calculados por seller e periodo.

## Regras de Catalogo

1. SKU deve ser unico por tenant.
2. Produto pertence a uma categoria e a um seller.
3. Categoria pode ter categoria pai, formando hierarquia.
4. Produto usa soft delete para preservar historico de vendas.
5. A tabela de preco historico permite somente um preco corrente por produto.
6. Preco de venda deve ser maior que zero.
7. Custo nao pode ser negativo nem maior que o preco.
8. Alteracoes em produto geram versao em `catalog.product_version_history`.

## Regras de Estoque

1. Estoque e controlado por produto e armazem.
2. `quantity_reserved` nao pode ser maior que `quantity_on_hand`.
3. Quantidades nao podem ser negativas.
4. Movimentacoes de estoque devem registrar tipo, quantidade e referencia.
5. Produtos abaixo do `safety_stock` entram em alerta de reposicao.
6. Checkout deve bloquear linha de estoque com `SELECT FOR UPDATE` para evitar overselling.

## Regras de Pedido

1. Pedido deve pertencer a um cliente ativo do mesmo tenant.
2. Um pedido pode ter varios itens.
3. Um item deve apontar para produto ativo e seller correto.
4. O preco e custo do item sao copiados no momento da compra para preservar historico.
5. Totais do pedido sao recalculados automaticamente por trigger.
6. Status validos:
   - `created`
   - `approved`
   - `paid`
   - `picking`
   - `shipped`
   - `delivered`
   - `cancelled`
   - `refunded`
7. Datas devem respeitar a ordem operacional:
   - `approved_at >= order_date`
   - `shipped_at` requer aprovacao
   - `delivered_at` requer envio
   - pedido cancelado nao pode estar entregue
8. Mudanca de status gera linha em `sales.order_status_history`.

## Regras de Pagamento

1. Metodos validos:
   - `credit_card`
   - `debit_card`
   - `pix`
   - `boleto`
   - `wallet`
2. Status validos:
   - `pending`
   - `authorized`
   - `paid`
   - `failed`
   - `refunded`
   - `chargeback`
3. Valor de pagamento nao pode ser negativo.
4. Parcelas devem estar entre 1 e 12.
5. `transaction_code` deve ser unico.
6. Conciliacao deve comparar soma de pagamentos com total do pedido.

## Regras de Devolucao

1. Devolucao ocorre por item do pedido.
2. Motivos validos:
   - `damaged`
   - `late_delivery`
   - `wrong_item`
   - `regret`
   - `defective`
   - `other`
3. Valor de estorno nao pode ser negativo.
4. `resolved_at` nao pode ser anterior a `requested_at`.
5. Devolucoes aprovadas ou reembolsadas impactam repasse ao seller.

## Regras Financeiras

1. Repasse e calculado por tenant, seller e periodo.
2. A chave unica evita duplicidade para o mesmo seller/periodo.
3. Formula base:

```text
net_amount = gross_amount - commission_amount - refund_amount
```

4. Repasses podem estar em:
   - `calculated`
   - `approved`
   - `paid`
   - `blocked`
5. A procedure `finance.sp_generate_seller_payouts` pode ser reexecutada para recalcular o periodo.

## Auditoria

1. Alteracoes em tabelas criticas sao gravadas em `audit.audit_log`.
2. A auditoria registra JSON antigo e novo.
3. A tabela e particionada por data.
4. Auditoria deve ser append-only na pratica operacional.
5. Usuarios comuns nao devem ter permissao de apagar logs.

## BI e Indicadores

Indicadores suportados pelo projeto:

| Indicador | Fonte principal |
| --- | --- |
| Faturamento mensal | `sales.orders`, `dw.fact_order_items` |
| Ticket medio | `sales.orders` |
| Produtos mais vendidos | `sales.order_items` |
| Clientes mais ativos | `sales.orders`, `core.customers` |
| Ranking de sellers | `sales.order_items`, `core.sellers` |
| Churn | `sales.v_customer_ltv` |
| Retencao | CTE de cohorts em `queries/reports.sql` |
| Take rate | `commission_amount / subtotal_amount` |
| Estoque critico | `fulfillment.v_inventory_position` |

## Regras de Seguranca

1. Credenciais nao devem ser versionadas.
2. Roles de negocio sao separadas:
   - `mercadonexa_readonly`
   - `mercadonexa_analyst`
   - `mercadonexa_app`
   - `mercadonexa_admin`
3. `PUBLIC` nao recebe acesso aos schemas.
4. RLS isola dados por tenant.
5. O schema `audit` deve ser restrito a aplicacao, analistas autorizados e admins.

## Regras de Performance

1. Consultas por periodo devem filtrar `tenant_id` e `order_date`.
2. Relatorios mensais devem usar indices compostos e/ou materialized views.
3. Busca de catalogo pode usar GIN/trigram.
4. Auditoria e eventos historicos devem ser particionados por data.
5. Dashboards recorrentes devem consultar `dw` ou materialized views, nao tabelas OLTP diretamente.

## Evolucoes Futuras

1. Adicionar tabela de frete e transportadoras.
2. Criar rotina incremental baseada em watermark no staging.
3. Implementar SCD tipo 2 completo para dimensoes.
4. Separar pagamentos em tentativas e capturas.
5. Adicionar antifraude com score por cliente.
6. Criar particionamento mensal em `sales.orders` para alto volume.
7. Adicionar testes SQL automatizados com pgTAP.
8. Criar pipeline dbt para camada analitica.
