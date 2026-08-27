-- Fase 9: draft additive schema produksi.
-- PostgreSQL 13. BELUM DIJALANKAN. Review dan uji di database UAT khusus.

CREATE SCHEMA IF NOT EXISTS inventory_production;

CREATE TABLE IF NOT EXISTS inventory_production.bill_of_material (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    bom_code varchar(80) NOT NULL,
    output_item_id bigint NOT NULL,
    output_uom_id bigint NOT NULL,
    name varchar(200) NOT NULL,
    active boolean NOT NULL DEFAULT true,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_production_bom_code UNIQUE (tenant_id, bom_code)
);

CREATE TABLE IF NOT EXISTS inventory_production.bill_of_material_version (
    id bigserial PRIMARY KEY,
    bom_id bigint NOT NULL REFERENCES inventory_production.bill_of_material(id),
    version_no integer NOT NULL,
    base_quantity numeric(20,6) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    effective_from timestamp without time zone,
    effective_until timestamp without time zone,
    approved_by varchar(100),
    approved_at timestamp without time zone,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_production_bom_base_qty CHECK (base_quantity > 0),
    CONSTRAINT ck_production_bom_status CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
    CONSTRAINT ck_production_bom_effective CHECK (effective_until IS NULL OR effective_from IS NULL OR effective_until > effective_from),
    CONSTRAINT uq_production_bom_version UNIQUE (bom_id, version_no)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_production_bom_one_active
    ON inventory_production.bill_of_material_version (bom_id)
    WHERE status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS inventory_production.bill_of_material_line (
    id bigserial PRIMARY KEY,
    bom_version_id bigint NOT NULL REFERENCES inventory_production.bill_of_material_version(id),
    line_no integer NOT NULL,
    component_item_id bigint NOT NULL,
    uom_id bigint NOT NULL,
    quantity numeric(20,6) NOT NULL,
    expected_loss_percent numeric(9,6) NOT NULL DEFAULT 0,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_production_bom_line_qty CHECK (quantity > 0),
    CONSTRAINT ck_production_bom_loss CHECK (expected_loss_percent >= 0 AND expected_loss_percent < 100),
    CONSTRAINT uq_production_bom_line UNIQUE (bom_version_id, line_no)
);

CREATE INDEX IF NOT EXISTS ix_production_bom_component
    ON inventory_production.bill_of_material_line (component_item_id);

CREATE TABLE IF NOT EXISTS inventory_production.production_order (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    location_id bigint NOT NULL,
    order_code varchar(80) NOT NULL,
    bom_version_id bigint NOT NULL REFERENCES inventory_production.bill_of_material_version(id),
    planned_quantity numeric(20,6) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    planned_start_at timestamp without time zone,
    planned_finish_at timestamp without time zone,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    legacy_produksi_id bigint,
    created_by varchar(100),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_production_order_qty CHECK (planned_quantity > 0),
    CONSTRAINT ck_production_order_status CHECK (status IN ('DRAFT','RELEASED','IN_PROGRESS','COMPLETED','CANCELLED')),
    CONSTRAINT uq_production_order_code UNIQUE (tenant_id, order_code)
);

CREATE INDEX IF NOT EXISTS ix_production_order_location_status
    ON inventory_production.production_order (tenant_id, location_id, status);

CREATE TABLE IF NOT EXISTS inventory_production.production_material_txn (
    id bigserial PRIMARY KEY,
    production_order_id bigint NOT NULL REFERENCES inventory_production.production_order(id),
    transaction_type varchar(20) NOT NULL,
    reference_code varchar(100) NOT NULL,
    idempotency_key varchar(180) NOT NULL,
    business_at timestamp without time zone NOT NULL,
    created_by varchar(100),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_production_material_type CHECK (transaction_type IN ('ISSUE','RETURN')),
    CONSTRAINT uq_production_material_reference UNIQUE (production_order_id, reference_code, transaction_type),
    CONSTRAINT uq_production_material_idempotency UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS inventory_production.production_material_txn_line (
    id bigserial PRIMARY KEY,
    material_txn_id bigint NOT NULL REFERENCES inventory_production.production_material_txn(id),
    line_no integer NOT NULL,
    item_id bigint NOT NULL,
    uom_id bigint NOT NULL,
    lot_id bigint NOT NULL REFERENCES inventory_core.inventory_lot(id),
    quantity numeric(20,6) NOT NULL,
    unit_cost numeric(20,6) NOT NULL DEFAULT 0,
    ledger_id bigint,
    legacy_pemakaian_id bigint,
    CONSTRAINT ck_production_material_line_qty CHECK (quantity > 0),
    CONSTRAINT ck_production_material_cost CHECK (unit_cost >= 0),
    CONSTRAINT uq_production_material_line UNIQUE (material_txn_id, line_no)
);

CREATE INDEX IF NOT EXISTS ix_production_material_lot
    ON inventory_production.production_material_txn_line (lot_id);

CREATE TABLE IF NOT EXISTS inventory_production.production_receipt (
    id bigserial PRIMARY KEY,
    production_order_id bigint NOT NULL REFERENCES inventory_production.production_order(id),
    receipt_code varchar(100) NOT NULL,
    idempotency_key varchar(180) NOT NULL,
    business_at timestamp without time zone NOT NULL,
    created_by varchar(100),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_production_receipt_code UNIQUE (production_order_id, receipt_code),
    CONSTRAINT uq_production_receipt_idempotency UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS inventory_production.production_receipt_line (
    id bigserial PRIMARY KEY,
    production_receipt_id bigint NOT NULL REFERENCES inventory_production.production_receipt(id),
    line_no integer NOT NULL,
    item_id bigint NOT NULL,
    uom_id bigint NOT NULL,
    output_lot_id bigint NOT NULL REFERENCES inventory_core.inventory_lot(id),
    accepted_quantity numeric(20,6) NOT NULL,
    ledger_id bigint,
    CONSTRAINT ck_production_receipt_qty CHECK (accepted_quantity > 0),
    CONSTRAINT uq_production_receipt_line UNIQUE (production_receipt_id, line_no)
);

CREATE TABLE IF NOT EXISTS inventory_production.production_lot_genealogy (
    id bigserial PRIMARY KEY,
    production_order_id bigint NOT NULL REFERENCES inventory_production.production_order(id),
    input_lot_id bigint NOT NULL REFERENCES inventory_core.inventory_lot(id),
    output_lot_id bigint NOT NULL REFERENCES inventory_core.inventory_lot(id),
    input_quantity numeric(20,6) NOT NULL,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_production_genealogy_qty CHECK (input_quantity > 0),
    CONSTRAINT uq_production_genealogy UNIQUE (production_order_id, input_lot_id, output_lot_id)
);

CREATE INDEX IF NOT EXISTS ix_production_genealogy_output
    ON inventory_production.production_lot_genealogy (output_lot_id);

CREATE TABLE IF NOT EXISTS inventory_production.production_waste (
    id bigserial PRIMARY KEY,
    production_order_id bigint NOT NULL REFERENCES inventory_production.production_order(id),
    reference_code varchar(100) NOT NULL,
    line_no integer NOT NULL,
    item_id bigint NOT NULL,
    uom_id bigint NOT NULL,
    lot_id bigint REFERENCES inventory_core.inventory_lot(id),
    quantity numeric(20,6) NOT NULL,
    reason_code varchar(60) NOT NULL,
    affects_stock boolean NOT NULL DEFAULT true,
    idempotency_key varchar(180) NOT NULL,
    ledger_id bigint,
    business_at timestamp without time zone NOT NULL,
    created_by varchar(100),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_production_waste_qty CHECK (quantity > 0),
    CONSTRAINT uq_production_waste_ref UNIQUE (production_order_id, reference_code, line_no),
    CONSTRAINT uq_production_waste_idempotency UNIQUE (idempotency_key)
);

CREATE INDEX IF NOT EXISTS ix_production_waste_order
    ON inventory_production.production_waste (production_order_id, business_at);

-- FK tenant/location/item/UOM sengaja belum dipasang karena tabel fisik kanonis
-- ditentukan setelah preflight Fase 2. Jangan menghubungkan ID ini ke tabel legacy
-- hanya berdasarkan nama kolom atau kebetulan nilai ID yang sama.
