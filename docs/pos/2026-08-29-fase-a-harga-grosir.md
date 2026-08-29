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

## Belum termasuk (kelanjutan Fase A)

1. Pemilih kemasan sekali-ketuk di kartu produk kasir (tanpa scanner) +
   snapshot `kemasanNama/qtyDasar` pada baris supaya struk mencetak
   "2 Karung 50kg (100 kg)".
2. Layar kelola `AturanHargaProduk` (CRUD sudah ada di API).
3. Tampilan harga grosir di keranjang _pos.jsp (otoritas harga FINAL sudah
   ikut lewat bayar; yang tertinggal hanya pratinjau di kanal web).
4. Keputusan terbuka dok. 48 §6: kelipatan wajib kemasan, dan harga tetap
   per-kemasan (Metode 2) bila diminta.
