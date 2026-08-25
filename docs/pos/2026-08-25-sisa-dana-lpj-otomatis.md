# Sisa Dana Pertanggungjawaban Otomatis

## Perubahan

- Kolom **Dikembalikan (sisa dana)** pada form Pertanggungjawaban Uang Muka dan Pertanggungjawaban Kas Besar tidak lagi dapat diisi manual.
- Nilainya selalu dihitung dengan rumus: **nilai sumber dana - total Rincian Realisasi (LPJ)**.
- Perhitungan tampilan diperbarui saat Uang Muka/Kas Besar dipilih serta saat rincian ditambah, diubah, atau dihapus.
- Backend menghitung ulang dari nilai sumber dana dan rincian yang tersimpan sehingga nilai kiriman klien tidak dipercaya.
- Tanggal stor tetap wajib bila sisa dana lebih dari Rp0,10.

## Skenario UAT

1. Uang muka Rp100.000 dan LPJ Rp100.000 menghasilkan sisa Rp0.
2. Uang muka Rp100.000 dan LPJ Rp60.000 menghasilkan sisa Rp40.000.
3. Mengubah atau menghapus rincian langsung memperbarui sisa dana.
4. Mengganti pilihan uang muka langsung memperbarui sisa dana.
5. LPJ yang melebihi uang muka tetap ditolak oleh server.
6. Nilai `dikembalikan` palsu dari klien diabaikan dan dihitung ulang oleh server.
7. Ulangi skenario yang sama pada Pertanggungjawaban Kas Besar; hasil tampilan dan nilai database harus identik.
