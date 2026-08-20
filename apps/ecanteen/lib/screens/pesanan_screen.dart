import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';

/// Pesanan (draft) member: yang belum lunas dapat dibatalkan sendiri.
///
/// Server hanya mengizinkan pembatalan bila `lunas` masih kosong DAN draft
/// itu milik anggota yang bersangkutan (lihat `batalPesanan`), jadi tombolnya
/// disembunyikan untuk pesanan yang sudah dibayar.
class PesananScreen extends StatefulWidget {
  const PesananScreen({super.key});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];
  int _halaman = 1;
  int _total = 0;
  static const int _perHalaman = 10;

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
      final res = await ApiClient.instance.aksi('kantin_pesanan_list', {
        'page': _halaman,
        'limit': _perHalaman,
      });
      _daftar = ApiClient.instance.daftar(res);
      _total = (res['total'] as num?)?.toInt() ?? _daftar.length;
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _batalkan(Map<String, dynamic> pesanan) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan pesanan?'),
        content: Text(
            'Pesanan di ${pesanan['pedagang'] ?? 'toko ini'} akan dihapus dan '
            'tidak dapat dikembalikan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ya, batalkan')),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      await ApiClient.instance
          .aksi('kantin_pesanan_batal', {'id': '${pesanan['id']}'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesanan dibatalkan.')));
      _muat();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.pesan)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman =
        _total == 0 ? 1 : ((_total - 1) ~/ _perHalaman) + 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan Saya')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: PanelGalat(pesan: _galat!, onCobaLagi: _muat),
                )
              : _daftar.isEmpty
                  ? const Center(child: Text('Belum ada pesanan.'))
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _daftar.length + 1,
                        itemBuilder: (context, i) {
                          if (i == _daftar.length) {
                            if (totalHalaman <= 1) {
                              return const SizedBox(height: 20);
                            }
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: _halaman > 1
                                      ? () {
                                          _halaman--;
                                          _muat();
                                        }
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Text('Hal $_halaman / $totalHalaman'),
                                IconButton(
                                  onPressed: _halaman < totalHalaman
                                      ? () {
                                          _halaman++;
                                          _muat();
                                        }
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            );
                          }
                          return _kartu(_daftar[i]);
                        },
                      ),
                    ),
    );
  }

  Widget _kartu(Map<String, dynamic> p) {
    final lunas = p['lunas'] == true;
    final total = (p['total_biaya'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${p['pedagang'] ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(lunas ? 'Lunas' : 'Belum bayar',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: lunas
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${p['tanggal'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if ('${p['cara_bayar'] ?? ''}'.isNotEmpty)
              Text('Saluran: ${p['cara_bayar']}',
                  style: const TextStyle(fontSize: 12)),
            if ('${p['keterangan'] ?? ''}'.trim().isNotEmpty)
              Text('Catatan: ${p['keterangan']}',
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(rupiah(total),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (!lunas)
                  TextButton.icon(
                    onPressed: () => _batalkan(p),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Batalkan'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
