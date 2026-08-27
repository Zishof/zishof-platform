# Fase 14 — Stabilisasi dan Dekomisioning Legacy

## Status

Fondasi kontrak keputusan dan gerbang keselamatan **selesai**. Penghentian writer legacy, penghapusan route/tabel, migrasi database, dan perubahan produksi **belum dilakukan**.

Implementasi utama:

- `ais.common.EbisnisLegacyDecommissionRegistry`
- `ais.common.test.EbisnisLegacyDecommissionRegistrySelfTest`

Registry ini bersifat murni dan hanya menilai bukti. Ia tidak menjalankan DDL/DML, tidak menghentikan writer, tidak menghapus artefak, dan tidak mengubah konfigurasi runtime.

## Tujuan

1. Menutup rollout hanya setelah periode observasi dan rekonsiliasi benar-benar selesai.
2. Mencegah reader/writer legacy dihentikan ketika masih mempunyai pemakai aktif.
3. Memisahkan deprecation, penghentian writer, pengarsipan, dan penghapusan fisik menjadi tahap berbeda.
4. Memastikan backup, restore, replay, SOP, pelatihan, runbook, DR, ownership, dan sign-off tersedia sebelum removal release.
5. Menyediakan alasan keputusan yang konsisten untuk operator dan audit.

## Batas keselamatan

- Dekomisioning default **OFF** (`DEFAULT_DECOMMISSION_ENABLED = false`).
- Tidak ada penghapusan otomatis pada tahap mana pun.
- Perpindahan normal hanya satu tahap ke depan; lompatan tahap ditolak.
- Tahap yang sama bersifat idempoten dan menghasilkan `NO_CHANGE`.
- Insiden integritas data memaksa `ROLLBACK_REQUIRED`.
- Penghapusan fisik wajib berada pada release terpisah setelah backup/restore/replay serta sign-off lengkap.
- Hak admin tidak melewati evidence gate, dependency gate, monitoring gate, atau sign-off gate.

## State machine

| Tahap | Tujuan | Bukti minimum sebelum maju |
|---|---|---|
| `OBSERVATION` | Mengamati hasil cutover selama periode yang disepakati | Observasi selesai, durasi memenuhi policy, error dan alert stabil |
| `RECONCILIATION_CLOSED` | Menutup seluruh exception rekonsiliasi | Rekonsiliasi selesai dan exception terbuka nol |
| `DEPRECATED` | Menandai route/action/tabel legacy sebagai deprecated | Reader dan writer terinventarisasi serta deprecation route/action/table tercatat |
| `LEGACY_WRITER_STOPPED` | Menghentikan writer legacy secara terkontrol | Reader/writer aktif nol dan penghentian writer terverifikasi |
| `ARCHIVED` | Mengarsipkan mapping dan audit migrasi | Mapping, audit, bukti, dan owner arsip lengkap |
| `READY_FOR_REMOVAL_RELEASE` | Menyetujui release penghapusan terpisah | Backup, restore, replay, SOP, training, runbook, DR, ownership, sign-off, dan release terpisah lengkap |
| `COMPLETE` | Menutup removal setelah verifikasi | Penghapusan fisik terverifikasi, monitoring pasca-removal sehat, tanpa incident |
| `ROLLED_BACK` | Mengembalikan scope ke kondisi aman | Rollback siap dan alasan tercatat |

## Kode keputusan

- `ALLOWED`: adapter eksternal boleh menjalankan tahap yang diminta.
- `NO_CHANGE`: scope sudah berada pada tahap tersebut.
- `BLOCKED_DISABLED`: feature flag dekomisioning belum aktif.
- `BLOCKED_SEQUENCE`: urutan tahap tidak sah.
- `BLOCKED_EVIDENCE`: bukti wajib belum lengkap.
- `BLOCKED_DEPENDENCY`: reader atau writer legacy masih aktif.
- `BLOCKED_MONITORING`: durasi observasi, error rate, atau alert belum memenuhi policy.
- `BLOCKED_SIGN_OFF`: ownership atau persetujuan formal belum lengkap.
- `ROLLBACK_REQUIRED`: adapter harus menghentikan kemajuan dan menjalankan playbook rollback.

