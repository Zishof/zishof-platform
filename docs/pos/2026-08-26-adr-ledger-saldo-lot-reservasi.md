# ADR: ledger append-only dengan saldo transaksional, lot, dan reservasi terpisah

Status: **Accepted untuk implementasi bertahap; migration belum di-deploy**  
Date: 26 Agustus 2026  
Deciders: Tim eBisnis/AIS, pemilik modul Persediaan, Pengadaan, Pergudangan, Distribusi, Produksi, dan POS

## Context

Stok saat ini berubah melalui banyak writer legacy: pengadaan, opname, penjualan, retur, mutasi outlet, pemakaian bahan, dan proses lain. Model saldo langsung tanpa jejak kanonis menyulitkan retry aman, rekonsiliasi, penelusuran lot, serta pencegahan stok teralokasi ganda. Fase 2 juga menetapkan bahwa identitas Produk, MasterAsset, lokasi, UOM, dan tenant tidak boleh disamakan hanya berdasarkan ID numerik atau nama.

Fase 3 membutuhkan sumber kebenaran yang dapat diaudit, pembacaan saldo yang tetap cepat, dan reservasi yang cocok untuk allocation/picking tanpa memaksa cutover besar pada seluruh writer lama sekaligus. Java server tetap harus kompatibel Java 1.7.

## Decision

1. Setiap mutasi baru dicatat sebagai baris append-only di `stock_ledger`.
2. `stock_balance` menjadi proyeksi transaksional untuk pembacaan cepat, bukan pengganti ledger. Insert ledger dan update saldo dilakukan atomik oleh satu repository.
3. Unique constraint `(tenant_id, idempotency_key)` menjadi pengaman akhir retry dan race. Implementasi tidak boleh hanya mengandalkan pola check-then-insert.
4. Saldo dibedakan oleh tenant, lokasi, item, dan lot nullable. Barang tanpa lot tetap hanya memiliki satu baris saldo melalui unique expression `COALESCE(lot_id, 0)`.
5. Lot dan status kualitas disimpan terpisah. Reservasi memiliki current state serta event append-only dengan idempotency per operasi RESERVE/RELEASE/CONSUME.
6. Tabel tidak dipecah per tanggal. Partisi waktu baru dipertimbangkan setelah metrik volume membuktikan kebutuhan; consumer tetap memakai satu kontrak repository.
7. Writer legacy dimigrasikan bertahap melalui `InventoryPostingPort`, dimulai shadow-write dan rekonsiliasi sebelum ledger menjadi sumber utama.

## Options considered

| Opsi | Konsistensi/audit | Performa baca | Kompleksitas migrasi | Retry/concurrency | Keputusan |
|---|---|---:|---:|---:|---|
| Saldo langsung tanpa ledger | Rendah; asal perubahan sulit dibuktikan | Tinggi | Rendah | Rentan double update | Ditolak |
| Full event sourcing untuk semua modul | Sangat tinggi | Memerlukan proyeksi luas | Sangat tinggi dan big-bang | Baik bila seluruh sistem berubah | Ditunda |
| Ledger append-only + saldo transaksional | Tinggi dan dapat direkonsiliasi | Tinggi | Sedang, dapat bertahap | Baik dengan unique constraint | Dipilih |
| Tabel ledger per hari/tanggal | Audit tersebar, query lintas tanggal rumit | Tidak stabil | Tinggi secara operasional | Idempotensi lintas tabel sulit | Ditolak |

## Trade-off analysis

- Dua representasi—ledger dan saldo—menambah kewajiban konsistensi, tetapi transaksi atomik dan rekonsiliasi memberi kontrol yang tidak tersedia pada saldo langsung.
- Unique constraint dapat menghasilkan conflict pada retry bersamaan; repository harus menangkap conflict lalu mengembalikan movement yang sudah ada sebagai `ALREADY_POSTED`.
- Lot meningkatkan jumlah baris saldo dan kompleksitas FEFO, tetapi diperlukan untuk kedaluwarsa, karantina, recall, dan traceability.
- Reservasi mengurangi `available quantity` tanpa mengubah on-hand. Hal ini mencegah over-allocation, tetapi membutuhkan proses expiry/release yang diaudit.
- Skema additif menjaga kompatibilitas writer lama, dengan konsekuensi adanya periode shadow-write dan rekonsiliasi.

## Consequences

Positif:

- Satu mutasi dapat dilacak ke source document dan correlation ID.
- Retry jaringan, klik ganda, dan dua thread tidak menggandakan stok.
- Saldo tetap cepat untuk POS/WMS, sedangkan ledger menjadi bukti audit.
- Lot, karantina, FEFO, reservasi, dan rekonsiliasi memiliki fondasi bersama.
- Struktur tidak memerlukan `UNION ALL` dinamis lintas tabel harian.

Negatif/risiko:

- Semua writer yang bermigrasi harus disiplin membentuk idempotency key stabil.
- Deadlock dan hot row mungkin terjadi pada item/lokasi ramai; urutan lock dan retry terbatas harus distandardisasi.
- Backfill tidak boleh langsung dipercaya sebelum total per tenant/lokasi/item/lot cocok dengan sumber existing.
- Foreign key identitas kanonis belum boleh ditetapkan sebelum keputusan fisik Fase 2 selesai.

## Action items

1. Review draft `2026-08-26-fase-3-schema-inventory-ledger.sql` terhadap hasil preflight staging.
2. Implementasikan adaptor repository PostgreSQL dengan transaksi atomik, lock saldo, insert ledger, update saldo, dan handling unique conflict.
3. Tambahkan integration test database nyata untuk dua koneksi bersamaan dengan idempotency key sama.
4. Tentukan format idempotency key per writer pada mutation writer register.
5. Pilih satu writer berisiko rendah untuk shadow-write dan bandingkan saldo tanpa memengaruhi transaksi lama.
6. Tambahkan job expiry reservasi yang mem-posting event RELEASE/EXPIRE secara idempoten.
7. Aktifkan cutover hanya setelah rekonsiliasi nol selisih dan rollback teruji.
