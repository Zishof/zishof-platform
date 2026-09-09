# TokoQu Al-Bahjah An Nahl Desktop 1.34.31 (build 194)

Rilis Desktop ini menindaklanjuti insiden login pada endpoint
`https://an-nahl.santri.info/nahl/Api_eBisnis` yang mengembalikan HTTP 522 berupa
teks. Aplikasi tidak lagi menampilkan `FormatException` sebagai pesan utama;
pengguna memperoleh penjelasan bahwa server belum menilai akun/kata sandi dan
langkah pemulihan yang aman.

## Perbaikan utama

- HTTP 522/5xx dan timeout gateway dikenali sebagai gangguan sementara.
- Login baru tetap fail-closed dan tidak pernah dianggap berhasil tanpa server.
- Mutasi master serta outbox idempoten ditulis lokal sebelum dikirim.
- Pratinjau posting terakhir dapat dibaca offline tanpa memulihkan hak posting
  final dari cache.
- Cache, outbox, alamat server, dan kanal auto-update tetap memakai namespace
  `nahl`; paket Al-Bahjah umum tidak dapat terpilih sebagai pembaruan.

## Verifikasi dan batasan

- 108 pengujian gateway/login dan regresi POS, 6 pengujian database outbox,
  serta pengujian kanal pembaruan lulus.
- Sapuan penuh mencatat 827 lulus dan 8 test kontrak eksternal tidak dapat
  dijalankan karena file runner/source AIS di luar repo tidak tersedia.
- Analisis statis tidak menemukan error atau warning.
- Reproduksi awal memperoleh HTTP 522. Probe pra-rilis pada 9 September 2026
  pukul 15.16 WIB sudah memperoleh HTTP 401 berbentuk JSON untuk identitas dummy,
  sehingga jalur Cloudflare–origin dinilai kembali merespons. Login akun nyata
  tidak dilakukan dan tidak diklaim lulus.
- Paket hanya untuk Windows Desktop dan belum ditandatangani Authenticode;
  gunakan untuk UAT/internal sesuai kebijakan organisasi.
- Perbaikan aplikasi tidak membutuhkan deploy WAR/server. HTTP 522 tetap harus
  ditangani pada infrastruktur data-centre/origin.

Dokumentasi teknis dan matriks UAT tersedia di
`docs/pos/2026-09-09-http-522-login-dan-penguatan-local-first.md`.
