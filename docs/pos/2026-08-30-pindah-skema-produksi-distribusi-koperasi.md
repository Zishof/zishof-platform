# 58. Tabel Produksi & Distribusi Pindah ke Skema `koperasi`

Tanggal: 30 Agustus 2026  
Status: terpasang & teruji di server lokal (UAT API admin lulus semua menu);
tercatat bersama rilis POS 1.34.09  
Rujukan: dok. 54 (prasyarat deployment lama), galat produksi ebisnis.id
30-08 (`PRODUCTION_SCHEMA_NOT_READY`, `relation
"inventory_distribution.distribution_document" does not exist`)

## Masalah

`hbm2ddl.auto=update` hanya membuat TABEL — tidak pernah membuat SCHEMA.
Modul Produksi (skema `inventory_production`) dan Pengiriman/Distribusi
(skema `inventory_distribution`) hanya berjalan di lingkungan yang skemanya
diprovisikan manual (UAT lama). Deployment produksi ebisnis.id tidak pernah
diprovisikan → SEMUA menu Produksi & Pengiriman gagal.

## Keputusan (pemilik, 30-08-2026)

Serahkan seluruh DDL ke Hibernate: tabel kedua modul pindah ke skema yang
SUDAH ada di semua deployment. Pemilik menyebut `inventory`; probe
`information_schema` membuktikan skema itu tidak ada bahkan di DB terpasang
— yang benar-benar ada di mana pun dan sudah menampung seluruh domain
inventori (produk, pengadaan, `mutasi_stok_produksi`, `produk_batch`)
adalah **`koperasi`**. Nama tabel TIDAK berubah; hanya skema.

- 9 entitas dipindah (5 produksi: `production_document`, `_line`, `_event`,
  `production_lot_genealogy`, `production_reservation`; 4 distribusi:
  `distribution_document`, `_line`, `_event`, `distribution_stock_posting`).
- 19 SQL mentah `DistribusiPengirimanApiHelper` + penjaga skema
  `ProduksiApiHelper` (cek `information_schema` + pesan admin) ikut pindah.
- Tidak ada tabrakan nama di `koperasi` (diverifikasi lewat
  `information_schema` sebelum pindah).
- Data uji lama `inventory_production.*` disalin satu kali ke `koperasi.*`
  (idempoten, hanya bila tujuan kosong; sequence di-setval). Skema lama
  dibiarkan sebagai arsip; produksi tidak punya data lama sama sekali.

## Bukti (server lokal, deploy penuh + restart)

- Boot `hbm2ddl` MEMBUAT sendiri kesembilan tabel `koperasi.*` — nol DDL
  manual, persis tujuan keputusan.
- UAT API (akun admin): `produksi_list` **9/9 jenis** status 00 (BOM, WO,
  issue, return, output, waste, cost, unbuild, quality_alert);
  `distribusi_list` **7/7 jenis** success (DO, FO, tracking, POD, penerimaan
  transfer, klaim, reverse logistics); jalur tulis `produksi_simpan` BOM →
  tampil kembali di daftar (lalu disapu).
- Harness fase diulang pada skema baru: Fase C **19/19**, D **17/17**,
  E **17/17**.

## Rollout produksi ebisnis.id

Cukup deploy build ini + restart. Tidak ada langkah database manual;
`hbm2ddl` membuat tabel di `koperasi` saat boot. Pesan
`PRODUCTION_SCHEMA_NOT_READY` kini hanya muncul bila boot belum tuntas,
dengan instruksi admin yang sudah disesuaikan.

## Catatan lingkungan pengembangan

Dua kejadian pohon-bersama saat pengerjaan: (1) cfg boot harness lama basi
(memetakan kelas terhapus, entri ber-spasi) — disegarkan dari cfg src;
(2) folder build (`uat-77608`, `fullcompile-*`) disapu sesi lain hingga
kosong — harness kini menunjuk kelas WEB-INF webapp terpasang.
