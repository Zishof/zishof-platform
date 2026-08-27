# Standar wajib pesan error dan penolakan yang edukatif

Status: **WAJIB** untuk seluruh POS Desktop, Android, endpoint POS, pekerjaan
baru, dan perubahan pada modul lama.

## Tujuan

Pengguna tidak boleh berhenti pada pesan seperti “gagal”, “ditolak”, “data
salah”, atau “hubungi admin”. Setiap kendala harus membantu pengguna memahami:

1. apa yang terjadi;
2. data atau aturan mana yang menyebabkan proses berhenti;
3. apakah aman untuk mencoba ulang;
4. menu, tombol, atau kolom yang perlu dibuka;
5. urutan tindakan mandiri untuk menyelesaikannya;
6. kapan tindakan harus dialihkan kepada supervisor, admin, atau developer.

Informasi teknis tetap tersedia untuk penelusuran, tetapi tidak boleh menjadi
satu-satunya sumber penjelasan.

## Kontrak wajib bagi setiap error

Setiap kegagalan yang sampai ke pengguna **HARUS** mempunyai lima bagian:

| Bagian | Isi wajib |
|---|---|
| Judul | Ringkasan khusus, misalnya “Batas hutang member terlampaui”, bukan “Error”. |
| Penjelasan | Apa yang ditolak, data terkait, batas/nilai/status saat ini, serta dampaknya. |
| Tindakan mandiri | Langkah berurutan dengan nama menu, tombol, atau kolom yang benar-benar tersedia. |
| Batas eskalasi | Kondisi yang memerlukan supervisor/admin/developer dan apa yang harus dikirim. |
| Informasi teknis | Kode referensi, action, HTTP/kode bisnis, request aman, respons aman, dan stack server bila relevan. |

Solusi minimal terdiri dari tiga langkah:

1. tindakan pertama yang aman, termasuk larangan mengulang bila retry tidak
   akan membantu;
2. lokasi perbaikan dengan pola `Menu > Submenu > Tombol/Kolom`;
3. langkah verifikasi atau eskalasi bila tindakan mandiri belum berhasil.

Kalimat “perbaiki data sesuai penjelasan”, “coba kembali”, dan “hubungi admin”
tidak memenuhi kontrak bila berdiri sendiri.

## Bentuk respons API

Endpoint POS harus mengirim struktur berikut untuk penolakan terduga:

```json
{
  "status": "error",
  "kode": "KODE_BISNIS_STABIL",
  "judul": "Judul khusus untuk pengguna",
  "message": "Apa yang terjadi, termasuk nilai atau status yang relevan.",
  "solusi": [
    "Tindakan aman pertama.",
    "Buka Menu > Submenu lalu perbaiki Kolom yang disebutkan.",
    "Setelah benar, kembali ke layar awal dan klik Tombol satu kali.",
    "Jika masih gagal, salin Informasi Teknis dan kirim ke peran yang tepat."
  ],
  "referensi": "API-...",
  "teknis": "detail untuk dukungan teknis"
}
```

Ketentuan:

- `kode` stabil dan dapat diuji; jangan menjadikan teks bebas sebagai satu-satunya
  pembeda perilaku.
- `message` aman dibaca pengguna dan tidak memuat SQL, stack trace, token,
  kata sandi, atau data rahasia.
- `solusi` menyebut tombol/menu yang nyata. Bila tidak ada tindakan mandiri,
  katakan secara eksplisit bahwa pengguna harus berhenti dan siapa yang harus
  menangani.
- `teknis` menyimpan sebab lengkap yang sudah disanitasi untuk dukungan.
- Klien mempertahankan solusi server yang sudah spesifik. Server lama yang
  masih mengirim solusi generik akan diperkaya oleh pemetaan terpusat di
  `AppErrorInfo`/`ApiException`.

## Matriks tindakan wajib

| Jenis kendala | Yang harus diberitahukan kepada pengguna |
|---|---|
| Jaringan/timeout | Periksa jaringan dan alamat server; transaksi lokal aman atau tidak; kapan retry otomatis berjalan; tombol retry manual bila tersedia. |
| Sesi login 401 | Sesi berakhir; kembali ke login; jangan terus mengoperasikan layar lama. |
| Toko kosong | Klik pilihan toko pada bilah atas, pilih toko, klik Muat Ulang; admin memeriksa akses toko bila daftar kosong. |
| Sesi kas | Klik Kas, buka/tutup sesi yang benar; supervisor menangani sesi perangkat lain atau koreksi. |
| Hak akses | Tindakan tidak diizinkan; admin memeriksa Grup Pengguna dan izin aksi; pengguna keluar-masuk setelah izin berubah. |
| Validasi form | Sebut kolom, nilai yang diterima, nilai yang dikirim, dan tombol yang dapat digunakan setelah koreksi. |
| Stok/batch/kedaluwarsa | Sebut produk dan jumlah; arahkan ke Stok Opname/pemeriksaan batch; jangan menyuruh retry sebelum stok diperbaiki. |
| Member/saldo/hutang | Sebut member, saldo/hutang berjalan, batas, dan tambahan transaksi; arahkan ke Pilih Member, Topup, atau Tipe Member sesuai kasus. |
| Duplikat/idempotensi | Larang membuat transaksi pengganti; arahkan ke Riwayat Penjualan dan Riwayat Sinkronisasi. |
| Transaksi pending | Bedakan gangguan teknis yang layak retry dengan penolakan bisnis yang tidak akan membaik karena retry. Pertahankan jurnal lokal. |
| Error internal | Nyatakan proses yang gagal dan apakah ada perubahan tersimpan; sediakan Salin Informasi Teknis dan kode referensi. |
| Data master masih dipakai | Sebut data yang hendak dihapus, jenis dan jumlah referensinya, contoh akun/transaksi terkait, menu untuk menonaktifkan atau memperbaiki relasi, serta larangan menghapus langsung di database. |
| Versi server tertinggal | Jelaskan bahwa perbaikan sudah ada di sumber tetapi kelas/JSP aktif masih lama; operator harus deploy artefak server terbaru, bersihkan cache kompilasi JSP bila relevan, restart, lalu verifikasi nomor revisi. Jangan menyuruh kasir mengulang aksi yang sama. |

