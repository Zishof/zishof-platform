import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../bantuan_content.dart';

class PosHelpSpec {
  final String keyName;
  final String title;
  final String purpose;
  final List<String> flow;
  final String input;
  final String process;
  final String output;
  final String control;
  final String scenario;

  const PosHelpSpec(this.keyName, this.title, this.purpose, this.flow,
      this.input, this.process, this.output, this.control, this.scenario);

  bool get isEmedik => keyName.startsWith('emedik_');

  String get narrative => '''
PENGANTAR DAN TUJUAN

$title merupakan bagian dari ${isEmedik ? 'POS eMedik' : 'POS Apotik'} yang dipakai untuk $purpose. Bantuan ini ditujukan kepada petugas operasional, supervisor, administrator, dan pemeriksa internal. Bacalah seluruh bagian sebelum menggunakan menu untuk pertama kali. Sistem membantu pencatatan, tetapi keputusan pelayanan tetap harus mengikuti kewenangan petugas, standar operasional fasilitas, peraturan kesehatan, dan hasil pemeriksaan dokumen sumber. Jangan memasukkan data contoh pada lingkungan produksi. Gunakan akun sendiri, jangan berbagi kata sandi, dan pastikan identitas pengguna yang tampil memang benar sebelum memproses data pasien, resep, obat, pembayaran, atau persediaan.

HASIL YANG DIHARAPKAN

Ketika pekerjaan selesai, sistem menghasilkan $output. Hasil dianggap benar apabila data sumber terbaca, identitas dan tanggal sesuai, angka telah diperiksa, tidak ada peringatan yang diabaikan, serta respons server menyatakan berhasil. Tombol simpan atau bayar tidak boleh ditekan berulang ketika jaringan lambat. Tunggu indikator proses dan baca pesan yang muncul. Jika hasil layar meragukan, jangan membuat transaksi pengganti sebelum memastikan transaksi pertama benar-benar gagal. Pemeriksaan dapat dilakukan melalui laporan, status tagihan, riwayat transaksi, kartu stok, atau konfirmasi supervisor sesuai menu yang digunakan.

PERSIAPAN SEBELUM MULAI

Pastikan perangkat memiliki tanggal dan waktu yang benar, koneksi ke server stabil, aplikasi memakai versi terbaru yang disetujui organisasi, printer dan pemindai bila diperlukan sudah siap, serta sesi login belum kedaluwarsa. Siapkan dokumen sumber berupa $input. Periksa kelengkapan, keterbacaan, nomor referensi, tanggal, pihak yang terkait, dan otorisasi. Untuk data klinis dan farmasi, hindari menyebutkan informasi pasien dengan suara keras atau memperlihatkan layar kepada orang yang tidak berkepentingan. Pada perangkat Android, gunakan orientasi yang nyaman, jaga baterai, dan hindari berpindah aplikasi ketika proses penyimpanan berjalan. Pada desktop, manfaatkan layar yang lebih lebar untuk membandingkan dokumen dengan data sistem.

MEMAHAMI TAMPILAN

Bagian judul menunjukkan menu aktif. Tombol Bantuan membuka panduan ini tanpa mengubah transaksi. Area filter atau pencarian digunakan untuk menemukan data yang sudah ada; gunakan kata kunci yang cukup spesifik, kemudian cocokkan lebih dari satu identitas sebelum memilih. Formulir digunakan untuk memasukkan data baru atau koreksi yang memang diizinkan. Daftar atau tabel menunjukkan hasil dari server dan dapat berubah setelah penyegaran. Warna hijau umumnya menandakan berhasil atau aman, kuning meminta perhatian, dan merah menunjukkan kondisi yang harus dihentikan atau dikoreksi. Ikon tidak menggantikan teks; baca tooltip, label, dan pesan validasi sampai tuntas.

ALUR KERJA RINCI

Alur utama menu ini adalah ${flow.join(' → ')}. Mulailah dari tahap pertama dan jangan melompati pemeriksaan. $process. Pada setiap perpindahan tahap, bandingkan data di layar dengan dokumen sumber. Jika ada pilihan yang mirip, periksa kode, nama, tanggal lahir, satuan, lokasi, nomor kunjungan, nomor resep, nomor faktur, atau atribut pembeda lain. Setelah mengisi form, baca kembali dari atas ke bawah. Koreksi kesalahan sebelum menyimpan karena pembatalan setelah posting dapat memerlukan kewenangan supervisor dan meninggalkan jejak audit.

CARA PAKAI LANGKAH DEMI LANGKAH

Pertama, buka menu dari beranda dan pastikan judulnya $title. Kedua, tentukan konteks kerja seperti pasien, resep, lokasi, periode, pemasok, atau transaksi sesuai kebutuhan. Ketiga, lakukan pencarian dan pilih hanya hasil yang identitasnya sudah diverifikasi. Keempat, lengkapi kolom wajib; jangan menggunakan tanda sembarang untuk melewati validasi. Kelima, periksa kuantitas, satuan, harga, diskon, penjamin, metode pembayaran, tanggal, serta catatan. Keenam, baca peringatan server. Ketujuh, minta verifikasi petugas kedua bila SOP mewajibkan. Kedelapan, tekan aksi utama satu kali dan tunggu. Kesembilan, catat nomor hasil atau cetak bukti bila tersedia. Kesepuluh, buka kembali laporan atau riwayat untuk memastikan hasil sudah tercatat sebagaimana dimaksud.

CONTOH PENGGUNAAN

$scenario. Dalam contoh tersebut petugas tidak langsung menekan Simpan. Petugas lebih dahulu mencocokkan sumber data, mengecek hak akses, meninjau seluruh rincian, lalu menunggu respons berhasil. Bila pasien atau pelanggan meminta perubahan setelah proses selesai, petugas tidak mengubah data secara diam-diam. Gunakan mekanisme koreksi, retur, pembatalan, atau penyesuaian resmi yang tersedia sehingga jejak awal dan alasan perubahan tetap dapat ditelusuri. Pendekatan ini melindungi pasien, petugas, persediaan, kas, dan laporan organisasi.

VALIDASI DAN KONTROL KEAMANAN

Kontrol terpenting pada menu ini adalah $control. Selain itu, sistem menerapkan hak akses berbasis role. Ketiadaan tombol biasanya berarti role belum diizinkan, bukan kerusakan tampilan. Jangan meminta akun orang lain untuk melewati pembatasan. Data sensitif hanya boleh dibuka untuk tujuan pekerjaan. Sebelum meninggalkan meja, selesaikan proses yang sedang berjalan dan kunci perangkat. Hindari tangkapan layar yang memuat identitas pasien. Bila bukti harus dikirim untuk dukungan teknis, samarkan nama, nomor identitas, alamat, nomor telepon, dan informasi medis kecuali kanal serta kewenangannya telah ditetapkan.

PENANGANAN PERINGATAN DAN KESALAHAN

Jika muncul pesan data tidak ditemukan, periksa ejaan, periode, lokasi, serta apakah data sumber memang sudah dibuat pada modul sebelumnya. Jika akses ditolak, catat nama menu dan minta administrator meninjau role; jangan mencoba memanipulasi alamat atau payload. Jika stok atau batch tidak cukup, hentikan pelayanan item tersebut dan ikuti prosedur substitusi atau pengadaan, bukan memaksa angka. Jika jaringan terputus setelah menekan simpan, jangan mengulang sebelum memeriksa riwayat. Jika angka laporan berbeda, samakan periode, zona waktu, status transaksi, lokasi, dan filter. Simpan pesan kesalahan lengkap beserta waktu kejadian untuk petugas dukungan tanpa menyertakan rahasia akun.

PEMERIKSAAN SETELAH PROSES

Sesudah berhasil, cocokkan nomor referensi, waktu, nama operator, nilai, status, dan rincian item. Untuk proses persediaan, bandingkan perubahan dengan kartu stok dan dokumen fisik. Untuk pembayaran, cocokkan total dengan kas, mesin pembayaran, atau bukti transfer. Untuk pendaftaran, pastikan kunjungan masuk ke antrean atau unit yang benar. Untuk laporan, pastikan filter tertulis pada hasil dan pahami bahwa laporan mencerminkan data yang sudah diposting. Laporkan selisih pada hari yang sama agar penelusuran lebih mudah. Jangan menghapus dokumen sumber sebelum masa retensi organisasi berakhir.

PENGAWASAN HARIAN DAN SERAH TERIMA

Pada awal shift, petugas memeriksa koneksi, konteks lokasi, perangkat pendukung, saldo atau status awal yang relevan, dan transaksi tertunda dari shift sebelumnya. Selama shift, petugas menjaga urutan nomor, memeriksa peringatan, serta memisahkan pekerjaan yang belum lengkap. Pada akhir shift, petugas meninjau transaksi berhasil, gagal, batal, retur, atau koreksi; membandingkan bukti fisik dengan sistem; kemudian menyerahkan masalah terbuka secara tertulis. Supervisor meninjau pengecualian, aktivitas bernilai besar, perubahan master, dan penggunaan kewenangan khusus. Jejak audit tidak boleh dibersihkan untuk membuat laporan tampak cocok.

PRAKTIK YANG HARUS DIHINDARI

Jangan memilih pasien atau item hanya karena berada di urutan pertama. Jangan mengubah tanggal agar masuk ke periode laporan tertentu. Jangan membagi satu kejadian menjadi beberapa transaksi untuk menghindari batas otorisasi. Jangan memakai catatan bebas untuk menyimpan kata sandi atau data kartu pembayaran. Jangan menutup aplikasi saat indikator proses masih aktif. Jangan menganggap warna hijau cukup tanpa membaca nomor hasil. Jangan mengabaikan peringatan kedaluwarsa, LASA, obat terkendali, duplikasi, penjamin tidak aktif, atau ketidaksesuaian nilai. Jangan melakukan koreksi langsung di basis data; gunakan fungsi aplikasi yang sah.

RINGKASAN CEPAT

Urutan aman selalu sama: siapkan dokumen, pastikan konteks, cari data, verifikasi identitas, isi rincian, tinjau peringatan, simpan satu kali, periksa hasil, dan dokumentasikan pengecualian. Gunakan diagram workflow di atas sebagai pengingat, sedangkan bagian rinci ini sebagai acuan pelaksanaan. Bila kondisi nyata tidak tercakup, hentikan proses pada titik aman dan minta keputusan supervisor atau tenaga klinis berwenang. Kecepatan pelayanan penting, tetapi ketepatan identitas, keselamatan pasien, keutuhan stok, kebenaran kas, perlindungan data, dan jejak audit selalu lebih utama.

$narasiPanduanOperasionalUmum
''';
}

