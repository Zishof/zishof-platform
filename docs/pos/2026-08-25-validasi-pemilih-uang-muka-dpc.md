# Validasi Pemilih Uang Muka pada Pertanggungjawaban

Tanggal: 2026-08-25

## Masalah

Dialog **Pilih Uang Muka** sebelumnya hanya menampilkan data yang lolos filter status, tetapi belum memvalidasi bahwa pencairan telah direalisasikan melalui Proses Transfer (DPC). Akibatnya, aturan kelayakan tidak terlihat oleh pengguna dan request lama berpotensi memilih Uang Muka yang belum siap dipertanggungjawabkan.

## Perubahan

- Semua Uang Muka yang relevan tetap ditampilkan agar statusnya dapat ditelusuri.
- Baris hanya dapat dipilih bila:
  - data aktif;
  - status telah **Disetujui** dan memiliki penyetuju;
  - telah masuk Proses Transfer (DPC);
  - DPC telah direalisasikan; dan
  - belum dipakai oleh pertanggungjawaban lain.
- Baris yang tidak memenuhi syarat dibuat nonaktif, diberi ikon kunci, status, dan alasan yang spesifik.
- Uang Muka yang sudah tersimpan pada dokumen yang sedang diedit tetap dapat dipertahankan.
- Validasi yang sama dijalankan ulang pada backend saat Simpan sehingga tidak dapat dilewati oleh klien lama atau request langsung.

## Kontrak respons pencarian

Setiap baris menyediakan `dapatDipilih`, `pilihanTersimpan`, `statusPemilihan`, `alasanTidakDapatDipilih`, `statusUangMuka`, `sudahMasukDpc`, dan `dpcDirealisasikan`.

## UAT yang perlu dijalankan

1. Uang Muka belum disetujui: tampil terkunci dan tidak dapat diklik.
2. Sudah disetujui tetapi belum masuk DPC: tampil terkunci dengan alasan belum masuk DPC.
3. Sudah masuk DPC tetapi belum direalisasikan: tampil terkunci dengan alasan belum direalisasikan.
4. Sudah disetujui dan DPC direalisasikan: dapat dipilih.
5. Sudah dipakai LPJ lain: tampil terkunci.
6. Edit LPJ lama: pilihan Uang Muka milik dokumen tersebut tetap dapat dipertahankan.
7. Request Simpan langsung dengan ID yang tidak memenuhi syarat: ditolak backend tanpa perubahan parsial.

