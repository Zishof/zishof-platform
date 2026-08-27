# Audit Posting ZKoss, Draf Jurnal, dan Diagnostik Akun

Tanggal audit: 27 Agustus 2026

Source ZKoss: `C:\opt\AIS\ais\src\main\src` dan mirror `C:\opt\AIS\ais\src\main\java`

Source POS: `apps/ebisnis`

## Hasil yang langsung dapat dipakai

- Posting Penjualan kini membaca metode pembayaran faktur lama secara berurutan: ID pada header, Nama/Kode pada detail, lalu `Tunai` sesuai kontrak model lama. Hasil berdasarkan nama hanya dipakai untuk slot utama; split pembayaran slot 2–5 tetap wajib mempunyai ID eksplisit.
- Metode, akun pendapatan, atau akun PPN yang belum ditemukan tidak lagi hanya menghasilkan `cara pembayaran tak dikenal`. Pesan menyebut referensi yang ditemukan, master/kolom yang perlu diperbaiki, tindakan setelah simpan, dan kapan harus meminta supervisor.
- Posting Kulakan, Bayar Hutang, Terima Piutang, serta Penyesuaian memakai satu pelengkap pesan terpusat. Sebab asli tetap ditampilkan dan ditambah jalur menu setting yang relevan.
- Desktop/Android menampilkan panel yang dapat dibuka dan disalin berisi seluruh masalah setting per dokumen. Dokumen siap tetap dapat diposting tanpa ditahan oleh dokumen lain yang belum siap.
- Draf pada layar adalah pratinjau terhitung per dokumen. Draf tidak menulis buku besar; jurnal permanen baru dibuat setelah pengguna menekan **Posting** dan hanya untuk baris berstatus **Siap diposting**.

## Tindakan pengguna saat draf belum siap

1. Buka rincian **memerlukan perbaikan setting**.
2. Catat referensi faktur/dokumen, nama metode/barang/supplier, nama akun yang kosong, serta menu yang disebutkan.
3. Lengkapi master terkait dan klik **Simpan**.
4. Kembali ke halaman Posting, lalu klik **Pratinjau** atau **Muat ulang**.
5. Pastikan draf menampilkan akun Debet dan Kredit serta status **Siap diposting** sebelum menekan **Posting**.
6. Jika pesan menyebut ID master hilang, split pembayaran tanpa ID, atau metode transaksi sebenarnya berbeda, hentikan posting dan minta supervisor mengoreksi transaksi sumber. Jangan mengubah payload atau draf jurnal secara manual.

Lokasi setting yang sekarang diinformasikan aplikasi:

| Masalah | Lokasi perbaikan |
|---|---|
| Akun metode pembayaran | **Master Data > Cara Pembayaran > metode terkait > Akun** |
| Akun kas fallback outlet | **Master Data > Toko > Akun Kas** |
| Pendapatan/PPN penjualan | **Master Data > Jenis Produk > Akun Pendapatan Penjualan / Akun PPN Keluaran** |
| Persediaan/HPP | **Master Aset atau Kelompok Aset barang > Akun Persediaan / Akun HPP** |
| Utang supplier | **Master Data > Penyedia > Akun Utang** |
| Piutang usaha | **Master Data > Toko > Akun Piutang Usaha**, lalu periksa Cara Pembayaran piutang |

## Seluruh metode Kasbon

- Semua metode yang kode atau namanya mengandung **Kasbon** otomatis diperlakukan sebagai **piutang customer**, termasuk Kasbon Pejuang, Kasbon Divisi, Kasbon Operasional, serta kode lama tanpa spasi/underscore.
- Semua Kasbon mewajibkan pemilihan member. Pada Kasbon Divisi/Operasional, member menjadi customer sekaligus **PJ/PIC yang mewakili divisi**, sehingga tagihan tetap mempunyai pemilik yang dapat ditelusuri.
- Saat startup, migrasi idempoten memperbaiki master Kasbon lama menjadi `masuk_sebagai_hutang=true` dan `wajib_pilih_member=true`. API penyimpanan master juga menegakkan kedua nilai tersebut agar tidak dapat dimatikan kembali secara tidak sengaja.
- Pada master Cara Pembayaran, kolom **Piutang Customer** dan **Wajib PIC** menampilkan aturan efektif. Form mengunci kedua aturan untuk metode Kasbon.
- Nominal Kasbon masuk ke mutasi/saldo piutang customer dan tetap mengikuti **Maksimal Boleh Utang** pada Tipe Member. Setelah setting batas diperbaiki, gunakan **Coba Kirim Transaksi Pending** untuk transaksi lokal yang sebelumnya ditolak.
- Bila kasir belum memilih member, checkout berhenti sebelum transaksi ditulis dan menampilkan tindakan **Pilih Member / PIC** beserta penjelasan bahwa Kasbon masuk piutang customer.

### Dampak dan UAT data lama

Ledger POS lama menentukan piutang dengan membaca flag pada master Cara Pembayaran saat laporan dibuka. Karena itu, normalisasi master Kasbon juga dapat membuat transaksi Kasbon historis yang sebelumnya salah berstatus “bukan hutang” muncul pada saldo piutang customer. Setelah deployment, tim keuangan wajib membandingkan **Mutasi Hutang/Piutang Member** dengan transaksi Kasbon historis sebelum melakukan penerimaan piutang atau posting massal. Jangan menghapus atau mengubah transaksi sumber; bila ditemukan PIC yang salah, koreksi melalui prosedur supervisor agar jejak audit tetap utuh.

## Audit seluruh class `*Posting*.java`

