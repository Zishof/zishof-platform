import 'package:flutter/material.dart';

import '../../core/apotik_design_tokens.dart';

/// Tingkat makna status — memilih warna DAN ikon sekaligus.
enum ApotikStatusNada { netral, sukses, peringatan, bahaya, info, klinis }

/// <h3>Penanda status apotik — §7.4: status TIDAK boleh bergantung warna saja.</h3>
///
/// Setiap pill selalu memuat **ikon + teks + warna**, dan opsional
/// [penjelasan] yang menjadi tooltip sekaligus label semantik. Ini bukan
/// sekadar estetika: kasir dengan buta warna harus tetap dapat membedakan
/// "Layak" dari "Karantina".
class ApotikStatusPill extends StatelessWidget {
  final String teks;
  final ApotikStatusNada nada;

  /// Alasan/penjelasan singkat (mis. "tidak dapat dipilih"). Muncul sebagai
  /// tooltip pada desktop dan dibacakan pembaca layar.
  final String? penjelasan;

  /// Ikon khusus; bila null dipilih otomatis dari [nada].
  final IconData? ikon;

  final bool rapat;

  const ApotikStatusPill({
    super.key,
    required this.teks,
    this.nada = ApotikStatusNada.netral,
    this.penjelasan,
    this.ikon,
    this.rapat = false,
  });

  /// Batch layak dipakai (rekomendasi FEFO).
  factory ApotikStatusPill.layak({String? penjelasan}) => ApotikStatusPill(
      teks: 'Layak',
      nada: ApotikStatusNada.sukses,
      ikon: Icons.check_circle_outline,
      penjelasan:
          penjelasan ?? 'Direkomendasikan FEFO — verifikasi fisik wajib');

  /// Mendekati kedaluwarsa; [hari] ikut ditulis agar angka tidak tersembunyi.
  factory ApotikStatusPill.nearExpiry(int hari) => ApotikStatusPill(
      teks: 'Near-expiry — $hari hari',
      nada: ApotikStatusNada.peringatan,
      ikon: Icons.warning_amber_outlined,
      penjelasan: 'Prioritaskan keluar lebih dulu (FEFO)');

  factory ApotikStatusPill.kedaluwarsa() => const ApotikStatusPill(
      teks: 'Kedaluwarsa',
      nada: ApotikStatusNada.bahaya,
      ikon: Icons.block,
      penjelasan: 'Tidak dapat dipilih');

  factory ApotikStatusPill.stokHabis() => const ApotikStatusPill(
      teks: 'Stok habis',
      nada: ApotikStatusNada.netral,
      ikon: Icons.inventory_2_outlined,
      penjelasan: 'Batch tidak tersedia');

  /// LASA (Look-Alike Sound-Alike) — nama obat mirip, risiko salah ambil.
  factory ApotikStatusPill.lasa() => const ApotikStatusPill(
      teks: 'LASA',
      nada: ApotikStatusNada.peringatan,
      ikon: Icons.compare_arrows,
      penjelasan: 'Nama/rupa mirip obat lain — baca ulang sebelum ambil');

  /// Obat terkendali (narkotika/psikotropika) — butuh registrasi pembeli.
  factory ApotikStatusPill.terkendali() => const ApotikStatusPill(
      teks: 'Terkendali',
      nada: ApotikStatusNada.bahaya,
      ikon: Icons.lock_outline,
      penjelasan: 'Wajib nama pembeli + resep/dokter, tercatat di register');

  factory ApotikStatusPill.racikan() => const ApotikStatusPill(
      teks: 'Racikan',
      nada: ApotikStatusNada.klinis,
      ikon: Icons.science_outlined,
      penjelasan: 'Perlu dispensing racikan');

  Color _warna(ApotikDesignTokens t) {
    switch (nada) {
      case ApotikStatusNada.sukses:
        return t.success;
      case ApotikStatusNada.peringatan:
        return t.warning;
      case ApotikStatusNada.bahaya:
        return t.danger;
      case ApotikStatusNada.info:
        return t.info;
      case ApotikStatusNada.klinis:
        return t.clinicalPurple;
      case ApotikStatusNada.netral:
        return t.textSecondary;
    }
  }

  IconData _ikonBawaan() {
    switch (nada) {
      case ApotikStatusNada.sukses:
        return Icons.check_circle_outline;
      case ApotikStatusNada.peringatan:
        return Icons.warning_amber_outlined;
      case ApotikStatusNada.bahaya:
        return Icons.error_outline;
      case ApotikStatusNada.info:
        return Icons.info_outline;
      case ApotikStatusNada.klinis:
        return Icons.medical_information_outlined;
      case ApotikStatusNada.netral:
        return Icons.remove_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final warna = _warna(t);
    final isi = Container(
      padding: EdgeInsets.symmetric(
          horizontal: rapat ? 6 : 8, vertical: rapat ? 2 : 4),
      decoration: BoxDecoration(
        // Latar sangat tipis: kontras teks tetap dari warna penuh.
        color: warna.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: warna.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon ?? _ikonBawaan(), size: rapat ? 12 : 14, color: warna),
          const SizedBox(width: 4),
          Text(teks,
              style: TextStyle(
                  fontSize: rapat ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: warna)),
        ],
      ),
    );
    // Label semantik menggabungkan teks + penjelasan supaya pembaca layar
    // menyampaikan alasan, bukan hanya kata statusnya.
    final semantik = penjelasan == null ? teks : '$teks. $penjelasan';
    return Semantics(
      label: semantik,
      // excludeSemantics: pembaca layar membacakan SATU frasa utuh
      // ("Kedaluwarsa. Tidak dapat dipilih") alih-alih potongan ikon + teks
      // + tooltip yang membingungkan.
      excludeSemantics: true,
      child:
          penjelasan == null ? isi : Tooltip(message: penjelasan!, child: isi),
    );
  }
}
