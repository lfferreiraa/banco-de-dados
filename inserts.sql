-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: database/inserts.sql
-- Objetivo: carga ficticia realista para ambiente de portfolio
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;
SET TIME ZONE 'America/Sao_Paulo';

-- Tenant principal usado nos dados mockados.
SELECT set_config('app.current_tenant_id', '11111111-1111-1111-1111-111111111111', false);

-- ATENCAO: carga de desenvolvimento. Remove dados existentes para permitir reproducibilidade.
TRUNCATE TABLE
    audit.audit_log,
    staging.raw_order_events,
    dw.fact_order_items,
    dw.dim_customer,
    dw.dim_product,
    dw.dim_seller,
    dw.dim_date,
    finance.seller_payouts,
    sales.returns,
    sales.payments,
    sales.order_status_history,
    sales.order_items,
    sales.orders,
    fulfillment.inventory_movements,
    fulfillment.inventory,
    fulfillment.warehouses,
    catalog.product_version_history,
    catalog.product_price_history,
    catalog.products,
    catalog.categories,
    core.customer_addresses,
    core.customers,
    core.sellers,
    core.tenants
RESTART IDENTITY CASCADE;

-- ================================================================
-- TENANTS
-- ================================================================

INSERT INTO core.tenants (
    tenant_id,
    tenant_name,
    legal_name,
    tax_id,
    plan_type,
    status,
    billing_email,
    created_at
)
VALUES
    (
        '11111111-1111-1111-1111-111111111111',
        'MercadoNexa',
        'MercadoNexa Tecnologia e Intermediacao S.A.',
        '47.928.110/0001-42',
        'enterprise',
        'active',
        'billing@mercadonexa.example',
        timestamp '2024-09-01 09:00:00'
    ),
    (
        '22222222-2222-2222-2222-222222222222',
        'MercadoNexa Sandbox',
        'MercadoNexa Sandbox Ltda.',
        '12.508.774/0001-99',
        'professional',
        'active',
        'financeiro@sandbox.example',
        timestamp '2025-02-10 10:00:00'
    );

-- ================================================================
-- SELLERS
-- ================================================================

INSERT INTO core.sellers (
    seller_id,
    tenant_id,
    seller_name,
    legal_name,
    tax_id,
    contact_email,
    contact_phone,
    seller_segment,
    onboarding_date,
    commission_rate,
    quality_score,
    status
)
SELECT
    g AS seller_id,
    '11111111-1111-1111-1111-111111111111'::uuid AS tenant_id,
    (ARRAY[
        'Alpha Eletronicos', 'Casa Aurora', 'Moda Vitta', 'Beleza Viva', 'Sport Prime',
        'Livro & Cia', 'Mercado Bom', 'TechNova Store', 'Lar Essencial', 'Urban Wear',
        'Fit House', 'Petra Digital', 'SmartZone', 'Decor Mais', 'Beauty Box',
        'Bike Trail', 'Office Pro', 'Gourmet Place', 'Kids Center', 'Eco Shop'
    ])[g] AS seller_name,
    (ARRAY[
        'Alpha Eletronicos Comercio Ltda.', 'Casa Aurora Utilidades Ltda.', 'Moda Vitta Confeccoes Ltda.',
        'Beleza Viva Cosmeticos Ltda.', 'Sport Prime Artigos Esportivos Ltda.', 'Livro e Cia Distribuidora Ltda.',
        'Mercado Bom Alimentos Ltda.', 'TechNova Store Ltda.', 'Lar Essencial Home Ltda.',
        'Urban Wear Industria e Comercio Ltda.', 'Fit House Equipamentos Ltda.', 'Petra Digital Ltda.',
        'SmartZone Comercio Ltda.', 'Decor Mais Interiores Ltda.', 'Beauty Box Cosmeticos Ltda.',
        'Bike Trail Mobilidade Ltda.', 'Office Pro Suprimentos Ltda.', 'Gourmet Place Alimentos Ltda.',
        'Kids Center Brinquedos Ltda.', 'Eco Shop Sustentaveis Ltda.'
    ])[g] AS legal_name,
    'CNPJ' || lpad(g::text, 14, '0') AS tax_id,
    'seller' || g || '@mercadonexa.example' AS contact_email,
    '+55 11 9' || lpad((80000000 + g * 137)::text, 8, '0') AS contact_phone,
    (ARRAY['electronics', 'home', 'fashion', 'beauty', 'sports', 'books', 'grocery', 'long_tail'])[((g - 1) % 8) + 1] AS seller_segment,
    date '2024-09-01' + (g * 11) AS onboarding_date,
    round((0.0800 + ((g % 7) * 0.0150))::numeric, 4) AS commission_rate,
    round((78 + (g % 20) + ((g % 3) * 0.35))::numeric, 2) AS quality_score,
    CASE WHEN g IN (7, 16) THEN 'under_review' ELSE 'active' END AS status
