# Fase 13 — Migrasi dan Rollout Bertahap

## Status

Fondasi kontrak dan pengambilan keputusan **selesai**. Aktivasi runtime, migrasi database, pergantian writer, dan deployment produksi **belum dilakukan**.

Implementasi utama:

- `ais.common.EbisnisMigrationRolloutRegistry`
- `ais.common.test.EbisnisMigrationRolloutRegistrySelfTest`

Registry ini bersifat murni dan tidak menulis database. Ia hanya memvalidasi apakah sebuah scope aman maju, tetap pada tahap sekarang, atau wajib rollback berdasarkan policy dan evidence yang diberikan adapter runtime.

## Tujuan

1. Menjamin migrasi berjalan bertahap, terukur, dan dapat dihentikan.
2. Mencegah writer baru aktif sebelum data, performa, dan prosedur rollback terbukti sehat.
3. Mengisolasi rollout berdasarkan tenant, lokasi, writer, dan persentase canary.
4. Menyediakan alasan keputusan yang konsisten untuk audit dan operator.
5. Mempertahankan seluruh logic lama sampai cutover dan sign-off selesai.

## Batas keselamatan

- Rollout default **OFF** (`DEFAULT_ROLLOUT_ENABLED = false`).
- Registry tidak menjalankan DDL/DML, backfill, deploy, atau pergantian writer.
- Perpindahan normal hanya satu tahap ke depan; lompatan tahap ditolak.
- Rollback harus eksplisit dan tercatat.
- Masalah integritas, mismatch, error-rate, atau regresi latensi pada tahap berisiko menghasilkan keputusan rollback.
- Hak admin untuk melihat menu tidak menghapus validasi aksi, audit, dan approval mutasi berisiko.

## State machine

| Tahap | Tujuan | Bukti minimum sebelum maju |
|---|---|---|
| `BASELINE` | Membekukan tolok ukur data dan performa existing | Baseline tersedia dan scope valid |
| `DRY_RUN` | Menguji mapping serta rencana tanpa mutasi | Dry-run lulus tanpa ambiguity/error |
| `BACKFILL` | Mengisi struktur baru secara repeatable | Backfill selesai dan jumlah data sesuai |
| `SHADOW_READ` | Membandingkan hasil baca legacy dan baru | Perbandingan baca tersedia dan mismatch nol |
| `SHADOW_WRITE` | Menjalankan writer bayangan tanpa menjadi sumber utama | Shadow-write selesai, idempotensi dan integritas lulus |
| `RECONCILIATION` | Merekonsiliasi saldo, jumlah, checksum, dan referensi | Rekonsiliasi selesai, mismatch nol |
| `CANARY` | Membatasi aktivasi pada scope/persentase kecil | Persentase sesuai policy, health sehat, waktu observasi cukup |
| `CUTOVER` | Menjadikan writer baru sumber utama pada scope | Canary lulus, approval dan rollback rehearsal tersedia |
| `COMPLETE` | Menutup rollout scope setelah observasi | Cutover stabil dan sign-off lengkap |
| `ROLLED_BACK` | Mengembalikan scope secara aman | Alasan rollback dan bukti pemulihan tercatat |

## Kode keputusan

- `ALLOWED`: tahap berikutnya boleh dijalankan oleh adapter eksternal.
- `NO_CHANGE`: scope tetap pada tahap sekarang.
- `BLOCKED_DISABLED`: rollout belum diaktifkan untuk scope.
- `BLOCKED_SEQUENCE`: urutan tahap tidak sah.
- `BLOCKED_EVIDENCE`: bukti wajib belum lengkap.
- `BLOCKED_HEALTH`: indikator kesehatan melewati ambang aman.
- `ROLLBACK_REQUIRED`: adapter harus menghentikan kemajuan dan menjalankan prosedur rollback yang telah disetujui.

## Kebijakan konservatif default

Policy bawaan menetapkan:

