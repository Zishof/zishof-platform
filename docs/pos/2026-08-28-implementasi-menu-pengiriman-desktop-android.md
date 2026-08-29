# Implementasi Menu Pengiriman Desktop dan Android

Tanggal: 28 Agustus 2026

## Tujuan

Menambahkan navigasi terpadu **Distribusi & Pengiriman** pada POS Desktop dan
Android berdasarkan blueprint rantai pasok terdahulu serta alur Freight Order,
Customs Clearance, Delivery Order, shipment, penerimaan, dan pelacakan dalam
dokumen referensi Manajemen Pengiriman Barang.

## Keputusan arsitektur

- **Transfer Antar Lokasi** tetap menjadi pintu mutasi stok existing. Fitur ini
  tidak diduplikasi sebagai transaksi stok baru.
- **Freight Order** mengatur kontrak/rencana angkutan, kapasitas, rute, layanan,
  dan biaya.
- **Delivery Order** menjadi pelepasan operasional barang dari gudang.
- **Shipment & Tracking** mencatat perjalanan muatan.
- **Proof of Delivery** menyimpan bukti serah terima.
- **Penerimaan Transfer Outlet** mencocokkan kiriman dan mem-posting stok outlet.
- **Selisih/Kerusakan/Klaim** menangani exception distribusi.
- **Retur & Reverse Logistics** menangani arus balik outlet ke gudang/vendor.

Pemisahan ini mencegah Freight Order, Delivery Order, dan mutasi stok menjadi
tiga sumber saldo persediaan. Perubahan stok tetap harus melalui posting ledger
yang idempoten sebagaimana blueprint inventory.

## Menu dan hak akses

| Urutan | Menu | Kunci `TbmroleAction` |
|---:|---|---|
| 1 | Transfer Antar Lokasi | `transfer_antar_lokasi` |
| 2 | Delivery Order | `delivery_order` |
| 3 | Freight Order/Rute/Muatan | `freight_order` |
| 4 | Shipment & Tracking | `shipment_tracking` |
| 5 | Proof of Delivery | `proof_of_delivery` |
| 6 | Penerimaan Transfer Outlet | `penerimaan_transfer_outlet` |
| 7 | Selisih/Kerusakan/Klaim | `klaim_distribusi` |
| 8 | Retur & Reverse Logistics | `reverse_logistics` |

Desktop dan Android memakai kunci izin yang sama. Admin tetap memperoleh bypass
melalui `Sesi.instance.isAdmin`, sedangkan pengguna non-admin mengikuti respons
hak akses server yang bersumber dari `TbmroleAction`.

## Implementasi UI

- Shell Desktop dan drawer mobile/Android menampilkan grup yang sama.
- Tujuh proses baru memakai satu layar responsif dengan konfigurasi judul,
  tahapan status, dan kolom yang berbeda per proses.
- Layout memakai `LayoutBuilder`, `Wrap`, dan satu area scroll sehingga tetap
  dapat digunakan pada layar sempit maupun lebar.
- Tujuh proses baru sudah memakai API persisten yang sama untuk daftar, detail,
  tambah/ubah, dan perubahan status. Setiap proses tetap dibedakan oleh nilai
  `jenis`, sehingga tidak menambah tujuh implementasi CRUD yang berulang.
- Form mewajibkan tujuan dan sekurangnya satu rincian dengan nama item serta
  kuantitas positif. Nama field rincian identik di Flutter dan Java:
  `itemId`, `kode`, `nama`, `qty`, `uom`, dan `catatan`.
- Transfer stok memvalidasi toko asal dan tujuan harus terisi serta berbeda.
  Proof of Delivery mewajibkan nama penerima dan URL bukti, sedangkan tagihan
  angkut mewajibkan nomor tagihan dan nilai positif.
- Detail dokumen menampilkan nomor pelacakan, bukti penerimaan, tagihan angkut,
  riwayat perubahan status, dan jurnal posting stok sehingga audit operasional
  dapat dilakukan dari satu layar.
- `clientMutationId` dikirim pada penyimpanan dan memiliki indeks unik per toko,
  sehingga pengulangan request yang sama tidak membuat dokumen ganda.

## Implementasi backend

Endpoint yang aktif melalui `PosApi`:

- `distribusi_list`;
- `distribusi_detail`;
- `distribusi_simpan`; dan
- `distribusi_status`.

Data disimpan pada tabel generik yang tetap terpisah dari ledger stok:

- `inventory_distribution.distribution_document`;
- `inventory_distribution.distribution_document_line`; dan
- `inventory_distribution.distribution_document_event`;
- `inventory_distribution.distribution_stock_posting`.

