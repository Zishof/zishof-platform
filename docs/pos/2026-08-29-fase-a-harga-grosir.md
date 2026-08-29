# Fase A (inti) — Mesin Harga Grosir Ber-ambang Kuantitas

Tanggal: 29 Agustus 2026  
Status: server + integrasi kasir **lulus** (harness 13/13, Flutter 459/459); belum di-commit  
Rujukan: SVN `docs/pos/51-fase-a-harga-grosir.md` (ringkasan) dan
`docs/pos/48-...md` §4 Fase 1 (desain)

## Ringkas

Harga grosir kini ada, SATU mesin untuk semua kanal:

- `AturanHargaProduk` (`koperasi.aturan_harga_produk`, dibuat Hibernate):
  ambang `min_qty_dasar` per produk, harga per satuan dasar, toko opsional,
  jendela waktu. Harga kemasan = ambang sebesar isi kemasan (Metode 1 PDF).
- `HargaGrosirApiHelper.terapkanKeItems` dipanggil dari dua kait dan hanya dua:
  `KantinHelper.bayar` (payload dimutasi SEBELUM evaluasi diskon → total,
  baris tersimpan, dan koreksi `selisihTotal` semuanya mewarisi) dan
  `diskon_evaluasi` (pratinjau keranjang; respons membawa peta `hargaGrosir`).
- **Urutan dikunci:** grosir menentukan harga satuan, diskon memotong
  sesudahnya. **Guard lokal-dulu:** transaksi `pengiriman_pending` tidak
  ditimpa — pelanggan sudah membayar harga saat kejadian.
- Klien: `ItemKeranjang.hargaGrosir` diisi HANYA dari server; `subtotal` dan
  seluruh payload memakai `hargaSatuanEfektif`; dua arah (qty turun di bawah
  ambang → kembali harga katalog).
- API `harga_grosir_list/simpan/hapus` (gerbang = gerbang aturan diskon;
  hapus = nonaktif, jejak komersial dipertahankan).

## Bukti

- `TesHargaGrosir` (DB UAT, fungsi persis yang dipanggil kedua kait): 13/13 —
  batas inklusif; toko>global; ambang terbesar menang; kedaluwarsa/nonaktif/
  toko-lain tidak bocor; qty digabung lintas baris (30+25 ≥ 50); baris ekstra
  bersarang ikut; qty di bawah ambang tidak disentuh.
- Flutter: `harga_grosir_kontrak_test` 4/4; suite penuh 459/459; analyze bersih.
- `javac -source 1.7 -target 1.7` EXIT=0; mirror `src`/`java` md5 identik;
  0 `.class` di source; cfg boot harness diperbarui.

## Berkas

SVN: `ais/database/model/koperasi/AturanHargaProduk.java` (baru),
`ais/action/servlet/api/HargaGrosirApiHelper.java` (baru),
`KantinHelper.java` (2 kait + `bolehAksiCrud` jadi package-visible),
`PosApi.java` (3 rute), `hibernate.cfg.xml` (1 mapping).  
Flutter: `lib/models.dart` (hargaGrosir + hargaSatuanEfektif),
`lib/screens/keranjang_screen.dart` (peta grosir + payload efektif),
`test/harga_grosir_kontrak_test.dart` (baru).

**Perhatian pohon bersama:** `keranjang_screen.dart` juga memuat perubahan
biometrik sesi lain yang belum di-commit — saat commit, pisahkan hunk (teknik
blob `git hash-object` + `git update-index`, commit TANPA pathspec).

## Pelengkap 29-08 (sesi yang sama): sisa Fase A terlaksana

- **Pemilih kemasan sekali-ketuk**: TEKAN-LAMA kartu produk kasir membuka
  lembar pilihan (satuan / tiap kemasan aktif) -- jalur yang SAMA dengan scan
  barcode kemasan, termasuk snapshot label.
- **Snapshot kemasan di baris**: `ItemKeranjang.kemasanNama/kemasanQtyDasar`
  (arsip, bukan rujukan); label "2 x Karung 50kg" di baris keranjang DAN struk;
  bila kasir mengubah qty hingga tidak bulat, label jatuh ke bentuk informatif
  "Karung 50kg (isi 50)" -- tidak berbohong mengaku kelipatan.
- **Editor aturan harga** (`harga_grosir_editor.dart`) di form Produk, di bawah
  seksi Kemasan: daftar + tambah + nonaktifkan lewat API; hanya untuk produk
  tersimpan dan pemegang izin ubah harga; ONLINE-ONLY disengaja (aturan
  komersial wajib serentak di semua kasir).

Uji: label kemasan masuk `harga_grosir_kontrak_test` (kelipatan bulat, qty
diubah, tanpa snapshot); suite penuh **460 lulus / 0 gagal**; analyze bersih
di kelima berkas tersentuh.

## Belum termasuk (di luar Fase A)

1. Tampilan harga grosir di keranjang _pos.jsp (otoritas harga FINAL sudah
   ikut lewat bayar; yang tertinggal hanya pratinjau di kanal web).
2. Keputusan terbuka dok. 48 §6: kelipatan wajib kemasan, dan harga tetap
   per-kemasan (Metode 2) bila diminta.
