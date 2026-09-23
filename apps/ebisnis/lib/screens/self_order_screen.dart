import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/server_config.dart';
import '../sesi.dart';

class SelfOrderScreen extends StatelessWidget {
  const SelfOrderScreen({super.key});

  String get _url {
    final basis = Uri.parse(ServerConfig.instance.baseUrlTanpaEndpoint);
    return basis.resolve('Kantin').replace(queryParameters: {
      'toko': '${Sesi.instance.tokoId}',
    }).toString();
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return Scaffold(
      appBar: AppBar(title: const Text('Self Order / QR Menu')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  Text(Sesi.instance.tokoNama,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Pelanggan memindai kode ini untuk membuka katalog, memilih menu, dan mengirim pesanan sendiri.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: CustomPaint(
                      size: const Size.square(280),
                      painter: _QrPainter(url),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(url, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Tautan self order disalin.')));
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Salin Tautan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Uji Buka Katalog'),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  const Text(
                    'Pesanan pelanggan masuk ke menu Operasional > Pesanan. Kasir memeriksa item, catatan, dan pembayaran sebelum melayani.',
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    for (final element in bc.Barcode.qrCode()
        .make(data, width: size.width, height: size.height)) {
      if (element is bc.BarcodeBar && element.black) {
        canvas.drawRect(
            Rect.fromLTWH(
                element.left, element.top, element.width, element.height),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.data != data;
}
