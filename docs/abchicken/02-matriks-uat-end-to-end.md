# Matriks UAT End-to-End AB Chicken

Status awal seluruh kasus adalah `BELUM DIUJI`. Ubah menjadi `LULUS` hanya setelah hasil aktual dan lokasi bukti diisi.

| ID | Proses | Skenario dan hasil yang diharapkan | Dampak/rekonsiliasi | Status |
|---|---|---|---|---|
| AB-01 | Varian | App membuka branding AB Chicken dan endpoint `abchiken.ebisnis.id/ebisnis` | Tidak mewarisi server tersimpan varian lain | BELUM DIUJI |
| AB-02 | Hak akses | Role outlet, gudang, pengadaan, produksi, keuangan, akuntansi, auditor melihat menu sesuai tugas | API menolak pemanggilan tanpa hak | BELUM DIUJI |
| AB-03 | Master pilot | Satu toko Pusat AB Chicken, satu gudang utama, satu gudang operasional toko, 50 menu, dan 100 bahan tampil bernilai | Semua ID dan relasi berada di schema tenant; rancangan tetap siap diperluas menjadi sekitar 90 outlet | BELUM DIUJI |
| AB-04 | BOM | Setiap menu mempunyai sedikitnya tiga bahan, kuantitas, satuan, susut, versi aktif | HPP dapat dihitung dan ditelusuri | BELUM DIUJI |
| AB-05 | Pesanan outlet | Outlet membuat/mengajukan pesanan ke pusat atau vendor | Dokumen, rincian, outlet, sumber pemenuhan tersimpan | BELUM DIUJI |
| AB-06 | Alokasi | Pusat memeriksa stok dan mengalokasikan pesanan yang cukup | Qty dialokasi tidak melebihi saldo tersedia | BELUM DIUJI |
| AB-07 | Kekurangan | Kekurangan stok membentuk kebutuhan PR | Referensi pesanan tetap terlacak | BELUM DIUJI |
| AB-08 | PR | Draft→Submitted→Approved; perubahan status ilegal ditolak | Minimal 50 record tampil dan status berbeda | BELUM DIUJI |
| AB-09 | PO | PO termin dan nontermin berasal dari PR/vendor | Total header sama dengan rincian | BELUM DIUJI |
| AB-10 | BAST pusat | Penerimaan mencatat qty baik/rusak/backorder/batch/expiry | Posting menambah stok bahan dan Dr Persediaan/Cr GRNI | BELUM DIUJI |
| AB-11 | Tagihan | Three-way match PO–BAST–invoice | Posting Dr GRNI/Cr Hutang Vendor | BELUM DIUJI |
| AB-12 | Pembayaran | Pembayaran merujuk tagihan dan referensi bank | Posting Dr Hutang Vendor/Cr Bank | BELUM DIUJI |
| AB-13 | Produksi | Produksi memakai BOM, mencatat aktual/susut dan hasil | Bahan turun; barang jadi naik; jurnal seimbang | BELUM DIUJI |
| AB-14 | Packing | Produk setengah jadi/eceran siap kirim | UOM dan kuantitas hasil konsisten | BELUM DIUJI |
| AB-15 | Pengiriman | Picking→Approved→Delivery→Arrived→Completed | Event waktu/lokasi tersedia; desain siap GPS | BELUM DIUJI |
| AB-16 | Bongkar muat | Outlet mencatat diterima, kurang, rusak | Stok tujuan hanya bertambah sesuai penerimaan yang sah | BELUM DIUJI |
| AB-17 | Klaim | Kekurangan/rusak membentuk backorder, retur, pengganti/potong tagihan | Bukti fisik dapat dibuka dari streaming | BELUM DIUJI |
| AB-18 | POS | Pelanggan membeli menu jadi di outlet | Faktur bernilai, stok/menu dan cara bayar benar | BELUM DIUJI |
| AB-19 | Konsumsi BOM | Penjualan menu menghasilkan pemakaian minimal tiga bahan | Qty bahan sesuai resep × qty terjual | BELUM DIUJI |
| AB-20 | Reorder | Saldo melewati titik minimum dan memicu siklus pesanan berikutnya | Tidak membuat permintaan ganda | BELUM DIUJI |
| AB-21 | Pemetaan akun | User berhak melihat sumber akun dan mengganti akun daun relevan | Preview dimuat ulang dari master, bukan ID hard-coded | BELUM DIUJI |
| AB-22 | Filter posting | Semua/Telah/Belum menampilkan jumlah dan kolom pembeda yang benar | Paging tidak menghilangkan record | BELUM DIUJI |
| AB-23 | Idempotensi | Posting dokumen sama dua kali | Hanya satu jurnal dan satu set mutasi stok | BELUM DIUJI |
| AB-24 | Stok negatif | Pengeluaran melebihi saldo ditolak | Tidak ada jurnal/mutasi parsial | BELUM DIUJI |
| AB-25 | Periode tutup | Posting pada periode tutup ditolak dengan petunjuk | Tidak ada jurnal parsial | BELUM DIUJI |
| AB-26 | Jurnal | Seluruh jurnal terposting mempunyai total debit=kredit | Referensi dokumen sumber dan akun dapat ditelusuri | BELUM DIUJI |
| AB-27 | Buku Besar | Drill-down akun menunjukkan jurnal tenant restoran | Saldo awal+mutasi=saldo akhir | BELUM DIUJI |
| AB-28 | Laba Rugi | Pendapatan, HPP, beban, dan laba tampil | Sama dengan jurnal terposting | BELUM DIUJI |
| AB-29 | Neraca | Persediaan, bank, hutang, dan ekuitas tampil | Neraca seimbang | BELUM DIUJI |
| AB-30 | Arus Kas | Pembayaran vendor dan penerimaan POS tampil | Sama dengan mutasi akun kas/bank | BELUM DIUJI |
| AB-31 | Laporan penuh | Tabel memakai lebar ruang kerja, clickable, scroll ke baris terakhir | Screenshot atas/rinci/bawah tersedia | BELUM DIUJI |
| AB-32 | Offline/cache | Daftar membaca cache dahulu; approval/posting tidak memberi sukses semu saat offline | Status sinkron transparan | BELUM DIUJI |
| AB-33 | Isolasi | Data `abchiken` tidak muncul di tenant/schema lain | Query dan cache terikat tenant | BELUM DIUJI |
| AB-34 | Migrasi prod | Dry-run, backup, checksum, restore schema kosong, rekonsiliasi | Main, audit, streaming konsisten | BELUM DIUJI |

