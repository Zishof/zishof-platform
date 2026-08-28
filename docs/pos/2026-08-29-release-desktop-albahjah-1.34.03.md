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

### UAT produksi 29 Agustus 2026

- Origin aktif dibuktikan dengan trace unik pada host aplikasi `38.47.178.34`, context `/albahjah`, Tomcat `/backup4/tomcat_ecampus` port lokal `6060`.
- Database target dibuktikan sebagai PostgreSQL `albahjah` pada `38.47.178.46:5432` sebelum migrasi.
- Backup pra-migrasi format custom PostgreSQL tersimpan di `/backup4/deploy-backups/albahjah-uom-r78485-20260829-0125/albahjah-pre-r78485.backup`.
- Ukuran backup: `1.027.859.754 byte`; SHA-256: `2298CEBFF459280B2077F426F1ECDF0E276A7E9C0A02F4401B11C228203209C4`.
- Backup lolos checksum dan katalog restore dapat dibaca oleh `pg_restore` PostgreSQL 17 dengan `24.062` entri.
- Migrasi berjalan dalam satu transaksi dan selesai `COMMIT`: 10 kolom target serta 2 foreign key terbentuk.
- Seluruh 22 UOM lama valid setelah migrasi; 5.975 dari 6.209 produk mendapatkan satuan pembelian dari satuan dasar yang sudah ada.
- Sebanyak 234 produk lama memang belum memiliki satuan dasar. Dampaknya, 228 dari 933 riwayat penerimaan tetap tanpa snapshot satuan. Nilai tidak ditebak agar audit stok/HPP historis tidak berubah; admin perlu melengkapi satuan master produk tersebut.
- Paket 15 class dipasang sebagai overlay terverifikasi pada exploded context, lalu hanya context Al-Bahjah yang di-reload pada `2026-08-29T01:34:44+07:00`. Reload selesai pukul `01:37:37 WIB`; tenant Nahl tetap aktif.
- Pascareload, seluruh 15 hash class cocok, halaman utama publik HTTP 200, dan `PosApi` publik/lokal HTTP 401 tanpa sesi sesuai kontrak keamanan. Tidak ditemukan error baru yang menyebut `PosApi`, `KantinHelper`, `PengadaanProduk`, atau kolom UOM baru; tidak ada sesi database yang terblokir.

Log reload masih memuat peringatan lama Hibernate `SchemaUpdate` pada constraint modul akademik/payroll dan peringatan thread context yang belum berhenti. Keduanya tidak berasal dari perubahan UOM, tetapi perlu tiket teknis terpisah agar reload berikutnya lebih bersih.

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

WAR hasil build bersih disimpan sebagai artefak rilis, tetapi tidak menimpa WAR produksi lama. Produksi memakai overlay class terverifikasi pada exploded context setelah backup database dan arsip rollback tersedia.

### Paket operasional backend

- Paket hot-swap terverifikasi: `C:\opt\release-worktrees\deploy-pos-uom-r78485.zip`
- Ukuran: `339.254 byte`
- SHA-256: `8AFEBDB56D0E38EC629BB04400E406A8C24718CF082036034E1E82A993877244`
- Isi: seluruh `PosApi*.class`, seluruh `KantinHelper*.class`, model `Produk` dan `PengadaanProduk`, migrasi/rollback final, checksum per file, serta runbook deployment dan UAT.
- Endpoint publik `https://ecampus.staialbahjah.ac.id/albahjah/PosApi` terjangkau dan menolak request tanpa sesi dengan HTTP 401 sesuai kontrak keamanan.
- Paket produksi, log migrasi, arsip rollback 15 class, dan bukti checksum tersimpan di `/backup4/deployments/albahjah-uom-r78485-20260829-0125`.
- Deployment produksi selesai melalui overlay class karena WAR lama mengandung entri ZIP tumpang tindih `WEB-INF/lib/JhengHei.jar` dan tidak aman diperbarui in-place. WAR lama tidak ditimpa. Deployment WAR bersih berikutnya wajib memakai hasil SVN minimal `r78485` agar perubahan tetap ikut ketika exploded context diganti.

## Tindak lanjut operasional

1. Admin master data melengkapi satuan dasar pada 234 produk lama yang masih kosong, lalu melakukan sinkronisasi produk. Riwayat lama tidak boleh diubah dengan satuan hasil tebakan.
2. Kasir memasang desktop `1.34.03+161`, menekan **Sinkronkan/Muat Ulang**, lalu menguji satu produk dengan satuan pembelian berbeda dan memastikan stok bertambah dalam satuan dasar.
3. Release owner memperbaiki WAR lama yang mempunyai entri ZIP tumpang tindih sebelum deployment WAR berikutnya.
4. Admin Cloudflare merotasi token tunnel yang sempat terekspos pada keluaran diagnostik deployment. Token lama tidak boleh disalin ke dokumentasi atau chat.
