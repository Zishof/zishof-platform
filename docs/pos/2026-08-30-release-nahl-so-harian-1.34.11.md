# Release Nahl POS 1.34.11 — SO Harian

Tanggal: 30 Agustus 2026

## Cakupan

- Tab **SO Harian** pada Stok Opname untuk barang yang terjual pada tanggal
  pilihan.
- Daftar penjualan bruto, retur, penjualan bersih, stok saat ini, serta
  checklist pemeriksaan lokal per toko/tanggal.
- Unduh template Excel dan unggah kembali hasil hitung fisik.
- Pratinjau perubahan sebelum simpan, validasi seluruh baris, penyimpanan
  atomik, audit pengguna, dan pencegahan unggah file identik dua kali.
- Cetak lembar pemeriksaan PDF.

## Ketergantungan deployment

Backend AIS SVN **r78607** harus dideploy lebih dahulu. Tidak ada migrasi
database. Sesudah backend sehat, pasang Nahl POS Desktop/Android 1.34.11 dan
tekan **Sinkronkan** pada setiap kasir.

## Bukti verifikasi

- Full compile backend Maven: 7.316 source Java, `BUILD SUCCESS`.
- Analisis terarah Flutter: `No issues found`.
- Seluruh test Flutter: 569 test lulus.
- Kedua working copy backend identik dan bersih pada SVN r78607.
- Build Nahl Windows release berhasil dan dikemas sebagai installer UAT.
- Build Nahl Android release berhasil; sesuai keputusan UAT saat ini APK masih
  menggunakan sertifikat Android Debug.

## Artefak UAT

- `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.11.exe` — SHA-256
  `DA87A0317D5E566AF481FB7E83A976925E4995FBE8F50D2089BEFBA555403BD6`.
- `TokoQu-Al-Bahjah-An-Nahl-Android-1.34.11-debug-signed.apk` — SHA-256
  `B11B50CADB4E70688EEDBE0A8B7A7B3A7C42675EBE6DEBA3D83AF548B48446F0`.

Installer Windows belum mempunyai signature Authenticode dan APK masih
debug-signed. Keduanya layak untuk UAT internal, tetapi belum boleh diposisikan
sebagai artefak bertanda tangan produksi. Untuk distribusi publik production,
siapkan sertifikat code-signing Windows dan Android keystore produksi lalu
bangun ulang dengan source/tag yang sama.

## UAT setelah deployment server

1. Buka Stok Opname > SO Harian dan pilih tanggal yang mempunyai transaksi.
2. Pastikan hanya produk terjual yang muncul dan nilai Terjual/Retur/Bersih
   dapat dijelaskan oleh transaksi pada hari tersebut.
3. Unduh Excel, isi sebagian kolom `STOK_FISIK`, lalu unggah.
4. Pastikan pratinjau menampilkan stok lama → stok fisik dan baris kosong
   dilewati.
5. Konfirmasi simpan dan periksa jurnal SO, stok server, serta stok kasir lain
   setelah sinkronisasi.
6. Unggah file identik sekali lagi; server harus menolaknya.
7. Jika entri salah, gunakan pembatalan SO oleh supervisor; jangan mengubah
   stok langsung dari Produk.

## Rollback

Jika UAT server gagal, kembalikan class backend ke revisi sebelum r78607 dan
jangan distribusikan klien 1.34.11. Data tidak berubah ketika pratinjau saja;
penyimpanan upload yang gagal di tengah proses di-rollback seluruhnya.
