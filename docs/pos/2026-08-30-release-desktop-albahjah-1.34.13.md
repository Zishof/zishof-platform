# Rilis Desktop Al-Bahjah POS 1.34.13

Tanggal: 30 Agustus 2026  
Versi aplikasi: `1.34.13+175`  
Varian: `albahjah` (Desktop Windows)  
Tag GitHub: `v1.34.13`  
Commit sumber aplikasi: `7e9bb06`

## Ringkasan perubahan

- Master Produk menampilkan kolom **HPP** tepat sebelum **Harga Jual**, sehingga
  petugas dapat membandingkan biaya perolehan dan harga jual pada satu tabel.
- Faktur Pembelian/Kulakan menggunakan A4 **potret** sebagai orientasi awal.
- Tombol cetak faktur berubah menjadi **Pratinjau & Print**. Aplikasi menampilkan
  isi dan format dokumen terlebih dahulu; dialog printer baru dibuka ketika
  pengguna menekan cetak dari pratinjau.
- Pratinjau, unduhan PDF, dan hasil cetak memakai byte PDF yang sama agar bentuk
  dokumen tidak berubah di antara ketiga jalur tersebut.
- Kontrak local-first tidak diubah: data lokal, cache, transaksi pending, dan
  outbox lama tetap dipertahankan saat pembaruan aplikasi.

## Verifikasi

- Suite penuh aplikasi: `574` tes lulus.
- Tes kontrak khusus HPP dan faktur: `2` tes lulus.
- `flutter analyze` untuk layar Produk, Kulakan, dan utilitas pratinjau: tidak
  ada masalah.
- `git diff --check`: lulus.
- Kompilasi Windows release dan pembuatan installer Inno Setup: berhasil.

Catatan: analisis proyek penuh masih memuat temuan lama di modul lain yang tidak
berasal dari perubahan ini; file yang diubah dalam rilis ini bersih pada analisis
terarah.

## Artefak

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| Al-Bahjah POS | `Al-Bahjah-POS-Setup-1.34.13.exe` | 85.897.715 byte | `26EC1A72FC117E504773CCDE3F4A8303FC12538C8321BD32571D5A4C51970342` |

Installer belum ditandatangani Authenticode dan ditujukan untuk distribusi
internal/UAT Al-Bahjah.

## UAT pemasangan

1. Tutup aplikasi lama. Jangan menghapus database, cache, foto, transaksi
   pending, atau outbox lokal.
2. Pasang installer dan pastikan versi kiri bawah menunjukkan `1.34.13`.
3. Buka **Master Data > Produk** dan pastikan kolom **HPP** muncul di samping
   kiri **Harga Jual** serta nilainya sesuai data produk.
4. Buka **Kulakan**, pilih salah satu faktur, lalu tekan **Pratinjau & Print**.
5. Pastikan pratinjau tampil sebagai A4 potret, data faktur lengkap, dan tombol
   cetak pada pratinjau dapat membuka pilihan printer.
6. Simpan PDF dan bandingkan dengan pratinjau; susunan dan orientasi harus sama.
7. Periksa satu transaksi lokal/pending untuk memastikan data lama tetap ada.

## Rollback dan penghentian rollout

- Hentikan rollout bila checksum installer tidak cocok, HPP tidak tampil, atau
  pratinjau faktur gagal dibuka.
- Pasang kembali `Al-Bahjah-POS-Setup-1.34.12.exe` tanpa menghapus data lokal.
- Jangan membersihkan database/outbox ketika rollback; kiriman tertunda akan
  dilanjutkan setelah aplikasi atau server kembali sehat.
