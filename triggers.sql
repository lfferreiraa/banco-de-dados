-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: database/triggers.sql
-- Objetivo: triggers de auditoria, historico, validacao e consistencia
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;

-- ================================================================
-- updated_at automatico
-- ================================================================

DROP TRIGGER IF EXISTS trg_tenants_touch_updated_at ON core.tenants;
CREATE TRIGGER trg_tenants_touch_updated_at
BEFORE UPDATE ON core.tenants
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_customers_touch_updated_at ON core.customers;
CREATE TRIGGER trg_customers_touch_updated_at
BEFORE UPDATE ON core.customers
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_customer_addresses_touch_updated_at ON core.customer_addresses;
CREATE TRIGGER trg_customer_addresses_touch_updated_at
BEFORE UPDATE ON core.customer_addresses
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_sellers_touch_updated_at ON core.sellers;
CREATE TRIGGER trg_sellers_touch_updated_at
BEFORE UPDATE ON core.sellers
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_categories_touch_updated_at ON catalog.categories;
CREATE TRIGGER trg_categories_touch_updated_at
BEFORE UPDATE ON catalog.categories
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_products_touch_updated_at ON catalog.products;
CREATE TRIGGER trg_products_touch_updated_at
BEFORE UPDATE ON catalog.products
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_warehouses_touch_updated_at ON fulfillment.warehouses;
CREATE TRIGGER trg_warehouses_touch_updated_at
BEFORE UPDATE ON fulfillment.warehouses
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

DROP TRIGGER IF EXISTS trg_orders_touch_updated_at ON sales.orders;
CREATE TRIGGER trg_orders_touch_updated_at
BEFORE UPDATE ON sales.orders
FOR EACH ROW
EXECUTE FUNCTION core.fn_touch_updated_at();

-- ================================================================
-- Auditoria generica em tabelas criticas
-- ================================================================

DROP TRIGGER IF EXISTS trg_customers_audit ON core.customers;
CREATE TRIGGER trg_customers_audit
AFTER INSERT OR UPDATE OR DELETE ON core.customers
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('customer_id');

DROP TRIGGER IF EXISTS trg_sellers_audit ON core.sellers;
CREATE TRIGGER trg_sellers_audit
AFTER INSERT OR UPDATE OR DELETE ON core.sellers
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('seller_id');

DROP TRIGGER IF EXISTS trg_products_audit ON catalog.products;
CREATE TRIGGER trg_products_audit
AFTER INSERT OR UPDATE OR DELETE ON catalog.products
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('product_id');

DROP TRIGGER IF EXISTS trg_product_price_history_audit ON catalog.product_price_history;
CREATE TRIGGER trg_product_price_history_audit
AFTER INSERT OR UPDATE OR DELETE ON catalog.product_price_history
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('product_price_id');

DROP TRIGGER IF EXISTS trg_inventory_audit ON fulfillment.inventory;
CREATE TRIGGER trg_inventory_audit
AFTER INSERT OR UPDATE OR DELETE ON fulfillment.inventory
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('inventory_id');

DROP TRIGGER IF EXISTS trg_orders_audit ON sales.orders;
CREATE TRIGGER trg_orders_audit
AFTER INSERT OR UPDATE OR DELETE ON sales.orders
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('order_id');

DROP TRIGGER IF EXISTS trg_payments_audit ON sales.payments;
CREATE TRIGGER trg_payments_audit
AFTER INSERT OR UPDATE OR DELETE ON sales.payments
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('payment_id');

DROP TRIGGER IF EXISTS trg_seller_payouts_audit ON finance.seller_payouts;
CREATE TRIGGER trg_seller_payouts_audit
AFTER INSERT OR UPDATE OR DELETE ON finance.seller_payouts
FOR EACH ROW
EXECUTE FUNCTION audit.fn_log_row_change('payout_id');

-- ================================================================
-- Versionamento de catalogo e historico de preco
-- ================================================================

DROP TRIGGER IF EXISTS trg_products_version_history ON catalog.products;
CREATE TRIGGER trg_products_version_history
AFTER INSERT OR UPDATE ON catalog.products
FOR EACH ROW
EXECUTE FUNCTION catalog.fn_version_product();

DROP TRIGGER IF EXISTS trg_product_price_close_previous ON catalog.product_price_history;
CREATE TRIGGER trg_product_price_close_previous
BEFORE INSERT ON catalog.product_price_history
FOR EACH ROW
EXECUTE FUNCTION catalog.fn_close_previous_current_price();

-- ================================================================
-- Vendas: validacao, totais e historico de status
-- ================================================================

DROP TRIGGER IF EXISTS trg_order_items_validate ON sales.order_items;
CREATE TRIGGER trg_order_items_validate
BEFORE INSERT OR UPDATE ON sales.order_items
FOR EACH ROW
EXECUTE FUNCTION sales.fn_validate_order_item();

DROP TRIGGER IF EXISTS trg_order_items_recalculate_totals ON sales.order_items;
CREATE TRIGGER trg_order_items_recalculate_totals
AFTER INSERT OR UPDATE OR DELETE ON sales.order_items
FOR EACH ROW
EXECUTE FUNCTION sales.fn_recalculate_order_totals_trigger();

DROP TRIGGER IF EXISTS trg_orders_status_history ON sales.orders;
CREATE TRIGGER trg_orders_status_history
AFTER INSERT OR UPDATE OF order_status ON sales.orders
FOR EACH ROW
EXECUTE FUNCTION sales.fn_log_order_status_change();
