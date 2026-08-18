# UAT Runtime — MitraInap Langkah 5 (Tiket Dapur + Kontrak/Statement Pemilik)

**Tanggal:** 18 Agustus 2026 (malam, Asia/Jakarta)
**Lingkungan:** UAT lokal — PostgreSQL `localhost:5432/ais` + Tomcat UAT port 18080
(pola & harness sama dengan `uat-room-charge-2026-08-18.md`; lapisan token Bearer
di luar cakupan, penolakan anonim diverifikasi ulang lewat HTTP).
**Build yang diuji:** working copy SVN pasca r77597 + perubahan Langkah 5 (belum
di-commit): entity `TiketDapur`/`KontrakPemilik`/`LaporanPemilik`, aksi
`hotel_kitchen_ticket_list|update`, `hotel_kontrak_pemilik_simpan|list`,
`hotel_laporan_pemilik_generate|list`, hook tiket dapur di `KantinHelper.bayar`
(payload `hotel_tiket_dapur=true`), 3 kunci menu baru fail-closed.

## Hasil: SELURUH 12 LANGKAH LULUS (`pass=12 fail=0`, run pertama)

| # | Langkah | Hasil |
|---|---|---|
| 1 | Master minimal (properti→tipe→kamar→tamu→check-in) | ✓ |
| 2 | `bayar` + `hotel_tiket_dapur=true` + `hotel_menginap_id` sekaligus → tiket QUEUED **dan** room charge tercatat dari SATU nota | ✓ `tiket=DIBUAT rc=TERCATAT` |
| 3 | Pembuatan tiket kedua utk nota sama → `IDEMPOTENT` (kolom unik `pembelian`) | ✓ |
| 4 | `hotel_kitchen_ticket_list` antrean aktif memuat tiket + rincian item nota (nama × qty) | ✓ |
| 5 | Transisi ILEGAL `QUEUED → SERVED` → **ditolak 91** (gap Node yang sengaja ditutup: versi Node upsert tanpa validasi) | ✓ |
| 6 | Jalur sah `QUEUED→PREPARING→READY→SERVED` + mundur dari SERVED ditolak (terminal) | ✓ |
| 7 | Kontrak pemilik: `persen_komisi=150` ditolak; kontrak sah (kamar 501, 20%) tersimpan | ✓ |
| 8 | Checkout stay → ROOM_CHARGE 300.000 masuk folio | ✓ |
| 9 | `hotel_laporan_pemilik_generate` Agu 2026: **kotor = 300.000 (hanya ROOM_CHARGE — POS_CHARGE 30.000 milik tamu TIDAK ikut pendapatan pemilik)**, komisi 20% = 60.000, biaya 15.000, bersih 225.000, hash SHA-256 64 char | ✓ |
| 10 | Generate ulang periode sama → idempoten, id & hash sama | ✓ |
| 11 | `hotel_laporan_pemilik_list` per properti memuat baris + snapshot rincian transaksi | ✓ |
| 12 | HTTP anonim `hotel_kitchen_ticket_list` → `{"status":"90"}` rapi | ✓ |

## Perbedaan disengaja dari referensi Node (didokumentasikan di JavaDoc)

1. **Transisi tiket dapur divalidasi server** (`transisiDapurBoleh`) — Node
   (`kitchen()` pos-hospitality.service.ts) melakukan upsert status tanpa
   validasi; handover menandai ini WAJIB diperbaiki di port Java.
2. **Statement dihitung server** dari baris ROOM_CHARGE folio kamar kontrak —
   Node `statement()` menerima gross/commission/net mentah dari klien (dan UAT
   Node menemukan endpoint pembuat kontraknya tidak pernah ada, sehingga
   statement tak terpakai ujung-ke-ujung; port Java mengirim keduanya sekaligus).
3. **Timestamp fase tiket diisi sekali** (pola COALESCE Node dipertahankan).

## Penyiapan lingkungan UAT pass ini

3 kelas entity + helper/PosApi/KantinHelper/EbisnisMenuKatalog dideploy ke
`.uat-classes`; +3 mapping cfg UAT; 3 tabel `public.hotel_*` + 3
`new_audit.*__audit` dibuat manual (padanan DDL hbm2ddl produksi); data uji
dibersihkan tuntas setelah lulus; Tomcat UAT restart bersih dengan overlay final.

## Yang TIDAK dicakup

Sama dengan pass Langkah 4: lapisan token end-to-end, klik-through UI Flutter
(layar `tiket_dapur_screen` / `kontrak_pemilik_screen` / `laporan_pemilik_screen`
+ checkbox "Buat tiket dapur" keranjang), dan role non-admin bersungguhan.
