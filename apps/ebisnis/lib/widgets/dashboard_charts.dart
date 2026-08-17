import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';

final formatRupiahDasbor =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final formatAngkaDasbor = NumberFormat.decimalPattern('id_ID');

/// Satu titik data chart -- semua chart di dasbor Ringkasan dinormalisasi ke
/// bentuk ini sebelum dirender, supaya widget chart-nya sendiri generik dan
/// tidak perlu tahu nama field asli JSON server (yang berbeda-beda: label/nilai,
/// nama/total, dsb).
typedef TitikChart = ({String label, double nilai});

List<TitikChart> titikDariList(List? list,
    {String labelKey = 'label', String nilaiKey = 'nilai'}) {
  if (list == null) return [];
  return list.map((e) {
    final m = e as Map<String, dynamic>;
    return (
      label: '${m[labelKey] ?? ''}',
      nilai: (m[nilaiKey] as num?)?.toDouble() ?? 0
    );
  }).toList();
}

class KartuKpi extends StatelessWidget {
  final String label;
  final String nilai;
  final Color warna;
  const KartuKpi(
      {super.key,
      required this.label,
      required this.nilai,
      required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warna.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nilai,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: warna),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class BarisKpi extends StatelessWidget {
  final List<KartuKpi> kartu;
  const BarisKpi({super.key, required this.kartu});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, batas) {
      final kolom = batas.maxWidth >= 960
          ? 4
          : batas.maxWidth >= 520
              ? 2
              : 1;
      final lebar = (batas.maxWidth - ((kolom - 1) * 8)) / kolom;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: kartu
            .map((item) => SizedBox(
                  width: lebar,
                  height: 84,
                  child: item,
                ))
            .toList(),
      );
    });
  }
}

