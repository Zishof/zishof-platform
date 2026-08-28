# Penolakan izin Kasbon Divisi pada transaksi member

Tanggal analisis: 28 Agustus 2026

## Kesimpulan operasional

Pesan **“Cara pembayaran tidak diizinkan untuk Jenis/Tipe Member ini”** adalah
penolakan aturan metode pembayaran. Pesan tersebut bukan penolakan nominal,
batas transaksi, atau batas hutang. Karena itu menaikkan **Batas Transaksi**
atau **Maksimal Boleh Utang** tidak menyelesaikan tahap ini.

Aturan efektif merupakan irisan dari:

1. **Pelanggan > Jenis Member > Cara Bayar yang Diizinkan**; dan
2. **Pelanggan > Tipe Member > Cara Bayar**, selama Tipe Member berlaku untuk
   toko kasir melalui **Cakupan Toko**.

Bila salah satu daftar belum disetel, daftar lain menjadi aturan efektif. Bila
keduanya sudah disetel, metode harus dicentang pada keduanya. Kasbon Divisi
tetap membutuhkan member sebagai PJ/PIC dan dicatat sebagai piutang customer,
tetapi kebutuhan PIC tidak otomatis membatalkan aturan izin metode member.

## Langkah penyelesaian

1. Jangan mengirim transaksi pending berulang dan jangan membuat transaksi
   pengganti. Jurnal lokal harus dipertahankan sebagai bukti transaksi asli.
2. Catat kode transaksi, member, Jenis Member, Tipe Member, metode pembayaran,
   toko, serta total.
3. Admin membuka **Pelanggan > Jenis Member**, memilih Jenis Member terkait,
   lalu mencentang **Kasbon Divisi** pada **Cara Bayar yang Diizinkan**.
4. Admin membuka **Pelanggan > Tipe Member**, memilih Tipe Member terkait,
   mencentang **Kasbon Divisi** pada **Cara Bayar**, serta memastikan
   **Cakupan Toko** mencakup toko kasir. Klik **Simpan**.
5. Kasir menekan **Sinkronkan**, lalu **Muat Ulang**.
6. Buka **Pesanan > Transaksi Pending** dan klik
   **Coba Kirim Transaksi Pending** satu kali.
7. Hanya jika penolakan berikutnya secara eksplisit menyebut batas harian,
   mingguan, bulanan, atau maksimal hutang, periksa nilai batas yang sesuai.

## Menentukan apakah batas Rp5.000.000 cukup

Nilai Rp5.000.000 tidak dapat dinyatakan cukup hanya dari satu transaksi pada
foto. Transaksi `AB260823144207L87H` bernilai Rp1.335.700, tetapi laporan
menyebut ada enam transaksi Syirkah. Sistem memeriksa dua kelompok batas yang
berbeda setelah izin metode lolos:

- **Batas Transaksi harian/mingguan/bulanan** membandingkan seluruh pemakaian
  member pada periode berjalan ditambah transaksi yang sedang dikirim.
- **Maksimal Boleh Utang** membandingkan hutang berjalan member ditambah
  nominal Kasbon baru.

Karena itu Rp5.000.000 hanya cukup bila, untuk member/PIC yang sama, total
periode berjalan ditambah transaksi berikutnya tidak melebihi batas periode
dan hutang berjalan ditambah seluruh Kasbon yang dikirim tidak melebihi batas
hutang. Bila enam transaksi memakai enam member/PIC berbeda, perhitungan
dilakukan per member. Catat nominal keenam transaksi dan member/PIC masing-masing
sebelum menentukan angka batas; jangan menaikkan limit secara tebakan.

Jika batas transaksi periode terlampaui, aplikasi membuat **Pengajuan Limit
Member** yang harus diputuskan petugas berwenang. Jika **Maksimal Boleh Utang**
terlampaui, admin perlu memperbaiki kebijakan Tipe Member atau tim keuangan
menyelesaikan hutang berjalan; persetujuan batas transaksi tidak otomatis
menghapus batas hutang.

## Koreksi pesan aplikasi

Server sekarang menyebut metode, member, Jenis/Tipe Member, keadaan jurnal
pending, lokasi setting, dan urutan retry. Klien juga membedakan penolakan izin
metode dari hak akses akun serta dari limit nominal. Ini mencegah saran keliru
untuk menaikkan limit atau login sebagai supervisor ketika akar masalahnya
adalah daftar metode yang diizinkan.

Jika perangkat masih menampilkan kalimat lama **“Cara pembayaran tidak
diizinkan untuk Jenis/Tipe Member ini. Muat ulang aturan pembayaran”** disertai
saran masuk dengan akun berwenang, backend aktif belum memuat koreksi SVN
`r78459` dan/atau klien belum memuat pemetaan pesan terbaru. Deploy backend,
restart layanan, lalu pasang build klien terbaru sebelum UAT ulang. Menekan
Sinkronkan pada perangkat tidak menggantikan class server yang belum dideploy.

## UAT wajib

- Member dengan Kasbon Divisi dicentang pada Jenis dan Tipe: metode tampil dan
  transaksi dapat dikirim.
- Metode hanya dicentang pada salah satu dari dua daftar yang sama-sama telah
  disetel: server menolak dengan nama metode/member dan langkah setting.
- Tipe tidak berlaku pada toko aktif: pesan menunjukkan Tipe belum berlaku pada
  toko dan mengarahkan admin ke Cakupan Toko.
- Setelah setting diperbaiki, satu kali **Coba Kirim Transaksi Pending** tidak
  membuat transaksi duplikat.
- Penolakan limit nominal, bila ada setelah izin lolos, tetap memakai pesan
  khusus limit dan tidak tercampur dengan penolakan izin metode.
