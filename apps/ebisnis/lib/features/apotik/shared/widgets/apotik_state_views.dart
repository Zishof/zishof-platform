import 'package:flutter/material.dart';

import '../../core/apotik_design_tokens.dart';

/// <h3>Pola seragam loading / kosong / galat / tanpa-izin (§2.2, §10).</h3>
///
/// Sebelumnya tiap layar apotik menulis sendiri `CircularProgressIndicator`
/// atau `Text('Belum ada data')` dengan gaya berbeda-beda. Empat widget di
/// bawah menyeragamkannya, dan yang terpenting: **selalu menjelaskan langkah
/// berikutnya**, tidak berhenti pada "gagal".

class ApotikLoadingState extends StatelessWidget {
  final String? pesan;
  const ApotikLoadingState({super.key, this.pesan});

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3)),
          if (pesan != null) ...[
            const SizedBox(height: 12),
            Text(pesan!,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class ApotikEmptyState extends StatelessWidget {
  final IconData ikon;
  final String judul;

  /// Wajib: jelaskan APA yang bisa dilakukan pengguna, bukan sekadar "kosong".
  final String petunjuk;
  final Widget? aksi;

  const ApotikEmptyState({
    super.key,
    required this.judul,
    required this.petunjuk,
    this.ikon = Icons.inbox_outlined,
    this.aksi,
  });

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 44, color: t.textSecondary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(judul,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
            const SizedBox(height: 6),
            Text(petunjuk,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.textSecondary)),
            if (aksi != null) ...[const SizedBox(height: 16), aksi!],
          ],
        ),
      ),
    );
  }
}

class ApotikErrorState extends StatelessWidget {
  /// Pesan APA ADANYA dari server bila ada — jangan ditelan/diganti UI
  /// (pagar existing: pesan penahan server ditampilkan apa adanya).
  final String pesan;
  final VoidCallback? onCobaLagi;
  final String? detailTeknis;

  const ApotikErrorState({
    super.key,
    required this.pesan,
    this.onCobaLagi,
    this.detailTeknis,
  });

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: t.danger),
            const SizedBox(height: 12),
            Text(pesan,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: t.textPrimary)),
            if (detailTeknis != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Detail teknis',
                    style: TextStyle(fontSize: 12, color: t.textSecondary)),
                children: [
                  SelectableText(detailTeknis!,
                      style: TextStyle(fontSize: 11, color: t.textSecondary)),
                ],
              ),
            ],
            if (onCobaLagi != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: onCobaLagi,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba lagi')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ditampilkan saat kunci permission mati. TIDAK menawarkan jalan pintas —
/// hanya menjelaskan siapa yang bisa membukakan aksesnya.
class ApotikPermissionDeniedState extends StatelessWidget {
  final String namaMenu;
  const ApotikPermissionDeniedState({super.key, required this.namaMenu});

  @override
  Widget build(BuildContext context) {
    return ApotikEmptyState(
      ikon: Icons.lock_outline,
      judul: 'Tidak memiliki akses $namaMenu',
      petunjuk: 'Akun Anda belum diberi hak untuk menu ini. Minta admin apotek '
          'mengaktifkannya lewat Pengguna & Hak Akses.',
    );
  }
}
