# 00 — Audit Kondisi Existing (Fase 0)

**Tanggal audit:** 19 Agustus 2026
**Branch:** `feature/apotik-modern-uiux` (worktree terpisah — `main` dipakai sesi lain)
**Basis:** commit `ce3d1b9`

## Ukuran source varian apotik

| File | Baris | Catatan |
|---|---:|---|
| `lib/screens/apotik/persediaan_apotik_screen.dart` | 1157 | **terlalu besar** — banyak tanggung jawab dalam satu file |
| `lib/screens/apotik/kasir_apotik_screen.dart` | 748 | POS + 2 sheet (batch, resep) dalam satu file |
| `lib/screens/apotik/laporan_apotik_screen.dart` | 492 | tiga laporan dalam satu file |
| `lib/screens/apotik/pos_help.dart` | 462 | bantuan kontekstual |
| `lib/screens/apotik/beranda_apotik_screen.dart` | 372 | dashboard kartu + chip menu |
| **Total** | **3231** | |

Pendukung bersama: `main_apotik.dart` (20), `theme/app_colors.dart` (79),
`widgets/app_shell.dart` (1602, dipakai SEMUA varian).

## Fondasi yang WAJIB dipertahankan

- Entrypoint `lib/main_apotik.dart` + `AppProductProfile.apotik()`.
- Pagar keselamatan yang sudah berjalan di kasir:
  - batch **FEFO** dengan prefill otomatis; batch kedaluwarsa **dinonaktifkan**;
  - badge **LASA** (nama mirip dibedakan visual);
  - **obat terkendali**: nama pembeli wajib + resep/nama dokter, jika tidak transaksi ditahan;
  - baris **racikan** pada resep ditampilkan TERKUNCI dengan alasan jujur (belum didukung kasir);
  - **kode idempoten dibuat SEKALI** sebelum kirim; retry memakai kode yang sama;
  - pesan penahan server ditampilkan apa adanya (tidak ditelan UI).
- Permission fail-closed (`bolehMenuVarianBaru`, default false).
- Offline-first master + baca lokal-dulu (`MasterOffline`) yang baru selesai di seluruh layar CRUD.

## Kekurangan yang dikonfirmasi dari source

1. **Dashboard** (`beranda_apotik_screen`) berorientasi kartu statistik + chip menu; ruang kerja utama kosong; tidak ada antrean resep, stok kritis, near-expiry, atau tugas shift.
2. **Kasir** memakai daftar teks satu baris (`kode • stok • harga`); tidak ada kartu obat yang membedakan bentuk/kekuatan/golongan; keranjang tanpa quantity stepper matang, tanpa edit batch inline, tanpa hold/resume.
3. **Mode transaksi** (OTC / Resep / Racikan / Produksi) tidak eksplisit — hanya tombol "Tebus Resep".
4. **Konteks kerja** (tenant, outlet, terminal, shift, sync, printer, scanner) tidak tampil konsisten.
5. **Persediaan** satu file 1157 baris — sulit dipelihara, akan makin berat saat batch/FEFO/karantina ditambah.
6. **Laporan** hanya angka + tabel dasar; belum cukup untuk rekonsiliasi & tutup shift.
7. **Struk/printer/laci** belum ada — kode kasir masih menyebut "Struk/cetak menyusul".
8. Tidak ada **golden test** untuk varian apotik.
9. Tidak ada **design token semantik** khusus apotik; warna diambil dari `AppColors` global (primary biru `#2563EB`, bukan teal farmasi `#0F766E` yang diminta).
10. Breakpoint tersebar sebagai pemeriksaan lebar ad-hoc, bukan kelas layout terpusat.

## Technical debt prioritas

| Debt | Dampak | Rencana |
|---|---|---|
| File layar >700 baris | sulit review & test | pecah ke `features/apotik/<domain>/` bertahap, layar lama jadi route adapter |
| Warna hard-code per layar | tidak konsisten | `ApotikDesignTokens` via ThemeExtension |
| Cek lebar ad-hoc | perilaku beda antar layar | `ApotikBreakpoints` terpusat |
| Tanpa golden test | regresi visual tak terdeteksi | golden Desktop + Mobile per layar |
