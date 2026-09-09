# Perbaikan Checkout Offline — Metode Pembayaran POS

Tanggal: 9 September 2026

Versi aplikasi: `1.34.30+193`

Cakupan rilis: Desktop Al-Bahjah dan Desktop Nahl

## Ringkasan kejadian

Ketika pusat data tidak dapat dihubungi, panel checkout berhenti pada tulisan
**Memuat metode...**. Tombol F4 untuk memilih metode pembayaran dan tombol F2
untuk membayar ikut nonaktif sampai permintaan jaringan selesai atau timeout.
Kondisi ini terjadi walaupun konfigurasi login telah menyediakan daftar metode
pembayaran dan transaksi POS biasa sudah mempunyai outbox lokal.

## Akar masalah

Layar menganggap proses penyegaran API sebagai syarat pembayaran. Daftar yang
sudah berada di memori/cache tidak ditampilkan selama penyegaran berlangsung.
Selain itu, respons `cara_bayar_list` per member belum disimpan dalam snapshot
permanen yang dipisahkan menurut konteks akses.

## Perilaku setelah perbaikan

1. Snapshot metode pembayaran lokal ditampilkan terlebih dahulu; penyegaran
   server berlangsung di latar.
2. F4 dan F2 tetap aktif saat server tidak dapat dijangkau, selama aplikasi
   mempunyai snapshot yang sah untuk konteks transaksi aktif.
3. Snapshot dipisahkan menurut varian aplikasi, tenant, pengguna, toko, dan
   member. Data Al-Bahjah tidak dapat dibaca Nahl, dan izin satu member tidak
   dapat dipakai member lain.
4. Ketika member diganti dan belum ada snapshot untuk member baru, pilihan lama
   langsung dibuang. Checkout menunggu data yang benar atau snapshot member
   tersebut; aplikasi tidak menebak izin pembayaran.
5. Transaksi biasa disimpan ke SQLite terlebih dahulu dengan status PENDING,
   lalu dikirim ulang memakai kode transaksi yang sama ketika server pulih.
6. Metode yang memerlukan verifikasi saldo/deposit, PIN/biometrik, limit member,
   gateway, atau otorisasi server tetap fail-closed. Tidak ada saldo atau
   persetujuan semu yang dibuat oleh klien.

## Matriks UAT

| Skenario | Hasil yang diwajibkan |
|---|---|
| Server tersedia, tanpa member | Metode terbaru dimuat dan snapshot diperbarui |
| Server putus setelah pernah sinkron | Metode tersimpan langsung tampil; F4 dapat dibuka |
| Server 500/502/503 atau respons gateway rusak | Cache sah tetap dipakai; penolakan bisnis tetap ditampilkan |
| Pembayaran tunai biasa saat offline | Transaksi tersimpan lokal dan masuk antrean sinkronisasi |
| Aplikasi dibuka ulang dengan snapshot yang sah | Daftar metode dapat dipulihkan dari SQLite |
| Member diganti ketika offline tanpa snapshot member itu | Metode lama dibuang dan pembayaran ditahan |
| Snapshot berasal dari toko/tenant/pengguna lain | Snapshot ditolak karena kunci konteks berbeda |
| Metode membutuhkan saldo/PIN/limit | Verifikasi khusus tetap wajib dan tidak dilewati |
| Server pulih | Antrean dikirim dengan kode dan waktu transaksi asli; tidak menggandakan nota |

## Audit pola serupa

- Helper baca lokal kini menggunakan klasifikasi gangguan teknis bersama:
  jaringan putus, timeout, HTTP 5xx, jawaban gateway non-JSON, dan kode teknis
  dapat memakai cache. HTTP 401/403 dan validasi bisnis tidak ditutupi cache.
- Checklist metode pembayaran pada master **Jenis Member** sekarang membaca
  snapshot yang sama dengan master **Tipe Member** sebelum menyegarkan server.
- Referensi metode pembayaran Kasir Apotik juga dipindahkan ke pola cache-first.
  Perubahan ini masuk codebase bersama, tetapi paket Apotik tidak diterbitkan
  dalam rilis desktop Al-Bahjah/Nahl ini.
- Top-up online, payment gateway, posting jurnal, pembalikan transaksi, dan
  putusan pengadaan tetap online-only karena memerlukan keputusan server saat
  itu juga.

## Verifikasi rilis

- 73 pengujian terfokus untuk kebijakan cache, pemisahan konteks, izin member,
  klasifikasi error, master offline, dan transaksi outbox: lulus.
- Analisis statis: tidak ada error atau warning baru; tersisa 45 informasi lint
  lama di area yang tidak terkait.
- Build wajib memakai target varian masing-masing dan kanal update terpisah:
  tag `albahjah-*` hanya untuk Al-Bahjah dan tag `nahl-*` hanya untuk Nahl.
- Paket rilis ini desktop-only; tidak menyertakan APK.

## Kebutuhan deploy server

Tidak ada perubahan endpoint, skema basis data, atau kontrak payload server.
Perbaikan berada sepenuhnya pada aplikasi desktop. Server tidak perlu dibangun
atau dideploy ulang untuk rilis ini.

## Pesan operasional ketika pusat data terganggu

> Mohon maaf, saat ini sedang terjadi gangguan pada pusat data. Tim kami sedang
> melakukan pemeriksaan dan pemulihan layanan. Transaksi POS biasa tetap dapat
> dilayani secara offline dan akan disinkronkan setelah layanan kembali normal.
> Terima kasih atas pengertiannya. 🙏
