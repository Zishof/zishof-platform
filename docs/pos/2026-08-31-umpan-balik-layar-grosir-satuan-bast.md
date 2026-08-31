# 62. Umpan Balik Layar (31-08) — Editor Grosir Dapat Diedit, Nominal Satuan Jual, Hasil Sinkron BAST

Tanggal: 31 Agustus 2026  
Status: terpasang & teruji (TesGrosirEditUat **11/11** pada server lokal;
Flutter 586/586, analyze bersih di berkas tersentuh); belum di-commit  
Rujukan: tangkapan layar pemilik 31-08, dok. 59 (BAST → stok), dok. 60
(Metode 2 & kelipatan), dok. 61 (Pack)

## Temuan dari gambar dan penyebabnya

### 1. "Tidak tampil item yang dibuat sebelumnya" (dialog Aturan Harga Grosir)

Kolom **Mulai kuantitas** diisi TEKS (`"Kecap Manis 100g Per Dus"`). Klien
mengirimkannya sebagai `min_qty_dasar = 0`; server menolak dengan benar
(`min_qty_dasar (>0) wajib`), tetapi penolakan itu hanya lewat sebagai
snackbar sekejap — pemilik menyangka aturan tersimpan, lalu daftarnya kosong.
Selain itu dialog memang **tidak punya mode ubah**: satu-satunya aksi pada
baris aturan adalah "nonaktifkan".

**Perbaikan:**

- **Validasi di dialog**: tombol Simpan MATI sampai ambang > 0 dan salah satu
  harga terisi; `errorText` menjelaskan per kolom ("Isi ANGKA lebih dari 0,
  mis. 6"). Isian ber-huruf (nama produk) dibaca 0, bukan ditebak jadi 100.
- **Parser rupiah Indonesia** (`angkaRupiahGrosir`, teruji): "1.200.000" =
  1200000, "1.200.000,5" = 1200000.5, "Rp 65.000" = 65000, teks ber-huruf = 0.
- **Mode UBAH**: ketuk baris aturan (atau ikon pensil) membuka dialog
  ber-prefill dan menyimpan ber-`id` — server memperbarui baris yang sama,
  tidak menumpuk aturan baru.
- **Daftar menampilkan aturan utuh**: Metode 2 tampil sebagai harga PAKET
  (angka yang diketik pemilik) dengan turunan per satuan di baris kedua,
  plus penanda "wajib kelipatan" dan lingkup toko.
- **Pratinjau turunan** saat mengetik harga paket: "= Rp 200.000 / Botol".

### 2. "Nominal mengikuti nilai yang ditentukan dalam UOM Dus" (Kasir)

Dialog **Satuan jual** hanya menampilkan konversi (`= 6.0 Botol`), tidak
nominalnya, sehingga kasir tidak tahu harga per Dus yang akan berlaku.
Pada tangkapan layar harga tetap Rp 250.500/Botol karena aturan grosirnya
memang belum pernah tersimpan (penyebab no. 1).

**Perbaikan:** dialog menampilkan nominal per satuan jual + total:

- produk ber-Pack & satuan = UOM Pack → "Harga pack: Rp 65.000 / Dus · total …"
  (harga tetap dari master, dok. 61);
- selain itu → "Perkiraan Rp … / Dus · total …" dengan catatan jujur bahwa
  **harga grosir final dihitung server** saat keranjang dihitung ulang;
- konversi ditulis bulat ("= 6 Botol", bukan "6.0").

Setelah aturan Metode 2 tersimpan benar (ambang 6, paket Rp 1.200.000),
mesin server memberi Rp 200.000/Botol → total 1 Dus **persis Rp 1.200.000**
(dibuktikan harness, bukan klaim layar).

### 3. "Otomatis stok bertambah" (BAST disetujui)

Mesinnya sudah ada sejak dok. 59 dan **sudah live di produksi** (dibuktikan
harga beli Rp 200.000 pada tangkapan layar — hasil konversi faktur per DUS).
Cacatnya ada di UMPAN BALIK: layar BAST membuang `sinkronOtomatis` dan
`peringatanSinkron` dari respons, sehingga sinkron yang GAGAL (barang belum
berpadanan produk, harga beli nol, akun tanpa hak sinkron) tetap tampak
seperti sukses dan pengguna menunggu stok yang tidak akan bertambah.

**Perbaikan:** layar BAST kini menyampaikan hasilnya apa adanya —
"Disetujui. Stok bertambah otomatis …; buka Produk lalu Muat Ulang",
atau peringatan oranye "Disetujui, TETAPI stok belum bertambah: <alasan>"
(6 detik), atau catatan bahwa keputusan offline baru menggerakkan stok
setelah terkirim.

## Berkas

Flutter: `screens/harga_grosir_editor.dart` (parser + editor ubah + daftar),
`screens/keranjang_screen.dart` (nominal satuan jual),
`screens/pengadaan_bast_screen.dart` (hasil sinkron),
`test/harga_grosir_input_test.dart` (baru, 5 uji parser). Server: tidak ada
perubahan — `harga_grosir_simpan` sudah menerima `id` untuk pembaruan.

## Bukti — TesGrosirEditUat 11/11 (skenario gambar, server lokal)

- aturan Metode 2 "mulai 6 Botol = Rp 1.200.000/paket" tersimpan dan
  **tampil di daftar** ber-`hargaPaket` 1.200.000 + turunan 200.000 +
  penanda kelipatan;
- menyimpan ulang ber-`id` **memperbarui baris yang sama** (daftar tetap
  satu aturan) — tombol Ubah tidak menggandakan;
- mesin harga: qty 6 → 200.000/Botol (total 1 Dus persis Rp 1.200.000);
  qty 12 → Rp 2.400.000; qty 3 (di bawah 1 Dus) → harga katalog;
- kelipatan wajib menolak 7 Botol dengan saran bulatkan ke 6 atau 12.

Flutter suite penuh **586/586**; analyze bersih di ketiga layar tersentuh.

## Catatan penerapan

- Fitur **Pack** (dok. 61, SVN r78639) belum ada di build produksi saat
  tangkapan layar dibuat; Metode 2, kelipatan wajib, dan BAST→stok sudah
  (diverifikasi lewat respons validasi `harga_grosir_simpan` di
  ebisnis.id). Deploy build terbaru + restart untuk mengaktifkan Pack.
- BAST yang **disetujui sebelum** build 31-08 terpasang tidak ikut
  tersinkron otomatis; gunakan tombol "Sinkron ke Kulakan" sekali pada
  dokumen tersebut (idempoten — tidak akan menggandakan stok).
