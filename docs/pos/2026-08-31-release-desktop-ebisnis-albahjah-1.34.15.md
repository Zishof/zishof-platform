# Rilis POS Desktop 1.34.15 — eBisnis dan Al-Bahjah

Tanggal: 31 Agustus 2026  
Status: dibangun, diverifikasi, dan dipublikasikan dari satu commit sumber

## Perubahan utama

- Retur Pembelian kini dapat dimulai dari faktur kulakan asal.
- Satu permintaan retur dapat memuat beberapa item dari faktur yang sama; kasir memilih item, jumlah, dan alasan per baris.
- Jumlah retur dibatasi maksimal sebesar jumlah pada faktur asal.
- Faktur asal dan supplier dibawa ke payload retur untuk menjaga keterlacakan.
- Riwayat retur menampilkan referensi faktur asal serta menyediakan pratinjau dan cetak dokumen retur dalam format A4 potret.
- Pencarian produk manual tetap tersedia sebagai jalur cadangan.
- Simpan/hapus tetap memakai kontrak local-first: perubahan disimpan di perangkat dan masuk antrean sinkronisasi ketika server belum dapat dihubungi.
- Penyempurnaan yang sudah ada di working tree ikut dirilis: metode harga paket/kelipatan wajib dan label satuan pembelian pada PR/PO.

## Bukti pengujian sebelum build

- `flutter analyze --no-pub` pada lima berkas yang berubah: **No issues found**.
- `flutter test --no-pub test/master_offline_kontrak_test.dart`: **23 lulus**.
- `flutter test --no-pub`: **575 lulus**.
- Pemeriksaan whitespace Git: tidak ada kesalahan.

## Artefak

- Commit sumber: `572f008b052b5b72d8e235904c44961562e02e51`.
- eBisnis Desktop: `eBisnis-Setup-1.34.15.exe` (85.841.896 byte).
  - SHA-256: `d37feac970a0c80449f93248c7d79c5b9a68e01e27fb6a5bb39e133b86326c00`.
  - Unduh: https://github.com/Zishof/zishof-platform/releases/download/v1.34.15/eBisnis-Setup-1.34.15.exe
- Al-Bahjah POS Desktop: `Al-Bahjah-POS-Setup-1.34.15.exe` (85.902.468 byte).
  - SHA-256: `31d9d0508e137d227f93ff869203f9b02743610537b1f1c08a865b07c2b1084f`.
  - Unduh: https://github.com/Zishof/zishof-platform/releases/download/v1.34.15/Al-Bahjah-POS-Setup-1.34.15.exe

Kedua installer dibangun oleh skrip multi-varian dalam satu proses selama sekitar 4,5 menit. Verifikasi packaging berhasil. Installer Windows belum ditandatangani sertifikat publik dan ditandai `UNSIGNED/UAT` oleh pipeline; pengguna Windows mungkin menerima peringatan SmartScreen.
