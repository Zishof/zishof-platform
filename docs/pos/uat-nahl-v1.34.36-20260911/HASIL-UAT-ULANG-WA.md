# Hasil UAT Ulang WA — TokoQu Al-Bahjah An Nahl v1.34.36

Tanggal pemeriksaan: 11–12 September 2026 (Asia/Jakarta)

Varian: **Nahl saja** (`EBISNIS_VARIANT=nahl`)

Server: `https://an-nahl.santri.info/nahl/Api_eBisnis`

## Kesimpulan

Belum seluruh persoalan operasional dapat dinyatakan selesai di produksi.
Perbaikan perangkat lunak untuk pembuatan produk cepat dan pencegahan transaksi
ganda sudah diterapkan serta lolos pengujian. Koreksi saldo stok fisik dan
rekonsiliasi transaksi historis tetap memerlukan tindakan data yang terkontrol;
angka tidak diubah otomatis agar stok, saldo member, dan omzet tidak rusak.

## Verifikasi bukti WA dan data pusat

| Pertanyaan/temuan WA | Hasil pemeriksaan | Status |
|---|---|---|
| Produk `AN000710` SUKY SUKY SEAWEED FLAVOR 60GR tampak **Habis/-3**, tetapi barang ada di rak | API produksi juga mengembalikan stok `-3`; jadi bukan cache atau salah tampilan. Riwayat stok opname terakhir tidak ditemukan dan statistik menunjukkan belum ada pengadaan tercatat. | **Perlu stok opname fisik**; jumlah fisik pasti harus diinput petugas. |
| Baygon `AN001000` masuk 5, terjual 5, tetapi tampil **-5** | API produksi mengembalikan stok `-5`. Statistik stok tidak menemukan pengadaan/stock-in terakhir untuk SKU tersebut; berarti penjualan 5 sudah tercatat, sedangkan mutasi masuk 5 belum tercatat di pusat. | **Penyebab terverifikasi**; mekanisme local-first diperbaiki di build 199, sedangkan data lama perlu satu kali stok opname fisik. |
| “Tambah produk” belum muncul / harus tetap bisa saat jaringan terganggu | Ditemukan bug pada Tambah Produk Cepat: payload mengirim `kode` kosong dan tidak mengirim satuan stok/pembelian. Sekarang kode memakai barcode hasil scan, UOM wajib dipilih, daftar UOM dapat berasal dari cache, dan draf disimpan lokal lebih dahulu. | **Selesai di build 199**. |
| Error `produk_simpan`: kode dan nama wajib diisi | Produk `SOSOFT FLORAL LILY 700ML` dikirim dengan `kode=""`. Build 199 tidak lagi mengirim kode kosong pada jalur Tambah Produk Cepat. | **Selesai di build 199**. |
| Error `produk_simpan`: satuan stok/dasar dan satuan pembelian wajib dipilih | Edit GOOD DAY mengirim `satuan_id=null` dan `satuan_pembelian_id=null`. Build 199 mewajibkan keduanya; Tambah Produk Cepat mengirim satu UOM valid untuk kedua field. | **Selesai di build 199**. |
| Gangguan `so_perubahan_stok`: server tidak menjawab | Bukti teknis menunjukkan kegagalan jaringan sebelum ada respons server. Jalur simpan master tetap local-first dan antrean dapat dikirim ulang saat koneksi pulih. | **Mekanisme pemulihan tersedia**; konektivitas perangkat tetap perlu dipastikan. |
| Baris laporan/Excel berulang | UAT baca-saja tanggal 8–11 September menemukan 366 baris, 324 nomor faktur unik, dan **42 kelompok nomor faktur ganda** (masing-masing dua transaksi). Contoh `EB260910110558QDUD` tersimpan sebagai ID 407 dan 521 dengan waktu, item, dan total Rp11.500 yang sama. | **Pencegahan selesai di SVN r88715; data lama perlu rekonsiliasi**. |

## Perbaikan yang diuji

1. Tambah Produk Cepat menolak proses bila master UOM belum tersedia, bukan
   membuat draf invalid yang terus gagal sinkron.
