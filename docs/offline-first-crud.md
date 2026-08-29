# Offline-first CRUD — arsitektur & aturan main

Berlaku untuk `apps/ebisnis` (POS Desktop & Android, seluruh varian).
Versi acuan: 1.33.62 (2026-08-19).

Foto produk memakai kamera native `camera`/`camera_windows` (bukan
`ImageSource.camera` dari `image_picker`, yang tidak diimplementasikan pada
Windows). Hasil kompresi selalu diberi ekstensi `.jpg`, dan URL servlet media
dinormalkan ke origin server aktif agar tetap benar di belakang reverse proxy.

## Tiga lapis

### 1. Simpan LOKAL DULU — `widgets/proses_simpan_master.dart`
`prosesSimpanMaster(context, aksi:, body:, kunci:, cacheKey:, rowLokal:)`
menampilkan dialog bertahap: **"Tersimpan di perangkat" ✓** →
**"Mengirim ke server…"** → **"Terkirim ke server" ✓** atau
**"Offline — akan dikirim otomatis nanti"**, lalu jendela menutup.
Batas tunggu kirim 6 detik: offline/server lambat TIDAK menahan kasir.

- Gangguan teknis server (offline, timeout, HTTP 5xx, jawaban rusak, atau
  `SERVER_ERROR`) → baris tetap `PENDING`, form selesai sebagai sukses lokal,
  dan pengiriman dicoba ulang otomatis dengan `client_mutation_id` yang sama.
- Penolakan BISNIS server (validasi) → baris menjadi `GAGAL`, tidak dihapus.
  Form tetap terbuka agar pesan dapat dibaca dan datanya diperbaiki; snapshot
  lokal tetap terlindungi agar refresh tidak mengembalikan versi server lama.
  Saat user menyimpan koreksi, payload `GAGAL` lama untuk kunci yang sama
  diganti payload terbaru lalu kembali `PENDING`.
- Retry latar tiap **5 menit** (`MasterOffline.intervalFlush`) dan
  **berhenti otomatis** begitu antrean kosong; hidup lagi saat ada antrean
  baru atau layar master dibuka.
- Payload antrean membawa `client_mutation_id`; server AIS mendedup replay
  (`MutasiIdempotenEBisnisUtil`), jadi kiriman ulang tidak menggandakan data.
- Refresh/sinkron penuh katalog dari server wajib menerapkan kembali edit
  produk lokal berstatus `PENDING`/`GAGAL` setelah snapshot server disimpan.
  Dengan demikian barcode, nama, harga, dan status lokal tidak mundur ke versi
  server lama selama mutasi masih menunggu penyelesaian.

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

0. **Kegagalan teknis server tidak boleh membatalkan simpan lokal CRUD.**
   HTTP 5xx, timeout/offline, jawaban non-JSON, `SERVER_ERROR`, kode teknis
   baru, dan respons error endpoint lama tanpa kode tetap `PENDING`. Retry
   periodik menggunakan `client_mutation_id` yang sama agar idempoten.
   Khusus edit produk, perubahan juga langsung di-upsert ke `produk_cache`
   agar barcode/nama terbaru tersedia untuk Kasir, Kulakan, dan Stok Opname
   sebelum server pulih. Pencarian SO membaca cache tersebut lebih dahulu.

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

## Audit jalur TULIS — apakah semua sudah "lokal dulu"? (2026-08-21)

Seluruh titik mutasi di `apps/ebisnis/lib` ditelusuri: setiap panggilan
`ApiClient.instance.aksi(...)` yang namanya menandakan perubahan data.

**Jalur yang sah untuk menulis:**

- `prosesSimpanMaster(...)` — menulis ke `outbox_master` LEBIH DULU
  (`MasterOffline.antreLokal`), baru mencoba mengirim dengan indikator
  bertahap. Ini satu-satunya pola yang benar-benar *local-first*.
- `MasterOffline.antreLokal` + `kirimSatuAntrean` — sama, tanpa dialog. Dipakai
  bila jendela proses tidak pantas muncul (mis. layar pelanggan).

`MasterOffline.simpanAtauAntre` **bukan** local-first: ia mencoba server dulu
dan hanya mengantre bila jaringan gagal. Datanya tetap tidak hilang, tetapi
urutannya terbalik. Tiga pemakai terakhirnya sudah dipindahkan ke
`prosesSimpanMaster`; fungsi itu dibiarkan ada untuk pemakaian programatik,
bukan untuk form.

**Dipindahkan ke local-first pada audit ini:**

| Layar | Aksi |
|---|---|
| `anggota/tab_satuan_kerja.dart` | `satuan_kerja_simpan`, `satuan_kerja_hapus`, `satuan_kerja_anggota_simpan` |
| `anggota/tab_topup.dart` | `deposit_hapus` |
| `konfigurasi_screen.dart` | `otomatis_pesanan_global_simpan` |
| `inventory_sales/hutang_supplier_screen.dart` | `si_purchase_terms_save` |
| `mitrainap/kamar_hotel_screen.dart` | seluruh mutasi kamar (dari server-dulu) |
| `pengadaan_tagihan_screen.dart` | `pengadaan_lampiran_hapus` (dari server-dulu) |
| `produk_screen.dart` | `produk_foto_hapus` (dari server-dulu) |
| `anggota/tab_data_member.dart` | `anggota_foto_upload`, `anggota_foto_hapus` — JPEG maks. 500 KB tersimpan di outbox dan diulang otomatis bila server terganggu |
| foto produk/member/screensaver | seluruh upload memakai `simpanGambarLocalFirst`: payload gambar masuk outbox sebelum HTTP; timeout, HTTP 5xx, dan respons non-JSON tidak menghilangkan pilihan pengguna |
| `layar_pelanggan_screen.dart` | `survey_kepuasan_simpan` — sebelumnya kegagalan kirim ditelan diam-diam dan rating hilang |

