-- Fase 2 preflight — READ ONLY.
-- Jalankan pada salinan/snapshot database, bukan langsung pada produksi.
BEGIN TRANSACTION READ ONLY;

-- 1. Baseline row count.
SELECT 'koperasi.produk' AS sumber, count(*) AS jumlah FROM koperasi.produk
UNION ALL
SELECT 'asset.master_asset', count(*) FROM asset.master_asset
UNION ALL
SELECT 'koperasi.toko', count(*) FROM koperasi.toko
UNION ALL
SELECT 'sirs.gudang', count(*) FROM sirs.gudang
UNION ALL
SELECT 'koperasi.satuan_produk', count(*) FROM koperasi.satuan_produk
UNION ALL
SELECT 'sirs.satuan_item', count(*) FROM sirs.satuan_item;

-- 2. Kode produk ganda dalam satu toko. NULL/kosong dilaporkan terpisah.
SELECT toko, lower(trim(kode)) AS kode_normal, count(*) AS jumlah,
       array_agg(id ORDER BY id) AS ids
FROM koperasi.produk
WHERE nullif(trim(kode), '') IS NOT NULL
GROUP BY toko, lower(trim(kode))
HAVING count(*) > 1
ORDER BY count(*) DESC, toko, kode_normal;

SELECT toko,
       count(*) FILTER (WHERE kode IS NULL OR trim(kode) = '') AS kode_kosong,
       count(*) FILTER (WHERE barcode IS NULL OR trim(barcode) = '') AS barcode_kosong
FROM koperasi.produk
GROUP BY toko
ORDER BY toko;

-- 3. Barcode ganda dalam satu toko.
SELECT toko, lower(trim(barcode)) AS barcode_normal, count(*) AS jumlah,
       array_agg(id ORDER BY id) AS ids
FROM koperasi.produk
WHERE nullif(trim(barcode), '') IS NOT NULL
GROUP BY toko, lower(trim(barcode))
HAVING count(*) > 1
ORDER BY count(*) DESC, toko, barcode_normal;

-- 4. Produk menunjuk toko/master asset/satuan yang tidak ada.
SELECT p.id, p.kode, p.nama, p.toko
FROM koperasi.produk p
LEFT JOIN koperasi.toko t ON t.id = p.toko
WHERE p.toko IS NOT NULL AND t.id IS NULL
ORDER BY p.id;

SELECT p.id, p.kode, p.nama, p.master_asset
FROM koperasi.produk p
LEFT JOIN asset.master_asset a ON a.id = p.master_asset
WHERE p.master_asset IS NOT NULL AND a.id IS NULL
ORDER BY p.id;

SELECT p.id, p.kode, p.nama, p.satuan
FROM koperasi.produk p
LEFT JOIN koperasi.satuan_produk s ON s.id = p.satuan
WHERE p.satuan IS NOT NULL AND s.id IS NULL
ORDER BY p.id;

-- 5. Satu MasterAsset dipetakan ke banyak Produk. Ini tidak selalu salah, tetapi
-- wajib diberi scope/varian dan tidak boleh otomatis digabung berdasarkan nama.
SELECT p.master_asset, count(*) AS jumlah_produk,
       count(DISTINCT p.toko) AS jumlah_toko,
       array_agg(p.id ORDER BY p.id) AS produk_ids
FROM koperasi.produk p
WHERE p.master_asset IS NOT NULL
GROUP BY p.master_asset
HAVING count(*) > 1
ORDER BY count(*) DESC, p.master_asset;

-- 6. Kode gudang ganda/kosong dan relasi induk orphan.
SELECT lower(trim(kode)) AS kode_normal, count(*) AS jumlah,
       array_agg(id ORDER BY id) AS ids
FROM sirs.gudang
WHERE nullif(trim(kode), '') IS NOT NULL
GROUP BY lower(trim(kode))
HAVING count(*) > 1
ORDER BY count(*) DESC, kode_normal;

SELECT id, kode, nama FROM sirs.gudang
WHERE kode IS NULL OR trim(kode) = ''
ORDER BY id;

SELECT g.id, g.kode, g.nama, g.gudang_induk
FROM sirs.gudang g
LEFT JOIN sirs.gudang induk ON induk.id = g.gudang_induk
WHERE g.gudang_induk IS NOT NULL AND induk.id IS NULL
ORDER BY g.id;

-- 7. Outlet dengan gudang pemasok orphan.
SELECT t.id, t.kode, t.nama, t.gudang_pemasok
FROM koperasi.toko t
LEFT JOIN sirs.gudang g ON g.id = t.gudang_pemasok
WHERE t.gudang_pemasok IS NOT NULL AND g.id IS NULL
ORDER BY t.id;

-- 8. Nama UOM ganda setelah normalisasi. Hasil ini menjadi bahan mapping, bukan
-- alasan menghapus satuan secara otomatis.
SELECT lower(trim(nama)) AS nama_normal, count(*) AS jumlah,
       array_agg(id ORDER BY id) AS ids
FROM koperasi.satuan_produk
WHERE nullif(trim(nama), '') IS NOT NULL
GROUP BY lower(trim(nama))
HAVING count(*) > 1
ORDER BY count(*) DESC, nama_normal;

SELECT lower(trim(nama)) AS nama_normal, count(*) AS jumlah,
       array_agg(id ORDER BY id) AS ids
FROM sirs.satuan_item
WHERE nullif(trim(nama), '') IS NOT NULL
GROUP BY lower(trim(nama))
HAVING count(*) > 1
ORDER BY count(*) DESC, nama_normal;

-- 9. Kandidat mapping nama lintas domain. Jangan dipakai sebagai UPDATE otomatis.
SELECT p.id AS produk_id, p.toko, p.kode AS produk_kode, p.nama AS produk_nama,
       a.id AS master_asset_id, a.kode AS asset_kode, a.nama AS asset_nama
FROM koperasi.produk p
JOIN asset.master_asset a ON lower(trim(a.nama)) = lower(trim(p.nama))
WHERE p.master_asset IS NULL
ORDER BY p.id, a.id;

ROLLBACK;
