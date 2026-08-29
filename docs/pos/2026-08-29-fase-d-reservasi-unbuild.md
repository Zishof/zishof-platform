# Fase D — Reservasi Komponen WO, Kekurangan → Pengajuan, UNBUILD

Tanggal: 29 Agustus 2026  
Status: server + Flutter **lulus** (TesFaseDProduksi 17/17 di DB UAT; Flutter
501/501; analyze bersih di berkas tersentuh); belum di-commit  
Rujukan: SVN `docs/pos/54-fase-d-reservasi-kekurangan-unbuild.md` (keputusan
lengkap), dok. 48 §4 Fase 4

## Ringkas

Tiga kemampuan produksi baru, semuanya menumpang mesin yang sudah terbukti:

- **UNBUILD (bongkar barang jadi)**: tipe dokumen produksi baru — kebalikan
  OUTPUT+ISSUE dalam SATU dokumen (barang jadi keluar, komponen BOM kembali
  masuk). Ledger, idempoten, dan REVERSED Fase 0 dipakai apa adanya; yang
  baru hanya arah stok per-BARIS (baris OUTPUT keluar, lainnya masuk).
- **Reservasi komponen** (`production_reservation`): WO RELEASED mengunci
  kebutuhan komponen BOM; ISSUE ber-referensi WO memakan sisa (REVERSED
  memulihkan); CANCELLED/COMPLETED melepas. **Informasi saja bagi kasir** —
  keputusan dok. 48 §6 no. 4 (reserved menolak penjualan?) masih terbuka,
  jadi tidak ada alur kasir yang berubah.
- **Kekurangan komponen saat rilis WO** → `PengajuanPembelianGudang`
  ber-rujukan WO (kolom `wo_id` baru), gudang asal = Gudang Pemasok toko;
  toko tanpa gudang pemasok tetap mendapat laporan kekurangan di respons
  rilis + catatan dokumen, tidak diam-diam hilang.

## Sisi Flutter (repo ini)

- `screens/produksi_screen.dart`: bagian baru `productionUnbuild` →
  layar produksi generik yang sama (`production_unbuild`, "Unbuild /
  Bongkar"); form baris sudah bisa memilih tipe OUTPUT vs MATERIAL sejak
  Fase 9, jadi tidak ada UI baru yang perlu ditulis.
- `widgets/app_shell.dart`: menu "Unbuild / Bongkar Barang Jadi" di grup
  Produksi, kunci izin `produksi_production_unbuild` (gerbang profil
  inventory-sales yang sama dengan menu produksi lain), plus dua switch
  MenuEBisnis dilengkapi (label drawer + pemetaan balik).

## Bukti

- `TesFaseDProduksi` 17/17 (DB UAT; refleksi ke method private persis yang
  dipanggil `ubahStatus`; `gudang_pemasok` toko dipulihkan seusai uji):
  reservasi 2×10/3×10, kekurangan → pengajuan 20 ber-`wo_id`, idempoten
  rilis, ISSUE memakan/memulihkan sisa, arah UNBUILD per-baris, posting
  dobel tidak menggandakan, REVERSED menukar arah, batal menutup reservasi.
- `javac 1.7` EXIT=0; Flutter suite penuh **501 lulus / 0 gagal**; analyze
  bersih di kedua berkas tersentuh.

## Perhatian pohon bersama

`app_shell.dart` juga memuat suntingan sesi lain yang belum di-commit —
saat commit, pisahkan hunk (blob `git hash-object` + `git update-index`,
commit TANPA pathspec) atau verifikasi diff sebelum `git add`.
