# 80. Self-Test Mesin-Status Distribusi/Logistik

Tanggal: 3 September 2026  
Modul: Pengadaan & Logistik  
Sifat: penguatan pengujian (regresi bebas basis data)

## Latar

Sesudah memperbaiki race stok ganda pada BAST (dok. 79), audit modul dilanjutkan
ke sisi distribusi. `DistribusiPengirimanApiHelper` sudah aman terhadap
posting-ganda karena `ubahStatus` mengunci baris dokumen `FOR UPDATE`, memakai
idempotensi per dokumen+baris+arah, dan mesin status menolak transisi ulang.
Tidak ditemukan bug — tetapi invarian yang menjaga hal itu belum terkunci uji.

## Yang ditambahkan

`DistribusiPengirimanSelfTest` (tanpa JUnit, **tanpa basis data**) mengunci tiga
invarian integritas stok:

1. **Hanya dua jenis dokumen menyentuh stok** — `penerimaan_transfer_outlet` dan
   `reverse_logistics`; jenis lain (`delivery_order`, `freight_order`, dst.)
   tidak boleh memicu mutasi.
2. **`COMPLETED` tak dapat dicapai lewat jalan pintas** — hanya dari `APPROVED`/
   `IN_PROGRESS` (yang sudah melewati persetujuan dan validasi kelengkapan),
   bukan langsung dari `DRAFT`/`SUBMITTED`.
3. **Status final tidak berpindah lagi** — `COMPLETED` hanya ke `REVERSED`;
   `REVERSED` dan `CANCELLED` terminal. Ini yang mencegah posting maju terjadi
   dua kali dan pembalikan berulang.

`transisiBoleh` dan `memengaruhiStok` dibuka dari `private` menjadi
package-private untuk keperluan uji sepaket; logikanya tidak diubah.

## Bukti

`DistribusiPengirimanSelfTest` lulus penuh. Karena bebas basis data, ia juga
berguna sebagai pemeriksaan cepat sebelum menyunting mesin status, dan tetap
dapat dijalankan meski SessionFactory UAT sedang tidak dapat dibangun (kendala
entitas sesi lain yang setengah ter-deploy).

## Catatan

Melengkapi pola self-test SQL/aturan yang sudah dipakai di modul lain sesi ini
(`LaporanKantinSqlSelfTest`, `SqlSecurityGuardSelfTest`): mengunci keputusan yang
mudah rusak diam-diam, cepat, dan tidak bergantung lingkungan.
