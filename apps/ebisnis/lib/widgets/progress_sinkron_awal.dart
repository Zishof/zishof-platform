import 'package:flutter/material.dart';

/// <h3>Dialog progress SINKRON AWAL data (hidrasi cache offline pertama).</h3>
///
/// Dipakai saat cache lokal masih KOSONG dan data server banyak (mis. 2.697
/// member): tanpa ini user hanya melihat satu halaman kecil dan tidak tahu
/// proses unduh massal sedang berjalan. Dialog menampilkan progress bar
/// determinate (persentase + "x / y") bila total diketahui, fallback
/// indeterminate bila tidak; ditutup otomatis dgn centang elastis saat
/// selesai. Gagal di tengah -> dialog menutup dan error diteruskan ke
/// pemanggil (data yang sudah terunduh TETAP tersimpan; sinkron berikutnya
/// melanjutkan, tidak mengulang dari nol bila alurnya inkremental).
///
/// Pemakaian:
/// ```dart
/// final total = await jalankanDenganProgressSinkron<int>(context,
///   judul: 'Sinkron member ke cache offline',
///   satuan: 'member',
///   tugas: (lapor) async { ...; lapor(tersinkron, total); ...; return n; });
/// ```
Future<T?> jalankanDenganProgressSinkron<T>(
  BuildContext context, {
  required String judul,
  required Future<T> Function(void Function(int tersinkron, int? total) lapor)
      tugas,
  String satuan = 'data',
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _DialogProgressSinkron<T>(judul: judul, tugas: tugas, satuan: satuan),
  );
}

class _DialogProgressSinkron<T> extends StatefulWidget {
  final String judul;
  final String satuan;
  final Future<T> Function(void Function(int tersinkron, int? total) lapor)
      tugas;
  const _DialogProgressSinkron(
      {required this.judul, required this.tugas, required this.satuan});

  @override
  State<_DialogProgressSinkron<T>> createState() =>
      _DialogProgressSinkronState<T>();
}

class _DialogProgressSinkronState<T> extends State<_DialogProgressSinkron<T>> {
  int _tersinkron = 0;
  int? _total;
  bool _selesai = false;

  @override
  void initState() {
    super.initState();
    _jalankan();
  }

  Future<void> _jalankan() async {
    try {
      final hasil = await widget.tugas((tersinkron, total) {
        if (!mounted) return;
        setState(() {
          _tersinkron = tersinkron;
          if (total != null && total > 0) _total = total;
        });
      });
      if (!mounted) return;
      setState(() => _selesai = true);
      // Beri mata waktu melihat centang + bar penuh sebelum menutup.
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (mounted) Navigator.of(context).pop(hasil);
    } catch (e) {
      // Jangan menelan error -- pemanggil yang memutuskan cara menampilkan.
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sinkron terhenti: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final rasio = _selesai
        ? 1.0
        : (total == null || total == 0)
            ? null
            : (_tersinkron / total).clamp(0.0, 1.0);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(children: [
          if (_selesai)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (_, nilai, anak) =>
                  Transform.scale(scale: nilai, child: anak),
              child:
                  const Icon(Icons.check_circle, color: Colors.green, size: 24),
            )
          else
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(widget.judul, style: const TextStyle(fontSize: 15))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Animasi halus menuju nilai progres terbaru (bukan lompat).
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: rasio ?? 0),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (_, nilai, __) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: rasio == null ? null : nilai, minHeight: 10),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selesai
                  ? 'Selesai — $_tersinkron ${widget.satuan} tersinkron ke cache offline.'
                  : total == null
                      ? '$_tersinkron ${widget.satuan} terunduh...'
                      : '$_tersinkron / $total ${widget.satuan}'
                          ' (${((rasio ?? 0) * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
                'Data tersimpan ke database lokal — setelah ini daftar tetap '
                'bisa dipakai saat offline.',
                style:
                    TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}
