import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Layar full-screen pemindai barcode/QR kamera (MLKit lewat `mobile_scanner`)
/// -- padanan kamera scan Stok Opname "SO by Scan" versi Electron (yang
/// memakai `Html5Qrcode` berbasis web); di sini native kamera Android/iOS.
///
/// Dipakai dgn `Navigator.push` + `await`, mengembalikan (`pop`) String kode
/// hasil scan pertama yang valid, atau `null` bila dibatalkan. Debounce 1
/// deteksi lalu langsung `pop` (BUKAN stream berkelanjutan) -- cukup utk
/// alur "scan satu produk, proses, scan lagi" yang dipakai Stok Opname/Kulakan;
/// pemanggil yang butuh scan berturutan cukup panggil ulang di loop-nya sendiri.
class BarcodeScannerScreen extends StatefulWidget {
  final String judul;
  const BarcodeScannerScreen({super.key, this.judul = 'Scan Barcode'});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();

  /// Buka layar scan, kembalikan kode hasil scan (atau null bila dibatalkan).
  static Future<String?> pindai(BuildContext context, {String judul = 'Scan Barcode'}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BarcodeScannerScreen(judul: judul)),
    );
  }
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _sudahDapat = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_sudahDapat) return;
    for (final b in capture.barcodes) {
      final nilai = b.rawValue;
      if (nilai != null && nilai.isNotEmpty) {
        _sudahDapat = true;
        Navigator.of(context).pop(nilai);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.judul),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) => Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off),
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
