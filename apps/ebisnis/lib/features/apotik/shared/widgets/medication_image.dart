import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../services/url_media.dart';
import '../../core/apotik_design_tokens.dart';
import 'medication_local_path.dart';

/// Gambar obat stabil dan non-breaking untuk katalog Apotik.
///
/// Urutan sumber: bytes lokal, path lokal, `fotoUrls.first`, `gambarUrl`, lalu
/// fallback berdasarkan bentuk sediaan. Widget ini sengaja tidak memanggil API
/// agar daftar 100+ obat tidak menghasilkan request N+1.
class MedicationImage extends StatelessWidget {
  final Map<String, dynamic> item;
  final double width;
  final double height;

  const MedicationImage({
    super.key,
    required this.item,
    this.width = 72,
    this.height = 88,
  });

  String get _nama => '${item['nama'] ?? 'Obat'}'.trim();

  Uint8List? get _bytesLokal {
    final nilai = item['localBytes'] ?? item['gambarLokalBytes'];
    return nilai is Uint8List ? nilai : null;
  }

  String get _pathLokal =>
      '${item['localPath'] ?? item['gambarLokalPath'] ?? ''}'.trim();

  String get _url {
    final daftar = item['fotoUrls'];
    if (daftar is List) {
      for (final nilai in daftar) {
        final mentah = '$nilai'.trim();
        if (mentah.isEmpty) continue;
        final url = normalisasiUrlMedia(mentah);
        if (url.isNotEmpty) return url;
      }
    }
    final utama = '${item['gambarUrl'] ?? ''}'.trim();
    return utama.isEmpty ? '' : normalisasiUrlMedia(utama);
  }

  IconData get _ikon {
    if (item['racikan'] == true) return Icons.science_outlined;
    if (item['produksi'] == true) return Icons.factory_outlined;
    final teks = '${item['bentukSediaan'] ?? ''} $_nama'.toLowerCase();
    if (teks.contains('sirup') ||
        teks.contains('drops') ||
        teks.contains('tetes')) {
      return Icons.medication_liquid_outlined;
    }
    if (teks.contains('salep') ||
        teks.contains('krim') ||
        teks.contains('gel')) {
      return Icons.healing_outlined;
    }
    if (teks.contains('injek') ||
        teks.contains('vial') ||
        teks.contains('vaksin')) {
      return Icons.vaccines_outlined;
    }
    if (teks.contains('alat kesehatan') || teks.contains('alkes')) {
      return Icons.medical_services_outlined;
    }
    return Icons.medication_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    // Warna fallback bukan representasi risiko klinis. Warna semantik bahaya,
    // peringatan, dan cold-chain tetap khusus untuk badge status.
    final warna = t.primary;
    final fallback = _FallbackObat(ikon: _ikon, warna: warna, nama: _nama);
    final bytes = _bytesLokal;
    final path = _pathLokal;
    final url = _url;
    final punyaSumber = bytes != null || path.isNotEmpty || url.isNotEmpty;
    Widget gambar;

    Widget ketikaGagal(BuildContext _, Object __, StackTrace? ___) => fallback;

    if (bytes != null) {
      gambar = Image.memory(
        bytes,
        key: const ValueKey('medication-image-local-bytes'),
        fit: BoxFit.contain,
        cacheWidth: 200,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: ketikaGagal,
      );
    } else {
      gambar = buildMedicationLocalPathImage(
            path: path,
            fit: BoxFit.contain,
            errorBuilder: ketikaGagal,
          ) ??
          (url.isEmpty
              ? fallback
              : KeyedSubtree(
                  key: const ValueKey('medication-image-network'),
                  child: Image.network(
                    url,
                    key: const ValueKey('medication-thumbnail-image'),
                    fit: BoxFit.contain,
                    cacheWidth: 200,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: ketikaGagal,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : fallback,
                  ),
                ));
    }

    return Semantics(
      image: true,
      label:
          punyaSumber ? 'Foto kemasan $_nama' : 'Belum ada foto kemasan $_nama',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        child: Container(
          key: const ValueKey('medication-image'),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: warna.withValues(alpha: 0.08),
            border: Border.all(color: warna.withValues(alpha: 0.18)),
            borderRadius:
                BorderRadius.circular(ApotikDesignTokens.radiusControl),
          ),
          child: KeyedSubtree(
            key: const ValueKey('medication-thumbnail'),
            child: gambar,
          ),
        ),
      ),
    );
  }
}

class _FallbackObat extends StatelessWidget {
  final IconData ikon;
  final Color warna;
  final String nama;

  const _FallbackObat({
    required this.ikon,
    required this.warna,
    required this.nama,
  });

  @override
  Widget build(BuildContext context) {
    final inisial = nama.isEmpty ? 'O' : nama.substring(0, 1).toUpperCase();
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(ikon, size: 34, color: warna.withValues(alpha: 0.86)),
        Positioned(
          left: 5,
          bottom: 5,
          child: Container(
            width: 21,
            height: 21,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: warna,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              inisial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
