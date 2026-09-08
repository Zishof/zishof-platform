# Laporan UAT Live Apotik Sederhana

Tanggal pengujian: 8 September 2026

Server: `https://demo.ecampus.id/ecampus`

Varian aplikasi: `apotik`

Frontend yang diverifikasi: `daba55da1b0fc11a0316db576e842640396fc173`

Backend yang diinformasikan telah terdeploy: SVN `r88240`

## Kesimpulan

**PASS.** Tampilan Apotik sederhana dan API pendukung yang telah dideploy dapat dimuat pada aplikasi desktop Windows. Seluruh screenshot pada laporan ini diambil dari widget aplikasi aktual dengan data live server, bukan mockup.

Pengujian ini bersifat `LIVE_READONLY_DAN_CAPTURE_UI`: membuka layar, berpindah tab, memilih resep, mengisi keranjang lokal, dan membuka dialog pembayaran tanpa menekan konfirmasi akhir. Karena itu, run ini tidak menambah transaksi penjualan, tidak membukukan jurnal, dan tidak mengubah stok. Validasi transaksi mutatif 100 data per alur tetap mengacu pada UAT end-to-end terdahulu yang tercatat pada dokumen handover proyek.

## Hasil minimum data

| Area | Data unik terbaca | Hasil |
|---|---:|---|
| Produk obat | 100 dari total 11.000 | PASS |
| Formula racikan | 100 dari total sampel 500 | PASS |
| Formula produksi farmasi | 100 dari total sampel 500 | PASS |
| Resep menunggu | 100 dari total 3.897 pada dashboard | PASS |
| Monitoring batch | 100 | PASS |
| Laporan penjualan | 200 | PASS |
| Permintaan Pembelian (PR) | 105 | PASS |
| Pemesanan Pembelian (PO) | 105 | PASS |
| Penerimaan Barang (BAST) | 105 | PASS |
| Terima Tagihan Vendor | 105 | PASS |
| Pembayaran Vendor | 105 | PASS |

Data pengadaan dihitung lintas halaman karena API live membatasi halaman daftar menjadi 15 baris. Harness menghapus duplikasi berdasarkan ID/kode sebelum mengevaluasi ambang minimal 100.

## Cakupan visual dan fungsi

- Dashboard Apotik memuat prioritas resep, batch mendekati kedaluwarsa, stok, dan daftar tindakan.
- Setup Produk Obat menampilkan katalog, tombol tambah, atribut farmasi, serta lokasi simpan berjenjang: gudang/ruang, zona, lantai, rak, lemari, kulkas/freezer, bin/posisi, dan rentang suhu.
- Menu Penerimaan/PBF tidak ada pada kelompok Apotik. Jalur resmi pembelian adalah PR → PO → BAST → Tagihan → Pembayaran Vendor.
- Kasir menampilkan OTC/Obat Bebas dan Resep Dokter; Racikan dan Produksi Farmasi tersedia sebagai menu kerja terpisah.
- Dialog pembayaran OTC dapat dibuka dan menampilkan Kredit Pelanggan, Online, Tunai, serta pembayaran terpisah.
- Form resep baru memuat pasien/RM, telepon/alamat, dokter/SIP, rumah sakit/klinik, poli, tanggal resep, ICD/diagnosis, indikasi, dan catatan khusus.
- Detail tebus resep menampilkan asal layanan, diagnosis/indikasi, keluhan, anamnesis, alergi, daftar periksa, pemeriksaan kedua, dan konseling.
- Laporan Apotik menampilkan nilai dan kuantitas penjualan serta rekap per golongan obat.

## Bukti eksekusi

Perintah utama:

```powershell
flutter test integration_test/uat_apotik_simplified_manual_capture_test.dart -d windows `
  --dart-define=EBISNIS_VARIANT=apotik `
  --dart-define=POS_TEST_HOST=demo.ecampus.id `
  --dart-define=POS_TEST_CONTEXT=ecampus `
  --dart-define=POS_TEST_USERNAME=demo `
  --dart-define=POS_TEST_PASSWORD=******** `
  --dart-define=POS_TEST_OUTPUT_DIR=<folder-screenshot>
```

Hasil akhir: `All tests passed!` dalam satu run penuh. Ringkasan terstruktur tersimpan pada `screenshots-live-simplified/uat-simplified-summary.json`.

## Batas validasi

- Screenshot menampilkan data sample/UAT dan tidak boleh dipakai sebagai keputusan klinis untuk pasien nyata.
- Tombol konfirmasi pembayaran tidak ditekan pada run pascadeploy ini agar tidak menambah transaksi live.
- Beberapa keterangan data seed pengadaan lama memuat karakter pengganti akibat encoding sumber data; tidak menghambat status, nilai, dan relasi dokumen.
