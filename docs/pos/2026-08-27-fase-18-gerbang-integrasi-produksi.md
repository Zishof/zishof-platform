# Fase 18 — Gerbang Integrasi Produksi

Tanggal: 27 Agustus 2026
Status: fondasi kode dan UAT statis selesai; integrasi infrastruktur eksternal belum diaktifkan

## Tujuan

Fase ini menutup celah antara kontrol operasional Fase 17 dan lingkungan produksi nyata. Implementasi menyediakan kontrak yang fail-closed untuk identitas teraudit, penyimpanan bukti immutable, snapshot terjadwal, alarm kegagalan, dan keputusan canary per tenant/lokasi.

## Implementasi

Kode utama berada di package `ais.common`:

1. `EbisnisMigrationAuditedIdentityProvider`
   - memverifikasi assertion dari penyedia identitas;
   - mencocokkan actor, masa berlaku, dan izin `workflow:stage` atau `workflow:*`;
   - selalu mencatat keputusan otorisasi ke audit sink;
   - gagal tertutup bila verifier atau audit sink gagal.
2. `EbisnisMigrationImmutableEvidencePublisher`
   - mewajibkan immutable write, encryption at rest, versioning, retention lock, dan replikasi lintas host;
   - menulis dengan semantik `putIfAbsent` agar bukti tidak ditimpa;
   - menghitung SHA-256 dan memverifikasi ulang hasil baca;
   - menolak retention time yang tidak valid atau data yang berubah.
3. `EbisnisMigrationEvidenceScheduler`
   - menjalankan satu siklus snapshot tanpa membuat thread internal;
   - menyerahkan penjadwalan kepada scheduler aplikasi/infrastruktur;
   - mengirim alarm bila snapshot atau publikasi gagal, kemudian meneruskan error.
4. `EbisnisMigrationProductionCanaryGate`
   - feature flag per tenant/lokasi dan default `OFF`;
   - hanya membuka canary jika hasil rekonsiliasi tidak memiliki mismatch;
   - mensyaratkan bukti backup/restore, crash recovery, rollback rehearsal, serta persetujuan QA, bisnis, dan TI.

## UAT yang dijalankan

Kompilasi dilakukan dengan `javac -source 1.7 -target 1.7` ke `C:\opt\AIS\ais\.codex-build\phase18`, bukan ke directory sumber.

| Gerbang | Hasil |
|---|---:|
| Evidence journal | 25 pemeriksaan lulus |
| Evidence gate | 30 pemeriksaan lulus |
| Operational readiness Fase 17 | 36 pemeriksaan lulus |
| Production integration Fase 18 | 27 pemeriksaan lulus |
| `.class` di `src/main/src` | 0 |
| Kesesuaian mirror `src/main/src` dan `src/main/java` | identik SHA-256 |

Kasus negatif mencakup assertion kedaluwarsa, actor berbeda, izin tidak lengkap, audit sink gagal, object store tidak memenuhi kapabilitas, overwrite bukti, checksum rusak, snapshot gagal, feature flag mati, dan bukti canary tidak lengkap.

## Perubahan versi

- SVN: r78365 — `Fase 18: tambah gerbang integrasi produksi`
- File yang masuk commit hanya empat komponen Fase 18 dan satu self-test.
- File tak berversi dari sesi lain tidak disertakan.

## Batasan dan prasyarat eksternal

Fase ini belum berarti integrasi produksi eksternal telah aktif. Sebelum canary nyata, masih wajib tersedia dan diuji:

- adapter konkret ke IAM/SSO produksi;
- object store WORM nyata dengan retention lock dan replikasi lintas host;
- scheduler dan kanal alarm operasional nyata;
- drill backup/restore, crash recovery, dan rollback di staging yang representatif;
- bukti serta persetujuan QA, bisnis, dan TI per tenant/lokasi.

Tanpa prasyarat tersebut, feature flag tetap `OFF` dan gerbang harus menolak canary.

## Fase berikutnya

Fase 19 memasang adapter infrastruktur konkret di staging, menjalankan drill, mengumpulkan bukti immutable, lalu membuka canary terbatas per tenant/lokasi. Aktivasi produksi tidak boleh dilakukan hanya berdasarkan self-test unit.