FROM generate_series(1, 20) AS g;

-- ================================================================
-- CUSTOMERS E ENDERECOS
-- ================================================================

INSERT INTO core.customers (
    customer_id,
    tenant_id,
    first_name,
    last_name,
    email,
    document_number,
    phone,
    birth_date,
    gender,
    acquisition_channel,
    status,
    marketing_opt_in,
    created_at
)
SELECT
    g AS customer_id,
    '11111111-1111-1111-1111-111111111111'::uuid AS tenant_id,
    (ARRAY[
        'Ana', 'Bruno', 'Carla', 'Diego', 'Elisa', 'Felipe', 'Gabriela', 'Henrique',
        'Isabela', 'Joao', 'Karina', 'Lucas', 'Marina', 'Nicolas', 'Olivia', 'Paulo',
        'Renata', 'Samuel', 'Tatiana', 'Vinicius'
    ])[((g - 1) % 20) + 1] AS first_name,
    (ARRAY[
        'Silva', 'Santos', 'Oliveira', 'Souza', 'Rodrigues', 'Ferreira', 'Almeida',
        'Costa', 'Gomes', 'Ribeiro', 'Martins', 'Carvalho', 'Araujo', 'Melo', 'Barbosa'
    ])[((g - 1) % 15) + 1] AS last_name,
    'cliente' || lpad(g::text, 3, '0') || '@email.example' AS email,
    'CPF' || lpad(g::text, 11, '0') AS document_number,
    '+55 11 9' || lpad((70000000 + g * 419)::text, 8, '0') AS phone,
    date '1975-01-01' + ((g * 173) % 12000) AS birth_date,
    (ARRAY['female', 'male', 'non_binary', 'not_informed'])[((g - 1) % 4) + 1] AS gender,
    (ARRAY['organic', 'paid_search', 'social', 'referral', 'affiliate', 'marketplace_app'])[((g - 1) % 6) + 1] AS acquisition_channel,
    CASE WHEN g IN (118, 119, 120) THEN 'blocked' ELSE 'active' END AS status,
    (g % 3 <> 0) AS marketing_opt_in,
    timestamp '2024-10-01 08:00:00' + (g * interval '17 hours') AS created_at
FROM generate_series(1, 120) AS g;

INSERT INTO core.customer_addresses (
    tenant_id,
    customer_id,
    address_type,
    street,
    number,
    complement,
    district,
    city,
    state_code,
    postal_code,
    is_default
)
SELECT
    '11111111-1111-1111-1111-111111111111'::uuid,
    g AS customer_id,
    'shipping',
    'Rua ' || (ARRAY['das Flores', 'Avenida Central', 'dos Pinheiros', 'Comercial', 'das Palmeiras'])[((g - 1) % 5) + 1],
    ((g * 13) % 950 + 10)::text,
    CASE WHEN g % 5 = 0 THEN 'Apto ' || ((g % 80) + 10)::text ELSE NULL END,
    (ARRAY['Centro', 'Vila Nova', 'Jardins', 'Moema', 'Santa Luzia', 'Boa Vista'])[((g - 1) % 6) + 1],
    (ARRAY['Sao Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba', 'Porto Alegre', 'Campinas'])[((g - 1) % 6) + 1],
    (ARRAY['SP', 'RJ', 'MG', 'PR', 'RS', 'SP'])[((g - 1) % 6) + 1],
    lpad(((1000000 + g * 791) % 99999999)::text, 8, '0'),
    true
