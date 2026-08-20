import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/server_config.dart';
import '../services/sesi.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';
import '../widgets/app_shell.dart';
import '../widgets/navigasi.dart';

/// Isi saldo (topup) + daftar Virtual Account / tagihan yang pernah dibuat.
///
/// Saluran yang ditawarkan diambil dgn `topup_only: "true"` sehingga hanya
/// metode NON-manual yang muncul -- persis seperti versi JSP, karena topup
/// tunai/transfer manual diproses petugas, bukan dari aplikasi.
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _saluran = [];
  List<Map<String, dynamic>> _va = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final saluranRes = await ApiClient.instance
          .aksi('kantin_cara_bayar', const {'topup_only': 'true'});
      _saluran = ApiClient.instance.daftar(saluranRes);

      final vaRes = await ApiClient.instance
          .aksi('kantin_va_list', const {'page': 1, 'limit': 20});
      _va = ApiClient.instance.daftar(vaRes);
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  /// Buka alur topup versi web lewat jembatan sesi (mobile_auth.jsp).
  ///
  /// Pembuatan tagihan memanggil payment gateway dan seluruh logikanya ada di
  /// _topup_service.jsp. Alur itu dipakai ulang apa adanya -- menyalin jalur
  /// uang ke aplikasi berisiko menyimpang tanpa ketahuan.
  Future<void> _bukaTopupWeb() async {
    final token = Sesi.instance.token;
    if (token == null || token.isEmpty) {
      setState(() => _galat = 'Sesi berakhir. Silakan masuk kembali.');
      return;
    }
    final url = ServerConfig.instance.urlJembatan(token, tujuan: 'topup');
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _galat = 'Tidak dapat membuka halaman pembayaran.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuAnggota.isiSaldo,
      judul: 'Isi ${Sesi.instance.labelSaldo}',
      subjudul: 'Saluran isi saldo mengikuti pengaturan jenis keanggotaan Anda.',
      onPilihMenu: navigasiMenu,
      child: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${Sesi.instance.labelSaldo} saat ini',
                              style: const TextStyle(fontSize: 12)),
                          Text(rupiah(Sesi.instance.saldo),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  if (_galat != null) ...[
                    const SizedBox(height: 14),
                    PanelGalat(pesan: _galat!, onCobaLagi: _muat),
                  ],
                  const SizedBox(height: 18),
                  const Text('Saluran isi saldo',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (_saluran.isEmpty)
                    const Text(
                      'Belum ada saluran isi saldo otomatis untuk jenis '
                      'keanggotaan Anda. Silakan isi saldo melalui petugas '
                      'kantin.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    )
                  else ...[
                    ..._saluran.map((s) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.account_balance_outlined),
                            title: Text('${s['nama'] ?? ''}'),
                          ),
                        )),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _bukaTopupWeb,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Buat Tagihan Pembayaran'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Pembuatan tagihan diproses di halaman pembayaran '
                        'resmi. Anda akan masuk otomatis, tidak perlu login '
                        'ulang.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text('Tagihan / Virtual Account',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (_va.isEmpty)
                    const Text('Belum ada tagihan.',
                        style: TextStyle(fontSize: 13, color: Colors.black54))
                  else
                    ..._va.map(_kartuVa),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _kartuVa(Map<String, dynamic> v) {
    final status = '${v['status_bayar'] ?? ''}'.toUpperCase();
    final warna = status == 'LUNAS'
        ? Colors.green
        : status == 'KEDALUWARSA'
            ? Colors.grey
            : Colors.orange;
    final total = (v['total'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${v['bank'] ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(status.isEmpty ? 'MENUNGGU' : status,
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: warna.withValues(alpha: 0.15),
                ),
              ],
            ),
            SelectableText('${v['kode'] ?? ''}',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 15, letterSpacing: 1)),
            if ('${v['keterangan'] ?? ''}'.trim().isNotEmpty)
              Text('${v['keterangan']}',
                  style: const TextStyle(fontSize: 12)),
            if ('${v['batas_waktu'] ?? ''}'.trim().isNotEmpty)
              Text('Batas waktu: ${v['batas_waktu']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(rupiah(total),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
