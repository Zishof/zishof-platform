# Rilis Al-Bahjah POS Desktop 1.33.84 (build 142)

Tanggal rilis: 26 Agustus 2026

## Masalah

POS sudah dapat membuka sesi terkunci saat server tidak terjangkau memakai bukti
kata sandi lokal yang dibuat setelah login daring berhasil. Namun waktu verifikasi
daring terakhir hanya dicatat dan belum dipakai sebagai batas. Akibatnya, bukti
lokal secara teoritis dapat dipakai melewati masa berlaku token perangkat.

## Perbaikan keamanan

- Login luring hanya tersedia bagi akun yang pernah berhasil diverifikasi server
  pada perangkat yang sama.
- Hanya kegagalan jaringan yang boleh jatuh ke verifikasi lokal. Kata sandi salah,
  akun nonaktif, dan penolakan server tetap gagal tertutup.
- Bukti lokal memakai PBKDF2-HMAC-SHA256 dengan garam acak; kata sandi asli tidak
  disimpan.
- Umur bukti luring dibatasi maksimum 30 hari, sama dengan masa berlaku token
  perangkat di server.
- Timestamp verifikasi yang berada di masa depan ditolak untuk mencegah clock
  rollback atau preferensi rusak memperpanjang akses.
- Keluar akun dan penolakan token server tetap menghapus token, bukti lokal, serta
  konteks tenant. Form login setelah logout tetap membutuhkan server.
- Pengikatan satu perangkat ke satu tenant dan penahanan antrean tenant lama tetap
  dipertahankan.

## UAT

- [x] Bukti belum tersedia: login luring ditolak.
- [x] Kata sandi benar diterima dan kata sandi salah ditolak.
- [x] Username lain ditolak walaupun memakai kata sandi yang sama.
- [x] Kata sandi asli tidak muncul di preferensi lokal.
- [x] Garam acak menghasilkan hash berbeda untuk kata sandi yang sama.
- [x] Logout menghapus seluruh jalan masuk luring.
- [x] Bukti berumur 29 hari masih berlaku.
- [x] Bukti lebih dari 30 hari ditolak.
- [x] Timestamp masa depan ditolak.
- [x] Penolakan server tidak dialihkan ke login luring.
- [x] Tenant berbeda dengan antrean tertunda ditahan.
- [x] Tenant berbeda dengan antrean kosong diarsipkan dan dialihkan.

## Hasil verifikasi otomatis

- `flutter analyze` pada lima file implementasi/tes terkait: **No issues found**.
- Tes paket `core_auth`: **10/10 lulus**.
- Tes terfokus login, tenant, dialog CRUD, dan kontrak Keuangan: **94/94 lulus**.
- Seluruh suite aplikasi: **358/358 lulus**.
- `git diff --check`: lulus.

## Hasil build

- Skrip: `tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah`.
- Flutter Windows release dan kompilasi installer Inno Setup: **berhasil**.
- Executable internal: `ebisnis_albahjah.exe`.
- Product/File version: `1.33.84+142`.
- Commit implementasi yang sudah didorong: `e3fce4e`.
- Authenticode: `NotSigned` karena pipeline lokal belum mempunyai sertifikat.

## Artefak

| Berkas | Ukuran | SHA-256 |
|---|---:|---|
| `Al-Bahjah-POS-Setup-1.33.84.exe` | 46.165.150 byte | `A2DC3068EDF4FA1BF2E585F153B3D0D1239C73B0879F6FD92E1472516A1AFFFB` |

Manifest `.sha256.txt` hasil build telah dibandingkan dengan perhitungan ulang dan
cocok. Publikasi memakai tag `v1.33.84-build142` pada repository
`Zishof/zishof-platform`.