FROM generate_series(1, 120) AS g;

-- ================================================================
-- CATEGORIAS
-- ================================================================

INSERT INTO catalog.categories (
    category_id,
    tenant_id,
    parent_category_id,
    category_name,
    slug,
    category_level
)
VALUES
    (1, '11111111-1111-1111-1111-111111111111', NULL, 'Eletronicos', 'eletronicos', 1),
    (2, '11111111-1111-1111-1111-111111111111', NULL, 'Casa e Decoracao', 'casa-decoracao', 1),
    (3, '11111111-1111-1111-1111-111111111111', NULL, 'Moda', 'moda', 1),
    (4, '11111111-1111-1111-1111-111111111111', NULL, 'Esportes e Lazer', 'esportes-lazer', 1),
    (5, '11111111-1111-1111-1111-111111111111', 1, 'Smartphones', 'smartphones', 2),
    (6, '11111111-1111-1111-1111-111111111111', 1, 'Notebooks', 'notebooks', 2),
    (7, '11111111-1111-1111-1111-111111111111', 1, 'Acessorios Tech', 'acessorios-tech', 2),
    (8, '11111111-1111-1111-1111-111111111111', 2, 'Cozinha', 'cozinha', 2),
    (9, '11111111-1111-1111-1111-111111111111', 2, 'Moveis', 'moveis', 2),
    (10, '11111111-1111-1111-1111-111111111111', 2, 'Iluminacao', 'iluminacao', 2),
    (11, '11111111-1111-1111-1111-111111111111', 3, 'Roupas Femininas', 'roupas-femininas', 2),
    (12, '11111111-1111-1111-1111-111111111111', 3, 'Roupas Masculinas', 'roupas-masculinas', 2),
    (13, '11111111-1111-1111-1111-111111111111', 3, 'Calcados', 'calcados', 2),
    (14, '11111111-1111-1111-1111-111111111111', 4, 'Fitness', 'fitness', 2),
    (15, '11111111-1111-1111-1111-111111111111', 4, 'Ciclismo', 'ciclismo', 2),
    (16, '11111111-1111-1111-1111-111111111111', NULL, 'Beleza', 'beleza', 1),
    (17, '11111111-1111-1111-1111-111111111111', 16, 'Skincare', 'skincare', 2),
    (18, '11111111-1111-1111-1111-111111111111', 16, 'Perfumaria', 'perfumaria', 2);

-- ================================================================
-- PRODUTOS E PRECOS
-- ================================================================