class PosHelpCatalog {
  static const specs = <String, PosHelpSpec>{
    'apotik_kasir': PosHelpSpec(
        'apotik_kasir',
        'Kasir Apotik',
        'melayani penjualan obat nonresep dan menyelesaikan pembayaran secara aman',
        [
          'Identifikasi pembeli',
          'Cari obat',
          'Validasi batch FEFO',
          'Tinjau keranjang',
          'Bayar',
          'Verifikasi bukti'
        ],
        'permintaan pelanggan, identitas bila dibutuhkan, obat yang dipilih, dan metode pembayaran',
        'Sistem memilih batch layak dengan prinsip FEFO, menolak batch kedaluwarsa, menghitung nilai, dan mencatat transaksi',
        'nomor transaksi, rincian obat, total pembayaran, pengurangan stok, dan jejak operator',
        'verifikasi obat benar, pasien benar, dosis atau jumlah wajar, batch valid, serta total pembayaran sesuai',
        'Seorang pelanggan membeli dua obat bebas; petugas mencari kode, membandingkan nama dan satuan, memeriksa batch, mengonfirmasi jumlah, menerima pembayaran, lalu mengecek nomor transaksi'),
    'apotik_resep': PosHelpSpec(
        'apotik_resep',
        'Tebus Resep Dokter',
        'mengambil resep menunggu dan menyerahkan obat sesuai instruksi dokter',
        [
          'Cari resep',
          'Cocokkan pasien',
          'Telaah item',
          'Siapkan obat',
          'Validasi farmasis',
          'Bayar dan serahkan'
        ],
        'resep sah, identitas pasien, informasi dokter, alergi atau catatan klinis yang tersedia',
        'Sistem memuat rincian resep, menghubungkan item, memeriksa batch, dan menandai status penebusan',
        'transaksi penebusan, status resep, bukti pembayaran, dan jejak penyerahan obat',
        'kecocokan resep-pasien-dokter, potensi duplikasi, obat terkendali, racikan, LASA, dan batch FEFO',
        'Pasien membawa resep yang sudah terdaftar; petugas mencari kode resep, meminta pasien menyebutkan identitas, mencocokkan seluruh baris, meminta validasi farmasis, lalu memproses pembayaran'),
    'apotik_racikan': PosHelpSpec(
        'apotik_racikan',
        'Racikan',
        'mencatat formula serta proses penyiapan obat racikan secara dapat ditelusuri',
        [
          'Pilih resep',
          'Telaah formula',
          'Hitung kebutuhan',
          'Siapkan bahan',
          'Racik dan periksa',
          'Serahkan'
        ],
        'resep racikan, formula, kekuatan, jumlah, aturan pakai, bahan, dan identitas peracik',
        'Petugas menyalin formula secara akurat, menghitung kebutuhan, mendokumentasikan bahan dan pemeriksaan akhir',
        'catatan racikan, rincian bahan, jumlah hasil, etiket, dan identitas petugas pemeriksa',
        'pemeriksaan ganda formula, perhitungan, kompatibilitas, kebersihan, label, dan kewenangan farmasis',
        'Farmasis menerima resep puyer; formula diverifikasi, kebutuhan tiap bahan dihitung ulang, bahan ditimbang, hasil diperiksa petugas kedua, kemudian etiket dan aturan pakai dikonfirmasi kepada pasien'),
    'apotik_formularium': PosHelpSpec(
        'apotik_formularium',
        'Formularium & Obat',
        'memelihara profil obat, golongan, penanda LASA, harga, dan informasi operasional',
        [
          'Cari item',
          'Verifikasi master',
          'Ubah profil',
          'Tinjau dampak',
          'Simpan',
          'Audit perubahan'
        ],
        'kode dan nama obat, satuan, golongan, harga, serta kebijakan formularium yang disahkan',
        'Sistem memperbarui profil apotik yang dipakai oleh pencarian, kasir, validasi, dan laporan',
        'master obat yang konsisten dan riwayat perubahan profil',
        'otorisasi perubahan master, validasi golongan, penanda LASA, satuan, harga, dan larangan duplikasi',
        'Supervisor menerima keputusan komite formularium; ia mencari item dengan kode, memastikan bukan item serupa, memperbarui golongan dan LASA, lalu menguji tampilannya pada kasir'),
    'apotik_batch': PosHelpSpec(
        'apotik_batch',
        'Batch & Kedaluwarsa',
        'memantau sisa batch dan memprioritaskan tindak lanjut obat yang mendekati kedaluwarsa',
        [
          'Tentukan horizon',
          'Muat batch',
          'Urutkan risiko',
          'Verifikasi fisik',
          'Tindak lanjuti',
          'Dokumentasikan'
        ],
        'periode hari ke depan, lokasi, data penerimaan, dan hasil pemeriksaan fisik',
        'Sistem menghitung sisa batch sesudah konsumsi dan mengurutkan tanggal terdekat',
        'daftar batch aktif, segera kedaluwarsa, kedaluwarsa, sisa, dan nilai risiko',
        'pencocokan fisik, karantina produk kedaluwarsa, FEFO, dan larangan penjualan batch tidak layak',
        'Petugas memilih horizon sembilan puluh hari, mencetak daftar, memeriksa rak, memisahkan produk kedaluwarsa, memberi tanda tindak lanjut, dan melaporkan selisih'),
    'apotik_pengadaan': PosHelpSpec(
        'apotik_pengadaan',
        'Pengadaan / PBF',
        'mencatat penerimaan obat dari pemasok resmi lengkap dengan jumlah, harga, dan kedaluwarsa',
        [
          'Terima dokumen',
          'Pilih item',
          'Periksa fisik',
          'Isi jumlah dan ED',
          'Simpan penerimaan',
          'Rekonsiliasi stok'
        ],
        'faktur atau surat jalan PBF, obat fisik, nomor referensi, harga, jumlah, lokasi, batch, dan tanggal kedaluwarsa',
        'Sistem mencatat stok masuk dan membentuk data batch yang akan dipakai kasir',
        'dokumen penerimaan, kenaikan stok, batch baru, nilai pembelian, dan jejak pemasok',
        'pemasok sah, kesesuaian pesanan-faktur-fisik, kondisi kemasan, suhu, batch, ED, harga, dan duplikasi nomor faktur',
        'Barang datang dari PBF; petugas mencocokkan surat jalan, menghitung kemasan, menolak kemasan rusak, memasukkan ED tiap item, menyimpan sekali, lalu membandingkan kartu stok'),
    'apotik_stok_opname': PosHelpSpec(
        'apotik_stok_opname',
        'Stok Opname Apotik',
        'menyesuaikan stok sistem berdasarkan penghitungan fisik yang sah dan terdokumentasi',
        [
          'Bekukan pergerakan',
          'Hitung fisik',
          'Bandingkan sistem',
          'Teliti selisih',
          'Simpan penyesuaian',
          'Setujui laporan'
        ],
        'lembar hitung fisik, lokasi, item, jumlah sistem, jumlah fisik, alasan selisih, dan persetujuan',
        'Sistem menghitung perbedaan lalu menulis penyesuaian stok dengan jejak operator',
        'saldo stok terkoreksi, daftar selisih, alasan, waktu, dan referensi opname',
        'pemisahan penghitung dan penyetuju, hitung ulang selisih besar, larangan menutup kehilangan tanpa investigasi',
        'Tim menghentikan pergerakan rak, dua petugas menghitung, supervisor membandingkan angka, selisih dihitung ulang, alasan dicatat, lalu penyesuaian disimpan'),
    'apotik_retur': PosHelpSpec(
        'apotik_retur',
        'Retur Obat',
        'mencatat pengembalian dari pembeli atau pengembalian ke PBF dengan arah stok yang tepat',
        [
          'Identifikasi transaksi',
          'Pilih jenis retur',
          'Periksa kelayakan',
          'Isi item dan alasan',
          'Otorisasi',
          'Simpan dan verifikasi'
        ],
        'referensi transaksi atau faktur, item, jumlah, kondisi barang, pihak asal atau tujuan, dan alasan retur',
        'Sistem menambah stok untuk retur penjualan yang layak atau mengurangi stok untuk retur ke PBF',
        'dokumen retur, mutasi stok, nilai koreksi, alasan, dan jejak persetujuan',
        'arah retur benar, barang dapat diterima kembali, jumlah tidak melebihi sumber, dan obat tertentu tidak kembali ke stok jual',
        'Pelanggan mengembalikan obat sesuai kebijakan; petugas mencari transaksi, memeriksa segel dan kondisi, meminta persetujuan, memilih retur masuk, lalu memastikan mutasi stok benar'),
    'apotik_narkotika': PosHelpSpec(
        'apotik_narkotika',
        'Obat Terkendali',
        'meninjau register narkotika dan psikotropika beserta pihak, dokter, jumlah, dan waktu',
        [
          'Pilih periode',
          'Muat register',
          'Periksa kelengkapan',
          'Cocokkan dokumen',
          'Investigasi selisih',
          'Arsipkan laporan'
        ],
        'periode, golongan obat, resep, identitas pembeli, alamat, dokter, jumlah, dan dokumen wajib',
        'Sistem membaca jejak penyerahan obat terkendali yang dibuat saat transaksi',
        'register kronologis dengan obat, golongan, jumlah, pihak, dokter, operator, dan keterangan',
        'akses terbatas, kelengkapan identitas, resep sah, rekonsiliasi stok, serta pelaporan menurut regulasi',
        'Apoteker penanggung jawab memilih periode bulanan, mencocokkan setiap baris dengan resep fisik dan kartu stok, meneliti selisih, kemudian mengarsipkan hasil'),
    'apotik_laporan': PosHelpSpec(
        'apotik_laporan',
        'Laporan Apotik',
        'menganalisis penjualan, pergerakan obat, dan risiko kedaluwarsa untuk pengawasan',
        [
          'Tentukan tujuan',
          'Pilih periode',
          'Muat data',
          'Validasi filter',
          'Analisis',
          'Ekspor atau tindak lanjut'
        ],
        'periode, lokasi, jenis laporan, horizon kedaluwarsa, dan kebutuhan analisis',
        'Sistem mengagregasi transaksi yang sudah diposting dan menampilkan kuantitas, nilai, golongan, atau batch',
        'indikator penjualan, rincian per obat, register, kedaluwarsa, dan dasar tindak lanjut',
        'periode konsisten, status transaksi, lokasi, cutoff, rekonsiliasi kas dan stok, serta pemisahan laporan dari data operasional mentah',
        'Supervisor memilih periode shift, membandingkan total dengan penerimaan kas, meninjau obat terlaris dan batch berisiko, lalu mencatat tindak lanjut'),
    'emedik_kasir': PosHelpSpec(
        'emedik_kasir',
        'Kasir Layanan Medis',
        'menyelesaikan pembayaran tagihan layanan dan tindakan pasien',
        [
          'Cari kunjungan',
          'Verifikasi pasien',
          'Telaah tagihan',
          'Terapkan penjamin',
          'Terima pembayaran',
          'Terbitkan bukti'
        ],
        'nomor kunjungan, identitas pasien, rincian layanan, penjamin, deposit, dan metode pembayaran',
        'Sistem menghitung kewajiban pasien sesudah penjamin atau deposit dan mencatat pembayaran',
        'status tagihan, bukti pembayaran, saldo tersisa, pemakaian deposit, dan jejak kasir',
        'pasien dan kunjungan benar, layanan sudah disahkan, penjamin aktif, alokasi pembayaran, serta larangan pembayaran ganda',
        'Pasien selesai berobat; kasir mencari nomor kunjungan, mencocokkan identitas, menjelaskan rincian, menerapkan penjamin, menerima pembayaran, dan memastikan status lunas'),
    'emedik_pendaftaran': PosHelpSpec(
        'emedik_pendaftaran',
        'Pendaftaran Pasien',
        'membuat booking atau kunjungan rawat jalan, rawat inap, maupun UGD secara tepat',
        [
          'Identifikasi pasien',
          'Pilih jenis layanan',
          'Lengkapi data',
          'Pilih unit dan jadwal',
          'Validasi',
          'Daftarkan'
        ],
        'identitas pasien, nomor rekam medis bila ada, kontak, penjamin, rujukan, unit tujuan, dokter, dan jadwal',
        'Sistem mencari pasien lama atau membuat hubungan pendaftaran lalu menghasilkan kunjungan',
        'nomor booking atau kunjungan, unit tujuan, jadwal, penjamin, dan status antrean',
        'pencegahan pasien ganda, verifikasi dua identitas, kegawatan UGD, rujukan, hak penjamin, dan persetujuan privasi',
        'Pasien rawat jalan datang membawa identitas; petugas mencari rekam medis, mengonfirmasi tanggal lahir, memilih poli dan dokter, memeriksa penjamin, lalu mencetak nomor kunjungan'),
    'emedik_tagihan': PosHelpSpec(
        'emedik_tagihan',
        'Tagihan Kunjungan',
        'meninjau status seluruh komponen biaya pada satu kunjungan pasien',
        [
          'Cari kunjungan',
          'Verifikasi pasien',
          'Telaah komponen',
          'Periksa status',
          'Koreksi melalui sumber',
          'Konfirmasi tagihan'
        ],
        'nomor kunjungan, identitas pasien, layanan, tindakan, obat, kamar, diskon, penjamin, dan pembayaran',
        'Sistem menggabungkan komponen biaya yang sudah diposting dari unit pelayanan',
        'rincian tagihan, nilai bruto, penjamin, pembayaran, saldo, dan status',
        'larangan mengubah layanan tanpa sumber klinis, pencegahan duplikasi, cutoff, otorisasi diskon, dan rekonsiliasi',
        'Kasir menerima pertanyaan pasien; nomor kunjungan dicari, setiap tindakan dijelaskan, komponen ganda ditelusuri ke unit sumber, kemudian tagihan dikonfirmasi'),
    'emedik_deposit': PosHelpSpec(
        'emedik_deposit',
        'Deposit Pasien',
        'menerima, menggunakan, dan memantau uang muka pasien secara dapat ditelusuri',
        [
          'Cari pasien',
          'Periksa saldo',
          'Pilih penerimaan atau penggunaan',
          'Isi nilai',
          'Otorisasi',
          'Simpan dan cetak'
        ],
        'identitas pasien, nomor kunjungan, nilai deposit, metode pembayaran, referensi, tujuan penggunaan, dan bukti',
        'Sistem menambah atau mengalokasikan saldo deposit serta mencatat mutasi',
        'saldo deposit, riwayat mutasi, bukti penerimaan atau penggunaan, dan operator',
        'identitas pasien, pemisahan uang antar pasien, larangan saldo negatif, otorisasi pengembalian, dan rekonsiliasi kas',
        'Keluarga pasien rawat inap menyerahkan uang muka; kasir mencari pasien dengan dua identitas, menerima dana, mencetak bukti, lalu memeriksa saldo pada riwayat'),
    'emedik_penjamin': PosHelpSpec(
        'emedik_penjamin',
        'Penjamin & Asuransi',
        'memelihara dan menggunakan informasi penjamin untuk menentukan tanggungan layanan',
        [
          'Pilih penjamin',
          'Verifikasi kepesertaan',
          'Periksa manfaat',
          'Hubungkan kunjungan',
          'Catat otorisasi',
          'Pantau klaim'
        ],
        'identitas peserta, penjamin, nomor polis atau peserta, masa aktif, kelas, manfaat, rujukan, dan nomor otorisasi',
        'Sistem menghubungkan penjamin dengan pasien atau kunjungan dan membantu perhitungan tanggungan',
        'status penjamin, porsi tanggungan, kewajiban pasien, referensi otorisasi, dan dasar klaim',
        'validitas kepesertaan, manfaat, pengecualian, kelas, rujukan, plafon, otorisasi, dan perlindungan data',
        'Petugas memverifikasi kartu asuransi melalui kanal resmi, mencocokkan identitas dan masa aktif, merekam nomor otorisasi, lalu menghubungkannya ke kunjungan'),
    'emedik_laporan': PosHelpSpec(
        'emedik_laporan',
        'Laporan Kasir Medis',
        'memantau kunjungan, status pembayaran, penerimaan, dan saldo tagihan layanan medis',
        [
          'Tentukan periode',
          'Pilih jenis laporan',
          'Terapkan filter',
          'Muat hasil',
          'Rekonsiliasi',
          'Tindak lanjuti'
        ],
        'periode, unit, kasir, penjamin, status kunjungan, status pembayaran, dan kebutuhan rekonsiliasi',
        'Sistem mengagregasi pendaftaran dan transaksi medis yang sudah tercatat',
        'jumlah kunjungan, tagihan, pembayaran, piutang, rincian pasien sesuai kewenangan, dan pengecualian',
        'cutoff shift, pembatalan, refund, deposit, penjamin, transaksi tertunda, serta pembatasan ekspor data pasien',
        'Supervisor menutup shift dengan memilih periode dan kasir, membandingkan penerimaan dengan kas, meneliti tagihan belum lunas, lalu mendokumentasikan selisih'),
  };
}

