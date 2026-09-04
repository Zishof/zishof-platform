# Standar tampilan profesional user manual bergambar

Standar ini berlaku untuk seluruh user manual dan dokumen UAT bergambar yang diterbitkan
setelah 4 September 2026.

## Aturan tampilan

- Judul pada halaman penjelasan hanya memakai judul proses atau judul tangkapan layar.
- Jangan menampilkan hitungan panjang teks, target panjang penjelasan, atau metrik internal
  penyusunan dokumen kepada pembaca.
- Jangan memakai label proses penyusunan, label jumlah kata, atau status pemeriksaan panjang
  teks pada judul, caption, tabel, header, footer, dan metadata publik.
- Caption gambar menjelaskan proses, kondisi data, periode, dan hasil yang terlihat.
- Penjelasan tetap harus rinci, operasional, mudah diikuti, serta mencakup tujuan, aktor,
  prasyarat, langkah kerja, sumber data, relasi akun, kontrol, hasil UAT, penanganan masalah,
  dan keterlacakan audit.
- Use case, flowchart, dan aliran data/ERD ditempatkan setelah penjelasan proses yang
  bersangkutan dan menggunakan istilah bisnis yang konsisten dengan layar aplikasi.

## Kontrol penerbitan

Generator boleh memeriksa tingkat kedalaman penjelasan secara internal, tetapi hasil hitungan
tersebut tidak boleh dicetak di dokumen pengguna. Sebelum Word dan PDF diterbitkan, lakukan
pemeriksaan teks untuk memastikan label internal tidak ikut tampil, lalu render seluruh halaman
untuk memeriksa judul, gambar, tabel, diagram, page break, header, dan footer.

Jika dokumen lama diterbitkan ulang, aturan ini diterapkan saat penggantian artefak. Nama berkas
dan versi boleh dipertahankan ketika revisi hanya memperbaiki penyajian tanpa mengubah hasil UAT.
