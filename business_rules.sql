-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: queries/business_rules.sql
-- Objetivo: validacoes, regras de negocio e exemplos transacionais
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;
SET app.current_tenant_id = '11111111-1111-1111-1111-111111111111';

-- ================================================================
-- 1) Checkout transacional com ACID
-- ================================================================
-- A procedure usa SELECT FOR UPDATE no estoque, valida tenant/cliente/produto,
-- cria pedido, itens, baixa estoque, pagamento e historico de status.

BEGIN;

CALL sales.sp_place_order(
    '11111111-1111-1111-1111-111111111111',
    1,
    jsonb_build_array(
        jsonb_build_object('product_id', 10, 'quantity', 2),
        jsonb_build_object('product_id', 25, 'quantity', 1)
    ),
    'pix',
    'web',
    'PORTFOLIO10',
    NULL,
    NULL
);

-- Em uma execucao real, revisar o pedido retornado antes de confirmar.
COMMIT;

-- ================================================================
-- 2) Soft delete: inativacao logica sem perder historico
-- ================================================================

UPDATE catalog.products
   SET status = 'archived',
       deleted_at = now()
 WHERE product_id = 220
   AND deleted_at IS NULL;

SELECT *
FROM audit.v_latest_changes
WHERE table_name = 'products'
  AND record_pk = '220'
LIMIT 5;

-- ================================================================
-- 3) Regra de integridade: item do pedido deve pertencer ao seller correto
-- ================================================================
-- Esta consulta identifica inconsistencias caso dados sejam importados sem usar triggers.

SELECT
    oi.order_item_id,
    oi.product_id,
    oi.seller_id AS seller_on_order_item,
    p.seller_id AS seller_on_product
FROM sales.order_items oi
JOIN catalog.products p
  ON p.product_id = oi.product_id
WHERE oi.seller_id <> p.seller_id;

-- ================================================================
-- 4) Conciliacao financeira: pedido x pagamento
-- ================================================================

SELECT
    o.order_id,
    o.order_number,
    o.order_status,
    o.total_amount AS order_total,
    coalesce(sum(p.amount), 0) AS paid_amount,
    round(o.total_amount - coalesce(sum(p.amount), 0), 2) AS difference_amount
FROM sales.orders o
LEFT JOIN sales.payments p
  ON p.order_id = o.order_id
 AND p.payment_status IN ('paid', 'refunded')
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered', 'refunded')
GROUP BY o.order_id, o.order_number, o.order_status, o.total_amount
HAVING abs(o.total_amount - coalesce(sum(p.amount), 0)) > 0.01
ORDER BY difference_amount DESC;

-- ================================================================
-- 5) Politica antifraude simplificada
-- ================================================================
-- Clientes com muitos pedidos de alto valor em uma janela curta.

WITH high_value_orders AS (
    SELECT
        customer_id,
        order_id,
        order_date,
        total_amount
    FROM sales.orders
    WHERE total_amount >= 1200
      AND order_status IN ('paid', 'picking', 'shipped', 'delivered')
),
rolling_window AS (
    SELECT
        h1.customer_id,
        h1.order_id,
        h1.order_date,
        count(h2.order_id) AS high_value_orders_24h,
        sum(h2.total_amount) AS amount_24h
    FROM high_value_orders h1
    JOIN high_value_orders h2
      ON h2.customer_id = h1.customer_id
     AND h2.order_date BETWEEN h1.order_date - INTERVAL '24 hours' AND h1.order_date
    GROUP BY h1.customer_id, h1.order_id, h1.order_date
)
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    rw.order_id,
    rw.order_date,
    rw.high_value_orders_24h,
    rw.amount_24h,
    CASE
        WHEN rw.high_value_orders_24h >= 3 OR rw.amount_24h >= 5000 THEN 'manual_review'
        ELSE 'monitor'
    END AS recommended_action
FROM rolling_window rw
JOIN core.customers c
  ON c.customer_id = rw.customer_id
