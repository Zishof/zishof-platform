# Al-Bahjah POS 1.34.104 (Build 267) — UAT internal

Tanggal: 11 November 2026 (WIB)
Varian: Al-Bahjah saja
Status: paket UAT internal; belum diterapkan ke sistem produksi.

## Keluhan yang ditangani

Masukan pada tangkapan layar Toko Albahjah sebelumnya mencakup perubahan
kuantitas faktur kulakan, pembatalan transaksi dengan persetujuan supervisor,
metode pembayaran dan ekspor riwayat retur, navigasi menu Posting Kulakan,
template identitas top-up, scroll rincian stok, laporan stok pada tanggal
pilihan, detail mutasi produk, Mutasi Barang per Tanggal, ringkasan SO Grand,
dan penanganan saat layanan tidak tersedia. Perubahan-perubahan tersebut telah
ada pada riwayat sumber sebelum rilis ini; lihat commit `89da432` dan
`b0dff6c` pada cabang `main`.

## Koreksi pada rilis ini

1. Tampilan dan ekspor Mutasi Barang per Tanggal tidak lagi memakai ringkasan
   periode sebagai pengganti rincian harian. Jika baris tidak memiliki tanggal
   atau ringkasan subtotal harian tidak lengkap, aplikasi menampilkan kendala
   dan tidak membuat subtotal yang seolah-olah benar.
   Rincian membaca salinan lokal yang cocok dengan pengguna, tenant, toko,
   rentang tanggal, pencarian, dan halaman sebelum meminta pembaruan. Salinan
   yang ditampilkan saat jaringan terputus diberi waktu penyimpanan.
2. Nilai persediaan tidak memakai harga jual sebagai pengganti harga beli/HPP.
   Jika harga beli untuk stok yang tersedia tidak diketahui, jumlah nilai
   diberi status “Belum lengkap”. Nilai tanggal lampau tetap merupakan
   perkiraan karena memakai harga beli saat ini; keterangan ini ditampilkan.
3. Aksi pada panel hasil analisis buku besar produk dipindahkan ke menu tiga
   titik dan tombol analisis toko duplikat dihilangkan.
4. Pengujian menambahkan pemeriksaan untuk HPP tersedia/tidak tersedia dan
   memastikan harga jual tidak dipakai menghitung nilai persediaan.

## Pemeriksaan yang dijalankan

- `flutter analyze` pada empat berkas Dart yang disentuh: lulus, tanpa temuan.
- `flutter test test/produk_stok_tanggal_test.dart`: lulus, 4 pengujian.
- `flutter clean`: berhasil.
- Build Android `assembleAlbahjahRelease`: berhasil; tanda tangan debug/UAT.
- Build Windows Release dan pemasang: berhasil; pemasang belum memiliki tanda
  tangan Authenticode produksi.
- Pemeriksaan sidik jari kedua paket: tersedia di berkas `.sha256.txt` yang
  menyertai paket.

## Batas rilis dan pemeriksaan lanjutan

Paket ini hanya untuk uji internal. APK memakai tanda tangan debug dan EXE
belum ditandatangani sertifikat penerbit; jangan dipakai sebagai rilis publik.
Periksa pemasangan, login, pilihan toko, rentang tanggal, subtotal per hari,
ekspor Excel/PDF, nilai persediaan, dan panel analisis dengan akun serta data
uji yang berwenang. Perbandingan angka terhadap database produksi, UAT oleh
petugas toko, dan penerapan produksi belum dilakukan dalam pekerjaan ini.

Untuk setiap nilai stok tanggal lampau, tampilkan harga beli yang dipakai
sebagai harga saat ini/perkiraan. Jika total tidak lengkap, pastikan HPP produk
yang stoknya tidak nol telah diperbarui oleh petugas yang berwenang; jangan
mengganti HPP dengan harga jual.
