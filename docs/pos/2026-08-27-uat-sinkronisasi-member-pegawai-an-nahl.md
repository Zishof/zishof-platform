# UAT sinkronisasi Member Pegawai An-Nahl

Tanggal UAT: 27 Agustus 2026  
Server: `https://an-nahl.santri.info/nahl/Api_eBisnis`  
Data uji: sesi admin An-Nahl yang sudah tersimpan pada perangkat UAT. Token dan
data autentikasi tidak dicatat dalam dokumen ini.

## Gejala

Menu **Pelanggan > Data Member Baru** hanya menampilkan satu member bertipe
Pegawai, sedangkan **Kepegawaian > Pegawai** berisi banyak data aktif.

## Bukti UAT produksi sebelum perbaikan

| Pemeriksaan | Hasil |
|---|---|
| `anggota_list`, halaman 1 | `status=success`, `total=1` |
| `sinkron_referensi`, tipe `koperasi` | `status=success`, jumlah Koperasi `0` |

Data Pegawai tidak otomatis sama dengan data Member. Pegawai baru menjadi
Member setelah admin/supervisor menjalankan **Pelanggan > Sinkronisasi
Siswa/Mahasiswa/Sivitas > Sinkronkan Semua** dan memilih Koperasi tujuan.
Karena master Koperasi produksi kosong, proses tersebut tidak mempunyai tujuan
dan tidak dapat dijalankan.

Respons kosong juga membuktikan backend produksi belum memuat perbaikan SVN
r78394: pada revisi tersebut, permintaan referensi Koperasi oleh
admin/supervisor akan membuat satu Koperasi utama bila tabelnya masih kosong.

## Perbaikan tambahan hasil audit kode

Batch Pegawai lama memilih kandidat memakai satu Hibernate session, tetapi
helper penyimpan membuka session lain dan menerima objek Koperasi dari session
pertama. Kegagalan setiap baris ditangkap dan hanya dijumlahkan sebagai
`gagal`, sehingga pengguna tidak memahami penyebabnya.

Perbaikannya:

1. kandidat diproses berdasarkan `pegawai.id`, sehingga kode kosong maupun kode
   ganda tidak menghilangkan kandidat karena `GROUP BY mycode`;
2. setiap penyimpanan memuat Pegawai dan Koperasi dalam session yang sama;
3. member lama dengan kode/NIK sama digunakan kembali dan dihubungkan ke
   Pegawai, bukan diduplikasi;
4. hasil menyebut jumlah berhasil, gagal, Pegawai nonaktif, dan Pegawai yang
   memang dialihkan melalui jalur Dosen/Guru;
5. layar POS menampilkan penjelasan server dan langkah berikutnya, bukan hanya
   tiga angka tanpa arti.

## Skenario UAT sesudah deployment

1. Deploy backend SVN yang memuat r78394 dan perbaikan batch Pegawai terbaru.
2. Masuk sebagai admin/supervisor An-Nahl.
3. Buka **Pelanggan > Sinkronisasi Siswa/Mahasiswa/Sivitas**.
4. Pastikan Koperasi terpilih otomatis; bila referensi masih kosong, hentikan
   UAT dan periksa revisi backend aktif.
5. Tekan **Sinkronkan Semua** satu kali.
6. Pada baris Pegawai, pastikan `Total = Berhasil + Gagal`, dan baca keterangan
   jumlah yang diproses lewat Dosen/Guru atau dilewati karena nonaktif.
7. Jika `Gagal > 0`, jangan menekan Sinkronkan berulang. Buka **Log Error** dan
   kirim referensi `sinkronPegawai` kepada admin.
8. Jika berhasil, kembali ke **Data Member Baru**, tekan **Unduh Offline**, lalu
   cari `AB-TNG 0030`, `AN-PEG-0018`, dan `AN-PEG-0063` sebagai sampel.

## Kriteria lulus

- Master Koperasi tersedia dan dapat dipilih.
- Pegawai aktif umum dibuat/diperbarui sebagai Member bertipe Pegawai.
- Pegawai yang mempunyai relasi Dosen/Guru tidak hilang: mereka muncul melalui
  hasil jalur Dosen/Guru dan tidak diduplikasi sebagai Pegawai umum.
- Pegawai nonaktif tidak dibuat menjadi Member dan jumlahnya dijelaskan.
- Menjalankan sinkronisasi ulang tidak membuat duplikat.
- Setelah **Unduh Offline**, jumlah dan pencarian Member pada perangkat sesuai
  data server.
