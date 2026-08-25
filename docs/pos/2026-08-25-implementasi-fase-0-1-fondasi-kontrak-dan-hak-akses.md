# Implementasi Fase 0–1: fondasi kontrak dan hak akses terpadu

Tanggal: 25 Agustus 2026  
Status: **implementasi awal selesai; gerbang parsial lulus**

## Ruang lingkup yang dikerjakan

Fase ini sengaja belum membuat tabel transaksi Pergudangan. Perubahan pertama
difokuskan pada kontrak kompatibilitas agar menu dan route lama tidak kehilangan hak
akses ketika istilah bisnis baru diperkenalkan.

Implementasi server:

- menambahkan `EbisnisMenuActionRegistry` pada kedua source tree server;
- menetapkan kunci menu existing sebagai kunci kanonik selama masa transisi;
- menyelesaikan alias menu PR, PO, BAST vendor, tagihan vendor, pembayaran vendor,
  BDP, Kulakan, mutasi outlet, stok, retur, laporan, dan produksi;
- menyelesaikan alias aksi legacy yang benar-benar ekuivalen: create/tambah,
  update/edit, delete/hapus, approve/setujui, dan reject/tolak;
- mengubah lookup `EbisnisMenuKatalog` agar role JSON lama maupun nama alias baru
  dibaca konsisten;
- mempertahankan perilaku admin existing: role `null` dari helper admin berarti semua
  menu terlihat, sedangkan validasi domain tetap berlaku pada mutasi;
- tidak menyamakan `submit`, `post`, `reverse`, `cancel`, `export`, dan `view_cost`
  dengan CRUD karena risikonya berbeda.

## Keputusan kompatibilitas

`TbmroleAction` dan JSON `Tbmrole.ebisnisMenu` tetap menjadi sumber izin existing.
Registry baru bukan penyimpanan hak akses kedua. Ia hanya menerjemahkan nama kanonik
dan alias sebelum pembacaan izin dilakukan.

Contoh:

| Nama masuk | Kunci kanonik |
|---|---|
| `purchase_order`, `po` | `pengadaan_po` |
| `vendor_bast`, `goods_receipt` | `pengadaan_bast` |
| `vendor_invoice` | `pengadaan_tagihan` |
| `edit`, `ubah` | `update` |
| `setujui` | `approve` |

## Hasil verifikasi

1. Kedua salinan `EbisnisMenuKatalog.java` mempunyai hash SHA-256 identik.
2. Kedua salinan `EbisnisMenuActionRegistry.java` mempunyai isi identik.
3. `mvn -DskipTests compile` lulus setelah perubahan, termasuk kompilasi incremental
   tiga source server.
4. UAT registry dikompilasi dengan `javac -source 1.7 -target 1.7` dan lulus.
5. UAT juga membuktikan `submit`, `post`, dan `reverse` tetap aksi mandiri.

Catatan: `pom.xml` proyek masih mengatur toolchain utama source/target 1.8. Kode yang
ditambahkan tidak memakai lambda, stream, diamond operator, try-with-resources, atau
API Java 8; UAT eksplisit dengan source 1.7 lulus.

## Gerbang Fase 0

| Gerbang | Status | Bukti / tindak lanjut |
|---|---|---|
| Inventaris menu-route awal | Selesai awal | `2026-08-25-menu-route-api-table-role-inventory.csv` |
| Register writer mutasi awal | Selesai awal | `2026-08-25-mutation-writer-register.md` |
| ADR kontrak data | Selesai | `2026-08-25-adr-kontrak-data-terpadu.md` |
| Kompilasi server | Lulus | Maven build success |
| UAT alias Java 1.7 | Lulus | `EbisnisMenuActionRegistryUat` |
| Snapshot schema, row count, orphan, duplikat | Tertunda | Harus dijalankan pada database target yang disetujui |
| Golden dataset dan checksum lintas domain | Tertunda | Tidak boleh direkayasa tanpa snapshot data UAT |
| Uji backup dan restore | Tertunda | Membutuhkan target restore terisolasi dan otorisasi operasi |

## Gerbang Fase 1

| Gerbang | Status |
|---|---|
| Alias menu legacy tidak kehilangan izin | Lulus statis dan unit-UAT |
| Alias aksi CRUD legacy kompatibel | Lulus statis dan unit-UAT |
| Aksi berisiko tidak memperoleh izin CRUD implisit | Lulus unit-UAT |
| Admin melihat seluruh menu | Dipertahankan dari alur existing; UAT UI lintas platform masih diperlukan |
| Audit mutasi approve/post/reverse | Tertunda ke implementasi action granular |
| Paritas Desktop/Android/JSP/ZKoss | Tertunda sampai kontrak `menu_context` final |

## Keputusan melanjutkan fase

Desain DDL aditif Fase 2 boleh dimulai. Migrasi database dan aktivasi writer baru
belum boleh dilakukan sampai audit schema, golden dataset, serta uji backup/restore
lulus. Dengan pagar ini, pekerjaan desain dapat berjalan tanpa mengubah produksi.

