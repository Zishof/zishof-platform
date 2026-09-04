# Baseline Dokumentasi UAT Apotik dan eMedik

Dokumen ini adalah aturan tetap untuk pembuatan dan pembaruan panduan pengguna, laporan UAT, PDF, serta presentasi Apotik dan eMedik. Berlaku untuk sesi pengembangan berikutnya dan harus dibaca sebelum menghasilkan artefak dokumentasi baru.

## Narasi per tangkapan layar

- Setiap tangkapan layar harus memiliki penjelasan yang spesifik terhadap informasi yang benar-benar terlihat pada gambar tersebut.
- Narasi menjelaskan tujuan layar, cara membaca bagian penting, urutan penggunaan, hasil UAT yang relevan, kontrol yang perlu dijaga, serta tindakan ketika hasil menyimpang.
- Jangan memakai paragraf generik yang sama untuk semua layar. Istilah, langkah, risiko, dan bukti harus disesuaikan dengan fungsi menu yang sedang dibahas.
- Tidak ada target minimum jumlah kata. Prioritasnya adalah ketepatan, makna, keterbacaan, dan manfaat operasional.
- Jangan menampilkan jumlah kata, target jumlah kata, label kelengkapan narasi, atau pernyataan serupa di Word, PDF, PPTX, release notes, maupun manifest yang dibaca pengguna.
- Keterangan di bawah gambar cukup memakai judul tangkapan layar yang profesional. Jangan menambahkan informasi produksi internal yang tidak diperlukan pembaca.

## Diagram

- Diagram hanya ditambahkan ketika membantu menjelaskan peran, alur kerja, keputusan, atau hubungan data.
- Panah dan connector harus dibuat di belakang node serta berhenti pada sisi node; garis tidak boleh melewati kotak, teks, label, atau objek lain.
- Setiap node harus mempunyai jarak yang cukup. Teks tidak boleh terpotong, keluar dari kotak, atau bertumpuk dengan connector.
- Use case, flowchart, dan ERD/aliran data harus sesuai dengan menu yang dijelaskan; diagram generik yang hanya mengganti judul tidak diterima.
- Semua halaman Word/PDF dan seluruh slide PPTX wajib dirender dan diperiksa secara visual. Overlap, clipping, overflow, wrapping buruk, atau connector silang yang tidak disengaja harus diperbaiki sebelum publikasi.

## Bukti dan profesionalitas

- Hanya hasil UAT yang benar-benar dijalankan dan dapat diverifikasi yang boleh dinyatakan PASS.
- Data sample/sintetik harus ditandai jelas dan tidak boleh dinyatakan sebagai data pasien, produk terdaftar, formula klinis, atau hasil produksi nyata.
- Tidak boleh ada tangkapan layar halaman kosong, keadaan awal tanpa data, tabel tanpa baris, atau panel pratinjau bernilai nol di dalam manual pengguna dan presentasi UAT final.
- Setiap menu yang didokumentasikan harus menampilkan sekurang-kurangnya 100 record data sample yang relevan dan telah diverifikasi melalui API atau ringkasan pengujian. Apabila satu layar hanya dapat memuat sebagian record karena paginasi, total record harus terlihat pada layar dan pemeriksaan API harus membuktikan jumlah keseluruhannya.
- Screenshot yang tidak memenuhi ambang data wajib diganti; jangan menutupinya dengan narasi, diagram, atau klaim lulus.
- Panduan lama tetap disimpan sebagai arsip rilis. Versi baru dibuat sebagai berkas baru dan menjadi rujukan aktif untuk rilisnya.
- Tema, nama aplikasi, versi, resolusi, status server, dan angka UAT pada dokumen harus konsisten dengan build serta ringkasan mesin yang dipublikasikan.
- Satu-satunya pengecualian rilis Apotik v1.34.24 yang telah disetujui adalah APK belum memakai keystore produksi; pengecualian lain harus ditulis sebagai temuan dan tidak boleh disamarkan.

## Tata letak laporan aplikasi

- Semua laporan keuangan dan laporan operasional harus memakai lebar area konten sampai sisi kanan layar; tabel dua atau tiga kolom tidak boleh menumpuk sempit di sisi kiri sementara area kanan kosong.
- Kolom uraian, keterangan, nama akun, atau deskripsi mendapat porsi lebar utama. Kolom kode, tanggal, status, dan nilai dibuat proporsional; angka tetap rata kanan dan mudah dibandingkan.
- Angka yang dapat ditelusuri harus mempunyai penanda interaksi yang konsisten, dapat diklik, dan membuka rincian atau data penyusunnya tanpa mengubah filter periode aktif.
- Perubahan layout laporan wajib diterapkan melalui komponen laporan bersama agar Laba Rugi, Neraca, Arus Kas, Buku Besar, Trial Balance, serta laporan operasional lain memperoleh perilaku desktop yang sama.
- Bukti layar untuk panduan harus diambil setelah layout lebar ini aktif, dalam jendela yang dimaksimalkan, sehingga judul, keterangan, nilai, pagination, dan penanda drill-down terlihat jelas.

## Status dan filter pada seluruh halaman posting

- Setiap halaman posting wajib menampilkan tiga filter yang konsisten: **Semua**, **Telah Diposting**, dan **Belum Diposting**.
- Pilihan **Belum Diposting** tetap membedakan status operasional menjadi **Siap** dan **Tertahan**; alasan tertahan harus terlihat serta dapat ditindaklanjuti.
- Status setiap baris berasal dari field eksplisit API (`statusPosting`/`sudahDiposting`), bukan disimpulkan dari tombol, nominal, atau kolom kosong.
- API mempertahankan `rincian` untuk kompatibilitas client lama dan mengirim riwayat pada `rincianSudahDiposting`; batas data yang didukung adalah 100 sampai 10.000 record.
- Bukti UAT wajib memperlihatkan filter, kolom status, sedikitnya 100 record sumber yang valid, serta contoh record yang sudah dan belum diposting.

## Checkpoint deployment lintas server

- Deployment pada satu sesi atau satu server tidak dianggap otomatis berlaku pada server lain, walaupun aplikasi Flutter dan codebase asalnya sama.
- Setiap target server harus memiliki checkpoint **SIAP DEPLOY** tersendiri yang mencantumkan revision/commit, daftar file, urutan build/deploy, dan pemeriksaan pascadeploy.
- Status UAT 100% hanya boleh diberikan setelah endpoint pada server target diverifikasi langsung sesudah deployment.

## Gerbang publikasi

Dokumentasi hanya boleh dipublikasikan setelah Word, PDF, dan PPTX lulus pemeriksaan visual penuh, seluruh diagram bebas overlap, narasi unik dan relevan, setiap layar data membuktikan minimal 100 record sample, tidak ada label jumlah kata, tidak ada data sensitif, serta tautan/versi/checksum sesuai dengan artefak rilis.
