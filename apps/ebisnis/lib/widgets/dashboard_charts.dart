import 'package:flutter/material.dart';
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
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kartu.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 150, child: kartu[i]),
      ),
    );
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
