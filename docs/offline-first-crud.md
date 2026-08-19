# Offline-first CRUD — arsitektur & aturan main

Berlaku untuk `apps/ebisnis` (POS Desktop & Android, seluruh varian).
Versi acuan: 1.33.62 (2026-08-19).

## Tiga lapis

### 1. Simpan LOKAL DULU — `widgets/proses_simpan_master.dart`
`prosesSimpanMaster(context, aksi:, body:, kunci:, cacheKey:, rowLokal:)`
menampilkan dialog bertahap: **"Tersimpan di perangkat" ✓** →
**"Mengirim ke server…"** → **"Terkirim ke server" ✓** atau
**"Offline — akan dikirim otomatis nanti"**, lalu jendela menutup.
Batas tunggu kirim 6 detik: offline/server lambat TIDAK menahan kasir.

- Penolakan BISNIS server (validasi) → baris antrean dihapus, error dilempar
  ke form, jendela TETAP terbuka supaya pesannya terbaca. Ini kontrak inti.
- Retry latar tiap **5 menit** (`MasterOffline.intervalFlush`) dan
  **berhenti otomatis** begitu antrean kosong; hidup lagi saat ada antrean
  baru atau layar master dibuka.
- Payload antrean membawa `client_mutation_id`; server AIS mendedup replay
  (`MutasiIdempotenEBisnisUtil`), jadi kiriman ulang tidak menggandakan data.

### 2. Baca LOKAL DULU — `MasterOffline.daftarCacheDulu(...)`
Memberi 1–2 emisi lewat `onData`: snapshot lokal seketika, lalu hasil server
+ diff. Pakai `DiffDaftarLokal` (services/diff_daftar_lokal.dart):

```dart
final _diff = DiffDaftarLokal();
await MasterOffline.daftarCacheDulu(aksi, body, 'master:<kunci>',
    kolomKunci: '<kolom>', onData: (hasil) {
  if (!mounted) return;
  setStateIfMounted(() {
    _daftar = _diff.terapkan(hasil);
    _total = _diff.total ?? _daftar.length;
    if (_diff.dariServer) { /* ringkasan/agregat server */ }
  });
});
```
Baris dibungkus `KilauBaris(kunci: MasterOffline.kunciBaris(row, '<kolom>'),
idBaru: _diff.idBaru, idBerubah: _diff.idBerubah, child: ...)`.

### 3. Riwayat data — `widgets/riwayat_data_dialog.dart`
`tampilkanRiwayatData(context, entitas: 'produk', id: ..., judul: ...)`
membaca audit trail Envers lewat aksi `revisi_daftar`/`revisi_detail`/
`revisi_pulihkan` (server: `RevisiApiHelper`, padanan `GenericRevisiHelper`
ZK). Tombol "Pulihkan" hanya muncul bila server menyatakan `bolehPulihkan`
(`Common.getApakahAdminLain`). Kode `entitas` harus terdaftar di
`RevisiApiHelper.ENTITAS` DAN entity-nya `@Audited`.

## Aturan yang TIDAK boleh dilanggar

1. **Jangan antrekan mutasi sensitif.** Kredensial/hak akses, uang
   (pembayaran, topup, retur, opname, mutasi stok), dan alur yang butuh id
   server seketika TETAP online-only. Dijaga
   `test/master_offline_kontrak_test.dart`.
2. **Jangan simpulkan penghapusan dari respons parsial.** Hanya respons yang
   benar-benar lengkap (dinyatakan lengkap + tanpa filter + mencakup `total`
   server) boleh menghapus baris lokal. Respons berhalaman/terfilter =
   MERGE murni. (Akar insiden banner "41 dihapus", 1.33.60.)
3. **Baris yang masih antre/gagal kirim tidak boleh ditimpa** salinan server
   yang lebih lama — versi lokal yang tampil sampai terkirim.
4. **cacheKey harus memuat seluruh parameter yang mengubah isi daftar**
   (periode, toko, filter, status). Salah kunci = data periode A menimpa B.
5. **Baris tanpa kolom `id` wajib menyetel `kolomKunci`.** Tanpa itu diff dan
   kilau mati; cache tetap aman (baris server menggantikan yang lokal).
6. **Kunci `KilauBaris` wajib lewat `MasterOffline.kunciBaris`** supaya sama
   persis dengan kunci diff internal — kalau beda, animasi tak pernah nyala.
7. **`total` tidak boleh di-cast paksa** — sebagian aksi memakainya untuk
   objek rekap (mis. `pembantu_piutang_list`), bukan cacah baris.
8. **Field top-level respons server diteruskan apa adanya** ke layar
   (ringkasan/summary/totalOutstanding/daftarKasir). Pernah dibuang →
   KPI diam-diam Rp 0.

Poin 2, 6, 7, 8 masing-masing pernah menjadi bug nyata dan kini dijaga uji
kontrak; jangan melonggarkannya tanpa mengganti penjaganya.

## Sengaja TIDAK di-cache
Kasir/POS & keranjang (punya jalur `transaksi_pending` sendiri), layar
pelanggan (realtime), cetak label, impor Excel, log error & riwayat
sinkronisasi (sudah baca DB lokal), dan sesi kas berjalan — angka basi di
sana menyesatkan.
