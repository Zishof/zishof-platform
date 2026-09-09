# TokoQu Al-Bahjah An Nahl Desktop 1.34.30 (build 193)

Rilis ini memperbaiki checkout saat server atau pusat data tidak dapat
dihubungi. Metode pembayaran yang sudah tersimpan dapat langsung dipilih; proses
penyegaran server tidak lagi mengunci F4 maupun F2. Transaksi POS biasa tetap
ditulis ke penyimpanan lokal dan dikirim ulang secara idempoten setelah koneksi
pulih.

## Perbaikan

- Cache-first untuk daftar metode pembayaran checkout.
- Snapshot terisolasi per varian, tenant, pengguna, toko, dan member.
- Perlindungan agar izin metode member lama tidak dipakai setelah member diganti.
- Fallback cache mencakup timeout, HTTP 5xx, dan respons gateway teknis, bukan
  hanya status jaringan offline.
- Penyegaran metode tetap berjalan di latar tanpa menghentikan kasir.
- Validasi saldo, PIN/biometrik, limit, dan otorisasi sensitif tetap wajib.
- Kanal auto-update tetap khusus tag `nahl-*`; paket Al-Bahjah umum tidak dapat
  terpilih oleh aplikasi Nahl.

## Verifikasi

- 73 pengujian offline/outbox/izin metode: lulus.
- Analisis statis: tanpa error atau warning baru.
- Paket: Windows Desktop saja; tidak menyertakan APK.
- Tidak memerlukan deploy server.

Dokumentasi teknis dan matriks UAT tersedia pada
`docs/pos/2026-09-09-offline-metode-pembayaran-pos.md`.

