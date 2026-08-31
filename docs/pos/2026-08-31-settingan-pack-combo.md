# 61. Settingan Pack/Combo — Jual per Pack dengan Harga Tetap

Tanggal: 31 Agustus 2026  
Status: terpasang & teruji server lokal (TesPackUat **13/13**, skenario PDF
persis; Flutter 580/580); belum di-commit  
Rujukan: PDF klien "Tolong tambahkan settingan Pack" (31-08), dok. 52
(mesin satuan jual per baris — fondasi), dok. 60 (Metode 2 aturan grosir)

## Kebutuhan PDF vs mesin yang ada

Skenario PDF: Kecap Manis, Botol (reference) Rp 12.000, 1 Dus = 6 Botol,
harga pack Rp 65.000 (SENGAJA bukan 6 × 12.000). Kasir memilih Botol/Dus;
pencatatan mengikuti pilihan (Dus); stok turun per Botol (500 → 494).

Fondasi Fase B sudah menutup separuhnya: satuan jual per baris → server
menurunkan qty dasar (stok 500→494 persis mekanisme teruji dok. 52), baris
menyimpan snapshot satuan/qty/faktor (pencatatan & struk "1 Dus"). Yang
BARU: settingan pack di master + **harga pack tetap** + menu pilihan kasir.

## Keputusan

1. **Master produk**: `pack_aktif` (centang), `satuan_pack` (FK UOM, wajib
   sekategori satuan dasar), `harga_pack` (harga jual TETAP per pack, wajib
   >0 saat aktif). Nonaktifkan pack → kedua kolom dibersihkan. Nullable
   semua — katalog lama tak berubah makna; hbm2ddl membuat kolom.
2. **Server berwenang atas harga pack**: `terapkanSatuanJual` (fungsi persis
   yang dipanggil `bayar`, dok. 52) menimpa harga baris menjadi
   `harga_pack / faktor` saat satuan jual baris = satuan pack produk —
   total per pack selalu persis harga pack (65.000; 2 Dus = 130.000).
   Satuan besar NON-pack (mis. Lusin) dan produk tanpa pack TIDAK tersentuh
   (harga katalog). Aturan grosir tetap dievaluasi SESUDAHNYA — aturan
   komersial menang bila cocok (urutan dok. 51/52).
3. **Katalog** membawa `packAktif`/`satuanPackId`/`satuanPackNama`/
   `hargaPack`/`faktorPackKeDasar` (faktor null bila kategori UOM salah —
   menu pack kasir bersembunyi, admin memperbaiki master).
4. **Kasir (Flutter)**: KETUK produk ber-Pack memunculkan menu
   "Jual sebagai: Botol — Rp 12.000 / Dus — Rp 65.000 (isi 6)". Memilih
   pack menambah baris ber-satuan-jual pack (qtyInput 1, jumlah = isi)
   dengan pratinjau harga pack per-dasar; ketukan pack berikutnya menumpuk
   di baris yang sama. Pemilih satuan generik di keranjang (Fase B) juga
   menyetel harga pack bila satuan yang dipilih = satuan pack.
   **Swa-batal pola Fase B**: stepper mengubah qty hingga bukan kelipatan
   pack → label & harga pack gugur ke katalog (tidak ada klaim bohong);
   grosir dari server tetap menang atas harga pack.
5. **Form Produk**: saklar "Dapat dijual berupa Pack (Combo) di POS" +
   dropdown UOM pack (tersaring sekategori) + harga per pack.

## Berkas

Server: `Produk.java` (3 kolom), `KantinHelper.java` (validasi
`produk_simpan` + timpa harga di `terapkanSatuanJual`), `PosApi.java`
(katalog). Flutter: `models.dart` (field pack + `hargaPackPerDasar` +
preseden `hargaSatuanEfektif`), `kasir_screen.dart` (menu pack +
`_tambahPack`), `keranjang_screen.dart` (pemilih satuan sadar-pack),
`produk_screen.dart` (seksi Pack), `test/pack_kontrak_test.dart` (5 uji).

## Bukti — TesPackUat 13/13 (API admin + refleksi, server lokal)

- validasi: tanpa UOM pack / lintas kategori / harga kosong → ditolak
  dengan pesan terbaca; nonaktif → kolom dibersihkan;
- settingan tersimpan (aktif + Dus + 65.000);
- mesin bayar: 1 Dus → jumlah 6 botol & total PERSIS 65.000; 2 Dus →
  12 botol & 130.000; Lusin (non-pack) → 12.000/botol tak tersentuh;
  produk tanpa pack → tak tersentuh.

Flutter 580/580 (uji pack: pemetaan katalog, subtotal 65.000 bukan 72.000,
swa-batal, grosir menang); analyze bersih di berkas tersentuh.

## Catatan

- Pencatatan akunting "berupa Dus": baris penjualan menyimpan
  `satuan_jual`/`qty_input`/`faktor` (dok. 52) — laporan yang ingin
  menampilkan per-Dus membaca snapshot itu; struk sudah berlabel.
- Pengujian katalog utk akun admin-global API terganjal resolusi toko
  (bukan cakupan Pack); field pack diverifikasi lewat kolom DB + serializer
  yang polanya identik dengan field yang sudah terbukti dibaca form.
