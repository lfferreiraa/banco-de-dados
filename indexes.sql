-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: database/indexes.sql
-- Objetivo: indices, constraints parciais e estruturas de performance
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;

-- ================================================================
-- CORE
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_customers_tenant_status
    ON core.customers (tenant_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_customers_created_at
    ON core.customers (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer
    ON core.customer_addresses (tenant_id, customer_id, is_default DESC);

CREATE INDEX IF NOT EXISTS idx_sellers_tenant_segment_status
    ON core.sellers (tenant_id, seller_segment, status)
    WHERE deleted_at IS NULL;

-- ================================================================
-- CATALOG
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_categories_parent
    ON catalog.categories (tenant_id, parent_category_id);

CREATE INDEX IF NOT EXISTS idx_products_seller_status
    ON catalog.products (tenant_id, seller_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_products_category_status
    ON catalog.products (tenant_id, category_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_products_name_trgm
    ON catalog.products
    USING gin (product_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_products_description_fts
    ON catalog.products
    USING gin (to_tsvector('portuguese', coalesce(product_name, '') || ' ' || coalesce(description, '')));

-- Garante apenas um preco corrente por produto.
CREATE UNIQUE INDEX IF NOT EXISTS uq_product_price_current
    ON catalog.product_price_history (product_id)
    WHERE is_current = true;

CREATE INDEX IF NOT EXISTS idx_product_price_history_period
    ON catalog.product_price_history (tenant_id, product_id, valid_from DESC, valid_to);

CREATE INDEX IF NOT EXISTS idx_product_version_history_product
    ON catalog.product_version_history (tenant_id, product_id, version_number DESC);

-- ================================================================
-- FULFILLMENT
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_inventory_tenant_product
    ON fulfillment.inventory (tenant_id, product_id);

CREATE INDEX IF NOT EXISTS idx_inventory_low_stock
    ON fulfillment.inventory (tenant_id, warehouse_id, product_id)
    WHERE (quantity_on_hand - quantity_reserved) <= safety_stock;

CREATE INDEX IF NOT EXISTS idx_inventory_movements_product_date
    ON fulfillment.inventory_movements (tenant_id, product_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_reference
    ON fulfillment.inventory_movements (reference_table, reference_id)
    WHERE reference_table IS NOT NULL;

-- ================================================================
-- SALES
-- ================================================================

-- Principal indice OLTP para telas de pedido e relatorios por periodo.
CREATE INDEX IF NOT EXISTS idx_orders_tenant_date_status
    ON sales.orders (tenant_id, order_date DESC, order_status);

-- BRIN e eficiente para tabelas grandes ordenadas por tempo.
CREATE INDEX IF NOT EXISTS idx_orders_order_date_brin
    ON sales.orders
    USING brin (order_date);

CREATE INDEX IF NOT EXISTS idx_orders_customer_date
    ON sales.orders (tenant_id, customer_id, order_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_orders_paid_delivered
    ON sales.orders (tenant_id, order_date DESC)
    WHERE order_status IN ('paid', 'picking', 'shipped', 'delivered');

CREATE INDEX IF NOT EXISTS idx_order_items_order
    ON sales.order_items (tenant_id, order_id);

CREATE INDEX IF NOT EXISTS idx_order_items_seller_product
    ON sales.order_items (tenant_id, seller_id, product_id);

CREATE INDEX IF NOT EXISTS idx_order_items_product
    ON sales.order_items (tenant_id, product_id);

CREATE INDEX IF NOT EXISTS idx_payments_order_status
    ON sales.payments (tenant_id, order_id, payment_status);

CREATE INDEX IF NOT EXISTS idx_payments_paid_at
    ON sales.payments (tenant_id, paid_at DESC)
    WHERE payment_status = 'paid';

CREATE INDEX IF NOT EXISTS idx_order_status_history_order
    ON sales.order_status_history (tenant_id, order_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_returns_status_date
    ON sales.returns (tenant_id, return_status, requested_at DESC);

-- ================================================================
-- FINANCE
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_seller_payouts_period_status
    ON finance.seller_payouts (tenant_id, period_start, period_end, payout_status);

CREATE INDEX IF NOT EXISTS idx_seller_payouts_seller_period
    ON finance.seller_payouts (tenant_id, seller_id, period_start DESC);

-- ================================================================
-- AUDIT E STAGING
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_audit_log_table_date
    ON audit.audit_log (schema_name, table_name, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_record
    ON audit.audit_log (schema_name, table_name, record_pk);

CREATE INDEX IF NOT EXISTS idx_audit_log_new_data_gin
    ON audit.audit_log
    USING gin (new_data jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_raw_order_events_status
    ON staging.raw_order_events (processing_status, ingested_at);

CREATE INDEX IF NOT EXISTS idx_raw_order_events_payload_gin
    ON staging.raw_order_events
    USING gin (event_payload jsonb_path_ops);

-- ================================================================
-- DW
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_dim_customer_business_key
    ON dw.dim_customer (tenant_id, customer_id, is_current);

CREATE INDEX IF NOT EXISTS idx_dim_product_business_key
    ON dw.dim_product (tenant_id, product_id, is_current);

CREATE INDEX IF NOT EXISTS idx_dim_seller_business_key
    ON dw.dim_seller (tenant_id, seller_id, is_current);

CREATE INDEX IF NOT EXISTS idx_fact_order_items_date_seller
    ON dw.fact_order_items (tenant_id, date_key, seller_key);

CREATE INDEX IF NOT EXISTS idx_fact_order_items_product
    ON dw.fact_order_items (tenant_id, product_key);

-- Atualiza estatisticas para o otimizador depois da carga inicial.
ANALYZE;
