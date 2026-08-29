# Audit CRUD yang masih memanggil ApiClient langsung (Prioritas 4 handover)

Tanggal audit: 29 Agustus 2026  
Basis: `main` @ `b899ed6` dengan working tree dirty (perubahan biometrik + Pengiriman milik sesi lain, tidak disentuh)  
Ruang lingkup: `apps/ebisnis/lib/screens` — pemanggilan `ApiClient.instance.aksi(...)` yang tidak melalui `MasterOffline`, outbox transaksi, atau outbox Inventory & Sales.

## 1. Metode

Pola pencarian (ripgrep):

- `ApiClient\.instance\.aksi` satu baris → 291 kemunculan di 98 file;
- bentuk multiline (`ApiClient.instance` lalu `.aksi('...'` di baris berikut, atau argumen di baris berikut) → ±110 kemunculan tambahan;
- total call-site `\.aksi\(` di `lib/screens`: **398 kemunculan di 106 file**;
- pembanding adopsi Local-First: `MasterOffline.(daftarCacheDulu|simpanAtauAntre)` → 137 kemunculan di 82 file; `KilauBaris|DiffDaftarLokal` → 94 kemunculan di 56 file;
- `lib/services` memiliki 23 call-site `\.aksi(` di 8 file — ini **legitim** (MasterOffline, outbox transaksi, outbox IS, sinkronisasi) dan bukan objek audit.

Tiap aksi diklasifikasikan dari semantik nama aksi + pembacaan konteks pada call-site dinamis (aksi berupa variabel). Klasifikasi mengikuti kontrak handover: **cached-read**, **queueable-mutation**, atau **online-only**.

## 2. Kesimpulan eksekutif

Mayoritas pemanggilan langsung yang tersisa **memang pantas online-only** (login, PIN/biometrik, saldo real-time, posting jurnal/closing, perhitungan server, file transfer, pencarian typeahead). Sisa pekerjaan Local-First yang bernilai nyata terkonsentrasi pada tiga kelompok:

1. **Master/opsi referensi yang dibaca berulang lintas layar** (terutama `akun_list`, `konfigurasi`, `toko_profil_ambil`, keluarga `*_opsi`) — kandidat cached-read terkuat;
2. **Statistik/dashboard dan daftar laporan** — kandidat cached-read dengan label "data tersimpan", wajib patuh aturan pagination (jangan hapus cache dari satu halaman);
3. **Sedikit mutasi master dan log non-kritis** (`produk_simpan` di bulk entry, `pedagang_ubah`, `si_print_log_create`) — kandidat queueable-mutation.

Beberapa layar (mis. `anggaran_screen.dart:335-341`) sudah **sengaja** memakai jalur online untuk aksi yang harus dihitung server dan mendokumentasikannya dalam komentar — pola ini benar dan jangan "dimigrasikan".

## 3. Klasifikasi

### 3.1 Online-only yang sudah benar — JANGAN diantrekan

