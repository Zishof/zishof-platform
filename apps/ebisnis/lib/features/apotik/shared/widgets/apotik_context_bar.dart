import 'package:flutter/material.dart';

import '../../core/apotik_breakpoints.dart';
import '../../core/apotik_design_tokens.dart';

/// Satu ruas konteks (label + nilai + ikon), mis. "Outlet · Apotek Pusat".
class ApotikKonteksRuas {
  final IconData ikon;
  final String label;
  final String nilai;

  /// Nada opsional untuk ruas berstatus (sync/printer/scanner).
  final Color? warna;

  /// Penjelasan bila nilainya bermasalah (mis. "printer belum dipilih").
  final String? penjelasan;

  const ApotikKonteksRuas({
    required this.ikon,
    required this.label,
    required this.nilai,
    this.warna,
    this.penjelasan,
  });
}

/// <h3>Bar konteks kerja apotik (§6.1, §10 — "Context is always visible").</h3>
///
/// Menjawab pertanyaan pertama pengguna setiap saat: *saya sedang bekerja untuk
/// tenant, outlet, terminal, dan shift yang mana?* Ini sekaligus memperbaiki
/// temuan audit "identitas Kantin Demo membingungkan pada modul apotik":
/// nilai tenant SELALU diambil dari sesi aktif, tidak pernah dari teks contoh.
///
/// Ruas yang nilainya kosong sengaja TIDAK dirender (lebih baik hilang daripada
/// menampilkan "-" yang menyesatkan, mis. shift yang memang belum dibuka).
class ApotikContextBar extends StatelessWidget {
  final List<ApotikKonteksRuas> ruas;

  /// Aksi kanan (mis. tombol bantuan tunggal, Ctrl+K). Dokumen melarang
  /// duplikasi tombol bantuan, jadi pemanggil hanya mengirim SATU.
  final List<Widget> aksi;

  const ApotikContextBar({super.key, required this.ruas, this.aksi = const []});

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final tampil = ruas.where((r) => r.nilai.trim().isNotEmpty).toList();
    return ApotikResponsive(
      builder: (context, layout) {
        final padding = EdgeInsets.symmetric(
            horizontal: ApotikBreakpoints.paddingHalaman(layout), vertical: 8);
        return Container(
          padding: padding,
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Expanded(
                // Mobile: gulir mendatar supaya konteks tetap lengkap tanpa
                // memakan tinggi layar yang mahal.
                child: layout.isMobile
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: _ruasWidget(t, tampil)),
                      )
                    : Wrap(
                        spacing: 0,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: _ruasWidget(t, tampil),
                      ),
              ),
              ...aksi,
            ],
          ),
        );
      },
    );
  }

  List<Widget> _ruasWidget(ApotikDesignTokens t, List<ApotikKonteksRuas> data) {
    final widgets = <Widget>[];
    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final warna = r.warna ?? t.textSecondary;
      final isi = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(r.ikon, size: 14, color: warna),
          const SizedBox(width: 4),
          Text('${r.label} ',
              style: TextStyle(fontSize: 11, color: t.textSecondary)),
          Text(r.nilai,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: warna)),
        ],
      );
      widgets.add(Semantics(
        label: '${r.label} ${r.nilai}'
            '${r.penjelasan == null ? '' : '. ${r.penjelasan}'}',
        child: r.penjelasan == null
            ? isi
            : Tooltip(message: r.penjelasan!, child: isi),
      ));
      if (i != data.length - 1) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('·', style: TextStyle(color: t.border, fontSize: 14)),
        ));
      }
    }
    return widgets;
  }
}
