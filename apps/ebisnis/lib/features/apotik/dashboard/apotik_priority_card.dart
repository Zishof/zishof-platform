import 'package:flutter/material.dart';

import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';

/// Kartu prioritas dashboard: satu angka besar + makna + tindakan.
///
/// Beda dengan kartu statistik lama: kartu ini WAJIB punya [tujuanLabel] dan
/// [onTap] — angka tanpa tindakan hanya membuat dashboard jadi papan pajangan
/// (temuan audit: "ruang kerja utama kosong").
///
/// [angka] null berarti sumber datanya belum tersedia/gagal dimuat; kartu
/// menampilkan "—" dan [catatan], BUKAN angka 0 yang menyesatkan.
class ApotikPriorityCard extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final int? angka;

  /// Label angka yang ditampilkan. Dipakai saat angkanya tidak pasti
  /// (mis. "100+" karena berasal dari daftar yang terpotong) — kartu tidak
  /// boleh menyajikan batas halaman sebagai fakta.
  final String? angkaLabel;
  final String satuan;

  /// Kalimat pendek yang menjelaskan MENGAPA angka ini penting.
  final String makna;
  final String? catatan;
  final String tujuanLabel;
  final VoidCallback? onTap;
  final ApotikPriorityNada nada;

  const ApotikPriorityCard({
    super.key,
    required this.ikon,
    required this.judul,
    required this.angka,
    this.angkaLabel,
    required this.makna,
    required this.tujuanLabel,
    this.satuan = '',
    this.catatan,
    this.onTap,
    this.nada = ApotikPriorityNada.netral,
  });

  Color _warna(ApotikDesignTokens t) {
    switch (nada) {
      case ApotikPriorityNada.mendesak:
        return t.danger;
      case ApotikPriorityNada.perhatian:
        return t.warning;
      case ApotikPriorityNada.klinis:
        return t.clinicalPurple;
      case ApotikPriorityNada.netral:
        return t.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    // Nada mendesak/perhatian hanya "menyala" bila angkanya memang > 0;
    // dashboard yang selalu merah membuat pengguna berhenti membacanya.
    final aktif = (angka ?? 0) > 0;
    final warna = aktif ? _warna(t) : t.textSecondary;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        child: Container(
          constraints: const BoxConstraints(
              minHeight: 132, minWidth: ApotikBreakpoints.targetSentuhMinimum),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
            border: Border.all(
                color: aktif ? warna.withValues(alpha: 0.35) : t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(ikon, size: 16, color: warna),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(judul,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary)),
                ),
              ]),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(angka == null ? '—' : (angkaLabel ?? '$angka'),
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: warna,
                          height: 1.05)),
                  if (satuan.isNotEmpty && angka != null) ...[
                    const SizedBox(width: 4),
                    Text(satuan,
                        style: TextStyle(fontSize: 12, color: t.textSecondary)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(angka == null ? (catatan ?? 'Data belum tersedia') : makna,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
              // SizedBox, BUKAN Spacer: kartu dipakai di dalam Wrap (tinggi
              // tak terbatas) sehingga flex-child akan melempar saat layout.
              const SizedBox(height: 10),
              if (onTap != null)
                Row(children: [
                  Text(tujuanLabel,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: warna)),
                  Icon(Icons.chevron_right, size: 15, color: warna),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

enum ApotikPriorityNada { netral, perhatian, mendesak, klinis }
