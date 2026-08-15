import 'bantuan_content.dart';

class SpesifikasiBantuanMenu {
  final String judul;
  final String tujuan;
  final List<String> workflow;
  final List<String> ilustrasi;
  final String objekUtama;
  final String hasilAkhir;

  const SpesifikasiBantuanMenu({
    required this.judul,
    required this.tujuan,
    required this.workflow,
    required this.ilustrasi,
    required this.objekUtama,
    required this.hasilAkhir,
  });
}

const spesifikasiBantuanMenu = <String, SpesifikasiBantuanMenu>{
  'kasir': SpesifikasiBantuanMenu(
      judul: 'Kasir/POS',
      tujuan:
          'memproses penjualan dari pemindaian barang sampai pembayaran dan struk',
      workflow: [
        'Buka sesi kas',
        'Scan atau cari produk',
        'Periksa keranjang',
        'Pilih pelanggan dan promo',
        'Terima pembayaran',
        'Cetak struk'
      ],
      ilustrasi: [
        'Status sesi dan toko',
        'Pencarian serta katalog',
        'Keranjang belanja',
        'Ringkasan total',
        'Panel pembayaran'
      ],
      objekUtama: 'keranjang dan transaksi penjualan',
      hasilAkhir:
          'transaksi lunas, stok berkurang, kas tercatat, dan struk tersedia'),
  'ringkasan': SpesifikasiBantuanMenu(
      judul: 'Dashboard',
      tujuan:
          'membaca indikator operasional, tren penjualan, produk, pelanggan, promo, dan kepatuhan',
      workflow: [
        'Pilih periode',
        'Muat indikator',
        'Bandingkan target',
        'Buka rincian',
        'Identifikasi anomali',
        'Tindak lanjuti'
      ],
      ilustrasi: [
        'Filter periode',
        'Kartu KPI',
        'Grafik tren',
        'Daftar peringkat',
        'Panel tindak lanjut'
      ],
      objekUtama: 'indikator dan agregat bisnis',
      hasilAkhir: 'keputusan operasional yang didukung data'),
  'pesanan': SpesifikasiBantuanMenu(
      judul: 'Pesanan',
      tujuan:
          'mengelola pesanan baru, antrean produksi, penyerahan, dan status penyelesaian',
      workflow: [
        'Terima pesanan',
        'Verifikasi isi',
        'Konfirmasi pembayaran',
        'Proses pesanan',
        'Serahkan',
        'Tutup status'
      ],
      ilustrasi: [
        'Filter status',
        'Daftar antrean',
        'Detail item',
        'Identitas pelanggan',
        'Tombol perubahan status'
      ],
      objekUtama: 'pesanan pelanggan',
      hasilAkhir: 'pesanan selesai dan seluruh perubahan status tercatat'),
  'anggota': SpesifikasiBantuanMenu(
      judul: 'Pelanggan/Anggota',
      tujuan:
          'mengelola identitas anggota, tipe, tabungan, hutang, top-up, dan histori hubungan pelanggan',
      workflow: [
        'Cari anggota',
        'Verifikasi identitas',
        'Pilih tab data',
        'Tambah atau koreksi data',
        'Validasi saldo',
        'Simpan dan audit'
      ],
      ilustrasi: [
        'Tab anggota',
        'Pencarian identitas',
        'Form data pribadi',
        'Rekap saldo',
        'Buku mutasi'
      ],
      objekUtama: 'profil dan rekening anggota',
      hasilAkhir: 'data anggota serta saldo yang akurat dan dapat ditelusuri'),
  'produk': SpesifikasiBantuanMenu(
      judul: 'Produk',
      tujuan:
          'mengelola katalog, barcode, harga, stok, impor Accurate, status aktif, dan atribut penjualan',
      workflow: [
        'Cari produk',
        'Periksa duplikasi',
        'Isi atribut',
        'Atur harga dan stok',
        'Validasi preview',
        'Simpan atau impor'
      ],
      ilustrasi: [
        'Toolbar produk',
        'Filter katalog',
        'Tabel produk',
        'Form editor',
        'Preview impor'
      ],
      objekUtama: 'master produk',
      hasilAkhir: 'katalog siap dipakai konsisten pada kasir dan laporan'),
  'jenisProduk': SpesifikasiBantuanMenu(
      judul: 'Jenis Produk',
      tujuan:
          'menyusun kategori produk untuk pencarian, pelaporan, dan pengaturan katalog',
      workflow: [
        'Lihat kategori',
        'Tambah jenis',
        'Beri nama jelas',
        'Atur status',
        'Simpan',
        'Periksa produk terkait'
      ],
      ilustrasi: [
        'Daftar kategori',
        'Pencarian',
        'Form jenis',
        'Status aktif',
        'Aksi edit'
      ],
      objekUtama: 'kategori atau jenis produk',
      hasilAkhir: 'pengelompokan produk yang konsisten'),
  'stokOpname': SpesifikasiBantuanMenu(
      judul: 'Stok Opname',
      tujuan:
          'merekonsiliasi stok sistem dengan hasil hitung fisik melalui input atau pemindaian',
      workflow: [
        'Mulai sesi',
        'Scan produk',
        'Baca stok sistem',
        'Hitung fisik',
        'Catat selisih',
        'Selesaikan sesi'
      ],
      ilustrasi: [
        'Status sesi opname',
        'Input barcode',
        'Informasi produk',
        'Stok sistem dan fisik',
        'Riwayat selisih'
      ],
      objekUtama: 'hasil hitung fisik produk',
      hasilAkhir: 'stok sistem terkoreksi dengan jejak opname'),
  'kedaluwarsa': SpesifikasiBantuanMenu(
      judul: 'Kedaluwarsa',
      tujuan:
          'mengontrol batch, tanggal kedaluwarsa, FEFO, karantina, dan pemusnahan',
      workflow: [
        'Pilih produk',
        'Catat batch',
        'Isi tanggal',
        'Pantau sisa hari',
        'Karantina bila perlu',
        'Jual dengan FEFO'
      ],
      ilustrasi: [
        'Kartu risiko',
        'Filter waktu',
        'Tabel batch',
        'Editor tanggal dan stok',
        'Status karantina'
      ],
      objekUtama: 'batch atau lot produk',
      hasilAkhir: 'barang terjual menurut FEFO dan barang berisiko dipisahkan'),
  'mutasiAntarOutlet': SpesifikasiBantuanMenu(
      judul: 'Mutasi Antar Outlet',
      tujuan:
          'memindahkan stok dan batch dari outlet asal ke outlet tujuan secara terkendali',
      workflow: [
        'Pilih outlet asal',
        'Pilih produk',
        'Pilih tujuan',
        'Isi jumlah',
        'Konfirmasi batch FEFO',
        'Simpan transfer'
      ],
      ilustrasi: [
        'Outlet asal',
        'Produk dan stok',
        'Outlet tujuan',
        'Jumlah transfer',
        'Riwayat mutasi'
      ],
      objekUtama: 'transfer stok antar-outlet',
      hasilAkhir: 'stok asal dan tujuan berubah seimbang'),
  'kulakan': SpesifikasiBantuanMenu(
      judul: 'Kulakan',
      tujuan:
          'mencatat faktur pembelian, supplier, barang masuk, harga modal, batch, dan kedaluwarsa',
      workflow: [
        'Isi faktur',
        'Pilih supplier',
        'Scan produk',
        'Isi jumlah dan harga',
        'Catat batch',
        'Simpan penerimaan'
      ],
      ilustrasi: [
        'Header faktur',
        'Picker supplier',
        'Input produk',
        'Batch dan tanggal',
        'Daftar barang faktur'
      ],
      objekUtama: 'faktur pengadaan dan barang masuk',
      hasilAkhir: 'stok bertambah dan nilai pembelian tercatat'),
  'penyedia': SpesifikasiBantuanMenu(
      judul: 'Supplier (Penyedia)',
      tujuan:
          'mengelola identitas pemasok dan informasi kontak untuk proses pengadaan',
      workflow: [
        'Cari supplier',
        'Periksa identitas',
        'Isi kontak',
        'Simpan',
        'Gunakan di kulakan',
        'Tinjau riwayat'
      ],
      ilustrasi: [
        'Pencarian supplier',
        'Daftar pemasok',
        'Form identitas',
        'Kontak',
        'Aksi edit'
      ],
      objekUtama: 'master supplier',
      hasilAkhir: 'pemasok dapat dipilih secara konsisten pada pengadaan'),
  'diskon': SpesifikasiBantuanMenu(
      judul: 'Aturan Diskon',
      tujuan:
          'membuat promo yang terukur berdasarkan periode, produk, pelanggan, kuantitas, dan metode bayar',
      workflow: [
        'Tentukan tujuan promo',
        'Pilih sasaran',
        'Isi syarat',
        'Atur periode',
        'Uji simulasi',
        'Aktifkan'
      ],
      ilustrasi: [
        'Daftar aturan',
        'Periode promo',
        'Syarat transaksi',
        'Nilai diskon',
        'Status aktif'
      ],
      objekUtama: 'aturan promo dan diskon',
      hasilAkhir:
          'diskon diterapkan hanya pada transaksi yang memenuhi syarat'),
  'caraBayar': SpesifikasiBantuanMenu(
      judul: 'Cara Pembayaran',
      tujuan:
          'mengatur metode tunai, non-tunai, hutang, saldo, dan perilaku pencatatan kas',
      workflow: [
        'Pilih metode',
        'Isi nama dan tipe',
        'Atur efek kas',
        'Atur hutang/saldo',
        'Aktifkan',
        'Uji transaksi'
      ],
      ilustrasi: [
        'Daftar metode',
        'Jenis pembayaran',
        'Konfigurasi kas',
        'Status aktif',
        'Preview kasir'
      ],
      objekUtama: 'metode pembayaran',
      hasilAkhir: 'pembayaran masuk ke akun dan laporan yang benar'),
  'returPenjualan': SpesifikasiBantuanMenu(
      judul: 'Retur Penjualan',
      tujuan:
          'membalik sebagian atau seluruh penjualan dengan referensi dan alasan yang sah',
      workflow: [
        'Cari transaksi',
        'Pilih item',
        'Isi jumlah retur',
        'Tentukan kondisi barang',
        'Konfirmasi pengembalian',
        'Simpan dokumen balik'
      ],
      ilustrasi: [
        'Pencarian struk',
        'Detail transaksi',
        'Item retur',
        'Alasan dan kondisi',
        'Ringkasan dampak'
      ],
      objekUtama: 'dokumen retur pelanggan',
      hasilAkhir:
          'stok, kas, dan riwayat terkoreksi tanpa menghapus transaksi asli'),
  'riwayatPenjualan': SpesifikasiBantuanMenu(
      judul: 'Riwayat Penjualan',
      tujuan:
          'menelusuri transaksi, mencetak ulang, memeriksa pembayaran, membuka rincian, dan menemukan perbedaan total master dengan rincian',
      workflow: [
        'Pilih periode',
        'Cari transaksi',
        'Aktifkan Transaksi tidak valid bila perlu',
        'Buka detail',
        'Cocokkan total master dan rincian',
        'Cetak ulang bila perlu',
        'Ekspor'
      ],
      ilustrasi: [
        'Filter periode',
        'Pencarian nomor',
        'Checkbox transaksi tidak valid',
        'Tabel transaksi',
        'Detail item',
        'Aksi cetak'
      ],
      objekUtama: 'riwayat transaksi penjualan',
      hasilAkhir: 'bukti transaksi ditemukan dan diverifikasi'),
  'laporanTransaksi': SpesifikasiBantuanMenu(
      judul: 'Laporan Transaksi',
      tujuan:
          'menganalisis transaksi menurut periode, kasir, toko, pelanggan, dan metode pembayaran',
      workflow: [
        'Tentukan periode',
        'Pilih filter',
        'Muat laporan',
        'Periksa total',
        'Buka rincian',
        'Ekspor'
      ],
      ilustrasi: [
        'Filter laporan',
        'Kartu total',
        'Tabel transaksi',
        'Paginasi',
        'Tombol ekspor'
      ],
      objekUtama: 'laporan transaksi terfilter',
      hasilAkhir: 'rekap yang siap direkonsiliasi atau dianalisis'),
  'laporanLaporan': SpesifikasiBantuanMenu(
      judul: 'Laporan-Laporan',
      tujuan:
          'memilih dan menghasilkan berbagai laporan operasional serta manajerial',
      workflow: [
        'Pilih kelompok',
        'Pilih laporan',
        'Isi parameter',
        'Jalankan',
        'Validasi angka',
        'Cetak atau ekspor'
      ],
      ilustrasi: [
        'Katalog laporan',
        'Parameter',
        'Preview',
        'Tabel hasil',
        'Ekspor'
      ],
      objekUtama: 'dokumen laporan',
      hasilAkhir: 'informasi terstruktur untuk pengawasan dan keputusan'),
  'laporanKeuangan': SpesifikasiBantuanMenu(
      judul: 'Laporan Keuangan',
      tujuan:
          'membaca neraca, laba rugi, arus kas, buku besar, piutang, dan posisi keuangan',
      workflow: [
        'Pilih entitas',
        'Pilih periode',
        'Jalankan laporan',
        'Telusuri akun',
        'Rekonsiliasi',
        'Finalisasi'
      ],
      ilustrasi: [
        'Filter entitas',
        'Periode akuntansi',
        'Ringkasan akun',
        'Drill-down buku besar',
        'Ekspor'
      ],
      objekUtama: 'saldo dan laporan keuangan',
      hasilAkhir: 'laporan yang seimbang dan dapat dipertanggungjawabkan'),
  'riwayatSinkron': SpesifikasiBantuanMenu(
      judul: 'Riwayat Sinkronisasi',
      tujuan:
          'memantau antrean offline, status pengiriman, kegagalan, dan percobaan ulang',
      workflow: [
        'Lihat antrean',
        'Periksa status',
        'Baca pesan gagal',
        'Perbaiki penyebab',
        'Kirim ulang',
        'Cocokkan server'
      ],
      ilustrasi: [
        'Indikator koneksi',
        'Antrean lokal',
        'Status per item',
        'Detail error',
        'Aksi sinkron'
      ],
      objekUtama: 'antrean sinkronisasi',
      hasilAkhir: 'seluruh transaksi lokal diterima server tepat satu kali'),
  'logError': SpesifikasiBantuanMenu(
      judul: 'Log Error',
      tujuan:
          'mendiagnosis gangguan aplikasi melalui pesan, konteks, perangkat, dan waktu kejadian',
      workflow: [
        'Pilih periode',
        'Cari error',
        'Buka detail',
        'Kelompokkan penyebab',
        'Kirim bukti',
        'Tandai selesai'
      ],
      ilustrasi: [
        'Filter error',
        'Daftar kejadian',
        'Stack atau pesan',
        'Informasi perangkat',
        'Aksi laporan'
      ],
      objekUtama: 'catatan kesalahan aplikasi',
      hasilAkhir: 'diagnosis yang memiliki bukti cukup untuk ditindaklanjuti'),
  'konfigurasi': SpesifikasiBantuanMenu(
      judul: 'Konfigurasi',
      tujuan:
          'mengatur server, perangkat, printer, update, tampilan, dan perilaku aplikasi',
      workflow: [
        'Pilih kelompok',
        'Baca nilai lama',
        'Ubah seperlunya',
        'Uji koneksi/perangkat',
        'Simpan',
        'Mulai ulang bila diminta'
      ],
      ilustrasi: [
        'Kelompok pengaturan',
        'Alamat server',
        'Printer dan scanner',
        'Auto update',
        'Tombol simpan'
      ],
      objekUtama: 'konfigurasi aplikasi',
      hasilAkhir: 'aplikasi beroperasi sesuai perangkat dan kebijakan toko'),
  'layarPelanggan': SpesifikasiBantuanMenu(
      judul: 'Layar Pelanggan',
      tujuan:
          'menampilkan keranjang, promo, total, dan status pembayaran pada layar kedua',
      workflow: [
        'Pilih monitor',
        'Buka layar',
        'Kirim keranjang',
        'Periksa tampilan',
        'Proses pembayaran',
        'Tutup layar'
      ],
      ilustrasi: [
        'Pemilih monitor',
        'Preview pelanggan',
        'Daftar barang',
        'Total',
        'Status pembayaran'
      ],
      objekUtama: 'tampilan pelanggan',
      hasilAkhir:
          'pelanggan dapat mengonfirmasi belanja tanpa melihat kontrol admin'),
  'hakAkses': SpesifikasiBantuanMenu(
      judul: 'Hak Akses',
      tujuan:
          'mengendalikan menu dan tindakan yang boleh dilakukan setiap role',
      workflow: [
        'Pilih role',
        'Tinjau tanggung jawab',
        'Centang menu',
        'Atur CRUD',
        'Simpan',
        'Uji akun'
      ],
      ilustrasi: [
        'Daftar role',
        'Matriks menu',
        'Hak lihat/tambah/ubah/hapus',
        'Ringkasan perubahan',
        'Tombol simpan'
      ],
      objekUtama: 'role dan izin pengguna',
      hasilAkhir:
          'setiap pengguna hanya dapat menjalankan tugas yang disetujui'),
  'berandaInventorySales': SpesifikasiBantuanMenu(
      judul: 'Beranda Inventory & Sales',
      tujuan:
          'memantau ringkasan distribusi, persediaan, penjualan sales, piutang, hutang, dan kas',
      workflow: [
        'Pilih periode',
        'Baca KPI',
        'Periksa peringatan',
        'Buka modul sumber',
        'Tindak lanjuti',
        'Pantau hasil'
      ],
      ilustrasi: [
        'Kartu KPI',
        'Grafik penjualan',
        'Peringatan stok',
        'Piutang dan hutang',
        'Aktivitas terbaru'
      ],
      objekUtama: 'indikator Inventory & Sales',
      hasilAkhir: 'prioritas kerja distribusi tersusun berdasarkan data'),
  'masterSupplier': SpesifikasiBantuanMenu(
      judul: 'Master Supplier',
      tujuan: 'mengelola pemasok pada alur Inventory & Sales',
      workflow: [
        'Cari pemasok',
        'Isi identitas',
        'Isi termin',
        'Simpan',
        'Gunakan di pembelian',
        'Tinjau saldo'
      ],
      ilustrasi: [
        'Daftar supplier',
        'Form identitas',
        'Kontak',
        'Termin pembayaran',
        'Riwayat'
      ],
      objekUtama: 'supplier distribusi',
      hasilAkhir: 'pembelian dan hutang terhubung ke pemasok yang benar'),
  'masterCustomer': SpesifikasiBantuanMenu(
      judul: 'Master Customer',
      tujuan:
          'mengelola pelanggan distribusi, alamat, kontak, limit, dan termin',
      workflow: [
        'Cari customer',
        'Verifikasi identitas',
        'Isi alamat',
        'Atur limit',
        'Simpan',
        'Gunakan di penjualan'
      ],
      ilustrasi: [
        'Daftar customer',
        'Alamat kirim',
        'Kontak',
        'Limit kredit',
        'Status aktif'
      ],
      objekUtama: 'customer distribusi',
      hasilAkhir: 'penjualan dan piutang terhubung ke pelanggan yang sah'),
  'masterSales': SpesifikasiBantuanMenu(
      judul: 'Master Sales',
      tujuan: 'mengelola petugas sales, wilayah, target, dan penugasan',
      workflow: [
        'Tambah sales',
        'Isi identitas',
        'Tentukan wilayah',
        'Atur target',
        'Aktifkan',
        'Pantau kinerja'
      ],
      ilustrasi: [
        'Daftar sales',
        'Profil petugas',
        'Wilayah',
        'Target',
        'Status'
      ],
      objekUtama: 'petugas dan wilayah sales',
      hasilAkhir: 'penugasan serta evaluasi sales tersusun jelas'),
  'persediaan': SpesifikasiBantuanMenu(
      judul: 'Persediaan & Kartu Stok',
      tujuan: 'melihat saldo, mutasi, lokasi, minimum, dan nilai persediaan',
      workflow: [
        'Pilih gudang',
        'Cari barang',
        'Baca saldo',
        'Buka kartu stok',
        'Telusuri mutasi',
        'Rekonsiliasi'
      ],
      ilustrasi: [
        'Filter gudang',
        'Saldo barang',
        'Kartu mutasi',
        'Nilai stok',
        'Peringatan minimum'
      ],
      objekUtama: 'saldo dan mutasi persediaan',
      hasilAkhir: 'posisi stok dapat dijelaskan sampai dokumen sumber'),
  'harga': SpesifikasiBantuanMenu(
      judul: 'Master & Analisis Harga',
      tujuan:
          'mengatur harga beli, jual, margin, tingkat harga, dan histori perubahan',
      workflow: [
        'Pilih barang',
        'Baca HPP',
        'Tentukan margin',
        'Isi harga',
        'Simulasikan',
        'Simpan'
      ],
      ilustrasi: [
        'Daftar harga',
        'HPP',
        'Margin',
        'Tingkat pelanggan',
        'Riwayat perubahan'
      ],
      objekUtama: 'struktur harga barang',
      hasilAkhir: 'harga jual konsisten dengan biaya dan kebijakan margin'),
  'hutangSupplier': SpesifikasiBantuanMenu(
      judul: 'Hutang Supplier',
      tujuan:
          'mencatat, memantau jatuh tempo, dan membayar kewajiban kepada supplier',
      workflow: [
        'Pilih supplier',
        'Lihat tagihan',
        'Cocokkan dokumen',
        'Catat pembayaran',
        'Alokasikan nominal',
        'Rekonsiliasi'
      ],
      ilustrasi: [
        'Ringkasan hutang',
        'Daftar tagihan',
        'Jatuh tempo',
        'Form pembayaran',
        'Kartu supplier'
      ],
      objekUtama: 'hutang usaha',
      hasilAkhir: 'saldo kewajiban dan pembayaran supplier akurat'),
  'penjualanSales': SpesifikasiBantuanMenu(
      judul: 'Penjualan Sales',
      tujuan: 'mencatat order dan penjualan distribusi oleh petugas sales',
      workflow: [
        'Pilih customer',
        'Pilih sales',
        'Tambah barang',
        'Tentukan harga',
        'Konfirmasi order',
        'Terbitkan transaksi'
      ],
      ilustrasi: [
        'Customer dan sales',
        'Katalog barang',
        'Keranjang order',
        'Termin',
        'Ringkasan transaksi'
      ],
      objekUtama: 'order atau penjualan distribusi',
      hasilAkhir: 'barang, pendapatan, dan piutang tercatat'),
  'piutang': SpesifikasiBantuanMenu(
      judul: 'Piutang Customer',
      tujuan:
          'memantau tagihan pelanggan, umur piutang, limit, dan penerimaan pembayaran',
      workflow: [
        'Pilih customer',
        'Lihat tagihan',
        'Periksa jatuh tempo',
        'Terima pembayaran',
        'Alokasikan',
        'Rekonsiliasi'
      ],
      ilustrasi: [
        'Ringkasan piutang',
        'Aging',
        'Daftar invoice',
        'Form penerimaan',
        'Kartu customer'
      ],
      objekUtama: 'piutang usaha',
      hasilAkhir: 'saldo customer dan penerimaan dapat ditelusuri'),
  'suratPerintahSales': SpesifikasiBantuanMenu(
      judul: 'Surat Perintah Sales',
      tujuan:
          'menugaskan sales membawa barang atau mengunjungi customer dengan dokumen resmi',
      workflow: [
        'Pilih sales',
        'Tentukan rute',
        'Pilih barang',
        'Isi jumlah',
        'Terbitkan surat',
        'Pantau penyelesaian'
      ],
      ilustrasi: [
        'Identitas sales',
        'Rute',
        'Daftar barang',
        'Nomor dokumen',
        'Status tugas'
      ],
      objekUtama: 'surat perintah dan muatan sales',
      hasilAkhir: 'penugasan lapangan memiliki batas dan pertanggungjawaban'),
  'notaSales': SpesifikasiBantuanMenu(
      judul: 'Sesi Nota Sales',
      tujuan:
          'mengelola rentang nota yang dibawa, digunakan, dikembalikan, dan dipertanggungjawabkan sales',
      workflow: [
        'Buka sesi',
        'Serahkan rentang nota',
        'Catat pemakaian',
        'Kembalikan sisa',
        'Periksa nomor',
        'Tutup sesi'
      ],
      ilustrasi: [
        'Sales pemegang nota',
        'Rentang nomor',
        'Nota terpakai',
        'Nota batal',
        'Rekonsiliasi'
      ],
      objekUtama: 'nomor nota dan sesi sales',
      hasilAkhir: 'tidak ada nomor nota yang hilang tanpa penjelasan'),
  'kasJurnal': SpesifikasiBantuanMenu(
      judul: 'Kas & Jurnal',
      tujuan:
          'mencatat penerimaan, pengeluaran, transfer, dan jurnal distribusi',
      workflow: [
        'Pilih kas',
        'Pilih jenis transaksi',
        'Isi akun lawan',
        'Masukkan nominal',
        'Lampirkan referensi',
        'Posting'
      ],
      ilustrasi: [
        'Saldo kas',
        'Form transaksi',
        'Akun debit/kredit',
        'Referensi',
        'Buku jurnal'
      ],
      objekUtama: 'transaksi kas dan jurnal',
      hasilAkhir: 'debit-kredit seimbang dan saldo kas dapat direkonsiliasi'),
  'labaRugi': SpesifikasiBantuanMenu(
      judul: 'Laba Rugi',
      tujuan:
          'menganalisis pendapatan, HPP, biaya, margin, dan laba menurut periode',
      workflow: [
        'Pilih periode',
        'Pilih dimensi',
        'Muat laporan',
        'Bandingkan pendapatan dan HPP',
        'Telusuri biaya',
        'Ekspor'
      ],
      ilustrasi: [
        'Filter periode',
        'Ringkasan laba',
        'Pendapatan',
        'HPP dan biaya',
        'Tren margin'
      ],
      objekUtama: 'laporan laba rugi',
      hasilAkhir: 'sumber keuntungan atau kerugian dapat diidentifikasi'),
};

