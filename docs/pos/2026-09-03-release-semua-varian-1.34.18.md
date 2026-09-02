# Catatan Rilis POS 1.34.18 — eBisnis, Al-Bahjah, dan Nahl

Tanggal build dan verifikasi: 3 September 2026

## Status rilis

Enam artefak UAT berhasil dibuat dari satu snapshot sumber yang sama:

- eBisnis POS: Windows dan Android;
- Al-Bahjah POS: Windows dan Android; dan
- TokoQu Al-Bahjah An-Nahl: Windows dan Android.

Versi aplikasi adalah **1.34.18+180**. Build dibekukan dari Git commit
`7130a4562349c3abaab8e7c92732a93230c19c55` beserta perubahan piutang yang
belum dikomit pada saat snapshot dibuat. Snapshot build disimpan di
`C:\opt\BuildSnapshots\ebisnis-1.34.18-r7130a45` agar hasil dapat direproduksi
dan tidak tercampur perubahan sesi lain yang berjalan bersamaan.

Backend terbaru juga dikompilasi ulang setelah seluruh pembaruan sesi masuk.
Pohon `src`, mirror `java`, dan `webapp` berada pada revisi SVN **83555**, bersih
tanpa perubahan lokal, dan kompilasi Maven penuh atas 7.505 sumber Java selesai
dengan `BUILD SUCCESS`.

## Perubahan utama

- Daftar Saldo Piutang Customer hanya menelusuri transaksi yang benar-benar
  memakai metode Kasbon. Voucher, QRIS, Tunai, Transfer, dan metode non-Kasbon
  tidak dimasukkan sebagai piutang.
- Pembayaran campuran hanya mencatat bagian nominal Kasbon sebagai piutang.
- Kode pada laporan saldo piutang diperlakukan sebagai kode pelanggan, bukan
  kode produk, sehingga drill-down mengambil transaksi pelanggan yang tepat.
- Rincian yang dapat diklik menampilkan waktu, nomor nota, kasir, pelanggan,
  produk, metode pembayaran lengkap, jenis piutang, piutang per faktur, qty,
  harga, dan total produk.
- Total piutang pada rincian dihitung satu kali per nomor faktur sehingga nota
  dengan beberapa produk tidak menggandakan nilai piutang.

Penjelasan analisis, keterbatasan data lama, dan skenario UAT rinci tersedia di
`docs/pos/2026-09-03-piutang-kasbon-rincian-produk.md`.

## Bukti verifikasi

- `flutter clean` dan resolusi dependency berhasil.
- Seluruh tes Flutter POS: **730/730 lulus**.
- Tes aset/model wajah: **19/19 lulus** setelah aset produksi dimasukkan ke
  snapshot build.
- `flutter analyze --no-fatal-infos`: exit code 0; tidak ada error penghambat,
  dengan 50 info lint lama.
- Maven `clean compile -DskipTests`: **BUILD SUCCESS**, 7.505 sumber Java,
  revisi SVN 83555.
- Build seluruh varian: **6/6 artefak berhasil**, durasi 36,9 menit.
- Semua salinan pada folder rilis utama cocok hash-nya dengan snapshot build.
- ProductVersion ketiga installer Windows terbaca sebagai `1.34.18`.

## Artefak dan checksum SHA-256

| Varian | Platform | Berkas | Ukuran | SHA-256 |
|---|---|---|---:|---|
| Al-Bahjah | Windows | `Al-Bahjah-POS-Setup-1.34.18.exe` | 85.936.944 byte | `6F7B1663B30667457F349E852848F4AF7CF32962583DD503542EDFC3C0E73BC3` |
| Al-Bahjah | Android | `app-albahjah-release.apk` | 190.062.964 byte | `D7F0C409576A28958BA6A4832FC030BB43136C9EE9F3A751026126287EDA586B` |
| eBisnis | Windows | `eBisnis-Setup-1.34.18.exe` | 85.880.452 byte | `D4DADA4FCA4C1A0FFD26245D4F98D65EEB7997AF59FD1EB41AC10577EDE410A0` |
| eBisnis | Android | `app-ebisnis-release.apk` | 190.001.932 byte | `401E3C54DC37653CBE637ED1FAA6E97679CB4D347FD347A62A19AB06DECE2742` |
| Nahl | Windows | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.18.exe` | 86.098.844 byte | `256C08CDA86775E37484D2A1BA1F95CCC68BAFFB9682090AE130F14FE1396F38` |
| Nahl | Android | `app-nahl-release.apk` | 190.067.988 byte | `7C89F47CF46C6C77A18FB94285C3EDBB31F105DCAE05E25ED131C1048DDF0CD4` |

Folder distribusi lokal:
`apps/ebisnis/release-artifacts/semua-varian/1.34.18`.

## Status tanda tangan dan batas distribusi

Artefak ini adalah paket **UAT/internal**, belum paket produksi:

- ketiga APK ditandatangani sertifikat Android Debug;
- ketiga installer Windows belum memiliki tanda tangan Authenticode.

APK UAT mungkin tidak dapat memperbarui aplikasi produksi yang memakai
sertifikat berbeda. Jangan mencopot aplikasi pada perangkat operasional hanya
untuk memasang APK UAT karena data lokal dapat ikut hilang. Gunakan perangkat
uji atau lakukan build ulang dengan keystore produksi. Windows dapat menampilkan
peringatan SmartScreen; untuk distribusi luas, tanda tangani installer dengan
sertifikat code-signing produksi.

## Langkah instalasi/UAT

1. Cadangkan data lokal dan selesaikan sinkronisasi aplikasi lama.
2. Untuk Windows, tutup POS lalu jalankan installer varian yang sesuai.
3. Untuk Android, gunakan perangkat uji yang menerima sertifikat Debug/UAT.
4. Login, pilih toko yang benar, tekan **Sinkronkan**, tunggu selesai, kemudian
   tekan **Muat Ulang**.
5. Pastikan versi yang tampil adalah 1.34.18.
6. Uji transaksi Tunai, QRIS, Voucher, Kasbon Pejuang, Kasbon Divisi, serta
   split payment QRIS + Kasbon.
7. Buka Daftar Saldo Piutang Customer. Pastikan hanya bagian Kasbon yang masuk.
8. Klik jumlah faktur atau saldo dan cocokkan metode, jenis piutang, produk,
   qty, harga, total produk, dan total piutang unik per faktur.
9. Cocokkan laporan layar dengan Riwayat Penjualan dan Mutasi Voucher.

## Rollback

Hentikan penyebaran dan kembali ke installer sebelumnya bila Voucher/QRIS masih
masuk piutang, transaksi Kasbon hilang, nilai split payment salah, nilai piutang
berlipat karena jumlah produk, atau aplikasi gagal sinkron/startup. Jangan hapus
data transaksi historis untuk melakukan rollback aplikasi.
