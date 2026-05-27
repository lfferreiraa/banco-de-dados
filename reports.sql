-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: queries/reports.sql
-- Objetivo: relatorios gerenciais e KPIs para dashboard executivo
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;
SET app.current_tenant_id = '11111111-1111-1111-1111-111111111111';

-- 1) Faturamento mensal, pedidos, unidades e ticket medio.
WITH monthly_orders AS (
    SELECT
        date_trunc('month', order_date)::date AS month_start,
        count(*) AS orders,
        count(DISTINCT customer_id) AS buying_customers,
        sum(total_amount) AS revenue,
        avg(total_amount) AS avg_ticket
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY date_trunc('month', order_date)::date
),
monthly_items AS (
    SELECT
        date_trunc('month', o.order_date)::date AS month_start,
        sum(oi.quantity) AS units_sold
    FROM sales.orders o
    JOIN sales.order_items oi
      ON oi.order_id = o.order_id
    WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY date_trunc('month', o.order_date)::date
)
SELECT
    mo.month_start,
    mo.orders,
    mo.buying_customers,
    mi.units_sold,
    round(mo.revenue, 2) AS revenue,
    round(mo.avg_ticket, 2) AS avg_ticket
FROM monthly_orders mo
JOIN monthly_items mi
  ON mi.month_start = mo.month_start
ORDER BY mo.month_start;

-- 2) Produtos mais vendidos por receita e volume.
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    c.category_name,
    sum(oi.quantity) AS units_sold,
    round(sum(oi.line_total_amount), 2) AS revenue,
    round(sum(oi.line_total_amount - oi.commission_amount - oi.unit_cost * oi.quantity), 2) AS contribution_margin
FROM sales.order_items oi
JOIN sales.orders o ON o.order_id = oi.order_id
JOIN catalog.products p ON p.product_id = oi.product_id
JOIN catalog.categories c ON c.category_id = p.category_id
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY p.product_id, p.sku, p.product_name, c.category_name
ORDER BY revenue DESC
LIMIT 20;

-- 3) Clientes mais ativos por pedidos, receita e recorrencia.
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email,
    count(o.order_id) AS paid_orders,
    round(sum(o.total_amount), 2) AS lifetime_value,
    round(avg(o.total_amount), 2) AS avg_ticket,
    min(o.order_date)::date AS first_order_date,
    max(o.order_date)::date AS last_order_date
FROM core.customers c
JOIN sales.orders o
  ON o.customer_id = c.customer_id
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY c.customer_id, c.first_name, c.last_name, c.email
ORDER BY lifetime_value DESC
LIMIT 25;

-- 4) Ticket medio por canal e metodo de pagamento.
SELECT
    o.sales_channel,
    p.payment_method,
    count(DISTINCT o.order_id) AS orders,
    round(avg(o.total_amount), 2) AS avg_ticket,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY o.total_amount) AS median_ticket,
    round(sum(o.total_amount), 2) AS revenue
FROM sales.orders o
JOIN sales.payments p
  ON p.order_id = o.order_id
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
  AND p.payment_status IN ('paid', 'refunded')
GROUP BY o.sales_channel, p.payment_method
ORDER BY revenue DESC;

-- 5) Crescimento mensal de receita e pedidos.
WITH monthly AS (
    SELECT
        date_trunc('month', order_date)::date AS month_start,
        sum(total_amount) AS revenue,
        count(*) AS orders
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY date_trunc('month', order_date)::date
)
SELECT
    month_start,
    revenue,
    orders,
    round((revenue - lag(revenue) OVER (ORDER BY month_start)) / nullif(lag(revenue) OVER (ORDER BY month_start), 0) * 100, 2) AS revenue_growth_percent,
    round((orders - lag(orders) OVER (ORDER BY month_start))::numeric / nullif(lag(orders) OVER (ORDER BY month_start), 0) * 100, 2) AS order_growth_percent
FROM monthly
ORDER BY month_start;

-- 6) Ranking de vendedores por GMV, comissao e margem.
SELECT
    dense_rank() OVER (ORDER BY sum(oi.gross_amount) DESC) AS seller_rank,
    s.seller_id,
    s.seller_name,
    s.seller_segment,
    s.quality_score,
    count(DISTINCT o.order_id) AS orders,
    round(sum(oi.gross_amount), 2) AS gmv,
    round(sum(oi.commission_amount), 2) AS marketplace_commission,
    round(sum(oi.line_total_amount - oi.commission_amount - oi.unit_cost * oi.quantity), 2) AS contribution_margin