## Penghapusan data master yang masih direferensi

Pelanggaran foreign key yang dapat diprediksi harus diperiksa **sebelum**
perintah `DELETE`. Contoh: Pedagang yang masih menjadi identitas akun pada
`tbmuser` tidak boleh dipaksa dihapus atau dihapus secara cascade.

Pesan wajib menyebut nama Pedagang, jumlah akun dan contoh ID akun terkait,
kemudian mengarahkan pengguna ke **Konfigurasi > Akun Pengguna**. Jika akun
tidak digunakan lagi, tindakan mandiri yang aman adalah mengubah **Status**
menjadi **Nonaktif**; data Pedagang tidak perlu dihapus. Penghapusan permanen
hanya dilanjutkan setelah admin sistem memindahkan atau melepaskan relasi akun
melalui alur yang teraudit. Mengubah foreign key langsung di database dilarang.

Pemeriksaan awal ini juga mencegah transaksi database masuk status `aborted`,
sehingga kegagalan yang sudah diperkirakan tidak menghasilkan stack trace
sebagai satu-satunya penjelasan kepada pengguna.

## Contoh wajib: batas hutang transaksi pending

Pesan yang benar:

> Batas hutang member terlampaui. Member coffequ kantin banin mempunyai batas
> Rp500.000, hutang berjalan Rp0, dan transaksi ini menambah Rp2.601.968.

Tindakan yang ditampilkan:

1. Jangan klik **Bayar** atau **Coba Kirim** berulang; penolakan bisnis tidak
   berubah karena retry.
2. Minta admin membuka **Pelanggan > Tipe Member**, memilih tipe terkait, lalu
   memeriksa **Maksimal Boleh Utang**.
3. Jika member atau metode kasbon salah, minta supervisor melakukan koreksi;
   jangan mengubah payload jurnal pending secara manual.
4. Setelah data benar, buka **Pesanan > Transaksi Pending** lalu klik
   **Coba Kirim Transaksi Pending** satu kali.
5. Bila tetap gagal, buka **Informasi Teknis**, klik **Salin Informasi Teknis**,
   dan kirimkan kode referensi beserta kode transaksi kepada admin.

## Aturan retry dan keselamatan data

- Retry otomatis hanya untuk gangguan jaringan, timeout, atau kegagalan teknis
  yang dinilai sementara.
- Penolakan bisnis stabil, misalnya batas hutang, hak akses, stok, atau data
  wajib, harus berstatus **Gagal/Ditolak** dan tidak membanjiri server.
- Tombol retry manual tidak boleh menjanjikan bahwa semua kegagalan dapat
  selesai dengan pengiriman ulang. Pesan harus menjelaskan prasyaratnya.
- Payload transaksi pending adalah jurnal kejadian dan tidak boleh diubah
  diam-diam. Koreksi harus melalui alur supervisor yang meninggalkan audit.
- Duplikat harus diperiksa melalui riwayat dan idempotensi, bukan diselesaikan
  dengan membuat kode transaksi baru.

## Implementasi terpusat

1. Server membentuk `kode`, `judul`, `message`, `solusi`, `referensi`, dan
   `teknis` pada pintu keluar API.
2. `ApiClient` mempertahankan solusi server yang spesifik.
3. `panduanResolusiGalat` memperkaya server lama atau solusi generik dengan
   langkah operasional berdasarkan pesan, kode, dan action.
4. Semua snackbar menyediakan tombol **Detail**.
5. Panel detail selalu menampilkan **Yang dapat Anda lakukan**, bagian
   **Informasi Teknis**, dan tombol **Salin Informasi Teknis**.

Layar baru tidak boleh membuat format error sendiri bila komponen terpusat dapat
dipakai.

## Definition of Done

Perubahan yang dapat menghasilkan error belum selesai sebelum seluruh butir ini
lulus:

- [ ] Setiap penolakan terduga memiliki kode stabil dan judul khusus.
- [ ] Pesan menyebut penyebab, data/status penting, dan dampaknya.
- [ ] Solusi menyebut menu/tombol/kolom serta urutan klik yang nyata.
- [ ] Dijelaskan apakah retry aman, sia-sia, atau berisiko duplikat.
- [ ] Ada batas eskalasi dan tombol Salin Informasi Teknis.
- [ ] Data sensitif tidak muncul di pesan maupun log yang dapat disalin.
- [ ] Ada uji regresi untuk minimal satu respons sukses, satu penolakan bisnis,
      satu gangguan jaringan, dan satu fallback server lama.
- [ ] UAT memverifikasi pesan menggunakan sudut pandang kasir, bukan hanya
      memeriksa kode HTTP atau stack trace.

## Review wajib

Reviewer harus menolak perubahan bila:

- hanya menampilkan `e.toString()` tanpa detail dan solusi;
- solusi hanya berkata “coba lagi” atau “hubungi admin”;
- penolakan permanen terus dicoba otomatis;
- nama menu/tombol pada solusi tidak ada di UI;
- stack trace/SQL menggantikan penjelasan pengguna;
- pesan menyatakan gagal tanpa menjelaskan apakah data sudah tersimpan.