- mismatch yang diterima: `0`;
- error rate maksimum: `50` basis point;
- regresi latensi maksimum: `15%`;
- observasi minimum: `1.440` menit;
- canary maksimum: `10%`;
- rollout tetap nonaktif sampai diaktifkan secara eksplisit untuk scope pilot.

Nilai produksi harus ditetapkan melalui konfigurasi terkontrol, direview, dan dicatat sebagai evidence. Jangan mengubah konstanta agar rollout tampak lulus.

## Urutan pilot

1. Tenant/toko demo.
2. Gudang atau outlet nonkritis.
3. Satu rute distribusi dengan volume terbatas.
4. Satu outlet produksi dengan observasi penuh.
5. Alur vendor, tagihan, dan pembayaran setelah inventory serta distribusi stabil.

Ekspansi dilakukan per scope, bukan sekaligus seluruh tenant atau seluruh lokasi.

## Prosedur operator

1. Tentukan scope tenant, lokasi, writer, dan persentase canary.
2. Ambil tahap tersimpan dan evidence aktual dari sumber audit.
3. Panggil registry untuk mengevaluasi tahap yang diminta.
4. Jika keputusan bukan `ALLOWED`, jangan menjalankan mutasi tahap.
5. Jika `ALLOWED`, adapter eksternal menjalankan pekerjaan tahap tersebut dalam transaksi yang sesuai.
6. Simpan hasil, checksum, metrik, approval, dan identitas operator.
7. Observasi sesuai policy sebelum meminta tahap berikutnya.
8. Jika registry menghasilkan `ROLLBACK_REQUIRED`, hentikan writer baru dan jalankan playbook rollback scope tersebut.

## Evidence wajib

- Identitas tenant, lokasi, writer, versi aplikasi, dan versi skema.
- Waktu mulai/selesai setiap tahap serta operator/approver.
- Jumlah sumber, jumlah target, checksum, dan mismatch.
- Hasil retry/idempotensi dan uji konkurensi.
- Error rate serta perbandingan latensi legacy vs baru.
- Lama observasi canary.
- Bukti rehearsal rollback.
- Approval QA, Product Owner, pemilik data, dan operasi sebelum cutover.

## Pemicu rollback

- Kehilangan atau duplikasi data.
- Mismatch checksum atau saldo lebih dari nol.
- Referensi lintas tenant/lokasi atau mapping ambigu.
- Error rate atau regresi latensi melewati policy.
- Kegagalan idempotensi/concurrency.
- Evidence atau approval wajib hilang.
- Incident integritas pada shadow-write, reconciliation, canary, cutover, atau complete.

Rollback harus non-destruktif: writer baru dihentikan untuk scope terkait, legacy tetap dapat dibaca, data hasil percobaan dipertahankan untuk audit, dan perbaikan dilakukan sebelum mengulang dari tahap yang disetujui.

## Hasil verifikasi

- Kompilasi target Java 1.7 berhasil.
- Self-test registry lulus **57 pemeriksaan**.
- Skenario yang diuji meliputi rollout disabled, urutan tahap, kekurangan evidence, health gate, batas canary, cutover, complete, serta rollback.
- Source canonical dan mirror memiliki SHA-256 identik.
- Tidak ada file `.class` di samping `.java`; output verifikasi berada di `.codex-build`.

## Pekerjaan runtime yang masih tersisa

1. Menyediakan penyimpanan tahap dan evidence yang immutable/auditable.
2. Membuat adapter registry ke feature flag, scheduler backfill, shadow comparator, dan metrik runtime.
3. Menjalankan DDL serta backfill hanya pada database staging yang telah disetujui.
4. Menjalankan UAT lintas modul dan lintas platform pada data representatif.
5. Melakukan rollback rehearsal dan membuktikan recovery time.
6. Mendapatkan sign-off sebelum canary dan sebelum cutover produksi.

## Gerbang menuju Fase 14

Fase 14 (stabilisasi, observabilitas, optimasi, dan penutupan rollout) baru boleh dimulai setelah satu pilot Fase 13 menyelesaikan seluruh tahap tanpa mismatch, memenuhi SLO, lulus rollback rehearsal, dan memperoleh sign-off formal.
