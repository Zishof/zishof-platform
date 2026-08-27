# ADR: Kontrak posting persediaan idempoten sebelum ledger terpadu

- Status: **Accepted for implementation foundation**
- Tanggal: 26 Agustus 2026
- Ruang lingkup: Fase 3 blueprint Pengadaan–Pergudangan–Distribusi–Produksi–POS

## Context

Mutasi stok saat ini berasal dari beberapa modul dan model data existing. Migrasi langsung semua writer ke tabel ledger baru berisiko menggandakan stok, menghilangkan histori, atau mencampur identitas `MasterAsset` dengan `Produk`. Pada saat yang sama, retry dari jaringan, POS offline, integrasi pengiriman, dan proses penerimaan mengharuskan posting aman bila pesan yang sama dikirim ulang.

## Decision

1. Semua writer baru menuju satu port aplikasi `InventoryPostingPort`.
2. Perintah posting menggunakan `InventoryMovementCommand` yang immutable dan memuat tenant, lokasi, item, UOM, lot opsional, kuantitas, jenis/ID sumber, kunci idempotensi, dan waktu bisnis.
3. Hasil posting harus eksplisit: `POSTED`, `ALREADY_POSTED`, atau `REJECTED`.
4. Kunci idempotensi adalah wajib. Implementasi database nantinya harus menegakkan unique constraint dalam lingkup tenant.
5. Kontrak ini tidak memilih tabel fisik sebelum hasil preflight struktur existing diverifikasi.
6. Adaptor writer lama ditambahkan bertahap dengan shadow-write dan rekonsiliasi; tidak ada penggantian big-bang.
7. `Produk` dan `MasterAsset` tidak boleh disatukan secara implisit. Mapping identitas item harus eksplisit dan dapat diaudit.

## Consequences

### Positive

- Retry aman dan dapat dibedakan dari posting baru.
- Modul gudang, distribusi, produksi, dan POS berbagi semantik mutasi yang sama.
- Kontrak dapat diuji tanpa database dan tetap kompatibel Java 1.7.
- Implementasi fisik ledger dapat berubah tanpa mengubah pemanggil.

### Negative

- Diperlukan adaptor sementara untuk writer existing.
- Rekonsiliasi shadow-write menambah pekerjaan operasional sebelum cutover.
- Unique key dan indeks akan menambah beban tulis; desainnya harus diuji pada volume produksi.

### Risks and mitigations

- **Kunci idempotensi salah lingkup:** wajib memasukkan tenant dan sumber bisnis pada desain unique key.
- **Dua identitas item menunjuk barang berbeda:** blok posting bila mapping ambigu.
- **Saldo ledger berbeda dari saldo existing:** jangan cutover sampai rekonsiliasi berulang menghasilkan selisih nol atau pengecualian terdokumentasi.

## Alternatives considered

1. **Langsung menulis ke tabel stok existing.** Ditolak karena mempertahankan coupling dan tidak memberi idempotensi lintas modul.
2. **Membuat tabel transaksi per tanggal.** Ditolak karena memperumit constraint, migrasi, query lintas periode, serta deduplikasi. Gunakan tabel stabil dan partisi native hanya setelah kebutuhan volume terbukti.
3. **Satu transaksi database lintas seluruh modul.** Ditolak untuk proses offline/asinkron; terlalu rapuh terhadap batas sistem dan retry.
4. **Event bus lebih dahulu.** Ditunda. Outbox/event dapat ditambahkan setelah kontrak posting dan sumber kebenaran stabil.

## Validation

- UAT kontrak Java: `InventoryMovementContractUat`.
- Audit database read-only: `2026-08-26-fase-3-preflight-inventory-ledger.sql`.
- Gerbang sebelum implementasi database: pemetaan identitas, DDL review, idempotency concurrency test, shadow-write, dan rekonsiliasi saldo.
