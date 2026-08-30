# Aturan Wajib Local-First untuk Semua Modul

Status: **WAJIB / gerbang rilis (fail-closed)**  
Cakupan: POS Desktop, Android, JSP/ZK yang berbagi kontrak API, seluruh varian,
seluruh modul master, operasional, inventori, pengadaan, produksi, distribusi,
pelanggan, dan modul berikutnya.

## Prinsip yang tidak boleh ditawar

Local-first berarti perangkat lokal adalah tempat pertama sebuah pekerjaan yang
aman ditunda dicatat. Server adalah tujuan sinkronisasi dan sumber rekonsiliasi,
bukan syarat agar pengguna dapat menyelesaikan pekerjaan tersebut.

### Baca data

- Render cache SQLite lebih dahulu; refresh server berjalan di latar belakang.
- Pencarian, filter, urut, dan pagination dilakukan terhadap SQLite. Jangan
  memuat snapshot puluhan ribu baris ke thread UI hanya untuk menampilkan satu
  halaman.
- Cache yang valid tidak boleh dikosongkan hanya karena server timeout/503.
- Respons server baru mengganti cache setelah respons lengkap dan tervalidasi.

### Create, Update, Delete yang queueable

Urutan wajib:

1. Validasi lokal.
2. Simpan perubahan lokal dan record outbox dalam satu transaksi.
3. Tutup form sebagai **tersimpan di perangkat**.
4. Coba kirim tanpa memblokir alur kerja.
5. Retry otomatis dengan idempotency key dan backoff hingga berhasil.
6. Bila server menolak aturan bisnis, pertahankan salinan lokal, tandai Gagal,
   tampilkan alasan dan tindakan koreksi; jangan retry membabi buta.
7. Setelah sukses, petakan ID sementara ke ID server dan perbarui semua referensi
   secara atomik.

### Foto dan lampiran

- Salin file ke penyimpanan aplikasi sebelum form dinyatakan berhasil.
- Preview edit membaca file lokal terlebih dahulu, lalu URL server sebagai
  fallback.
- Upload berjalan melalui outbox dan dapat dilanjutkan setelah restart.
- Penghapusan lokal baru dilakukan setelah upload terverifikasi atau kebijakan
  retensi berakhir.

### Transaksi dan stok

- Transaksi kasir, stok, produksi, dan distribusi menggunakan jurnal/outbox
  domain yang idempoten; bukan antrean master generik bila membutuhkan efek
  akuntansi/inventori.
- Stok UI berasal dari ledger/cache lokal yang diperbarui oleh event lokal dan
  direkonsiliasi dengan server.
- ID sementara tidak boleh masuk ke transaksi server yang mensyaratkan ID final.

## Pengecualian aman: online-only

"Semua modul local-first" tidak berarti semua tombol boleh sukses tanpa server.
Aksi berikut wajib memperoleh jawaban server karena menundanya dapat membuat
saldo, hak akses, atau jurnal menjadi salah:

- login, token, PIN, biometrik, dan perubahan kredensial;
- pemeriksaan saldo/limit yang menentukan persetujuan transaksi;
- approval, posting jurnal, closing, dan tindakan keuangan final;
- pembatalan/koreksi yang membalik jurnal atau stok yang sudah final;
- impor massal dan migrasi yang memerlukan validasi referensial global.

Pengecualian wajib fail-closed dengan pesan: apa yang gagal, mengapa perlu server,
apa yang perlu dilakukan pengguna, dan bahwa menekan tombol berulang tidak akan
menyelesaikan penolakan bisnis.

## Gerbang review dan rilis

Setiap sesi AI/developer wajib menjawab sebelum commit:

- Apakah ada mutasi langsung `ApiClient.aksi` baru?
- Jika ada, apakah sudah memakai outbox local-first atau tercatat sebagai
  pengecualian online-only dengan alasan integritas?
- Apakah cache tetap tampil saat offline/timeout/HTTP 5xx?
- Apakah restart aplikasi aman dan retry tidak menggandakan data?
- Apakah foto/lampiran dapat tampil dari antrean lokal?
- Apakah tes offline, restart, idempotensi, penolakan bisnis, dan rekonsiliasi
  lulus?

Jika satu jawaban belum dapat dibuktikan, rilis **ditahan**.

## Implementasi rujukan

- Master CRUD: `apps/ebisnis/lib/widgets/proses_simpan_master.dart`
- Antrean master: `apps/ebisnis/lib/services/master_offline.dart`
- Foto: `apps/ebisnis/lib/services/simpan_gambar_local_first.dart`
- Audit kontrak: `docs/pos/2026-08-29-audit-crud-apiclient-langsung.md`

