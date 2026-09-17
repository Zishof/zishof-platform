# TokoQu Al-Bahjah An Nahl 1.34.41 (build 204) — UAT

Rilis UAT yang menjawab empat keluhan produksi grup WhatsApp Al-Bahjah An Nahl
tanggal 17 September 2026. Rincian teknis keempatnya ada di
`ais docs/pos/131-empat-keluhan-produksi-kantin-17-09-2026.md` (SVN r91690).

An Nahl adalah pelapor keempat keluhan tersebut, jadi dua di antaranya —
Mutasi Voucher — berada di sisi server dan **tidak** ikut dalam APK ini.

## Yang ikut di APK ini

- **Rincian Produk: kolom Bruto dan Diskon.** Kolom Total selama ini bernilai
  neto (server menyimpan `total = harga * qty - diskon`), sementara harga di
  sebelahnya bruto. Karena itu "Roti bakar 7.000 x 4 = 28.000 tapi jadi 24.000"
  dan "Mangga 21.000 tapi totalnya 19.000" tidak bisa dijelaskan dari apa pun
  yang tampil di layar. Bruto dipulihkan dari `total + diskon` per baris, bukan
  dari perkalian ulang `harga * qty` yang akan meleset pada baris berharga
  khusus. Selisih 6.000 terhadap rekap Excel kantin (1.629.000 vs 1.623.000)
  adalah 4.000 + 2.000 diskon yang tidak pernah ditampilkan — bukan uang hilang,
  dan setoran tidak berubah.
- **Tombol Lunasi pada Mutasi Piutang.** Menjawab "kalau di entry pelunasan ini
  kita harus manual yaa". Baris yang menambah piutang kini punya tombol yang
  membuka lembar pelunasan sudah terisi nominal dan keterangannya, masih dapat
  disunting, dan tetap tunduk pada izin `bolehEntryPelunasanPiutang`.

## Yang datang lewat server (SVN r91690, sudah ter-deploy)

- **Keterangan Mutasi Voucher memakai nama produk.** Sebelumnya menampilkan kode
  nota, yang tidak berarti bagi wali santri. Sekarang dirakit dari nama produk
  pada nota itu (`LEFT JOIN LATERAL` + `string_agg`); kode nota tidak dibuang,
  hanya dipindah ke dalam kurung agar kasir tetap bisa menelusuri. Qty ditempel
  hanya bila lebih dari 1.
- **Unduh Word pada Mutasi Voucher.** Rincian mutasi plus Total Masuk, Total
  Keluar, dan Sisa Saldo. Berkasnya `.doc` yang dapat disunting di Word, dan
  membaca sumber data yang sama dengan cetak PDF agar keduanya tidak pernah
  bercerita berbeda.

Keduanya sudah **ter-deploy pada 18 September 2026** dan aktif tanpa perlu
memasang APK. Pemasangan APK tetap diperlukan untuk kolom Bruto/Diskon dan
tombol Lunasi.

## Yang sengaja tidak dijanjikan

Pelunasan tetap tercatat pada **saldo** anggota, bukan dialokasikan ke satu nota:
aksi `hutang_bayar_simpan` hanya menerima `id_member`, `nominal`, `keterangan`,
`waktu`. Tombol Lunasi mempercepat pengisian, bukan alokasi per transaksi.
Alokasi per nota membutuhkan perubahan skema dan keputusan akuntansi tersendiri.

## Verifikasi

- `flutter test`: **861 lulus, 0 gagal.**
- `dart analyze` pada berkas yang disentuh: bersih.
- Runner klien (`alat/uji-klien.py`): ANALISIS DAN UJI LULUS.
- SQL Mutasi Voucher dirakit dari JSP lalu di-`EXPLAIN` pada klaster PostgreSQL
  sekali pakai (`initdb -A trust`, port sendiri, dibuang sesudahnya) — tanpa
  menyentuh service terpasang dan tanpa kredensial produksi.
- Sintaks JSP diperiksa `alat/cek-sintaks-jsp.py`: bersih.
- Harness UAT Java: **19 dari 20 lulus.** Yang ke-20
  (`RestaurantNetworkPostingIntegrationUat`) menuntut database `*_uat` dengan
  schema tenant restoran yang sudah di-seed — jalur AB Chicken yang tertahan
  menunggu sesi admin platform, tidak berhubungan dengan rilis ini.
- Delapan penjaga `alat/`: bersih, sesudah dua temuan ditangani pada sesi yang
  sama (SVN r91741 dan r91743).
- Dua uji kontrak-sumber baru (10 asersi) dibuktikan **bisa gagal** dengan cacat
  nyata sebelum diterima — bukan sekadar hijau.

## Batasan paket

- **Paket UAT internal.** APK bertanda tangan **debug** (`CN=Android Debug`),
  sesuai praktik paket UAT di repo ini. Distribusi produksi tetap menuntut
  sertifikat resmi organisasi.
- Belum diuji pada perangkat nyata dalam rilis ini; pengujian yang dilaporkan di
  atas adalah uji otomatis dan analisis statis.

## Artefak

| Berkas | Ukuran | SHA-256 |
|---|---|---|
| `app-nahl-release.apk` | 191.531.061 bytes | `8f0b3de2165b30b0e99de50d21b8a93855b1cf58ef5d76125576d310f8151b57` |

`package=id.zishof.ebisnis.nahl`, `versionName=1.34.41`, `versionCode=204`,
label `TokoQu Al-Bahjah An Nahl`.

Build 204 dipilih karena rilis terbit sudah memakai 201/202/203 sementara
pubspec tertinggal di 198; versionCode yang lebih rendah dari paket terpasang
membuat Android menolak pemasangan sebagai pembaruan.
