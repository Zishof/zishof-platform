# Importer Tenant AB Chicken: Lokal ke Produksi

Importer dipakai nanti setelah calon pelanggan menyetujui cutover. Alat ini tidak mengubah schema tenant lain dan secara default hanya menampilkan rencana.

## Cakupan

- database utama: schema `abchiken` dan, bila ada, `abchiken__audit`;
- database file: schema `abchiken` pada `streaming_ais`;
- backup format custom PostgreSQL, checksum SHA-256, restore tanpa owner/privilege lokal;
- target wajib belum mempunyai schema tersebut; importer berhenti bila target sudah ada;
- rekonsiliasi minimal outlet, menu, bahan, pengiriman, dan payload lampiran setelah restore.

## Dry-run

```powershell
& 'C:\opt\AIS\ais\script\abchicken\migrate_abchiken_to_production.ps1'
```

Dry-run menampilkan sumber, target yang masih perlu diisi, schema, dan strategi. Tidak membuat arsip dan tidak menyentuh database.

## Eksekusi terkontrol

Siapkan dua `PGPASSFILE`: satu untuk sumber lokal, satu untuk target produksi. Pastikan file hanya dapat dibaca akun operator. Jangan memasukkan password sebagai parameter atau menyimpannya di repository.

```powershell
$env:ABCHICKEN_DB_USER = '<source-main-user>'
$env:ABCHICKEN_STREAMING_DB_USER = '<source-stream-user>'
$env:ABCHICKEN_SOURCE_PGPASSFILE = '<source-pgpass>'
$env:ABCHICKEN_TARGET_PGPASSFILE = '<target-pgpass>'

& 'C:\opt\AIS\ais\script\abchicken\migrate_abchiken_to_production.ps1' `
  -Execute `
  -TargetMainHost '<host-db-produksi>' `
  -TargetMainUser '<target-main-user>' `
  -TargetStreamingHost '<host-streaming-produksi>' `
  -TargetStreamingUser '<target-stream-user>'
```

Importer sengaja tidak memakai `--clean` dan tidak menimpa schema yang sudah ada. Jika restore berhenti di tengah, jangan langsung menjalankan ulang. Inspeksi schema target, catat tahap terakhir, lalu pilih pemulihan dari backup atau penghapusan schema parsial melalui change approval terpisah.

## Cutover aplikasi

1. Bekukan transaksi demo dan tunggu outbox client kosong.
2. Jalankan verifikasi sumber; semua gerbang wajib lulus.
3. Jalankan importer dan simpan checksum/rekonsiliasi.
4. Konfigurasikan tenant registry, host `abchiken.ebisnis.id`, TLS, dan context `/ebisnis`.
5. Login smoke test dengan role terbatas lalu role admin.
6. Uji satu dokumen baru end-to-end di produksi tanpa mengubah data historis demo.
7. Cocokkan laporan dan lampiran streaming.
8. Buka akses pengguna hanya setelah pemilik bisnis menandatangani hasil rekonsiliasi.

## Rollback

Rollback dilakukan jika count berbeda, checksum arsip tidak cocok, ada relasi putus, file tidak dapat dibuka, tenant bocor, atau jurnal tidak seimbang. DNS belum dialihkan sebelum smoke test lulus. Bila DNS sudah dialihkan, kembalikan ke endpoint sebelumnya, hentikan transaksi tenant AB Chicken, dan pulihkan target berdasarkan backup/catatan perubahan. Jangan menimpa database sumber lokal sampai masa validasi produksi selesai.
