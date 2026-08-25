# Tagihan rutin tanpa BAST dan sumber anggaran

Tanggal: 2026-08-25

## Permintaan

- Menu **Terima Tagihan Vendor** harus menerima tagihan rutin yang tidak mempunyai BAST, misalnya listrik PLN, air, internet, sewa, dan layanan berkala lain.
- Setiap rincian tagihan dapat menunjuk sumber anggaran.
- Logika anggaran mengikuti implementasi ZKoss lama.
- Anggaran tidak wajib secara bawaan dan dapat diwajibkan melalui konfigurasi.

## Keputusan implementasi

Logika ZKoss memakai satu `SaldoAwalMasterAsset` sebagai kepala tagihan dan beberapa
`SaldoAwalMasterAssetDetail` sebagai rincian. Sumber anggaran disimpan pada relasi
`Workspace` di setiap rincian, bukan satu anggaran global pada kepala tagihan. Model
yang sama digunakan pada POS agar alur pembayaran dan pembuatan
`DaftarPengajuanTransfer` tetap konsisten dengan aplikasi lama.

Alur BAST lama tidak diubah. Tagihan rutin ditampilkan pada kelompok terpisah di
halaman yang sama sehingga tagihan berbasis penerimaan barang tetap bekerja seperti
sebelumnya.

## Konfigurasi

- Kunci: `pengadaan_tagihan_rutin_anggaran_wajib`
- Nilai bawaan: `TIDAK_AKTIF`
- Tidak aktif: sumber anggaran boleh kosong per rincian.
- Aktif: setiap rincian wajib memilih anggaran sebelum disimpan.

Konfigurasi didaftarkan pada halaman konfigurasi kategori **Pengadaan / Tagihan
Vendor**.

## API dan UI

- `pengadaan_tagihan_rutin_simpan`: menyimpan kepala dan rincian tagihan rutin,
  memvalidasi anggaran sesuai konfigurasi, lalu membuat DPC melalui mekanisme resmi.
- `pengadaan_tagihan_daftar`: mengembalikan tagihan BAST lama serta `dataRutin`
  beserta kode/nama anggaran tiap rincian dan flag `anggaranWajib`.
- Tombol **Tagihan Tanpa BAST** membuka form penyedia, nomor/tanggal tagihan,
  keterangan, dan rincian berulang berisi uraian, nominal, serta pemilih anggaran.
- Daftar tagihan rutin langsung terlihat pada halaman Terima Tagihan Vendor dan
  dapat dibuka untuk melihat rincian sumber anggarannya.

## Pengelolaan sesi

Operasi tulis menggunakan `openSession()` dan selalu melakukan rollback bila perlu,
kemudian `clear`/`disconnect`/`close` melalui `HibernateUtil.closeSessionQuietly()` di
blok `finally`. Operasi baca juga menutup sesi pada `finally`.

## Verifikasi lokal

- Kompilasi backend: `mvn -DskipTests compile` — berhasil dengan Java 1.7.
- Flutter analyzer untuk `pengadaan_tagihan_screen.dart` — tidak ada temuan.
- Uji kontrak Pengadaan dan Anggaran — seluruh `14` pengujian lulus.
- Build lokal installer Desktop eBisnis `1.33.82` — berhasil.
- Dua source-tree backend (`src/main/src` dan `src/main/java`) diverifikasi identik.
- Tidak dilakukan commit, push, atau publikasi pada tahap uji lokal ini.

## Verifikasi lanjutan 25-08-2026

- Rute API `pengadaan_tagihan_rutin_simpan` diverifikasi terdaftar pada
  `PengadaanPosApiHelper`; data anggaran tetap dilekatkan pada setiap
  `SaldoAwalMasterAssetDetail` sebagai `Workspace`, sama seperti alur ZKoss.
- Validasi server memastikan anggaran hanya wajib apabila konfigurasi
  `pengadaan_tagihan_rutin_anggaran_wajib` aktif. Dalam keadaan bawaan
  (`TIDAK_AKTIF`), tagihan listrik, air, internet, sewa, dan tagihan rutin lain
  dapat disimpan tanpa memilih anggaran.
- Form POS mengirim `workspaceId` hanya untuk rincian yang dipilih dan
  menampilkan status wajib/opsional sesuai respons server.
- Kompilasi ulang backend dengan Maven 3.9.16 dan opsi `-DskipTests compile`
  berhasil pada 25-08-2026. Flutter analyzer untuk layar tagihan juga selesai
  tanpa temuan.
- Saat verifikasi build, satu pemanggilan Hibernate yang tidak terkait tagihan
  rutin pada `RepositoryAlertService` diperbaiki dari `Restrictions.or(a,b,c)`
  menjadi OR bertingkat yang ekuivalen; versi Hibernate proyek hanya mendukung
  dua argumen dan perubahan ini diperlukan agar kompilasi dapat selesai.
