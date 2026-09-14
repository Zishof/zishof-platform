# TokoQu Al-Bahjah An Nahl v1.34.38 build 201 — UAT WA 14–15 September 2026

Tanggal verifikasi: 15 September 2026
Commit aplikasi kandidat: `c1a8c5f`
Commit backend: SVN `r90209`

## Perbaikan yang diverifikasi

1. Cache dan permintaan Kulakan terikat tenant/toko aktif, termasuk simpan, daftar, detail, dan batal.
2. Rekap seluruh Kulakan dapat diunduh sebagai Excel atau PDF tanpa membuka faktur satu per satu.
3. Faktur transaksi piutang (Kasbon, E-Money, Reward, dan Voucher BMT) tidak mendapat stempel LUNAS tanpa bukti pelunasan eksplisit.
4. Riwayat Topup dapat difilter memakai tipe member dinamis dari master, termasuk Santri dan Pegawai bila kedua tipe itu aktif pada tenant.
5. Sinkronisasi siswa/member tersedia bagi admin/supervisor; UAT tidak mengubah data pribadi produksi.

## Temuan konfigurasi yang masih perlu tindakan PIC

- Dua akun yang dimaksud melihat dataset Kulakan yang sama hanya bila pemetaan tokonya sama.
- Label tipe member yang tidak tampil harus diperiksa pada master tipe member tenant; patch tidak membuat atau mengganti data master produksi.

## Hasil pengujian

- Suite aplikasi: 874/874 lulus.
- Uji terarah: 49/49 lulus.
- `core_db`: 14/14 lulus; `core_update`: 6/6 lulus.
- Uji kanal Nahl: 7/7 lulus dan tetap terisolasi dari aset Al-Bahjah.
- Backend Maven offline compile: BUILD SUCCESS; filter Topup dicommit ke SVN `r90209`.
- Analisis statis: tidak ada error/warning; 45 info gaya lama tetap ada.
- Android: `id.zishof.ebisnis.nahl`, version `1.34.38`, versionCode `201`.

## Artefak Nahl

| Berkas | SHA-256 |
|---|---|
| `app-nahl-release.apk` | `e23198e012ec0310b4bcaad33c53286131d56eea374634a1f02ca8d737975ce2` |
| `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.38.exe` | `5c08b5da78c20c93a0fc5d69434f4ec53b1873a20fcc870416bb426ce33d7357` |

Kandidat ini adalah prerelease/UAT: APK memakai sertifikat Android Debug dan installer Windows belum memiliki Authenticode produksi. Backend `r90209` dan aplikasi ini belum diterapkan ke produksi.
