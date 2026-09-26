# v1.34.46 build 209 - koreksi Topup Tabungan dari Mutasi Voucher

Perbaikan POS Desktop untuk varian Al-Bahjah dan TokoQu Al-Bahjah An Nahl dari
commit lokal setelah `a6f745b`:

- Halaman Pelanggan > Mutasi Voucher menampilkan menu Ubah/Hapus khusus untuk
  baris Topup Tabungan.
- Aksi hanya muncul untuk akun yang memiliki hak `Boleh Entry Topup`.
- Baris pembelian/belanja voucher tidak dapat diubah atau dihapus dari halaman
  Mutasi Voucher.
- Form ubah meminta keterangan/alasan perubahan, lalu server menghitung ulang
  saldo akhir setelah perubahan diterima.
- Dialog hapus meminta alasan dan memberi peringatan bahwa tindakan tidak dapat
  dipulihkan dari aplikasi; bila backend memakai arsip/nonaktif, audit tetap
  mengikuti aturan server.
- Sebelum koreksi, aplikasi melakukan pemeriksaan defensif ke fitur Tutup Buku
  Akuntansi. Jika periode sudah tertutup, perubahan dibatalkan. Server tetap
  menjadi pengaman utama untuk penolakan periode terkunci.

## Batas perubahan

Tidak ada perubahan database produksi, nominal transaksi lama, jurnal, atau
deployment server. Koreksi saldo/topup tetap online-only karena menyentuh saldo
akhir dan periode akuntansi. Aplikasi tidak menampilkan sukses lokal palsu untuk
koreksi ini.

## Validasi

- `flutter analyze lib/screens/anggota/tab_mutasi_tabungan.dart test/mutasi_voucher_word_test.dart` - lulus.
- `flutter test test/mutasi_voucher_word_test.dart` - 6 tes lulus.
- `flutter test test/master_offline_kontrak_test.dart` - 25 tes lulus.
- `powershell -ExecutionPolicy Bypass -File tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah,nahl -IzinkanUnsignedWindows` - lulus.

## Artefak Windows

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.46/` dan
tidak disimpan di Git.

| Varian | Installer | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.46.exe` | 89.903.673 byte | `e7212717d3d9a588c652e608a6885e203598348fcbaf42a55a086fe74afd9e8e` |
| TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.46.exe` | 90.056.424 byte | `be0e2abf89242d7db1e71c21095e601172644c35bec6c9bfd7dbf160000a78c6` |

## Status paket

Installer Windows berhasil dibuat dan diverifikasi sebagai `UNSIGNED/UAT` karena
sertifikat Authenticode produksi tidak tersedia di sesi ini. Build release bukan
bukti pemasangan produksi atau UAT pengguna. Publikasi GitHub tidak mengubah
perangkat maupun server secara otomatis.
