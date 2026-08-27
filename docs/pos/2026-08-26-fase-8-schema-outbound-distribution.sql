-- Fase 8 - DRAFT migration outbound dan distribusi.
-- Target: PostgreSQL 13.
-- Status: UNTUK REVIEW. Jangan jalankan langsung ke produksi.
-- BAST vendor tetap berada pada procurement/inbound. Outlet receipt adalah
-- dokumen distribusi internal yang berbeda.

CREATE SCHEMA IF NOT EXISTS inventory_distribution;

CREATE TABLE IF NOT EXISTS inventory_distribution.stock_transfer (
    id                      bigserial PRIMARY KEY,
    tenant_id               bigint NOT NULL,
    transfer_number         varchar(80) NOT NULL,
    source_location_id      bigint NOT NULL,
    destination_location_id bigint NOT NULL,
    request_source_type     varchar(50),
    request_source_id       varchar(100),
    status                  varchar(30) NOT NULL DEFAULT 'DRAFT',
    requested_at            timestamp without time zone NOT NULL,
    reservation_expires_at  timestamp without time zone,
    created_by              varchar(100) NOT NULL,
    created_at              timestamp without time zone NOT NULL DEFAULT now(),
    updated_at              timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_stock_transfer_number UNIQUE (tenant_id, transfer_number),
    CONSTRAINT ck_stock_transfer_location CHECK
        (source_location_id <> destination_location_id),
    CONSTRAINT ck_stock_transfer_status CHECK
        (status IN ('DRAFT', 'SUBMITTED', 'APPROVED', 'RESERVED', 'PICKED',
                    'PACKED', 'DISPATCHED', 'IN_TRANSIT',
                    'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_distribution.stock_transfer_line (
    id                  bigserial PRIMARY KEY,
    stock_transfer_id   bigint NOT NULL,
    line_number         integer NOT NULL,
    item_id             bigint NOT NULL,
    uom_id              bigint NOT NULL,
    requested_quantity  numeric(24,6) NOT NULL,
    approved_quantity   numeric(24,6) NOT NULL,
    note                varchar(1000),
    CONSTRAINT fk_stock_transfer_line_header FOREIGN KEY (stock_transfer_id)
        REFERENCES inventory_distribution.stock_transfer(id),
    CONSTRAINT uq_stock_transfer_line UNIQUE (stock_transfer_id, line_number),
    CONSTRAINT ck_stock_transfer_line_quantity CHECK
        (requested_quantity > 0 AND approved_quantity >= 0
         AND approved_quantity <= requested_quantity)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.stock_transfer_allocation (
    id                  bigserial PRIMARY KEY,
    stock_transfer_line_id bigint NOT NULL,
    allocation_key      varchar(200) NOT NULL,
    source_lot_id       bigint,
    allocated_quantity  numeric(24,6) NOT NULL,
    reservation_key     varchar(200) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_transfer_allocation_line FOREIGN KEY (stock_transfer_line_id)
        REFERENCES inventory_distribution.stock_transfer_line(id),
    CONSTRAINT fk_transfer_allocation_lot FOREIGN KEY (source_lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT uq_transfer_allocation_key UNIQUE (allocation_key),
    CONSTRAINT uq_transfer_reservation_key UNIQUE (reservation_key),
    CONSTRAINT ck_transfer_allocation_quantity CHECK (allocated_quantity > 0)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.picking_task (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    stock_transfer_id   bigint NOT NULL,
    task_number         varchar(80) NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'OPEN',
    assigned_to         varchar(100),
    started_at          timestamp without time zone,
    completed_at        timestamp without time zone,
    idempotency_key     varchar(200) NOT NULL,
    CONSTRAINT fk_picking_transfer FOREIGN KEY (stock_transfer_id)
        REFERENCES inventory_distribution.stock_transfer(id),
    CONSTRAINT uq_picking_number UNIQUE (tenant_id, task_number),
    CONSTRAINT uq_picking_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_picking_status CHECK
        (status IN ('OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_distribution.picking_task_line (
    id                  bigserial PRIMARY KEY,
    picking_task_id     bigint NOT NULL,
    allocation_id       bigint NOT NULL,
    picked_quantity     numeric(24,6) NOT NULL,
    source_bin_code     varchar(100),
    picked_at           timestamp without time zone,
    CONSTRAINT fk_picking_line_header FOREIGN KEY (picking_task_id)
        REFERENCES inventory_distribution.picking_task(id),
    CONSTRAINT fk_picking_line_allocation FOREIGN KEY (allocation_id)
        REFERENCES inventory_distribution.stock_transfer_allocation(id),
    CONSTRAINT uq_picking_line_allocation UNIQUE (picking_task_id, allocation_id),
    CONSTRAINT ck_picking_line_quantity CHECK (picked_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.packing (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    stock_transfer_id   bigint NOT NULL,
    packing_number      varchar(80) NOT NULL,
    package_count       integer NOT NULL DEFAULT 0,
    status              varchar(30) NOT NULL DEFAULT 'OPEN',
    packed_by           varchar(100),
    packed_at           timestamp without time zone,
    idempotency_key     varchar(200) NOT NULL,
    CONSTRAINT fk_packing_transfer FOREIGN KEY (stock_transfer_id)
        REFERENCES inventory_distribution.stock_transfer(id),
    CONSTRAINT uq_packing_number UNIQUE (tenant_id, packing_number),
    CONSTRAINT uq_packing_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_packing_package_count CHECK (package_count >= 0),
    CONSTRAINT ck_packing_status CHECK
        (status IN ('OPEN', 'PACKED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_distribution.delivery_order (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    stock_transfer_id   bigint NOT NULL,
    delivery_number     varchar(80) NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'DRAFT',
    planned_departure_at timestamp without time zone,
    carrier_name        varchar(200),
    vehicle_number      varchar(100),
    driver_name         varchar(200),
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_delivery_order_transfer FOREIGN KEY (stock_transfer_id)
        REFERENCES inventory_distribution.stock_transfer(id),
    CONSTRAINT uq_delivery_order_number UNIQUE (tenant_id, delivery_number),
    CONSTRAINT ck_delivery_order_status CHECK
        (status IN ('DRAFT', 'READY', 'DISPATCHED', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_distribution.shipment (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    delivery_order_id   bigint NOT NULL,
    shipment_number     varchar(80) NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'READY',
    dispatched_at       timestamp without time zone,
    delivered_at        timestamp without time zone,
    dispatch_idempotency_key varchar(200) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_shipment_delivery_order FOREIGN KEY (delivery_order_id)
        REFERENCES inventory_distribution.delivery_order(id),
    CONSTRAINT uq_shipment_number UNIQUE (tenant_id, shipment_number),
    CONSTRAINT uq_shipment_dispatch_idempotency UNIQUE (dispatch_idempotency_key),
    CONSTRAINT ck_shipment_status CHECK
        (status IN ('READY', 'DISPATCHED', 'IN_TRANSIT', 'DELIVERED',
                    'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_distribution.shipment_line (
    id                  bigserial PRIMARY KEY,
    shipment_id         bigint NOT NULL,
    allocation_id       bigint NOT NULL,
    shipped_quantity    numeric(24,6) NOT NULL,
    issue_idempotency_key varchar(200) NOT NULL,
    CONSTRAINT fk_shipment_line_header FOREIGN KEY (shipment_id)
        REFERENCES inventory_distribution.shipment(id),
    CONSTRAINT fk_shipment_line_allocation FOREIGN KEY (allocation_id)
        REFERENCES inventory_distribution.stock_transfer_allocation(id),
    CONSTRAINT uq_shipment_line_allocation UNIQUE (shipment_id, allocation_id),
    CONSTRAINT uq_shipment_line_issue_key UNIQUE (issue_idempotency_key),
    CONSTRAINT ck_shipment_line_quantity CHECK (shipped_quantity > 0)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.shipment_event (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    shipment_id         bigint NOT NULL,
    event_type          varchar(50) NOT NULL,
    event_at            timestamp without time zone NOT NULL,
    actor               varchar(100),
    location_note       varchar(500),
    note                varchar(1000),
    idempotency_key     varchar(200) NOT NULL,
    CONSTRAINT fk_shipment_event_header FOREIGN KEY (shipment_id)
        REFERENCES inventory_distribution.shipment(id),
    CONSTRAINT uq_shipment_event_idempotency UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.proof_of_delivery (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    shipment_id         bigint NOT NULL,
    proof_number        varchar(100) NOT NULL,
    received_by         varchar(200) NOT NULL,
    delivered_at        timestamp without time zone NOT NULL,
    signature_reference varchar(500),
    photo_reference     varchar(500),
    note                varchar(1000),
    idempotency_key     varchar(200) NOT NULL,
    CONSTRAINT fk_pod_shipment FOREIGN KEY (shipment_id)
        REFERENCES inventory_distribution.shipment(id),
    CONSTRAINT uq_pod_number UNIQUE (tenant_id, proof_number),
    CONSTRAINT uq_pod_idempotency UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.outlet_receipt (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    shipment_id         bigint NOT NULL,
    receipt_number      varchar(80) NOT NULL,
    destination_location_id bigint NOT NULL,
    received_by         varchar(100) NOT NULL,
    received_at         timestamp without time zone NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'RECEIVED',
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_outlet_receipt_shipment FOREIGN KEY (shipment_id)
        REFERENCES inventory_distribution.shipment(id),
    CONSTRAINT uq_outlet_receipt_number UNIQUE (tenant_id, receipt_number),
    CONSTRAINT ck_outlet_receipt_status CHECK
        (status IN ('RECEIVED', 'PARTIAL', 'DISCREPANCY', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_distribution.outlet_receipt_line (
    id                  bigserial PRIMARY KEY,
    outlet_receipt_id   bigint NOT NULL,
    shipment_line_id    bigint NOT NULL,
    accepted_quantity   numeric(24,6) NOT NULL,
    damaged_quantity    numeric(24,6) NOT NULL DEFAULT 0,
    rejected_quantity   numeric(24,6) NOT NULL DEFAULT 0,
    receive_idempotency_key varchar(200) NOT NULL,
    note                varchar(1000),
    CONSTRAINT fk_outlet_receipt_line_header FOREIGN KEY (outlet_receipt_id)
        REFERENCES inventory_distribution.outlet_receipt(id),
    CONSTRAINT fk_outlet_receipt_line_shipment FOREIGN KEY (shipment_line_id)
        REFERENCES inventory_distribution.shipment_line(id),
    CONSTRAINT uq_outlet_receipt_line UNIQUE (outlet_receipt_id, shipment_line_id),
    CONSTRAINT uq_outlet_receipt_receive_key UNIQUE (receive_idempotency_key),
    CONSTRAINT ck_outlet_receipt_line_quantity CHECK
        (accepted_quantity >= 0 AND damaged_quantity >= 0
         AND rejected_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS inventory_distribution.transfer_discrepancy (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    outlet_receipt_line_id bigint NOT NULL,
    discrepancy_type    varchar(30) NOT NULL,
    quantity            numeric(24,6) NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'OPEN',
    resolution_note     varchar(1000),
    resolved_by         varchar(100),
    resolved_at         timestamp without time zone,
    idempotency_key     varchar(200) NOT NULL,
    CONSTRAINT fk_transfer_discrepancy_receipt FOREIGN KEY (outlet_receipt_line_id)
        REFERENCES inventory_distribution.outlet_receipt_line(id),
    CONSTRAINT uq_transfer_discrepancy_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_transfer_discrepancy_quantity CHECK (quantity > 0),
    CONSTRAINT ck_transfer_discrepancy_type CHECK
        (discrepancy_type IN ('SHORT', 'DAMAGED', 'REJECTED', 'OVER')),
    CONSTRAINT ck_transfer_discrepancy_status CHECK
        (status IN ('OPEN', 'INVESTIGATING', 'RESOLVED', 'CANCELLED'))
);

CREATE INDEX IF NOT EXISTS ix_stock_transfer_status
    ON inventory_distribution.stock_transfer
       (tenant_id, source_location_id, destination_location_id, status, requested_at);
CREATE INDEX IF NOT EXISTS ix_transfer_line_item
    ON inventory_distribution.stock_transfer_line (item_id, uom_id);
CREATE INDEX IF NOT EXISTS ix_transfer_allocation_lot
    ON inventory_distribution.stock_transfer_allocation (source_lot_id);
CREATE INDEX IF NOT EXISTS ix_shipment_status
    ON inventory_distribution.shipment (tenant_id, status, dispatched_at);
CREATE INDEX IF NOT EXISTS ix_shipment_event_time
    ON inventory_distribution.shipment_event (shipment_id, event_at);
CREATE INDEX IF NOT EXISTS ix_outlet_receipt_time
    ON inventory_distribution.outlet_receipt
       (tenant_id, destination_location_id, received_at);
CREATE INDEX IF NOT EXISTS ix_transfer_discrepancy_status
    ON inventory_distribution.transfer_discrepancy (tenant_id, status);

-- Adapter runtime wajib memastikan total shipment per allocation tidak melebihi
-- alokasi/reservasi dan total accepted+damaged+rejected tidak melebihi shipped.
-- Validasi lintas baris tersebut dilakukan dengan row lock dalam satu transaksi.
-- FK tenant, lokasi, item, dan UOM ditambahkan setelah mapping kanonis Fase 2
-- disahkan; kolom ID sudah disediakan agar kontrak tidak berubah.
