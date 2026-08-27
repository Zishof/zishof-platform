# Fase 3: fondasi shadow-write dan rekonsiliasi inventory ledger

Tanggal: 26 Agustus 2026

## Status implementasi

Fondasi layanan shadow-write dan rekonsiliasi sudah tersedia serta lulus UAT kontrak Java 1.7. Implementasi ini **belum dihubungkan ke writer transaksi produksi**, belum mengaktifkan feature flag, dan tidak menjalankan DDL/DML pada database produksi.

Jalur legacy tetap menjadi sumber kebenaran. Shadow-write hanya boleh dipanggil **setelah transaksi legacy berhasil commit**. Kegagalan ledger bayangan maupun audit tidak boleh mengubah hasil transaksi legacy yang sudah berhasil.

## Urutan eksekusi yang diwajibkan

1. Writer legacy memvalidasi dan menyimpan transaksi lama.
2. Writer legacy melakukan commit.
3. Setelah commit berhasil, aplikasi membentuk `InventoryMovementCommand` dengan idempotency key stabil.
4. `InventoryShadowWriteService` mencoba posting ke ledger baru bila feature flag writer aktif.
5. Hasil POSTED, ALREADY_POSTED, REJECTED, atau FAILED dicatat melalui port audit.
6. `InventoryReconciliationService` membandingkan saldo legacy dan ledger secara read-only per tenant, lokasi, item, dan lot.
7. Selisih hanya dilaporkan. Fondasi ini tidak melakukan koreksi saldo otomatis.

## Kelas yang ditambahkan

- `InventoryShadowWriteSettings`: feature flag dan kode writer; default aman melalui `disabled(...)`.
- `InventoryLegacyBalancePort`: kontrak pembaca saldo legacy tanpa mutasi.
- `InventoryShadowAuditPort`: tujuan audit yang berada di luar transaksi legacy.
- `InventoryShadowWriteResult`: status terstruktur DISABLED, POSTED, ALREADY_POSTED, REJECTED, dan FAILED.
- `InventoryShadowWriteService`: eksekutor pasca-commit yang menahan seluruh kegagalan shadow agar tidak merusak transaksi legacy.
- `InventoryReconciliationResult`: hasil MATCHED, MISMATCH, atau FAILED beserta kedua saldo dan selisih.
- `InventoryReconciliationService`: pembanding read-only saldo ledger terhadap saldo legacy.

Source kanonis berada di `C:\opt\AIS\ais\src\main\src\ais\common\inventory\shadow` dan mirror kompatibilitas berada di `C:\opt\AIS\ais\src\main\java\ais\common\inventory\shadow`. Kedua mirror telah diverifikasi identik SHA-256.

## Invarian keselamatan

- Legacy tetap otoritatif sampai cutover resmi.
- Shadow-write tidak boleh dijalankan sebelum commit legacy.
- Feature flag per writer default nonaktif.
- Retry wajib memakai idempotency key yang sama; ALREADY_POSTED adalah hasil sukses idempoten, bukan kegagalan.
- Scope saldo selalu tenant + lokasi + item + lot.
- Rekonsiliasi tidak boleh menulis atau mengoreksi saldo.
- Kegagalan audit tidak boleh dilempar kembali ke transaksi legacy.
- Tidak ada `openSession()` atau `currentNativeSession()` pada layanan ini.
- Implementasi tetap Java 1.7 dan gaya Java 1.6 tanpa lambda, stream, diamond operator, atau try-with-resources.

## UAT

Kompilasi dilakukan dengan `javac -source 1.7 -target 1.7`.

- Feature flag nonaktif tidak memanggil posting port: **LULUS**.
- POSTED dan ALREADY_POSTED dipetakan sebagai sukses: **LULUS**.
- REJECTED dipertahankan sebagai penolakan terstruktur: **LULUS**.
- Runtime exception pada ledger menjadi FAILED tanpa keluar ke transaksi legacy: **LULUS**.
- Runtime exception pada audit tidak keluar dan tercatat pada pesan hasil: **LULUS**.
- Rekonsiliasi menganggap `10.0` dan `10.00` sama secara numerik: **LULUS**.
- Rekonsiliasi menghitung selisih ledger dikurangi legacy: **LULUS**.
- Rekonsiliasi tetap read-only pada MATCHED, MISMATCH, dan FAILED: **LULUS**.
- Seluruh UAT domain inventory sebelumnya: **LULUS**.
- UAT adapter PostgreSQL: **SKIPPED secara aman**, menunggu URL database UAT eksplisit.

## Gerbang sebelum integrasi writer produksi

1. Review dan jalankan draft DDL hanya pada database staging/UAT.
2. Jalankan UAT adapter dua koneksi sampai benar-benar LULUS, bukan SKIPPED.
3. Pilih satu writer bervolume rendah dan berisiko rendah sebagai pilot.
4. Panggil shadow service hanya dari callback/alur yang terbukti berjalan setelah commit legacy.
5. Gunakan feature flag khusus writer, default OFF, dengan rollback cukup menonaktifkan flag.
6. Pantau jumlah POSTED, ALREADY_POSTED, REJECTED, FAILED, dan kegagalan audit.
7. Rekonsiliasi harus mencapai nol mismatch pada periode pilot yang disepakati sebelum memperluas writer.
8. Jangan menjadikan ledger baru sebagai sumber kebenaran sebelum backfill, rekonsiliasi, canary, dan sign-off selesai.

## Kelanjutan yang direkomendasikan

Langkah berikutnya adalah menyiapkan database UAT inventory ledger, menjalankan migration draft yang telah direview, mengeksekusi harness dua koneksi, kemudian menghubungkan **satu** writer pilot ke `InventoryShadowWriteService` dalam keadaan feature flag nonaktif.