INSERT INTO catalog.products (
    product_id,
    tenant_id,
    seller_id,
    category_id,
    sku,
    product_name,
    description,
    brand,
    condition_type,
    weight_kg,
    length_cm,
    width_cm,
    height_cm,
    status,
    created_at
)
SELECT
    g AS product_id,
    '11111111-1111-1111-1111-111111111111'::uuid AS tenant_id,
    ((g - 1) % 20) + 1 AS seller_id,
    ((g - 1) % 14) + 5 AS category_id,
    'SKU-MNX-' || lpad(g::text, 5, '0') AS sku,
    (ARRAY['Nova', 'Prime', 'Urban', 'Essential', 'Max', 'Pro', 'Lite', 'Plus', 'Smart', 'Eco'])[((g - 1) % 10) + 1]
        || ' '
        || (ARRAY[
            'Smartphone', 'Notebook', 'Fone Bluetooth', 'Panela Inox', 'Mesa Compacta',
            'Luminaria LED', 'Vestido Casual', 'Camisa Oxford', 'Tenis Runner', 'Halter Ajustavel',
            'Capacete Bike', 'Serum Facial', 'Perfume Fresh', 'Mochila Executiva'
        ])[((g - 1) % 14) + 1]
        || ' '
        || lpad(((g * 37) % 999)::text, 3, '0') AS product_name,
    'Produto com ficha tecnica completa, garantia do seller e historico de precos para analise de margem.' AS description,
    (ARRAY['Nexa', 'Aurora', 'Vitta', 'PrimeLab', 'UrbanCo', 'CasaMax', 'FitPro', 'Lumina'])[((g - 1) % 8) + 1] AS brand,
    CASE WHEN g % 29 = 0 THEN 'refurbished' ELSE 'new' END AS condition_type,
    round((0.15 + ((g % 35) * 0.18))::numeric, 3) AS weight_kg,
    round((8 + ((g * 3) % 70))::numeric, 2) AS length_cm,
    round((6 + ((g * 5) % 55))::numeric, 2) AS width_cm,
    round((3 + ((g * 7) % 40))::numeric, 2) AS height_cm,
    'active' AS status,
    timestamp '2024-10-15 09:00:00' + (g * interval '9 hours') AS created_at
FROM generate_series(1, 220) AS g;

INSERT INTO catalog.product_price_history (
    tenant_id,
    product_id,
    price,
    cost_amount,
    valid_from,
    is_current
)
SELECT
    p.tenant_id,
    p.product_id,
    round((35 + (p.product_id % 40) * 12.70 + (p.category_id % 5) * 43.90)::numeric, 2) AS price,
    round((35 + (p.product_id % 40) * 12.70 + (p.category_id % 5) * 43.90) * (0.52 + ((p.product_id % 9) * 0.025))::numeric, 2) AS cost_amount,
    p.created_at + interval '1 day' AS valid_from,
    true
FROM catalog.products p;

-- ================================================================
-- ARMAZENS E ESTOQUE
-- ================================================================

INSERT INTO fulfillment.warehouses (
    warehouse_id,
    tenant_id,
    warehouse_code,
    warehouse_name,
    city,
    state_code,
    postal_code,
    is_active
)
VALUES
    (1, '11111111-1111-1111-1111-111111111111', 'SP-GRU-01', 'CD Guarulhos', 'Guarulhos', 'SP', '07000000', true),
    (2, '11111111-1111-1111-1111-111111111111', 'RJ-DUC-01', 'CD Duque de Caxias', 'Duque de Caxias', 'RJ', '25000000', true),
    (3, '11111111-1111-1111-1111-111111111111', 'PR-CWB-01', 'CD Curitiba', 'Curitiba', 'PR', '80000000', true),
    (4, '11111111-1111-1111-1111-111111111111', 'PE-REC-01', 'CD Recife', 'Recife', 'PE', '50000000', true);

INSERT INTO fulfillment.inventory (
    tenant_id,
    warehouse_id,
    product_id,
    quantity_on_hand,
    quantity_reserved,
    safety_stock,
    last_counted_at
)
SELECT
    '11111111-1111-1111-1111-111111111111'::uuid,
    w.warehouse_id,
    p.product_id,
    120 + ((p.product_id * w.warehouse_id * 17) % 420) AS quantity_on_hand,
    ((p.product_id + w.warehouse_id) % 9) AS quantity_reserved,
    15 + ((p.product_id + w.warehouse_id) % 35) AS safety_stock,
    timestamp '2026-05-01 08:00:00' + ((p.product_id % 20) * interval '4 hours') AS last_counted_at
FROM fulfillment.warehouses w
CROSS JOIN catalog.products p;

INSERT INTO fulfillment.inventory_movements (
    tenant_id,
    warehouse_id,
    product_id,
    movement_type,
    quantity_delta,
    balance_after,
    reference_table,
    reason,
    created_at
)
SELECT
    i.tenant_id,
    i.warehouse_id,
    i.product_id,
    'purchase',
    i.quantity_on_hand,
    i.quantity_on_hand,
    'initial_load',
    'Carga inicial de estoque do portfolio',
    timestamp '2025-01-01 07:00:00' + ((i.product_id % 30) * interval '1 hour')