class PosHelp {
  static Future<void> open(BuildContext context, String keyName) async {
    final spec = PosHelpCatalog.specs[keyName];
    if (spec == null) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PosHelpScreen(spec: spec)));
  }

  static Widget button(BuildContext context, String keyName,
          {bool compact = false}) =>
      compact
          ? IconButton(
              tooltip: 'Bantuan rinci',
              icon: const Icon(Icons.help_outline),
              onPressed: () => open(context, keyName))
          : FilledButton.tonalIcon(
              onPressed: () => open(context, keyName),
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Bantuan'));
}

class PosHelpScreen extends StatelessWidget {
  final PosHelpSpec spec;
  const PosHelpScreen({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    final paragraphs = spec.narrative.trim().split(RegExp(r'\n\s*\n'));
    return Scaffold(
      appBar: AppBar(title: Text('Bantuan — ${spec.title}')),
      body: SelectionArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                  spec.isEmedik
                      ? 'assets/images/help/emedik-workflow.png'
                      : 'assets/images/help/apotik-workflow.png',
                  fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 18),
          Text('Diagram workflow',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _WorkflowDiagram(steps: spec.flow),
          const SizedBox(height: 20),
          ...paragraphs.map((p) {
            final heading = !p.contains('\n') && p == p.toUpperCase();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(p,
                  style: heading
                      ? Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w800)
                      : const TextStyle(fontSize: 15, height: 1.65)),
            );
          }),
        ]),
      ),
    );
  }
}

class _WorkflowDiagram extends StatelessWidget {
  final List<String> steps;
  const _WorkflowDiagram({required this.steps});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final vertical = box.maxWidth < 700;
        final widgets = <Widget>[];
        for (var i = 0; i < steps.length; i++) {
          widgets.add(Container(
            constraints: const BoxConstraints(minWidth: 130),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.primary),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 13, child: Text('${i + 1}')),
              const SizedBox(height: 7),
              Text(steps[i],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ));
          if (i < steps.length - 1) {
            widgets.add(Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                    vertical ? Icons.arrow_downward : Icons.arrow_forward,
                    color: AppColors.primary)));
          }
        }
        return vertical
            ? Column(children: widgets)
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: widgets));
      });
}
