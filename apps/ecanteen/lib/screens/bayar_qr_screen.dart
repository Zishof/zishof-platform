import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_client.dart';
import '../services/sesi.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';
import '../widgets/app_shell.dart';
import '../widgets/navigasi.dart';

/// Bayar dengan memindai QR tagihan dari kasir.
///
/// Mengikuti `onScanSuccessBayar()` versi JSP: isi QR adalah JSON berisi
/// `nominal`, `kodeToko`, dan `kodeUnik`; saldo disegarkan lebih dulu, lalu
/// dicek kecukupan saldo DAN batas saldo mengendap sebelum aksi `bayarOnline`
/// dipanggil. Server tetap melakukan pemeriksaan yang sama.
class BayarQrScreen extends StatefulWidget {
  const BayarQrScreen({super.key});

  @override
  State<BayarQrScreen> createState() => _BayarQrScreenState();
}

class _BayarQrScreenState extends State<BayarQrScreen> {
  final _kode = TextEditingController();
  bool _memproses = false;
  String? _galat;
  String? _sukses;
  bool _sedangTertembak = false;

  static bool get _kameraDidukung {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void dispose() {
    _kode.dispose();
    super.dispose();
  }

  Future<int> _segarkanSaldo() async {
    try {
      final res = await ApiClient.instance.aksi('kantin_saldo', const {});
      final saldo = res['data'];
      if (saldo is num) Sesi.instance.saldo = saldo.round();
    } on ApiException {
      // Biarkan memakai angka terakhir; server tetap punya kata akhir.
    }
    return Sesi.instance.saldo;
  }

  Future<void> _proses(String isiQr) async {
    if (_memproses) return;
    final teks = isiQr.trim();
    if (teks.isEmpty) {
      setState(() => _galat = 'Isi QR masih kosong.');
      return;
    }
    setState(() {
      _memproses = true;
      _galat = null;
      _sukses = null;
    });
    try {
      Map<String, dynamic> qr;
      try {
        final decoded = jsonDecode(teks);
        if (decoded is! Map) throw const FormatException('bukan objek');
        qr = decoded.map((k, v) => MapEntry('$k', v));
      } catch (_) {
        throw ApiException(
            'QR tidak dikenali sebagai instruksi pembayaran yang sah.');
      }
      if (qr['nominal'] == null ||
          qr['kodeToko'] == null ||
          qr['kodeUnik'] == null) {
        throw ApiException('Format QR tidak lengkap.');
      }

      final nominal =
          double.tryParse('${qr['nominal']}'.replaceAll(',', '.')) ?? 0;
      final saldo = await _segarkanSaldo();
      if (saldo < nominal) {
        throw ApiException(
            'Saldo Anda tidak mencukupi untuk pembayaran ini.');
      }
      if ((saldo - nominal) < Sesi.instance.minimalSaldo) {
        throw ApiException(
            'Sisa saldo setelah pembayaran kurang dari batas saldo mengendap '
            'yang diizinkan.');
      }

      // idMember TIDAK dikirim: server menentukan sendiri anggota dari token.
      await ApiClient.instance.aksi('bayarOnline', {'kode': teks});
      await _segarkanSaldo();
      if (!mounted) return;
      setState(() {
        _sukses = 'Pembayaran ${rupiah(nominal)} berhasil diproses.';
        _sedangTertembak = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = e.pesan;
        _sedangTertembak = false;
      });
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuAnggota.bayarQr,
      judul: 'Bayar dengan QR',
      subjudul: 'Pindai QR tagihan dari kasir untuk membayar dari saldo Anda.',
      onPilihMenu: navigasiMenu,
      child: Column(
        children: [
          if (_kameraDidukung && _sukses == null)
            SizedBox(
              height: 280,
              child: MobileScanner(
                onDetect: (capture) {
                  if (_sedangTertembak || _memproses) return;
                  for (final b in capture.barcodes) {
                    final nilai = b.rawValue;
                    if (nilai != null && nilai.trim().isNotEmpty) {
                      _sedangTertembak = true;
                      _proses(nilai);
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
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${Sesi.instance.labelSaldo} Anda',
                            style: const TextStyle(fontSize: 12)),
                        Text(rupiah(Sesi.instance.saldo),
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_sukses != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.10),
                      border:
                          Border.all(color: Colors.green.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_sukses!)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () =>
                        navigasiMenu(context, MenuAnggota.belanja),
                    child: const Text('Selesai'),
                  ),
                ] else ...[
                  Text(
                    _kameraDidukung
                        ? 'Arahkan kamera ke QR tagihan dari kasir, atau tempel isinya di bawah.'
                        : 'Tempel isi QR tagihan dari kasir di bawah ini.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _kode,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Isi QR'),
                  ),
                  if (_galat != null) ...[
                    const SizedBox(height: 14),
                    PanelGalat(pesan: _galat!),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _memproses ? null : () => _proses(_kode.text),
                    icon: _memproses
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.payments_outlined),
                    label: Text(_memproses ? 'Memproses...' : 'Bayar sekarang'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