| Kelompok | Aksi (contoh lokasi) | Alasan |
|---|---|---|
| Autentikasi | `login` (login_screen.dart:40, layar_kunci_screen.dart:89), `akun_ganti_password` (akun_saya_screen.dart:40), `pilih_toko_aktif` (kasir_screen.dart:407-489) | Kontrak arsitektur: autentikasi online-only |
| PIN & biometrik | `verifikasi_pin`, `verifikasi_biometrik_member`, `biometrik_kemampuan/daftar/simpan/nonaktifkan` (keranjang_screen.dart:958-1030, member_biometric_panel.dart:83-212) | Bukti biometrik berumur 5 menit; enrollment/verifikasi wajib online; material biometrik dilarang masuk outbox |
| Pembayaran & saldo | `bayar`, `draft_bayar` (keranjang_screen.dart:1507,1641; pesanan_screen.dart:820,1440), `saldo_member` (keranjang_screen.dart:670), `topup_saldo`/`deposit_ubah` (tab_topup.dart:288,751; tab_mutasi_tabungan.dart:314), `pencairan_diskon_saldo_member`, `penyesuaian_saldo_cek/list` (tab_saldo_voucher.dart:502-519), `uang_muka_saldo`, `kas_kecil_saldo`, `anggota_transaksi_terbaru` | Operasi/pembacaan saldo real-time; `bayar` punya jalur outbox transaksi tersendiri — panggilan langsung di sini adalah jalur online/rekonsiliasi (riwayat_sinkronisasi_screen.dart:238) yang memang harus menunggu ACK server |
| Sesi kas | `sesi_kas_status/buka/tutup/koreksi` (kasir_screen.dart:629-911, tab_sesi_kasir.dart:606) | Status kas real-time, koreksi supervisor |
| Posting akuntansi | `jurnal_umum_posting` (+ posting/hapus dinamis jurnal_umum_screen.dart:182), `posting_${jenis}_draft/terapkan` (posting_toko_dialog.dart:84,131), `closing_periksa/jurnal`, `proses_transfer/transitori_*`, `pemetaan_akun_terapkan/usulan`, `kode_akun_bersihkan`, `siklus_akuntansi` dinamis (siklus_akuntansi_screen.dart:162) | Posting final/jurnal — kontrak: online-only |
| Koreksi & audit | `batalkan_transaksi`, `edit_transaksi` (riwayat_penjualan_screen.dart:1797,1833; ringkasan/tab_umum.dart:1075), `revisi_entitas/jelajah/pulihkan_massal`, `perbaiki_nilai_bayar` (riwayat_audit_screen.dart) | Operasi berisiko atas data server; wajib konfirmasi + validasi server |
| Perhitungan server | `diskon_evaluasi` (keranjang/kasir/price_tag), `*_hitung` (kas_kecil/kas_besar/pj_*/penggantian/reimbursement/pesanan_hitung_ulang), `*_resolve` (pengadaan_barang/grup_produk/diskon_grup), aksi dinamis anggaran `_kirimServer` (anggaran_screen.dart:338) | Hasil tidak punya bentuk lokal yang benar; mengantrekannya berisiko duplikasi (sudah didokumentasikan di source anggaran) |
| Workflow SOP/approval | `sop_ajukan/proses/ubah/batalkan_langkah/batalkan_pengajuan` (pengajuan_baru_screen.dart:507; pengajuan_anda_detail_screen.dart:101-205) | Rantai persetujuan butuh status server terkini |
| Hotel (MitraInap) | `hotel_reservasi_buat/checkin/checkout/pindah_kamar/tamu_simpan/folio_get/room_charge_lookup` | Ketersediaan kamar real-time |
| File & cetak | `produk_foto_upload`, `layar_pelanggan_slide_upload`, `pengadaan_lampiran_unggah/unduh`, `laporan_pdf`, `keuangan_cetak`, `pengadaan_cetak`, `sop_cetak`, `so_impor_excel/so_ekspor_excel`, `produk_impor_excel_preview/komit`, `produk_nonaktifkan_tak_diimpor`, `si_import_legacy`, `_defAksiImpor` (kode_akun_screen.dart:466) | Transfer berkas/bulk import — payload besar, butuh umpan balik langsung |
| Sinkronisasi | `sinkron_referensi` + aksi dinamis (tab_sinkronisasi.dart:89,143), `anggota_sync_list`, `transaksi_backup_status/toko_list` | Layar sinkronisasi memang online by definition |
| Demo/dev | `pos_demo_seed_*`, `pos_demo_status`, `apotik_provision_demo`, `hotel_data_contoh` | Alat pengembangan, bukan jalur produksi |

### 3.2 Kandidat cached-read (prioritas migrasi)

Urut dari nilai tertinggi:

