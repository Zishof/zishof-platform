import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Panduan operasional wajib untuk penolakan API.
///
/// Server adalah sumber alasan bisnis, tetapi beberapa versi server lama hanya
/// mengirim solusi generik seperti "perbaiki data". Pemetaan ini menjadi pagar
/// terakhir di klien agar pengguna selalu memperoleh langkah yang dapat
/// dilakukan sendiri, lokasi menu/tombol, dan batas kapan perlu eskalasi.
class PanduanResolusiGalat {
  final String? judul;
  final List<String> solusi;

  const PanduanResolusiGalat({this.judul, required this.solusi});
}

PanduanResolusiGalat panduanResolusiGalat(String pesan,
    {String? aktivitas, String? kode}) {
  final lower = pesan.toLowerCase();

  if (lower.contains('batas maksimal hutang') ||
      lower.contains('maksimal boleh utang')) {
    return const PanduanResolusiGalat(
      judul: 'Batas hutang member terlampaui',
      solusi: [
        'Jangan klik Bayar atau Coba Kirim berulang; batas hutang adalah penolakan bisnis dan tidak akan berubah hanya karena dicoba lagi.',
        'Minta admin membuka Pelanggan > Tipe Member, memilih tipe member terkait, lalu memeriksa nilai Maksimal Boleh Utang.',
        'Jika member atau metode kasbon pada transaksi salah, minta supervisor melakukan koreksi; jangan mengubah jurnal transaksi pending secara manual.',
        'Setelah batas atau data transaksi sudah benar, buka Pesanan > Transaksi Pending lalu klik Coba Kirim Transaksi Pending.',
      ],
    );
  }

  if (lower.contains('metode pembayaran') &&
      lower.contains('tidak diizinkan') &&
      (lower.contains('jenis member') || lower.contains('tipe member'))) {
    return const PanduanResolusiGalat(
      judul: 'Metode pembayaran belum diizinkan untuk member',
      solusi: [
        'Jangan klik Bayar, Sinkron, atau Coba Kirim berulang; transaksi belum diterima server dan jurnal pending lokal tetap aman.',
        'Menaikkan Batas Transaksi atau Maksimal Boleh Utang tidak menyelesaikan penolakan ini karena kendalanya adalah izin metode pembayaran.',
        'Minta admin membuka Pelanggan > Jenis Member dan Pelanggan > Tipe Member. Pada data yang disebutkan dalam pesan, centang metode terkait di Cara Bayar yang Diizinkan/Cara Bayar dan pastikan Cakupan Toko mencakup toko kasir, lalu klik Simpan.',
        'Sesudah admin menyimpan, kasir menekan Sinkronkan lalu Muat Ulang. Buka Pesanan > Transaksi Pending dan klik Coba Kirim Transaksi Pending satu kali.',
        'Jika tetap ditolak, kirim kode transaksi, nama member, Jenis/Tipe Member, metode pembayaran, dan Informasi Teknis kepada admin; jangan membuat transaksi pengganti atau mengubah payload pending.',
      ],
    );
  }

  if (lower.contains('toko tidak diketahui') ||
      lower.contains('toko wajib dipilih') ||
      lower.contains('pilih toko terlebih dahulu')) {
    return const PanduanResolusiGalat(
      judul: 'Toko aktif belum dipilih',
      solusi: [
        'Klik pilihan toko pada bilah atas, lalu pilih toko yang sedang dioperasikan.',
        'Klik Muat Ulang setelah nama toko yang benar tampil, kemudian ulangi prosesnya.',
        'Jika daftar toko kosong atau toko yang benar tidak tersedia, minta admin memeriksa hubungan akun, grup pengguna, dan akses toko.',
      ],
    );
  }

  if (lower.contains('sesi kas') || lower.contains('buka kas')) {
    return const PanduanResolusiGalat(
      judul: 'Sesi kas perlu diperiksa',
      solusi: [
        'Klik Kas pada bilah atas dan pastikan sesi kas perangkat ini berstatus Terbuka.',
        'Jika sesi masih terbuka pada perangkat lain, tutup sesi tersebut secara resmi atau minta supervisor melakukan koreksi sesi kas.',
        'Setelah sesi kas benar, kembali ke proses sebelumnya dan klik kirim atau simpan satu kali.',
      ],
    );
  }

  if (lower.contains('wajib memilih nama pelanggan') ||
      lower.contains('member wajib dipilih') ||
      lower.contains('pelanggan terlebih dahulu')) {
    return const PanduanResolusiGalat(
      judul: 'Pelanggan perlu dipilih',
      solusi: [
        'Kembali ke Kasir/POS, klik Pilih Member atau tekan F5, lalu pilih pelanggan yang benar.',
        'Periksa kembali metode pembayaran; metode kasbon, hutang, atau potong saldo harus memiliki pelanggan.',
        'Setelah nama pelanggan tampil di keranjang, klik Bayar satu kali.',
      ],
    );
  }

  if (lower.contains('saldo') &&
      (lower.contains('tidak cukup') || lower.contains('kurang'))) {
    return const PanduanResolusiGalat(
      judul: 'Saldo member belum mencukupi',
      solusi: [
        'Periksa kembali member dan nominal pembayaran yang dipilih pada Kasir/POS.',
        'Jika saldo memang kurang, buka Pelanggan > Topup untuk menambah saldo sesuai bukti pembayaran dan kewenangan Anda.',
        'Setelah topup berhasil, kembali ke Kasir/POS, muat ulang data member, lalu lakukan pembayaran satu kali.',
      ],
    );
  }

  if (lower.contains('stok') || lower.contains('kadaluarsa')) {
    final kedaluwarsa = lower.contains('kadaluarsa');
    return PanduanResolusiGalat(
      judul: kedaluwarsa ? 'Produk tidak boleh dijual' : 'Stok belum mencukupi',
      solusi: [
        'Periksa nama produk dan jumlahnya pada keranjang.',
        kedaluwarsa
            ? 'Pisahkan produk kedaluwarsa dari stok jual, lalu pilih batch atau produk pengganti yang masih layak.'
            : 'Buka Stok Opname atau minta petugas stok memeriksa jumlah fisik bila stok di layar tidak sesuai.',
        'Ulangi pembayaran hanya setelah produk, jumlah, atau stok sudah diperbaiki.',
      ],
    );
  }

  if (lower.contains('akses') ||
      lower.contains('hak ') ||
      lower.contains('tidak diizinkan') ||
      lower.contains('hanya supervisor') ||
      lower.contains('hanya admin')) {
    return const PanduanResolusiGalat(
      judul: 'Akun belum memiliki kewenangan',
      solusi: [
        'Jangan mengulang tombol yang sama; masuk dengan akun yang memang berwenang atau minta persetujuan supervisor.',
        'Minta admin membuka pengaturan Grup Pengguna dan memeriksa izin menu serta izin tindakan yang disebutkan pada pesan.',
        'Setelah izin diperbarui, keluar lalu masuk kembali agar hak akses dimuat ulang, kemudian coba satu kali.',
      ],
    );
  }

  if (lower.contains('sudah tercatat') ||
      lower.contains('duplicate key') ||
      lower.contains('unique constraint')) {
    return const PanduanResolusiGalat(
      judul: 'Transaksi mungkin sudah tercatat',
      solusi: [
        'Jangan menekan Bayar atau Kirim Ulang lagi sebelum melakukan pemeriksaan.',
        'Buka Riwayat Penjualan dan cari kode transaksi yang disebutkan pada detail kendala.',
        'Jika transaksi ada, tidak perlu membuat transaksi pengganti; jika tidak ada, salin Informasi Teknis dan minta supervisor melakukan rekonsiliasi.',
      ],
    );
  }

  final pembayaran = aktivitas == 'bayar' ||
      aktivitas == 'pembayaran' ||
      (aktivitas?.endsWith('_bayar') ?? false);
  if (pembayaran) {
    return const PanduanResolusiGalat(
      judul: 'Pembayaran perlu diperiksa',
      solusi: [
        'Jangan langsung menekan Bayar atau Coba Kirim berulang; baca alasan penolakan dan periksa Riwayat Penjualan terlebih dahulu.',
        'Periksa keranjang, member, metode pembayaran, nominal uang diterima, toko aktif, dan status sesi kas sesuai alasan yang tampil.',
        'Setelah data diperbaiki, klik Bayar atau Coba Kirim satu kali.',
        'Jika alasan belum dapat diselesaikan, buka Informasi Teknis, klik Salin Informasi Teknis, lalu kirimkan bersama kode referensi kepada supervisor/admin.',
      ],
    );
  }

  return const PanduanResolusiGalat(solusi: [
    'Baca alasan yang tampil dan kembali ke kolom atau data yang disebutkan untuk memperbaikinya.',
    'Klik Muat Ulang agar data terbaru tampil, lalu ulangi tindakan satu kali setelah perbaikan selesai.',
    'Jika menu, data, atau kewenangan yang dibutuhkan tidak tersedia, minta admin/supervisor memeriksanya.',
    'Jika masih gagal, buka Informasi Teknis, klik Salin Informasi Teknis, lalu kirimkan bersama kode referensi dan langkah terakhir yang dilakukan.',
  ]);
}