FROM fulfillment.inventory i;

-- ================================================================
-- PEDIDOS
-- ================================================================

WITH order_seed AS (
    SELECT
        g,
        timestamp '2025-01-01 08:00:00'
            + ((g % 512) * interval '1 day')
            + ((g % 11) * interval '1 hour') AS order_date,
        CASE
            WHEN g % 20 = 0 THEN 'cancelled'
            WHEN g % 17 = 0 THEN 'refunded'
            WHEN g % 11 = 0 THEN 'shipped'
            WHEN g % 7 = 0 THEN 'picking'
            WHEN g % 5 = 0 THEN 'paid'
            ELSE 'delivered'
        END AS order_status
    FROM generate_series(1, 620) AS g
)
INSERT INTO sales.orders (
    order_id,
    tenant_id,
    customer_id,
    order_number,
    order_status,
    sales_channel,
    order_date,
    approved_at,
    shipped_at,
    delivered_at,
    cancelled_at,
    freight_amount,
    coupon_code,
    created_at
)
SELECT
    g AS order_id,
    '11111111-1111-1111-1111-111111111111'::uuid,
    ((g * 7) % 117) + 1 AS customer_id,
    'MNX-2025-' || lpad(g::text, 6, '0') AS order_number,
    order_status,
    (ARRAY['web', 'mobile_app', 'api', 'marketplace_partner'])[((g - 1) % 4) + 1] AS sales_channel,
    order_date,
    CASE WHEN order_status <> 'cancelled' THEN order_date + interval '15 minutes' END AS approved_at,
    CASE WHEN order_status IN ('shipped', 'delivered', 'refunded') THEN order_date + interval '2 days' END AS shipped_at,
    CASE WHEN order_status IN ('delivered', 'refunded') THEN order_date + interval '6 days' END AS delivered_at,
    CASE WHEN order_status = 'cancelled' THEN order_date + interval '2 hours' END AS cancelled_at,
    round((12.90 + (g % 8) * 3.75)::numeric, 2) AS freight_amount,
    CASE WHEN g % 9 = 0 THEN 'CUPOM' || lpad((g % 40)::text, 2, '0') END AS coupon_code,
    order_date
FROM order_seed;

INSERT INTO sales.order_items (
    tenant_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    unit_cost,
    discount_amount,
    tax_amount,
    commission_rate
)
SELECT
    o.tenant_id,
    o.order_id,
    p.product_id,
    p.seller_id,
    ((o.order_id + item.item_no) % 4) + 1 AS quantity,
    ph.price AS unit_price,
    ph.cost_amount AS unit_cost,
    round(
        CASE
            WHEN o.coupon_code IS NOT NULL THEN ph.price * (((o.order_id + item.item_no) % 4) + 1) * 0.08
            WHEN o.sales_channel = 'marketplace_partner' THEN ph.price * (((o.order_id + item.item_no) % 4) + 1) * 0.03
            ELSE 0
        END,
        2
    ) AS discount_amount,
    round(ph.price * (((o.order_id + item.item_no) % 4) + 1) * 0.0925, 2) AS tax_amount,
    s.commission_rate
FROM sales.orders o
CROSS JOIN LATERAL generate_series(1, ((o.order_id % 4) + 1)) AS item(item_no)
JOIN catalog.products p
  ON p.product_id = ((o.order_id * 7 + item.item_no * 13) % 220) + 1
JOIN core.sellers s
  ON s.seller_id = p.seller_id
JOIN catalog.product_price_history ph
  ON ph.product_id = p.product_id
 AND ph.is_current = true;

