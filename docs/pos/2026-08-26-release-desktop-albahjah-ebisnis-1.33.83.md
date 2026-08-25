# Rilis POS Desktop 1.33.83 (build 141)

Tanggal rilis: 26 Agustus 2026

Varian:

- Al-Bahjah POS Desktop
- eBisnis POS Desktop

## Ringkasan perubahan

- Menyatukan perubahan terbaru lintas sesi pada modul POS Desktop dan memastikan varian Al-Bahjah serta eBisnis dibangun dari sumber yang sama.
- Memperbaiki alur pengadaan, termasuk tata letak aksi, penerimaan tagihan vendor, proses transfer, serta validasi status agar tindakan yang sudah selesai tidak dapat dijalankan ulang.
- Memperbaiki alur jurnal otomatis pada realisasi transfer dan memperjelas tampilan draft jurnal beserta pasangan debit/kredit sebelum diposting.
- Menyelaraskan perilaku modul akuntansi Desktop dengan alur bisnis versi ZKoss yang relevan tanpa menghilangkan fungsi Desktop yang sudah ada.
- Memperbaiki pencarian produk POS secara asinkron dan mempertahankan hasil lokal agar produk tidak menghilang ketika respons lama datang terlambat.
- Menyegarkan metode pembayaran berdasarkan kasir/toko aktif sehingga pilihan pembayaran tidak tertinggal antarperangkat.
- Menambah pengamanan sesi kas, agregasi transaksi, dan kompatibilitas respons API lama.
- Memperbaiki paging tabel umum, cakupan toko pada produk, tampilan Draft Jurnal, serta filter Layanan Semua.
- Menyertakan pembaruan responsivitas, navigasi, dan konsistensi tampilan dari perubahan sesi-sesi terbaru.

## Kompatibilitas dan lingkup

- Server bawaan varian Al-Bahjah tetap menggunakan konfigurasi Al-Bahjah.
- Server bawaan varian eBisnis tetap menggunakan `https://ebisnis.id/ebisnis`.
- Penyimpanan lokal tetap terpisah per varian agar kedua aplikasi dapat dipasang pada komputer yang sama.
- Rilis ini membangun installer Windows Desktop; artefak Android tidak termasuk dalam rilis ini.

## Verifikasi

- [ ] Build Al-Bahjah POS Desktop berhasil.
- [ ] Build eBisnis POS Desktop berhasil.
- [ ] Installer dan checksum SHA-256 diverifikasi.
- [ ] Commit rilis didorong ke GitHub.
- [ ] Artefak diterbitkan pada GitHub Release.

## Artefak

Checksum dan tautan rilis diisi setelah proses build dan publikasi selesai.
