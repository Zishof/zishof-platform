# Fase 17 — Kesiapan Operasional Evidence Migrasi

Tanggal: 27 Agustus 2026  
Status: fondasi aplikasi selesai; aktivasi runtime/produksi tetap **OFF**

## Tujuan

Fase ini menutup celah operasional Fase 15–16 tanpa mengaktifkan writer produksi. Fokusnya adalah kontrol fail-closed, snapshot evidence yang tersegel, pemulihan, replay, rencana retensi, serta pembuktian perilaku ketika terjadi konkurensi dan crash.

## Implementasi

### Kontrol operasional fail-closed

- `EbisnisMigrationOperationalControl` menerima `FeatureFlag` dan `IdentityProvider` eksplisit.
- Nilai bawaan feature flag adalah nonaktif.
- Eksekusi ditolak apabila flag tidak aktif, kredensial/identitas tidak sah, atau aktor tidak berwenang.
- Setelah pemeriksaan tersebut lulus, operasi tetap melewati `EbisnisMigrationEvidenceGate`; tidak ada jalur pintas yang mematikan audit atau idempotensi.
- Eksekusi diserialkan pada instance kontrol agar request bersamaan dengan kunci operasi sama tidak menjalankan aksi dua kali.

### Snapshot, restore, replay, dan retensi

- `EbisnisMigrationEvidenceOperations` membuat snapshot baru secara no-overwrite.
- Manifest memuat jumlah record, hash terakhir journal, dan SHA-256 file snapshot.
- Restore hanya boleh menuju journal baru/kosong, memverifikasi checksum snapshot, lalu memverifikasi kembali hash-chain journal hasil restore.
- Sumber snapshot yang hilang atau bukan file ditolak; restore tidak boleh diam-diam menghasilkan journal kosong.
- Replay menghitung status akhir per operation ID (`PREPARED`, `APPLIED`, `FAILED`), sehingga record `PREPARED` bekas crash yang kemudian diselesaikan tidak salah dianggap menggantung.
- Retensi hanya menghasilkan keputusan/rencana. Implementasi ini tidak menghapus evidence otomatis, dan legal hold selalu mencegah penghapusan.

## UAT

Kompilasi dan test menggunakan target Java 1.7 dengan output terisolasi di `.codex-build`, bukan di samping file `.java`.

- `EbisnisMigrationEvidenceJournalSelfTest`: **LULUS, 25 pemeriksaan**.
- `EbisnisMigrationEvidenceGateSelfTest`: **LULUS, 30 pemeriksaan**.
- `EbisnisMigrationOperationalReadinessSelfTest`: **LULUS, 36 pemeriksaan**.
- Skenario Fase 17 mencakup flag OFF, aktor tidak sah, idempotensi, snapshot immutable, restore, sumber snapshot hilang, replay, target restore tidak kosong, delapan thread bersamaan, recovery `PREPARED` setelah crash, pencatatan kegagalan, retensi, dan legal hold.
- Empat file Fase 17 pada source kanonis dan mirror memiliki SHA-256 identik.
- Tidak ditemukan file `.class` pada kedua source tree.
- Tidak ada `openSession()`, `currentNativeSession()`, atau `currentSession()` pada implementasi Fase 17.

## Perubahan repository

- SVN revision: **r78364**.
- File utama:
  - `ais/common/EbisnisMigrationOperationalControl.java`
  - `ais/common/EbisnisMigrationEvidenceOperations.java`
  - `ais/common/EbisnisMigrationEvidenceGate.java`
  - `ais/common/test/EbisnisMigrationOperationalReadinessSelfTest.java`

## Batasan yang disengaja

- Snapshot file tersegel pada level aplikasi, tetapi belum merupakan storage WORM/compliance-grade.
- `IdentityProvider` adalah port kontrak, belum adapter IAM/SSO produksi.
- Rencana retensi belum menjalankan penghapusan fisik.
- Belum ada scheduler backup eksternal, replikasi lintas host, alarm operasional, atau key management produksi.
- Feature flag tetap OFF dan fase ini tidak mengubah writer produksi.

## Gerbang Fase 18

1. Implementasikan adapter identity production dan mapping role/aksi yang dapat diaudit.
2. Hubungkan repository ke storage immutable/WORM dengan enkripsi, versioning, dan kebijakan retensi yang disetujui.
3. Tambahkan scheduler snapshot, replikasi lintas host, monitoring checksum, serta alarm replay/restore.
4. Jalankan backup–restore dan crash-recovery drill pada staging dengan evidence yang disimpan di luar host aplikasi.
5. Lakukan canary satu scope berisiko rendah dengan flag per tenant/lokasi tetap dapat dimatikan segera.
6. Aktivasi produksi hanya setelah rekonsiliasi nol mismatch, rollback rehearsal lulus, dan sign-off operasional/keamanan tersedia.