-- Pagamentos coerentes com o status do pedido e ja com totais recalculados pelos triggers.
INSERT INTO sales.payments (
    tenant_id,
    order_id,
    payment_method,
    payment_status,
    amount,
    installments,
    transaction_code,
    authorized_at,
    paid_at,
    created_at
)
SELECT
    o.tenant_id,
    o.order_id,
    (ARRAY['credit_card', 'debit_card', 'pix', 'boleto', 'wallet'])[((o.order_id - 1) % 5) + 1] AS payment_method,
    CASE
        WHEN o.order_status = 'cancelled' THEN 'failed'
        WHEN o.order_status = 'refunded' THEN 'refunded'
        ELSE 'paid'
    END AS payment_status,
    CASE WHEN o.order_status = 'cancelled' THEN 0 ELSE o.total_amount END AS amount,
    CASE WHEN o.order_id % 5 = 1 THEN 6 WHEN o.order_id % 5 = 2 THEN 3 ELSE 1 END AS installments,
    'TX-MNX-' || lpad(o.order_id::text, 8, '0') AS transaction_code,
    CASE WHEN o.order_status <> 'cancelled' THEN o.approved_at END AS authorized_at,
    CASE WHEN o.order_status NOT IN ('cancelled') THEN o.approved_at + interval '1 minute' END AS paid_at,
    o.order_date
FROM sales.orders o;

-- Devolucoes/amostras de pos-venda.
INSERT INTO sales.returns (
    tenant_id,
    order_item_id,
    return_reason,
    return_status,
    requested_at,
    resolved_at,
    refund_amount
)
SELECT
    oi.tenant_id,
    oi.order_item_id,
    (ARRAY['damaged', 'late_delivery', 'wrong_item', 'regret', 'defective', 'other'])[((oi.order_item_id - 1) % 6) + 1],
    CASE WHEN o.order_status = 'refunded' THEN 'refunded' ELSE (ARRAY['requested', 'approved', 'received'])[((oi.order_item_id - 1) % 3) + 1] END,
    coalesce(o.delivered_at, o.order_date + interval '7 days') + interval '2 days',
    CASE WHEN oi.order_item_id % 3 <> 1 THEN coalesce(o.delivered_at, o.order_date + interval '7 days') + interval '5 days' END,
    round(oi.line_total_amount * CASE WHEN o.order_status = 'refunded' THEN 1 ELSE 0.80 END, 2)
FROM sales.order_items oi
JOIN sales.orders o
  ON o.order_id = oi.order_id
WHERE o.order_status IN ('delivered', 'refunded')
  AND oi.order_item_id % 19 = 0
LIMIT 85;

-- Ajuste de estoque por vendas historicas, mantendo rastreabilidade em movimentos.
WITH sold AS (
    SELECT
        oi.tenant_id,
        oi.product_id,
        ceil(sum(oi.quantity)::numeric / 4)::integer AS qty_per_warehouse
    FROM sales.order_items oi
    JOIN sales.orders o
      ON o.order_id = oi.order_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY oi.tenant_id, oi.product_id
)
INSERT INTO fulfillment.inventory_movements (
    tenant_id,
    warehouse_id,
    product_id,
    movement_type,
    quantity_delta,
    reference_table,
    reason,
    created_at
)
SELECT
    i.tenant_id,
    i.warehouse_id,
    i.product_id,
    'sale',
    -least(i.quantity_on_hand - i.safety_stock, s.qty_per_warehouse),
    'sales.order_items',
    'Baixa agregada por vendas historicas da carga mockada',
    timestamp '2026-05-20 20:00:00'
FROM fulfillment.inventory i
JOIN sold s
  ON s.product_id = i.product_id
WHERE i.quantity_on_hand > i.safety_stock;

WITH sold AS (
    SELECT
        oi.product_id,
        ceil(sum(oi.quantity)::numeric / 4)::integer AS qty_per_warehouse
    FROM sales.order_items oi
    JOIN sales.orders o
      ON o.order_id = oi.order_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY oi.product_id
)
UPDATE fulfillment.inventory i
   SET quantity_on_hand = greatest(i.quantity_on_hand - s.qty_per_warehouse, i.safety_stock),
       updated_at = now()
  FROM sold s
 WHERE s.product_id = i.product_id;

