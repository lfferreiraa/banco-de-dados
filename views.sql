-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: database/views.sql
-- Objetivo: views operacionais, gerenciais e analiticas
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;

-- Catalogo pronto para API/listagem de produto.
CREATE OR REPLACE VIEW catalog.v_product_catalog AS
SELECT
    p.tenant_id,
    p.product_id,
    p.sku,
    p.product_name,
    p.brand,
    p.condition_type,
    p.status,
    c.category_id,
    c.category_name,
    s.seller_id,
    s.seller_name,
    ph.price,
    ph.cost_amount,
    ph.margin_percent,
    fulfillment.fn_available_stock(p.product_id) AS available_stock,
    p.created_at,
    p.updated_at
FROM catalog.products p
JOIN catalog.categories c
  ON c.category_id = p.category_id
JOIN core.sellers s
  ON s.seller_id = p.seller_id
LEFT JOIN catalog.product_price_history ph
  ON ph.product_id = p.product_id
 AND ph.is_current = true
WHERE p.deleted_at IS NULL;

-- Posicao de estoque por armazem, incluindo alerta de ruptura.
CREATE OR REPLACE VIEW fulfillment.v_inventory_position AS
SELECT
    i.tenant_id,
    w.warehouse_code,
    w.warehouse_name,
    w.city,
    w.state_code,
    p.product_id,
    p.sku,
    p.product_name,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.quantity_on_hand - i.quantity_reserved AS available_quantity,
    i.safety_stock,
    CASE
        WHEN i.quantity_on_hand - i.quantity_reserved <= 0 THEN 'stockout'
        WHEN i.quantity_on_hand - i.quantity_reserved <= i.safety_stock THEN 'reorder'
        ELSE 'healthy'
    END AS stock_status,
    i.updated_at
FROM fulfillment.inventory i
JOIN fulfillment.warehouses w
  ON w.warehouse_id = i.warehouse_id
JOIN catalog.products p
  ON p.product_id = i.product_id;

-- Visao de pedido com dados de cliente e pagamento.
CREATE OR REPLACE VIEW sales.v_order_summary AS
WITH item_agg AS (
    SELECT
        order_id,
        count(*) AS item_count,
        sum(quantity) AS total_quantity
    FROM sales.order_items
    GROUP BY order_id
),
payment_agg AS (
    SELECT
        order_id,
        max(payment_method) AS payment_method,
        max(payment_status) AS payment_status,
        max(paid_at) AS paid_at
    FROM sales.payments
    GROUP BY order_id
)
SELECT
    o.tenant_id,
    o.order_id,
    o.order_number,
    o.order_date,
    o.order_status,
    o.sales_channel,
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email AS customer_email,
    coalesce(ia.item_count, 0) AS item_count,
    coalesce(ia.total_quantity, 0) AS total_quantity,
    o.subtotal_amount,
    o.discount_amount,
    o.freight_amount,
    o.tax_amount,
    o.commission_amount,
    o.total_amount,
    pa.payment_method,
    pa.payment_status,
    pa.paid_at
FROM sales.orders o
JOIN core.customers c
  ON c.customer_id = o.customer_id
LEFT JOIN item_agg ia
  ON ia.order_id = o.order_id
LEFT JOIN payment_agg pa
  ON pa.order_id = o.order_id
WHERE o.deleted_at IS NULL;

