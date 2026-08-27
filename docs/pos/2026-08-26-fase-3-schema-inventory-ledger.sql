-- Fase 3 - DRAFT migration inventory ledger, saldo, lot, dan reservasi.
-- Target: PostgreSQL 13.
-- Status: UNTUK REVIEW. Jangan jalankan langsung ke produksi.
-- Prasyarat: hasil preflight Fase 2 dan Fase 3 telah ditinjau dan ID kanonis
-- tenant/lokasi/item/UOM sudah disepakati.

CREATE SCHEMA IF NOT EXISTS inventory_core;

CREATE TABLE IF NOT EXISTS inventory_core.inventory_lot (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    item_id             bigint NOT NULL,
    lot_code            varchar(100) NOT NULL,
    production_date     timestamp without time zone,
    expiry_date         timestamp without time zone,
    supplier_batch_code varchar(100),
    status              varchar(30) NOT NULL DEFAULT 'AVAILABLE',
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT ck_inventory_lot_status CHECK
        (status IN ('AVAILABLE', 'QUARANTINE', 'BLOCKED', 'EXPIRED', 'DEPLETED')),
    CONSTRAINT uq_inventory_lot_code UNIQUE (tenant_id, item_id, lot_code)
);

CREATE TABLE IF NOT EXISTS inventory_core.stock_balance (
    id              bigserial PRIMARY KEY,
    tenant_id       bigint NOT NULL,
    location_id     bigint NOT NULL,
    item_id         bigint NOT NULL,
    lot_id          bigint,
    quantity_on_hand numeric(24,6) NOT NULL DEFAULT 0,
    quantity_reserved numeric(24,6) NOT NULL DEFAULT 0,
    version_number  bigint NOT NULL DEFAULT 0,
    updated_at      timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_stock_balance_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT ck_stock_balance_reserved_nonnegative CHECK (quantity_reserved >= 0),
    CONSTRAINT ck_stock_balance_reserved_within_on_hand CHECK
        (quantity_reserved <= GREATEST(quantity_on_hand, 0))
);

-- PostgreSQL menganggap NULL berbeda pada UNIQUE biasa. COALESCE memastikan
-- barang tanpa lot tetap hanya mempunyai satu saldo per tenant/lokasi/item.
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_balance_scope
    ON inventory_core.stock_balance
    (tenant_id, location_id, item_id, COALESCE(lot_id, 0));

CREATE TABLE IF NOT EXISTS inventory_core.stock_ledger (
    id                bigserial PRIMARY KEY,
    tenant_id         bigint NOT NULL,
    location_id       bigint NOT NULL,
    item_id           bigint NOT NULL,
    uom_id            bigint NOT NULL,
    lot_id            bigint,
    quantity          numeric(24,6) NOT NULL,
    balance_before    numeric(24,6) NOT NULL,
    balance_after     numeric(24,6) NOT NULL,
    source_type       varchar(50) NOT NULL,
    source_id         varchar(150) NOT NULL,
    event_type        varchar(50) NOT NULL,
    idempotency_key   varchar(200) NOT NULL,
    business_at       timestamp without time zone NOT NULL,
    posted_at         timestamp without time zone NOT NULL DEFAULT now(),
    posted_by         varchar(100),
    correlation_id    varchar(100),
    CONSTRAINT fk_stock_ledger_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT ck_stock_ledger_quantity_nonzero CHECK (quantity <> 0),
    CONSTRAINT ck_stock_ledger_arithmetic CHECK
        (balance_after = balance_before + quantity),
    CONSTRAINT uq_stock_ledger_idempotency UNIQUE (tenant_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS ix_stock_ledger_balance_timeline
    ON inventory_core.stock_ledger
    (tenant_id, location_id, item_id, lot_id, business_at, id);

CREATE INDEX IF NOT EXISTS ix_stock_ledger_source
    ON inventory_core.stock_ledger (tenant_id, source_type, source_id);

CREATE TABLE IF NOT EXISTS inventory_core.stock_reservation (
    id                  bigserial PRIMARY KEY,
    tenant_id           bigint NOT NULL,
    reservation_key     varchar(200) NOT NULL,
    location_id         bigint NOT NULL,
    item_id             bigint NOT NULL,
    lot_id              bigint,
    quantity_requested  numeric(24,6) NOT NULL,
    quantity_reserved   numeric(24,6) NOT NULL,
    quantity_consumed   numeric(24,6) NOT NULL DEFAULT 0,
    status              varchar(30) NOT NULL,
    expires_at          timestamp without time zone,
    created_at          timestamp without time zone NOT NULL DEFAULT now(),
    updated_at          timestamp without time zone NOT NULL DEFAULT now(),
    version_number      bigint NOT NULL DEFAULT 0,
    CONSTRAINT fk_stock_reservation_lot FOREIGN KEY (lot_id)
        REFERENCES inventory_core.inventory_lot(id),
    CONSTRAINT ck_stock_reservation_quantity CHECK
        (quantity_requested > 0 AND quantity_reserved >= 0 AND quantity_consumed >= 0
         AND quantity_reserved + quantity_consumed <= quantity_requested),
    CONSTRAINT ck_stock_reservation_status CHECK
        (status IN ('ACTIVE', 'PARTIAL', 'CONSUMED', 'RELEASED', 'EXPIRED', 'CANCELLED')),
    CONSTRAINT uq_stock_reservation_key UNIQUE (tenant_id, reservation_key)
);

CREATE INDEX IF NOT EXISTS ix_stock_reservation_expiry
    ON inventory_core.stock_reservation (tenant_id, status, expires_at);

-- Event terpisah diperlukan karena satu reservation_key dapat menerima banyak
-- operasi RELEASE/CONSUME. Unique idempotency berlaku per operasi, bukan hanya
-- pada state reservasi terakhir.
CREATE TABLE IF NOT EXISTS inventory_core.stock_reservation_event (
    id                bigserial PRIMARY KEY,
    tenant_id         bigint NOT NULL,
    reservation_id    bigint NOT NULL,
    action_type       varchar(20) NOT NULL,
    quantity          numeric(24,6) NOT NULL,
    idempotency_key   varchar(200) NOT NULL,
    occurred_at       timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT fk_stock_reservation_event_reservation FOREIGN KEY (reservation_id)
        REFERENCES inventory_core.stock_reservation(id),
    CONSTRAINT ck_stock_reservation_event_action CHECK
        (action_type IN ('RESERVE', 'RELEASE', 'CONSUME', 'EXPIRE', 'CANCEL')),
    CONSTRAINT ck_stock_reservation_event_quantity CHECK (quantity > 0),
    CONSTRAINT uq_stock_reservation_event_idempotency UNIQUE
        (tenant_id, idempotency_key)
);

-- Foreign key ke tabel tenant, lokasi, item, dan UOM kanonis sengaja belum
-- ditambahkan pada draft ini. Nama tabel/ID fisiknya harus berasal dari hasil
-- keputusan Fase 2; menebak relasi berisiko mencampur Produk dan MasterAsset.

-- ROLLBACK (jalankan hanya pada lingkungan yang dipastikan belum berisi data):
-- DROP TABLE inventory_core.stock_reservation_event;
-- DROP TABLE inventory_core.stock_reservation;
-- DROP TABLE inventory_core.stock_ledger;
-- DROP TABLE inventory_core.stock_balance;
-- DROP TABLE inventory_core.inventory_lot;
-- DROP SCHEMA inventory_core;