/// Informasi kesalahan yang aman dibaca pengguna. Detail teknis sengaja
/// dipisahkan agar tidak memenuhi pesan utama, tetapi tetap dapat disalin
/// untuk administrator saat penyelesaian mandiri belum berhasil.
class AppErrorInfo {
  final String judul;
  final String pesan;
  final List<String> solusi;
  final String teknis;
  final String kodeReferensi;

  const AppErrorInfo({
    required this.judul,
    required this.pesan,
    required this.solusi,
    required this.teknis,
    required this.kodeReferensi,
  });

  factory AppErrorInfo.dari(Object error, {String? aktivitas}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final kode =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    if (lower.contains('nama pengguna') ||
        lower.contains('username') ||
        lower.contains('kata sandi') ||
        lower.contains('password')) {
      return AppErrorInfo(
        judul: 'Belum dapat masuk',
        pesan: 'Nama pengguna atau kata sandi belum cocok dengan data akun.',
        solusi: const [
          'Periksa kembali huruf besar/kecil dan pastikan tidak ada spasi yang ikut terketik.',
          'Pastikan akun yang dipakai memang memiliki akses ke aplikasi POS.',
          'Jika lupa kata sandi atau akun terkunci, minta admin melakukan pemeriksaan akun.',
        ],
        teknis: '${aktivitas ?? 'login'} | $raw',
        kodeReferensi: kode,
      );
    }
    if (lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('tidak bisa menghubungi') ||
        lower.contains('network')) {
      return AppErrorInfo(
        judul: 'Server belum dapat dihubungi',
        pesan: 'Aplikasi belum memperoleh jawaban dari server.',
        solusi: const [
          'Pastikan internet atau jaringan kantor sedang tersambung.',
          'Periksa Alamat Server melalui tombol pengaturan di layar masuk.',
          'Coba kembali setelah beberapa saat; server mungkin sedang dimulai ulang.',
        ],
        teknis: '${aktivitas ?? 'permintaan jaringan'} | $raw',
        kodeReferensi: kode,
      );
    }
    if (lower.contains('sesi') ||
        lower.contains('401') ||
        lower.contains('unauthorized')) {
      return AppErrorInfo(
        judul: 'Sesi masuk telah berakhir',
        pesan: 'Demi keamanan, aplikasi perlu melakukan masuk ulang.',
        solusi: const [
          'Kembali ke layar masuk dan masukkan akun Anda kembali.',
          'Jika kejadian terus berulang, pastikan tanggal dan waktu perangkat sudah benar.',
        ],
        teknis: '${aktivitas ?? 'validasi sesi'} | $raw',
        kodeReferensi: kode,
      );
    }
    if (lower.contains('balasan server') ||
        lower.contains('format') ||
        lower.contains('json') ||
        lower.contains('http')) {
      return AppErrorInfo(
        judul: 'Jawaban server belum dapat diproses',
        pesan:
            'Aplikasi menerima jawaban yang berbeda dari format yang dibutuhkan.',
        solusi: const [
          'Pastikan Alamat Server mengarah ke instalasi AIS/Al-Bahjah yang benar.',
          'Coba Muat Ulang. Jika server baru diperbarui, tunggu restart selesai.',
          'Jika tetap terjadi, kirim kode referensi dan Informasi Teknis kepada admin.',
        ],
        teknis: '${aktivitas ?? 'pemrosesan balasan'} | $raw',
        kodeReferensi: kode,
      );
    }
    return AppErrorInfo(
      judul: 'Proses belum berhasil',
      pesan: aktivitas == null
          ? 'Aplikasi belum dapat menyelesaikan permintaan Anda.'
          : 'Aplikasi belum dapat menyelesaikan proses $aktivitas.',
      solusi: const [
        'Periksa kembali data yang diisi, lalu coba sekali lagi.',
        'Muat ulang halaman bila data terlihat belum diperbarui.',
        'Jika tetap terjadi, kirim kode referensi dan Informasi Teknis kepada admin.',
      ],
      teknis: '${aktivitas ?? 'proses aplikasi'} | $raw',
      kodeReferensi: kode,
    );
  }
}

