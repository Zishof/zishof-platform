import 'package:flutter/material.dart';

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
    final kode = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    if (lower.contains('nama pengguna') || lower.contains('username') ||
        lower.contains('kata sandi') || lower.contains('password')) {
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
    if (lower.contains('socket') || lower.contains('timeout') ||
        lower.contains('tidak bisa menghubungi') || lower.contains('network')) {
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
    if (lower.contains('sesi') || lower.contains('401') || lower.contains('unauthorized')) {
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
    if (lower.contains('balasan server') || lower.contains('format') ||
        lower.contains('json') || lower.contains('http')) {
      return AppErrorInfo(
        judul: 'Jawaban server belum dapat diproses',
        pesan: 'Aplikasi menerima jawaban yang berbeda dari format yang dibutuhkan.',
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(info.judul, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(info.pesan),
        if (!ringkas) ...[
          const SizedBox(height: 8),
          const Text('Yang dapat Anda lakukan:', style: TextStyle(fontWeight: FontWeight.w600)),
          ...info.solusi.map((s) => Padding(
              padding: const EdgeInsets.only(top: 3), child: Text('• $s'))),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Informasi Teknis', style: TextStyle(fontSize: 13)),
            children: [SelectableText(
              'Kode referensi: ${info.kodeReferensi}\n${info.teknis}',
              style: Theme.of(context).textTheme.bodySmall,
            )],
          ),
        ),
      ]),
    );
  }
}

Future<void> tampilkanKesalahan(
    BuildContext context, Object error, {String? aktivitas}) {
  final info = error is AppErrorInfo ? error : AppErrorInfo.dari(error, aktivitas: aktivitas);
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Ada kendala'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(child: AppErrorPanel(info: info)),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    ),
  );
}