| Prioritas | Aksi | Lokasi pemakai | Catatan |
|---|---|---|---|
| P1 | `akun_list` | kas_kecil_screen.dart:95, kas_besar_screen.dart:95, jurnal_umum_screen.dart:71, laporan_screen.dart:594, master_keuangan_screen.dart:85, penggantian_kas_kecil_screen.dart:94, siklus_akuntansi_screen.dart:103, uang_muka_screen.dart:548, anggaran_screen.dart:149 | **9 layar** memuat master akun yang sama tiap kali dibuka. Satu cache `MasterOffline.daftarCacheDulu` dipakai bersama = perbaikan terbesar dengan usaha terkecil |
| P1 | `konfigurasi` | kasir_screen.dart:490-515, beranda_apotik_screen.dart:74, beranda_is_screen.dart:73 | Konfigurasi toko — snapshot lokal + refresh background; kasir tidak boleh gagal render karena konfigurasi tak terjangkau |
| P1 | `toko_profil_ambil` | struk_screen.dart:407, konfigurasi_screen.dart:933 | Dipakai saat cetak struk — jika offline, struk gagal; cache wajib |
| P2 | Keluarga `*_opsi` | `kas_kecil_opsi`, `kas_besar_opsi`, `closing_opsi`, `dana_talangan_opsi`, `master_keuangan_opsi`, `nomor_surat_keuangan_opsi`, `pj_uang_muka_opsi`, `pj_kas_besar_opsi`, `proses_transfer_opsi`, `proses_transitori_opsi`, `reimbursement_opsi`, `uang_muka_opsi`, `penggantian_kas_kecil_opsi`, `pengadaan_cara_bayar_opsi`, `laporan_metode_bayar_opsi` | Opsi form yang stabil; pola seragam sehingga bisa dimigrasikan satu helper |
| P2 | Master list kecil | `jenis_anggota_list` (3 layar), `tipe_anggota_list`, `cara_bayar_list/_semua` (keranjang_screen.dart:241, tab_jenis_member.dart:107), `satuan_kerja_list`, `penyedia_list`, `jenis_produk_list`, `grup_produk_list`, `uom_list`, `pedagang_list`, `hak_akses_list`, `pengguna_toko_list`, `si_customer_list`, `si_supplier_list`, `si_expense_category_list`, `ebisnis_role_menu_ambil` | Sebagian entitas ini sudah punya cache di layar masternya sendiri — pemakaian di layar LAIN masih fetch langsung. `cara_bayar_list` di keranjang menyentuh area bug lama metode bayar terkunci: migrasi harus tetap validasi ulang server saat bayar |
| P2 | `katalog` | kasir_screen.dart:535, produk_screen.dart:266,618, price_tag_screen.dart:714, riwayat_penjualan_screen.dart:239, kulakan_bulk_entry_screen.dart:177, penjualan_sales_screen.dart:1047 | Produk sudah tersinkron ke `core_db` — layar-layar ini idealnya membaca cache produk yang sama, bukan fetch katalog ulang |
| P3 | Statistik/dashboard | `anggota_statistik`, `produk_statistik(_detail)`, `transaksi_statistik`, `stok_dashboard`, `so_ringkasan`, `sop_dashboard`, `draft_jurnal_ringkasan`, `monitor_promo_cashback`, `error_log_health` | Cached-read + label "data tersimpan" + timestamp; angka boleh basi asalkan berlabel |
| P3 | Daftar berhalaman | `laporan_order_list`, `deposit_list`, `sesi_kas_list`, keluarga `laporan_*_list/detail`, `si_*_list/report/aging/history`, `pengadaan_*_daftar/detail`, `mutasi_stok_*_list`, `kulakan_faktur_list/detail`, `jurnal_umum_list/detail`, `anggaran_revisi/realisasi_list`, `apotik_laporan_*`, `pembantu_piutang_list`, `produk_batch_produk_list`, `produk_foto_list`, `si_print_log_list` | Bernilai untuk UX offline, tetapi WAJIB mengikuti perlindungan pagination (jangan hapus row lokal dari satu halaman server) dan diff per ID stabil + `KilauBaris` |
| P3 | Layar pelanggan | `layar_pelanggan_slide_untuk_tampil/ambil/screensaver_config_ambil/slide_list` | Screensaver/display harus tetap tampil saat offline — cache aset lokal |

### 3.3 Kandidat queueable-mutation (sedikit, tangani hati-hati)

| Aksi | Lokasi | Catatan |
|---|---|---|
| `produk_simpan` | kulakan_bulk_entry_screen.dart:780 | Master produk sudah punya jalur `MasterOffline.simpanAtauAntre` di layar produk; panggilan langsung di bulk entry ini kandidat disatukan ke jalur yang sama agar idempoten |
| `pedagang_ubah` | konfigurasi_screen.dart:2095 | Mutasi master biasa; layak outbox master |
| `si_print_log_create` | piutang_screen.dart:719,1275; nota_sales_screen.dart:862; hutang_supplier_screen.dart:409; laba_rugi_screen.dart:230 | Log cetak bersifat fire-and-forget; saat offline log hilang diam-diam — kandidat outbox ringan dengan dedup |
| `pengaturan_edit_transaksi_global_simpan` | konfigurasi_screen.dart:503 | Pengaturan; bisa diantre, tetapi karena memengaruhi kebijakan edit transaksi, pertimbangkan tetap online + konfirmasi |
| `pengajuan_limit_member_putuskan` | tab_pengajuan_limit.dart:135 | Keputusan approval — condong online-only; masuk daftar ini hanya untuk dicatat sudah diaudit |
| `anggota_pin_simpan_massal` | tab_data_member.dart:488,573 | JANGAN diantrekan: payload PIN sensitif; tetap online + hak akses |
| `sesi_kas_koreksi`, `ebisnis_role_menu_simpan`, `si_coa_save`, `si_collection_reverse`, `si_payable_payment_reverse` | (lihat 3.1) | Diaudit dan diputuskan tetap online-only |

