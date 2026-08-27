# Matriks Paritas Platform Fase 12

Tanggal: 26 Agustus 2026

| Kapabilitas/aturan | Desktop | Android | JSP | ZK | Status fondasi |
|---|---:|---:|---:|---:|---|
| Navigasi responsif | Ya | Ya | Ya | Ya | Terdefinisi |
| Work queue | Ya | Ya | Ya | Ya | Terdefinisi |
| Menu dan aksi kanonis | Ya | Ya | Ya | Ya | Teruji |
| Admin bypass terkontrol | Ya | Ya | Ya | Ya | Teruji |
| Izin non-admin dari `TbmroleAction` | Ya | Ya | Ya | Ya | Teruji |
| Aksi tanpa izin hidden + disabled | Ya | Ya | Ya | Ya | Teruji |
| Paging default 10, maksimum 100 | Ya | Ya | Ya | Ya | Teruji |
| Idempotency key untuk write | Ya | Ya | Ya | Ya | Teruji |
| Optimistic version untuk update | Ya | Ya | Ya | Ya | Teruji |
| Error contract `EBISNIS_ERROR_V1` | Ya | Ya | Ya | Ya | Teruji |
| Ekspor PDF | Ya | Ya | Ya | Ya | Terdefinisi |
| Ekspor Excel | Ya | Ya | Ya | Ya | Terdefinisi |
| Cetak | Ya | Ya | Ya | Ya | Terdefinisi |
| Bantuan kontekstual | Ya | Ya | Ya | Ya | Terdefinisi |
| Scan barcode | Ya | Ya | Tidak/N/A | Tidak/N/A | Teruji |
| Scan QR | Ya | Ya | Tidak/N/A | Tidak/N/A | Teruji |
| Antrean offline | Ya | Ya | Tidak/N/A | Tidak/N/A | Teruji |

## Golden flow yang wajib diuji pada adapter layar

| Skenario | Hasil yang diwajibkan |
|---|---|
| View daftar | Filter dan urutan stabil; halaman awal 10 baris |
| Create | Memerlukan idempotency key; retry tidak membuat duplikat |
| Edit draft | Memerlukan versi optimistik; versi basi menghasilkan conflict |
| Admin | Semua menu yang terdaftar dapat dilihat dan diaudit |
| Non-admin | Hanya aksi dengan `TbmroleAction` aktif yang terlihat dan dapat dipanggil |
| Export | PDF/Excel berasal dari filter dan snapshot data yang sama dengan layar |
| Error | Struktur dan arti pesan sama pada empat platform |
| Offline Desktop/Android | Masuk antrean lokal dan dikirim ulang idempoten saat online |

## Sign-off

| Peran | Status | Catatan |
|---|---|---|
| Engineering | Lulus fondasi teknis | Java: 76 pemeriksaan; Flutter: 3 kelompok tes |
| QA | Pending | Menunggu adapter layar dan UAT end-to-end |
| Product Owner | Pending | Menunggu verifikasi UX dan kesetaraan proses bisnis |

Dokumen ini tidak menyatakan seluruh UI produksi telah selesai. Status “Ya” berarti kapabilitas merupakan bagian kontrak platform; implementasi layar harus dibuktikan lagi melalui golden flow dan sign-off.
