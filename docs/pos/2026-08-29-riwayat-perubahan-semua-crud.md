# Riwayat perubahan seluruh CRUD POS

Tanggal implementasi: 29 Agustus 2026

## Keputusan desain

Riwayat perubahan tidak disalin menjadi tab terpisah pada setiap halaman.
Seluruh CRUD POS dipantau melalui satu fasilitas generik di menu
**Sistem > Riwayat Perubahan Data**. Tab kontekstual pada Produk dan Pelanggan
tetap tersedia sebagai pintasan untuk pengguna yang sedang bekerja pada data
tersebut.

Pada halaman Pelanggan, pintasan diberi nama **Riwayat CRUD** dan memakai layar
global dalam mode tertanam. Default-nya Anggota/Member, tetapi pilihan Jenis Data
tetap memuat seluruh entitas yang didukung server.

Pendekatan terpusat dipilih agar filter, keamanan, format nilai
**dari → menjadi**, penanganan error, dan pengembangan berikutnya mempunyai satu
implementasi. Menyalin tab ke puluhan halaman akan menyebabkan perilaku audit
berbeda-beda dan mudah tertinggal saat sebuah CRUD baru ditambahkan.

## Cakupan

Registry backend mencakup master dan transaksi operasional POS yang sudah
`@Audited`, antara lain:

- produk, kategori, grup, UOM, pemasok, batch, toko, dan kebijakan retur;
- member, jenis/tipe/identitas member, calon member, limit, saldo, dan
  pembayaran member;
- kulakan, faktur/item pengadaan, stok opname, mutasi stok, retur, produksi,
  serta pemakaian bahan baku;
- cara pembayaran, diskon, transaksi, pesanan, sesi kas, piutang customer,
  hutang supplier, Inventory & Sales, apotek, hotel, pengadaan aset, dan ujian.

Daftar jenis data di aplikasi diambil dinamis dari aksi `revisi_entitas`.
Penambahan kode baru pada registry server otomatis muncul di pilihan aplikasi;
kode yang belum memiliki label khusus tetap diubah dari `camelCase` atau
`snake_case` menjadi label yang ramah.

## Aturan wajib CRUD baru

1. Entitas yang perlu dipantau harus memakai `@Audited` dan migrasi tabel audit
   harus tersedia sebelum fitur dipakai.
2. Daftarkan entitas dengan kode stabil pada whitelist
   `RevisiApiHelper.ENTITAS`. Jangan menerima nama kelas bebas dari request.
3. Pastikan properti teknis dan kredensial tidak muncul. PIN, pass/password,
   hash, salt, token, dan secret dikecualikan dari daftar, detail, pencarian,
   pilihan kolom, dan proses restore.
4. Gunakan `revisi_jelajah` untuk pemantauan lintas baris dan `revisi_daftar`
   untuk riwayat satu baris. Jangan membuat query audit sendiri di tiap layar.
5. Tampilkan jenis data, nilai sebelum, nilai sesudah, waktu, nomor revisi,
   jenis perubahan, dan pelaku. Error server wajib menjelaskan tindakan yang
   dapat dilakukan pengguna.
6. Jelajah dan restore lintas baris hanya untuk administrator. Audit tetap
   online-only dan tidak disalin ke SQLite perangkat.

## UAT

1. Login sebagai administrator dan buka **Sistem > Riwayat Perubahan Data**.
2. Pastikan pilihan **Jenis data** memuat master serta transaksi POS yang
   didukung server.
3. Ubah masing-masing satu data Produk, Member, UOM, Pemasok, Kulakan, Stok
   Opname, dan Produksi.
4. Cari tiap jenis data pada rentang hari ini; pastikan revisi dan pelakunya
   muncul.
5. Klik revisi; pastikan field menampilkan nilai **dari → menjadi** dengan label
   yang dapat dibaca.
6. Pastikan PIN/password/hash/salt/token tidak muncul, tidak dapat dicari, dan
   tidak tersedia sebagai kolom filter.
7. Login sebagai non-administrator; menu lintas data tidak boleh tersedia,
   sedangkan tombol riwayat satu baris yang memang diizinkan tetap bekerja.