### 3.4 Pencarian interaktif (online + degradasi jelas)

`cari_member`, `so_produk_scan` (4 layar), `grup_produk_produk_cari`, `pengadaan_penyedia/barang/anggaran_cari`, `sop_cari(_entitas)`, `diskon_grup_produk_cari`, `produk_duplikat_cari/hapus`, `reimbursement_cari_pegawai`, `edit_transaksi_kasir_cari`, `uang_muka_cari_pr/anggaran`, `dana_talangan_cari_uang_muka`, `kas_besar_cari_kas_kecil`, `penggantian_kas_kecil_cari_kas_kecil`, `pj_*_cari_*`, `apotik_item_cari`, `hotel_*_lookup`.

Typeahead ke server tetap online, tetapi dua di antaranya menyentuh jalur kasir dan layak fallback cache lokal: `cari_member` (cache `anggota_cache` sudah ada) dan `so_produk_scan` (cache produk/barcode sudah ada). Sisanya cukup diberi pesan kegagalan yang jelas saat offline.

## 4. Batasan audit

- `pengiriman_screen.dart` (`distribusi_list/detail/status/simpan`) **milik pekerjaan sesi lain** — diinventarisasi tetapi sengaja tidak dianalisis/diubah.
- Klasifikasi P2–P3 didasarkan pada semantik nama aksi + sampel konteks, bukan pembacaan penuh 398 call-site; sebelum memigrasikan satu layar, baca alur layarnya utuh (terutama bentuk respons `summary`/`ringkasan` top-level yang pernah hilang).
- `lib/services` dan widget di luar `lib/screens` tidak termasuk cakupan; 23 call-site di services adalah infrastruktur Local-First itu sendiri.

## 5. Rekomendasi urutan eksekusi

1. `akun_list` → satu entri cache `MasterOffline` dipakai 9 layar keuangan.
2. `konfigurasi` + `toko_profil_ambil` → jalur kasir/struk tahan offline.
3. Helper generik untuk keluarga `*_opsi` (pola identik di ±15 layar).
4. `katalog` di layar non-produk → baca cache produk `core_db` yang sudah ada.
5. `si_print_log_create` → outbox ringan idempoten.
6. Statistik/dashboard dan daftar berhalaman → bertahap per layar, dengan test kontrak pagination.

Setiap langkah harus disertai test kontrak (pola `*_contract_test.dart` yang sudah ada) dan tidak mencampur perubahan antarfitur dalam satu commit.

## 6. Status pelaksanaan

- **Langkah 1 (`akun_list`) — selesai 29 Agustus 2026.** Kesembilan layar keuangan
  (anggaran, jurnal umum, kas besar, kas kecil, laporan, master keuangan,
  penggantian kas kecil, siklus akuntansi, uang muka) kini memuat bagan akun
  lewat `MasterOffline.daftarDenganCache('akun_list', {'limit': 5000},
  'master:akun')` — satu cache bersama dengan fallback offline. Limit
  diseragamkan ke 5000 (superset dari 2000 yang lama; jurnal umum sudah memakai
  5000 sebelumnya). Perilaku online tidak berubah (server tetap dipanggil dan
  bentuk respons sama); yang bertambah adalah snapshot lokal sehingga dropdown
  akun tetap terisi saat offline. Penjaganya: test `akun_list dibaca lewat
  cache bersama master:akun` di `test/master_offline_kontrak_test.dart`.
