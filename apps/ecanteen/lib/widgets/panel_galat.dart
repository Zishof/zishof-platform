import 'package:flutter/material.dart';

/// Panel galat yang menampilkan pesan apa adanya dari server -- termasuk
/// alamat endpoint saat gangguan jaringan, supaya pengguna/IT bisa menelusuri
/// tanpa membuka log.
class PanelGalat extends StatelessWidget {
  final String pesan;
  final VoidCallback? onCobaLagi;
  const PanelGalat({super.key, required this.pesan, this.onCobaLagi});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(pesan,
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
          if (onCobaLagi != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCobaLagi,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Coba lagi'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
