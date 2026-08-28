# Rilis Desktop Al-Bahjah POS 1.34.03

Tanggal: 29 Agustus 2026  
Versi aplikasi: `1.34.03+161`  
Varian: `albahjah`  
Tag GitHub: `v1.34.03-build161`

## Ringkasan

- Satuan dasar/penjualan dan satuan pembelian produk memakai master UOM yang berelasi.
- Kuantitas dan harga pembelian dikonversi ke satuan dasar saat penerimaan, sedangkan satuan input dan faktor konversinya disimpan sebagai snapshot audit.
- Kemasan/barcode multi-unit dipisahkan dari UOM akuntansi. Pemindaian barcode kemasan di Kasir menambahkan kuantitas satuan dasar sesuai isi kemasan.
- Validasi mencegah UOM lintas kategori, faktor konversi tidak valid, serta barcode kemasan ganda.
- Pesan penolakan menjelaskan penyebab dan tindakan koreksi yang dapat dilakukan pengguna.

## Urutan penerapan

1. Jalankan `migrasi_uom_kategori_pembelian_20260828.sql` pada database server.
2. Deploy server/SVN revisi `r78485` (`r78484` implementasi runtime, `r78485` penguatan migrasi).
3. Pasang desktop Al-Bahjah POS 1.34.03.
4. Tekan **Sinkronkan/Muat Ulang** agar master UOM dan produk terbaru masuk ke cache lokal.

Jangan memasang desktop sebelum migrasi dan server baru aktif karena penyimpanan produk/pembelian memakai kolom dan kontrak API baru.

## UAT

- Analisis statis Flutter pada modul UOM, produk, pembelian, dan kasir: lulus.
- Seluruh pengujian aplikasi Flutter: 437 lulus.
- Seluruh pengujian `core_db`: 9 lulus.
- Kompilasi Java 8 terarah untuk model, API POS, dan helper pembelian: lulus.
- Full build backend dari snapshot SVN bersih: 7.288 sumber Java terkompilasi dan Maven menghasilkan `ais.war` (`BUILD SUCCESS`).
- Parser PostgreSQL menerima migrasi dan rollback final tanpa kesalahan sintaks.
- Kesesuaian salinan sumber Java `java/` dan `src/`: terverifikasi identik sebelum commit.

## Rollback

- Hentikan rollout bila simpan produk/pembelian gagal, hasil konversi stok tidak sesuai, atau sinkronisasi master UOM ditolak server.
- Kembalikan aplikasi ke rilis sebelumnya dan server ke revisi sebelum `r78484`.
- Jalankan `rollback_uom_kategori_pembelian_20260828.sql`. Skrip mempertahankan kolom audit/snapshot agar bukti transaksi tidak hilang.

## Artefak

- File: `Al-Bahjah-POS-Setup-1.34.03.exe`
- Ukuran: `47.230.693 byte` (`45,04 MiB`)
- SHA-256: `B7BF9046455660DFAC210B0FE5CC9C8DFDE5E042C809F95AC034FC3AAF89F265`
- Metadata executable: `Al-Bahjah POS 1.34.03+161`
- Authenticode: belum ditandatangani (`NotSigned`). Jika Windows menampilkan peringatan penerbit, cocokkan nama file dan SHA-256 sebelum melanjutkan instalasi.

Build dilakukan dari checkout bersih pada commit Git `4f81136`; perubahan lokal dari pekerjaan lain tidak masuk ke artefak.

### Artefak backend untuk release owner

- Source: snapshot SVN bersih sampai `r78485`.
- File lokal: `C:\opt\release-worktrees\ais-r78484\build\maven\ais.war`
- Ukuran: `747.885.455 byte` (`713,24 MiB`)
- SHA-256: `89E369C4F27E7A08406D2152C588AE89ADFC5D96522819F2945387A379A33A9A`
- Isi diverifikasi memuat kelas `PosApi`, `KantinHelper`, `Produk`, `PengadaanProduk`, serta SQL migrasi/rollback final.

WAR tidak dipasang otomatis ke produksi. Deployment membutuhkan backup database, endpoint target, kredensial release owner, jadwal maintenance, dan observasi runtime setelah restart.

### Paket operasional backend

- Paket hot-swap terverifikasi: `C:\opt\release-worktrees\deploy-pos-uom-r78485.zip`
- Ukuran: `339.254 byte`
- SHA-256: `8AFEBDB56D0E38EC629BB04400E406A8C24718CF082036034E1E82A993877244`
- Isi: seluruh `PosApi*.class`, seluruh `KantinHelper*.class`, model `Produk` dan `PengadaanProduk`, migrasi/rollback final, checksum per file, serta runbook deployment dan UAT.
- Endpoint publik `https://ecampus.staialbahjah.ac.id/albahjah/PosApi` terjangkau dan menolak request tanpa sesi dengan HTTP 401 sesuai kontrak keamanan.

Deployment produksi belum dijalankan karena host asal berada di balik Cloudflare dan tidak ada profil server lokal yang dapat dibuktikan sebagai target Al-Bahjah. Operator wajib mengonfirmasi host/context, service Tomcat, database target, backup, dan jadwal maintenance; jangan memilih profil SSH berdasarkan perkiraan.
