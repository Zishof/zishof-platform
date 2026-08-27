# Fase 3 — Adapter PostgreSQL inventory ledger

Tanggal: 26 Agustus 2026

## Hasil fase

Adapter JDBC PostgreSQL untuk kontrak `InventoryLedgerRepository` telah dibuat pada dua mirror source server. Implementasi ini belum dihubungkan ke writer transaksi produksi dan belum menjalankan DDL pada database produksi.

Tujuan fase ini adalah memastikan fondasi penyimpanan mutasi stok mempunyai sifat berikut:

- satu mutasi, saldo, dan idempotency key diproses dalam satu transaksi database;
- retry dengan payload yang sama tidak membuat ledger atau perubahan saldo kedua;
- pemakaian idempotency key yang sama untuk payload berbeda ditolak;
- race dari dua koneksi ditahan oleh unique constraint dan row lock database;
- seluruh koneksi, statement, dan result set milik adapter ditutup pada blok `finally`;
- kode tetap kompatibel Java 1.7 dan gaya Java 1.6.

## File implementasi

Mirror utama:

- `C:\opt\AIS\ais\src\main\src\ais\common\inventory\jdbc\InventoryJdbcConnectionProvider.java`
- `C:\opt\AIS\ais\src\main\src\ais\common\inventory\jdbc\DriverManagerInventoryConnectionProvider.java`
- `C:\opt\AIS\ais\src\main\src\ais\common\inventory\jdbc\InventoryPersistenceException.java`
- `C:\opt\AIS\ais\src\main\src\ais\common\inventory\jdbc\JdbcInventoryLedgerRepository.java`

Mirror kompatibilitas yang identik berada di `src/main/java/ais/common/inventory/jdbc`.

Harness integrasi:

- `C:\opt\AIS\ais\src\test\java\ais\common\inventory\jdbc\PostgreSqlInventoryLedgerIntegrationUat.java`

## Algoritma transaksi atomik

1. Validasi command dan scope tenant/lokasi/item/UOM.
2. Buka koneksi khusus milik adapter dan matikan auto-commit.
3. Cari ledger dengan pasangan `(tenant_id, idempotency_key)`.
4. Jika ditemukan dan payload sama, kembalikan `ALREADY_POSTED`.
5. Jika ditemukan tetapi payload berbeda, kembalikan `REJECTED`.
6. Pastikan baris saldo tersedia memakai `INSERT ... ON CONFLICT DO NOTHING`.
7. Kunci baris saldo dengan `SELECT ... FOR UPDATE`.
8. Sisipkan ledger dan ambil ID hasil posting.
9. Perbarui saldo dan version.
10. Commit sekali setelah ledger dan saldo berhasil.
11. Jika unique constraint `23505` terjadi akibat race, rollback seluruh percobaan, baca ledger pemenang, lalu klasifikasikan sebagai replay atau konflik payload.

Pendekatan ini menghindari pola rawan `check-then-insert`. Dalam race dua koneksi, koneksi yang kalah tidak dapat meninggalkan kenaikan saldo parsial karena seluruh pekerjaannya di-rollback sebelum membaca hasil pemenang.

## Lifecycle resource

Adapter tidak memakai `openSession()`, `currentNativeSession()`, atau `currentSession()`. Koneksi JDBC dibuka oleh `InventoryJdbcConnectionProvider`, dimiliki adapter, dan selalu ditutup pada `finally`. `PreparedStatement` dan `ResultSet` juga ditutup eksplisit pada `finally`. Tidak digunakan try-with-resources, lambda, diamond operator, atau API Java 8.

## UAT yang dijalankan

Kompilasi:

```text
javac -encoding UTF-8 -source 1.7 -target 1.7
```

Hasil:

- `InventoryMovementContractUat`: **LULUS**.
- `InventoryMasterReferenceContractUat`: **LULUS**.
- `InventoryLedgerDomainContractUat`: **LULUS**.
- `PostgreSqlInventoryLedgerIntegrationUat`: **SKIPPED secara aman**, karena URL database UAT khusus belum diberikan.
- Empat file adapter pada `src/main/src` dan `src/main/java`: **identik SHA-256**.

Harness integrasi hanya boleh dijalankan pada database UAT yang tervalidasi. Ia membuat schema temporer `inventory_uat_*`, menjalankan dua koneksi serentak, memverifikasi satu `POSTED` dan satu `ALREADY_POSTED`, menguji konflik payload, memeriksa saldo dan jumlah ledger, lalu menghapus schema temporer di `finally`.

Contoh eksekusi pada database lokal khusus UAT:

```powershell
java `
  -Dinventory.uat.jdbc.url=jdbc:postgresql://localhost:5432/inventory_uat `
  -Dinventory.uat.jdbc.user=inventory_uat `
  -Dinventory.uat.jdbc.password=PASSWORD_UAT `
  -cp "CLASSES;C:\opt\AIS\ais\src\main\webapp\WEB-INF\lib\postgresql-42.7.13.jar" `
  ais.common.inventory.jdbc.PostgreSqlInventoryLedgerIntegrationUat
```

Target remote ditolak oleh harness kecuali nama database menunjukkan `test`/`uat` dan `-Dinventory.uat.allowRemote=true` diberikan secara eksplisit.

## Gerbang sebelum shadow-write

- Jalankan draft DDL Fase 3 pada salinan/staging setelah review DBA.
- Jalankan harness dua koneksi hingga **LULUS**, bukan `SKIPPED`.
- Simpan bukti saldo akhir, satu baris ledger, dan movement ID yang sama untuk replay.
- Verifikasi query plan index tenant/idempotency dan tenant/lokasi/item/lot.
- Tentukan writer pilot berisiko rendah dan feature flag rollback.
- Jangan mengaktifkan shadow-write pada produksi sebelum rekonsiliasi dan rollback runbook disetujui.

