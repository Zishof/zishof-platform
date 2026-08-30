# Rilis Android POS 1.34.10 — TokoQu Al-Bahjah An-Nahl

Tanggal: 30 Agustus 2026  
Versi aplikasi: `1.34.10+172`  
Varian: `nahl`  
Platform: Android  
Tag GitHub: `v1.34.10`  
Prasyarat backend stok opname: SVN `r78605`

## Ruang lingkup

- Hanya varian Android `nahl` yang dibangun dan dipublikasikan.
- APK memakai source tree dan kontrak local-first yang sama dengan POS Desktop `1.34.10`.
- Perbaikan sinkronisasi stok opname, pembaruan cache stok, dan pengiriman ulang antrean lokal ikut terkompilasi.
- APK ini ditandatangani menggunakan sertifikat Android Debug dan hanya ditujukan untuk distribusi internal/UAT, bukan Google Play produksi.

## Artefak

| Artefak | Ukuran | SHA-256 |
|---|---:|---|
| `app-nahl-release.apk` | 188.937.396 byte | `EAB9706717EE9F621ED8700AD2469055C4B06AEAA6A2D2AE36B0351E0CA56F6D` |

Signing yang diverifikasi:

`Signer #1 certificate DN: C=US, O=Android, CN=Android Debug`

## UAT pemasangan

1. Pastikan backend SVN `r78605` sudah aktif sebelum menguji sinkronisasi stok opname.
2. Jangan hapus data aplikasi lama atau antrean transaksi pending.
3. Android dapat menolak pembaruan langsung bila aplikasi lama ditandatangani dengan sertifikat berbeda. Bila terjadi, ekspor/periksa transaksi pending terlebih dahulu; jangan menghapus aplikasi tanpa memastikan data lokal aman.
4. Setelah pemasangan, pastikan versi aplikasi menunjukkan `1.34.10`.
5. Uji login, Produk, Kasir/POS, transaksi local-first, dan satu stok opname pada produk uji.
6. Bandingkan stok dengan perangkat Desktop/kasir lain setelah 15–30 detik saat seluruh perangkat online.

## Batasan signing

- APK debug/UAT tidak boleh dipromosikan sebagai build produksi Play Store.
- Publikasi produksi berikutnya harus memakai keystore organisasi yang tetap agar peningkatan versi dapat dipasang tanpa uninstall.
