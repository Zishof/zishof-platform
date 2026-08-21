import 'bantuan_content.dart';

class SpesifikasiBantuanMenu {
  final String judul;
  final String tujuan;
  final List<String> workflow;
  final List<String> ilustrasi;
  final String objekUtama;
  final String hasilAkhir;

  /// Istilah khusus halaman ini beserta artinya (format 'Istilah = penjelasan').
  /// Dipakai halaman Bantuan sebagai bagian "Kamus istilah" -- penting untuk menu
  /// akuntansi yang istilahnya tidak sehari-hari bagi kasir/operator toko.
  final List<String> istilah;

  /// Hal yang sering keliru dan akibatnya bila diabaikan.
  final List<String> catatanPenting;

  /// Tanya jawab khusus halaman ini: tiap entri berisi dua elemen
  /// [pertanyaan, jawaban]. Ditambahkan SETELAH tanya jawab umum.
  final List<List<String>> tanyaJawabTambahan;

  const SpesifikasiBantuanMenu({
    required this.judul,
    required this.tujuan,
    required this.workflow,
    required this.ilustrasi,
    required this.objekUtama,
    required this.hasilAkhir,
    this.istilah = const [],
    this.catatanPenting = const [],
    this.tanyaJawabTambahan = const [],
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
      hasilAkhir: 'data anggota serta saldo yang akurat dan dapat ditelusuri',
      istilah: [
        'Saldo voucher/deposit = uang milik anggota yang dititipkan di toko dan dipakai untuk belanja',
        'Saldo menurut sistem = hasil hitungan aplikasi, yaitu seluruh topup dikurangi seluruh pemakaian; angkanya TIDAK disimpan sebagai satu kolom melainkan dihitung ulang tiap kali dibuka',
        'Saldo seharusnya = saldo yang benar menurut hasil pemeriksaan petugas, sejajar dengan "stok fisik" pada opname barang',
        'Penyesuaian Saldo = opname saldo: membandingkan saldo sistem dengan saldo seharusnya lalu mencatat selisihnya beserta alasannya',
        'Selisih = saldo seharusnya dikurangi saldo sistem; positif berarti saldo anggota ditambah, negatif berarti dikurangi',
        'Topup = penambahan saldo karena anggota menyetor uang; berbeda dari penyesuaian yang sifatnya mengoreksi catatan',
        'Mutasi voucher = daftar setiap penambahan dan pemakaian saldo, termasuk baris koreksi hasil penyesuaian',
      ],
      catatanPenting: [
        'Penyesuaian Saldo bukan pengganti Topup. Topup dipakai ketika anggota benar-benar menyetor uang; penyesuaian dipakai ketika catatan saldo tidak cocok dengan kenyataan, misalnya topup terlanjur dientri dua kali',
        'Alasan penyesuaian wajib diisi dan sebaiknya menyebut buktinya, misalnya "koreksi topup ganda 19 Agustus nota TP-0912" — inilah satu-satunya keterangan yang tersisa ketika koreksi ini ditanyakan berbulan-bulan kemudian',
        'Saldo tidak ditimpa. Sistem membuat satu baris mutasi senilai selisihnya, sehingga riwayat topup dan pemakaian yang lama tetap utuh dan dapat ditelusuri',
        'Saldo sistem dibaca ulang dari server saat menyimpan, jadi angka di layar yang sudah lama terbuka tidak akan ikut terpakai; bila ada kasir lain yang baru saja menambah topup, penyesuaian Anda tetap dihitung dari saldo terbaru',
        'Yang boleh menyesuaikan saldo hanya pengguna yang berhak menambah dan mengubah topup/deposit. Bila tombolnya tidak terlihat, itu memang hak akses, bukan aplikasi rusak',
        'Periksa dulu tab Mutasi Voucher sebelum menyesuaikan. Sering kali selisih yang dikira kesalahan sistem ternyata transaksi yang belum tersinkron atau belanja yang belum dibaca',
      ],
      tanyaJawabTambahan: [
        [
          'Apa itu Penyesuaian Saldo dan kapan saya memakainya?',
          'Penyesuaian Saldo adalah opname untuk saldo voucher anggota, cara kerjanya sama seperti Stok Opname pada barang: aplikasi menampilkan saldo menurut catatannya, Anda mengisi saldo yang seharusnya, lalu selisihnya dicatat beserta alasannya. Pakai fitur ini hanya ketika catatan saldo memang tidak cocok dengan kenyataan — misalnya topup terlanjur dientri dua kali, setoran tercatat pada anggota yang salah, atau saldo awal saat pertama memakai sistem belum lengkap. Bila anggota memang menyetor uang, gunakan Topup, bukan penyesuaian.',
        ],
        [
          'Di mana tombolnya dan mengapa saya tidak melihatnya?',
          'Tombol "Penyesuaian Saldo" ada di halaman Pelanggan, tab Saldo Voucher, sebaris dengan tombol Preview/PDF/Excel. Tombol itu hanya muncul untuk pengguna yang berhak menambah dan mengubah topup/deposit. Jika tidak terlihat, mintalah admin mengaktifkan hak "Boleh Entry Topup" pada peran Anda. Sekadar catatan: menyembunyikan tombol bukan satu-satunya pengaman — server menolak juga bila hak itu tidak ada.',
        ],
        [
          'Apakah saldo lama akan hilang atau tertimpa?',
          'Tidak. Saldo anggota tidak disimpan sebagai satu angka yang bisa ditimpa, melainkan dihitung dari seluruh mutasinya. Penyesuaian membuat SATU baris mutasi baru senilai selisih — positif bila saldo perlu ditambah, negatif bila perlu dikurangi. Seluruh topup dan pemakaian sebelumnya tetap tercatat apa adanya, dan koreksinya terlihat jelas di tab Mutasi Voucher dengan penanda [Penyesuaian Saldo].',
        ],
        [
          'Bagaimana urutan kerja yang benar?',
          'Pertama, buka tab Mutasi Voucher anggota tersebut dan telusuri dulu penyebab selisihnya; sering kali ada transaksi yang belum tersinkron. Kedua, bila memang perlu dikoreksi, tekan Penyesuaian Saldo lalu pilih anggotanya. Ketiga, baca "Saldo menurut sistem" yang muncul. Keempat, isi "Saldo seharusnya" sesuai hasil pemeriksaan. Kelima, periksa angka Selisih beserta keterangan arah koreksinya (ditambah atau dikurangi). Keenam, tulis alasan yang menyebut bukti. Terakhir, simpan dan pastikan saldo di daftar sudah berubah.',
        ],
        [
          'Tombol Simpan tidak bisa ditekan, apa yang kurang?',
          'Tombol baru aktif bila empat hal terpenuhi: anggota sudah dipilih, saldo sistem sudah termuat, kolom saldo seharusnya sudah diisi, dan alasan sudah ditulis. Selain itu, bila saldo yang Anda masukkan sama persis dengan saldo sistem, penyesuaian ditolak karena memang tidak ada yang perlu dikoreksi.',
        ],
        [
          'Saya salah memasukkan angka penyesuaian, bagaimana memperbaikinya?',
          'Jangan menghapus catatannya. Buat penyesuaian baru dengan saldo yang benar, dan pada alasannya sebutkan bahwa ini mengoreksi penyesuaian sebelumnya. Dengan begitu riwayatnya tetap runtut dan pemeriksa dapat melihat apa yang terjadi, sama seperti prinsip koreksi pada jurnal akuntansi.',
        ],
        [
          'Di mana saya bisa melihat riwayat penyesuaian?',
          'Ada tiga tempat. Riwayat singkat tampil langsung di bagian bawah dialog Penyesuaian Saldo. Untuk laporan yang bisa dicetak dan diekspor, buka menu Laporan-Laporan kategori "Deposit / Saldo": pilih "Rincian Penyesuaian Saldo (Opname Voucher)" untuk melihat satu baris per penyesuaian, atau "Rekap Penyesuaian Saldo per Anggota" untuk melihat siapa yang paling sering disesuaikan beserta total selisihnya. Selain itu, mutasi koreksinya sendiri juga terlihat di tab Mutasi Voucher anggota.',
        ],
        [
          'Apakah penyesuaian saldo memengaruhi laporan keuangan?',
          'Saldo voucher adalah titipan uang anggota, sehingga penyesuaiannya mengubah jumlah kewajiban toko kepada anggota. Angkanya langsung terlihat pada laporan saldo dan mutasi voucher. Untuk pembukuan resminya, ikuti kebijakan bagian keuangan: penyesuaian bernilai besar sebaiknya disertai jurnal koreksi lewat menu Akuntansi > Jurnal Umum agar buku besar ikut mencerminkannya.',
        ],
      ]),
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
  // ---------------------------------------------------------------------------
  // Menu grup "Akuntansi". Ditulis rinci karena penggunanya kasir/staf toko yang
  // belum tentu berlatar akuntansi: tiap entri menjelaskan istilah, urutan kerja,
  // dan akibat bila langkahnya dilewati.
  // ---------------------------------------------------------------------------
  'jurnalUmum': SpesifikasiBantuanMenu(
      judul: 'Jurnal Umum',
      tujuan:
          'mencatat jurnal manual yang tidak terbentuk otomatis dari transaksi kasir, '
          'misalnya koreksi salah akun, biaya yang dibayar tunai, penyusutan, '
          'saldo awal, atau penyesuaian akhir bulan',
      workflow: [
        'Tentukan periode',
        'Tekan Jurnal Baru',
        'Isi tanggal & keterangan',
        'Isi baris debet dan kredit',
        'Pastikan seimbang',
        'Simpan sebagai draf',
        'Periksa ulang',
        'Posting ke buku besar'
      ],
      ilustrasi: [
        'Filter periode dan status',
        'Daftar jurnal beserta status Draf/Terposting',
        'Tombol Jurnal Baru dan Posting Semua Draf',
        'Editor jurnal: kepala di atas, baris debet/kredit di tengah',
        'Indikator keseimbangan di kanan bawah'
      ],
      objekUtama:
          'satu jurnal: kepala jurnal beserta baris debet dan kreditnya',
      hasilAkhir:
          'jurnal seimbang tersimpan, diposting, dan nilainya muncul di Buku Besar, '
          'Neraca, serta Laba Rugi',
      istilah: [
        'Debet = sisi kiri jurnal. Menambah harta/aset dan beban, mengurangi utang, modal, dan pendapatan',
        'Kredit = sisi kanan jurnal. Menambah utang, modal, dan pendapatan, mengurangi harta dan beban',
        'Seimbang (balance) = total debet sama persis dengan total kredit; jurnal yang tidak seimbang tidak boleh disimpan',
        'Draf = jurnal sudah tersimpan tetapi BELUM masuk buku besar dan belum terbaca laporan keuangan',
        'Terposting = jurnal sudah resmi masuk buku besar; sejak itu jurnal terkunci dan ikut dihitung laporan',
        'Jenis Transaksi = penentu awalan nomor jurnal, misalnya JU/08/00001 untuk jurnal umum bulan Agustus urutan pertama',
        'Tutup buku (closing) = batas tanggal yang periodenya sudah dikunci; jurnal bertanggal sebelum itu ditolak sistem',
      ],
      catatanPenting: [
        'Satu baris hanya boleh diisi debet ATAU kredit, tidak keduanya sekaligus',
        'Keterangan wajib diisi dan sebaiknya menyebut bukti sumbernya, misalnya nomor nota atau nama penyetor, karena inilah yang terbaca saat menelusuri buku besar berbulan-bulan kemudian',
        'Jurnal draf tidak memengaruhi laporan apa pun; kalau laporan belum berubah setelah menyimpan, hampir selalu penyebabnya jurnal belum diposting',
        'Jangan mengoreksi jurnal terposting dengan menghapusnya. Batalkan posting bila memang salah ketik, atau buat jurnal pembalik bila periodenya sudah dilaporkan ke pimpinan',
        'Akun yang dipilih menentukan laporan mana yang berubah. Salah memilih akun beban menjadi akun harta membuat laba terlihat lebih besar daripada kenyataan',
      ],
      tanyaJawabTambahan: [
        [
          'Kapan saya perlu memakai Jurnal Umum, bukan menu lain?',
          'Pakai Jurnal Umum hanya untuk kejadian yang tidak punya menu sendiri. Penjualan cukup lewat Kasir lalu Posting Penjualan; harga pokok lewat Posting HPP; pembelian barang lewat Kulakan. Jurnal Umum dipakai untuk koreksi salah akun, biaya kecil yang dibayar tunai tanpa dokumen pembelian, penyusutan, sewa dibayar di muka, saldo awal saat pertama kali memakai sistem, dan penyesuaian akhir periode. Kalau sebuah kejadian sudah punya menu sendiri, memakai Jurnal Umum justru berisiko dobel catat.',
        ],
        [
          'Bagaimana cara mengisi debet dan kredit kalau saya belum terbiasa?',
          'Tanyakan dua hal: apa yang BERTAMBAH dan apa yang BERKURANG. Contoh menerima uang sewa tunai Rp250.000: kas bertambah maka Kas ditulis di DEBET 250.000; pendapatan bertambah maka Pendapatan Sewa ditulis di KREDIT 250.000. Contoh membayar listrik tunai Rp300.000: beban bertambah maka Beban Listrik di DEBET 300.000; kas berkurang maka Kas di KREDIT 300.000. Aturan praktisnya: harta dan beban bertambah di debet; utang, modal, dan pendapatan bertambah di kredit.',
        ],
        [
          'Kenapa tombol Simpan tidak bisa ditekan?',
          'Tombol Simpan hanya aktif bila jurnal sudah seimbang dan bernilai. Lihat penanda di kanan bawah editor: bila tertulis Selisih beserta angkanya, berarti total debet dan kredit belum sama. Periksa apakah ada baris yang lupa diisi, salah menaruh angka di kolom sebelah, atau ada baris yang akunnya belum dipilih.',
        ],
        [
          'Saya salah ketik pada jurnal yang sudah diposting, apa yang harus dilakukan?',
          'Bila periodenya masih berjalan dan laporan belum diserahkan ke pimpinan, buka jurnalnya lalu tekan Batalkan Posting; jurnal kembali menjadi draf dan bisa diperbaiki, kemudian diposting lagi. Bila laporannya sudah terlanjur diserahkan atau periodenya sudah ditutup buku, jangan diutak-atik; buat jurnal baru sebagai koreksi dengan keterangan yang menyebut nomor jurnal yang dikoreksi, sehingga jejak auditnya tetap utuh.',
        ],
        [
          'Nomor jurnal muncul otomatis, apakah bisa diatur?',
          'Nomor dibuat otomatis dari kode Jenis Transaksi yang dipilih, dengan pola KODE/BULAN/URUTAN, misalnya JU/08/00001. Bila Anda tidak memilih Jenis Transaksi, sistem memakai awalan JU. Untuk memakai awalan lain, tambahkan atau ubah datanya di menu Akuntansi > Jenis Transaksi.',
        ],
        [
          'Apa bedanya Jurnal Umum dengan Posting HPP dan Posting Penjualan?',
          'Posting HPP dan Posting Penjualan bekerja otomatis: sistem membaca transaksi kasir lalu menyusun jurnalnya untuk Anda, Anda tinggal memeriksa dan menekan Posting. Jurnal Umum bekerja manual: Anda sendiri yang menentukan akun dan nilainya. Karena manual, Jurnal Umum lebih fleksibel tetapi juga lebih berisiko salah, sehingga sebaiknya dipakai seperlunya dan selalu disertai keterangan yang jelas.',
        ],
      ]),
  'postingHpp': SpesifikasiBantuanMenu(
      judul: 'Posting HPP',
      tujuan:
          'membukukan harga pokok barang yang sudah terjual, sehingga laba yang '
          'dilaporkan sudah dikurangi biaya barangnya',
      workflow: [
        'Pilih periode',
        'Muat draf jurnal',
        'Periksa harga pokok per barang',
        'Lengkapi akun yang belum diatur',
        'Posting per barang atau semua',
        'Cek Buku Besar'
      ],
      ilustrasi: [
        'Pemilih periode',
        'Draf jurnal per barang',
        'Kolom akun HPP dan akun Persediaan',
        'Penanda baris yang belum siap',
        'Tombol Posting'
      ],
      objekUtama: 'draf jurnal harga pokok penjualan per barang',
      hasilAkhir:
          'akun Beban Pokok Penjualan bertambah, Persediaan berkurang, dan laba '
          'kotor pada Laba Rugi menjadi benar',
      istilah: [
        'HPP = Harga Pokok Penjualan, yaitu nilai beli barang yang laku terjual, bukan harga jualnya',
        'Persediaan = nilai barang yang masih ada di toko; berkurang saat barang terjual',
        'Laba kotor = penjualan dikurangi HPP; inilah angka yang menunjukkan untung per barang sebelum biaya operasional',
      ],
      catatanPenting: [
        'HPP hanya bisa diposting bila barangnya sudah tertaut Master Aset dan akunnya sudah diatur; baris yang belum lengkap ditampilkan beserta alasannya, bukan disembunyikan',
        'Jangan memposting HPP untuk periode yang sama dua kali; sistem sudah menandai dokumen yang terposting agar tidak dobel, tetapi tetap periksa hasilnya',
        'HPP mengkredit Persediaan. Bila pembelian/kulakan belum pernah diposting, saldo Persediaan bisa terlihat minus. Posting kulakan lebih dulu agar wajar',
      ],
      tanyaJawabTambahan: [
        [
          'Kenapa angka HPP saya terlihat sangat besar atau minus?',
          'Hampir selalu karena harga beli pada master barang salah, misalnya harga per dus diisi sebagai harga per pieces, atau sebaliknya. Buka laporan Rincian HPP untuk melihat barang mana penyumbang terbesarnya, lalu betulkan harga belinya di menu Produk. Setelah master diperbaiki, jalankan ulang posting untuk periode berikutnya; periode yang sudah terposting perlu dikoreksi lewat jurnal koreksi.',
        ],
        [
          'Apa akibatnya kalau HPP tidak pernah diposting?',
          'Laba Rugi akan menampilkan seluruh penjualan sebagai keuntungan tanpa dikurangi biaya barangnya, sehingga laba terlihat jauh lebih besar daripada kenyataan, dan nilai Persediaan di Neraca tidak pernah berkurang meski barangnya sudah habis terjual.',
        ],
      ]),
  'postingPenjualan': SpesifikasiBantuanMenu(
      judul: 'Posting Penjualan',
      tujuan:
          'membukukan penjualan kasir menjadi jurnal akuntansi resmi: kas atau '
          'piutang bertambah, pendapatan dan PPN keluaran tercatat',
      workflow: [
        'Pilih periode',
        'Muat draf jurnal per transaksi',
        'Periksa akun pendapatan tiap jenis produk',
        'Posting per transaksi atau semua',
        'Cocokkan dengan Laporan Transaksi'
      ],
      ilustrasi: [
        'Pemilih periode',
        'Daftar draf per faktur penjualan',
        'Kolom akun debet dan kredit',
        'Status siap atau belum siap',
        'Tombol Posting'
      ],
      objekUtama: 'draf jurnal penjualan per transaksi kasir',
      hasilAkhir:
          'pendapatan penjualan muncul di Laba Rugi dan penerimaan kas muncul di '
          'Neraca serta Arus Kas',
      istilah: [
        'Akun pendapatan = akun tempat nilai penjualan dicatat, diatur per Jenis Produk',
        'PPN keluaran = pajak yang dipungut dari pembeli dan nantinya disetor; dicatat terpisah dari pendapatan',
        'Piutang = penjualan yang belum dibayar tunai, muncul bila cara bayarnya ditandai Masuk sebagai Hutang',
      ],
      catatanPenting: [
        'Akun pendapatan diambil dari Jenis Produk, sedangkan akun kas/piutang diambil dari Cara Pembayaran. Bila salah satunya belum diisi, transaksinya tidak bisa diposting dan akan tampil dengan keterangan alasannya',
        'Posting penjualan tidak mengubah stok; stok sudah berkurang sejak transaksi kasir tersimpan',
      ],
      tanyaJawabTambahan: [
        [
          'Penjualan hari ini sudah ada di Laporan Transaksi, tetapi belum muncul di Laba Rugi. Kenapa?',
          'Laporan Transaksi membaca data kasir, sedangkan Laba Rugi membaca buku besar. Selama penjualan belum diposting, keduanya memang berbeda. Jalankan Posting Penjualan untuk periode itu, lalu buka kembali Laba Rugi.',
        ],
      ]),
  'kodeAkun': SpesifikasiBantuanMenu(
      judul: 'Kode Akun',
      tujuan:
          'mengelola bagan akun (daftar rekening) yang menjadi tulang punggung '
          'seluruh laporan keuangan',
      workflow: [
        'Cari akun',
        'Periksa struktur induk-anak',
        'Unduh contoh Excel',
        'Sunting di Excel',
        'Unggah kembali',
        'Petakan akun ke Kelompok Laporan'
      ],
      ilustrasi: [
        'Kotak cari kode dan nama',
        'Tab Akun berbentuk pohon',
        'Tab Daftar Akun berbentuk tabel datar',
        'Tombol Download dan Upload',
        'Tombol Petakan Akun'
      ],
      objekUtama: 'akun/rekening beserta posisi debet-kreditnya',
      hasilAkhir:
          'bagan akun lengkap, tersusun berjenjang, dan seluruhnya sudah terpetakan '
          'ke Kelompok Laporan',
      istilah: [
        'Bagan akun (Chart of Accounts) = daftar seluruh rekening yang dipakai, biasanya bernomor: 1xx harta, 2xx harta tetap, 3xx kewajiban dan modal, 4xx pendapatan, 5xx beban',
        'Akun induk = akun judul yang menaungi akun di bawahnya; transaksi sebaiknya dicatat di akun paling bawah (akun daun)',
        'Kelompok Laporan = penentu apakah sebuah akun muncul di Neraca atau Laba Rugi; akun yang belum dipetakan TIDAK ikut terhitung',
      ],
      catatanPenting: [
        'Jangan mengganti arti sebuah akun yang sudah dipakai transaksi; buat akun baru bila kebutuhannya berbeda, agar riwayat lama tetap benar',
        'Unggahan Excel hanya menambah dan memperbarui, tidak pernah menghapus. Baris tanpa kode ditolak dan dilaporkan beserta nomor barisnya',
        'Setelah menambah akun baru, jalankan tombol Petakan Akun supaya akun itu ikut muncul di Neraca atau Laba Rugi',
      ],
      tanyaJawabTambahan: [
        [
          'Saya menambah akun baru, tetapi nilainya tidak muncul di Neraca. Kenapa?',
          'Neraca dan Laba Rugi hanya menampilkan akun yang sudah dipetakan ke Kelompok Laporan. Buka menu Akuntansi > Laporan-Laporan lalu jalankan Diagnosa Pemetaan Akun untuk melihat akun mana saja yang belum terpetakan, atau langsung tekan tombol Petakan Akun di halaman ini.',
        ],
      ]),
  'grupAkun': SpesifikasiBantuanMenu(
      judul: 'Grup Akun',
      tujuan:
          'mengelompokkan akun sejenis agar bagan akun lebih mudah dibaca dan dicari',
      workflow: [
        'Buka daftar grup',
        'Periksa jumlah akun tiap grup',
        'Tentukan grup untuk akun baru',
        'Sesuaikan grup pada akun',
        'Periksa ulang bagan akun'
      ],
      ilustrasi: [
        'Tab Grup Akun',
        'Tabel grup akun',
        'Kolom jumlah akun per grup',
        'Kolom keterangan',
        'Tab Akun sebagai pembanding'
      ],
      objekUtama: 'grup/pengelompokan akun',
      hasilAkhir: 'bagan akun tersusun rapi dan mudah ditelusuri',
      istilah: [
        'Grup Akun = label pengelompokan bebas pada bagan akun, misalnya Kas & Bank atau Piutang',
        'Kelompok Laporan = berbeda dari Grup Akun; Kelompok Laporan-lah yang menentukan posisi akun di Neraca atau Laba Rugi',
      ],
      catatanPenting: [
        'Mengubah Grup Akun tidak mengubah angka laporan sama sekali; ia hanya memengaruhi cara akun dikelompokkan saat dilihat',
      ],
      tanyaJawabTambahan: [
        [
          'Apa bedanya Grup Akun dengan Kelompok Laporan?',
          'Grup Akun adalah label agar daftar akun rapi dan mudah dicari; tidak berpengaruh pada laporan. Kelompok Laporan menentukan sebuah akun tampil di Neraca atau di Laba Rugi, dan pada kelompok mana, sehingga sangat berpengaruh pada laporan. Bila laporan terasa kurang lengkap, yang perlu diperiksa adalah Kelompok Laporan, bukan Grup Akun.',
        ],
      ]),
  'jenisTransaksi': SpesifikasiBantuanMenu(
      judul: 'Jenis Transaksi',
      tujuan:
          'mengatur jenis transaksi beserta akun bawaannya dan awalan penomoran jurnal',
      workflow: [
        'Buka daftar jenis transaksi',
        'Periksa kode dan akun bawaannya',
        'Unduh Excel bila perlu diubah massal',
        'Unggah kembali',
        'Uji pada Jurnal Umum'
      ],
      ilustrasi: [
        'Tab Jenis Transaksi',
        'Tabel jenis transaksi',
        'Kolom kode',
        'Kolom akun bawaan',
        'Tombol Download dan Upload'
      ],
      objekUtama: 'jenis transaksi beserta akun bawaan dan kodenya',
      hasilAkhir:
          'penomoran jurnal rapi per jenis dan akun bawaan mempercepat pengisian',
      istilah: [
        'Kode jenis transaksi = awalan nomor jurnal, misalnya JU menghasilkan JU/08/00001',
        'Akun bawaan = akun yang otomatis disarankan saat jenis transaksi ini dipakai',
      ],
      catatanPenting: [
        'Kode wajib unik. Mengubah kode tidak mengubah nomor jurnal yang sudah terlanjur terbit',
      ],
      tanyaJawabTambahan: [
        [
          'Untuk apa Jenis Transaksi bagi kasir?',
          'Terutama untuk penomoran jurnal agar dokumen mudah dikelompokkan, misalnya kas masuk, kas keluar, dan koreksi memakai awalan yang berbeda. Kasir tidak perlu mengubah apa pun di sini; cukup memilihnya saat membuat Jurnal Umum.',
        ],
      ]),
  'bankAkun': SpesifikasiBantuanMenu(
      judul: 'Bank',
      tujuan:
          'mendaftarkan rekening bank dan menautkannya ke akun kas/bank di bagan akun',
      workflow: [
        'Buka daftar bank',
        'Periksa kode dan akun kasnya',
        'Unduh Excel',
        'Perbarui data',
        'Unggah kembali'
      ],
      ilustrasi: [
        'Tab Bank',
        'Tabel bank',
        'Kolom kode',
        'Kolom akun kas',
        'Tombol Download dan Upload'
      ],
      objekUtama: 'data bank beserta akun kas yang mewakilinya',
      hasilAkhir:
          'setiap rekening bank punya akun kas sendiri sehingga rekonsiliasi bank '
          'dapat dilakukan per rekening',
      istilah: [
        'Akun kas bank = akun di bagan akun yang mewakili satu rekening; saldonya harus cocok dengan rekening koran',
        'Kode bank = kunci pencocokan saat mengunggah Excel, supaya mengganti nama bank tidak membuat data kembar',
      ],
      catatanPenting: [
        'Satu rekening sebaiknya diwakili satu akun. Menggabungkan beberapa rekening ke satu akun membuat rekonsiliasi bank tidak dapat dilakukan',
        'Isi kode bank agar unggahan Excel memperbarui data yang ada, bukan membuat data baru',
      ],
      tanyaJawabTambahan: [
        [
          'Saya mengganti nama bank lewat Excel, kenapa dulu jadi data kembar?',
          'Dahulu bank dicocokkan lewat nama, sehingga nama baru dianggap bank baru. Sekarang tersedia kolom Kode; selama kodenya sama, unggahan akan memperbarui data yang ada meskipun namanya berubah.',
        ],
      ]),
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
  // --- Modul Pengadaan: PR -> PO -> BAST -> Terima Tagihan -> Bayar Tagihan -> Bayar Pajak ---
  // Kuncinya adalah nama enum MenuEBisnis, sehingga BantuanFab yang dipasang AppShell
  // langsung menemukannya tanpa perubahan di masing-masing layar.
  'pengadaanPr': SpesifikasiBantuanMenu(
      judul: 'Permintaan Pembelian (PR)',
      tujuan: 'mengajukan kebutuhan barang toko sebelum dipesan ke penyedia',
      workflow: [
        'Buat PR',
        'Pilih barang',
        'Isi jumlah dan harga',
        'Ajukan',
        'Disetujui atau ditolak'
      ],
      ilustrasi: [
        'Daftar PR',
        'Form permintaan',
        'Pemilih barang',
        'Tombol setujui dan tolak',
        'Alasan penolakan pada PR yang ditolak'
      ],
      objekUtama: 'permintaan pembelian',
      hasilAkhir: 'PR disetujui yang siap dijadikan pesanan',
      istilah: [
        'DRAFT = masih dapat diubah dan dihapus',
        'DISETUJUI = terkunci, menjadi dasar pembuatan PO',
        'TUTUP = permintaan tidak dilanjutkan lagi'
      ],
      catatanPenting: [
        'Setiap menu Pengadaan punya dua tab: Dasbor (ringkasan angka dan tren) dan tab data untuk pembuatan serta penyuntingan dokumen',
        'Seluruh penyimpanan dan keputusan ditulis di perangkat lebih dulu, lalu dikirim ke server; bekerja tanpa sinyal tetap aman',
        'Nilai PR dihitung ulang server dari barisnya, jadi total dokumen selalu sama dengan rinciannya',
        'PR yang sudah disetujui tidak dapat diubah; batalkan keputusannya dulu bila perlu dikoreksi',
        'Menolak wajib menyertakan alasan minimal 5 karakter supaya pembuat PR tahu apa yang harus diperbaiki'
      ],
      tanyaJawabTambahan: [
        [
          'Kenapa nomor PR tidak bisa saya ketik sendiri?',
          'Nomor dibuat otomatis dengan pola PR/toko/periode/urut agar tidak kembar antar toko dan antar bulan.'
        ],
        [
          'Barang yang saya cari tidak muncul.',
          'Pemilih barang mengambil dari Produk POS milik toko Anda. Bila belum ada, daftarkan dulu di menu Produk.'
        ],
      ]),
  'pengadaanPo': SpesifikasiBantuanMenu(
      judul: 'Pemesanan Pembelian (PO)',
      tujuan:
          'memesan barang ke penyedia, sekali bayar maupun bertahap dengan termin',
      workflow: [
        'Buat PO atau ambil dari PR',
        'Pilih penyedia',
        'Isi baris barang',
        'Atur termin bila bertahap',
        'Ajukan dan setujui'
      ],
      ilustrasi: [
        'Daftar PO',
        'Form pesanan',
        'Pemilih penyedia',
        'Jadwal termin',
        'Tombol bagi rata'
      ],
      objekUtama: 'pesanan pembelian dan jadwal pembayarannya',
      hasilAkhir: 'PO disetujui yang siap diterima barangnya',
      istilah: [
        'Termin = pembayaran bertahap sesuai jadwal',
        'DPP = nilai dasar pengenaan pajak, yaitu nilai penagihan termin',
        'DP = uang muka, hanya berlaku pada PO tanpa termin',
        'LUNAS = seluruh nilai PO sudah dibayar dan disetujui'
      ],
      catatanPenting: [
        'Setiap menu Pengadaan punya dua tab: Dasbor (ringkasan angka dan tren) dan tab data untuk pembuatan serta penyuntingan dokumen',
        'Seluruh penyimpanan dan keputusan ditulis di perangkat lebih dulu, lalu dikirim ke server; bekerja tanpa sinyal tetap aman',
        'Tombol Dari PR menampilkan BARANG-nya, dikelompokkan per nomor PR; barang dari beberapa PR boleh digabung ke dalam satu pesanan',
        'Jumlah seluruh termin wajib sama dengan nilai PO; selisih lebih dari Rp 1 akan ditolak saat menyimpan',
        'DP dan termin saling meniadakan. Bila memakai termin, tuliskan uang mukanya sebagai termin pertama',
        'PO yang sudah disetujui atau sudah menerima pembayaran tidak dapat diubah',
        'PPh dan PPN diisi di sini per termin, dan itulah yang nanti muncul di menu Bayar Pajak'
      ],
      tanyaJawabTambahan: [
        [
          'Apa beda "Dari PR" dengan "Buat PO"?',
          '"Dari PR" mengambil sisa yang belum dipesan dari permintaan yang sudah disetujui, sehingga satu PR bisa dipecah menjadi beberapa PO tanpa kelebihan pesan. "Buat PO" untuk pesanan langsung tanpa permintaan.'
        ],
        [
          'Tombol Bagi Rata itu untuk apa?',
          'Membagi nilai PO rata ke seluruh termin. Pembulatannya dibebankan ke termin terakhir supaya jumlahnya tepat sama dengan nilai PO.'
        ],
      ]),
  'pengadaanBast': SpesifikasiBantuanMenu(
      judul: 'Penerimaan Barang (BAST)',
      tujuan:
          'mencatat barang yang datang dari penyedia dan memasukkannya ke stok toko',
      workflow: [
        'Terima dari PO atau terima langsung',
        'Periksa jumlah yang datang',
        'Isi harga, potongan, dan PPN',
        'Setujui',
        'Sinkronkan ke stok Kulakan'
      ],
      ilustrasi: [
        'Daftar penerimaan',
        'Form BAST',
        'Penanda sisa boleh diterima',
        'Tombol sinkron ke Kulakan',
        'Rincian jumlah dipesan dibanding jumlah diterima'
      ],
      objekUtama: 'berita acara serah terima barang',
      hasilAkhir: 'barang tercatat diterima dan stok toko bertambah',
      istilah: [
        'BAST = Berita Acara Serah Terima, bukti barang sudah diterima',
        'Sisa boleh diterima = jumlah dipesan dikurangi yang sudah diterima dokumen lain',
        'Tanpa PO = penerimaan langsung untuk pembelian toko tanpa pesanan'
      ],
      catatanPenting: [
        'Setiap menu Pengadaan punya dua tab: Dasbor (ringkasan angka dan tren) dan tab data untuk pembuatan serta penyuntingan dokumen',
        'Seluruh penyimpanan dan keputusan ditulis di perangkat lebih dulu, lalu dikirim ke server; bekerja tanpa sinyal tetap aman',
        'Pesanan bertermin diterima PER TERMIN. Pesanan dengan tiga termin melahirkan tiga penerimaan, masing-masing dengan fakturnya sendiri -- jadi tagihannya juga tiga kali',
        'Pada pesanan bertermin, termin yang diterima WAJIB dipilih. Termin yang sudah pernah diterima tetap tampil namun tidak dapat dipilih lagi, supaya satu termin tidak tertagih dua kali',
        'Penerimaan lama yang dibuat sebelum aturan ini berlaku tidak menyimpan terminnya, sehingga kolom Termin-nya kosong. Bila disunting, terminnya harus dipilih ulang',
        'Barang datang kurang? Simpan dahulu yang benar-benar diterima, lalu tekan Back Order / Pesan Kembali untuk menutup sisanya dan menerbitkan pesanan susulan',
        'Sisa pesanan yang sudah ditutup tidak menerima barang lagi -- kekurangannya diterima pada pesanan susulan',
        'PPN dan PPh diisi per baris dalam persen; nilainya ikut muncul di layar Bayar Pajak',
        'Jumlah diterima tidak boleh melebihi sisa yang dipesan; angka sisanya tertera pada tiap baris',
        'Satu PO boleh diterima bertahap bila barang datang beberapa kali',
        'Stok baru bertambah setelah BAST disetujui DAN disinkronkan ke Kulakan',
        'Sinkronisasi hanya dapat dilakukan sekali; pengulangan ditolak agar stok tidak tergandakan'
      ],
      tanyaJawabTambahan: [
        [
          'Kenapa tidak ada tombol Tolak seperti di PR dan PO?',
          'Penerimaan barang tidak mengenal penolakan. Bila keliru, perbaiki dokumennya atau hapus selama masih berstatus DRAFT.'
        ],
        [
          'Sinkronisasi gagal karena barang belum berpadanan produk toko.',
          'Barisnya menunjuk barang inventaris yang belum punya padanan Produk POS. Buat dokumennya dari daftar Produk POS, atau petakan barang tersebut lebih dulu.'
        ],
      ]),
  'pengadaanTagihan': SpesifikasiBantuanMenu(
      judul: 'Terima Tagihan Vendor',
      tujuan:
          'mencatat nomor dan tanggal faktur vendor atas barang yang sudah diterima',
      workflow: [
        'Pilih penerimaan yang sudah disetujui',
        'Isi nomor faktur',
        'Isi tanggal faktur',
        'Simpan tagihan',
        'Periksa kembali di daftar sudah ditagih'
      ],
      ilustrasi: [
        'Daftar siap ditagih',
        'Penanda belum dan sudah ditagih',
        'Form nomor faktur',
        'Kolom tanggal faktur',
        'Daftar penerimaan yang sudah ditagih'
      ],
      objekUtama: 'faktur vendor atas penerimaan barang',
      hasilAkhir: 'tagihan tercatat dan siap dibayar',
      istilah: [
        'BELUM DITAGIH = barang sudah diterima tetapi fakturnya belum masuk',
        'SUDAH DITAGIH = nomor dan tanggal faktur sudah tercatat'
      ],
      catatanPenting: [
        'Setiap menu Pengadaan punya dua tab: Dasbor (ringkasan angka dan tren) dan tab data untuk pembuatan serta penyuntingan dokumen',
        'Seluruh penyimpanan dan keputusan ditulis di perangkat lebih dulu, lalu dikirim ke server; bekerja tanpa sinyal tetap aman',
        'Satu baris di sini mewakili SATU penerimaan. Pesanan bertermin diterima per termin, jadi pesanan tiga termin menghasilkan tiga baris tagihan -- kolom Termin ke membedakannya',
        'Kolom Barang menyatakan apakah penerimaannya sudah disetujui; kolom Faktur menyatakan apakah tagihannya sudah masuk. Keduanya kerap tidak sejalan karena faktur sering datang lebih dulu',
        'Kolom Lampiran menyebut berkas yang sudah diunggah. Bila penyimpanan berkas sedang tidak terbaca, kolom itu kosong sementara daftarnya tetap tampil',
        'Invoice WAJIB diunggah dan harus berupa gambar; tagihan tidak dapat diterima sebelum lampiran itu ada',
        'Faktur Pajak, Surat Jalan, dan Kwitansi bersifat pelengkap',
        'Berkasnya tersimpan di tabel lampiran yang sama dengan versi ZKoss, jadi terbaca di kedua versi',
        'Hanya penerimaan yang sudah DISETUJUI yang muncul di sini; barang yang belum diakui diterima tidak boleh menimbulkan kewajiban bayar',
        'Nomor dan tanggal faktur keduanya wajib karena menjadi rujukan pembayaran',
        'Nomor faktur yang sama pada penyedia yang sama akan ditolak untuk mencegah tagihan berganda',
        'Tagihan tidak dapat dibatalkan bila pesanannya sudah menerima pembayaran'
      ],
      tanyaJawabTambahan: [
        [
          'Penerimaan saya tidak muncul di daftar.',
          'Pastikan BAST-nya sudah disetujui. Selama masih DRAFT, dokumen itu belum boleh ditagihkan.'
        ],
      ]),
  'pengadaanDpc': SpesifikasiBantuanMenu(
      judul: 'Pembayaran Vendor',
      tujuan: 'membayar tagihan penyedia atas pesanan yang sudah disetujui',
      workflow: [
        'Pilih vendor',
        'Centang tagihan yang dibayar',
        'Isi nilai bayar',
        'Simpan',
        'Setujui dan pilih apakah diajukan transfer'
      ],
      ilustrasi: [
        'Daftar pembayaran',
        'Tagihan terbuka per termin',
        'Kolom sisa dan nilai bayar',
        'Pilihan ajukan transfer',
        'Ringkasan pajak yang menjadi terutang'
      ],
      objekUtama: 'dokumen pembayaran vendor',
      hasilAkhir: 'pesanan tercatat terbayar dan pajaknya menjadi terutang',
      istilah: [
        'Tagihan terbuka = termin yang masih menyisakan kewajiban bayar',
        'Sisa = nilai tagih dikurangi yang sudah dibayar dokumen lain',
        'Pengajuan transfer = permintaan pencairan yang masuk antrean keuangan',
        'Transfer = uangnya langsung menuju rekening penyedia. Jurnalnya memakai akun pada Cara Transfer yang dipilih',
        'Transitori = uangnya TIDAK langsung ke penyedia, melainkan ditampung dahulu pada akun perantara. Jurnalnya memakai Akun Transitori pada Cara Transfer, bukan akunnya yang biasa',
        'Akun transitori = akun perantara tempat uang menunggu sebelum benar-benar dicairkan. Selama masih di sini, kewajiban ke penyedia sudah berkurang tetapi uangnya belum keluar dari kas/bank',
        'Realisasi = mengumpulkan transitori yang menunggu menjadi satu batch lalu menyetujuinya. Ini menandai bahwa pencairannya sudah benar-benar dikerjakan',
        'Posting jurnal = penerbitan jurnal ke buku besar. Ini LANGKAH TERPISAH dari realisasi'
      ],
      catatanPenting: [
        'Setiap menu Pengadaan punya dua tab: Dasbor (ringkasan angka dan tren) dan tab data untuk pembuatan serta penyuntingan dokumen',
        'Seluruh penyimpanan dan keputusan ditulis di perangkat lebih dulu, lalu dikirim ke server; bekerja tanpa sinyal tetap aman',
        'Cara transfer wajib dipilih karena akun pada cara transfer itulah yang dipakai saat jurnal dibentuk',
        'Tagihan yang sudah diajukan pada dokumen lain tidak muncul lagi, supaya tidak terbayar dua kali',
        'Dokumen DRAFT belum diakui sebagai pembayaran; status pesanan baru berubah setelah DISETUJUI',
        'Nilai bayar tidak boleh melebihi sisa tagihan terminnya',
        'Pembayaran yang sudah disetujui tidak dapat diubah maupun dihapus; batalkan persetujuannya dulu',
        'Centang ajukan transfer bank hanya bila dibayar lewat transfer. Pembayaran tunai tidak perlu masuk antrean pencairan',
        'Pilihan Transfer atau Transitori ditentukan PER BARIS tagihan, bukan per dokumen. Satu pembayaran boleh memuat sebagian yang ditransfer langsung dan sebagian yang ditampung dulu',
        'Pilihan itu bukan sekadar penanda di layar: ia menentukan akun kredit jurnalnya. Salah memilih berarti salah akun, dan koreksinya harus lewat pembatalan posting',
        'Baris transitori TIDAK selesai dengan sendirinya. Ia harus direalisasikan lewat tab Transitori; selama belum, uangnya masih tercatat di akun perantara dan belum sampai ke penyedia',
        'Realisasi hanya dapat dilakukan atas pembayaran yang SUDAH DISETUJUI. Dokumen draf masih bisa disunting, sehingga barisnya dapat berubah setelah uangnya dicairkan',
        'Realisasi BUKAN posting jurnal. Realisasi menandai pencairannya sudah dikerjakan; jurnalnya diterbitkan menyusul lewat menu Posting Proses Transitori, sama seperti versi ZKoss',
        'Pembayaran yang salah satu barisnya sudah masuk batch realisasi tidak dapat disunting lagi. Batalkan dahulu realisasinya bila memang perlu dikoreksi'
      ],
      tanyaJawabTambahan: [
        [
          'Saya sudah menyimpan pembayaran, kenapa PO belum berkurang?',
          'Pembayaran baru diakui setelah disetujui. Selama masih draf, kolom dibayar pada PO memang belum berubah.'
        ],
        [
          'Bisakah membayar sebagian dari satu termin?',
          'Bisa. Kurangi nilai bayarnya, dan sisanya tetap muncul sebagai tagihan terbuka pada pembayaran berikutnya.'
        ],
        [
          'Apa bedanya Transfer dan Transitori?',
          'Transfer berarti uangnya langsung menuju rekening penyedia pada saat itu juga. Transitori berarti uangnya ditampung dahulu pada akun perantara dan pencairannya menyusul. Keduanya sama-sama mengurangi kewajiban Anda kepada penyedia, tetapi pada transfer uangnya sudah keluar dari kas/bank, sedangkan pada transitori belum. Bedanya nyata di jurnal: transfer memakai akun pada Cara Transfer, transitori memakai Akun Transitori pada Cara Transfer yang sama.'
        ],
        [
          'Kapan sebaiknya memakai Transitori?',
          'Ketika pembayarannya sudah disahkan tetapi pencairannya belum dapat dilakukan hari itu juga -- misalnya menunggu jadwal pencairan bank, menunggu dana masuk, atau pembayaran dikumpulkan dahulu untuk ditransfer sekaligus. Dengan transitori, tagihannya tercatat lunas terhadap penyedia sementara uangnya masih dapat ditelusuri di akun perantara.'
        ],
        [
          'Saya memilih Transitori. Apa yang harus dikerjakan setelahnya?',
          'Buka tab Transitori pada menu ini. Baris yang menunggu akan tampil di sana. Centang yang sudah benar-benar dicairkan, lalu tekan Realisasikan. Selama belum direalisasikan, uangnya masih tercatat di akun perantara.'
        ],
        [
          'Setelah direalisasikan, apakah jurnalnya langsung terbit?',
          'Belum. Realisasi dan posting jurnal adalah dua langkah terpisah, juga di versi ZKoss. Realisasi menandai pencairannya sudah dikerjakan; jurnalnya diterbitkan menyusul lewat menu Posting Proses Transitori yang membaca batch yang sudah disetujui. Pembatalan posting juga dikerjakan di sana.'
        ],
        [
          'Kenapa baris transitori saya tidak bisa dicentang di tab Transitori?',
          'Karena pembayarannya belum disetujui. Dokumen yang masih draf boleh disunting, sehingga barisnya bisa berubah setelah uangnya dicairkan. Setujui dahulu pembayarannya.'
        ],
        [
          'Saya salah memilih Transitori, padahal seharusnya Transfer. Bagaimana?',
          'Selama pembayarannya masih draf, buka dokumennya dan ubah pilihan pada barisnya. Bila sudah disetujui, batalkan dahulu persetujuannya. Bila barisnya sudah masuk batch realisasi, batalkan dahulu realisasinya -- baris yang sudah direalisasikan sudah punya arti akuntansi dan tidak dapat diubah begitu saja.'
        ],
      ]),
  'pengadaanBdp': SpesifikasiBantuanMenu(
      judul: 'Barang Dalam Proses',
      tujuan:
          'merekap penerimaan barang (BAST) beserta nilai dan statusnya, sekaligus memantau kiriman yang belum datang',
      workflow: [
        'Pilih pandangan Sudah Diterima atau Belum Datang',
        'Saring bila perlu',
        'Periksa nilai dan status',
        'Tindak lanjuti ke penyedia',
        'Pantau ulang setelah barang datang'
      ],
      ilustrasi: [
        'Sakelar dua pandangan',
        'Ringkasan nilai dan status persetujuan',
        'Penanda sudah/belum masuk stok',
        'Saringan penyedia dan periode',
        'Rincian nilai per pesanan'
      ],
      objekUtama: 'penerimaan barang beserta statusnya',
      hasilAkhir:
          'nilai barang yang sudah diterima terpantau, dan kiriman tertunda dapat ditagih ke penyedia',
      istilah: [
        'CIP = Pekerjaan Dalam Pelaksanaan, kelompok aset yang pengerjaannya belum selesai',
        'Sudah masuk stok = penerimaan ini sudah disalin menjadi faktur Kulakan',
        'Belum datang = jumlah dipesan dikurangi yang sudah diterima',
        'Terlambat = sudah melewati batas kirim yang disepakati'
      ],
      catatanPenting: [
        'Istilah "Barang Dalam Proses" di sini mengikuti versi ZKoss: sumbernya PENERIMAAN, bukan pesanan yang belum datang',
        'Penyaring CIP mati secara bawaan, karena pada pemasangan POS umumnya belum ada kelompok aset yang ditandai CIP',
        'Halaman ini tidak dapat diubah; isinya dihitung dari dokumen yang sudah tercatat'
      ]),
  'pengadaanPajak': SpesifikasiBantuanMenu(
      judul: 'Bayar Pajak',
      tujuan:
          'menyetor PPh yang dipotong dan mencatat PPN dari pembayaran vendor',
      workflow: [
        'Buka tab Terutang',
        'Centang baris yang disetor',
        'Isi NTPN dan tanggal setor',
        'Setor',
        'Periksa di tab Riwayat'
      ],
      ilustrasi: [
        'Ringkasan PPh dan PPN',
        'Daftar pajak terutang',
        'Form bukti setor',
        'Riwayat setoran',
        'Tab Terutang dan tab Riwayat'
      ],
      objekUtama: 'setoran pajak atas pembayaran vendor',
      hasilAkhir: 'kewajiban pajak tercatat lunas beserta bukti setornya',
      istilah: [
        'DPP = dasar pengenaan pajak, yaitu nilai penagihan termin',
        'PPh = pajak yang DIPOTONG dari pembayaran dan disetor ke negara',
        'PPN = pajak masukan yang DIBAYARKAN kepada vendor bersama tagihan',
        'NTPN = Nomor Transaksi Penerimaan Negara, bukti setoran diterima kas negara',
        'Terutang = pajak yang sudah timbul tetapi belum disetor'
      ],
      catatanPenting: [
        'Setiap menu Pengadaan punya dua tab: Dasbor (ringkasan angka dan tren) dan tab data untuk pembuatan serta penyuntingan dokumen',
        'Seluruh penyimpanan dan keputusan ditulis di perangkat lebih dulu, lalu dikirim ke server; bekerja tanpa sinyal tetap aman',
        'Pajak datang dari dua sumber: PPN/PPh yang diketik pada penerimaan barang (lencana BAST), dan PPh termin dari pembayaran vendor (lencana BAYAR)',
        'Baris yang dokumennya belum disetujui tetap ditampilkan tetapi belum dapat disetor',
        'PPN menambah tagihan ke vendor, sedangkan PPh dipotong dari kas yang keluar. Keduanya mudah tertukar, jadi ditampilkan terpisah',
        'Pajak baru menjadi terutang setelah pembayaran vendor disetujui',
        'Nilainya dihitung sebanding dengan porsi yang benar-benar dibayar, sehingga pembayaran sebagian tidak menyetorkan pajak atas nilai yang belum dibayar',
        'NTPN dan tanggal setor wajib diisi karena keduanya bukti bahwa uangnya masuk kas negara',
        'Baris yang sudah disetor tidak dapat disetor ulang'
      ],
      tanyaJawabTambahan: [
        [
          'Saya salah mengisi NTPN, bagaimana memperbaikinya?',
          'Batalkan setorannya di tab Riwayat. Rekamannya dinonaktifkan tanpa dihapus, dan pajaknya kembali menjadi terutang sehingga dapat disetor ulang dengan bukti yang benar.'
        ],
        [
          'Kenapa jenis pajaknya kosong?',
          'Jenis PPh dan PPN ditetapkan per termin saat membuat PO. Bila kosong, lengkapi dulu pada pesanan yang bersangkutan.'
        ],
      ]),
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
      if (s.istilah.isNotEmpty)
        BagianBantuan(
            'Kamus istilah yang dipakai halaman ini',
            'Istilah akuntansi kerap terdengar asing bagi petugas toko, padahal salah '
                'memahaminya langsung berakibat pada angka laporan. Berikut arti tiap '
                'istilah yang muncul di halaman ini. ${s.istilah.join('. ')}. '
                'Bila menemui istilah lain yang belum tercantum, tanyakan kepada bagian '
                'keuangan sebelum menyimpan data, karena memperbaiki catatan yang '
                'terlanjur salah jauh lebih sulit daripada bertanya di awal.'),
      if (s.catatanPenting.isNotEmpty)
        BagianBantuan(
            'Hal yang sering keliru dan akibatnya',
            'Kesalahan berikut paling sering terjadi di halaman ini. '
                '${s.catatanPenting.join('. ')}. Setiap butir di atas bukan sekadar '
                'anjuran administratif: masing-masing berpengaruh langsung pada angka '
                'yang dibaca pimpinan. Bila ragu, simpan sebagai draf terlebih dahulu, '
                'mintalah bagian keuangan memeriksa, baru lanjutkan ke tahap berikutnya.'),
      // BARU 20-08-2026: tanyaJawabTambahan sudah terisi untuk sejumlah menu sejak lama,
      // tetapi tidak pernah ikut dirender sehingga isinya tidak pernah sampai ke pengguna.
      // Kini ditampilkan sebagai bagian tersendiri, sekaligus menjadi sasaran pilihan
      // "Tanya Jawab" pada tombol bantuan mengambang.
      if (s.tanyaJawabTambahan.isNotEmpty)
        BagianBantuan(
            'Tanya Jawab halaman ini',
            s.tanyaJawabTambahan
                .where((qa) => qa.length >= 2)
                .map((qa) => 'Tanya: ${qa[0]} Jawab: ${qa[1]}')
                .join(' ')),
      ...platform.bagian,
    ],
  );
}
