import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';
import 'inventory_sales/cetak_util.dart';
import 'struk_screen.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggalServer = DateFormat('yyyy-MM-dd');

String _formatWaktu(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

Future<void> _tampilkanRincianAngka(
  BuildContext context, {
  required String judul,
  required String nilai,
  String? keterangan,
  Map<String, String> rincian = const {},
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(judul),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                nilai,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (keterangan != null && keterangan.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(keterangan),
              ],
              if (rincian.isNotEmpty) ...[
                const Divider(height: 24),
                ...rincian.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(entry.key)),
                        const SizedBox(width: 16),
                        Flexible(
                          child: SelectableText(
                            entry.value,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

Widget _angkaLaporan(
  BuildContext context, {
  required String label,
  required String nilai,
  String? keterangan,
  Map<String, String> rincian = const {},
  TextStyle? style,
  TextAlign textAlign = TextAlign.left,
  int maxLines = 1,
}) {
  return Tooltip(
    message: 'Klik untuk melihat rincian',
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => _tampilkanRincianAngka(
          context,
          judul: label,
          nilai: nilai,
          keterangan: keterangan,
          rincian: rincian,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Text(
            nilai,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: (style ?? const TextStyle(fontSize: 12.5)).copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Layar Laporan Transaksi (padanan laporan-transaksi.html/-renderer.js
/// Electron) -- dasbor KPI (`transaksi_statistik`) di atas, lalu 6 sub-tab
/// server-side paginated: Report Order (`laporan_order_list`), Report Sesi
/// (`laporan_sesi_list`), Report Payment (`laporan_payment_list`). Ketiganya
/// TIDAK dicache offline (laporan historis, selalu online) -- beda dari
/// Produk/Anggota/Pesanan yang punya cache lokal.
class LaporanTransaksiScreen extends StatefulWidget {
  const LaporanTransaksiScreen({super.key});

  @override
  State<LaporanTransaksiScreen> createState() => _LaporanTransaksiScreenState();
}

class _LaporanTransaksiScreenState extends State<LaporanTransaksiScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, dynamic>? _statistik;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _muatStatistik();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _muatStatistik() async {
    try {
      final hasil = await ApiClient.instance.aksi('transaksi_statistik');
      if (mounted) setStateIfMounted(() => _statistik = hasil);
    } catch (_) {
      // dasbor KPI gagal muat bukan blocker utk 3 tab laporan di bawahnya.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.laporanTransaksi,
      judul: 'Laporan Transaksi',
      subjudul: 'Analitik order, sesi kas, dan metode pembayaran',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statistik != null)
            _KartuStatistikTransaksi(statistik: _statistik!),
          if (_statistik != null)
            _VisualisasiLaporanTransaksi(statistik: _statistik!),
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Report Order'),
              Tab(text: 'Report Sesi'),
              Tab(text: 'Transaksi Per Kasir'),
              Tab(text: 'Report Payment'),
              Tab(text: 'Penjualan per Kasir'),
              Tab(text: 'Penerimaan per Kasir'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              _TabOrder(),
              _TabSesi(),
              _TabTransaksiPerKasir(),
              _TabPayment(),
              _TabPenjualanKasir(),
              _TabPenerimaanKasir(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _KartuStatistikTransaksi extends StatelessWidget {
  final Map<String, dynamic> statistik;
  const _KartuStatistikTransaksi({required this.statistik});

  @override
  Widget build(BuildContext context) {
    final kartu = <(String, String, Color, String)>[
      (
        'Transaksi Hari Ini',
        '${statistik['trxHariIni'] ?? 0}',
        const Color(0xFF1E3A5F),
        'Jumlah transaksi yang tercatat sejak pukul 00.00 hari ini.'
      ),
      (
        'Omzet Hari Ini',
        _formatRupiah.format(statistik['omzetHariIni'] ?? 0),
        const Color(0xFF2E7D32),
        'Akumulasi nilai transaksi yang tercatat hari ini.'
      ),
      (
        'Transaksi 30 Hari',
        '${statistik['trx30Hari'] ?? 0}',
        const Color(0xFF0284C7),
        'Jumlah transaksi selama 30 hari terakhir.'
      ),
      (
        'Omzet 30 Hari',
        _formatRupiah.format(statistik['omzet30Hari'] ?? 0),
        const Color(0xFFC0563D),
        'Akumulasi nilai transaksi selama 30 hari terakhir.'
      ),
    ];
    final byKasir =
        ((statistik['byKasir'] as List?) ?? []).cast<Map<String, dynamic>>();
    final byMesin =
        ((statistik['byMesin'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kartu.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (label, nilai, warna, keterangan) = kartu[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _tampilkanRincianAngka(context,
                      judul: label,
                      nilai: nilai,
                      keterangan: keterangan,
                      rincian: {
                        'Periode': label.contains('30 Hari')
                            ? '30 hari terakhir'
                            : 'Hari ini',
                        'Sumber': 'Transaksi toko aktif',
                      }),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: warna.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(nilai,
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dotted,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: warna)),
                        Text(
                          label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (byKasir.isNotEmpty || byMesin.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (byKasir.isNotEmpty)
                    Expanded(
                        child: _panelPeringkat(
                            context, 'Omzet per Kasir (30 hari)', byKasir)),
                  if (byKasir.isNotEmpty && byMesin.isNotEmpty)
                    const SizedBox(width: 8),
                  if (byMesin.isNotEmpty)
                    Expanded(
                        child: _panelPeringkat(
                            context, 'Omzet per Mesin (30 hari)', byMesin)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelPeringkat(
      BuildContext context, String judul, List<Map<String, dynamic>> data) {
    final maksNilai = data
        .map((e) => (e['nilai'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(judul,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            ...data.take(5).map((e) {
              final nilai = (e['nilai'] as num).toDouble();
              final nilaiTampil = _formatRupiah.format(nilai);
              return InkWell(
                onTap: () => _tampilkanRincianAngka(context,
                    judul: '$judul · ${e['label']}',
                    nilai: nilaiTampil,
                    keterangan: 'Kontribusi dalam periode 30 hari terakhir.'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('${e['label']}',
                                style: const TextStyle(fontSize: 11))),
                        Text(nilaiTampil,
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700)),
                      ]),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maksNilai > 0 ? nilai / maksNilai : 0,
                          minHeight: 6,
                          backgroundColor: AppColors.borderOf(context),
                          color: const Color(0xFF1E3A5F),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _VisualisasiLaporanTransaksi extends StatelessWidget {
  final Map<String, dynamic> statistik;

  const _VisualisasiLaporanTransaksi({required this.statistik});

  List<Map<String, dynamic>> _daftar(String key) =>
      ((statistik[key] as List?) ?? []).cast<Map<String, dynamic>>();

  @override
  Widget build(BuildContext context) {
    final tren = _daftar('trenHarian');
    final metode = _daftar('byMetode');
    final radar = _daftar('radarKasir');
    if (tren.isEmpty && metode.isEmpty && radar.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 224,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        children: [
          if (tren.isNotEmpty)
            _kartuGrafik(
              context,
              judul: 'Tren Omzet & Transaksi',
              subjudul: '30 hari terakhir',
              lebar: 360,
              painter: _TrendLaporanPainter(tren, AppColors.primary),
              nilaiUtama: _formatRupiah.format(tren.fold<double>(
                  0, (v, e) => v + ((e['omzet'] as num?)?.toDouble() ?? 0))),
              rincian: {
                'Hari dengan transaksi': '${tren.length}',
                'Total transaksi':
                    '${tren.fold<int>(0, (v, e) => v + ((e['transaksi'] as num?)?.toInt() ?? 0))}',
              },
            ),
          if (metode.isNotEmpty) ...[
            const SizedBox(width: 8),
            _kartuGrafik(
              context,
              judul: 'Komposisi Pembayaran',
              subjudul: 'Nilai per metode',
              lebar: 300,
              painter: _DonutLaporanPainter(metode),
              nilaiUtama: _formatRupiah.format(metode.fold<double>(
                  0, (v, e) => v + ((e['nilai'] as num?)?.toDouble() ?? 0))),
              rincian: {
                for (final e in metode.take(8))
                  '${e['label'] ?? '-'} · ${e['transaksi'] ?? 0} trx':
                      _formatRupiah.format(e['nilai'] ?? 0),
              },
            ),
          ],
          if (radar.isNotEmpty) ...[
            const SizedBox(width: 8),
            _kartuGrafik(
              context,
              judul: 'Radar Performa Kasir',
              subjudul: 'Omzet, transaksi, rata-rata, hari aktif',
              lebar: 330,
              painter: _RadarLaporanPainter(radar),
              nilaiUtama: '${radar.length} kasir',
              rincian: {
                for (final e in radar.take(8))
                  '${e['label'] ?? '-'} · ${e['transaksi'] ?? 0} trx':
                      _formatRupiah.format(e['omzet'] ?? 0),
              },
            ),
          ],
          if (tren.isNotEmpty) ...[
            const SizedBox(width: 8),
            _kartuGrafik(
              context,
              judul: 'Candle Nilai Transaksi',
              subjudul: 'Open, high, low, close harian',
              lebar: 360,
              painter: _CandleLaporanPainter(tren),
              nilaiUtama: '${tren.length} hari',
              rincian: {
                'Nilai tertinggi': _formatRupiah.format(tren.fold<double>(
                    0,
                    (v, e) => v > ((e['high'] as num?)?.toDouble() ?? 0)
                        ? v
                        : ((e['high'] as num?)?.toDouble() ?? 0))),
                'Keterangan': 'Hijau: close ≥ open; merah: close < open',
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _kartuGrafik(
    BuildContext context, {
    required String judul,
    required String subjudul,
    required double lebar,
    required CustomPainter painter,
    required String nilaiUtama,
    required Map<String, String> rincian,
  }) {
    return SizedBox(
      width: lebar,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _tampilkanRincianAngka(context,
              judul: judul,
              nilai: nilaiUtama,
              keterangan: subjudul,
              rincian: rincian),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(judul,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                Text(subjudul,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 8),
                Expanded(
                  child: CustomPaint(
                    painter: painter,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendLaporanPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final Color warna;
  _TrendLaporanPainter(this.data, this.warna);

  @override
  void paint(Canvas canvas, Size size) {
    final nilai =
        data.map((e) => (e['omzet'] as num?)?.toDouble() ?? 0).toList();
    final maks = nilai.fold<double>(0, (a, b) => a > b ? a : b);
    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: .18)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (nilai.isEmpty || maks <= 0) return;
    final path = Path();
    for (var i = 0; i < nilai.length; i++) {
      final x = nilai.length == 1
          ? size.width / 2
          : size.width * i / (nilai.length - 1);
      final y = size.height - (nilai[i] / maks * (size.height - 8)) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.4, Paint()..color = warna);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = warna
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _TrendLaporanPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _DonutLaporanPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  _DonutLaporanPainter(this.data);
  static const warna = [
    Color(0xFF1E3A5F),
    Color(0xFF0284C7),
    Color(0xFF2E7D32),
    Color(0xFFC0563D),
    Color(0xFF7C3AED),
    Color(0xFFD97706)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<double>(
        0, (v, e) => v + ((e['nilai'] as num?)?.toDouble() ?? 0));
    if (total <= 0) return;
    final radius = size.shortestSide * .36;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2), radius: radius);
    var mulai = -1.5708;
    for (var i = 0; i < data.length; i++) {
      final sudut =
          (((data[i]['nilai'] as num?)?.toDouble() ?? 0) / total) * 6.28318;
      canvas.drawArc(
          rect,
          mulai,
          sudut,
          false,
          Paint()
            ..color = warna[i % warna.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * .42);
      mulai += sudut;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutLaporanPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _RadarLaporanPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  _RadarLaporanPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final axes = 4;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .38;
    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: .22)
      ..style = PaintingStyle.stroke;
    for (var level = 1; level <= 4; level++) {
      final p = Path();
      for (var i = 0; i < axes; i++) {
        final a = -1.5708 + (6.28318 * i / axes);
        final point = center +
            Offset(math.cos(a), math.sin(a)) * radius * level.toDouble() / 4;
        if (i == 0) {
          p.moveTo(point.dx, point.dy);
        } else {
          p.lineTo(point.dx, point.dy);
        }
      }
      p.close();
      canvas.drawPath(p, grid);
    }
    final maxTrx = data.fold<double>(
        1,
        (v, e) => v > ((e['transaksi'] as num?)?.toDouble() ?? 0)
            ? v
            : ((e['transaksi'] as num?)?.toDouble() ?? 0));
    final maxOmzet = data.fold<double>(
        1,
        (v, e) => v > ((e['omzet'] as num?)?.toDouble() ?? 0)
            ? v
            : ((e['omzet'] as num?)?.toDouble() ?? 0));
    final maxAvg = data.fold<double>(
        1,
        (v, e) => v > ((e['rataRata'] as num?)?.toDouble() ?? 0)
            ? v
            : ((e['rataRata'] as num?)?.toDouble() ?? 0));
    final e = data.first;
    final values = <double>[
      ((e['transaksi'] as num?)?.toDouble() ?? 0) / maxTrx,
      ((e['omzet'] as num?)?.toDouble() ?? 0) / maxOmzet,
      ((e['rataRata'] as num?)?.toDouble() ?? 0) / maxAvg,
      (((e['hariAktif'] as num?)?.toDouble() ?? 0) / 30)
          .clamp(0.0, 1.0)
          .toDouble()
    ];
    final p = Path();
    for (var i = 0; i < axes; i++) {
      final a = -1.5708 + (6.28318 * i / axes);
      final point =
          center + Offset(math.cos(a), math.sin(a)) * radius * values[i];
      if (i == 0) {
        p.moveTo(point.dx, point.dy);
      } else {
        p.lineTo(point.dx, point.dy);
      }
    }
    p.close();
    canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: .22)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _RadarLaporanPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _CandleLaporanPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  _CandleLaporanPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final visible = data.length > 16 ? data.sublist(data.length - 16) : data;
    final maks = visible.fold<double>(
        1,
        (v, e) => v > ((e['high'] as num?)?.toDouble() ?? 0)
            ? v
            : ((e['high'] as num?)?.toDouble() ?? 0));
    if (visible.isEmpty) return;
    final slot = size.width / visible.length;
    for (var i = 0; i < visible.length; i++) {
      final e = visible[i];
      final open = (e['open'] as num?)?.toDouble() ?? 0;
      final close = (e['close'] as num?)?.toDouble() ?? 0;
      final high = (e['high'] as num?)?.toDouble() ?? 0;
      final low = (e['low'] as num?)?.toDouble() ?? 0;
      final color =
          close >= open ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
      double y(double value) =>
          size.height - (value / maks * (size.height - 8)) - 4;
      final x = slot * i + slot / 2;
      canvas.drawLine(
          Offset(x, y(high)),
          Offset(x, y(low)),
          Paint()
            ..color = color
            ..strokeWidth = 1.3);
      final top = y(open > close ? open : close);
      final bottom = y(open > close ? close : open);
      canvas.drawRect(
          Rect.fromLTRB(x - slot * .24, top, x + slot * .24,
              bottom == top ? bottom + 2 : bottom),
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CandleLaporanPainter oldDelegate) =>
      oldDelegate.data != data;
}

/// Bar filter tanggal (+opsional kata kunci pembeli) dipakai oleh ke-3 tab.
class _FilterTanggal extends StatelessWidget {
  final DateTime? mulai;
  final DateTime? sampai;
  final bool pakaiCariPembeli;
  final ValueChanged<DateTime?> onMulaiBerubah;
  final ValueChanged<DateTime?> onSampaiBerubah;
  final ValueChanged<String>? onCariPembeli;
  final VoidCallback onTerapkan;

  const _FilterTanggal({
    required this.mulai,
    required this.sampai,
    required this.onMulaiBerubah,
    required this.onSampaiBerubah,
    required this.onTerapkan,
    this.pakaiCariPembeli = false,
    this.onCariPembeli,
  });

  Future<void> _pilihTanggal(BuildContext context, DateTime? awal,
      ValueChanged<DateTime?> onBerubah) async {
    final d = await showDatePicker(
      context: context,
      initialDate: awal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) onBerubah(d);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _pilihTanggal(context, mulai, onMulaiBerubah),
                  child: Text(mulai == null
                      ? 'Dari Tanggal'
                      : _formatTanggalServer.format(mulai!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _pilihTanggal(context, sampai, onSampaiBerubah),
                  child: Text(sampai == null
                      ? 'Sampai Tanggal'
                      : _formatTanggalServer.format(sampai!)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: onTerapkan, child: const Text('Terapkan')),
            ],
          ),
          if (pakaiCariPembeli)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppSearchField(
                hintText: 'Cari nama pembeli...',
                debounce: const Duration(milliseconds: 450),
                onChanged: onCariPembeli ?? (_) {},
              ),
            ),
        ],
      ),
    );
  }
}

Widget _kartuStatusMuat(
    {required bool memuat, String? error, required VoidCallback onCoba}) {
  if (memuat) {
    return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
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
          Text(error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ],
      ),
    ),
  );
}

class _TabOrder extends StatefulWidget {
  const _TabOrder();
  @override
  State<_TabOrder> createState() => _TabOrderState();
}

class _TabOrderState extends State<_TabOrder> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  DateTime? _mulai;
  DateTime? _sampai;
  String _cariPembeli = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_order_list', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        if (_cariPembeli.isNotEmpty) 'cariPembeli': _cariPembeli,
        'includePembayaran': true,
        'includeSplitPembayaran': true,
        'sertakanPembayaran': true,
        'withPayments': true,
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muat();
  }

  Future<void> _terapkan() async {
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Future<void> _lihatDetail(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items =
          ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      final pajakHeader = (row['pajak'] as num?)?.toDouble() ?? 0;
      final diskonHeader = (row['totalDiskon'] as num?)?.toDouble() ?? 0;
      final subtotalPerBaris = items
          .map((i) =>
              (i['harga'] as num).toDouble() * (i['qty'] as num).toDouble() -
              ((i['diskon'] as num?) ?? 0).toDouble())
          .toList();
      final totalSubtotal = subtotalPerBaris.fold<double>(0, (s, v) => s + v);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detail ${hasil['kode'] ?? ''}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chipRingkasan(
                        'Metode',
                        StrukScreen.labelPembayaran(hasil, row),
                        AppColors.primary),
                    _chipRingkasan('Diskon', _formatRupiah.format(diskonHeader),
                        Colors.orange),
                    _chipRingkasan('Pajak', _formatRupiah.format(pajakHeader),
                        Colors.blueGrey),
                    _chipRingkasan(
                        'Bayar',
                        _formatRupiah.format(hasil['totalBiaya'] ?? 0),
                        const Color(0xFF2E7D32)),
                  ]),
                  const Divider(),
                  ...List.generate(items.length, (idx) {
                    final i = items[idx];
                    final subtotal = subtotalPerBaris[idx];
                    final pajakBaris = totalSubtotal > 0
                        ? pajakHeader * (subtotal / totalSubtotal)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${i['nama']} x${(i['qty'] as num).toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            'Harga ${_formatRupiah.format(i['harga'])} - Diskon ${_formatRupiah.format(i['diskon'] ?? 0)} - Pajak ${_formatRupiah.format(pajakBaris)} - Subtotal ${_formatRupiah.format(subtotal)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'))
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _chipRingkasan(String label, String nilai, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $nilai',
          style: TextStyle(
              color: warna, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _tabelOrder() {
    return AppDataTable(
      minWidth: 980,
      emptyText: 'Belum ada order pada rentang ini.',
      columns: const [
        AppTableColumn('Nota', flex: 4),
        AppTableColumn('Waktu', flex: 2),
        AppTableColumn('Pembeli', flex: 2),
        AppTableColumn('Kasir / Mesin', flex: 2),
        AppTableColumn('Metode', flex: 2),
        AppTableColumn('Total', flex: 2, align: TextAlign.right),
        AppTableColumn('Aksi', width: 74, align: TextAlign.center),
      ],
      rows: _data.map((row) {
        final kasir = '${row['kasir'] ?? '-'}';
        final mesin = '${row['namaMesin'] ?? ''}'.trim();
        final kasirMesin = mesin.isEmpty ? kasir : '$kasir / $mesin';
        return AppTableRowData(
          onTap: () => _lihatDetail(row),
          cells: [
            AppTableCell.text(
              '${row['nomorNota'] ?? '-'}',
              flex: 4,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
            AppTableCell.text('${row['pembeli'] ?? 'Umum'}', flex: 2),
            AppTableCell.text(kasirMesin, flex: 2),
            AppTableCell(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: StrukScreen.labelPembayaran(row),
                  warna: AppColors.primary,
                ),
              ),
            ),
            AppTableCell(
              flex: 2,
              align: TextAlign.right,
              child: _angkaLaporan(context,
                  label: 'Total transaksi ${row['nomorNota'] ?? '-'}',
                  nilai: _formatRupiah.format(row['totalBiaya'] ?? 0),
                  keterangan:
                      'Klik baris atau ikon mata untuk melihat produk penyusun transaksi.',
                  rincian: {
                    'Waktu': _formatWaktu(row['waktu']),
                    'Kasir': kasirMesin,
                    'Metode': StrukScreen.labelPembayaran(row),
                  },
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
            AppTableCell(
              width: 74,
              align: TextAlign.center,
              child: Tooltip(
                message: 'Detail transaksi',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  onPressed: () => _lihatDetail(row),
                ),
              ),
            ),
          ],
        );
      }).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'transaksi',
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            pakaiCariPembeli: true,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d),
            onCariPembeli: (v) {
              _cariPembeli = v;
              _terapkan();
            },
            onTerapkan: _terapkan,
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _tabelOrder(),
            ),
        ],
      ),
    );
  }
}

class _TabSesi extends StatefulWidget {
  const _TabSesi();
  @override
  State<_TabSesi> createState() => _TabSesiState();
}

class _TabSesiState extends State<_TabSesi> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  DateTime? _mulai;
  DateTime? _sampai;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_sesi_list', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muat();
  }

  Future<void> _terapkan() async {
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _tabelSesi() {
    return AppDataTable(
      minWidth: 920,
      emptyText: 'Belum ada sesi pada rentang ini.',
      columns: const [
        AppTableColumn('Kode Sesi', flex: 3),
        AppTableColumn('Kasir', flex: 2),
        AppTableColumn('Waktu Buka', flex: 2),
        AppTableColumn('Waktu Tutup', flex: 2),
        AppTableColumn('Status', flex: 2),
        AppTableColumn('Saldo Akhir', flex: 2, align: TextAlign.right),
      ],
      rows: _data.map((row) {
        final tutup = row['status']?.toString().toUpperCase() == 'TUTUP';
        final proyeksi = row['saldoAkhirDikonfirmasi'] != true;
        final labelStatus = proyeksi ? 'Proyeksi' : (tutup ? 'Tutup' : 'Buka');
        final warnaStatus = tutup
            ? AppColors.textSecondaryOf(context)
            : const Color(0xFF2E7D32);
        return AppTableRowData(
          cells: [
            AppTableCell.text(
              '${row['sesiKode'] ?? '-'}',
              flex: 3,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            AppTableCell.text('${row['kasir'] ?? '-'}', flex: 2),
            AppTableCell.text(_formatWaktu(row['waktuBuka']), flex: 2),
            AppTableCell.text(_formatWaktu(row['waktuTutup']), flex: 2),
            AppTableCell(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(label: labelStatus, warna: warnaStatus),
              ),
            ),
            AppTableCell(
              flex: 2,
              align: TextAlign.right,
              child: _angkaLaporan(context,
                  label: 'Saldo akhir sesi ${row['sesiKode'] ?? '-'}',
                  nilai: _formatRupiah.format(row['saldoAkhir'] ?? 0),
                  keterangan: proyeksi
                      ? 'Nilai masih berupa proyeksi karena sesi belum dikonfirmasi tutup.'
                      : 'Nilai penutupan sesi yang sudah dikonfirmasi.',
                  rincian: {
                    'Kasir': '${row['kasir'] ?? '-'}',
                    'Status': labelStatus,
                    'Waktu buka': _formatWaktu(row['waktuBuka']),
                    'Waktu tutup': _formatWaktu(row['waktuTutup']),
                  },
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      }).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'sesi',
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d),
            onTerapkan: _terapkan,
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _tabelSesi(),
            ),
        ],
      ),
    );
  }
}

class _TabTransaksiPerKasir extends StatefulWidget {
  const _TabTransaksiPerKasir();

  @override
  State<_TabTransaksiPerKasir> createState() => _TabTransaksiPerKasirState();
}

class _TabTransaksiPerKasirState extends State<_TabTransaksiPerKasir> {
  late DateTime _mulai;
  late DateTime _sampai;
  bool _memuat = true;
  bool _mencetak = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  double _totalTransaksi = 0;
  double _totalSelisih = 0;
  int _jumlahTransaksi = 0;

  @override
  void initState() {
    super.initState();
    final sekarang = DateTime.now();
    _mulai = DateTime(sekarang.year, sekarang.month, sekarang.day);
    _sampai = _mulai;
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'laporan_transaksi_per_kasir',
        {
          'tglMulai': _formatTanggalServer.format(_mulai),
          'tglSampai': _formatTanggalServer.format(_sampai),
        },
      );
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _totalTransaksi = (hasil['totalTransaksi'] as num?)?.toDouble() ?? 0;
        _totalSelisih = (hasil['totalSelisih'] as num?)?.toDouble() ?? 0;
        _jumlahTransaksi = (hasil['jumlahTransaksi'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _mencetak = true);
    try {
      final rows = <List<String>>[];
      for (final kasir in _data) {
        final metode = ((kasir['metodePembayaran'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map((e) =>
                '${e['nama'] ?? '-'}: ${_formatRupiah.format(e['total'] ?? 0)}')
            .join('; ');
        rows.add([
          '${kasir['kasir'] ?? '-'}',
          '${kasir['jumlahTransaksi'] ?? 0}',
          _formatRupiah.format(kasir['modalAwal'] ?? 0),
          metode.isEmpty ? '-' : metode,
          _formatRupiah.format(kasir['kasSeharusnya'] ?? 0),
          _formatRupiah.format(kasir['kasClosing'] ?? 0),
          _formatRupiah.format(kasir['selisih'] ?? 0),
        ]);
      }
      await CetakUtilIs.cetakPdfTabel(
        judul: 'Laporan Transaksi Per Kasir',
        parameter:
            '${_formatTanggalServer.format(_mulai)} s.d. ${_formatTanggalServer.format(_sampai)}',
        headers: const [
          'Kasir',
          'Trx',
          'Modal',
          'Penerimaan per Metode',
          'Kas Seharusnya',
          'Kas Closing',
          'Selisih'
        ],
        rows: rows,
        namaFile:
            'transaksi-per-kasir-${_formatTanggalServer.format(_mulai)}-${_formatTanggalServer.format(_sampai)}.pdf',
        barisTotal:
            '$_jumlahTransaksi transaksi · ${_formatRupiah.format(_totalTransaksi)} · Total selisih ${_formatRupiah.format(_totalSelisih)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mencetak PDF: $e')));
      }
    } finally {
      setStateIfMounted(() => _mencetak = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d!),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d!),
            onTerapkan: _muat,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _angkaLaporan(context,
                          label: 'Jumlah transaksi per kasir',
                          nilai: '$_jumlahTransaksi transaksi',
                          keterangan:
                              'Jumlah seluruh transaksi pada periode yang dipilih.'),
                      _angkaLaporan(context,
                          label: 'Total transaksi per kasir',
                          nilai: _formatRupiah.format(_totalTransaksi),
                          keterangan:
                              'Akumulasi seluruh metode pembayaran pada periode yang dipilih.'),
                      _angkaLaporan(context,
                          label: 'Total selisih kasir',
                          nilai: _formatRupiah.format(_totalSelisih),
                          keterangan:
                              'Kas closing dikurangi modal awal dan penerimaan tunai.'),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _mencetak || _memuat ? null : _cetakPdf,
                  icon: _mencetak
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else if (_data.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child:
                  Center(child: Text('Belum ada transaksi pada periode ini.')),
            )
          else
            ..._data.map((kasir) {
              final metode = ((kasir['metodePembayaran'] as List?) ?? [])
                  .cast<Map<String, dynamic>>();
              final selisih = (kasir['selisih'] as num?)?.toDouble() ?? 0;
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text('${kasir['kasir'] ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Wrap(spacing: 8, children: [
                    _angkaLaporan(context,
                        label: 'Jumlah transaksi ${kasir['kasir'] ?? '-'}',
                        nilai: '${kasir['jumlahTransaksi'] ?? 0} transaksi'),
                    _angkaLaporan(context,
                        label: 'Total transaksi ${kasir['kasir'] ?? '-'}',
                        nilai:
                            _formatRupiah.format(kasir['totalTransaksi'] ?? 0)),
                  ]),
                  trailing: _angkaLaporan(context,
                      label: 'Selisih kas ${kasir['kasir'] ?? '-'}',
                      nilai: _formatRupiah.format(selisih),
                      keterangan: 'Kas closing dikurangi kas yang seharusnya.',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selisih == 0
                              ? const Color(0xFF2E7D32)
                              : Colors.red)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Column(
                        children: [
                          _barisNilai('Modal awal', kasir['modalAwal']),
                          ...metode.map((m) => _barisNilai(
                              '${m['nama'] ?? '-'} (${m['jumlahTransaksi'] ?? 0} trx)',
                              m['total'])),
                          const Divider(),
                          _barisNilai('Kas seharusnya', kasir['kasSeharusnya']),
                          _barisNilai('Kas closing', kasir['kasClosing']),
                          _barisNilai('Selisih', kasir['selisih'], tebal: true),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _barisNilai(String label, dynamic nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label)),
        _angkaLaporan(context,
            label: label,
            nilai: _formatRupiah.format(nilai ?? 0),
            keterangan: 'Komponen rekonsiliasi transaksi per kasir.',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: tebal ? FontWeight.bold : null)),
      ]),
    );
  }
}

class _TabPayment extends StatefulWidget {
  const _TabPayment();
  @override
  State<_TabPayment> createState() => _TabPaymentState();
}

class _TabPaymentState extends State<_TabPayment> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  DateTime? _mulai;
  DateTime? _sampai;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_payment_list', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muat();
  }

  Future<void> _terapkan() async {
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _tabelPayment() {
    return AppDataTable(
      minWidth: 860,
      emptyText: 'Belum ada pembayaran pada rentang ini.',
      columns: const [
        AppTableColumn('Order', flex: 3),
        AppTableColumn('Waktu', flex: 2),
        AppTableColumn('Sesi', flex: 2),
        AppTableColumn('Metode', flex: 2),
        AppTableColumn('Jumlah', flex: 2, align: TextAlign.right),
      ],
      rows: _data.map((row) {
        return AppTableRowData(
          cells: [
            AppTableCell.text(
              '${row['orderKode'] ?? '-'}',
              flex: 3,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
            AppTableCell.text('${row['sesiKode'] ?? '-'}', flex: 2),
            AppTableCell(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: StrukScreen.labelPembayaran(row),
                  warna: AppColors.primary,
                ),
              ),
            ),
            AppTableCell(
              flex: 2,
              align: TextAlign.right,
              child: _angkaLaporan(context,
                  label: 'Pembayaran ${row['orderKode'] ?? '-'}',
                  nilai: _formatRupiah.format(row['jumlah'] ?? 0),
                  rincian: {
                    'Metode': StrukScreen.labelPembayaran(row),
                    'Sesi': '${row['sesiKode'] ?? '-'}',
                    'Waktu': _formatWaktu(row['waktu']),
                  },
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      }).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'pembayaran',
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d),
            onTerapkan: _terapkan,
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _tabelPayment(),
            ),
        ],
      ),
    );
  }
}

class _TabPenjualanKasir extends StatefulWidget {
  const _TabPenjualanKasir();

  @override
  State<_TabPenjualanKasir> createState() => _TabPenjualanKasirState();
}

class _TabPenjualanKasirState extends State<_TabPenjualanKasir> {
  static const _pageSize = 15;
  late DateTime _mulai;
  late DateTime _sampai;
  bool _memuat = true;
  bool _mencetak = false;
  bool _bolehFilterKasir = false;
  String? _error;
  String _kasir = '';
  List<String> _daftarKasir = [];
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _ringkasan = [];
  int _halaman = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    final hariIni = DateTime.now();
    _mulai = DateTime(hariIni.year, hariIni.month, hariIni.day);
    _sampai = _mulai;
    _muat();
  }

  Map<String, dynamic> _payload({int? page, int pageSize = _pageSize}) => {
        'tglMulai': _formatTanggalServer.format(_mulai),
        'tglSampai': _formatTanggalServer.format(_sampai),
        if (_kasir.isNotEmpty) 'kasir': _kasir,
        'page': page ?? _halaman,
        'pageSize': pageSize,
      };

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance
          .aksi('laporan_penjualan_kasir_list', _payload());
      final daftar = ((hasil['daftarKasir'] as List?) ?? [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toSet()
          .toList();
      final aktif = '${hasil['kasirAktif'] ?? ''}'.trim();
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _ringkasan = ((hasil['ringkasanKasir'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
        _bolehFilterKasir = hasil['bolehFilterKasir'] == true;
        _daftarKasir = daftar;
        if (!_bolehFilterKasir || (_kasir.isEmpty && aktif.isNotEmpty)) {
          _kasir = aktif;
        }
        if (_kasir.isNotEmpty && !_daftarKasir.contains(_kasir)) {
          _daftarKasir = [_kasir, ..._daftarKasir];
        }
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _terapkan() async {
    if (_sampai.isBefore(_mulai)) {
      setStateIfMounted(() => _error =
          'Tanggal akhir tidak boleh lebih awal daripada tanggal mulai.');
      return;
    }
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  Future<void> _pindah(int halaman) async {
    setStateIfMounted(() => _halaman = halaman);
    await _muat();
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _mencetak = true);
    try {
      final semua = <Map<String, dynamic>>[];
      var page = 1;
      var total = 0;
      do {
        final hasil = await ApiClient.instance.aksi(
            'laporan_penjualan_kasir_list',
            _payload(page: page, pageSize: 100));
        semua.addAll(
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
        total = (hasil['total'] as num?)?.toInt() ?? semua.length;
        page++;
      } while (semua.length < total);
      final totalNilai = semua.fold<double>(
          0, (jumlah, row) => jumlah + ((row['totalBiaya'] as num?) ?? 0));
      await CetakUtilIs.cetakPdfTabel(
        judul: 'Penerimaan Penjualan per Kasir',
        parameter:
            'Periode ${_formatTanggalServer.format(_mulai)} s.d. ${_formatTanggalServer.format(_sampai)}; Kasir: ${_kasir.isEmpty ? "Semua kasir" : _kasir}',
        headers: const [
          'Waktu',
          'Kasir',
          'Nota',
          'Pembeli',
          'Metode',
          'Penerimaan'
        ],
        rows: semua
            .map((row) => [
                  _formatWaktu(row['waktu']),
                  '${row['kasir'] ?? '-'}',
                  '${row['nomorNota'] ?? '-'}',
                  '${row['pembeli'] ?? 'Umum'}',
                  StrukScreen.labelPembayaran(row),
                  _formatRupiah.format(row['totalBiaya'] ?? 0),
                ])
            .toList(),
        namaFile:
            'penjualan-per-kasir-${_formatTanggalServer.format(_mulai)}-${_formatTanggalServer.format(_sampai)}.pdf',
        barisTotal:
            'Jumlah transaksi: ${semua.length} · Total penerimaan: ${_formatRupiah.format(totalNilai)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mencetak PDF: $e')));
      }
    } finally {
      setStateIfMounted(() => _mencetak = false);
    }
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _filter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 170,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_formatTanggalServer.format(_mulai)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _mulai,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now());
                if (d != null) setStateIfMounted(() => _mulai = d);
              },
            ),
          ),
          const Text('s.d.'),
          SizedBox(
            width: 170,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined, size: 16),
              label: Text(_formatTanggalServer.format(_sampai)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _sampai,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now());
                if (d != null) setStateIfMounted(() => _sampai = d);
              },
            ),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              value: _kasir.isEmpty && !_bolehFilterKasir ? null : _kasir,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Kasir',
                  prefixIcon: Icon(Icons.person_outline),
                  isDense: true),
              items: [
                if (_bolehFilterKasir)
                  const DropdownMenuItem(value: '', child: Text('Semua kasir')),
                ..._daftarKasir
                    .map((k) => DropdownMenuItem(value: k, child: Text(k))),
              ],
              onChanged: _bolehFilterKasir
                  ? (v) => setStateIfMounted(() => _kasir = v ?? '')
                  : null,
            ),
          ),
          FilledButton.icon(
              onPressed: _memuat ? null : _terapkan,
              icon: const Icon(Icons.filter_alt_outlined, size: 17),
              label: const Text('Terapkan')),
          OutlinedButton.icon(
              onPressed: _memuat || _mencetak ? null : _cetakPdf,
              icon: _mencetak
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Cetak PDF')),
        ],
      ),
    );
  }

  Widget _ringkasanWidget() {
    if (_ringkasan.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 82,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: _ringkasan.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = _ringkasan[i];
          return Container(
            width: 210,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: .2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['kasir'] ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                _angkaLaporan(context,
                    label: 'Total penjualan ${r['kasir'] ?? '-'}',
                    nilai: _formatRupiah.format(r['total'] ?? 0),
                    keterangan:
                        'Total penerimaan kasir pada periode yang dipilih.',
                    style: TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w800)),
                _angkaLaporan(context,
                    label: 'Jumlah transaksi ${r['kasir'] ?? '-'}',
                    nilai: '${r['jumlahTransaksi'] ?? 0} transaksi',
                    keterangan:
                        'Jumlah nota yang dilayani kasir pada periode yang dipilih.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryOf(context))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabel() {
    return AppDataTable(
      minWidth: 1040,
      emptyText: 'Belum ada penjualan pada periode dan kasir ini.',
      columns: const [
        AppTableColumn('Waktu', flex: 2),
        AppTableColumn('Kasir', flex: 2),
        AppTableColumn('Nota', flex: 4),
        AppTableColumn('Pembeli', flex: 2),
        AppTableColumn('Metode', flex: 2),
        AppTableColumn('Penerimaan', flex: 2, align: TextAlign.right),
        AppTableColumn('Aksi', width: 70, align: TextAlign.center),
      ],
      rows: _data
          .map((row) => AppTableRowData(
                onTap: () => _lihatDetailPenjualanKasir(context, row),
                cells: [
                  AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
                  AppTableCell.text('${row['kasir'] ?? '-'}', flex: 2),
                  AppTableCell.text('${row['nomorNota'] ?? '-'}',
                      flex: 4,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  AppTableCell.text('${row['pembeli'] ?? 'Umum'}', flex: 2),
                  AppTableCell.text(StrukScreen.labelPembayaran(row), flex: 2),
                  AppTableCell(
                      flex: 2,
                      align: TextAlign.right,
                      child: _angkaLaporan(context,
                          label: 'Penerimaan ${row['nomorNota'] ?? '-'}',
                          nilai: _formatRupiah.format(row['totalBiaya'] ?? 0),
                          keterangan:
                              'Klik baris untuk membuka rincian produk transaksi.',
                          rincian: {
                            'Kasir': '${row['kasir'] ?? '-'}',
                            'Pembeli': '${row['pembeli'] ?? 'Umum'}',
                            'Metode': StrukScreen.labelPembayaran(row),
                          },
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  AppTableCell(
                    width: 70,
                    align: TextAlign.center,
                    child: IconButton(
                        tooltip: 'Lihat rincian penjualan',
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        onPressed: () =>
                            _lihatDetailPenjualanKasir(context, row)),
                  ),
                ],
              ))
          .toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'penjualan',
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _filter(),
          if (!_bolehFilterKasir && !_memuat)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Akun kasir hanya dapat melihat penjualan miliknya sendiri.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          _ringkasanWidget(),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _tabel()),
        ],
      ),
    );
  }
}

Future<void> _lihatDetailPenjualanKasir(
    BuildContext context, Map<String, dynamic> row) async {
  try {
    final hasil = await ApiClient.instance
        .aksi('laporan_penjualan_kasir_detail', {'id': row['idTransaksi']});
    final items = ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rincian ${hasil['kode'] ?? row['nomorNota'] ?? ''}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Kasir: ${row['kasir'] ?? '-'}'),
                Text('Waktu: ${_formatWaktu(row['waktu'])}'),
                Text('Pembeli: ${row['pembeli'] ?? 'Umum'}'),
                Text('Metode: ${StrukScreen.labelPembayaran(row)}'),
                const Divider(),
                ...items.map((item) {
                  final qty = (item['qty'] as num?)?.toDouble() ?? 0;
                  final harga = (item['harga'] as num?)?.toDouble() ?? 0;
                  final diskon = (item['diskon'] as num?)?.toDouble() ?? 0;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['nama'] ?? '-'}'),
                    subtitle: Text(
                        '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} × ${_formatRupiah.format(harga)}${diskon > 0 ? ' · Diskon ${_formatRupiah.format(diskon)}' : ''}'),
                    trailing:
                        Text(_formatRupiah.format((qty * harga) - diskon)),
                  );
                }),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total ${_formatRupiah.format(hasil['totalBiaya'] ?? row['totalBiaya'] ?? 0)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'))
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _TabPenerimaanKasir extends StatefulWidget {
  const _TabPenerimaanKasir();

  @override
  State<_TabPenerimaanKasir> createState() => _TabPenerimaanKasirState();
}

class _TabPenerimaanKasirState extends State<_TabPenerimaanKasir> {
  static const _pageSize = 15;
  late DateTime _mulai;
  late DateTime _sampai;
  bool _memuat = true;
  bool _mencetak = false;
  bool _bolehFilterKasir = false;
  String? _error;
  String _kasir = '';
  List<String> _daftarKasir = [];
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    final hariIni = DateTime.now();
    _mulai = DateTime(hariIni.year, hariIni.month, hariIni.day);
    _sampai = _mulai;
    _muat();
  }

  Map<String, dynamic> _payload({int? page, int pageSize = _pageSize}) => {
        'tglMulai': _formatTanggalServer.format(_mulai),
        'tglSampai': _formatTanggalServer.format(_sampai),
        if (_kasir.isNotEmpty) 'kasir': _kasir,
        'page': page ?? _halaman,
        'pageSize': pageSize,
      };

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance
          .aksi('laporan_penerimaan_kasir_list', _payload());
      final daftar = ((hasil['daftarKasir'] as List?) ?? [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final aktif = '${hasil['kasirAktif'] ?? ''}'.trim();
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
        _bolehFilterKasir = hasil['bolehFilterKasir'] == true;
        _daftarKasir = daftar;
        if (!_bolehFilterKasir || (_kasir.isEmpty && aktif.isNotEmpty)) {
          _kasir = aktif;
        }
        if (_kasir.isNotEmpty && !_daftarKasir.contains(_kasir)) {
          _daftarKasir = [_kasir, ..._daftarKasir];
        }
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _terapkan() async {
    if (_sampai.isBefore(_mulai)) {
      setStateIfMounted(() => _error =
          'Tanggal akhir tidak boleh lebih awal daripada tanggal mulai.');
      return;
    }
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  Future<void> _pindah(int halaman) async {
    setStateIfMounted(() => _halaman = halaman);
    await _muat();
  }

  Future<List<Map<String, dynamic>>> _semuaData() async {
    final semua = <Map<String, dynamic>>[];
    var page = 1;
    var total = 0;
    do {
      final hasil = await ApiClient.instance.aksi(
          'laporan_penerimaan_kasir_list', _payload(page: page, pageSize: 100));
      semua.addAll(
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
      total = (hasil['total'] as num?)?.toInt() ?? semua.length;
      page++;
    } while (semua.length < total);
    return semua;
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _mencetak = true);
    try {
      final semua = await _semuaData();
      final totalTrx = semua.fold<int>(
          0,
          (nilai, row) =>
              nilai + ((row['jumlahTransaksi'] as num?)?.toInt() ?? 0));
      final totalNilai = semua.fold<double>(
          0, (nilai, row) => nilai + ((row['total'] as num?)?.toDouble() ?? 0));
      await CetakUtilIs.cetakPdfTabel(
        judul: 'Penerimaan Penjualan per Kasir',
        parameter:
            'Periode ${_formatTanggalServer.format(_mulai)} s.d. ${_formatTanggalServer.format(_sampai)}; Kasir: ${_kasir.isEmpty ? "Semua kasir" : _kasir}',
        headers: const [
          'Tanggal',
          'Nama Kasir',
          'Metode / Bank',
          'Jumlah Transaksi',
          'Jumlah Penerimaan'
        ],
        rows: semua
            .map((row) => [
                  '${row['tanggal'] ?? '-'}',
                  '${row['kasir'] ?? '-'}',
                  '${row['metode'] ?? '-'}',
                  '${row['jumlahTransaksi'] ?? 0}',
                  _formatRupiah.format(row['total'] ?? 0),
                ])
            .toList(),
        namaFile:
            'penerimaan-per-kasir-${_formatTanggalServer.format(_mulai)}-${_formatTanggalServer.format(_sampai)}.pdf',
        barisTotal:
            'Total transaksi: $totalTrx · Total penerimaan: ${_formatRupiah.format(totalNilai)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mencetak PDF: $e')));
      }
    } finally {
      setStateIfMounted(() => _mencetak = false);
    }
  }

  Widget _filter() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_formatTanggalServer.format(_mulai)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _mulai,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (d != null) setStateIfMounted(() => _mulai = d);
                },
              ),
            ),
            const Text('s.d.'),
            SizedBox(
              width: 170,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(_formatTanggalServer.format(_sampai)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _sampai,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (d != null) setStateIfMounted(() => _sampai = d);
                },
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                value: _kasir.isEmpty && !_bolehFilterKasir ? null : _kasir,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Kasir',
                    prefixIcon: Icon(Icons.person_outline),
                    isDense: true),
                items: [
                  if (_bolehFilterKasir)
                    const DropdownMenuItem(
                        value: '', child: Text('Semua kasir')),
                  ..._daftarKasir
                      .map((k) => DropdownMenuItem(value: k, child: Text(k))),
                ],
                onChanged: _bolehFilterKasir
                    ? (v) => setStateIfMounted(() => _kasir = v ?? '')
                    : null,
              ),
            ),
            FilledButton.icon(
                onPressed: _memuat ? null : _terapkan,
                icon: const Icon(Icons.filter_alt_outlined, size: 17),
                label: const Text('Terapkan')),
            OutlinedButton.icon(
                onPressed: _memuat || _mencetak ? null : _cetakPdf,
                icon: _mencetak
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Cetak PDF')),
          ],
        ),
      );

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _tabel() => AppDataTable(
        minWidth: 940,
        emptyText: 'Belum ada penerimaan pada periode dan kasir ini.',
        columns: const [
          AppTableColumn('Tanggal', flex: 2),
          AppTableColumn('Kasir', flex: 3),
          AppTableColumn('Metode / Bank', flex: 3),
          AppTableColumn('Jumlah Transaksi', flex: 2, align: TextAlign.right),
          AppTableColumn('Penerimaan', flex: 3, align: TextAlign.right),
          AppTableColumn('Aksi', width: 70, align: TextAlign.center),
        ],
        rows: _data
            .map((row) => AppTableRowData(
                  onTap: () => _lihatRincianPenerimaan(context, row),
                  cells: [
                    AppTableCell.text('${row['tanggal'] ?? '-'}', flex: 2),
                    AppTableCell.text('${row['kasir'] ?? '-'}',
                        flex: 3,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    AppTableCell.text('${row['metode'] ?? '-'}', flex: 3),
                    AppTableCell(
                        flex: 2,
                        align: TextAlign.right,
                        child: _angkaLaporan(context,
                            label: 'Jumlah transaksi ${row['kasir'] ?? '-'}',
                            nilai: '${row['jumlahTransaksi'] ?? 0}',
                            keterangan:
                                'Jumlah transaksi penyusun penerimaan ini.',
                            textAlign: TextAlign.right)),
                    AppTableCell(
                        flex: 3,
                        align: TextAlign.right,
                        child: _angkaLaporan(context,
                            label: 'Penerimaan ${row['kasir'] ?? '-'}',
                            nilai: _formatRupiah.format(row['total'] ?? 0),
                            keterangan:
                                'Klik baris untuk melihat seluruh transaksi penyusun.',
                            rincian: {
                              'Tanggal': '${row['tanggal'] ?? '-'}',
                              'Metode / bank': '${row['metode'] ?? '-'}',
                            },
                            textAlign: TextAlign.right,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800))),
                    AppTableCell(
                      width: 70,
                      align: TextAlign.center,
                      child: IconButton(
                          tooltip: 'Lihat transaksi penyusun',
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          onPressed: () =>
                              _lihatRincianPenerimaan(context, row)),
                    ),
                  ],
                ))
            .toList(),
        pagination: _total > _pageSize
            ? AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _total,
                labelData: 'ringkasan penerimaan',
                onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                onBerikutnya: _halaman < _totalHalaman
                    ? () => _pindah(_halaman + 1)
                    : null,
              )
            : null,
      );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            _filter(),
            if (!_bolehFilterKasir && !_memuat)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                    'Akun kasir hanya dapat melihat penerimaan miliknya sendiri.',
                    style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            if (_memuat || _error != null)
              _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
            else
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _tabel()),
          ],
        ),
      );
}

Future<void> _lihatRincianPenerimaan(
    BuildContext context, Map<String, dynamic> ringkasan) async {
  try {
    final hasil =
        await ApiClient.instance.aksi('laporan_penerimaan_kasir_detail', {
      'tanggal': ringkasan['tanggal'],
      'kasir': ringkasan['kasir'],
      'metode': ringkasan['metode'],
    });
    final data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rincian penerimaan · ${ringkasan['tanggal'] ?? '-'}'),
        content: SizedBox(
          width: 650,
          height: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kasir: ${ringkasan['kasir'] ?? '-'}'),
              Text('Metode / bank: ${ringkasan['metode'] ?? '-'}'),
              Text(
                  '${ringkasan['jumlahTransaksi'] ?? data.length} transaksi · ${_formatRupiah.format(ringkasan['total'] ?? 0)}'),
              const Divider(),
              Expanded(
                child: data.isEmpty
                    ? const Center(child: Text('Tidak ada rincian transaksi.'))
                    : ListView.separated(
                        itemCount: data.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final row = data[i];
                          return ListTile(
                            dense: true,
                            title: Text('${row['nomorNota'] ?? '-'}'),
                            subtitle: Text(
                                '${_formatWaktu(row['waktu'])} · ${row['pembeli'] ?? 'Umum'}'),
                            trailing: Text(
                                _formatRupiah.format(row['totalBiaya'] ?? 0),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            onTap: () =>
                                _lihatDetailPenjualanKasir(dialogContext, row),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup')),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
