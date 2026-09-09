# Hasil UAT End-to-End AB Chicken POS Desktop

Tanggal pengujian: 9 September 2026
Tenant: `abchiken`
Schema: `abchiken`
Audit schema: `abchiken__audit`
Mode: `TENANT_ONLY`
Outlet pilot: **Pusat AB Chicken**
Gudang pusat: **Gudang Utama AB Chicken**
Client: POS Desktop Windows varian `abchicken`, versi 1.34.27 build 190

## Kesimpulan

UAT dinyatakan **LULUS** pada gate kontrak, data, aksi, dan laporan. Pengujian tidak hanya membaca API:
integration test mengendalikan POS Desktop, memilih menu serta filter, membuka dialog aksi, menekan
tombol yang sesuai, mengonfirmasi posting, dan membaca kembali status hasil dari server. Web tidak
dipakai untuk menyelesaikan transaksi operasional.

## Gate data dan integritas

- 1 outlet pilot dan 1 gudang pusat.
- 50 produk jadi dan 100 bahan baku.
- 50 relasi resep/BOM; setiap produk contoh terhubung ke bahan baku.
- 170 pesanan outlet.
- Masing-masing 170 PR, PO, BAST vendor, tagihan vendor, pembayaran vendor, produksi, dan pengiriman.
- 80 klaim/backorder dan 120 penjualan POS.
- 300 jurnal tersedia sebelum aksi baru dijalankan.
- 19 dari 19 pemeriksaan integritas lulus dan tidak ada layar proses kosong.

## Gate aksi POS Desktop

| Urutan | Proses | Dokumen | Status awal | Status akhir | Jurnal | Hasil |
|---:|---|---|---|---|---:|---|
| 1 | Pesanan outlet | UAT-AB-REQ-0007 | DRAFT | ALLOCATED | — | LULUS |
| 2 | PR | UAT-AB-PR-0009 | DRAFT | APPROVED | — | LULUS |
| 3 | PO vendor | UAT-AB-PO-0009 | DRAFT | APPROVED | — | LULUS |
| 4 | BAST vendor | UAT-AB-BAST-0009 | DRAFT | POSTED | 301 | LULUS |
| 5 | Tagihan vendor | UAT-AB-INV-0010 | DRAFT | POSTED | 302 | LULUS |
| 6 | Pembayaran vendor | UAT-AB-PAY-0010 | DRAFT | POSTED | 303 | LULUS |
| 7 | Produksi gudang | UAT-AB-PROD-0010 | DRAFT | POSTED | 304 | LULUS |
| 8 | Delivery Order | UAT-AB-SHP-0010 | DRAFT | COMPLETED | 305 | LULUS |
| 9 | Klaim/backorder | UAT-AB-CLM-0010 | DRAFT | RESOLVED | — | LULUS |
| 10 | Penjualan POS | UAT-AB-POS-00044 | DRAF | TERPOSTING | 306 | LULUS |

Status perantara juga diuji. Pesanan melewati SUBMITTED dan APPROVED sebelum ALLOCATED; BAST,
tagihan, pembayaran, serta produksi melewati approval dan dialog konfirmasi sebelum POSTED; Delivery
Order melewati SUBMITTED, APPROVED, DELIVERY, dan ARRIVED sebelum COMPLETED; klaim melewati approval
sebelum RESOLVED. Setelah seluruh aksi, 19 pemeriksaan integritas tetap lulus.

## Gate laporan akuntansi

| Laporan | Baris | Hasil utama |
|---|---:|---|
| Keseluruhan Jurnal | 594 | Debit dan kredit Rp1.422.723.912,50; halaman 43/43 terbaca |
| Buku Besar | 594 | Nomor sumber dan mutasi akun dapat ditelusuri |
| Neraca Saldo | 7 | Total debit sama dengan total kredit |
| Laba Rugi | 7 | Pendapatan Rp4.310.000; HPP Rp2.525.287,50; laba Rp1.784.712,50 |
| Neraca | 11 | Aset sama dengan liabilitas dan ekuitas Rp121.278.462,50; selisih 0 |
| Arus Kas | 5 | Penerimaan Rp4.310.000; pembayaran Rp373.706.250 |

Arus Kas menghasilkan saldo akhir negatif Rp369.396.250 karena data pilot belum memiliki saldo awal
kas/bank. Perhitungan dan penelusuran jurnal dinyatakan benar, tetapi data pembukuan produksi harus
didahului dengan pengisian saldo awal yang disetujui.

## Relasi akun yang diverifikasi

- BAST vendor: debit 114100 Persediaan Bahan Baku; kredit 210100 GRNI.
- Tagihan vendor: debit 210100 GRNI; kredit 210200 Hutang Vendor.
- Pembayaran vendor: debit 210200 Hutang Vendor; kredit 111200 Bank Operasional.
- Produksi: debit 114200 Persediaan Barang Jadi; kredit 114100 Persediaan Bahan Baku.
- Pengiriman: mutasi persediaan antarlokasi dengan nilai tenant tetap seimbang.
- Penjualan POS: debit 111200 Bank dan 510100 HPP; kredit 410100 Pendapatan dan 114200 Persediaan.

Akun diselesaikan server dari Master Produk, BOM, dan Sumber Akun Posting. Akun tidak ditanam tetap
pada tombol posting. Koreksi dilakukan pada master, lalu halaman Desktop dimuat ulang dan dipratinjau
kembali sebelum posting.

## Temuan dan tindak lanjut

UAT menemukan kondisi respons lama dapat menimpa hasil filter terbaru ketika pengguna mengubah filter
status dengan cepat. Pengaman generasi muat telah ditambahkan pada
`lib/screens/abchicken/operasi_abchicken_screen.dart`. Perubahan ini berada di sisi POS Desktop dan
harus disertakan pada build/installer berikutnya; tidak memerlukan deploy ulang Tomcat eBisnis.

Tidak dilakukan penghapusan luas pada `C:\opt` karena lokasi tersebut dipakai banyak sesi. Seluruh
pekerjaan sementara UAT ditempatkan pada workspace terisolasi di drive E.
