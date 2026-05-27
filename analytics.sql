-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: queries/analytics.sql
-- Objetivo: consultas avancadas para demonstrar SQL analitico
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;
SET app.current_tenant_id = '11111111-1111-1111-1111-111111111111';

-- 1) INNER JOIN: receita por categoria e seller.
SELECT
    c.category_name,
    s.seller_name,
    count(DISTINCT o.order_id) AS orders,
    sum(oi.quantity) AS units_sold,
    round(sum(oi.line_total_amount), 2) AS net_revenue
FROM sales.orders o
INNER JOIN sales.order_items oi
    ON oi.order_id = o.order_id
INNER JOIN catalog.products p
    ON p.product_id = oi.product_id
INNER JOIN catalog.categories c
    ON c.category_id = p.category_id
INNER JOIN core.sellers s
    ON s.seller_id = oi.seller_id
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
GROUP BY c.category_name, s.seller_name
ORDER BY net_revenue DESC;

-- 2) LEFT JOIN: clientes sem compra nos ultimos 90 dias.
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.email,
    max(o.order_date)::date AS last_order_date,
    current_date - max(o.order_date)::date AS days_since_last_order
FROM core.customers c
LEFT JOIN sales.orders o
    ON o.customer_id = c.customer_id
   AND o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
WHERE c.status = 'active'
  AND c.deleted_at IS NULL
GROUP BY c.customer_id, c.first_name, c.last_name, c.email
HAVING max(o.order_date) IS NULL
    OR max(o.order_date)::date < current_date - INTERVAL '90 days'
ORDER BY days_since_last_order DESC NULLS FIRST;

-- 3) RIGHT JOIN: sellers mesmo quando nao possuem produtos ativos.
SELECT
    s.seller_id,
    s.seller_name,
    count(p.product_id) AS active_products
FROM catalog.products p
RIGHT JOIN core.sellers s
    ON s.seller_id = p.seller_id
   AND p.status = 'active'
   AND p.deleted_at IS NULL
GROUP BY s.seller_id, s.seller_name
ORDER BY active_products ASC, s.seller_name;

-- 4) FULL JOIN: conciliacao entre catalogo e estoque.
WITH product_stock AS (
    SELECT product_id, sum(quantity_on_hand - quantity_reserved) AS available_stock
    FROM fulfillment.inventory
    GROUP BY product_id
)
SELECT
    coalesce(p.product_id, ps.product_id) AS product_id,
    p.sku,
    p.product_name,
    coalesce(ps.available_stock, 0) AS available_stock,
    CASE
        WHEN p.product_id IS NULL THEN 'stock_without_catalog'
        WHEN ps.product_id IS NULL THEN 'catalog_without_stock'
        WHEN ps.available_stock <= 0 THEN 'stockout'
        ELSE 'ok'
    END AS reconciliation_status
FROM catalog.products p
FULL JOIN product_stock ps
    ON ps.product_id = p.product_id
ORDER BY reconciliation_status, product_id;

-- 5) CROSS JOIN: matriz de meses x segmentos para dashboards com meses sem venda.
WITH months AS (
    SELECT generate_series(date '2025-01-01', date '2026-05-01', interval '1 month')::date AS month_start
),
segments AS (
    SELECT DISTINCT seller_segment FROM core.sellers
),
sales_by_segment AS (
    SELECT
        date_trunc('month', o.order_date)::date AS month_start,
        s.seller_segment,
        sum(oi.line_total_amount) AS revenue
    FROM sales.orders o
    JOIN sales.order_items oi ON oi.order_id = o.order_id
    JOIN core.sellers s ON s.seller_id = oi.seller_id
    WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY date_trunc('month', o.order_date)::date, s.seller_segment
)
SELECT
    m.month_start,
    sg.seller_segment,
    coalesce(sbs.revenue, 0) AS revenue
FROM months m
CROSS JOIN segments sg
LEFT JOIN sales_by_segment sbs
    ON sbs.month_start = m.month_start
   AND sbs.seller_segment = sg.seller_segment
ORDER BY m.month_start, sg.seller_segment;

-- 6) SELF JOIN: hierarquia de categorias pai/filha.
SELECT
    parent.category_name AS parent_category,
    child.category_name AS child_category,
    child.slug
