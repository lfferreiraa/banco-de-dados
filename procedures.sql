-- ================================================================
-- Projeto: MercadoNexa Marketplace Analytics
-- Arquivo: database/procedures.sql
-- Objetivo: functions e stored procedures de negocio, auditoria e ETL
-- ================================================================

\connect mercadonexa_marketplace

SET search_path TO core, catalog, sales, fulfillment, finance, audit, dw, public;

-- ================================================================
-- FUNCOES UTILITARIAS
-- ================================================================

CREATE OR REPLACE FUNCTION core.fn_normalize_email(p_email TEXT)
RETURNS CITEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT lower(trim(p_email))::citext;
$$;

CREATE OR REPLACE FUNCTION core.fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION finance.fn_seller_net_amount(
    p_gross_amount NUMERIC,
    p_commission_amount NUMERIC,
    p_refund_amount NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT greatest(
        coalesce(p_gross_amount, 0)
        - coalesce(p_commission_amount, 0)
        - coalesce(p_refund_amount, 0),
        0
    );
$$;

-- ================================================================
-- FUNCOES DE AUDITORIA E VERSIONAMENTO
-- ================================================================

CREATE OR REPLACE FUNCTION audit.fn_log_row_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
    v_record_pk TEXT;
    v_operation CHAR(1);
    v_pk_column TEXT := coalesce(TG_ARGV[0], 'id');
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_operation := 'I';
        v_new_data := to_jsonb(NEW);
        v_record_pk := v_new_data ->> v_pk_column;
    ELSIF TG_OP = 'UPDATE' THEN
        v_operation := 'U';
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
        v_record_pk := coalesce(v_new_data ->> v_pk_column, v_old_data ->> v_pk_column);
    ELSE
        v_operation := 'D';
        v_old_data := to_jsonb(OLD);
        v_record_pk := v_old_data ->> v_pk_column;
    END IF;

    INSERT INTO audit.audit_log (
        schema_name,
        table_name,
        operation,
        record_pk,
        old_data,
        new_data,
        changed_by
    )
    VALUES (
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        v_operation,
        v_record_pk,
        v_old_data,
        v_new_data,
        current_user
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION catalog.fn_version_product()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_next_version INTEGER;
BEGIN
    SELECT coalesce(max(version_number), 0) + 1
      INTO v_next_version
      FROM catalog.product_version_history
     WHERE product_id = NEW.product_id;

    INSERT INTO catalog.product_version_history (
        tenant_id,
        product_id,
        version_number,
        product_snapshot,
        changed_by
    )
    VALUES (
        NEW.tenant_id,
        NEW.product_id,
        v_next_version,
        to_jsonb(NEW),
        current_user
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION catalog.fn_close_previous_current_price()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_current THEN
        UPDATE catalog.product_price_history
           SET is_current = false,
               valid_to = NEW.valid_from
         WHERE product_id = NEW.product_id
           AND is_current = true
           AND product_price_id <> coalesce(NEW.product_price_id, -1);
    END IF;

    RETURN NEW;
END;
$$;

-- ================================================================
-- FUNCOES DE VENDAS E ESTOQUE
-- ================================================================

CREATE OR REPLACE FUNCTION fulfillment.fn_available_stock(p_product_id BIGINT)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(sum(quantity_on_hand - quantity_reserved), 0)::integer
      FROM fulfillment.inventory
     WHERE product_id = p_product_id;
$$;

CREATE OR REPLACE FUNCTION sales.fn_customer_lifetime_value(p_customer_id BIGINT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(sum(total_amount), 0)
      FROM sales.orders
     WHERE customer_id = p_customer_id
       AND order_status IN ('paid', 'picking', 'shipped', 'delivered')
       AND deleted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION sales.fn_validate_order_item()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_product_tenant UUID;
    v_product_seller BIGINT;
    v_seller_commission NUMERIC(5,4);
BEGIN
    SELECT p.tenant_id, p.seller_id, s.commission_rate
      INTO v_product_tenant, v_product_seller, v_seller_commission
      FROM catalog.products p
      JOIN core.sellers s
        ON s.seller_id = p.seller_id
     WHERE p.product_id = NEW.product_id
       AND p.status = 'active'
       AND p.deleted_at IS NULL;

    IF v_product_tenant IS NULL THEN
        RAISE EXCEPTION 'Produto % inexistente ou inativo.', NEW.product_id;
    END IF;

    IF v_product_tenant <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Produto % pertence a outro tenant.', NEW.product_id;
    END IF;

    IF NEW.seller_id <> v_product_seller THEN
        RAISE EXCEPTION 'Seller informado (%) nao corresponde ao seller do produto (%).',
            NEW.seller_id, v_product_seller;
    END IF;

    IF NEW.commission_rate IS NULL THEN
        NEW.commission_rate := v_seller_commission;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sales.fn_recalculate_order_totals(p_order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_subtotal NUMERIC(14,2);
    v_discount NUMERIC(14,2);
    v_tax NUMERIC(14,2);
    v_commission NUMERIC(14,2);
    v_items_total NUMERIC(14,2);
BEGIN
    SELECT
        coalesce(sum(gross_amount), 0),
        coalesce(sum(discount_amount), 0),
        coalesce(sum(tax_amount), 0),
        coalesce(sum(commission_amount), 0),
        coalesce(sum(line_total_amount), 0)
      INTO v_subtotal, v_discount, v_tax, v_commission, v_items_total
      FROM sales.order_items
     WHERE order_id = p_order_id;

    UPDATE sales.orders
       SET subtotal_amount = v_subtotal,
           discount_amount = v_discount,
           tax_amount = v_tax,
           commission_amount = v_commission,
           total_amount = v_items_total + freight_amount,
           updated_at = now()
     WHERE order_id = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION sales.fn_recalculate_order_totals_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id BIGINT;
BEGIN
    v_order_id := coalesce(NEW.order_id, OLD.order_id);
    PERFORM sales.fn_recalculate_order_totals(v_order_id);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sales.fn_log_order_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO sales.order_status_history (
            tenant_id,
            order_id,
            old_status,
            new_status,
            changed_by,
            reason
        )
        VALUES (
            NEW.tenant_id,
            NEW.order_id,
            NULL,
            NEW.order_status,
            current_user,
            'Pedido criado'
        );

        RETURN NEW;
    END IF;

    IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN
        INSERT INTO sales.order_status_history (
            tenant_id,
            order_id,
            old_status,
            new_status,
            changed_by,
            reason
        )
        VALUES (
            NEW.tenant_id,
            NEW.order_id,
            OLD.order_status,
            NEW.order_status,
            current_user,
            'Alteracao de status'
        );
    END IF;

    RETURN NEW;
END;
$$;

-- ================================================================
-- STORED PROCEDURES TRANSACIONAIS
-- ================================================================

CREATE OR REPLACE PROCEDURE sales.sp_place_order(
    IN p_tenant_id UUID,
    IN p_customer_id BIGINT,
    IN p_items JSONB,
    IN p_payment_method VARCHAR DEFAULT 'pix',
    IN p_sales_channel VARCHAR DEFAULT 'web',
    IN p_coupon_code VARCHAR DEFAULT NULL,
    OUT p_order_id BIGINT,
    OUT p_order_number VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_item JSONB;
    v_product_id BIGINT;
    v_quantity INTEGER;
    v_seller_id BIGINT;
    v_commission_rate NUMERIC(5,4);
    v_price NUMERIC(12,2);
    v_cost NUMERIC(12,2);
    v_warehouse_id BIGINT;
    v_available INTEGER;
    v_freight NUMERIC(14,2) := 19.90;
    v_payment_amount NUMERIC(14,2);
BEGIN
    IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'p_items deve ser um array JSON com ao menos um produto.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM core.customers
         WHERE customer_id = p_customer_id
           AND tenant_id = p_tenant_id
           AND status = 'active'
           AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Cliente % inexistente, inativo ou de outro tenant.', p_customer_id;
    END IF;

    INSERT INTO sales.orders (
        tenant_id,
        customer_id,
        order_number,
        order_status,
        sales_channel,
        order_date,
        freight_amount,
        coupon_code
    )
    VALUES (
        p_tenant_id,
        p_customer_id,
        'MNX-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || '-' || lpad((floor(random() * 10000))::text, 4, '0'),
        'created',
        p_sales_channel,
        now(),
        v_freight,
        p_coupon_code
    )
    RETURNING order_id, order_number INTO p_order_id, p_order_number;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item ->> 'product_id')::BIGINT;
        v_quantity := (v_item ->> 'quantity')::INTEGER;

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Quantidade invalida para produto %.', v_product_id;
        END IF;

        SELECT p.seller_id, s.commission_rate, ph.price, ph.cost_amount
          INTO v_seller_id, v_commission_rate, v_price, v_cost
          FROM catalog.products p
          JOIN core.sellers s
            ON s.seller_id = p.seller_id
          JOIN catalog.product_price_history ph
            ON ph.product_id = p.product_id
           AND ph.is_current = true
         WHERE p.product_id = v_product_id
           AND p.tenant_id = p_tenant_id
           AND p.status = 'active'
           AND p.deleted_at IS NULL;

        IF v_price IS NULL THEN
            RAISE EXCEPTION 'Produto % sem preco corrente.', v_product_id;
        END IF;

        SELECT i.warehouse_id, i.quantity_on_hand - i.quantity_reserved
          INTO v_warehouse_id, v_available
          FROM fulfillment.inventory i
          JOIN fulfillment.warehouses w
            ON w.warehouse_id = i.warehouse_id
         WHERE i.tenant_id = p_tenant_id
           AND i.product_id = v_product_id
           AND w.is_active = true
           AND (i.quantity_on_hand - i.quantity_reserved) >= v_quantity
         ORDER BY (i.quantity_on_hand - i.quantity_reserved) DESC
         LIMIT 1
         FOR UPDATE OF i;

        IF v_warehouse_id IS NULL THEN
            RAISE EXCEPTION 'Estoque insuficiente para produto %. Disponivel total: %.',
                v_product_id, fulfillment.fn_available_stock(v_product_id);
        END IF;

        UPDATE fulfillment.inventory
           SET quantity_reserved = quantity_reserved + v_quantity,
               updated_at = now()
         WHERE warehouse_id = v_warehouse_id
           AND product_id = v_product_id;

        INSERT INTO fulfillment.inventory_movements (
            tenant_id,
            warehouse_id,
            product_id,
            movement_type,
            quantity_delta,
            reference_table,
            reference_id,
            reason
        )
        VALUES (
            p_tenant_id,
            v_warehouse_id,
            v_product_id,
            'reservation',
            -v_quantity,
            'sales.orders',
            p_order_id,
            'Reserva de estoque no checkout'
        );

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
        VALUES (
            p_tenant_id,
            p_order_id,
            v_product_id,
            v_seller_id,
            v_quantity,
            v_price,
            v_cost,
            CASE WHEN p_coupon_code IS NOT NULL THEN round(v_price * v_quantity * 0.05, 2) ELSE 0 END,
            round(v_price * v_quantity * 0.0925, 2),
            v_commission_rate
        );

        UPDATE fulfillment.inventory
           SET quantity_on_hand = quantity_on_hand - v_quantity,
               quantity_reserved = quantity_reserved - v_quantity,
               updated_at = now()
         WHERE warehouse_id = v_warehouse_id
           AND product_id = v_product_id;

        INSERT INTO fulfillment.inventory_movements (
            tenant_id,
            warehouse_id,
            product_id,
            movement_type,
            quantity_delta,
            reference_table,
            reference_id,
            reason
        )
        VALUES (
            p_tenant_id,
            v_warehouse_id,
            v_product_id,
            'sale',
            -v_quantity,
            'sales.orders',
            p_order_id,
            'Baixa definitiva apos aprovacao de pagamento'
        );
    END LOOP;

    PERFORM sales.fn_recalculate_order_totals(p_order_id);

    UPDATE sales.orders
       SET order_status = 'paid',
           approved_at = now(),
           updated_at = now()
     WHERE order_id = p_order_id
     RETURNING total_amount INTO v_payment_amount;

    INSERT INTO sales.payments (
        tenant_id,
        order_id,
        payment_method,
        payment_status,
        amount,
        installments,
        transaction_code,
        authorized_at,
        paid_at
    )
    VALUES (
        p_tenant_id,
        p_order_id,
        p_payment_method,
        'paid',
        v_payment_amount,
        CASE WHEN p_payment_method = 'credit_card' THEN 3 ELSE 1 END,
        'TX-' || p_order_number,
        now(),
        now()
    );
END;
$$;

CREATE OR REPLACE PROCEDURE sales.sp_update_order_status(
    IN p_order_id BIGINT,
    IN p_new_status VARCHAR,
    IN p_reason VARCHAR DEFAULT 'Atualizacao operacional'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(30);
BEGIN
    SELECT order_status
      INTO v_current_status
      FROM sales.orders
     WHERE order_id = p_order_id
       AND deleted_at IS NULL
     FOR UPDATE;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'Pedido % nao encontrado.', p_order_id;
    END IF;

    IF p_new_status NOT IN ('created', 'approved', 'paid', 'picking', 'shipped', 'delivered', 'cancelled', 'refunded') THEN
        RAISE EXCEPTION 'Status % invalido.', p_new_status;
    END IF;

    IF v_current_status IN ('delivered', 'cancelled', 'refunded')
       AND p_new_status <> v_current_status THEN
        RAISE EXCEPTION 'Pedido em status terminal (%) nao pode ir para %.',
            v_current_status, p_new_status;
    END IF;

    UPDATE sales.orders
       SET order_status = p_new_status,
           approved_at = CASE WHEN p_new_status IN ('approved', 'paid', 'picking', 'shipped', 'delivered')
                              THEN coalesce(approved_at, now()) ELSE approved_at END,
           shipped_at = CASE WHEN p_new_status IN ('shipped', 'delivered')
                             THEN coalesce(shipped_at, now()) ELSE shipped_at END,
           delivered_at = CASE WHEN p_new_status = 'delivered'
                               THEN coalesce(delivered_at, now()) ELSE delivered_at END,
           cancelled_at = CASE WHEN p_new_status = 'cancelled'
                               THEN coalesce(cancelled_at, now()) ELSE cancelled_at END,
           updated_at = now()
     WHERE order_id = p_order_id;

    UPDATE sales.order_status_history
       SET reason = p_reason
     WHERE status_history_id = (
        SELECT status_history_id
          FROM sales.order_status_history
         WHERE order_id = p_order_id
         ORDER BY changed_at DESC
         LIMIT 1
     );
END;
$$;

CREATE OR REPLACE PROCEDURE finance.sp_generate_seller_payouts(
    IN p_tenant_id UUID,
    IN p_period_start DATE,
    IN p_period_end DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_period_end < p_period_start THEN
        RAISE EXCEPTION 'Periodo invalido: % ate %.', p_period_start, p_period_end;
    END IF;

    INSERT INTO finance.seller_payouts (
        tenant_id,
        seller_id,
        period_start,
        period_end,
        gross_amount,
        commission_amount,
        refund_amount,
        net_amount,
        payout_status
    )
    SELECT
        o.tenant_id,
        oi.seller_id,
        p_period_start,
        p_period_end,
        sum(oi.gross_amount) AS gross_amount,
        sum(oi.commission_amount) AS commission_amount,
        coalesce(sum(r.refund_amount) FILTER (WHERE r.return_status IN ('approved', 'received', 'refunded')), 0) AS refund_amount,
        finance.fn_seller_net_amount(
            sum(oi.gross_amount),
            sum(oi.commission_amount),
            coalesce(sum(r.refund_amount) FILTER (WHERE r.return_status IN ('approved', 'received', 'refunded')), 0)
        ) AS net_amount,
        'calculated'
      FROM sales.orders o
      JOIN sales.order_items oi
        ON oi.order_id = o.order_id
      LEFT JOIN sales.returns r
        ON r.order_item_id = oi.order_item_id
     WHERE o.tenant_id = p_tenant_id
       AND o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
       AND o.order_date::date BETWEEN p_period_start AND p_period_end
       AND o.deleted_at IS NULL
     GROUP BY o.tenant_id, oi.seller_id
    ON CONFLICT (tenant_id, seller_id, period_start, period_end)
    DO UPDATE
       SET gross_amount = EXCLUDED.gross_amount,
           commission_amount = EXCLUDED.commission_amount,
           refund_amount = EXCLUDED.refund_amount,
           net_amount = EXCLUDED.net_amount,
           payout_status = 'calculated',
           created_at = now();
END;
$$;

CREATE OR REPLACE PROCEDURE dw.sp_refresh_sales_mart(
    IN p_start_date DATE,
    IN p_end_date DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_end_date < p_start_date THEN
        RAISE EXCEPTION 'Periodo invalido: % ate %.', p_start_date, p_end_date;
    END IF;

    INSERT INTO dw.dim_date (
        date_key,
        full_date,
        year_number,
        quarter_number,
        month_number,
        month_name,
        day_number,
        week_number,
        is_weekend
    )
    SELECT
        to_char(d::date, 'YYYYMMDD')::integer,
        d::date,
        extract(year FROM d)::integer,
        extract(quarter FROM d)::integer,
        extract(month FROM d)::integer,
        trim(to_char(d, 'TMMonth')),
        extract(day FROM d)::integer,
        extract(week FROM d)::integer,
        extract(isodow FROM d)::integer IN (6, 7)
      FROM generate_series(p_start_date, p_end_date, INTERVAL '1 day') AS d
    ON CONFLICT (date_key) DO NOTHING;

    INSERT INTO dw.dim_customer (
        tenant_id,
        customer_id,
        customer_name,
        email,
        acquisition_channel,
        status
    )
    SELECT
        c.tenant_id,
        c.customer_id,
        c.first_name || ' ' || c.last_name,
        c.email,
        c.acquisition_channel,
        c.status
      FROM core.customers c
     WHERE c.deleted_at IS NULL
       AND NOT EXISTS (
            SELECT 1
              FROM dw.dim_customer dc
             WHERE dc.tenant_id = c.tenant_id
               AND dc.customer_id = c.customer_id
               AND dc.is_current = true
       );

    INSERT INTO dw.dim_product (
        tenant_id,
        product_id,
        sku,
        product_name,
        category_name,
        brand,
        seller_id
    )
    SELECT
        p.tenant_id,
        p.product_id,
        p.sku,
        p.product_name,
        c.category_name,
        p.brand,
        p.seller_id
      FROM catalog.products p
      JOIN catalog.categories c
        ON c.category_id = p.category_id
     WHERE p.deleted_at IS NULL
       AND NOT EXISTS (
            SELECT 1
              FROM dw.dim_product dp
             WHERE dp.tenant_id = p.tenant_id
               AND dp.product_id = p.product_id
               AND dp.is_current = true
       );

    INSERT INTO dw.dim_seller (
        tenant_id,
        seller_id,
        seller_name,
        seller_segment,
        quality_score
    )
    SELECT
        s.tenant_id,
        s.seller_id,
        s.seller_name,
        s.seller_segment,
        s.quality_score
      FROM core.sellers s
     WHERE s.deleted_at IS NULL
       AND NOT EXISTS (
            SELECT 1
              FROM dw.dim_seller ds
             WHERE ds.tenant_id = s.tenant_id
               AND ds.seller_id = s.seller_id
               AND ds.is_current = true
       );

    DELETE FROM dw.fact_order_items f
     USING dw.dim_date d
     WHERE f.date_key = d.date_key
       AND d.full_date BETWEEN p_start_date AND p_end_date;

    INSERT INTO dw.fact_order_items (
        tenant_id,
        date_key,
        customer_key,
        product_key,
        seller_key,
        order_id,
        order_item_id,
        quantity,
        gross_revenue,
        discount_amount,
        tax_amount,
        net_revenue,
        commission_amount,
        product_cost,
        contribution_margin
    )
    SELECT
        o.tenant_id,
        to_char(o.order_date::date, 'YYYYMMDD')::integer AS date_key,
        dc.customer_key,
        dp.product_key,
        ds.seller_key,
        o.order_id,
        oi.order_item_id,
        oi.quantity,
        oi.gross_amount,
        oi.discount_amount,
        oi.tax_amount,
        oi.line_total_amount,
        oi.commission_amount,
        oi.unit_cost * oi.quantity AS product_cost,
        oi.line_total_amount - oi.commission_amount - (oi.unit_cost * oi.quantity) AS contribution_margin
      FROM sales.orders o
      JOIN sales.order_items oi
        ON oi.order_id = o.order_id
      JOIN dw.dim_customer dc
        ON dc.tenant_id = o.tenant_id
       AND dc.customer_id = o.customer_id
       AND dc.is_current = true
      JOIN dw.dim_product dp
        ON dp.tenant_id = oi.tenant_id
       AND dp.product_id = oi.product_id
       AND dp.is_current = true
      JOIN dw.dim_seller ds
        ON ds.tenant_id = oi.tenant_id
       AND ds.seller_id = oi.seller_id
       AND ds.is_current = true
     WHERE o.order_date::date BETWEEN p_start_date AND p_end_date
       AND o.order_status IN ('paid', 'picking', 'shipped', 'delivered')
       AND o.deleted_at IS NULL
    ON CONFLICT (tenant_id, order_item_id) DO NOTHING;
END;
$$;
