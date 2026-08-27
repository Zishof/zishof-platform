-- Draft skema Fase 10: Accounts Payable dan integrasi akuntansi.
-- DOKUMEN REVIEW SAJA. Jangan dijalankan langsung pada produksi.
-- Semua writer baru harus aktif melalui feature flag setelah rekonsiliasi staging lulus.

CREATE TABLE IF NOT EXISTS ap_invoice (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    vendor_id bigint NOT NULL,
    nomor_invoice_vendor varchar(120) NOT NULL,
    mata_uang varchar(8) NOT NULL DEFAULT 'IDR',
    tanggal_invoice timestamp without time zone NOT NULL,
    tanggal_jatuh_tempo timestamp without time zone,
    nilai_bruto numeric(19,2) NOT NULL DEFAULT 0,
    nilai_dibayar numeric(19,2) NOT NULL DEFAULT 0,
    nilai_kredit numeric(19,2) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    legacy_saldo_awal_master_asset_id bigint,
    dibuat_oleh varchar(100) NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    diubah_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_ap_invoice_vendor_number UNIQUE (tenant_id, vendor_id, nomor_invoice_vendor),
    CONSTRAINT ck_ap_invoice_amount CHECK (nilai_bruto >= 0 AND nilai_dibayar >= 0 AND nilai_kredit >= 0),
    CONSTRAINT ck_ap_invoice_open CHECK (nilai_dibayar + nilai_kredit <= nilai_bruto)
);

CREATE TABLE IF NOT EXISTS ap_invoice_line (
    id bigserial PRIMARY KEY,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    nomor_baris integer NOT NULL,
    po_detail_id bigint,
    receipt_detail_id bigint,
    item_type varchar(40),
    item_id bigint,
    deskripsi varchar(500),
    qty numeric(19,6) NOT NULL,
    harga_satuan numeric(19,2) NOT NULL,
    pajak numeric(19,2) NOT NULL DEFAULT 0,
    nilai_baris numeric(19,2) NOT NULL,
    CONSTRAINT uq_ap_invoice_line UNIQUE (invoice_id, nomor_baris),
    CONSTRAINT ck_ap_invoice_line_qty CHECK (qty > 0)
);

CREATE TABLE IF NOT EXISTS ap_match_result (
    id bigserial PRIMARY KEY,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    status varchar(30) NOT NULL,
    toleransi_qty numeric(19,6) NOT NULL DEFAULT 0,
    toleransi_nilai numeric(19,2) NOT NULL DEFAULT 0,
    diperiksa_oleh varchar(100),
    diperiksa_pada timestamp without time zone NOT NULL DEFAULT now(),
    versi integer NOT NULL DEFAULT 1,
    CONSTRAINT uq_ap_match_result_version UNIQUE (invoice_id, versi)
);

CREATE TABLE IF NOT EXISTS ap_match_line (
    id bigserial PRIMARY KEY,
    match_result_id bigint NOT NULL REFERENCES ap_match_result(id),
    invoice_line_id bigint NOT NULL REFERENCES ap_invoice_line(id),
    qty_po numeric(19,6),
    qty_receipt numeric(19,6),
    qty_invoice numeric(19,6) NOT NULL,
    nilai_po numeric(19,2),
    nilai_invoice numeric(19,2) NOT NULL,
    status varchar(30) NOT NULL,
    alasan varchar(1000),
    CONSTRAINT uq_ap_match_line UNIQUE (match_result_id, invoice_line_id)
);

CREATE TABLE IF NOT EXISTS ap_dispute (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    jenis varchar(40) NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    uraian varchar(2000) NOT NULL,
    penyelesaian varchar(2000),
    dibuat_oleh varchar(100) NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    diselesaikan_pada timestamp without time zone
);

CREATE TABLE IF NOT EXISTS ap_payment_schedule (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    urutan integer NOT NULL,
    tanggal_jatuh_tempo date NOT NULL,
    nilai numeric(19,2) NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    CONSTRAINT uq_ap_payment_schedule UNIQUE (invoice_id, urutan),
    CONSTRAINT ck_ap_payment_schedule_amount CHECK (nilai > 0)
);

CREATE TABLE IF NOT EXISTS ap_credit_note (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    nomor_credit_note varchar(120) NOT NULL,
    nilai numeric(19,2) NOT NULL,
    tanggal_credit_note timestamp without time zone NOT NULL,
    alasan varchar(1000) NOT NULL,
    idempotency_key varchar(180) NOT NULL,
    CONSTRAINT uq_ap_credit_note_number UNIQUE (tenant_id, nomor_credit_note),
    CONSTRAINT uq_ap_credit_note_idempotency UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_ap_credit_note_amount CHECK (nilai > 0)
);