ArtikelBantuan artikelBantuanUntukMenu(
    String menuId, String judulFallback, String platformId) {
  final s = spesifikasiBantuanMenu[menuId] ??
      SpesifikasiBantuanMenu(
        judul: judulFallback,
        tujuan:
            'menjalankan pekerjaan pada halaman ini secara tertib, aman, dan dapat diaudit',
        workflow: const [
          'Buka halaman',
          'Pilih data',
          'Periksa input',
          'Simpan',
          'Validasi hasil',
          'Tindak lanjuti'
        ],
        ilustrasi: const [
          'Judul dan status',
          'Filter',
          'Area data',
          'Form tindakan',
          'Ringkasan hasil'
        ],
        objekUtama: 'data pada halaman',
        hasilAkhir: 'pekerjaan tersimpan dan dapat ditelusuri',
      );
  final platform = artikelBantuan.firstWhere((a) => a.id == platformId,
      orElse: () => artikelBantuan.first);
  return ArtikelBantuan(
    id: menuId,
    judul: 'Bantuan ${s.judul}',
    ringkasan:
        'Panduan kontekstual ${s.judul} untuk ${platform.judul}: ${s.tujuan}.',
    workflow: s.workflow,
    ilustrasi: s.ilustrasi,
    bagian: [
      BagianBantuan(
          'Tujuan halaman, hasil yang diharapkan, dan batas tanggung jawab',
          'Halaman ${s.judul} digunakan untuk ${s.tujuan}. Objek utama yang dikelola adalah ${s.objekUtama}. Hasil yang dianggap selesai bukan sekadar munculnya pesan sukses, melainkan ${s.hasilAkhir}. Sebelum bekerja, pastikan outlet, pengguna, periode, koneksi, dan hak akses sesuai. Baca judul halaman serta subjudul karena keduanya menjelaskan ruang lingkup data. Jangan melanjutkan bila outlet atau identitas pengguna salah. Pisahkan tindakan melihat, menambah, mengubah, menghapus, menyetujui, dan mengekspor; setiap tindakan dapat memiliki kewenangan berbeda. Data yang sudah menjadi dokumen transaksi tidak boleh diperbaiki dengan menghapus jejak. Gunakan koreksi, retur, pembatalan, atau dokumen pembalik yang tersedia. Jika tombol tidak terlihat, periksa role dan status data sebelum menyimpulkan aplikasi rusak. Selalu cocokkan hasil di layar dengan bukti fisik atau dokumen sumber. Catat nomor referensi setelah penyimpanan. Pada perangkat bersama, jangan meninggalkan halaman berisi data sensitif tanpa mengunci atau logout. Tujuan kontrol ini adalah menjaga ketepatan data sekaligus melindungi operator karena setiap perubahan dapat dijelaskan siapa, kapan, dari outlet mana, dan berdasarkan bukti apa.'),
      BagianBantuan('Workflow rinci dan titik pemeriksaan pada setiap tahap',
          'Workflow halaman ini terdiri dari ${s.workflow.join(', kemudian ')}. Pada tahap pertama, pastikan konteks dan data awal benar sebelum memasukkan perubahan. Tahap kedua memilih objek yang tepat; gunakan kode unik, barcode, nomor dokumen, atau identitas resmi, bukan hanya kemiripan nama. Tahap ketiga adalah validasi: bandingkan nilai lama, input baru, satuan, tanggal, jumlah, status, dan hubungan dengan data lain. Tahap keempat menyimpan atau memproses tindakan. Tekan tombol satu kali lalu tunggu indikator selesai. Tahap kelima memeriksa hasil dari server, bukan hanya perubahan visual lokal. Muat ulang bila perlu dan pastikan daftar, saldo, atau status benar-benar berubah. Tahap terakhir adalah tindak lanjut seperti mencetak bukti, menyerahkan barang, memberi tahu supervisor, mengekspor laporan, atau menutup sesi. Bila satu tahap gagal, jangan langsung mengulang seluruh alur. Baca pesan, perbaiki penyebab pada tahap tersebut, lalu periksa riwayat untuk memastikan permintaan sebelumnya belum tercatat. Diagram menampilkan urutan normal, tetapi kontrol dapat kembali ke tahap validasi saat ditemukan perbedaan. Setiap perpindahan status harus mempunyai alasan operasional yang dapat dipahami petugas berikutnya.'),
      BagianBantuan('Cara membaca ilustrasi halaman dan contoh penggunaan',
          'Ilustrasi halaman membagi layar menjadi ${s.ilustrasi.join(', ')}. Pada desktop, area tersebut umumnya tersusun berdampingan agar perbandingan cepat; pada Android, area yang sama ditumpuk dari atas ke bawah dan harus digulir. Mulailah dari filter atau identitas konteks, lanjutkan ke daftar data, pilih satu baris, kemudian gunakan form atau tombol tindakan. Contoh penggunaan yang aman: operator memilih konteks yang benar, mencari data dengan kode paling spesifik, membuka rincian, membandingkan dengan dokumen sumber, mengisi hanya kolom yang memang perlu berubah, membaca ringkasan dampak, lalu menyimpan. Setelah server menyatakan berhasil, operator kembali ke daftar dan memastikan nilai baru terlihat. Jika hasil berbeda dari perkiraan, operator tidak membuat entri kedua; ia membuka detail, melihat audit atau riwayat, dan menghubungi supervisor dengan nomor referensi. Pada layar kecil, tutup keyboard agar tombol bawah terlihat dan hindari ketukan berulang. Pada desktop, gunakan Tab untuk berpindah kolom tetapi tetap baca fokus aktif. Warna merah menunjukkan risiko atau kegagalan, kuning membutuhkan perhatian, hijau biasanya menandakan aman atau selesai, sedangkan abu-abu dapat berarti nonaktif. Warna adalah petunjuk tambahan; teks status tetap rujukan utama.'),
      ...platform.bagian,
    ],
  );
}
