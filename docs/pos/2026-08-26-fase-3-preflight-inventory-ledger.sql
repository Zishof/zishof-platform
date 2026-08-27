-- Fase 3 - Preflight inventory ledger, saldo, lot, dan reservasi
-- PostgreSQL 13+; READ ONLY. Skrip ini tidak membuat atau mengubah objek/data.
-- Jalankan pada database target sebelum menyusun DDL final.

BEGIN TRANSACTION READ ONLY;

-- 1. Identitas lingkungan. Simpan hasil ini bersama tiket/deployment evidence.
SELECT current_database() AS database_name,
       current_user AS database_user,
       inet_server_addr() AS server_address,
       inet_server_port() AS server_port,
       version() AS database_version,
       clock_timestamp() AS inspected_at;

-- 2. Inventaris tabel yang berpotensi menjadi sumber/target persediaan.
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       CASE c.relkind
           WHEN 'r' THEN 'table'
           WHEN 'p' THEN 'partitioned_table'
           WHEN 'v' THEN 'view'
           WHEN 'm' THEN 'materialized_view'
           ELSE c.relkind::text
       END AS object_type,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       COALESCE(s.n_live_tup, 0) AS estimated_live_rows,
       COALESCE(s.n_dead_tup, 0) AS estimated_dead_rows
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE c.relkind IN ('r', 'p', 'v', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND lower(c.relname) ~ '(produk|item|barang|stok|stock|inventory|mutasi|ledger|saldo|balance|lot|batch|reserv|gudang|warehouse|lokasi|location|satuan|uom|pengadaan|pembelian|penerimaan)'
ORDER BY pg_total_relation_size(c.oid) DESC, n.nspname, c.relname;

-- 3. Kolom domain penting. Hasilnya dipakai untuk memetakan nama existing ke
--    kontrak tenant/location/item/UOM/lot/quantity/source/idempotency/status/date.
SELECT cols.table_schema,
       cols.table_name,
       cols.ordinal_position,
       cols.column_name,
       cols.data_type,
       cols.udt_name,
       cols.is_nullable,
       cols.column_default
FROM information_schema.columns cols
WHERE cols.table_schema NOT IN ('pg_catalog', 'information_schema')
  AND (
      lower(cols.table_name) ~ '(produk|item|barang|stok|stock|inventory|mutasi|ledger|saldo|balance|lot|batch|reserv|gudang|warehouse|lokasi|location|satuan|uom)'
      OR lower(cols.column_name) ~ '(tenant|toko|outlet|cabang|lokasi|location|gudang|warehouse|produk|item|barang|satuan|uom|lot|batch|qty|quantity|jumlah|source|sumber|reference|referensi|idempot|status|waktu|tanggal|created|posted)'
  )
ORDER BY cols.table_schema, cols.table_name, cols.ordinal_position;

-- 4. Primary key, unique constraint, foreign key, dan check constraint.
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       con.conname AS constraint_name,
       CASE con.contype
           WHEN 'p' THEN 'PRIMARY KEY'
           WHEN 'u' THEN 'UNIQUE'
           WHEN 'f' THEN 'FOREIGN KEY'
           WHEN 'c' THEN 'CHECK'
           WHEN 'x' THEN 'EXCLUSION'
           ELSE con.contype::text
       END AS constraint_type,
       pg_get_constraintdef(con.oid, true) AS definition
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND lower(c.relname) ~ '(produk|item|barang|stok|stock|inventory|mutasi|ledger|saldo|balance|lot|batch|reserv|gudang|warehouse|lokasi|location|satuan|uom)'
ORDER BY n.nspname, c.relname, constraint_type, con.conname;

-- 5. Indeks existing, terutama kandidat pencarian saldo dan idempotensi.
SELECT schemaname AS schema_name,
       tablename AS table_name,
       indexname AS index_name,
       indexdef AS index_definition
FROM pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  AND lower(tablename) ~ '(produk|item|barang|stok|stock|inventory|mutasi|ledger|saldo|balance|lot|batch|reserv|gudang|warehouse|lokasi|location|satuan|uom)'
ORDER BY schemaname, tablename, indexname;

-- 6. Deteksi kandidat tabel target bernama umum tanpa mereferensikan tabel
--    yang mungkin belum ada. Rows=0 berarti target memang belum dibuat.
SELECT table_schema,
       table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
  AND lower(table_name) IN (
      'inventory_movement', 'inventory_ledger', 'inventory_balance',
      'inventory_lot', 'inventory_reservation', 'item_identity',
      'stock_location', 'unit_of_measure'
  )
ORDER BY table_schema, table_name;

-- 7. Audit keberadaan pasangan kolom yang diperlukan unique idempotency key.
WITH candidate AS (
    SELECT table_schema,
           table_name,
           bool_or(lower(column_name) IN ('tenant_id', 'tenant', 'toko', 'id_toko')) AS has_tenant,
           bool_or(lower(column_name) IN ('idempotency_key', 'idempotencykey', 'kunci_idempotensi')) AS has_idempotency_key,
           bool_or(lower(column_name) IN ('source_type', 'sumber_tipe', 'jenis_sumber')) AS has_source_type,
           bool_or(lower(column_name) IN ('source_id', 'sumber_id', 'id_sumber', 'reference_id')) AS has_source_id
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    GROUP BY table_schema, table_name
)
SELECT table_schema,
       table_name,
       has_tenant,
       has_idempotency_key,
       has_source_type,
       has_source_id,
       CASE
           WHEN has_tenant AND has_idempotency_key THEN 'READY_FOR_TENANT_IDEMPOTENCY_UNIQUE'
           WHEN has_source_type AND has_source_id THEN 'CAN_DERIVE_SOURCE_IDEMPOTENCY'
           ELSE 'GAP'
       END AS readiness
FROM candidate
WHERE has_idempotency_key OR has_source_type OR has_source_id
ORDER BY readiness, table_schema, table_name;

-- 8. Ringkasan aktivitas tabel untuk menentukan prioritas shadow-write dan
--    rekonsiliasi. Angka bersifat statistik/estimasi, bukan saldo akuntansi.
SELECT schemaname AS schema_name,
       relname AS table_name,
       n_live_tup AS estimated_live_rows,
       seq_scan,
       idx_scan,
       n_tup_ins,
       n_tup_upd,
       n_tup_del,
       last_analyze,
       last_autoanalyze
FROM pg_stat_user_tables
WHERE lower(relname) ~ '(produk|item|barang|stok|stock|inventory|mutasi|ledger|saldo|balance|lot|batch|reserv)'
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC, schemaname, relname;

ROLLBACK;