**Sengaja TETAP online-only.** Bukan kelalaian; mengantrekannya akan merusak
data atau uang. Dikunci uji `master_offline_kontrak_test.dart`:

| Alasan | Aksi |
|---|---|
| Kontrol akses harus berlaku seketika | `ebisnis_role_menu_simpan` |
| Spec 13.3 "perubahan rekening/harga sensitif" | `si_coa_save` |
| Spec 13.3 "reversal" | `batalkan_transaksi`, `edit_transaksi` |
| Spec 13.3 "journal posting" | `jurnal_umum_posting` |
| Kredensial | `pedagang_ubah` dengan `password_baru` |
| Butuh id server seketika untuk dokumen yang sedang disusun | `produk_simpan` & `penyedia_simpan` (kulakan), `hotel_tamu_simpan` |
| Respons server menentukan langkah berikutnya | `mutasi_stok_simpan` (cabang "pilih manual"), `produk_duplikat_hapus` (server yang menghitung penggabungan) |
| Sudah punya jalur luring sendiri | penjualan kasir → `transaksi_outbox_service` |

**Belum diputuskan — perlu keputusan bisnis, bukan teknis.** Dokumen final yang
memindahkan stok/uang: retur pembelian & penjualan, stok opname, opname/retur
apotik, pembayaran hutang anggota, penyesuaian saldo voucher, faktur kulakan,
reservasi & folio hotel. Semuanya membawa `idempotency_key` sehingga replay
aman, tetapi bila diantre, penolakan bisnis (mis. qty melebihi sisa karena
sudah diretur di mesin lain) baru ketahuan saat pengiriman latar — pengguna
sudah meninggalkan layar dan mungkin sudah menyerahkan uang atau barang.
Mengubahnya menuntut otorisasi stok dari server seperti diminta spec 13.3
("jangan sekadar melewati validasi"), bukan sekadar mengganti pemanggilan.

## Foto profil member

- Foto hanya dapat ditambahkan setelah member memiliki ID server. Pada form
  member baru, aplikasi mengedukasi pengguna untuk menyimpan member dahulu,
  lalu membuka **Ubah Member**. Ini mencegah foto kehilangan relasi saat ID
  lokal sementara belum dipetakan ke ID server.
- Galeri dan kamera menghasilkan JPEG terkompresi di bawah 500 KB sebelum
  masuk antrean `outbox_master`. Gangguan server tidak membatalkan pilihan
  foto; aksi unggah/hapus dikirim ulang otomatis dan idempoten.
- Backend tidak membuat tabel foto baru. `anggota_foto_upload` mengganti foto
  pada `FotoSiswa`, `FotoMahasiswa`, `FotoPegawai`, atau `FotoAdmin` melalui
  `ProfileImageUtil`, sehingga foto yang sama langsung dipakai POS dan web
  eCampus. Member yang belum ditautkan ke pengguna/sivitas ditolak dengan
  petunjuk eksplisit agar admin memperbaiki relasinya terlebih dahulu.

## Kontrak upload gambar (2026-08-30)

- Semua upload gambar wajib melalui `services/simpan_gambar_local_first.dart`.
  Dilarang memanggil `ApiClient.instance.aksi(...)` langsung untuk upload foto.
- Cakupan saat ini: `produk_foto_upload`, `anggota_foto_upload`, dan
  `layar_pelanggan_slide_upload`. Semua gambar dikonversi ke JPEG di bawah
  500 KB dan nama berkas diakhiri `.jpg`, sehingga tipe konten sesuai isi.
- Produk baru memakai ID lokal negatif. Foto yang dipilih ikut mengantre dengan
  `produk_id` tersebut dan baru dikirim setelah pemetaan ID server tersedia.
- Status `PENDING` berarti gambar sudah aman di perangkat, bukan gagal simpan.
  Pengguna tidak perlu memilih ulang; buka **Sistem > Riwayat Sinkronisasi**
  untuk melihat kendala dan tekan sinkron setelah backend diperbarui.
- Backend yang dipasang wajib mengenali ketiga aksi di atas. Bila Log Error
  berbunyi `Aksi tidak dikenal`, perbaikannya adalah deploy backend yang memuat
  kontrak aksi tersebut—menekan Sinkron berulang tidak dapat memperbarui kode
  server. Payload tetap disimpan dan otomatis terkirim setelah backend sesuai.
### Foto dan gambar

Semua gambar yang dipilih pengguna wajib ditulis ke outbox SQLite sebelum
dikirim. Layar edit/daftar wajib menggabungkan media server dengan payload
gambar berstatus `PENDING` atau `GAGAL`, sehingga menutup dan membuka ulang
form tidak menghilangkan preview. Saat server pulih, pengiriman periodik tetap
menjadi jalur penyelesaian; kegagalan server tidak boleh memaksa pengguna
memilih foto yang sama untuk kedua kalinya.
