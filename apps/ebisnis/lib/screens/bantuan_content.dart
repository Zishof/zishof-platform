class BagianBantuan {
  final String judul;
  final String isi;
  const BagianBantuan(this.judul, this.isi);
}

class ArtikelBantuan {
  final String id;
  final String judul;
  final String ringkasan;
  final List<BagianBantuan> bagian;
  const ArtikelBantuan({
    required this.id,
    required this.judul,
    required this.ringkasan,
    required this.bagian,
  });

  int get jumlahKata => bagian
      .map((b) => '${b.judul} ${b.isi}')
      .join(' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((kata) => kata.isNotEmpty)
      .length;
}

const _dasarOperasional = <BagianBantuan>[
  BagianBantuan(
    'Tujuan, peran pengguna, dan prinsip kerja aman',
    'Halaman POS dipakai untuk mengubah pilihan barang menjadi transaksi penjualan yang tercatat, dapat dibayar, dapat dicetak, dan dapat ditelusuri kembali. Kasir bertugas memastikan barang, jumlah, pelanggan, harga, promo, metode pembayaran, dan uang yang diterima benar sebelum menekan Bayar. Supervisor menangani tindakan yang memerlukan otorisasi seperti pembatalan, pembukaan laci manual, koreksi tertentu, atau penyelesaian selisih. Admin menyiapkan produk, harga, perangkat, cara bayar, toko, dan hak akses. Pemisahan peran ini penting karena tombol yang tidak tampak atau ditolak bukan selalu kerusakan; sering kali akun memang tidak memiliki izin. Jangan meminjam akun orang lain. Gunakan akun sendiri agar audit mencatat pelaku yang benar. Sebelum mulai, periksa nama toko, nama pengguna, status koneksi, printer, laci, dan sesi kas. Jika toko mewajibkan sesi kas, masukkan modal awal sesuai uang nyata di laci. Jangan menebak nominal. Transaksi yang sudah berhasil tidak boleh dibuat ulang hanya karena struk gagal keluar; gunakan cetak ulang dari riwayat. Prinsip utamanya adalah satu kejadian penjualan menghasilkan satu dokumen, satu pembayaran yang dapat direkonsiliasi, dan jejak perubahan yang utuh.',
  ),
  BagianBantuan(
    'Persiapan awal shift dan pemeriksaan sebelum melayani',
    'Mulailah shift dengan memastikan alamat server menunjuk lingkungan yang benar dan indikator sinkronisasi tidak menampilkan kegagalan lama yang belum diselesaikan. Pilih toko atau outlet yang sesuai lokasi fisik. Kesalahan outlet membuat stok, nomor struk, kas, dan laporan masuk ke tempat yang salah. Pastikan tanggal serta jam perangkat benar karena waktu dipakai untuk urutan transaksi, laporan shift, dan sinkronisasi. Buka sesi kas menggunakan jumlah uang tunai yang benar-benar tersedia, bukan saldo perkiraan kemarin. Lakukan uji cetak singkat bila printer baru dinyalakan, kertas diganti, atau koneksi USB/Bluetooth berubah. Periksa laci uang dan layar pelanggan bila digunakan. Pastikan katalog menampilkan produk dan harga terbaru; jalankan sinkronisasi jika ada perubahan master dari kantor. Untuk toko yang beroperasi offline, lihat antrean transaksi tertunda sebelum mulai agar operator mengetahui apakah ada data yang belum sampai ke server. Pisahkan masalah perangkat dari masalah data: printer tidak mencetak tidak berarti penjualan gagal, sedangkan pesan server menolak pembayaran berarti transaksi belum selesai. Catat kondisi awal yang tidak normal kepada supervisor sebelum antrean pelanggan ramai. Pemeriksaan dua menit di awal shift mencegah koreksi panjang di akhir hari.',
  ),
  BagianBantuan(
    'Mencari produk, memindai barcode, dan menyusun keranjang',
    'Fokuskan kolom pencarian lalu pindai barcode. Pemindai biasanya bertindak seperti keyboard dan mengirim Enter; karena itu kursor harus berada di kolom pencarian. Jika barcode tidak ditemukan, cari dengan sebagian nama atau kode produk, pilih kategori, lalu sentuh atau klik kartu produk. Setiap pemilihan menambah barang ke keranjang. Periksa nama, varian, satuan, jumlah, harga satuan, tambahan atau topping, diskon, dan subtotal baris. Produk yang tampak mirip dapat memiliki satuan atau harga berbeda. Gunakan tombol tambah dan kurang untuk mengubah kuantitas; jangan memindai berulang tanpa melihat jumlah. Hapus hanya baris yang memang batal dibeli. Bila produk memiliki pilihan ekstra, selesaikan dialog ekstra sebelum menambahkan agar harga dan deskripsi pesanan akurat. Untuk barang timbang, ikuti konfigurasi barcode timbangan dan pastikan berat terbaca wajar. Peringatan stok adalah alat bantu, bukan alasan mengabaikan barang fisik. Bila stok sistem nol tetapi barang ada, hubungi petugas stok sesuai prosedur, jangan membuat produk pengganti sembarang. Setelah seluruh barang masuk, bandingkan keranjang dengan barang di meja dari kiri ke kanan. Kebiasaan membaca ulang jumlah dan subtotal mengurangi retur akibat salah scan.',
  ),
  BagianBantuan(
    'Memilih pelanggan, promo, pajak, dan harga akhir',
    'Pilih pelanggan atau anggota sebelum pembayaran bila transaksi memakai harga anggota, saldo, limit hutang, poin, cashback, atau riwayat khusus. Cari menggunakan kode, nama, nomor telepon, kartu, atau QR sesuai fasilitas toko. Konfirmasikan identitas tanpa membacakan data pribadi berlebihan. Sesudah pelanggan dipilih, sistem dapat menghitung ulang promo dan harga. Amati subtotal, diskon, cashback, pajak, pembulatan, dan total akhir. Promo otomatis diterapkan jika semua syarat terpenuhi; promo manual harus dipilih oleh kasir. Baca syarat minimal belanja, produk sasaran, periode, kuota, metode pembayaran, dan kemungkinan promo tidak dapat digabung. Jangan menjanjikan diskon sebelum indikator pada keranjang benar-benar berubah. Jika harga di rak berbeda dari aplikasi, hentikan sejenak dan ikuti kebijakan toko: verifikasi label, waktu berlaku, serta produk yang dimaksud. Jangan mengubah harga tanpa hak akses. Untuk transaksi tanpa pelanggan, pastikan pilihan pelanggan sebelumnya sudah dibersihkan agar poin atau hutang tidak masuk ke akun yang salah. Harga akhir yang terlihat sebelum Bayar adalah angka yang harus dikonfirmasi kepada pelanggan. Perubahan pelanggan atau metode pembayaran dapat memicu perhitungan ulang, jadi lakukan pemeriksaan terakhir setelah semua pilihan selesai.',
  ),
  BagianBantuan(
    'Pembayaran tunai, non-tunai, split, dan konfirmasi akhir',
    'Tekan Bayar hanya setelah keranjang dan identitas pelanggan benar. Pilih metode yang benar: tunai, kartu, transfer, QR, saldo anggota, hutang, atau metode lain yang diaktifkan toko. Pada pembayaran tunai, masukkan jumlah yang benar-benar diberikan pelanggan; sistem menghitung kembalian. Hitung uang di depan pelanggan, sebutkan nominal diterima dan kembalian, lalu simpan uang setelah transaksi disetujui agar tidak tertukar. Untuk non-tunai, jangan menganggap tangkapan layar sebagai bukti final. Tunggu status berhasil dari perangkat atau penyedia pembayaran sesuai prosedur. Pada split payment, alokasikan nominal ke setiap metode sampai sisa tepat nol. Periksa bahwa bagian tunai dan non-tunai tidak tertukar. Jangan menekan Bayar berulang saat sistem sedang memproses. Jika respons lambat, lihat indikator dan riwayat sebelum mencoba kembali; kode unik transaksi melindungi dari duplikasi, tetapi disiplin operator tetap diperlukan. Ketika muncul konfirmasi berhasil, catat nomor transaksi dan cetak struk. Jika muncul penolakan, baca pesan lengkap, perbaiki penyebab, kemudian ulangi tindakan yang memang gagal. Jangan membuat keranjang baru sebelum memastikan transaksi pertama tidak tercatat. Untuk transaksi hutang atau saldo, pastikan limit dan otorisasi pelanggan sah.',
  ),
  BagianBantuan(
    'Struk, laci kas, layar pelanggan, dan transaksi tertahan',
    'Setelah pembayaran berhasil, struk dapat dicetak, dibagikan melalui kanal yang disediakan, atau dicetak ulang. Kegagalan printer tidak membatalkan dokumen penjualan. Periksa kertas, tutup printer, kabel, daya, antrean cetak, pilihan printer, dan ukuran kertas; lalu gunakan Cetak Ulang pada transaksi yang sama. Jangan membayar ulang hanya demi memperoleh struk. Laci kas biasanya terbuka saat pembayaran tunai. Pembukaan manual harus memiliki alasan operasional dan dapat dibatasi PIN supervisor. Layar pelanggan menampilkan barang, total, promo, dan status pembayaran; gunakan sebagai sarana konfirmasi, tetapi keranjang kasir tetap sumber pengendalian utama. Keranjang Tertahan berguna saat pelanggan mengambil barang lain atau antrean perlu dilayani bergantian. Beri catatan yang mudah dikenali, simpan, lalu pastikan keranjang aktif kosong sebelum melayani pelanggan berikutnya. Saat melanjutkan keranjang tertahan, periksa ulang harga, promo, stok, pelanggan, dan metode bayar karena kondisi dapat berubah. Hapus keranjang tertahan yang memang tidak dilanjutkan sesuai kewenangan. Jangan memakai fitur tahan sebagai pengganti transaksi kredit. Data tertahan belum merupakan penjualan dan belum boleh dihitung sebagai penerimaan kas.',
  ),
  BagianBantuan(
    'Koneksi terputus, mode offline, dan sinkronisasi',
    'Aplikasi dapat mendukung operasi terbatas saat koneksi tidak stabil. Perhatikan indikator online, jumlah antrean, waktu percobaan terakhir, dan pesan kegagalan. Transaksi offline harus memiliki identitas unik dan disimpan di perangkat sampai server mengakui penerimaan. Jangan menghapus data aplikasi, membersihkan penyimpanan, mengganti perangkat, atau melakukan instal ulang selama antrean masih ada. Tekan Sinkronkan sekali lalu tunggu hasil per item. Status terkirim berarti server telah menerima; status gagal perlu dibaca sebabnya, misalnya sesi berakhir, hak akses berubah, referensi tidak ditemukan, atau data tidak valid. Jangan membuat salinan transaksi untuk mengatasi antrean gagal. Jika internet kembali, sinkronkan sebelum menutup shift. Bandingkan jumlah transaksi lokal, transaksi server, uang tunai, dan metode non-tunai. Bila aplikasi menunjukkan konflik, catat nomor lokal, waktu, nilai, pengguna, dan pesan. Berikan bukti tersebut kepada admin tanpa mengirim sandi. Mode offline bukan izin untuk melewati aturan stok, limit, atau otorisasi. Beberapa metode pembayaran memang harus online. Informasikan kepada pelanggan secara jelas dan pilih alternatif yang sah. Keutuhan data lebih penting daripada memaksa transaksi terlihat selesai pada layar.',
  ),
  BagianBantuan(
    'Retur, pembatalan, koreksi, dan audit',
    'Kesalahan setelah transaksi berhasil ditangani melalui retur atau pembatalan resmi, bukan menghapus dokumen atau membuat penjualan negatif secara manual. Cari transaksi asli melalui nomor struk, tanggal, kasir, atau pelanggan. Cocokkan produk, jumlah, metode bayar, dan alasan. Retur dapat mengembalikan barang ke stok bila kondisi barang memenuhi aturan; barang rusak atau kedaluwarsa dapat memiliki jalur stok berbeda. Pengembalian uang harus mengikuti metode dan persetujuan toko. Pembatalan penuh biasanya memerlukan kewenangan lebih tinggi serta alasan yang dicatat. Dokumen yang sudah posted dipertahankan dan dibuatkan dokumen pembalik agar laporan serta audit tetap dapat dijelaskan. Jangan memakai akun supervisor tanpa kehadirannya. Sebelum menyimpan, baca ringkasan dampak: jumlah dikembalikan, stok, kas, poin, hutang, pajak, dan referensi. Setelah berhasil, cetak atau simpan bukti koreksi dan serahkan kepada pihak terkait. Bila hanya struk salah cetak, gunakan cetak ulang—itu bukan alasan retur. Bila harga salah tetapi transaksi belum dibayar, koreksi keranjang. Bila sudah dibayar, ikuti prosedur resmi. Riwayat audit melindungi kasir dan toko karena menunjukkan apa yang terjadi, kapan, serta oleh siapa.',
  ),
  BagianBantuan(
    'Menutup shift dan melakukan rekonsiliasi',
    'Sebelum menutup sesi, hentikan penerimaan transaksi baru dan selesaikan semua keranjang aktif atau tertahan yang memang harus diproses. Sinkronkan antrean sampai tidak ada transaksi tertunda. Cetak atau buka ringkasan sesi: saldo awal, penjualan tunai, penerimaan non-tunai, pengeluaran atau pembukaan laci yang tercatat, retur, pembatalan, setoran, dan kas seharusnya. Hitung uang fisik menurut pecahan di tempat yang aman. Masukkan kas aktual tanpa menyesuaikan angka agar terlihat sama. Jika ada selisih, hitung ulang, periksa transaksi terakhir, keranjang tertahan, pembayaran split, retur, uang kembalian, dan transaksi yang belum tersinkron. Tulis alasan yang faktual; jangan memakai keterangan umum seperti salah hitung bila penyebab belum diketahui. Supervisor memeriksa dan menyetujui sesuai kebijakan. Cocokkan pula laporan kartu, QR, transfer, saldo, dan hutang dengan sumber masing-masing. Tutup sesi hanya setelah semua bukti tersedia. Logout setelah penutupan agar transaksi shift berikutnya tidak memakai identitas lama. Simpan perangkat, printer, pemindai, dan uang sesuai prosedur. Rekonsiliasi yang konsisten membuat laporan harian dapat dipercaya dan memudahkan penyelesaian selisih tanpa menuduh operator secara keliru.',
  ),
  BagianBantuan(
    'Pemecahan masalah dan informasi yang harus dicatat',
    'Jika halaman tidak merespons, jangan langsung menutup paksa. Tunggu proses aktif, lihat indikator, dan catat tahap terakhir. Untuk masalah produk, catat kode, nama, barcode, toko, harga yang diharapkan, dan harga yang tampil. Untuk pembayaran, catat nomor transaksi, waktu, total, metode, status pada alat pembayaran, serta apakah struk terbentuk. Untuk sinkronisasi, catat ID antrean dan pesan server. Untuk printer, catat nama printer, koneksi, ukuran kertas, dan hasil uji. Ambil tangkapan layar tanpa memperlihatkan sandi, PIN, nomor kartu lengkap, atau data pribadi yang tidak perlu. Coba tindakan aman berurutan: periksa input, tutup dialog, muat ulang data, periksa koneksi, sinkronkan, lalu hubungi supervisor. Hindari menghapus cache, database lokal, atau memasang ulang aplikasi tanpa arahan teknis karena dapat menghilangkan antrean. Pesan akses ditolak diselesaikan melalui pengaturan role, bukan percobaan berulang. Pesan sesi ditutup memerlukan sesi baru atau persetujuan. Pesan duplikat perlu diperiksa di riwayat karena mungkin transaksi pertama sudah diterima. Laporan masalah yang terstruktur mempercepat bantuan: siapa, perangkat apa, outlet mana, kapan, langkah, hasil yang diharapkan, hasil aktual, dan bukti.',
  ),
];

const artikelBantuan = <ArtikelBantuan>[
  ArtikelBantuan(
    id: 'desktop',
    judul: 'POS Desktop',
    ringkasan:
        'Panduan operator kasir Windows dengan keyboard, scanner, printer, laci, dan layar kedua.',
    bagian: [
      BagianBantuan(
        'Orientasi tampilan desktop dan pintasan utama',
        'Pada desktop, layar dibagi menjadi navigasi, pencarian dan katalog produk, keranjang, ringkasan total, serta tombol tindakan. Ruang lebar memungkinkan katalog dan keranjang terlihat bersamaan. Gunakan mouse untuk eksplorasi dan keyboard untuk pelayanan cepat. F1 membuka bantuan, F2 memulai pembayaran, F3 menahan keranjang, F4 memilih metode bayar, F5 memilih member, F6 membuka laci sesuai izin, F7 memusatkan keranjang, F8 menjalankan sinkronisasi, dan F9 membuka layar pelanggan. Pintasan dapat berbeda menurut konfigurasi; label pada tombol adalah rujukan terakhir. Scanner barcode harus mengarahkan input ke pencarian. Jangan mengetik saat dialog pembayaran terbuka karena karakter dapat masuk ke kolom nominal. Gunakan Tab untuk berpindah kontrol dan Escape untuk menutup dialog yang belum disimpan. Pada monitor ganda, letakkan layar pelanggan di monitor yang menghadap pembeli dan pastikan tidak menampilkan menu admin. Ilustrasi di bawah menunjukkan urutan kerja dari area kiri ke kanan: cari barang, susun keranjang, tinjau total, pilih pembayaran, konfirmasi, lalu cetak. Operator sebaiknya tidak mengubah ukuran jendela selama antrean ramai agar posisi kontrol konsisten dan kesalahan klik berkurang.',
      ),
      ..._dasarOperasional,
    ],
  ),
  ArtikelBantuan(
    id: 'android',
    judul: 'POS Android',
    ringkasan:
        'Panduan kasir ponsel/tablet dengan sentuhan, kamera atau scanner Bluetooth, dan printer mobile.',
    bagian: [
      BagianBantuan(
        'Orientasi Android, sentuhan, dan perangkat bergerak',
        'Pada Android, menu utama dibuka dari ikon navigasi dan panel disusun vertikal agar mudah disentuh. Gulir halaman untuk berpindah dari pencarian ke katalog, keranjang, dan pembayaran. Ketuk sekali, lalu tunggu respons; ketukan berulang dapat menambah kuantitas tanpa sengaja. Gunakan tombol kembali untuk menutup dialog, bukan menutup aplikasi dari daftar recent. Barcode dapat dipindai dengan scanner Bluetooth yang bertindak sebagai keyboard atau fasilitas kamera bila tersedia. Pastikan keyboard virtual tidak menutupi tombol Bayar; tutup keyboard setelah selesai mengetik. Tablet lebih nyaman dalam orientasi lanskap, sedangkan ponsel dapat memakai potret. Jaga baterai di atas batas aman, koneksi Wi-Fi stabil, Bluetooth printer aktif, dan izin aplikasi tidak dicabut. Jangan berbagi hotspot yang tidak dipercaya. Bila layar terkunci di tengah pembayaran, buka kembali aplikasi dan periksa riwayat sebelum mengulang. Diagram menunjukkan alur sentuh yang sama dengan desktop, tetapi setiap tahap tampil sebagai panel berurutan. Ilustrasi perangkat menandai lokasi menu, kolom scan, kartu barang, keranjang, total, dan tombol Bayar. Gunakan stylus hanya bila tidak mengurangi ketepatan sentuhan dan bersihkan layar agar angka tetap mudah dibaca.',
      ),
      ..._dasarOperasional,
    ],
  ),
  ArtikelBantuan(
    id: 'jsp',
    judul: 'POS JSP / Browser',
    ringkasan:
        'Panduan POS web AIS di browser, termasuk sesi, refresh, tab, dan perilaku jaringan.',
    bagian: [
      BagianBantuan(
        'Orientasi browser dan batas aman navigasi',
        'POS JSP berjalan di dalam AIS melalui browser. Pastikan alamat, ikon keamanan jaringan, dan nama lingkungan benar sebelum login. Gunakan satu tab POS aktif per kasir untuk mencegah dua keranjang atau sesi bersaing. Hindari tombol Back, Forward, Refresh, dan penutupan tab ketika pembayaran sedang diproses. Navigasi memakai menu AIS, sedangkan area POS memuat status sesi kas, pencarian barcode, kategori, katalog, keranjang, pembayaran, ringkasan stok, dan transaksi terakhir. F2 memusatkan pencarian dan F12 memulai pembayaran pada implementasi JSP; lihat badge tombol karena pintasan dapat berbeda dari aplikasi Flutter. Browser harus mengizinkan popup untuk layar pelanggan dan pencetakan. Zoom 100 persen direkomendasikan agar tombol dan tabel tidak terpotong. Bila sesi login berakhir, jangan mengisi ulang transaksi sebelum memeriksa apakah pembayaran terakhir sudah tersimpan. Diagram menjelaskan perjalanan data dari browser ke API AIS, validasi hak akses, penyimpanan transaksi, pembaruan stok dan kas, lalu respons untuk struk. Ilustrasi browser menunjukkan bahwa katalog berada di kiri dan keranjang di kanan pada layar lebar, kemudian bertumpuk pada layar sempit. Gunakan reload hanya setelah memastikan tidak ada permintaan aktif dan keranjang penting sudah ditahan.',
      ),
      ..._dasarOperasional,
    ],
  ),
];
