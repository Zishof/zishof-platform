# Popup Analisis Pintar KRS

Tanggal: 3 September 2026

## Tujuan

Ringkasan pada kolom **Keterangan** KRS sebelumnya hanya menampilkan beberapa
kalimat seperti jumlah perkuliahan yang disetujui dan yang belum dinilai.
Ringkasan tersebut kini menjadi kartu yang jelas dapat diklik. Klik membuka
popup analisis rinci tanpa mengubah data akademik.

## Tampilan ringkasan

- Ringkasan dibungkus kartu biru yang tetap menampilkan informasi lama.
- Di bawah ringkasan terdapat label **Analisis pintar & grafik — klik**.
- Cursor dan tooltip menjelaskan bahwa kartu dapat dibuka.
- Listener dipasang sekali. Refresh/timer hanya memperbarui konteks pada
  atribut komponen sehingga tidak terjadi listener ganda atau memakai entity
  dari render lama.

## Isi popup

Popup **Analisis Pintar KRS Mahasiswa** berisi:

1. identitas mahasiswa dan konteks semester/tahap/SP/remedial;
2. kesimpulan utama yang diturunkan dari status rincian KRS;
3. kartu indikator jumlah mata kuliah, persetujuan, penilaian, dan SKS;
4. grafik persetujuan: disetujui, menunggu, dan status nonstandar;
5. grafik penilaian: sudah dan belum dinilai di antara mata kuliah disetujui;
6. grafik distribusi SKS berdasarkan status persetujuan;
7. IPS, IPK, SKS semester, SKS kumulatif, dan catatan KRS;
8. temuan analitis dan rekomendasi tindak lanjut;
9. tabel setiap mata kuliah: kode, nama, SKS, persetujuan, dan penilaian;
10. penjelasan cara sistem menghitung hasil agar analisis dapat diaudit.

Analisis bersifat deterministik/explainable. Istilah "pintar" tidak berarti
data dikirim ke layanan AI eksternal; kesimpulan dibuat dari aturan domain dan
data KRS yang tersedia pada server.

## Aturan analisis

- Persetujuan memakai `Detailperkuliahan.persetujuan`.
- Nilai dianggap terisi hanya bila mata kuliah disetujui dan `totalNilai >= 0.1`,
  sama dengan aturan ringkasan KRS yang sudah ada.
- SKS grafik dihitung dari mata kuliah setiap detail KRS.
- Angka rekap `KrsMahasiswa` ditampilkan terpisah agar sumber data dapat
  dibandingkan, bukan diam-diam dicampur.
- Kondisi tanpa KRS, menunggu persetujuan, semua belum dinilai, sebagian belum
  dinilai, semua sudah dinilai, dan status nonstandar mempunyai kesimpulan dan
  rekomendasi berbeda.

## Cakupan pola

Helper bersama diterapkan pada 20 jalur tampilan interaktif, mencakup:

- daftar Mahasiswa dan Alumni;
- KRS Mahasiswa, KRS Kurikulum, paket, nonpaket, serta helper KRS umum;
- Nilai, Penilaian, Ujian, dan Absensi;
- Monitor KRS, dashboard KRS, detail dosen PA, dan Studi Mahasiswa;
- profil Mahasiswa, renderer data KRS, dan detail kalender mingguan.

Keluaran ekspor/snapshot dan konten kalender bulanan gabungan tetap berupa
teks. Keduanya tidak mempunyai komponen ringkasan mandiri untuk menerima event
popup, sehingga tidak diberi affordance klik palsu.

## Performa dan keamanan

- Renderer tetap menyusun ringkasan yang sama seperti sebelumnya.
- Pengambilan rincian dan penyusunan grafik baru berjalan setelah pengguna
  mengklik kartu.
- Resolver memakai cache entity KRS yang telah digunakan `KrsDetailHelper`;
  tidak menambahkan write database.
- Seluruh nilai dinamis pada popup di-escape sebelum dimasukkan ke HTML.
- Popup secara eksplisit read-only: tidak mengubah KRS, persetujuan, nilai,
  maupun rekap akademik.

## Verifikasi

- 22 pasangan file pada `src/main/java` dan `src/main/src`: SHA-256 identik.
- Bytecode helper analisis dan popup ditemukan pada hasil build.
- `mvn -DskipTests clean compile`: **BUILD SUCCESS** (7.512 source Java).
- Revisi kode utama: SVN r83819, r83827, dan r83828.

## Deployment

Perubahan berada di Java server/ZK. Deploy WAR/class hasil build dan restart
atau reload aplikasi. Sesudah deployment, uji kartu Keterangan pada daftar
Mahasiswa serta minimal satu layar KRS/Nilai untuk memastikan event popup dan
grafik tampil pada browser target.

