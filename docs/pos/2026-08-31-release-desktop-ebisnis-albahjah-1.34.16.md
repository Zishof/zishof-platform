# Rilis POS Desktop 1.34.16 — eBisnis dan Al-Bahjah

Tanggal: 31 Agustus 2026  
Status: dibangun dan diverifikasi dari satu commit sumber

## Perubahan utama

Rilis ini membawa perbaikan dari umpan balik layar pemilik (dok. 62) beserta
fitur Pack/Combo (dok. 61) yang sebelumnya belum pernah masuk build:

- **Aturan Harga Grosir dapat diubah.** Ketuk baris aturan (atau ikon pensil)
  membuka dialog ber-prefill dan menyimpannya ber-`id`, sehingga server
  memperbarui baris yang sama — bukan menumpuk aturan baru.
- **Isian aturan divalidasi di layar.** Tombol Simpan mati sampai ambang
  kuantitas > 0 dan salah satu harga terisi; teks ber-huruf (mis. nama produk
  yang salah ketik ke kolom kuantitas) ditolak dengan pesan jelas, tidak lagi
  dikirim sebagai ambang 0 yang ditolak diam-diam oleh server. Pemisah ribuan
  Indonesia dibaca benar ("1.200.000" = 1200000).
- **Daftar aturan menampilkan isi sebenarnya**: harga per paket (Metode 2)
  berikut turunan per satuan, penanda kelipatan wajib, dan lingkup toko.
- **Pack/Combo di master produk dan kasir.** Produk dapat ditandai boleh
  dijual per pack dengan UOM pack dan harga TETAP per pack; kasir memilih
  satuan atau pack saat produk diketuk. Stok tetap turun per satuan dasar.
- **Dialog Satuan jual menampilkan nominal**, bukan hanya konversi: harga per
  satuan jual dan totalnya, dengan catatan jujur bahwa harga grosir final
  dihitung server.
- **Layar Penerimaan Barang (BAST) menyampaikan hasil sinkron stok**:
  konfirmasi stok bertambah, atau peringatan berisi alasan bila sinkron tidak
  berjalan — sebelumnya kegagalan sinkron tampak seperti sukses.
- Ikut terbawa dari pohon kerja yang sama: label satuan pembelian pada layar
  PR/PO, saklar harga beli manual, rute MTO dan tanda QC pada produk, serta
  ledger mutasi stok pada Laporan dan Stok Opname.

## Bukti pengujian sebelum build

- `flutter analyze --no-pub --no-fatal-infos`: **0 error, 0 warning**
  (51 saran gaya/informasi lama tidak memblokir build).
- `flutter test --no-pub`: **586 lulus / 0 gagal**.
- Sisi server pada UAT lokal: `TesGrosirEditUat` 11/11 (aturan tampil di
  daftar, Ubah tidak menggandakan, 1 Dus = persis Rp 1.200.000, kelipatan
  wajib menolak qty nanggung) dan `TesPackUat` 13/13 (harga pack tetap, stok
  turun per satuan dasar).

## Artefak

- Commit sumber: lihat commit `release(pos): desktop ebisnis dan albahjah
  1.34.16` pada `main`.
- eBisnis Desktop: `eBisnis-Setup-1.34.16.exe` (85.852.643 byte), dibangun
  ulang dari seluruh source terbaru pada 1 September 2026.
  - SHA-256: `D28569021DDBD79D1E57145BF2FD27A0555ADB17B683D5C8A06F00C6314759D6`.
- Al-Bahjah POS Desktop: `Al-Bahjah-POS-Setup-1.34.16.exe` (85.908.633 byte).
  - SHA-256: `67DBB90EFAFACC99E74DDC832FDED3B4D276246EBA812D187DCD59F2708A20E5`.

Kedua installer dibangun skrip multi-varian dalam satu proses (4,2 menit) dari
pohon kerja yang sama. Installer Windows belum ditandatangani sertifikat
publik dan ditandai `UNSIGNED/UAT` oleh pipeline; pengguna Windows mungkin
menerima peringatan SmartScreen.

Pada publikasi 1 September 2026 hanya installer **eBisnis Desktop** yang
diunggah sebagai rilis GitHub. Artefak Al-Bahjah di atas tetap merupakan hasil
build 31 Agustus dan tidak dipublikasikan ulang pada proses tersebut.

## Prasyarat sisi server

Perbaikan layar di atas memakai kontrak API yang sudah ada, KECUALI
**Pack/Combo** yang menuntut server ber-build ≥ SVN r78639 (kolom
`pack_aktif`, `satuan_pack`, `harga_pack` dibuat `hbm2ddl` saat boot — tanpa
DDL manual). Deploy build server terbaru lalu restart sebelum mengaktifkan
Pack pada master produk.

## Batas kompatibilitas dokumen BAST lama

BAST lama tidak menyimpan snapshot UOM/faktor konversi tersendiri. Jika payload
sinkron dokumen lama tidak membawa satuan input, server memakai UOM pembelian
produk yang aktif saat sinkronisasi. Karena itu perubahan UOM produk setelah
dokumen lama dibuat perlu diperiksa supervisor sebelum validasi; rilis Desktop
ini tidak menebak atau memigrasikan histori tersebut secara otomatis.