FROM catalog.categories child
LEFT JOIN catalog.categories parent
    ON parent.category_id = child.parent_category_id
ORDER BY parent.category_name NULLS FIRST, child.category_name;

-- 7) UNION: base unica de contatos comerciais sem duplicidade semantica.
SELECT 'customer' AS contact_type, email, first_name || ' ' || last_name AS contact_name
FROM core.customers
WHERE marketing_opt_in = true
UNION
SELECT 'seller' AS contact_type, contact_email AS email, seller_name AS contact_name
FROM core.sellers
WHERE status = 'active'
ORDER BY contact_type, contact_name;

-- 8) UNION ALL: funil operacional preservando volumes por origem.
SELECT 'orders' AS source_table, order_status AS status_name, count(*) AS records
FROM sales.orders
GROUP BY order_status
UNION ALL
SELECT 'payments' AS source_table, payment_status AS status_name, count(*) AS records
FROM sales.payments
GROUP BY payment_status
UNION ALL
SELECT 'returns' AS source_table, return_status AS status_name, count(*) AS records
FROM sales.returns
GROUP BY return_status
ORDER BY source_table, status_name;

-- 9) EXISTS / NOT EXISTS: produtos vendidos e produtos sem venda.
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM sales.order_items oi WHERE oi.product_id = p.product_id
        ) THEN 'sold'
        ELSE 'never_sold'
    END AS sales_status
FROM catalog.products p
WHERE NOT EXISTS (
    SELECT 1
    FROM sales.returns r
    JOIN sales.order_items oi ON oi.order_item_id = r.order_item_id
    WHERE oi.product_id = p.product_id
      AND r.return_status = 'refunded'
)
ORDER BY sales_status, p.product_id;

-- 10) Subquery: pedidos acima do ticket medio do proprio canal.
SELECT
    o.order_id,
    o.order_number,
    o.sales_channel,
    o.total_amount,
    (
        SELECT round(avg(o2.total_amount), 2)
        FROM sales.orders o2
        WHERE o2.sales_channel = o.sales_channel
          AND o2.order_status IN ('paid', 'picking', 'shipped', 'delivered')
    ) AS channel_avg_ticket
FROM sales.orders o
WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
  AND o.total_amount > (
        SELECT avg(o2.total_amount)
        FROM sales.orders o2
        WHERE o2.sales_channel = o.sales_channel
          AND o2.order_status IN ('paid', 'picking', 'shipped', 'delivered')
  )
ORDER BY o.total_amount DESC;

-- 11) CTE + LAG: crescimento mensal de receita.
WITH monthly_revenue AS (
    SELECT
        date_trunc('month', order_date)::date AS month_start,
        sum(total_amount) AS revenue,
        count(*) AS orders
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY date_trunc('month', order_date)::date
),
monthly_growth AS (
    SELECT
        month_start,
        revenue,
        orders,
        lag(revenue) OVER (ORDER BY month_start) AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    month_start,
    revenue,
    orders,
    previous_month_revenue,
    round((revenue - previous_month_revenue) / nullif(previous_month_revenue, 0) * 100, 2) AS revenue_growth_percent
FROM monthly_growth
ORDER BY month_start;

-- 12) Recursive CTE: arvore de categorias com caminho completo.
WITH RECURSIVE category_tree AS (
    SELECT
        category_id,
        parent_category_id,
        category_name,
        category_name::text AS full_path,
        1 AS depth
    FROM catalog.categories
    WHERE parent_category_id IS NULL

    UNION ALL

    SELECT
        child.category_id,
        child.parent_category_id,
        child.category_name,
        category_tree.full_path || ' > ' || child.category_name AS full_path,
        category_tree.depth + 1
    FROM catalog.categories child
    JOIN category_tree
        ON category_tree.category_id = child.parent_category_id
)
SELECT *
FROM category_tree
ORDER BY full_path;

