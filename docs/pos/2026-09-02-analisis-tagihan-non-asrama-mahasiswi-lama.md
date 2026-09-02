# Analisis Tagihan Non-Asrama Mahasiswi Lama

Tanggal: 2 September 2026

Tangkapan layar Mutiara Rahma Humairah (NIM `2022010066`) memperlihatkan item
Asrama Rp2.800.000 per bulan, sedangkan kebutuhan bisnisnya adalah SPP
Rp1.500.000 per bulan tanpa Asrama.

Penelusuran source server ZK menunjukkan ini bukan kesalahan aritmetika. Mesin
memilih satu `SettingBiaya` dari profil mahasiswa, kemudian mengambil
`DetailBiaya` dan `PengaturanPembayaranBulanan`. Kode tidak menyimpulkan status
non-asrama dari istilah "mahasiswi lama" atau nama item biaya. Tanpa routing per
NIM, mahasiswa tetap mewarisi setting cohort Asrama.

Kode server terbaru menyediakan pembatasan setting untuk mahasiswa terpilih,
pengecualian NIM, dan prioritas melalui `SettingBiayaMahasiswaSelector`.
Implementasi memerlukan build SVN `r82956` atau lebih baru serta migrasi
`migrasi_relasi_prioritas_setting_biaya_20260902.sql`.

Daftar lampiran berisi 18 nama tetapi tidak mencantumkan Mutiara. Perubahan
produksi harus menunggu pemetaan seluruh nama ke NIM dan konfirmasi apakah
Mutiara adalah orang ke-19. Setelah setting Non Asrama berisi SPP Rp1.500.000
dan NIM tersebut dikecualikan dari setting Asrama, tagihan wajib dimuat ulang
untuk membersihkan cache. Pembayaran terposting atau VA aktif harus
direkonsiliasi, bukan dihapus langsung.

Catatan kanonis dan draf balasan WhatsApp terdapat pada working copy SVN:
`docs/pos/76-analisis-tagihan-non-asrama-mahasiswi-lama.md`.
