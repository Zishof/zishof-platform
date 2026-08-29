# Rilis Desktop POS 1.34.04 — eBisnis, Al-Bahjah, dan Nahl

Tanggal: 29 Agustus 2026

Versi aplikasi: `1.34.04+162`

Varian: `ebisnis`, `albahjah`, `nahl`

Tag GitHub: `v1.34.04-build162`

## Ringkasan

- Bulk Entry Faktur Kulakan mengisi produk existing setelah pengguna memilih hasil pencarian berdasarkan nama, kode, atau barcode.
- Produk master lama dicari secara persis dari cache lokal ketika server tidak dapat dijangkau.
- Gangguan server/cache tidak lagi otomatis mengubah produk existing menjadi produk baru; posting ditahan sampai verifikasi berhasil.
- Detail faktur historis tetap menampilkan ringkasan, status data, langkah pemulihan, dan informasi teknis ketika rincian server belum dapat dimuat.
- Setelah instalasi baru atau pembaruan versi, aplikasi menawarkan sinkronisasi seluruh tabel yang didukung ketika koneksi tersedia.
- Ketiga installer dibangun berurutan oleh satu skrip dan satu snapshot source agar implementasi antartoko tetap konsisten.

## UAT dan kompilasi

- Enam pengujian terarah Kulakan lulus.
- Seluruh `514` pengujian aplikasi eBisnis/Al-Bahjah/Nahl lulus.
- Pengujian paket lokal `core_auth`, `core_billing`, `core_db`, `core_device`, `core_hw`, `core_notif`, `core_sync`, `core_ui`, dan `core_update` lulus.
- Seluruh `18` pengujian aplikasi eCanteen lulus.
- Analisis terarah pada modul Kulakan lulus tanpa temuan.
- Analisis penuh masih melaporkan `53` lint lama di modul lain: `52` saran gaya/depresiasi dan `1` cast tidak perlu. Tidak ada error kompilasi dan ketiga build Windows release berhasil.
- AOT hasil build terverifikasi memuat kontrak penahanan posting saat produk belum berhasil diverifikasi.

## Artefak

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.04.exe` | 85.583.422 byte | `A9EF1ABDEDA6AEA8E900C5D4E984F124E2A956D2D9D970BED8615DD62B7673DD` |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.04.exe` | 85.642.122 byte | `3BEDDAB768FC7FD8CB39515ADAF068DA14698E30755913412257C86D7F027B33` |
| Nahl | `FF-Fajrul-Falah-Mart-Setup-1.34.04.exe` | 85.589.463 byte | `BAFF58079C1CC188C44BF475FB72460AAFA4AE0E0AF9A63A20FB0353A6959CA7` |

Metadata executable ketiga varian memakai versi `1.34.04+162`. Seluruh installer berstatus Authenticode `NotSigned`; artefak ini untuk distribusi UAT/internal. Pengguna wajib mencocokkan nama file dan SHA-256 sebelum memasang.

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.04/`

## UAT pengguna

1. Pasang installer yang sesuai toko, lalu pilih **Sinkronkan seluruh tabel** ketika ditawarkan.
2. Buka **Kulakan → Bulk Entry Faktur**.
3. Ketik sebagian nama produk, lalu klik produk yang benar pada daftar saran. Kolom kode/barcode, nama produk, kategori, dan status harus menjadi data produk existing.
4. Ulangi menggunakan kode internal dan barcode fisik.
5. Jika verifikasi server/cache belum tersedia, jangan posting. Tekan **Sinkronkan**, kemudian **Cek Produk Existing** kembali.
6. Buka faktur historis. Jika rincian belum dapat dimuat, pastikan ringkasan faktur tetap tampil dan kirim nomor faktur beserta **Detail Error** kepada admin; jangan membuat faktur pengganti.

## Rollback

- Hentikan rollout bila produk pilihan tetap dianggap baru, produk yang salah terpilih, atau detail faktur berubah/hilang.
- Kembalikan desktop ke `1.34.03+161`.
- Data faktur dan produk tidak boleh dihapus atau dibuat ulang sebagai bagian rollback; lakukan sinkronisasi dan kirim Detail Error untuk pemeriksaan server.