2. Kode produk cepat tidak kosong dan stabil: memakai barcode hasil scan.
3. `satuan_id` dan `satuan_pembelian_id` selalu dikirim.
4. Produk lokal dengan ID sementara negatif tetap terlihat di Master Produk,
   tetapi tidak dapat dipilih di POS sampai server memberi ID positif.
5. Backend mengurutkan request checkout dengan kode nota yang sama, memeriksa
   transaksi yang sudah ada sebelum efek saldo/stok, lalu mengembalikan ACK
   idempoten. Perbaikan backend tercatat pada **SVN r88715**.
6. Input stok/opname tersimpan atomik bersama antrean lokal dan langsung
   memperbarui cache stok perangkat.
7. Transaksi POS tersimpan atomik bersama jurnal pengurangan stok lokal. Kode
   transaksi yang sama hanya memengaruhi stok satu kali.
8. Sinkron POS menjalankan antrean stok masuk/opname terlebih dahulu dan menahan
   penjualan bila mutasi stok produk terkait masih pending/gagal.
9. Refresh katalog tidak boleh menimpa stok produk yang masih memiliki jurnal
   transaksi atau mutasi stok lokal yang belum diakui server.
10. Edit identitas/harga produk tidak mengirim field `stok` bila stok tidak
    benar-benar diubah.

## Hasil pengujian otomatis

- Skenario regresi Baygon local-first: **lulus** — stok awal 0, masuk 5 menjadi
  5, jual 5 menjadi 0, retry transaksi yang sama tetap 0, refresh server lama
  tidak menimpa 0, dan ACK server mempertahankan 0.
- Tes terarah perubahan ini: **64/64 lulus** (57 aplikasi + 7 Core DB).
- Seluruh rangkaian tes aplikasi: **851/851 lulus**.
- Kompilasi Java `KantinHelper.java` (Java 8): **lulus**.
- `flutter analyze`: tidak ada error/warning baru; 45 info lint lama di luar
  perubahan ini tetap tercatat.
- APK Nahl 1.34.36+199: **berhasil**, 191.531.089 byte, SHA-256
  `1A513E80531ED0E37F16C6F6CDE83CD1CF4245A29B466F0462A063E88155C0B9`.
- Installer Windows Nahl 1.34.36: **berhasil**, 86.178.218 byte, SHA-256
  `460CE670FB54D3B1D430BECA109223E45332C011174112E70A4BB917A6E99A1F`.
- Signing artefak: APK `DEBUG/UAT`; Windows `UNSIGNED/UAT`. Keduanya hanya
  untuk UAT internal dan akan dipublikasikan sebagai GitHub prerelease.

## Langkah UAT produksi yang masih wajib

1. Deploy backend minimal **SVN r88715**.
2. Instal build Nahl 1.34.36 (build 199), lalu sinkronkan master UOM dan Produk.
3. Scan barcode produk baru, pilih UOM, matikan jaringan sebelum Simpan, dan
   pastikan draf muncul di Master Produk tetapi belum dapat dijual. Nyalakan
   jaringan dan pastikan sinkron menghasilkan satu produk dengan ID server.
4. Kirim ulang satu payload transaksi dengan `kodeUnik` yang sama dan pastikan
   ID transaksi pada balasan kedua sama serta jumlah baris laporan tidak naik.
5. Hitung fisik SKU `AN000710`, lalu lakukan **Stok Opname** dengan jumlah hasil
   hitung. Jangan mengubah stok langsung dari form produk.
6. Hitung fisik SKU Baygon `AN001000`, lalu lakukan **Stok Opname** satu kali
   untuk mengoreksi data historis `-5`. Bila fisik memang 0, input hasil opname
   0; jangan menambah 5 tanpa hitung fisik.
7. Audit 42 pasangan transaksi historis terhadap struk/uang/saldo member.
   Batalkan hanya baris yang dipastikan duplikat; jangan menghapus langsung di
   database karena efek stok dan voucher juga harus dibalik melalui proses
   pembatalan resmi.

Balasan WA final berstatus “selesai seluruhnya” hanya boleh dikirim setelah
langkah 1–7 menghasilkan selisih nol.
