# Hasil Re-UAT Pertanyaan WA — Nahl 1.34.36 build 199

Waktu pemeriksaan ulang: 12 September 2026 (Asia/Jakarta)

Varian: **TokoQu Al-Bahjah An Nahl saja**

## Keputusan

Perbaikan aplikasi untuk mencegah kejadian baru **lulus re-UAT**, tetapi seluruh
pertanyaan WA belum boleh dinyatakan selesai di produksi. Stok historis `-3`
dan `-5`, transaksi lama yang terduplikasi, serta status deployment backend
masih memerlukan verifikasi/koreksi operasional.

## Matriks verifikasi ulang

| Pertanyaan WA | Verifikasi 12 September | Keputusan |
|---|---|---|
| Barang masih ada di rak tetapi sistem `Habis/-3` | Bukti sebelumnya menunjukkan server sendiri menyimpan `AN000710 = -3`, bukan sekadar salah tampilan aplikasi. | **Belum selesai pada data lama**; wajib hitung fisik dan Stok Opname. |
| Baygon masuk 5, keluar 5, tetapi sistem `-5` | Server sebelumnya menyimpan `AN001000 = -5` tanpa riwayat stock-in yang ditemukan. Regresi lokal menghasilkan `0 -> masuk 5 -> jual 5 = 0`; retry tetap 0. | **Logika baru selesai**; nilai lama perlu Stok Opname berdasarkan fisik. |
| Server down dan produk tambahan belum muncul | Endpoint Nahl saat re-UAT dapat dijangkau: halaman HTTP 200; API tanpa token membalas HTTP 401, sehingga server merespons dan autentikasi aktif. Jalur master tetap menyimpan lokal saat gangguan teknis. | **Mekanisme pemulihan selesai**; perlu UAT perangkat setelah instalasi. |
| `produk_simpan`: kode dan nama wajib diisi | Tambah Produk Cepat tidak lagi mengirim kode kosong; barcode scan dipakai sebagai kode stabil. | **Selesai di build 199**. |
| `produk_simpan`: UOM dasar/pembelian kosong | UOM wajib dipilih dan `satuan_id` serta `satuan_pembelian_id` ikut disimpan/dikirim. | **Selesai di build 199**. |
| Hampir semua barang menjadi minus | Stok masuk/opname kini disimpan atomik bersama outbox lokal; transaksi POS mengurangi stok lokal tepat sekali dan menunggu mutasi masuk produk terkait tersinkron. Refresh server tidak boleh menimpa mutasi lokal pending. | **Pencegahan baru selesai**; semua SKU lama yang minus tetap perlu rekonsiliasi. |
| Baris transaksi/Excel berulang | Backend guard idempoten sudah dicommit pada SVN r88715. Audit sebelumnya menemukan 42 kelompok faktur historis ganda. | **Belum dapat ditutup di produksi** sampai deployment r88715 dikonfirmasi dan transaksi lama direkonsiliasi. |

## Hasil re-UAT otomatis

- Jalur aplikasi: **57/57 lulus**.
- Core DB local-first: **7/7 lulus**.
- Total tes terarah ulang: **64/64 lulus**.
- Seluruh suite pada commit rilis yang sama: **851/851 lulus**.
- Kanal update varian Nahl: **lulus**, tetap terpisah dari varian lain.
- Git commit aplikasi: `85f64e332ae62142747e701c64dec149079edf00`.
- Backend pencegahan transaksi ganda: SVN `r88715`.

## Skenario stok lokal yang lulus

1. Stok pusat/lokal awal 0.
2. Input stok masuk 5 disimpan atomik ke SQLite dan outbox; stok lokal langsung 5.
3. Penjualan 5 disimpan atomik; stok lokal langsung 0.
4. Retry kode transaksi yang sama tidak mengurangi lagi; stok tetap 0.
5. Refresh server lama saat antrean belum ACK tidak menimpa stok lokal 0.
6. Sinkronisasi mengirim mutasi stok masuk/opname sebelum transaksi penjualan
   produk yang sama.
7. Setelah server ACK, jurnal lokal dibersihkan dan refresh server 0 tetap 0.

## Tindakan produksi sebelum tiket ditutup

1. Instal Nahl 1.34.36 build 199 pada perangkat UAT.
2. Hitung fisik `AN000710` dan `AN001000`; lakukan Stok Opname sesuai hasil
   hitung. Bila fisik Baygon 0, input hasil opname 0, bukan penambahan 5 tanpa
   pemeriksaan fisik.
3. Matikan jaringan, tambah satu produk lengkap dengan barcode dan UOM, lalu
   pastikan produk muncul lokal dengan status menunggu sinkron.
4. Nyalakan jaringan dan pastikan produk yang sama memperoleh ID server tanpa
   membuat duplikat.
5. Pastikan server telah memakai minimal SVN r88715, lalu ulangi kirim satu
   kode transaksi yang sama dan pastikan hanya satu transaksi tercatat.
6. Rekonsiliasi 42 kelompok faktur lama terhadap struk, uang, saldo member,
   dan stok. Pembatalan harus melalui proses resmi, bukan penghapusan database.
7. Ekspor ulang laporan dan nyatakan selesai hanya bila tidak ada duplikat baru
   serta saldo stok sampel sama dengan hitungan fisik.

## Artefak UAT

- APK: `TokoQu-Al-Bahjah-An-Nahl-1.34.36-build-199-UAT.apk`
- Windows: `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.36-UAT.exe`
- APK memakai signing `DEBUG/UAT`; Windows `UNSIGNED/UAT`. Keduanya hanya untuk
  UAT internal, bukan distribusi produksi.
