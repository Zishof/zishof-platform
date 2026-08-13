import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

class ProdukRekonsiliasiLedgerTab extends StatefulWidget {
  const ProdukRekonsiliasiLedgerTab({super.key});

  @override
  State<ProdukRekonsiliasiLedgerTab> createState() =>
      _ProdukRekonsiliasiLedgerTabState();
}

class _ProdukRekonsiliasiLedgerTabState
    extends State<ProdukRekonsiliasiLedgerTab> {
  static const _pageSize = 15;
  final _cari = TextEditingController();
  bool _memuat = true;
  bool _hanyaSelisih = true;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _jumlahProduk = 0;
  int _tercakup = 0;
  int _belumTercakup = 0;
  double _totalSelisih = 0;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('produk_rekonsiliasi_ledger', {
        'page': _page,
        'page_size': _pageSize,
        'keyword': _cari.text.trim(),
        'hanya_selisih': _hanyaSelisih,
      });
      setStateIfMounted(() {
        _data =
            ((hasil['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
        _jumlahProduk = (hasil['jumlahProduk'] as num?)?.toInt() ?? 0;
        _tercakup = (hasil['produkTercakupLedger'] as num?)?.toInt() ?? 0;
        _belumTercakup = (hasil['produkBelumTercakup'] as num?)?.toInt() ?? 0;
        _totalSelisih = (hasil['totalSelisihAbsolut'] as num?)?.toDouble() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  String _angka(dynamic value) {
    final number = (value as num?)?.toDouble() ?? 0;
    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final pages = (_total / _pageSize).ceil().clamp(1, 999999);
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppInfoBanner(
            icon: Icons.fact_check_outlined,
            color: AppColors.info,
            text:
                'Mode audit: tabel ini membandingkan stok operasional dengan buku besar mutasi tanpa mengubah data. Produk lama akan memperoleh saldo awal saat mutasi ledger pertamanya.',
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _Stat('Total Produk', _jumlahProduk),
            _Stat('Tercakup Ledger', _tercakup),
            _Stat('Belum Tercakup', _belumTercakup),
            _Stat('Total Selisih Absolut', _totalSelisih),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cari,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari nama, kode, atau barcode'),
                onSubmitted: (_) {
                  _page = 1;
                  _muat();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _hanyaSelisih,
              label: const Text('Hanya yang selisih'),
              onSelected: (value) {
                setStateIfMounted(() {
                  _hanyaSelisih = value;
                  _page = 1;
                });
                _muat();
              },
            ),
            IconButton(
                onPressed: _memuat ? null : _muat,
                icon: const Icon(Icons.refresh)),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _error!),
          ],
          if (_memuat)
            const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()))
          else if (_data.isEmpty)
            Padding(
              padding: const EdgeInsets.all(36),
              child: Center(
                  child: Text(_hanyaSelisih
                      ? 'Tidak ada selisih pada produk yang sudah tercakup ledger.'
                      : 'Belum ada produk yang tercakup ledger.')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Produk')),
                  DataColumn(label: Text('Kode / Barcode')),
                  DataColumn(label: Text('Stok Sistem'), numeric: true),
                  DataColumn(label: Text('Stok Ledger'), numeric: true),
                  DataColumn(label: Text('Selisih'), numeric: true),
                  DataColumn(label: Text('Mutasi Terakhir')),
                ],
                rows: _data.map((row) {
                  final selisih = (row['selisih'] as num?)?.toDouble() ?? 0;
                  return DataRow(cells: [
                    DataCell(Text('${row['nama']}')),
                    DataCell(Text('${row['kode']} / ${row['barcode']}')),
                    DataCell(Text(_angka(row['stokTersimpan']))),
                    DataCell(Text(_angka(row['stokLedger']))),
                    DataCell(Text(_angka(selisih),
                        style: TextStyle(
                            color: selisih == 0
                                ? AppColors.success
                                : AppColors.danger,
                            fontWeight: FontWeight.w700))),
                    DataCell(Text('${row['mutasiTerakhir'] ?? '-'}')),
                  ]);
                }).toList(),
              ),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('Halaman $_page dari $pages'),
            IconButton(
                onPressed: _page > 1
                    ? () {
                        _page--;
                        _muat();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left)),
            IconButton(
                onPressed: _page < pages
                    ? () {
                        _page++;
                        _muat();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final num value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text('$value',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}