class AppErrorPanel extends StatelessWidget {
  final AppErrorInfo info;
  final bool ringkas;
  const AppErrorPanel({super.key, required this.info, this.ringkas = false});

  @override
  Widget build(BuildContext context) {
    final detailTeknis =
        'Kode referensi: ${info.kodeReferensi}\n${info.teknis}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(info.judul, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(info.pesan),
        if (!ringkas) ...[
          const SizedBox(height: 8),
          const Text('Yang dapat Anda lakukan:',
              style: TextStyle(fontWeight: FontWeight.w600)),
          ...info.solusi.map((s) => Padding(
              padding: const EdgeInsets.only(top: 3), child: Text('• $s'))),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title:
                const Text('Informasi Teknis', style: TextStyle(fontSize: 13)),
            children: [
              SelectableText(
                detailTeknis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: detailTeknis));
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Informasi teknis sudah disalin. Silakan tempelkan kepada admin/developer.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 17),
                  label: const Text('Salin Informasi Teknis'),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

Future<void> tampilkanKesalahan(BuildContext context, Object error,
    {String? aktivitas}) {
  final info = error is AppErrorInfo
      ? error
      : AppErrorInfo.dari(error, aktivitas: aktivitas);
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Ada kendala'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(child: AppErrorPanel(info: info)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup'))
      ],
    ),
  );
}
