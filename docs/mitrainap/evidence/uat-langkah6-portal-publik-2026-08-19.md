# UAT Runtime — MitraInap Langkah 6 (Portal Publik Booking + Pembayaran)

**Tanggal:** 19 Agustus 2026 (dini hari, Asia/Jakarta)
**Lingkungan:** UAT lokal — Tomcat 18080 + PostgreSQL `localhost:5432/ais`.
**Jalur uji:** **HTTP ANONIM SUNGGUHAN** ke `/ais/mitrainap-publik` (servlet publik
baru; tanpa token staf — endpoint memang publik, jadi UAT-nya end-to-end penuh
termasuk lapisan servlet/filter), plus satu panggilan harness utk aksi staf.

**Build yang diuji:** `MitraInapPublikServlet` + `MitraInapPublikHelper` +
`hotel_booking_konfirmasi_bayar` (HotelApiHelper) + registrasi `web.xml`
(semuanya belum di-commit saat pass ini).

## Hasil: 11/11 LULUS

| # | Langkah | Hasil |
|---|---|---|
| 1 | `mode=katalog` — properti aktif + tipe kamar + harga (hanya data publik) | ✓ |
| 2 | `mode=ketersediaan` 2 malam → `tersedia:2`, `total:400000` (harga dihitung server) | ✓ |
| 3 | `mode=booking` POST → Tamu + Reservasi BOOKED + tagihan `KodePembayaranOnline` (kode 64 hex, nominal server-side) | ✓ `BOOK-D395E7BC2E` |
| 4 | POST ulang `idempotency_key` sama → booking yang SAMA dikembalikan (`idempotent:true`, via RetailIdempotencyUtil) | ✓ |
| 5 | Ketersediaan turun ke 1 — booking BOOKED langsung mengunci slot | ✓ |
| 6 | `mode=status` (kode+telp) → BOOKED, `lunas:false` | ✓ |
| 7 | `mode=status` telp salah → ditolak (verifikasi kepemilikan ringan) | ✓ |
| 8 | Honeypot `website` terisi → sukses PALSU (`BOOK-TERIMA`) dan **tidak ada record tersimpan** (diverifikasi SQL) | ✓ |
| 9 | `checkin` masa lalu → ditolak 91 | ✓ |
| 10 | Aksi staf `hotel_booking_konfirmasi_bayar` (gate hotel_reservasi/approve) → logPembayaran "MANUAL oleh admin_1 …", reservasi CONFIRMED | ✓ |
| 11 | `mode=status` publik → `CONFIRMED`, `lunas:true` — lingkaran booking → bayar → konfirmasi tertutup | ✓ |

Keamanan yang terpasang (pola `PendaftaranTenantServlet`): rate limit per IP
(katalog 60/jam, ketersediaan 120/jam, status 60/jam, booking 5/jam), honeypot
anti-bot, error internal tidak pernah membocorkan stack trace (amplop 91 generik +
ErrorAuditUtil), idempotency key wajib utk booking. Batas rate tidak diuji live
(akan mengunci IP uji 1 jam) — logika = `PublicRegistrationRateLimiter` existing.

## Status pembayaran online (keputusan kanal MENUNGGU)

Booking menerbitkan tagihan `KodePembayaranOnline` (nominal server-side, penanda
`keterangan=MITRAINAP-BOOKING:<kode>`; lunas = `logPembayaran` terisi; promosi
BOOKED→CONFIRMED otomatis di endpoint status). **Wiring webhook kanal bank
(VA BTN / QRIS / Moota dsb.) belum dipasang — butuh keputusan kanal + kredensial
merchant**; sementara itu verifikasi manual staf (`hotel_booking_konfirmasi_bayar`)
menutup alurnya. Desain sengaja TANPA kolom baru di entity ber-audit lama.

## Insiden lingkungan selama pass (bukan bug fitur)

1. **Kelas akunting sesi paralel** (`DaftarPengajuanTransfer`/`ReimbursementPegawai`,
   in-flight) sempat mematikan factory Hibernate UAT dua kali:
   relasi audited→non-audited tanpa `targetAuditMode=NOT_AUDITED`, lalu getter
   `getAktif()` turunan tanpa setter/@Transient. Perbaikan `targetAuditMode`
   di DaftarPengajuanTransfer dipertahankan; **ReimbursementPegawai TIDAK diubah**
   (permintaan eksplisit — sesi paralel menanganinya sendiri; overlay UAT sementara
   memakai binari scaffold agar bisa boot, refresh dari source mereka setelah commit).
   ⚠ Keduanya HARUS konsisten sebelum deploy produksi — pola insiden `hotel.Kamar`
   (produksi mati di restart harian).
2. **`.uat-classes/hibernate.cfg.xml` tertimpa template** (`${username}`/`${password}`
   + URL `/.uat-classes` hasil substitusi meleset) → pool webapp gagal autentikasi;
   tiga baris koneksi dipulihkan (mapping tidak hilang).

## Data uji dibersihkan tuntas setelah lulus.