-- Eventos brutos para demonstrar staging/ETL.
INSERT INTO staging.raw_order_events (
    tenant_id,
    source_system,
    event_type,
    event_payload,
    ingested_at,
    processing_status
)
SELECT
    o.tenant_id,
    'checkout-api',
    'order_status_changed',
    jsonb_build_object(
        'order_id', o.order_id,
        'order_number', o.order_number,
        'status', o.order_status,
        'channel', o.sales_channel,
        'total_amount', o.total_amount
    ),
    o.order_date + interval '5 minutes',
    CASE WHEN o.order_id % 23 = 0 THEN 'failed' ELSE 'processed' END
FROM sales.orders o
WHERE o.order_id <= 200;

-- Apuracao financeira e carga do DW.
CALL finance.sp_generate_seller_payouts(
    '11111111-1111-1111-1111-111111111111',
    date '2025-01-01',
    date '2026-05-31'
);

CALL dw.sp_refresh_sales_mart(date '2025-01-01', date '2026-05-31');

REFRESH MATERIALIZED VIEW dw.mv_monthly_seller_performance;

-- Reposiciona sequences apos inserts com IDs explicitos.
SELECT setval(pg_get_serial_sequence('core.customers', 'customer_id'), (SELECT max(customer_id) FROM core.customers));
SELECT setval(pg_get_serial_sequence('core.customer_addresses', 'address_id'), (SELECT max(address_id) FROM core.customer_addresses));
SELECT setval(pg_get_serial_sequence('core.sellers', 'seller_id'), (SELECT max(seller_id) FROM core.sellers));
SELECT setval(pg_get_serial_sequence('catalog.categories', 'category_id'), (SELECT max(category_id) FROM catalog.categories));
SELECT setval(pg_get_serial_sequence('catalog.products', 'product_id'), (SELECT max(product_id) FROM catalog.products));
SELECT setval(pg_get_serial_sequence('catalog.product_price_history', 'product_price_id'), (SELECT max(product_price_id) FROM catalog.product_price_history));
SELECT setval(pg_get_serial_sequence('catalog.product_version_history', 'product_version_id'), (SELECT max(product_version_id) FROM catalog.product_version_history));
SELECT setval(pg_get_serial_sequence('fulfillment.warehouses', 'warehouse_id'), (SELECT max(warehouse_id) FROM fulfillment.warehouses));
SELECT setval(pg_get_serial_sequence('fulfillment.inventory', 'inventory_id'), (SELECT max(inventory_id) FROM fulfillment.inventory));
SELECT setval(pg_get_serial_sequence('fulfillment.inventory_movements', 'movement_id'), (SELECT max(movement_id) FROM fulfillment.inventory_movements));
SELECT setval(pg_get_serial_sequence('sales.orders', 'order_id'), (SELECT max(order_id) FROM sales.orders));
SELECT setval(pg_get_serial_sequence('sales.order_items', 'order_item_id'), (SELECT max(order_item_id) FROM sales.order_items));
SELECT setval(pg_get_serial_sequence('sales.payments', 'payment_id'), (SELECT max(payment_id) FROM sales.payments));
SELECT setval(pg_get_serial_sequence('sales.order_status_history', 'status_history_id'), (SELECT max(status_history_id) FROM sales.order_status_history));
SELECT setval(pg_get_serial_sequence('sales.returns', 'return_id'), (SELECT max(return_id) FROM sales.returns));
SELECT setval(pg_get_serial_sequence('finance.seller_payouts', 'payout_id'), (SELECT max(payout_id) FROM finance.seller_payouts));
SELECT setval(pg_get_serial_sequence('staging.raw_order_events', 'raw_event_id'), (SELECT max(raw_event_id) FROM staging.raw_order_events));

ANALYZE;
