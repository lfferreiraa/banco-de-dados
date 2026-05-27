-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: database/security.sql
-- Objetivo: roles, grants e isolamento multi-tenant com Row Level Security
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;

-- Roles sem senha para evitar credenciais versionadas.
-- Em producao, crie usuarios LOGIN e associe a estas roles:
-- CREATE ROLE app_user LOGIN PASSWORD '<secret>';
-- GRANT mercadonexa_app TO app_user;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mercadonexa_readonly') THEN
        CREATE ROLE mercadonexa_readonly;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mercadonexa_analyst') THEN
        CREATE ROLE mercadonexa_analyst;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mercadonexa_app') THEN
        CREATE ROLE mercadonexa_app;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mercadonexa_admin') THEN
        CREATE ROLE mercadonexa_admin;
    END IF;
END
$$;

REVOKE ALL ON DATABASE mercadonexa_marketplace FROM PUBLIC;
GRANT CONNECT ON DATABASE mercadonexa_marketplace TO mercadonexa_readonly, mercadonexa_analyst, mercadonexa_app, mercadonexa_admin;

REVOKE ALL ON SCHEMA core, catalog, sales, fulfillment, finance, audit, staging, dw FROM PUBLIC;
GRANT USAGE ON SCHEMA core, catalog, sales, fulfillment, finance, dw TO mercadonexa_readonly, mercadonexa_analyst, mercadonexa_app, mercadonexa_admin;
GRANT USAGE ON SCHEMA audit, staging TO mercadonexa_analyst, mercadonexa_admin;

GRANT SELECT ON ALL TABLES IN SCHEMA core, catalog, sales, fulfillment, finance, dw
    TO mercadonexa_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA core, catalog, sales, fulfillment, finance, audit, staging, dw
    TO mercadonexa_analyst;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core, catalog, sales, fulfillment, finance
    TO mercadonexa_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA core, catalog, sales, fulfillment, finance
    TO mercadonexa_app;

GRANT SELECT, INSERT ON audit.audit_log TO mercadonexa_app;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core, catalog, sales, fulfillment, finance, audit, staging, dw
    TO mercadonexa_admin;

GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core, catalog, sales, fulfillment, finance, audit, staging, dw
    TO mercadonexa_admin;

-- Funcao usada pelas policies multi-tenant.
CREATE OR REPLACE FUNCTION core.current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT nullif(current_setting('app.current_tenant_id', true), '')::uuid;
$$;

-- Exemplo de uso na sessao da aplicacao:
-- SET app.current_tenant_id = '11111111-1111-1111-1111-111111111111';

ALTER TABLE core.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.sellers ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.product_price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE fulfillment.warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE fulfillment.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.seller_payouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation_customers ON core.customers;
CREATE POLICY tenant_isolation_customers ON core.customers
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_customer_addresses ON core.customer_addresses;
CREATE POLICY tenant_isolation_customer_addresses ON core.customer_addresses
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_sellers ON core.sellers;
CREATE POLICY tenant_isolation_sellers ON core.sellers
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_categories ON catalog.categories;
CREATE POLICY tenant_isolation_categories ON catalog.categories
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_products ON catalog.products;
CREATE POLICY tenant_isolation_products ON catalog.products
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_product_prices ON catalog.product_price_history;
CREATE POLICY tenant_isolation_product_prices ON catalog.product_price_history
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_warehouses ON fulfillment.warehouses;
CREATE POLICY tenant_isolation_warehouses ON fulfillment.warehouses
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_inventory ON fulfillment.inventory;
CREATE POLICY tenant_isolation_inventory ON fulfillment.inventory
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_orders ON sales.orders;
CREATE POLICY tenant_isolation_orders ON sales.orders
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_order_items ON sales.order_items;
CREATE POLICY tenant_isolation_order_items ON sales.order_items
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_payments ON sales.payments;
CREATE POLICY tenant_isolation_payments ON sales.payments
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

DROP POLICY IF EXISTS tenant_isolation_seller_payouts ON finance.seller_payouts;
CREATE POLICY tenant_isolation_seller_payouts ON finance.seller_payouts
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());

-- Permissoes padrao para novos objetos.
ALTER DEFAULT PRIVILEGES IN SCHEMA core, catalog, sales, fulfillment, finance, dw
    GRANT SELECT ON TABLES TO mercadonexa_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA core, catalog, sales, fulfillment, finance, dw
    GRANT SELECT ON TABLES TO mercadonexa_analyst;

ALTER DEFAULT PRIVILEGES IN SCHEMA core, catalog, sales, fulfillment, finance
    GRANT SELECT, INSERT, UPDATE ON TABLES TO mercadonexa_app;
