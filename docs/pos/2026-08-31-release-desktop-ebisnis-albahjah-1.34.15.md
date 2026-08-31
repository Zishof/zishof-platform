# Rilis POS Desktop 1.34.15 — eBisnis dan Al-Bahjah

Tanggal: 31 Agustus 2026  
Status: siap dibangun dan dipublikasikan dari satu commit sumber

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

Artefak final, SHA-256, commit sumber, dan tautan unduh GitHub dicatat setelah build dan unggahan selesai.
