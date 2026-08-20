import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_client.dart';
import '../widgets/panel_galat.dart';

/// Pilih meja lewat QR.
///
/// Kamera hanya tersedia di Android/iOS; di Desktop (Windows) mobile_scanner
/// tidak punya implementasi, jadi layar ini menyediakan input kode manual --
/// keduanya berujung pada aksi `kantin_meja_cek` yang sama.
class PindaiMejaScreen extends StatefulWidget {
  const PindaiMejaScreen({super.key});

  @override
  State<PindaiMejaScreen> createState() => _PindaiMejaScreenState();
}

class _PindaiMejaScreenState extends State<PindaiMejaScreen> {
  final _kode = TextEditingController();
  bool _memproses = false;
  String? _galat;
  bool _sudahTertembak = false;

  static bool get _kameraDidukung {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void dispose() {
    _kode.dispose();
    super.dispose();
  }

  Future<void> _verifikasi(String kode) async {
    if (_memproses) return;
    final bersih = kode.trim();
    if (bersih.isEmpty) {
      setState(() => _galat = 'Kode meja masih kosong.');
      return;
    }
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      final res =
          await ApiClient.instance.aksi('kantin_meja_cek', {'kode': bersih});
      final data = res['data'];
      if (data is! Map) {
        throw ApiException('Balasan server tidak berisi data meja.');
      }
      if (!mounted) return;
      Navigator.of(context).pop({
        'id': '${data['id']}',
        'nama': '${data['nama'] ?? bersih}',
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = e.pesan;
        _sudahTertembak = false;
      });
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Meja')),
      body: Column(
        children: [
          if (_kameraDidukung)
            SizedBox(
              height: 280,
              child: MobileScanner(
                onDetect: (capture) {
                  if (_sudahTertembak || _memproses) return;
                  for (final barcode in capture.barcodes) {
                    final nilai = barcode.rawValue;
                    if (nilai != null && nilai.trim().isNotEmpty) {
                      _sudahTertembak = true;
                      _verifikasi(nilai);
                      break;
                    }
                  }
                },
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _kameraDidukung
                      ? 'Arahkan kamera ke QR meja, atau ketik kodenya di bawah.'
                      : 'Ketik kode meja yang tertera pada stiker QR di meja Anda.',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _kode,
                  decoration: const InputDecoration(labelText: 'Kode meja'),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _verifikasi,
                ),
                if (_galat != null) ...[
                  const SizedBox(height: 14),
                  PanelGalat(pesan: _galat!),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      _memproses ? null : () => _verifikasi(_kode.text),
                  child: _memproses
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Gunakan meja ini'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