CREATE TABLE IF NOT EXISTS ap_payment_allocation (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    nilai numeric(19,2) NOT NULL,
    dibayar_pada timestamp without time zone NOT NULL,
    proses_transfer_id bigint,
    daftar_pengajuan_transfer_id bigint,
    idempotency_key varchar(180) NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_ap_payment_allocation_idempotency UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_ap_payment_allocation_amount CHECK (nilai > 0)
);

CREATE TABLE IF NOT EXISTS accounting_posting_source (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    source_type varchar(50) NOT NULL,
    source_id varchar(120) NOT NULL,
    event_type varchar(50) NOT NULL,
    journal_id bigint,
    idempotency_key varchar(180) NOT NULL,
    nilai numeric(19,2) NOT NULL,
    tanggal_posting timestamp without time zone NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_accounting_posting_source UNIQUE (tenant_id, source_type, source_id, event_type),
    CONSTRAINT uq_accounting_posting_idempotency UNIQUE (tenant_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS accounting_posting_job (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    source_type varchar(50) NOT NULL,
    source_id varchar(120) NOT NULL,
    event_type varchar(50) NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    attempt_count integer NOT NULL DEFAULT 0,
    next_attempt_at timestamp without time zone,
    last_error varchar(2000),
    idempotency_key varchar(180) NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    diubah_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_accounting_posting_job UNIQUE (tenant_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS accounting_posting_reversal (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    posting_source_id bigint NOT NULL REFERENCES accounting_posting_source(id),
    reversal_posting_source_id bigint REFERENCES accounting_posting_source(id),
    alasan varchar(1000) NOT NULL,
    dibuat_oleh varchar(100) NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_accounting_posting_reversal UNIQUE (tenant_id, posting_source_id)
);

CREATE TABLE IF NOT EXISTS inventory_valuation_layer (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    location_type varchar(40) NOT NULL,
    location_id bigint NOT NULL,
    item_type varchar(40) NOT NULL,
    item_id bigint NOT NULL,
    lot_id bigint,
    movement_id bigint NOT NULL,
    qty_masuk numeric(19,6) NOT NULL DEFAULT 0,
    qty_keluar numeric(19,6) NOT NULL DEFAULT 0,
    biaya_satuan numeric(19,6) NOT NULL,
    nilai_layer numeric(19,2) NOT NULL,
    metode varchar(20) NOT NULL,
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_inventory_valuation_movement UNIQUE (tenant_id, movement_id)
);

CREATE TABLE IF NOT EXISTS accounting_period_lock (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    periode_mulai date NOT NULL,
    periode_sampai date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    dikunci_oleh varchar(100),
    dikunci_pada timestamp without time zone,
    alasan varchar(1000),
    CONSTRAINT uq_accounting_period_lock UNIQUE (tenant_id, periode_mulai, periode_sampai),
    CONSTRAINT ck_accounting_period_range CHECK (periode_sampai >= periode_mulai)
);

CREATE TABLE IF NOT EXISTS ap_event (
    id bigserial PRIMARY KEY,
    tenant_id bigint NOT NULL,
    invoice_id bigint NOT NULL REFERENCES ap_invoice(id),
    event_type varchar(50) NOT NULL,
    payload_json text,
    idempotency_key varchar(180) NOT NULL,
    dibuat_oleh varchar(100),
    dibuat_pada timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT uq_ap_event_idempotency UNIQUE (tenant_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS ix_ap_invoice_status_due
    ON ap_invoice (tenant_id, status, tanggal_jatuh_tempo);
CREATE INDEX IF NOT EXISTS ix_ap_invoice_vendor_date
    ON ap_invoice (tenant_id, vendor_id, tanggal_invoice);
CREATE INDEX IF NOT EXISTS ix_ap_payment_schedule_due
    ON ap_payment_schedule (tenant_id, status, tanggal_jatuh_tempo);
CREATE INDEX IF NOT EXISTS ix_ap_dispute_status
    ON ap_dispute (tenant_id, status, dibuat_pada);
CREATE INDEX IF NOT EXISTS ix_accounting_posting_job_queue
    ON accounting_posting_job (status, next_attempt_at);
CREATE INDEX IF NOT EXISTS ix_inventory_valuation_item
    ON inventory_valuation_layer (tenant_id, location_type, location_id, item_type, item_id, lot_id);

-- Catatan cutover:
-- 1. SaldoAwalMasterAsset tetap dibaca sebagai sumber legacy selama shadow-read.
-- 2. Setelah satu periode rekonsiliasi disetujui, tandai writer invoice vendor legacy RETIRE-WRITE.
-- 3. ProsesTransfer dan DaftarPengajuanTransfer tetap menjadi eksekutor pembayaran;
--    ap_payment_allocation hanya mencatat hubungan pembayaran ke invoice secara idempoten.
-- 4. Reversal membuat posting lawan; jurnal lama tidak boleh dihapus.
