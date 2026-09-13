# Al-Bahjah POS v1.34.37 build 200 — UAT WA 12–13 September 2026

Tanggal verifikasi: 14 September 2026
Commit kandidat: `b9da9ca`

## Perbaikan yang diverifikasi

1. **Double tapping pembayaran**
   - Checkout dikunci secara sinkron sejak ketukan pertama, sebelum dialog member/PIC dan sebelum operasi `await` pertama.
   - Ketukan kedua tidak dapat membuka alur pembayaran paralel.
   - Kunci selalu dilepas melalui `finally`, termasuk ketika validasi dibatalkan atau gagal.
2. **Stok local-first**
   - Penerimaan/koreksi produk ditulis ke SQLite dan outbox sebelum pengiriman server.
   - Refresh katalog tidak boleh menimpa mutasi lokal yang masih pending.
   - Transaksi POS memakai arsip lokal sebagai patokan sebelum sinkronisasi idempoten.
3. **Laporan Transfer dan QRIS**
   - Opsi metode dimuat ulang setelah tanggal laporan diterapkan.
   - Filter baru **Transfer + QRIS** menyatukan nama `Transfer`, `QRIS`, dan penamaan lama `QRS - ...`.
   - Filter berlaku pada tabel, pagination, PDF, Excel/Word, ringkasan, dan rincian penerimaan.
4. **Produk/member ketika server terganggu**
   - Pesan “Tersimpan di perangkat — Belum terkirim” berarti simpan lokal berhasil, bukan gagal; outbox mengirim ulang otomatis.
   - Input siswa/member tetap local-first untuk akun yang memiliki hak Kelola Pelanggan.
   - Akun tanpa hak tersebut sekarang mendapat penjelasan eksplisit dan tidak dinaikkan haknya secara diam-diam.
5. **Produk ganda**
   - Fitur aman **Produk → Bersihkan Duplikat** tetap tersedia untuk admin/supervisor. Sistem mempratinjau, menggabungkan transaksi/stok ke produk utama, kemudian menghapus salinan.
6. **Faktur PDF Back Office**
   - Riwayat Penjualan menyediakan Faktur PDF A4 dengan identitas pembeli, rincian produk, total, terbilang, status pembayaran, dan area persetujuan.

## Hasil pengujian

- 15/15 pengujian terarah pembayaran, laporan, hak akses, dan ekspor lulus.
- Suite aplikasi: 863 skenario lulus; satu prasyarat model wajah yang belum ada ditemukan. Setelah dua model diunduh dan hash diverifikasi, suite model 20/20 lulus.
- `core_db`: 14/14 lulus (arsip transaksi lokal, outbox, coalescing, dan isolasi tenant).
- `core_update`: 6/6 lulus, termasuk penolakan aset Nahl pada kanal Al-Bahjah.
- Uji kanal Al-Bahjah dan Nahl dengan dart-define masing-masing: 7/7 per varian lulus.
- Analisis statis: tidak ada error/warning baru; terdapat 45 info gaya lama di luar perubahan ini.
- Android: `id.zishof.ebisnis.albahjah`, version `1.34.37`, versionCode `200`.

## Artefak Al-Bahjah

| Berkas | SHA-256 |
|---|---|
| `app-albahjah-release.apk` | `1c4ad00bd32d16e2534b2b2edb1dae83d2ee9248c23d83e2ec8691d51640b64c` |
| `Al-Bahjah-POS-Setup-1.34.37.exe` | `9fc6f7b2eca0ed9fee59c2d7e3c59b21b1c54cc646d8f4441d744e6b446ceee7` |

Kandidat ini adalah prerelease/UAT: APK memakai sertifikat Android Debug dan installer Windows belum memiliki Authenticode produksi.