- **Langkah 2 (`konfigurasi` + `toko_profil_ambil`) — selesai 29 Agustus 2026.**
  `MasterOffline` mendapat helper baru `objekDenganCache` (padanan
  `daftarDenganCache` untuk respons objek: server dulu, snapshot seluruh
  respons, fallback `{offline: true}`). Pemakainya: `konfigurasi` di
  kasir (`_gantiToko`, `_sinkronKatalogDanKonfigurasi`), beranda apotik, dan
  beranda Inventory & Sales dengan kunci bersama `'konfigurasi'`; serta
  `toko_profil_ambil` di layar struk dan tab profil toko konfigurasi dengan
  kunci per toko `'toko_profil_ambil:<idToko>'` — struk tetap ber-kop saat
  offline. Pengecualian yang disengaja: refetch `konfigurasi` PASCA memilih
  toko baru di kasir tetap online-only karena snapshot lokal masih milik toko
  sebelumnya. Penjaganya: test `konfigurasi dan toko_profil_ambil punya
  fallback cache objek` di test kontrak yang sama.
- **Langkah 3 (keluarga `*_opsi`) — selesai 29 Agustus 2026.** Helper generik
  yang direncanakan audit ternyata sudah terpenuhi oleh `objekDenganCache`
  (respons `*_opsi` adalah objek berisi beberapa daftar opsi). 14 call-site
  ber-body kosong dimigrasikan dengan kunci cache = nama aksinya:
  `closing_opsi`, `dana_talangan_opsi`, `kas_kecil_opsi`, `kas_besar_opsi`,
  `master_keuangan_opsi`, `nomor_surat_keuangan_opsi`,
  `pengadaan_cara_bayar_opsi`, `penggantian_kas_kecil_opsi`,
  `pj_uang_muka_opsi`, `pj_kas_besar_opsi`, `proses_transfer_opsi`,
  `proses_transitori_opsi`, `reimbursement_opsi`, `uang_muka_opsi` — form
  tetap bisa dibuka saat offline. `laporan_metode_bayar_opsi` sengaja TIDAK
  ikut: body-nya memuat rentang tanggal sehingga kunci cache-nya tak
  terbatas; tetap online-only dan dikunci test. Penjaganya: test `keluarga
  *_opsi dibaca lewat objekDenganCache`.
- **Langkah 4 (`katalog` di layar non-produk) — selesai 29 Agustus 2026.**
  Audit lanjutan menemukan 4 dari 6 call-site sudah benar sejak awal: kasir
  sudah Local-First penuh (cache dulu + server refresh background + upsert),
  price_tag sudah cache-first dengan fallback katalog yang mengisi ulang
  cache, dan dua call-site produk_screen adalah sinkron penuh ber-progress
  (memang online) serta pemuat relasi form dengan degradasi yang sudah baik.
  Yang diperbaiki adalah dua dialog pencarian produk tanpa fallback offline:
  pencarian produk koreksi transaksi (`riwayat_penjualan_screen`) dan dialog
  cari produk Sales (`penjualan_sales_screen`) kini jatuh ke
  `CoreDb.produkCache(keyword: ...)` saat `ApiException.offline`, dipetakan
  lewat helper tunggal baru `Produk.cacheRowKeJson` di `models.dart`
  (kebalikan `baseKeCacheRow`, supaya pemetaan SQLite<->JSON tidak digandakan
  per layar). `kulakan_bulk_entry` memakai `katalog` hanya sebagai fallback
  kategori server-lama di dalam try/catch yang sudah bergraceful-degradation —
  dibiarkan. Penjaganya: test `pencarian produk jatuh ke cache produk lokal
  saat offline`.
- **Langkah 5 (`si_print_log_create`) — selesai 29 Agustus 2026.** Register
  riwayat cetak (P10) sebelumnya fire-and-forget langsung ke server sehingga
  log hilang diam-diam saat offline. Kelima call-site (kwitansi penerimaan
  dan rekap penjualan di piutang, laporan sesi nota sales, laporan laba rugi,
  voucher pembayaran hutang) kini lewat `OutboxIs.kirimAtauAntre` dengan
  `kode_unik` `PRN-<microsecondsSinceEpoch>` per kejadian cetak; layar
  laba_rugi dan hutang_supplier ikut memanggil `OutboxIs.flush()` saat dibuka
  (piutang dan nota_sales sudah sejak dulu). Catatan jujur: handler backend
  `printLogCreate` (SalesInventoryReversalHelper.java) masih append murni
  tanpa dedup `kode_unik` — duplikat baris log hanya mungkin bila aplikasi
  mati tepat di antara kirim dan tandai-sukses, dapat diterima untuk log
  append-only; `kode_unik` sudah dikirim sehingga dedup server dapat
  ditambahkan belakangan tanpa mengubah klien. Penjaganya: test `log cetak
  diantre lewat OutboxIs, tidak hilang saat offline`.
