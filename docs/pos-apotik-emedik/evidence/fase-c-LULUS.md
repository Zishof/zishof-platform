# FASE C — Laporan Apotik — LULUS PENUH — 2026-08-12

Server: `https://demo.ecampus.id/ecampus/Api_eBisnis` (branch `feat/new-ui-rbac-role-user`
s/d `32de5201`). Akun `demo`, role uji `am` (grant `apotik_laporan` sementara, direstore).
Data uji dari FASE A/B (jual Paracetamol/Codein, register narkotika, batch ED 2020/2030).

## Hasil E2E (3 laporan read-only)

### 1. Laporan Penjualan (`apotik_laporan_penjualan`, periode 2020..2027)
- totalNilai=**Rp31.000**, totalQty=**7**, baris=2.
- Per item: `UJI-CDN Codein` qty 2 = Rp16.000; `UJI-PCT Paracetamol` qty 5 = Rp15.000.
- Per golongan: NARKOTIKA Rp16.000; BEBAS Rp15.000.
- Konsisten dgn transaksi uji (Paracetamol 5×@3.000 + Codein 2×@8.000). **LULUS**

### 2. Laporan Obat Terkendali (`apotik_laporan_terkendali`)
- 1 baris register: `2026-08-12 07:42 [NARKOTIKA] Codein qty 2`, pembeli "Budi Uji",
  dokter "dr Uji" — register wajib apotek tercatat lengkap. **LULUS**

### 3. Laporan Kedaluwarsa (`apotik_laporan_kedaluwarsa`)
- KPI: 1 sudah-kedaluwarsa, 2 segera, nilai terancam Rp34.500.
- `UJI-PCT ED 2020-01-01 sisa 10 = Rp15.000 (kedaluwarsa)`, `UJI-PCT ED 2030 sisa 5`,
  `UJI-CDN ED 2030 sisa 3`. **LULUS**

## Bug ditemukan & diperbaiki lewat E2E
`apotik_laporan_penjualan` gagal (generic system error): SQL memakai
`hasil_penghitungan_total` padahal kolom sebenarnya `hasilpenghitungantotal`
(jebakan Hibernate implicit-naming: camelCase digabung tanpa underscore). Fix
`32de5201` (3 titik). Dua laporan lain lolos sejak awal.

## Gerbang & kebersihan
- `apotik_laporan_*` fail-closed di `apotik_laporan` (403 tanpa grant; success setelah grant).
- Role `am` direstore (apotik sisa-nyala=0). Data uji "UJI-*" sengaja ditinggal utk UAT ulang.

## Kesimpulan
Ketiga laporan apotek (penjualan, register obat terkendali, kedaluwarsa) terbukti di
server hidup dgn data nyata. **FASE C: LULUS.** Layar Flutter 3 tab (`db3bf2c`) siap
mengonsumsi ketiga aksi ini.