-- 13) Window functions: ranking de sellers por GMV e participacao percentual.
WITH seller_revenue AS (
    SELECT
        s.seller_id,
        s.seller_name,
        s.seller_segment,
        sum(oi.gross_amount) AS gmv
    FROM core.sellers s
    JOIN sales.order_items oi ON oi.seller_id = s.seller_id
    JOIN sales.orders o ON o.order_id = oi.order_id
    WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY s.seller_id, s.seller_name, s.seller_segment
)
SELECT
    seller_id,
    seller_name,
    seller_segment,
    gmv,
    dense_rank() OVER (ORDER BY gmv DESC) AS gmv_rank,
    round(gmv / sum(gmv) OVER () * 100, 2) AS gmv_share_percent
FROM seller_revenue
ORDER BY gmv_rank;

-- 14) Running total: receita acumulada diaria.
WITH daily AS (
    SELECT
        order_date::date AS order_day,
        sum(total_amount) AS daily_revenue
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY order_date::date
)
SELECT
    order_day,
    daily_revenue,
    sum(daily_revenue) OVER (ORDER BY order_day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue
FROM daily
ORDER BY order_day;

-- 15) Analise de coorte: retencao mensal por mes da primeira compra.
WITH customer_orders AS (
    SELECT
        customer_id,
        date_trunc('month', order_date)::date AS order_month
    FROM sales.orders
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY customer_id, date_trunc('month', order_date)::date
),
cohorts AS (
    SELECT
        customer_id,
        min(order_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_id
),
retention AS (
    SELECT
        c.cohort_month,
        co.order_month,
        (
            extract(year FROM age(co.order_month, c.cohort_month)) * 12
            + extract(month FROM age(co.order_month, c.cohort_month))
        )::integer AS month_number,
        count(DISTINCT co.customer_id) AS retained_customers
    FROM cohorts c
    JOIN customer_orders co
        ON co.customer_id = c.customer_id
    GROUP BY c.cohort_month, co.order_month
)
SELECT
    cohort_month,
    month_number,
    retained_customers,
    round(retained_customers::numeric / first_value(retained_customers) OVER (
        PARTITION BY cohort_month
        ORDER BY month_number
    ) * 100, 2) AS retention_percent
FROM retention
ORDER BY cohort_month, month_number;

-- 16) Curva ABC / Pareto de produtos.
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.sku,
        p.product_name,
        sum(oi.line_total_amount) AS revenue
    FROM catalog.products p
    JOIN sales.order_items oi ON oi.product_id = p.product_id
    JOIN sales.orders o ON o.order_id = oi.order_id
    WHERE o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY p.product_id, p.sku, p.product_name
),
abc AS (
    SELECT
        *,
        sum(revenue) OVER (ORDER BY revenue DESC) / sum(revenue) OVER () AS cumulative_share
    FROM product_revenue
)
SELECT
    product_id,
    sku,
    product_name,
    revenue,
    round(cumulative_share * 100, 2) AS cumulative_share_percent,
    CASE
        WHEN cumulative_share <= 0.80 THEN 'A'
        WHEN cumulative_share <= 0.95 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM abc
ORDER BY revenue DESC;

-- 17) RFM: segmentacao de clientes por recencia, frequencia e valor monetario.
WITH rfm_base AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name AS customer_name,
        current_date - max(o.order_date)::date AS recency_days,
        count(o.order_id) AS frequency,
        sum(o.total_amount) AS monetary_value
    FROM core.customers c
    JOIN sales.orders o
        ON o.customer_id = c.customer_id
       AND o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
    GROUP BY c.customer_id, c.first_name, c.last_name
),
rfm_scored AS (
    SELECT
        *,
        ntile(5) OVER (ORDER BY recency_days DESC) AS recency_score,
        ntile(5) OVER (ORDER BY frequency ASC) AS frequency_score,
        ntile(5) OVER (ORDER BY monetary_value ASC) AS monetary_score
    FROM rfm_base
)
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    monetary_value,
    recency_score,
    frequency_score,
    monetary_score,
    CASE
        WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'champions'
        WHEN recency_score <= 2 AND frequency_score >= 4 THEN 'at_risk_high_value'
        WHEN recency_score >= 4 AND frequency_score <= 2 THEN 'new_or_promising'
        ELSE 'regular'
    END AS rfm_segment
FROM rfm_scored
ORDER BY monetary_value DESC;
