# 01 — Source Inventory (P0, 2026-08-11)

## Dokumen input (hash: lihat source-manifest.sha256, salinan: docs/input/)

| Berkas | Status | Peran |
|---|---|---|
| PERINTAH_MASTER_…_48_LAYAR.md | dibaca lengkap (4244 baris) | arsitektur, larangan, fase P0-P8, API si_*, DoD |
| ERD_DAN_SPESIFIKASI_DATA_NOTA_SALES_JAVA_AIS.md | dibaca lengkap | model data SPJ/sesi/rumus/state machine |
| MAPPING_48_LAYAR_KE_ZISHOF_PLATFORM_DAN_JAVA_AIS.csv | dibaca lengkap | reuse vs baru + aksi API per layar |
| TRACKER_IMPLEMENTASI_…csv | dibaca lengkap → di-fork jadi 01-gap-ledger.csv | status per requirement |
| Panduan-Transisi-48-Layar…v2.pdf/.docx | teks diekstrak dari .docx (pdftoppm tidak tersedia); intro+prinsip+indeks+bab contoh dibaca; bab per layar di-grep saat implementasi | kontrak paritas per layar + struktur DBF legacy |
| Matriks-Paritas-Komponen-48-Layar-v2.csv | dibaca lengkap (48 baris) | tombol/field/grid/validasi minimum per layar |
| Sistem Sales.mp4 + analisis video/48 frame | TIDAK DITEMUKAN LOKAL | → uat-required.md #9 |
| Source legacy/DBF (5-Inventory--.rar) | TIDAK tersedia lokal; struktur DBF terekam di Panduan v2 (SUPPLIER/BELI/TRAN_HUT/masterbl/USERS) | rekonsiliasi migrasi = UAT |

## Struktur DBF legacy yang terekam di Panduan v2 (FACT_MANUAL)

- `SUPPLIER.DBF`: KODESUPPL(3 char), NAMASUPPL, SYARAT_BYR(termin), ATASNAMA, ALAMAT,
  NOTELPON, REKRUPIAH, ALMBANK, NAMABANK, WILAYAH, HUT_AWAL/HUT_MASUK/HUT_KELUAR.
- `BELI.DBF`: TANGGAL, NOFAKTUR, KODESUPPL, KODEBRG, JUMLAH, HARGABELI, HARGAASLI,
  DISCOUNT, DISCOUNT2, NOBATCH, TGLEXP, TGLOPNAME.
- `TRAN_HUT.DBF`: NOFAKTUR, KODESUPPL, TANGGAL, JTHTEMPO, TGLBAYAR, JUMLAH, KETBAYAR,
  NOMERBG, NAMABANK, TANGGALBG (event hutang + giro/BG).
- `masterbl.DBF`: KODESUPPL, KODEBRG, TANGGAL, HARGABELI (histori harga beli per supplier).
- `USERS.DBF`: field PSW plaintext — TIDAK dimigrasikan (reset kredensial via Tbmuser).
- Kode customer 5 char, kode sales 2 char + No. Perkiraan (akun COA per sales).

## Peta reuse server AIS (rujukan cepat; detail + baris: 00-baseline.md)

| Kebutuhan varian | Reuse existing | Catatan |
|---|---|---|
| Endpoint API | `/Api_eBisnis` (ApiEBisnis extends PosApi) | hook prosesAksiTambahan (P1) |
| Auth | PosDeviceAuthApi Bearer token | tidak disentuh |
| RBAC | Tbmrole.ebisnisMenu + EbisnisMenuKatalog + hakAkses() | + kunci menu si (P1) |
| Supplier | library.Penyedia + penyedia_list/simpan | + profil termin/bank/wilayah (P2) |
| Procurement | PengadaanFaktur + kulakan_faktur_* | basis layar 20 (P3) |
| Customer | koperasi.AnggotaKoperasi | + CustomerInventoryProfile (P2) |
| Sesi kas | inventory.SesiKasKasir | referensi pola idempoten `kode` |
| Stok | StokKantinUtil (8 suku, 2 salinan) + MutasiStokToko | stok mobil sales (P5) |
| COA/Jurnal | akunting.Akun + akunting.Transaksi | layar 43-48 (P6) |
| Laporan | LaporanKatalogData + LaporanKantinUtil + laporan_jalankan/pdf | + id laporan si (P2-P6) |
| Audit | Envers (new_audit, __audit) | entity baru wajib @Audited |

## Peta reuse Flutter (rujukan cepat)

| Kebutuhan varian | Reuse existing |
|---|---|
| Varian build | app_variant.dart (dart-define) + variant.cmake + Runner.rc ifdef + .iss per varian |
| Shell/menu | AppShell + MenuEBisnis + bolehTampilMenu + Sesi.aksesMenu (server-driven) |
| API client | ApiClient.aksi() → /Api_eBisnis |
| Offline DB | core_db (schema v3, upgrade idempoten) |
| Update | core_update (keyword asset per varian) |
| Scanner/laci | core_hw |
| Layar reuse | Kasir/Keranjang/Pesanan/Anggota/Produk/StokOpname/MutasiAntarOutlet/Kulakan+ReturPembelian/ReturPenjualan/RiwayatPenjualan/LaporanTransaksi/Laporan(katalog, parameterized)/HakAkses |
| Placeholder yang HARUS diimplementasi | core_sync (kosong; FND-009/P7) |

## Drift/temuan yang memengaruhi desain

1. Menu Flutter terdaftar di 2 tempat (app_shell + app_drawer) — registry varian (P1) harus
   menjadi satu-satunya titik tambah menu baru.
2. `soResolveTokoId` mempercayai `toko_id` mentah dari admin global — aksi `si_*` TIDAK
   memakai helper ini; resolver baru memvalidasi scope (fail-closed).
3. Piutang customer tidak punya tabel ledger (dihitung on-the-fly) — ledger AR per-invoice
   untuk Nota Sales didesain baru di P4, tidak memaksakan reuse.
4. `bolehAksesActionKantin` default `return true` — blok gate `si_` wajib ditambah (P1).
5. JavaDoc HakAksesScreen menyebut "13 checkbox", katalog server 28 kunci — server adalah
   sumber kebenaran; angka di JavaDoc klien basi (tidak diubah di P1, cukup dicatat).
