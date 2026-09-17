# Al-Bahjah POS 1.34.41 (build 204) — UAT

Rilis UAT yang menjawab keluhan produksi grup WhatsApp Al-Bahjah An Nahl
tanggal 17 September 2026. Rincian teknis keempat keluhan ada di
`ais docs/pos/131-empat-keluhan-produksi-kantin-17-09-2026.md` (SVN r91690).

## Yang ikut di APK ini

- **Rincian Produk: kolom Bruto dan Diskon.** Kolom Total selama ini bernilai
  neto (server menyimpan `total = harga * qty - diskon`), sementara harga di
  sebelahnya bruto — sehingga "7.000 x 4 = 28.000 tapi tercatat 24.000" tidak
  bisa dijelaskan dari apa pun yang tampil. Bruto dipulihkan dari
  `total + diskon` per baris, bukan dari perkalian ulang `harga * qty` yang akan
  meleset pada baris berharga khusus. Selisih 6.000 terhadap rekap Excel kantin
  (1.629.000 vs 1.623.000) adalah jumlah diskon yang tidak pernah ditampilkan.
- **Tombol Lunasi pada Mutasi Piutang.** Baris yang menambah piutang kini punya
  tombol yang membuka lembar pelunasan sudah terisi nominal dan keterangannya,
  masih dapat disunting, dan tetap tunduk pada izin `bolehEntryPelunasanPiutang`.

## Yang TIDAK ikut di APK ini

Perbaikan layar **Mutasi Voucher** (keterangan memakai nama produk, dan tombol
unduh Word) berada di sisi server — `_mutasi_tabungan.jsp`, SVN r91690. Keduanya
baru terlihat setelah WAR/server diperbarui. Deploy server bukan bagian dari
paket ini.

## Yang sengaja tidak dijanjikan

Pelunasan tetap tercatat pada **saldo** anggota, bukan dialokasikan ke satu nota:
aksi `hutang_bayar_simpan` hanya menerima `id_member`, `nominal`, `keterangan`,
`waktu`. Tombol Lunasi mempercepat pengisian, bukan alokasi per transaksi.
Alokasi per nota membutuhkan perubahan skema dan keputusan akuntansi tersendiri.

## Verifikasi

- `flutter test`: **861 lulus, 0 gagal.**
- `dart analyze` pada berkas yang disentuh: bersih.
- Runner klien (`alat/uji-klien.py`): ANALISIS DAN UJI LULUS.
- Harness UAT Java: **19 dari 20 lulus.** Yang ke-20
  (`RestaurantNetworkPostingIntegrationUat`) menuntut database `*_uat` dengan
  schema tenant restoran yang sudah di-seed (`TenantSchemaDdlDump` + profil seed)
  — jalur AB Chicken yang tertahan menunggu sesi admin platform, tidak
  berhubungan dengan rilis ini.
- Delapan penjaga `alat/`: bersih, sesudah dua temuan ditangani pada sesi yang
  sama (lihat "Temuan UAT" di bawah).
- Dua uji kontrak-sumber baru (10 asersi) dibuktikan **bisa gagal** dengan cacat
  nyata sebelum diterima — bukan sekadar hijau.

## Temuan UAT yang ikut diperbaiki

- `gerbang-peran-tanpa-katalog.py` menemukan `apotik_batch` beraksi `update`
  tetapi berada di luar `KUNCI_CRUD`, sehingga `bolehAksi` mengembalikan
  `aksiLegacy=true` untuk setiap peran: gerbangnya tidak pernah menggigit dan
  pesan penolakannya mustahil muncul. Diperbaiki di SVN r91741. Varian albahjah
  tidak terpengaruh (modul apotik entrypoint terpisah).
- `payload-tanpa-pembaca.py` menuduh `_disimpanPada` — stempel cache lokal —
  sebagai kunci payload tanpa pembaca. Penjaganya yang keliru, bukan kodenya;
  dipersempit di SVN r91743.

## Batasan paket

- **Paket UAT internal.** APK bertanda tangan **debug**
  (`CN=Android Debug`), sesuai praktik paket UAT di repo ini. Distribusi
  produksi tetap menuntut sertifikat resmi organisasi.
- Belum diuji pada perangkat nyata dalam rilis ini; pengujian yang dilaporkan di
  atas adalah uji otomatis dan analisis statis.

## Artefak

| Berkas | Ukuran | SHA-256 |
|---|---|---|
| `app-albahjah-release.apk` | 190.997.413 bytes | `f44d2840ac00a90848c8f765edb2d10939e4a084c8b1937830382e6a0c331833` |

`package=id.zishof.ebisnis.albahjah`, `versionName=1.34.41`,
`versionCode=204`, label `Al-Bahjah POS`.

Build 204 dipilih karena rilis terbit sudah memakai 201/202/203 sementara
pubspec tertinggal di 198; versionCode yang lebih rendah dari paket terpasang
membuat Android menolak pemasangan sebagai pembaruan.