Struktur tabel, kolom, indeks unik, dan perubahan skema dikelola Hibernate melalui
entity `DistribusiDokumen`, `DistribusiDokumenBaris`, `DistribusiDokumenEvent`,
dan `DistribusiPostingStok` yang telah didaftarkan pada `hibernate.cfg.xml`.
Konfigurasi `hbm2ddl.auto=update` membentuk atau menyesuaikan objek tabel ketika
aplikasi dimulai. Helper tidak menjalankan `CREATE`, `ALTER`, atau DDL lain saat
request, dan tidak ada skrip migrasi SQL manual untuk fitur ini. Namespace schema
PostgreSQL `inventory_distribution` merupakan prasyarat lingkungan deployment.

Backend memakai `openSession()` dan seluruh jalur menutup sesi pada `finally`
melalui `HibernateUtil.closeSessionQuietly(session)`. Kompilasi verifikasi harus
selalu memakai output terpisah dari folder `.java`, sesuai panduan
`2026-08-26-pencegahan-class-di-source-tree.md`.

## Batas transaksi persediaan

Penyimpanan draft, Delivery Order, shipment, POD, dan tagihan angkut tidak
langsung mengubah saldo. Posting baru dijalankan ketika
`penerimaan_transfer_outlet` berstatus selesai: ledger
`koperasi.mutasi_stok_toko` menerima mutasi keluar dari toko asal dan mutasi
masuk ke toko tujuan. `reverse_logistics` yang selesai memakai arah kebalikan.

Setiap baris posting mempunyai kunci unik dokumen/baris/arah pada
`inventory_distribution.distribution_stock_posting`. Pengulangan request atau
status tidak membuat mutasi ganda. Saldo operasional tetap dihitung oleh
`StokKantinUtil` dari ledger signed tersebut; tabel produk tidak diubah langsung.
Jika transaksi posting gagal, transaksi database di-rollback sehingga status
selesai dan mutasi stok tidak dapat tersimpan parsial.

## UAT statis

Kontrak otomatis memeriksa:

- delapan kunci izin identik di shell Desktop dan drawer Android;
- delapan label submenu tersedia;
- layar tetap responsif; dan
- keempat route API tersedia;
- kontrak nama field rincian dan `clientMutationId` konsisten; dan
- validasi tujuan, transfer antar-toko, POD, dan tagihan angkut konsisten; dan
- detail menyediakan timeline status serta jurnal posting stok; dan
- tidak ada lagi pesan placeholder/fail-closed lama.

Test: `apps/ebisnis/test/pengiriman_menu_contract_test.dart`.

Verifikasi 29 Agustus 2026:

- test kontrak Pengiriman: lulus 3/3;
- regresi penuh aplikasi eBisnis: lulus 442/442 test;
- `flutter analyze` pada layar dan test Pengiriman: tanpa masalah;
- helper backend dan `PosApi`: lulus `javac -source 1.7 -target 1.7`;
- hasil kompilasi backend ditempatkan di
  `C:\opt\AIS\ais\.codex-build\pengiriman-final-20260829`, bukan di direktori
  source; kompilasi transitif menghasilkan 18.953 class pada folder build itu;
- Android release varian eBisnis berhasil dibangun pada
  `apps/ebisnis/build/app/outputs/flutter-apk/app-ebisnis-release.apk`;
- Windows release varian eBisnis berhasil dibangun pada
  `apps/ebisnis/build/windows/x64/runner/Release/ebisnis.exe`;
- installer Windows eBisnis 1.34.03 berhasil dibuat pada
  `apps/ebisnis/installer/dist/eBisnis-Setup-1.34.03.exe`; dan
- pemeriksaan pascabuild memastikan tidak ada
  `DistribusiPengirimanApiHelper*.class` di direktori source Java.

Hash artefak UAT eBisnis:

| Artefak | Ukuran | SHA-256 |
|---|---:|---|
| `app-ebisnis-release.apk` | 127.375.517 byte | `A0F77AA57B350D5D1584F8736161A0DC05BE0E6B15B30F50BE32DBA61F1D13B6` |
| `ebisnis.exe` | 91.648 byte | `389FAD715008DB3A567387D0E023D9A6502C4ABB288B445ED92926FBCDA36C5A` |
| `eBisnis-Setup-1.34.03.exe` | 47.210.452 byte | `107F46B4869281C2DA79AAC618B61C34B9432C1420BAC5F748AE016AB6E31365` |

APK ditandatangani dengan sertifikat debug khusus UAT dan installer Windows
belum ditandatangani. Keduanya bukan artefak produksi.

Artefak tersebut adalah hasil build lokal untuk UAT dan belum dipublikasikan.
