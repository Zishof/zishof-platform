# TokoQu Al-Bahjah An Nahl v1.34.37 build 200 — UAT WA 12–13 September 2026

Tanggal verifikasi: 14 September 2026
Commit kandidat: `b9da9ca`

## Perbaikan yang diverifikasi

1. Checkout dikunci sejak ketukan pertama untuk mencegah nota ganda akibat double tapping.
2. Stok dan transaksi disimpan local-first; outbox lokal menjadi patokan sebelum sinkronisasi idempoten ke server.
3. Opsi metode laporan mengikuti tanggal aktif. Filter **Transfer + QRIS** mencakup `Transfer`, `QRIS`, dan `QRS - ...` pada Penjualan/Penerimaan per Kasir beserta ekspornya.
4. Produk yang menampilkan “Tersimpan di perangkat — Belum terkirim” sudah aman di lokal dan dikirim ulang otomatis.
5. Input siswa/member dapat dilakukan local-first oleh akun berhak Kelola Pelanggan; akun tanpa hak mendapat penjelasan eksplisit.
6. Produk ganda ditangani melalui **Produk → Bersihkan Duplikat** oleh admin/supervisor agar histori dan stok digabung sebelum salinan dihapus.
7. Faktur PDF A4 dapat dibuat dari Riwayat Penjualan Back Office.

## Hasil pengujian

- 15/15 pengujian terarah lulus.
- Suite aplikasi: 863 skenario lulus; setelah prasyarat model wajah diunduh dan hash diverifikasi, suite model 20/20 lulus.
- `core_db`: 14/14 lulus.
- `core_update`: 6/6 lulus.
- Uji kanal khusus Nahl: 7/7 lulus.
- Android: `id.zishof.ebisnis.nahl`, version `1.34.37`, versionCode `200`.
- Kanal pembaruan: hanya tag `nahl-*`; tidak dapat mengambil rilis `albahjah-*`.

## Artefak Nahl

| Berkas | SHA-256 |
|---|---|
| `app-nahl-release.apk` | `45efee62068d310c0445edc87e77bc3d66b8532e9cc164ec712545a48478e213` |
| `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.37.exe` | `fd40ebeb5341e2a3214636d2e7aaa4fd5618cd4173af878ef9f001afec41b342` |

Kandidat ini adalah prerelease/UAT: APK memakai sertifikat Android Debug dan installer Windows belum memiliki Authenticode produksi.
