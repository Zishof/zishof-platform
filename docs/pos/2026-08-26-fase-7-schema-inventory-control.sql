-- Fase 7 - DRAFT migration inventory control.
-- Target: PostgreSQL 13.
-- Status: UNTUK REVIEW. Jangan jalankan langsung ke produksi.
-- Koreksi kuantitas wajib masuk inventory_core.inventory_movement melalui
-- InventoryPostingPort. Pelepasan karantina hanya mengubah status lot dan
-- tidak boleh membuat movement kuantitas positif kedua.

CREATE SCHEMA IF NOT EXISTS inventory_control;

CREATE TABLE IF NOT EXISTS inventory_control.cycle_count (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    location_id         bigint NOT NULL,
    count_number        varchar(80) NOT NULL,
    business_at         timestamp without time zone NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'DRAFT',
    reason              varchar(1000),
    approved_by         varchar(100),
    approved_at         timestamp without time zone,
    posted_at           timestamp without time zone,
    created_by          varchar(100) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_cycle_count_number UNIQUE (tenant_id, count_number),
    CONSTRAINT ck_cycle_count_status CHECK
        (status IN ('DRAFT', 'COUNTING', 'SUBMITTED', 'APPROVED',
                    'POSTED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT ck_cycle_count_approval CHECK
        (status NOT IN ('APPROVED', 'POSTED')
         OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS inventory_control.cycle_count_line (
    id                  bigserial PRIMARY KEY,
    cycle_count_id      bigint NOT NULL,
    line_number         integer NOT NULL,
    item_id             bigint NOT NULL,
    uom_id              bigint NOT NULL,
    lot_id              bigint,
    expected_quantity   numeric(24,6) NOT NULL,
    counted_quantity    numeric(24,6) NOT NULL,
    variance_quantity   numeric(24,6) NOT NULL,
    variance_reason     varchar(1000),
    idempotency_key     varchar(200) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_cycle_count_line_header FOREIGN KEY (cycle_count_id)
        REFERENCES inventory_control.cycle_count(id),
    CONSTRAINT fk_cycle_count_line_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT uq_cycle_count_line UNIQUE (cycle_count_id, line_number),
    CONSTRAINT uq_cycle_count_line_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_cycle_count_line_quantity CHECK
        (expected_quantity >= 0 AND counted_quantity >= 0
         AND variance_quantity = counted_quantity - expected_quantity),
    CONSTRAINT ck_cycle_count_line_reason CHECK
        (variance_quantity = 0 OR length(trim(coalesce(variance_reason, ''))) > 0)
);

CREATE TABLE IF NOT EXISTS inventory_control.quarantine_release (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    lot_id              bigint NOT NULL,
    quantity            numeric(24,6) NOT NULL,
    reason              varchar(1000) NOT NULL,
    status              varchar(30) NOT NULL DEFAULT 'APPROVED',
    approved_by         varchar(100) NOT NULL,
    approved_at         timestamp without time zone NOT NULL,
    released_at         timestamp without time zone,
    idempotency_key     varchar(200) NOT NULL,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_quarantine_release_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT uq_quarantine_release_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_quarantine_release_quantity CHECK (quantity > 0),
    CONSTRAINT ck_quarantine_release_status CHECK
        (status IN ('APPROVED', 'RELEASED', 'REJECTED', 'CANCELLED'))
);

CREATE TABLE IF NOT EXISTS inventory_control.inventory_lot_status_event (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    lot_id              bigint NOT NULL,
    status_from         varchar(30) NOT NULL,
    status_to           varchar(30) NOT NULL,
    source_type         varchar(50) NOT NULL,
    source_id           varchar(100) NOT NULL,
    reason              varchar(1000),
    changed_by          varchar(100) NOT NULL,
    changed_at          timestamp without time zone NOT NULL,
    idempotency_key     varchar(200) NOT NULL,
    CONSTRAINT fk_lot_status_event_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT uq_lot_status_event_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_lot_status_event_change CHECK (status_from <> status_to)
);

CREATE INDEX IF NOT EXISTS ix_cycle_count_status
    ON inventory_control.cycle_count (tenant_id, location_id, status, business_at);
CREATE INDEX IF NOT EXISTS ix_cycle_count_line_item
    ON inventory_control.cycle_count_line (item_id, lot_id);
CREATE INDEX IF NOT EXISTS ix_quarantine_release_lot
    ON inventory_control.quarantine_release (tenant_id, lot_id, status);
CREATE INDEX IF NOT EXISTS ix_lot_status_event_lot
    ON inventory_control.inventory_lot_status_event (tenant_id, lot_id, changed_at);

-- Adapter runtime wajib menjalankan lock header/lot, validasi ulang saldo,
-- posting seluruh variance, pencatatan event, dan perubahan status dalam satu
-- transaksi database. Kegagalan satu baris harus me-rollback seluruh dokumen.
-- FK tenant, lokasi, item, dan UOM ditambahkan setelah mapping kanonis Fase 2
-- disahkan; kolom ID sudah disediakan agar kontrak tidak berubah.