FROM core.sellers s
JOIN sales.order_items oi ON oi.seller_id = s.seller_id
JOIN sales.orders o ON o.order_id = oi.order_id
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY s.seller_id, s.seller_name, s.seller_segment, s.quality_score
ORDER BY seller_rank;

-- 7) Analise de churn: clientes ativos, em risco e churned.
SELECT
    lifecycle_stage,
    count(*) AS customers,
    round(count(*)::numeric / sum(count(*)) OVER () * 100, 2) AS customer_share_percent,
    round(sum(lifetime_value), 2) AS ltv_sum
FROM sales.v_customer_ltv
GROUP BY lifecycle_stage
ORDER BY customers DESC;

-- 8) Retencao por coorte mensal em formato tabular.
WITH customer_month AS (
    SELECT
        customer_id,
        date_trunc('month', order_date)::date AS order_month
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY customer_id, date_trunc('month', order_date)::date
),
cohort AS (
    SELECT customer_id, min(order_month) AS cohort_month
    FROM customer_month
    GROUP BY customer_id
),
retention AS (
    SELECT
        c.cohort_month,
        (
            extract(year FROM age(cm.order_month, c.cohort_month)) * 12
            + extract(month FROM age(cm.order_month, c.cohort_month))
        )::integer AS month_n,
        count(DISTINCT cm.customer_id) AS customers
    FROM cohort c
    JOIN customer_month cm ON cm.customer_id = c.customer_id
    GROUP BY c.cohort_month, month_n
)
SELECT
    cohort_month,
    max(customers) FILTER (WHERE month_n = 0) AS m0,
    max(customers) FILTER (WHERE month_n = 1) AS m1,
    max(customers) FILTER (WHERE month_n = 2) AS m2,
    max(customers) FILTER (WHERE month_n = 3) AS m3,
    max(customers) FILTER (WHERE month_n = 4) AS m4,
    max(customers) FILTER (WHERE month_n = 5) AS m5
FROM retention
GROUP BY cohort_month
ORDER BY cohort_month;

-- 9) KPIs executivos para cards de dashboard.
WITH paid_orders AS (
    SELECT *
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
),
returns AS (
    SELECT count(*) AS return_count, coalesce(sum(refund_amount), 0) AS refund_amount
    FROM sales.returns
    WHERE return_status IN ('approved', 'received', 'refunded')
)
SELECT
    count(DISTINCT po.order_id) AS total_orders,
    count(DISTINCT po.customer_id) AS active_buyers,
    round(sum(po.total_amount), 2) AS total_revenue,
    round(avg(po.total_amount), 2) AS avg_ticket,
    round(sum(po.commission_amount), 2) AS marketplace_take_rate_amount,
    round(sum(po.commission_amount) / nullif(sum(po.subtotal_amount), 0) * 100, 2) AS take_rate_percent,
    r.return_count,
    r.refund_amount,
    round(r.return_count::numeric / nullif(count(DISTINCT po.order_id), 0) * 100, 2) AS return_rate_percent
FROM paid_orders po
CROSS JOIN returns r
GROUP BY r.return_count, r.refund_amount;

-- 10) Dashboard SQL: vendas diarias recentes com media movel de 7 dias.
WITH daily AS (
    SELECT
        order_date::date AS order_day,
        count(*) AS orders,
        sum(total_amount) AS revenue
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY order_date::date
)
SELECT
    order_day,
    orders,
    revenue,
    round(avg(revenue) OVER (
        ORDER BY order_day
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS revenue_7d_moving_avg
FROM daily
ORDER BY order_day DESC
LIMIT 60;

-- 11) Relatorio de estoque critico para compras/reposicao.
SELECT
    warehouse_code,
    warehouse_name,
    sku,
    product_name,
    available_quantity,
    safety_stock,
    stock_status
FROM fulfillment.v_inventory_position
WHERE stock_status IN ('stockout', 'reorder')
ORDER BY stock_status, available_quantity ASC;

-- 12) Performance: plano de execucao esperado para relatorio mensal.
-- O indice idx_orders_tenant_date_status deve ser considerado pelo otimizador.
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
