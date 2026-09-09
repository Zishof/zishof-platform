# Al-Bahjah POS Desktop 1.34.31 (build 194)

Rilis Desktop ini memperbaiki penanganan gangguan gateway HTTP 522 dan
memperkuat urutan local-first pada cache/outbox. Respons gateway teks tidak lagi
ditampilkan sebagai `FormatException`; pengguna memperoleh pesan operasional dan
langkah pemulihan, sedangkan detail teknis tetap dapat disalin oleh admin.

## Perbaikan utama

- HTTP 522/5xx dan timeout gateway dikenali sebagai gangguan sementara.
- Login baru tetap fail-closed dan tidak pernah dianggap berhasil tanpa server.
- Mutasi master serta outbox idempoten ditulis lokal sebelum dikirim.
- Pratinjau posting terakhir dapat dibaca offline tanpa memulihkan hak posting
  final dari cache.
- Cache, outbox, alamat server, dan kanal auto-update tetap memakai namespace
  `albahjah`; paket Nahl tidak dapat terpilih sebagai pembaruan.

## Verifikasi dan batasan

- 108 pengujian gateway/login dan regresi POS, 6 pengujian database outbox,
  serta pengujian kanal pembaruan lulus.
- Sapuan penuh mencatat 827 lulus dan 8 test kontrak eksternal tidak dapat
  dijalankan karena file runner/source AIS di luar repo tidak tersedia.
- Analisis statis tidak menemukan error atau warning.
- Paket hanya untuk Windows Desktop dan belum ditandatangani Authenticode;
  gunakan untuk UAT/internal sesuai kebijakan organisasi.
- Tidak membutuhkan deploy server. Gangguan HTTP 522 pada origin tetap harus
  dipulihkan oleh pengelola data-centre.

Dokumentasi teknis dan matriks UAT tersedia di
`docs/pos/2026-09-09-http-522-login-dan-penguatan-local-first.md`.