class PanelChart extends StatelessWidget {
  final String judul;
  final Widget child;
  const PanelChart({super.key, required this.judul, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(judul,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _kosong(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          'Belum ada data.',
          style: TextStyle(color: AppColors.textSecondaryOf(context)),
        ),
      ),
    );

/// Chart batang vertikal (padanan `buatBarVertikal` di ringkasan-renderer.js
/// Electron) -- dipakai utk tren waktu (harian/mingguan/dst).
class BarVertikal extends StatelessWidget {
  final List<TitikChart> data;
  final Color warna;
  final String Function(double)? formatNilai;
  const BarVertikal(
      {super.key,
      required this.data,
      this.warna = const Color(0xFF1E3A5F),
      this.formatNilai});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _kosong(context);
    final maks =
        data.map((e) => e.nilai.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((t) {
          final tinggi = maks > 0 ? (t.nilai.abs() / maks) * 100 : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                      formatNilai != null
                          ? formatNilai!(t.nilai)
                          : formatAngkaDasbor.format(t.nilai),
                      style: const TextStyle(fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Container(
                    height: tinggi.clamp(2, 100),
                    decoration: BoxDecoration(
                        color: t.nilai < 0 ? Colors.red : warna,
                        borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Chart batang vertikal 2-seri berdampingan (mis. Diskon vs Cashback per
/// periode) -- padanan `groupedBar` versi ZK (`DashboardUiKit.groupedBar`,
/// dipakai `MonitorDiskonKantinAction`). `labels`/`seri1`/`seri2` harus
/// SEJAJAR urutan &amp; panjangnya (satu titik per indeks).
class GroupedBarVertikal extends StatelessWidget {
  final List<String> labels;
  final List<double> seri1;
  final List<double> seri2;
  final String labelSeri1;
  final String labelSeri2;
  final Color warnaSeri1;
  final Color warnaSeri2;
  final String Function(double)? formatNilai;
  const GroupedBarVertikal({
    super.key,
    required this.labels,
    required this.seri1,
    required this.seri2,
    required this.labelSeri1,
    required this.labelSeri2,
    this.warnaSeri1 = const Color(0xFFC0563D),
    this.warnaSeri2 = const Color(0xFF2E7D32),
    this.formatNilai,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return _kosong(context);
    final maks = [...seri1, ...seri2].fold<double>(0, (a, b) => a > b ? a : b);
    final fmt = formatNilai ?? formatAngkaDasbor.format;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legenda(warnaSeri1, labelSeri1),
            const SizedBox(width: 14),
            _legenda(warnaSeri2, labelSeri2),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(labels.length, (i) {
              final t1 = maks > 0 ? (seri1[i] / maks) * 100 : 0.0;
              final t2 = maks > 0 ? (seri2[i] / maks) * 100 : 0.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 8,
                            height: t1.clamp(2, 100),
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                                color: warnaSeri1,
                                borderRadius: BorderRadius.circular(2)),
                          ),
                          Container(
                            width: 8,
                            height: t2.clamp(2, 100),
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                                color: warnaSeri2,
                                borderRadius: BorderRadius.circular(2)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Skala: ${fmt(maks)}',
          style: TextStyle(
              fontSize: 10, color: AppColors.textSecondaryOf(context)),
        ),
      ],
    );
  }

  Widget _legenda(Color warna, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, color: warna),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

/// Chart batang horizontal berperingkat (padanan `buatBarHorizontal`) --
/// dipakai utk daftar top-N (produk terlaris, kasir teratas, dsb).
class BarHorizontal extends StatelessWidget {
  final List<TitikChart> data;
  final Color warna;
  final String Function(double)? formatNilai;
  final bool tampilkanPeringkat;
  const BarHorizontal(
      {super.key,
      required this.data,
      this.warna = const Color(0xFF1E3A5F),
      this.formatNilai,
      this.tampilkanPeringkat = true});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _kosong(context);
    final maks =
        data.map((e) => e.nilai).fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      children: List.generate(data.length, (i) {
        final t = data[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              if (tampilkanPeringkat)
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
              Expanded(
                  flex: 2,
                  child: Text(t.label,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maks > 0 ? t.nilai / maks : 0,
                      minHeight: 8,
                      backgroundColor: AppColors.borderOf(context),
                      color: warna,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                    formatNilai != null
                        ? formatNilai!(t.nilai)
                        : formatAngkaDasbor.format(t.nilai),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Batang proporsional tunggal + legenda (padanan `buatStackProporsional`) --
/// dipakai utk komposisi metode bayar.
class StackProporsional extends StatelessWidget {
  final List<TitikChart> data;
  const StackProporsional({super.key, required this.data});

  static const _palet = [
    Color(0xFF1E3A5F),
    Color(0xFF0284C7),
    Color(0xFF2E7D32),
    Color(0xFFC0563D),
    Color(0xFFB8860B),
    Colors.purple,
    Colors.teal,
    Colors.brown,
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _kosong(context);
    final total = data.fold<double>(0, (s, e) => s + e.nilai);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 22,
            child: Row(
              children: data.asMap().entries.map((e) {
                final flexValue = total > 0
                    ? (e.value.nilai / total * 1000).round().clamp(1, 1000)
                    : 1;
                return Expanded(
                    flex: flexValue,
                    child: Container(color: _palet[e.key % _palet.length]));
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: data.asMap().entries.map((e) {
            final persen = total > 0 ? (e.value.nilai / total * 100) : 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: _palet[e.key % _palet.length],
                        shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${e.value.label} (${persen.toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 11)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Garis tren dengan area transparan. Cocok untuk perubahan omzet dari waktu
/// ke waktu; berbeda dari batang yang lebih tepat untuk perbandingan kategori.
class GarisTren extends StatelessWidget {
  final List<TitikChart> data;
  final Color warna;
  const GarisTren(
      {super.key, required this.data, this.warna = const Color(0xFF1E3A5F)});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _kosong(context);
    return SizedBox(
      height: 185,
      child: Column(children: [
        Expanded(
            child: CustomPaint(
                painter: _GarisTrenPainter(data, warna),
                child: const SizedBox.expand())),
        const SizedBox(height: 5),
        Row(
            children: data
                .map((e) => Expanded(
                      child: Text(e.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondaryOf(context))),
                    ))
                .toList()),
      ]),
    );
  }
}

class _GarisTrenPainter extends CustomPainter {
  final List<TitikChart> data;
  final Color warna;
  _GarisTrenPainter(this.data, this.warna);
  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.map((e) => e.nilai).fold<double>(0, math.max);
    final minV =
        data.map((e) => e.nilai).fold<double>(data.first.nilai, math.min);
    final rentang = math.max(1.0, maxV - minV);
    final titik = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = data.length == 1
          ? size.width / 2
          : i * size.width / (data.length - 1);
      final y = size.height -
          12 -
          ((data[i].nilai - minV) / rentang) * (size.height - 28);
      titik.add(Offset(x, y));
    }
    final grid = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      canvas.drawLine(Offset(0, size.height * i / 4),
          Offset(size.width, size.height * i / 4), grid);
    }
    final area = Path()..moveTo(titik.first.dx, size.height);
    for (final p in titik) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(titik.last.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = warna.withValues(alpha: .12));
    final garis = Path()..moveTo(titik.first.dx, titik.first.dy);
    for (var i = 1; i < titik.length; i++) {
      garis.lineTo(titik[i].dx, titik[i].dy);
    }
    canvas.drawPath(
        garis,
        Paint()
          ..color = warna
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    for (final p in titik) {
      canvas.drawCircle(p, 3.5, Paint()..color = warna);
    }
  }

  @override
  bool shouldRepaint(covariant _GarisTrenPainter old) =>
      old.data != data || old.warna != warna;
}

/// Radar/spider untuk membandingkan dimensi kinerja yang skalanya sudah
/// dinormalisasi ke 0..100.
class RadarKinerja extends StatelessWidget {
  final List<TitikChart> data;
  const RadarKinerja({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.length < 3) return _kosong(context);
    return SizedBox(
        height: 220,
        child: CustomPaint(
            painter: _RadarPainter(data, Theme.of(context).colorScheme.primary),
            child: const SizedBox.expand()));
  }
}

class _RadarPainter extends CustomPainter {
  final List<TitikChart> data;
  final Color warna;
  _RadarPainter(this.data, this.warna);
  Offset _p(Offset c, double r, int i) {
    final a = -math.pi / 2 + i * math.pi * 2 / data.length;
    return Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * .34;
    final grid = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke;
    for (var level = 1; level <= 4; level++) {
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final p = _p(c, r * level / 4, i);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    final area = Path();
    for (var i = 0; i < data.length; i++) {
      final axis = _p(c, r, i);
      canvas.drawLine(c, axis, grid);
      final p = _p(c, r * (data[i].nilai.clamp(0, 100) / 100), i);
      i == 0 ? area.moveTo(p.dx, p.dy) : area.lineTo(p.dx, p.dy);
      final tp = _p(c, r + 18, i);
      final t = TextPainter(
          text: TextSpan(
              text: data[i].label,
              style: const TextStyle(fontSize: 9, color: Color(0xFF475569))),
          textDirection: ui.TextDirection.ltr)
        ..layout(maxWidth: 80);
      t.paint(canvas, Offset(tp.dx - t.width / 2, tp.dy - t.height / 2));
    }
    area.close();
    canvas.drawPath(area, Paint()..color = warna.withValues(alpha: .18));
    canvas.drawPath(
        area,
        Paint()
          ..color = warna
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.data != data;
}

/// Heatmap hari/jam. Input label berupa "Sen 08" dan nilai berupa jumlah
/// transaksi; warna makin pekat ketika aktivitas makin tinggi.
class HeatmapAktivitas extends StatelessWidget {
  final List<TitikChart> data;
  const HeatmapAktivitas({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _kosong(context);
    final maks = data.map((e) => e.nilai).fold<double>(0, math.max);
    return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: data.map((e) {
          final p = maks <= 0 ? 0.0 : e.nilai / maks;
          return Tooltip(
              message:
                  '${e.label}: ${formatAngkaDasbor.format(e.nilai)} transaksi',
              child: Container(
                  width: 58,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Color.lerp(
                          const Color(0xFFE8F5E9), const Color(0xFF166534), p),
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(e.label,
                      style: TextStyle(
                          fontSize: 9,
                          color: p > .55
                              ? Colors.white
                              : const Color(0xFF334155)))));
        }).toList());
  }
}

typedef LilinChart = ({
  String label,
  double buka,
  double tinggi,
  double rendah,
  double tutup
});

/// Candlestick omzet per periode (open/close = transaksi pertama/terakhir,
/// high/low = transaksi terbesar/terkecil). Ini bukan grafik harga saham.
class CandlestickOmzet extends StatelessWidget {
  final List<LilinChart> data;
  const CandlestickOmzet({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _kosong(context);
    return SizedBox(
        height: 190,
        child: CustomPaint(
            painter: _CandlePainter(data), child: const SizedBox.expand()));
  }
}

class _CandlePainter extends CustomPainter {
  final List<LilinChart> data;
  _CandlePainter(this.data);
  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.map((e) => e.tinggi).fold<double>(0, math.max);
    final minV =
        data.map((e) => e.rendah).fold<double>(data.first.rendah, math.min);
    final range = math.max(1.0, maxV - minV);
    double y(double v) =>
        size.height - 25 - ((v - minV) / range) * (size.height - 40);
    final w = size.width / data.length;
    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      final x = w * (i + .5);
      final naik = e.tutup >= e.buka;
      final color = naik ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
      canvas.drawLine(
          Offset(x, y(e.tinggi)),
          Offset(x, y(e.rendah)),
          Paint()
            ..color = color
            ..strokeWidth = 2);
      final top = math.min(y(e.buka), y(e.tutup));
      final h = math.max(3.0, (y(e.buka) - y(e.tutup)).abs());
      canvas.drawRect(
          Rect.fromLTWH(
              x - math.min(10.0, w * .25), top, math.min(20.0, w * .5), h),
          Paint()..color = color);
      final t = TextPainter(
          text: TextSpan(
              text: e.label,
              style: const TextStyle(fontSize: 8, color: Color(0xFF64748B))),
          textDirection: ui.TextDirection.ltr)
        ..layout(maxWidth: w);
      t.paint(canvas, Offset(x - t.width / 2, size.height - 13));
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) => old.data != data;
}

/// Placeholder standar dipakai semua tab dasbor saat memuat/error.
Widget statusMuatDasbor(
    {required bool memuat, String? error, required VoidCallback onCoba}) {
  if (memuat) {
    return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()));
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 8),
          Text(error ?? 'Gagal memuat.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ],
      ),
    ),
  );
}
