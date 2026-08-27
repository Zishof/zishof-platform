-- Fase 6 - DRAFT migration WMS inbound, QC, dan putaway.
-- Target: PostgreSQL 13.
-- Status: UNTUK REVIEW. Jangan jalankan langsung ke produksi.
-- BAST existing tetap dokumen penerimaan formal. Saldo available hanya berubah
-- setelah QC diterima dan putaway selesai melalui InventoryPostingPort.

CREATE SCHEMA IF NOT EXISTS warehouse;

CREATE TABLE IF NOT EXISTS warehouse.inbound_shipment (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    inbound_number      varchar(80) NOT NULL,
    purchase_order_id   bigint,
    bast_id             bigint,
    vendor_id           bigint,
    expected_at         timestamp without time zone,
    arrived_at          timestamp without time zone,
    status              varchar(30) NOT NULL DEFAULT 'PLANNED',
    reference_note      varchar(500),
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_inbound_shipment_number UNIQUE (tenant_id, inbound_number),
    CONSTRAINT ck_inbound_shipment_status CHECK
        (status IN ('PLANNED', 'ARRIVED', 'RECEIVING', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS warehouse.inbound_shipment_detail (
    id                  bigserial PRIMARY KEY,
    inbound_shipment_id bigint NOT NULL,
    purchase_order_detail_id bigint,
    item_id             bigint NOT NULL,
    uom_id              bigint NOT NULL,
    expected_quantity   numeric(24,6) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_inbound_detail_header FOREIGN KEY (inbound_shipment_id)
        REFERENCES warehouse.inbound_shipment(id),
    CONSTRAINT ck_inbound_detail_quantity CHECK (expected_quantity > 0)
);

CREATE TABLE IF NOT EXISTS warehouse.goods_receipt (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    receipt_number      varchar(80) NOT NULL,
    inbound_shipment_id bigint,
    purchase_order_id   bigint,
    bast_id             bigint,
    vendor_id           bigint,
    received_at         timestamp without time zone NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'DRAFT',
    created_by          varchar(100),
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_goods_receipt_inbound FOREIGN KEY (inbound_shipment_id)
        REFERENCES warehouse.inbound_shipment(id),
    CONSTRAINT uq_goods_receipt_number UNIQUE (tenant_id, receipt_number),
    CONSTRAINT ck_goods_receipt_status CHECK
        (status IN ('DRAFT', 'IN_QC', 'ACCEPTED', 'PARTIALLY_ACCEPTED',
                    'POSTED', 'REJECTED', 'REVERSED'))
);

CREATE TABLE IF NOT EXISTS warehouse.goods_receipt_detail (
    id                  bigserial PRIMARY KEY,
    goods_receipt_id    bigint NOT NULL,
    line_number         integer NOT NULL,
    purchase_order_detail_id bigint,
    bast_detail_id      bigint,
    vendor_id           bigint,
    item_id             bigint NOT NULL,
    uom_id              bigint NOT NULL,
    expected_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    received_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    accepted_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    rejected_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    quarantined_quantity numeric(24,6) NOT NULL DEFAULT 0,
    lot_id              bigint,
    lot_code            varchar(100),
    expiry_date         timestamp without time zone,
    receiving_location_id bigint NOT NULL,
    quality_status      varchar(30) NOT NULL DEFAULT 'PENDING',
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_goods_receipt_detail_header FOREIGN KEY (goods_receipt_id)
        REFERENCES warehouse.goods_receipt(id),
    CONSTRAINT fk_goods_receipt_detail_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT uq_goods_receipt_line UNIQUE (goods_receipt_id, line_number),
    CONSTRAINT ck_goods_receipt_detail_quantities CHECK
        (expected_quantity >= 0 AND received_quantity >= 0
         AND accepted_quantity >= 0 AND rejected_quantity >= 0
         AND quarantined_quantity >= 0
         AND received_quantity = accepted_quantity + rejected_quantity
                                 + quarantined_quantity),
    CONSTRAINT ck_goods_receipt_detail_quality CHECK
        (quality_status IN ('PENDING', 'ACCEPTED', 'PARTIAL', 'REJECTED', 'QUARANTINED')),
    CONSTRAINT ck_goods_receipt_detail_lot CHECK
        (accepted_quantity = 0 OR lot_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS warehouse.goods_receipt_qc (
    id                  bigserial PRIMARY KEY,
    goods_receipt_detail_id bigint NOT NULL,
    inspected_at        timestamp without time zone NOT NULL,
    inspected_by        varchar(100) NOT NULL,
    accepted_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    rejected_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    quarantined_quantity numeric(24,6) NOT NULL DEFAULT 0,
    result_status       varchar(30) NOT NULL,
    reason              varchar(1000),
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_goods_receipt_qc_detail FOREIGN KEY (goods_receipt_detail_id)
        REFERENCES warehouse.goods_receipt_detail(id),
    CONSTRAINT ck_goods_receipt_qc_quantities CHECK
        (accepted_quantity >= 0 AND rejected_quantity >= 0
         AND quarantined_quantity >= 0),
    CONSTRAINT ck_goods_receipt_qc_status CHECK
        (result_status IN ('ACCEPTED', 'PARTIAL', 'REJECTED', 'QUARANTINED'))
);

CREATE TABLE IF NOT EXISTS warehouse.putaway_task (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    task_number         varchar(80) NOT NULL,
    goods_receipt_id    bigint NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'OPEN',
    assigned_to         varchar(100),
    completed_at        timestamp without time zone,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_putaway_task_receipt FOREIGN KEY (goods_receipt_id)
        REFERENCES warehouse.goods_receipt(id),
    CONSTRAINT uq_putaway_task_number UNIQUE (tenant_id, task_number),
    CONSTRAINT ck_putaway_task_status CHECK
        (status IN ('OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS warehouse.putaway_task_detail (
    id                  bigserial PRIMARY KEY,
    putaway_task_id     bigint NOT NULL,
    goods_receipt_detail_id bigint NOT NULL,
    target_location_id  bigint NOT NULL,
    quantity            numeric(24,6) NOT NULL,
    completed_at        timestamp without time zone,
    idempotency_key     varchar(200) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_putaway_detail_task FOREIGN KEY (putaway_task_id)
        REFERENCES warehouse.putaway_task(id),
    CONSTRAINT fk_putaway_detail_receipt FOREIGN KEY (goods_receipt_detail_id)
        REFERENCES warehouse.goods_receipt_detail(id),
    CONSTRAINT uq_putaway_detail_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_putaway_detail_quantity CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS ix_inbound_shipment_status
    ON warehouse.inbound_shipment (tenant_id, status, expected_at);
CREATE INDEX IF NOT EXISTS ix_goods_receipt_status
    ON warehouse.goods_receipt (tenant_id, status, received_at);
CREATE INDEX IF NOT EXISTS ix_goods_receipt_detail_item
    ON warehouse.goods_receipt_detail (item_id, lot_id);
CREATE INDEX IF NOT EXISTS ix_putaway_task_status
    ON warehouse.putaway_task (tenant_id, status, created_at);

-- Tidak dibuat FK ke tabel tenant, item, UOM, lokasi, PO, BAST, dan vendor
-- sebelum keputusan mapping kanonis Fase 2/5 disahkan. Kolom ID sengaja tetap
-- tersedia agar migration lanjutan dapat menambah FK tanpa mengubah kontrak.