## Hasil gerbang otomatis setelah deploy r88246

Tabel utama di atas tetap menyatakan UAT **live/visual** belum diuji sampai login anggota tenant dan
screenshot tersedia. Bukti otomatis berikut berdiri sendiri dan tidak boleh disalahartikan sebagai
kelulusan layar yang belum dibuka.

| Gerbang otomatis | Hasil aktual | Status |
|---|---|---|
| Host dan tenant live | `abchiken` berstatus `READY`, mode `TENANT_ONLY`, schema data/audit siap | LULUS |
| Toko pilot live | Tepat satu `AB-OUT-001 — Pusat AB Chicken`; replay mengembalikan `storeId=6` yang sama | LULUS |
| Volume sumber lokal | 31/31 pemeriksaan; 50 menu, 100 bahan, 170 record per rantai operasi utama | LULUS |
| Filter posting | Per proses: 170 total, 50 telah diposting, 100 siap diposting, 20 tahap awal | LULUS |
| Posting helper aplikasi | 50 BAST + 50 tagihan + 50 pembayaran + 50 produksi + 50 pengiriman | LULUS |
| Idempotensi | 250 replay mengembalikan ID jurnal yang sama; duplikat idempotency key = 0 | LULUS |
| Rekonsiliasi akuntansi/stok | 250 jurnal, 500 detail, 650 mutasi; jurnal tidak seimbang = 0; stok negatif = 0 | LULUS |
| Login dan UI live | Form memakai email anggota tenant; kredensial operator tenant belum tersedia | TERTAHAN |

## Hasil gerbang otomatis setelah deploy r88283

| Gerbang otomatis | Hasil aktual | Status |
|---|---|---|
| Login anggota tenant | Login API pada host kanonik berhasil | LULUS |
| Role | `tenant_list` dan `tenant_context` sama-sama `ADMIN_TENANT` | LULUS |
| Entitlement | `INVENTORY_SALES` dan `PRODUKSI` aktif; replay rekonsiliasi `0/0` | LULUS |
| Isolasi pilihan tenant | Tepat satu tenant id 1, kode `TEN-2026-000001`, status `READY` | LULUS |
| Akses operasi | `si_restaurant_summary` dan `si_restaurant_integrity` dapat dipanggil; alias lama tetap kompatibel | LULUS |
| Volume data live | Satu outlet tersedia; master dan transaksi AB Chicken masih nol | TERTAHAN |

Status tabel r88246 tetap merupakan bukti sumber lokal, bukan data live. Dataset live wajib ditanam
melalui jalur admin server yang diaudit, lalu seluruh pemeriksaan integritas diulang sebelum langkah
visual pada matriks utama diberi status lulus.

## Format hasil aktual

Untuk setiap ID catat: versi client, versi server, waktu, aktor/role, outlet/gudang, nomor dokumen, input utama, respons UI/API, query rekonsiliasi, expected vs actual, lokasi screenshot, status, nomor temuan, perbaikan, dan waktu retest. Satu kegagalan membuat gerbang terkait tidak lulus; kasus tidak boleh “dipaksa” menjadi hijau dengan mengubah data langsung tanpa mencatat perbaikannya.
