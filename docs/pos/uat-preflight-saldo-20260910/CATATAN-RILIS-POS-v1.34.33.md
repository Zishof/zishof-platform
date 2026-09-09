# Catatan Rilis POS Desktop v1.34.33

Tanggal rilis: 10 September 2026

Build: `1.34.33+196`

## Ringkasan

Rilis ini mencegah transaksi pembayaran saldo/voucher telanjur masuk daftar
pending ketika saldo pusat sebenarnya tidak mencukupi. Kasus acuan adalah nota
`AB20909202600019`: saldo yang sempat tampil Rp152.600, tetapi saldo terbaru di
server sudah Rp3.100 ketika transaksi Rp149.500 diproses.

Perbaikan diterapkan pada kode POS bersama untuk varian eBisnis, Al-Bahjah, dan
TokoQu Al-Bahjah An Nahl.

## Perubahan utama

- Saat **Bayar** ditekan dan salah satu metode memotong saldo, aplikasi membaca
  ulang saldo member dari server sebelum nomor transaksi dibuat.
- Saldo terbaru dibandingkan hanya dengan porsi pembayaran yang memotong saldo;
  transaksi split tunai+saldo tidak salah membandingkan seluruh total.
- Jika saldo kurang, dialog menampilkan saldo terbaru, nominal yang akan
  dipotong, dan nilai kekurangannya.
- Penolakan terjadi sebelum nomor transaksi, penyimpanan transaksi lokal, dan
  antrean sinkron dibuat. Keranjang tetap utuh agar kasir dapat melakukan topup
  atau mengganti metode pembayaran melalui F4.
- Jika server tidak dapat dihubungi, pembayaran saldo berhenti dengan pesan yang
  mudah dipahami dan tombol Informasi Teknis. Aplikasi tidak menampilkan sukses
  lokal palsu.
- Server tetap melakukan validasi atomik pada aksi pembayaran untuk mencegah
  race ketika saldo dipakai hampir bersamaan dari perangkat lain.
- Pembayaran tunai/manual yang aman tetap local-first: disimpan lokal lebih
  dahulu dan dikirim melalui outbox idempoten.
- Transaksi pending lama tetap dapat ditelusuri dan dikoreksi melalui Riwayat
  Sinkronisasi; rilis ini berfokus mencegah kasus baru.

## Dampak pada local-first

| Jenis pembayaran | Saat server tersedia | Saat server tidak tersedia |
|---|---|---|
| Tunai/manual aman | Lokal dahulu, sinkronisasi background | Tetap dapat dilayani dan masuk outbox |
| Saldo/voucher | Saldo diperiksa sebelum transaksi; server memberi keputusan akhir | Dihentikan sebelum transaksi dibuat |
| Split tunai+saldo | Porsi saldo diverifikasi, lalu transaksi diproses server | Dihentikan sebelum transaksi dibuat |
| PIN/biometrik/limit | Tetap memerlukan konfirmasi server | Dihentikan dengan penjelasan |

## Deploy server

Perbaikan ini memakai aksi `saldo_member` dan validasi `bayar` yang sudah tersedia.
Tidak ada migrasi basis data atau deploy server yang diperlukan untuk klien
v1.34.33. Validasi saldo atomik di server tidak boleh dinonaktifkan.

## Artefak

- `eBisnis-Setup-1.34.33.exe`
- `Al-Bahjah-POS-Setup-1.34.33.exe`
- `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.33.exe`
- `HASIL-UAT-PREFLIGHT-SALDO-POS-v1.34.33.md`
- Manual UAT Training Operasional eBisnis (Word dan PDF)
- `Bukti-UAT-Lengkap-POS-v1.34.33.zip`

Ketiga installer Windows Desktop merupakan build UAT tanpa tanda tangan digital.
Berkas SHA-256 disertakan pada setiap rilis untuk memverifikasi bahwa unduhan
utuh dan tidak berubah. Paket bukti UAT memiliki SHA-256
`a4aca0c22fd3fb7047e7c02ce941a8ab57d9e248d99f1b04a1296410bd61e8ca`.

## Ringkasan verifikasi

- Analisis statis: lulus tanpa temuan.
- Pengujian regresi aplikasi: 850/850 lulus.
- Regresi terfokus saldo, metode pembayaran, dan outbox: 20/20 lulus.
- Kanal auto-update eBisnis, Al-Bahjah, dan Nahl: 3/3 lulus dan terpisah.
- Build installer Windows Desktop: 3/3 berhasil.