-- LTV, recencia, frequencia e ticket medio por cliente.
CREATE OR REPLACE VIEW sales.v_customer_ltv AS
SELECT
    c.tenant_id,
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email,
    c.acquisition_channel,
    min(o.order_date)::date AS first_order_date,
    max(o.order_date)::date AS last_order_date,
    count(o.order_id) FILTER (WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')) AS paid_orders,
    coalesce(sum(o.total_amount) FILTER (WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')), 0) AS lifetime_value,
    coalesce(avg(o.total_amount) FILTER (WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')), 0) AS avg_ticket,
    current_date - max(o.order_date)::date AS days_since_last_order,
    CASE
        WHEN max(o.order_date)::date >= current_date - INTERVAL '30 days' THEN 'active'
        WHEN max(o.order_date)::date >= current_date - INTERVAL '90 days' THEN 'at_risk'
        WHEN max(o.order_date)::date IS NULL THEN 'never_purchased'
        ELSE 'churned'
    END AS lifecycle_stage
FROM core.customers c
LEFT JOIN sales.orders o
  ON o.customer_id = c.customer_id
 AND o.deleted_at IS NULL
WHERE c.deleted_at IS NULL
GROUP BY
    c.tenant_id,
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.acquisition_channel;

-- Performance financeira por seller.
CREATE OR REPLACE VIEW finance.v_seller_financials AS
SELECT
    s.tenant_id,
    s.seller_id,
    s.seller_name,
    s.seller_segment,
    s.quality_score,
    count(DISTINCT o.order_id) AS paid_orders,
    coalesce(sum(oi.gross_amount) FILTER (WHERE o.order_id IS NOT NULL), 0) AS gross_merchandise_value,
    coalesce(sum(oi.commission_amount) FILTER (WHERE o.order_id IS NOT NULL), 0) AS marketplace_commission,
    coalesce(sum(oi.line_total_amount - oi.commission_amount - (oi.unit_cost * oi.quantity)) FILTER (WHERE o.order_id IS NOT NULL), 0) AS contribution_margin,
    coalesce(avg(oi.commission_rate) FILTER (WHERE o.order_id IS NOT NULL), s.commission_rate) AS avg_commission_rate,
    coalesce(sum(r.refund_amount), 0) AS refund_amount
FROM core.sellers s
LEFT JOIN sales.order_items oi
  ON oi.seller_id = s.seller_id
LEFT JOIN sales.orders o
  ON o.order_id = oi.order_id
 AND o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
 AND o.deleted_at IS NULL
LEFT JOIN sales.returns r
  ON r.order_item_id = oi.order_item_id
 AND r.return_status IN ('approved', 'received', 'refunded')
WHERE s.deleted_at IS NULL
GROUP BY
    s.tenant_id,
    s.seller_id,
    s.seller_name,
    s.seller_segment,
    s.quality_score,
    s.commission_rate;

-- KPIs diarios a partir da fato do DW.
CREATE OR REPLACE VIEW dw.v_daily_kpis AS
SELECT
    f.tenant_id,
    d.full_date,
    count(DISTINCT f.order_id) AS orders,
    count(DISTINCT f.customer_key) AS buying_customers,
    sum(f.quantity) AS units_sold,
    sum(f.gross_revenue) AS gross_revenue,
    sum(f.discount_amount) AS discount_amount,
    sum(f.net_revenue) AS net_revenue,
    sum(f.commission_amount) AS commission_amount,
    sum(f.contribution_margin) AS contribution_margin,
    round(sum(f.net_revenue) / nullif(count(DISTINCT f.order_id), 0), 2) AS avg_ticket
FROM dw.fact_order_items f
JOIN dw.dim_date d
  ON d.date_key = f.date_key
GROUP BY f.tenant_id, d.full_date;

-- Ultimas alteracoes auditadas para analise de compliance.
CREATE OR REPLACE VIEW audit.v_latest_changes AS
SELECT
    changed_at,
    schema_name,
    table_name,
    operation,
    record_pk,
    changed_by,
    old_data,
    new_data
FROM audit.audit_log
ORDER BY changed_at DESC;

-- Materialized view para dashboard mensal de sellers.
DROP MATERIALIZED VIEW IF EXISTS dw.mv_monthly_seller_performance;
CREATE MATERIALIZED VIEW dw.mv_monthly_seller_performance AS
SELECT
    f.tenant_id,
    date_trunc('month', d.full_date)::date AS month_start,
    ds.seller_id,
    ds.seller_name,
    ds.seller_segment,
    count(DISTINCT f.order_id) AS orders,
    sum(f.quantity) AS units_sold,
    sum(f.net_revenue) AS net_revenue,
    sum(f.commission_amount) AS commission_amount,
    sum(f.contribution_margin) AS contribution_margin,
    round(sum(f.net_revenue) / nullif(count(DISTINCT f.order_id), 0), 2) AS avg_ticket
FROM dw.fact_order_items f
JOIN dw.dim_date d
  ON d.date_key = f.date_key
JOIN dw.dim_seller ds
  ON ds.seller_key = f.seller_key
GROUP BY
    f.tenant_id,
    date_trunc('month', d.full_date)::date,
    ds.seller_id,
    ds.seller_name,
    ds.seller_segment
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_monthly_seller_performance
    ON dw.mv_monthly_seller_performance (tenant_id, month_start, seller_id);
