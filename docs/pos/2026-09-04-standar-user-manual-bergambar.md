# Baseline wajib user manual dan UAT bergambar

**Status: CATATAN PENTING / BASELINE WAJIB.** Standar ini berlaku untuk seluruh user manual
dan dokumen UAT bergambar yang diterbitkan atau diterbitkan ulang setelah 4 September 2026.

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
- Panjang penjelasan mengikuti kebutuhan layar, bukan kuota. Dilarang menambah paragraf umum
  atau mengulang isi layar lain hanya untuk membuat bagian terlihat panjang.
- Setiap penjelasan harus menyebut unsur yang benar-benar terlihat atau dibuktikan oleh layar,
  misalnya nama menu, filter, periode, status, jumlah transaksi, nilai, akun, tombol, halaman,
  posisi scroll, hasil validasi, atau tindakan pengguna yang relevan.
- Dua tangkapan layar yang berbeda tidak boleh memakai isi penjelasan yang sama. Struktur judul
  boleh konsisten, tetapi konteks, cara membaca, tindakan, makna akuntansi, dan hasil UAT harus
  spesifik terhadap bukti pada layar tersebut.
- Layar daftar transaksi, pratinjau posting, buku besar, dan laporan tidak boleh diterbitkan dalam
  keadaan kosong apabila tujuan UAT adalah membuktikan alur data. Jalankan filter, tombol
  **Pratinjau**, **Muat ulang**, atau **Tampilkan** terlebih dahulu dan tunggu pemuatan selesai.
- Untuk UAT berbasis volume, siapkan sedikitnya 100 record pada setiap sumber transaksi utama.
  Jika aplikasi secara sah mengagregasi record—misalnya HPP merangkum banyak nota per produk—
  screenshot dan penjelasan harus menyebut jumlah transaksi sumber, kuantitas, jumlah agregat,
  dan nilai agar layar tidak disalahartikan sebagai kekurangan data.
- Bukti end-to-end harus dibagi menjadi praposting, hasil posting, dan pascaposting. Screenshot
  praposting memperlihatkan data serta akun; screenshot pascaposting membuktikan antrean bersih
  dan laporan telah berubah. Dilarang memakai keadaan kosong pascaposting sebagai satu-satunya
  bukti menu posting.
- Tabel laporan keuangan dan laporan lain harus memanfaatkan lebar area kerja sampai sisi kanan.
  Kolom uraian diberi ruang lebih besar, kolom angka tetap rata kanan, dan area angka yang dapat
  diklik harus memenuhi lebar sel. Screenshot laporan wajib diambil setelah tata letak penuh ini
  aktif agar keterangan maupun nilai tidak menumpuk di sisi kiri layar.
- Use case, flowchart, dan aliran data/ERD ditempatkan setelah penjelasan proses yang
  bersangkutan dan menggunakan istilah bisnis yang konsisten dengan layar aplikasi.
- Konektor diagram harus memakai ruang kosong di antara node. Garis dan kepala panah tidak
  boleh melintasi kotak proses, teks, kepala panah lain, atau batas node tujuan.

## Kontrol penerbitan

Generator harus memeriksa cakupan seluruh layar, paragraf kosong, duplikasi, dan kemiripan isi.
Pemeriksaan tidak boleh memaksa panjang tertentu dan metrik internal tidak boleh dicetak di
dokumen pengguna. Sebelum Word dan PDF diterbitkan, render seluruh halaman untuk memeriksa
judul, gambar, tabel, diagram, arah dan jarak konektor, page break, header, dan footer.

Jika dokumen lama diterbitkan ulang, aturan ini diterapkan saat penggantian artefak. Nama berkas
dan versi boleh dipertahankan ketika revisi hanya memperbaiki penyajian tanpa mengubah hasil UAT.