## Kebijakan konservatif default

Policy bawaan menetapkan:

- observasi minimum `30` hari;
- error rate maksimum `25` basis point;
- alert terbuka maksimum `0`;
- dekomisioning tetap nonaktif sampai diaktifkan eksplisit pada scope yang disetujui.

Nilai produksi harus datang dari konfigurasi terkontrol dan tidak boleh diubah hanya agar sebuah scope terlihat lulus.

## Prosedur operator

1. Tentukan scope modul, artefak legacy, owner, dan removal release.
2. Ambil tahap tersimpan serta evidence aktual dari sumber audit immutable.
3. Evaluasi tahap yang diminta melalui registry.
4. Jika keputusan bukan `ALLOWED`, jangan menjalankan perubahan runtime.
5. Jalankan perubahan tahap melalui adapter eksternal yang transaksional dan auditable.
6. Simpan checksum, metrik, dependency scan, approval, operator, waktu, dan hasil verifikasi.
7. Observasi kembali setelah writer dihentikan dan setelah removal release.
8. Jika muncul incident integritas, hentikan proses dan jalankan rollback.

## Evidence wajib

- Periode observasi, error rate, dan jumlah alert terbuka.
- Status rekonsiliasi dan jumlah exception yang belum ditutup.
- Inventaris reader/writer aktif per route, action, job, report, integrasi, dan platform.
- Penanda deprecated untuk route, action, dan tabel.
- Bukti writer legacy berhenti tanpa reader/writer tersisa.
- Arsip mapping dan audit migrasi.
- Bukti backup, restore, serta replay.
- SOP, materi training, runbook operasi, dan dokumen disaster recovery.
- Owner teknis, owner bisnis, QA sign-off, operasi sign-off, dan data-owner sign-off.
- Identitas release penghapusan terpisah.
- Verifikasi penghapusan fisik dan monitoring pasca-removal.

## Gerbang penghapusan fisik

Penghapusan fisik tidak boleh digabung dengan release penghentian writer. Release removal hanya boleh dibuat bila:

1. tidak ada reader atau writer aktif yang bergantung pada artefak;
2. observasi dan monitoring stabil;
3. rekonsiliasi tidak memiliki exception terbuka;
4. backup dapat direstore dan event dapat direplay;
5. dokumen operasi serta ownership lengkap;
6. semua sign-off formal tersedia;
7. rollback masih dapat dijalankan.

## Hasil verifikasi lokal

- Kompilasi target Java 1.7 berhasil.
- Self-test registry lulus **43 pemeriksaan**.
- Skenario mencakup default OFF, transisi berurutan, tahap idempoten, lompatan tahap, observasi kurang, dependency aktif, evidence tidak lengkap, sign-off, removal release, complete, dan rollback.
- Source canonical dan mirror memiliki SHA-256 identik.
- Output kompilasi berada di `.codex-build`; tidak ada `.class` di samping `.java`.

## Pekerjaan runtime yang masih tersisa

1. Membuat penyimpanan tahap dan evidence yang immutable/auditable.
2. Menghubungkan registry dengan dependency scanner, monitoring, alerting, dan feature flag staging.
3. Menjalankan pilot Fase 13 sampai selesai sebelum memulai observasi Fase 14.
4. Menjalankan restore/replay drill dan menyimpan hasilnya.
5. Melengkapi SOP, training, runbook, DR, ownership, dan sign-off.
6. Menjadwalkan penghentian writer dan removal sebagai release yang berbeda.
7. Melakukan penghapusan fisik hanya setelah change approval produksi tersendiri.

## Keputusan implementasi

Fase 14 saat ini adalah **decision-only foundation**. Tidak ada tabel, route, action, writer, atau logic lama yang dimatikan. Dengan demikian seluruh fungsi existing tetap dipertahankan sampai evidence produksi dan persetujuan formal memenuhi seluruh gerbang.