WHERE rw.high_value_orders_24h >= 2
ORDER BY rw.amount_24h DESC;

-- ================================================================
-- 6) SLA logistico: pedidos enviados ou entregues fora do prazo
-- ================================================================

SELECT
    order_id,
    order_number,
    order_status,
    order_date,
    shipped_at,
    delivered_at,
    CASE
        WHEN shipped_at IS NULL AND order_status IN ('paid', 'picking') AND now() > order_date + INTERVAL '2 days' THEN 'shipping_delay'
        WHEN delivered_at IS NULL AND order_status = 'shipped' AND now() > shipped_at + INTERVAL '7 days' THEN 'delivery_delay'
        WHEN delivered_at > order_date + INTERVAL '10 days' THEN 'delivered_late'
        ELSE 'on_time'
    END AS sla_status
FROM sales.orders
WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
  AND (
      shipped_at IS NULL
      OR delivered_at IS NULL
      OR delivered_at > order_date + INTERVAL '10 days'
  )
ORDER BY order_date;

-- ================================================================
-- 7) Reabastecimento: produtos abaixo do estoque de seguranca
-- ================================================================

SELECT
    p.product_id,
    p.sku,
    p.product_name,
    w.warehouse_code,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.quantity_on_hand - i.quantity_reserved AS available_quantity,
    i.safety_stock,
    greatest((i.safety_stock * 2) - (i.quantity_on_hand - i.quantity_reserved), 0) AS suggested_replenishment_qty
FROM fulfillment.inventory i
JOIN catalog.products p ON p.product_id = i.product_id
JOIN fulfillment.warehouses w ON w.warehouse_id = i.warehouse_id
WHERE i.quantity_on_hand - i.quantity_reserved <= i.safety_stock
ORDER BY suggested_replenishment_qty DESC;

-- ================================================================
-- 8) Repasse aos sellers com controle de periodo
-- ================================================================

CALL finance.sp_generate_seller_payouts(
    '11111111-1111-1111-1111-111111111111',
    date '2026-01-01',
    date '2026-01-31'
);

SELECT
    s.seller_name,
    p.period_start,
    p.period_end,
    p.gross_amount,
    p.commission_amount,
    p.refund_amount,
    p.net_amount,
    p.payout_status
FROM finance.seller_payouts p
JOIN core.sellers s ON s.seller_id = p.seller_id
WHERE p.period_start = date '2026-01-01'
ORDER BY p.net_amount DESC;

-- ================================================================
-- 9) Data quality: registros suspeitos para monitoramento
-- ================================================================

SELECT 'orders_without_items' AS issue, count(*) AS records
FROM sales.orders o
WHERE NOT EXISTS (
    SELECT 1 FROM sales.order_items oi WHERE oi.order_id = o.order_id
)
UNION ALL
SELECT 'payments_without_order' AS issue, count(*) AS records
FROM sales.payments p
WHERE NOT EXISTS (
    SELECT 1 FROM sales.orders o WHERE o.order_id = p.order_id
)
UNION ALL
SELECT 'negative_available_stock' AS issue, count(*) AS records
FROM fulfillment.inventory
WHERE quantity_on_hand - quantity_reserved < 0
UNION ALL
SELECT 'products_without_current_price' AS issue, count(*) AS records
FROM catalog.products p
WHERE NOT EXISTS (
    SELECT 1
    FROM catalog.product_price_history ph
    WHERE ph.product_id = p.product_id
      AND ph.is_current = true
);

-- ================================================================
-- 10) Refresh incremental do DW
-- ================================================================

CALL dw.sp_refresh_sales_mart(date '2026-05-01', date '2026-05-31');
REFRESH MATERIALIZED VIEW dw.mv_monthly_seller_performance;

SELECT *
FROM dw.v_daily_kpis
WHERE full_date >= date '2026-05-01'
ORDER BY full_date;
