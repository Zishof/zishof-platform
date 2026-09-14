# Al-Bahjah POS v1.34.38 build 201 — UAT WA 14–15 September 2026

Tanggal verifikasi: 15 September 2026
Commit aplikasi kandidat: `c1a8c5f`
Commit backend: SVN `r90209`

## Perbaikan yang diverifikasi

1. Cache riwayat Kulakan dipisahkan menurut tenant dan toko. Daftar, detail, batal, serta simpan selalu memakai toko aktif sehingga snapshot akun/toko lain tidak tampil sebagai data lokal.
2. Riwayat Kulakan menyediakan unduhan rekap seluruh halaman dalam Excel dan PDF, termasuk jumlah faktur dan total global sesuai toko/filter aktif.
3. Faktur penjualan tidak lagi menganggap status respons teknis sebagai bukti lunas. Kasbon, piutang, E-Money, Reward, dan Voucher BMT tidak diberi stempel LUNAS tanpa status pelunasan eksplisit.
4. Riwayat Topup menyediakan filter dinamis dari master Tipe Member. Filter diterapkan pada layar, cache lokal, pagination, dan ekspor.
5. Sinkronisasi siswa/member tetap tersedia untuk admin/supervisor melalui Pelanggan > Data Member > Sinkron Sivitas. Data pribadi pelapor tidak diubah dalam UAT ini.

## Temuan konfigurasi yang masih perlu tindakan PIC

- Akun Ika dan Nia harus dipetakan ke toko yang sama bila memang ditujukan melihat dataset Kulakan yang sama. Patch mencegah percampuran cache, tetapi tidak menggabungkan data lintas toko.
- Nama `Yayasan Al-Bahjah (Divisi)` tidak hilang karena filter aplikasi. API mengembalikan seluruh tipe member aktif; screenshot menunjukkan master aktif saat ini memakai nama `Al Bahjah Cabang 1 (Divisi)`. Admin/PIC perlu memeriksa status/nama record master tanpa menghapus relasi member.

## Hasil pengujian

- Suite aplikasi: 874/874 lulus.
- Uji terarah Kulakan, faktur, local-first, Topup, dan sinkronisasi member: 49/49 lulus.
- `core_db`: 14/14 lulus; `core_update`: 6/6 lulus.
- Uji kanal Al-Bahjah: 7/7 lulus.
- Backend Maven offline compile: BUILD SUCCESS (1.713 source); perubahan filter Topup telah dicommit ke SVN `r90209`.
- Analisis statis: tidak ada error/warning; 45 info gaya lama tetap ada.
- Android: `id.zishof.ebisnis.albahjah`, version `1.34.38`, versionCode `201`.

## Artefak Al-Bahjah

| Berkas | SHA-256 |
|---|---|
| `app-albahjah-release.apk` | `b76f914c863b969e1230bbe0a66315a27813c295587baced4f6c683dc5f78ebd` |
| `Al-Bahjah-POS-Setup-1.34.38.exe` | `a7985008f7fd836227d0e9b06713dd4fda72244b6abb43594b1df4100a306675` |

Kandidat ini adalah prerelease/UAT: APK memakai sertifikat Android Debug dan installer Windows belum memiliki Authenticode produksi. Backend `r90209` dan aplikasi ini belum diterapkan ke produksi.
