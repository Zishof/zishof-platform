# Publikasi eBisnis POS Desktop 1.34.16

Tanggal: 1 September 2026
Varian yang dipublikasikan: **eBisnis Desktop saja**
Status: lulus gerbang source, analisis, test, build, checksum, dan siap UAT

## Ruang lingkup source yang diaudit

Build dibuat ulang dari seluruh source `main` terbaru setelah memastikan tidak
ada perubahan lintas sesi yang tertinggal. Ruang lingkup yang ikut terbawa:

- aturan harga grosir dapat ditambah dan diubah tanpa menggandakan baris;
- Pack/Combo dengan UOM pack, harga tetap per pack, dan pengurangan stok dalam
  satuan dasar;
- pemilihan satuan jual di kasir beserta nominal dan konversinya;
- penerimaan BAST memberi status sinkron stok yang eksplisit;
- label satuan pembelian, harga beli manual, ledger stok, dan fitur terkait UOM;
- seluruh mutasi yang memenuhi syarat antre mengikuti aturan wajib
  **local-first**: simpan lokal dan outbox lebih dahulu, kemudian retry
  idempoten ke server tanpa menghilangkan data lokal.

Perapihan tambahan pada rebuild ini menghapus cast integer yang tidak diperlukan
di paginasi detail laporan. Tidak ada perubahan perilaku bisnis pada perapihan
tersebut.

## Bukti verifikasi

- Test kontrak Pack/UOM/grosir/pengadaan/kulakan: **30 lulus**.
- Seluruh test eBisnis: **586 lulus, 0 gagal**.
- `flutter analyze --no-pub --no-fatal-infos`: **0 error, 0 warning**;
  tersisa 51 saran informasi/gaya lama.
- Build Windows release dan pembuatan installer selesai tanpa kegagalan.
- File pada folder build dan folder artefak memiliki ukuran dan SHA-256 sama.

## Artefak yang dipublikasikan

- File: `eBisnis-Setup-1.34.16.exe`
- Ukuran: **85.852.643 byte**
- SHA-256: `D28569021DDBD79D1E57145BF2FD27A0555ADB17B683D5C8A06F00C6314759D6`
- Tanda tangan: **UNSIGNED/UAT**; Windows dapat menampilkan SmartScreen.
- Tautan: <https://github.com/Zishof/zishof-platform/releases/download/v1.34.16/eBisnis-Setup-1.34.16.exe>

## Prasyarat dan batas aman

- Fitur Pack/Combo memerlukan backend SVN **r78639 atau lebih baru** dan restart
  layanan setelah deployment.
- BAST lama tidak memiliki snapshot UOM/faktor konversi. Bila payload lama
  tidak membawa satuan, server memakai UOM pembelian produk yang aktif saat
  sinkron. Supervisor wajib memeriksa dokumen lama jika UOM produk pernah
  berubah; tidak ada migrasi historis spekulatif pada rilis ini.
- Instalasi baru sebaiknya dicoba di satu perangkat UAT, login, sinkronkan data,
  lalu uji Pack/UOM, transaksi kasir, penerimaan BAST, dan retry outbox sebelum
  rollout luas.

## Rollback

Jika ditemukan regresi, hentikan rollout, pasang kembali installer versi
sebelumnya, dan jangan menghapus database lokal/outbox. Simpan Log Error serta
kode referensi agar antrean lokal dapat diperiksa dan dikirim ulang setelah
penyebabnya diperbaiki.

## Template balasan WA

### eBisnis

Assalamu'alaikum warahmatullahi wabarakatuh. Build terbaru eBisnis POS Desktop
versi 1.34.16 sudah selesai dibangun ulang dari seluruh source terbaru dan sudah
lulus 586 pengujian. Perubahan Pack/Combo, aturan harga grosir, pilihan satuan
jual, informasi sinkron stok BAST, ledger stok, serta penguatan local-first ikut
terbawa. Silakan unduh melalui tautan berikut:
https://github.com/Zishof/zishof-platform/releases/download/v1.34.16/eBisnis-Setup-1.34.16.exe

Setelah instalasi, mohon uji dahulu pada satu perangkat: login, sinkronkan data,
cek transaksi kasir, satuan/Pack, penerimaan BAST, dan pastikan antrean pending
terkirim. Data lokal dan antrean jangan dihapus apabila server sedang bermasalah;
aplikasi akan mencoba mengirim ulang secara otomatis. Installer ini masih
berstatus unsigned/UAT sehingga peringatan Windows SmartScreen mungkin muncul.
Mohon kirimkan kode referensi dari Log Error apabila ada kendala. Terima kasih.

### Al-Bahjah

Assalamu'alaikum warahmatullahi wabarakatuh. Source bersama untuk POS telah kami
audit ulang dan seluruh 586 test lulus. Namun pada publikasi ini kami hanya
membangun dan mengunggah varian eBisnis Desktop; installer Al-Bahjah tidak
dipublikasikan ulang agar tidak memberi tautan versi yang belum dibangun dari
commit rilis ini. Varian Al-Bahjah akan memperoleh tautan tersendiri setelah
build dan checksum khusus variannya selesai diverifikasi. Terima kasih.

### Nahl

Assalamu'alaikum warahmatullahi wabarakatuh. Source bersama untuk POS telah kami
audit ulang dan seluruh 586 test lulus. Pada proses publikasi ini hanya varian
eBisnis Desktop yang dibangun dan diunggah. Varian Nahl Desktop/Android tidak
ikut dipublikasikan ulang, sehingga mohon tetap menggunakan tautan rilis Nahl
yang terakhir sampai build khusus Nahl selesai dibuat dan diverifikasi. Terima
kasih.