Pencarian dilakukan pada source kanonis dengan pola nama berkas, bukan hanya menu yang tampak di sidebar. Ditemukan 53 berkas:

- 45 mesin posting;
- 3 navigator/agregator;
- 1 helper API;
- 4 kontrak/model/utilitas pendukung.

Dari 45 mesin posting, 42 sudah memiliki pola pratinjau/draf jurnal. Tiga class ZKoss lama berikut belum memiliki pratinjau jurnal eksplisit dan menjadi gap lanjutan:

| Class | Kondisi | Tindak lanjut aman |
|---|---|---|
| `PostingPerjanjianKerjasamaAction.java` | Menampilkan validasi akun, belum membentuk draf per dokumen | Pisahkan kalkulasi draf dari eksekusi sebelum membuka posting massal |
| `PostingPembayaranAction.java` | Posting lama tanpa kontrak draf per dokumen | Tambahkan builder draf dan status siap/belum siap tanpa mengubah rumus jurnal |
| `PostingTransaksiHarianAction.java` | Jalur lama tidak mempunyai pratinjau akun eksplisit | Petakan sumber akun dan tambahkan pratinjau sebelum tombol posting |

Class berikut sudah diperiksa tetapi memang bukan mesin pembentuk jurnal sehingga tidak wajib mempunyai draf sendiri:

- `PostingJurnalLoadingUtil.java`
- `PostingHistory.java`
- `InventoryPostingPort.java`
- `JournalPostingPort.java`
- `PostingJurnalAction.java`
- `PostingHistoryAction.java`
- `PostingTokoKantinAction.java`
- `PostingKantinLanjutanHelper.java` (adapter API; draf dibentuk untuk empat menu toko)

Mesin posting yang sudah memiliki pratinjau/draf eksplisit:

- Asset: `PostingSaldoAwalMasterAssetDetailAction`, `PostingPenyusutanAssetAction`, `PostingPengadaanAction`, `PostingPemesananPekerjaanAction`, `PostingPemesananDpAction`, `PostingPembayaranTerminAction`, `PostingPembayaranDpAction`, `PostingJurnalBalikDpPemesananPekerjaanAction`, dan `PostingDpPemesananPekerjaanAction`.
- Akuntansi: `PostingUangMukaAction`, `PostingProsesTransitoriAction`, `PostingProsesTransferAction`, `PostingPertangungjawabanPengembalianAction`, `PostingPertangungjawabanPajakAction`, `PostingPertangungjawabanKasBesarAction`, `PostingPertangungjawabanAction`, `PostingPenyusutanTabsAction`, `PostingPenggantianKasKecilAction`, `PostingKasKecilAction`, `PostingKasBesarAction`, `PostingJenisKasKecilAction`, dan `PostingDanaTalanganAction`.
- Sekolah: `PostingUtangDiskonSiswaAction`, `PostingPiutangSiswaAction`, `PostingPiutangDendaSiswaAction`, `PostingDibayarDimukaSiswaAction`, `PostingDepositSiswaAction`, dan `PostingCicilanSiswaAction`.
- Mahasiswa: `PostingDetailKegiatanAction`, `PostingDepositSiswaAction`, `PostingDepositAction`, `PostingCicilanMahasiswaAction`, `PostingCicilanDibayarDimukaMahasiswaAction`, `PostingBiayaPaymentGatewayPembayaranMahasiswaAction`, `PostingBiayaAdministrasiPembayaranMahasiswaAction`, dan `PostingPengeluaranMahasiswaAction`.
- Payroll: `PostingTransaksiPenggajianAction`, `PostingTransaksiPembayaranGajiAction`, dan `PostingTransaksiPegawaiAction`.
- Kantin/POS: `PostingPenjualanKantinAction` dan `PostingHppKantinAction`.
- Helper bersama: `PostingJurnalHelper`.

## Tingkat diagnostik saat audit

- 15 class sudah memakai petunjuk langkah terstruktur dari `CommonAkunting`.
- 28 class masih mempunyai setidaknya satu pesan akun generik. Ini bukan berarti jurnalnya salah, tetapi jalur setting pada seluruh cabang error belum seragam.
- Perubahan kali ini menutup jalur yang dipakai seluruh menu Posting POS/toko dan kasus produksi Posting Penjualan. Standardisasi 28 class lama harus dilakukan bertahap per modul karena sumber akun berbeda-beda; mengganti pesan secara mekanis berisiko mengarahkan admin ke master yang salah.

Aturan untuk perubahan berikutnya: setiap cabang `akun == null` pada class Posting wajib menyebut (1) dokumen, (2) peran akun, (3) master/parameter sumber akun, (4) menu dan kolom yang perlu diisi, (5) tindakan setelah simpan, dan (6) kapan perlu eskalasi ke supervisor.

## Verifikasi

- SVN source kanonis dan mirror sebelum perubahan: bersih pada revisi 78384.
- Source kanonis dan mirror untuk dua class yang diubah: identik byte-for-byte.
- Kompilasi Java 8 berhasil untuk `PostingPenjualanKantinAction`, `PostingKantinLanjutanHelper`, `CaraPembayaranKoperasi`, `PosApi`, dan `KantinHelper` beserta dependensinya.
- Flutter analyzer untuk perubahan Kasbon Divisi/Operasional: tidak ada error; tersisa satu info gaya `sort_child_properties_last` yang sudah ada pada struktur form.
- Test kontrak Draft Jurnal, diagnostik posting, dan Kode Akun: 14/14 lulus. Test khusus Kasbon/PIC/piutang dan refresh Cara Pembayaran: 9/9 lulus.
