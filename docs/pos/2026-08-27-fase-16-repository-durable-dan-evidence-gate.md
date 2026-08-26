# Fase 16 — Repository Durable dan Evidence Gate Fail-Closed

Tanggal: 27 Agustus 2026
Status: fondasi kode dan UAT statis selesai; integrasi runtime/staging belum diaktifkan

## Tujuan

Fase ini menghubungkan journal evidence migrasi immutable dari Fase 15 dengan sebuah repository durable dan gerbang eksekusi. Mutasi tahap migrasi tidak boleh berjalan bila identitas aktor tidak sah, journal rusak, scope tidak sesuai, atau evidence tidak dapat disimpan.

## Keputusan arsitektur

1. Penyimpanan evidence diakses melalui `EbisnisMigrationEvidenceRepository`, bukan langsung melalui file atau database dari orchestrator.
2. Implementasi awal `FileEbisnisMigrationEvidenceRepository` menyimpan setiap scope pada journal terpisah di bawah root kanonis yang telah ditentukan operator.
3. Nama scope disanitasi dan diverifikasi agar tidak dapat keluar dari root repository.
4. `EbisnisMigrationEvidenceGate` melakukan validasi aktor dan verifikasi journal sebelum action dijalankan.
5. Status `PREPARED`, `FAILED`, dan `APPLIED` dicatat secara append-only. Kegagalan menulis evidence membuat gate gagal tertutup (*fail-closed*).
6. Retry menggunakan event/idempotency key yang sama. Action yang dipasang pada gate wajib idempoten karena kegagalan setelah action selesai tetapi sebelum evidence `APPLIED` durable dapat menyebabkan action dijalankan ulang.
7. Implementasi file adalah fondasi lokal/staging. Produksi tetap memerlukan storage WORM atau repository database yang diaudit, backup, retention, monitoring, dan akses least-privilege.

## Kontrak keamanan dan konsistensi

- Aktor kosong, tidak aktif, atau tidak berwenang ditolak sebelum mutasi.
- Journal diverifikasi sebelum dipakai; hash chain rusak, record terpotong, atau konflik event ditolak.
- Scope tenant/lokasi/tahap tidak boleh bercampur dalam satu file.
- Hasil retry yang sudah `APPLIED` dikembalikan tanpa menggandakan action.
- Exception action menghasilkan evidence `FAILED` dan diteruskan ke pemanggil.
- Exception repository tidak diubah menjadi sukses semu.
- Metrik gate membedakan prepared, applied, failed, rejected, dan idempotent replay.

## Berkas implementasi

- `ais/common/EbisnisMigrationEvidenceRepository.java`
- `ais/common/FileEbisnisMigrationEvidenceRepository.java`
- `ais/common/EbisnisMigrationEvidenceGate.java`
- `ais/common/test/EbisnisMigrationEvidenceGateSelfTest.java`

Fase 16 bergantung pada:

- `ais/common/EbisnisMigrationEvidenceJournal.java`
- kontrak rollout Fase 13;
- kontrak stabilisasi/dekomisioning Fase 14.

## UAT yang dijalankan

Kompilasi dilakukan ke direktori eksternal `C:\opt\AIS\ais\.codex-build`, bukan ke source tree, dengan `javac -source 1.7 -target 1.7`.

Hasil:

- `EbisnisMigrationEvidenceGateSelfTest`: **LULUS, 30 pemeriksaan**.
- Regresi Fase 15: **LULUS, 25 pemeriksaan**.
- Regresi Fase 13: **LULUS, 57 pemeriksaan**.
- Regresi Fase 14: **LULUS, 43 pemeriksaan**.
- Tidak ada file `.class` di bawah direktori source Java setelah verifikasi.

Skenario yang diuji mencakup:

- aktor sah dan tidak sah;
- scope terisolasi;
- action sukses dan gagal;
- retry idempoten;
- kegagalan append evidence;
- journal yang telah dirusak;
- metrik hasil eksekusi;
- validasi root dan nama scope.

## Batasan dan risiko

- `FileEbisnisMigrationEvidenceRepository` belum menggantikan kebutuhan WORM storage produksi.
- Action non-idempoten tidak boleh dipasang pada gate.
- File lock hanya melindungi proses pada filesystem yang mendukung locking; pengujian cluster/multi-node tetap wajib.
- Retention, rotasi, replikasi, enkripsi at-rest, dan alert belum menjadi tanggung jawab implementasi awal.
- Belum ada aktivasi writer produksi maupun migrasi database dalam fase ini.

## Rollback

Fondasi ini bersifat additive dan default tidak mengaktifkan mutasi. Rollback kode dapat dilakukan dengan melepas wiring gate dari orchestrator runtime. Evidence yang sudah ditulis tidak boleh dihapus; tandai pembatalan melalui event baru agar audit trail tetap utuh.

## Gerbang menuju Fase 17

Fase berikutnya harus:

1. menyediakan adapter repository produksi yang durable/WORM;
2. mengintegrasikan identity provider dan otorisasi aksi nyata;
3. memasang observability, retention, backup, restore, dan replay drill;
4. menjalankan concurrency serta crash-recovery test pada staging;
5. menghubungkan satu alur rollout risiko rendah dengan feature flag tetap default OFF;
6. membuktikan rollback rehearsal dan rekonsiliasi nol mismatch sebelum canary.
