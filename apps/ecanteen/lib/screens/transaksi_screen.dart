import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';

/// Riwayat transaksi lunas + rincian itemnya, dan riwayat barang yang dibeli.
class TransaksiScreen extends StatefulWidget {
  const TransaksiScreen({super.key});

  @override
  State<TransaksiScreen> createState() => _TransaksiScreenState();
}

class _TransaksiScreenState extends State<TransaksiScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Riwayat'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Transaksi'),
            Tab(text: 'Barang Dibeli'),
          ]),
        ),
        body: const TabBarView(children: [
          _TabTransaksi(),
          _TabBarang(),
        ]),
      ),
    );
  }
}

class _TabTransaksi extends StatefulWidget {
  const _TabTransaksi();

  @override
  State<_TabTransaksi> createState() => _TabTransaksiState();
}

class _TabTransaksiState extends State<_TabTransaksi> {
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
      final res = await ApiClient.instance.aksi('kantin_transaksi_list', {
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

  Future<void> _bukaRincian(Map<String, dynamic> trx) async {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DialogRincian(idTransaksi: '${trx['id']}', header: trx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = _total == 0 ? 1 : ((_total - 1) ~/ _perHalaman) + 1;
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PanelGalat(pesan: _galat!, onCobaLagi: _muat),
      );
    }
    if (_daftar.isEmpty) {
      return const Center(child: Text('Belum ada transaksi.'));
    }
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _daftar.length + 1,
        itemBuilder: (context, i) {
          if (i == _daftar.length) {
            if (totalHalaman <= 1) return const SizedBox(height: 20);
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
          final t = _daftar[i];
          final total = (t['total_biaya'] as num?)?.toDouble() ?? 0;
          final cashback = (t['total_cashback'] as num?)?.toDouble() ?? 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text('${t['pedagang'] ?? '-'}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t['tanggal'] ?? ''}'),
                  if ('${t['cara_bayar'] ?? ''}'.isNotEmpty)
                    Text('${t['cara_bayar']}',
                        style: const TextStyle(fontSize: 12)),
                  if (cashback > 0)
                    Text('Cashback ${rupiah(cashback)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.orange)),
                ],
              ),
              trailing: Text(rupiah(total),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => _bukaRincian(t),
            ),
          );
        },
      ),
    );
  }
}

class _DialogRincian extends StatefulWidget {
  final String idTransaksi;
  final Map<String, dynamic> header;
  const _DialogRincian({required this.idTransaksi, required this.header});

  @override
  State<_DialogRincian> createState() => _DialogRincianState();
}

class _DialogRincianState extends State<_DialogRincian> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _item = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final res = await ApiClient.instance
          .aksi('kantin_transaksi_detail', {'id_transaksi': widget.idTransaksi});
      _item = ApiClient.instance.daftar(res);
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.header['pedagang'] ?? 'Rincian'}'),
      content: SizedBox(
        width: 420,
        child: _memuat
            ? const SizedBox(
                height: 90, child: Center(child: CircularProgressIndicator()))
            : _galat != null
                ? PanelGalat(pesan: _galat!)
                : _item.isEmpty
                    ? const Text('Tidak ada rincian item.')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.header['tanggal'] ?? ''}',
                              style: const TextStyle(fontSize: 12)),
                          const Divider(),
                          ..._item.map((it) {
                            final harga =
                                (it['harga'] as num?)?.toDouble() ?? 0;
                            final jumlah =
                                (it['jumlah'] as num?)?.toDouble() ?? 0;
                            final diskon =
                                (it['diskon'] as num?)?.toDouble() ?? 0;
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${it['nama'] ?? ''}'),
                                        Text(
                                            '${rupiah(harga)} x ${angka(jumlah)}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54)),
                                      ],
                                    ),
                                  ),
                                  Text(rupiah(harga * jumlah - diskon)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup')),
      ],
    );
  }
}

class _TabBarang extends StatefulWidget {
  const _TabBarang();

  @override
  State<_TabBarang> createState() => _TabBarangState();
}

class _TabBarangState extends State<_TabBarang> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];

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
      final res = await ApiClient.instance
          .aksi('kantin_barang_list', const {'page': 1, 'limit': 50});
      _daftar = ApiClient.instance.daftar(res);
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PanelGalat(pesan: _galat!, onCobaLagi: _muat),
      );
    }
    if (_daftar.isEmpty) {
      return const Center(child: Text('Belum ada barang yang dibeli.'));
    }
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _daftar.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final b = _daftar[i];
          final total = (b['total'] as num?)?.toDouble() ?? 0;
          final qty = (b['qty'] as num?)?.toDouble() ?? 0;
          return ListTile(
            dense: true,
            title: Text('${b['namabarang'] ?? ''}'),
            subtitle: Text(
                '${b['waktu'] ?? ''} - ${b['pedagang'] ?? ''} - ${angka(qty)} pcs'),
            trailing: Text(rupiah(total)),
          );
        },
      ),
    );
  }
}
