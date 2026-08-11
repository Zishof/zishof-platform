import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/safe_state.dart';

final _fmtRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtQty = NumberFormat('#,##0.##', 'id_ID');
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Persediaan & Kartu Stok -- layar legacy 08 (Data Stok Barang).</h3>
///
/// Saldo = hasil LEDGER (`si_inventory_balance`): AWAL + MASUK + OPNAME - KELUAR
/// = AKHIR per rentang tanggal acuan; nilai = akhir x harga beli; penanda stok
/// minimum/negatif/tersedia. Tap baris = KARTU STOK (`si_inventory_ledger`):
/// seluruh mutasi ber-tanggal 8 suku ledger + saldo berjalan. Koreksi stok
/// TIDAK dilakukan di sini -- lewat Stok Opname/adjustment beralasan (paritas
/// aturan legacy "saldo bukan angka yang diedit bebas").
class PersediaanScreen extends StatefulWidget {
  const PersediaanScreen({super.key});

  @override
  State<PersediaanScreen> createState() => _PersediaanScreenState();
}

class _PersediaanScreenState extends State<PersediaanScreen> {
  static const _pageSize = 20;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  String _filter = 'semua'; // semua | minimum | negatif | tersedia
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('si_inventory_balance', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
        'hanya_minimum': _filter == 'minimum',
        'hanya_negatif': _filter == 'negatif',
        'hanya_tersedia': _filter == 'tersedia',
        'page': _halaman,
        'page_size': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Future<void> _pilihTanggal({required bool dari}) async {
    final awal = dari ? _dari : _sampai;
    final hasil = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (hasil == null) return;
    setStateIfMounted(() {
      if (dari) {
        _dari = hasil;
      } else {
        _sampai = hasil;
      }
    });
    _halaman = 1;
    await _muat();
  }

  Future<void> _bukaKartuStok(Map<String, dynamic> p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _KartuStokSheet(
          produkId: (p['produkId'] as num).toInt(),
          kode: '${p['kode']}',
          nama: '${p['nama']}',
          dari: _dari,
          sampai: _sampai),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.persediaan,
      judul: 'Persediaan & Kartu Stok',
      subjudul:
          'Saldo stok hasil ledger: Awal + Masuk + Opname - Keluar = Akhir (layar legacy 08)',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message:
              'Cetak/preview/Excel Laporan Persediaan tersedia di fase laporan (P2-F).',
          child:
              IconButton(icon: const Icon(Icons.print_outlined), onPressed: null),
        ),
        IconButton(
            icon: const Icon(Icons.refresh), tooltip: 'Muat Ulang', onPressed: _muat),
      ]),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _muat, child: const Text('Coba Lagi')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 260,
                            child: TextField(
                              decoration: const InputDecoration(
                                  hintText: 'Cari kode / nama / barcode...',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              onSubmitted: (v) {
                                _kataKunci = v.trim();
                                _halaman = 1;
                                _muat();
                              },
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pilihTanggal(dari: true),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text('Dari: ${_fmtTgl.format(_dari)}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pilihTanggal(dari: false),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text('Sampai: ${_fmtTgl.format(_sampai)}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<String>(
                              value: _filter,
                              isDense: true,
                              decoration: const InputDecoration(
                                  labelText: 'Filter',
                                  isDense: true,
                                  border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(
                                    value: 'semua', child: Text('Semua')),
                                DropdownMenuItem(
                                    value: 'minimum',
                                    child: Text('Stok minimum')),
                                DropdownMenuItem(
                                    value: 'negatif',
                                    child: Text('Stok negatif')),
                                DropdownMenuItem(
                                    value: 'tersedia',
                                    child: Text('Stok tersedia')),
                              ],
                              onChanged: (v) {
                                _filter = v ?? 'semua';
                                _halaman = 1;
                                _muat();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppDataTable(
                        minWidth: 1040,
                        emptyText: 'Tidak ada data persediaan.',
                        columns: const [
                          AppTableColumn('Kode', flex: 1),
                          AppTableColumn('Nama Barang', flex: 3),
                          AppTableColumn('Sat', flex: 1),
                          AppTableColumn('Hrg Beli', flex: 2,
                              align: TextAlign.right),
                          AppTableColumn('Awal', flex: 1, align: TextAlign.right),
                          AppTableColumn('Masuk', flex: 1,
                              align: TextAlign.right),
                          AppTableColumn('Keluar', flex: 1,
                              align: TextAlign.right),
                          AppTableColumn('Akhir', flex: 1,
                              align: TextAlign.right),
                          AppTableColumn('Total Harga', flex: 2,
                              align: TextAlign.right),
                          AppTableColumn('Min', flex: 1, align: TextAlign.right),
                        ],
                        rows: _data.map((p) {
                          final akhir = (p['akhir'] as num?)?.toDouble() ?? 0;
                          final min = (p['stokMinimum'] as num?)?.toDouble() ?? 0;
                          final negatif = akhir < 0;
                          final diBawahMin = akhir <= min && min > 0;
                          return AppTableRowData(
                            onTap: () => _bukaKartuStok(p),
                            cells: [
                              AppTableCell.text('${p['kode']}',
                                  flex: 1,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12)),
                              AppTableCell.text('${p['nama']}',
                                  flex: 3, maxLines: 2),
                              AppTableCell.text('${p['satuan'] ?? ''}', flex: 1),
                              AppTableCell.text(
                                  _fmtRp.format((p['hargaBeli'] as num?) ?? 0),
                                  flex: 2,
                                  align: TextAlign.right),
                              AppTableCell.text(
                                  _fmtQty.format((p['awal'] as num?) ?? 0),
                                  flex: 1,
                                  align: TextAlign.right),
                              AppTableCell.text(
                                  _fmtQty.format((p['masuk'] as num?) ?? 0),
                                  flex: 1,
                                  align: TextAlign.right),
                              AppTableCell.text(
                                  _fmtQty.format((p['keluar'] as num?) ?? 0),
                                  flex: 1,
                                  align: TextAlign.right),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.right,
                                child: Text(
                                  _fmtQty.format(akhir),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: negatif
                                          ? AppColors.danger
                                          : (diBawahMin
                                              ? AppColors.warning
                                              : AppColors
                                                  .textPrimaryOf(context))),
                                ),
                              ),
                              AppTableCell.text(
                                  _fmtRp.format((p['totalHarga'] as num?) ?? 0),
                                  flex: 2,
                                  align: TextAlign.right),
                              AppTableCell.text(_fmtQty.format(min),
                                  flex: 1, align: TextAlign.right),
                            ],
                          );
                        }).toList(),
                        pagination: AppTablePagination(
                          halaman: _halaman,
                          totalHalaman: _totalHalaman,
                          totalData: _total,
                          labelData: 'produk',
                          onSebelumnya: _halaman > 1
                              ? () {
                                  _halaman--;
                                  _muat();
                                }
                              : null,
                          onBerikutnya: _halaman < _totalHalaman
                              ? () {
                                  _halaman++;
                                  _muat();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Kartu stok satu produk -- mutasi ber-tanggal + saldo berjalan (drill-down
/// baris persediaan; angka pada kartu HARUS rekonsil dgn kolom daftar).
class _KartuStokSheet extends StatefulWidget {
  final int produkId;
  final String kode;
  final String nama;
  final DateTime dari;
  final DateTime sampai;
  const _KartuStokSheet(
      {required this.produkId,
      required this.kode,
      required this.nama,
      required this.dari,
      required this.sampai});

  @override
  State<_KartuStokSheet> createState() => _KartuStokSheetState();
}

class _KartuStokSheetState extends State<_KartuStokSheet> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _baris = [];
  double _saldoAwal = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('si_inventory_ledger', {
        'produk_id': widget.produkId,
        'dari': _fmtTgl.format(widget.dari),
        'sampai': _fmtTgl.format(widget.sampai),
      });
      setStateIfMounted(() {
        _baris = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _saldoAwal = (hasil['saldoAwal'] as num?)?.toDouble() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      expand: false,
      builder: (context, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(20),
        children: [
          Text('Kartu Stok — ${widget.kode} ${widget.nama}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              'Periode ${_fmtTgl.format(widget.dari)} s.d. ${_fmtTgl.format(widget.sampai)} · '
              'Saldo awal periode: ${_fmtQty.format(_saldoAwal)}',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
              ]),
            )
          else if (_baris.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Tidak ada mutasi pada periode ini.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondaryOf(context))),
            )
          else
            AppDataTable(
              minWidth: 760,
              columns: const [
                AppTableColumn('Waktu', flex: 2),
                AppTableColumn('Jenis Mutasi', flex: 3),
                AppTableColumn('Ref', flex: 1),
                AppTableColumn('Masuk', flex: 1, align: TextAlign.right),
                AppTableColumn('Keluar', flex: 1, align: TextAlign.right),
                AppTableColumn('Saldo', flex: 1, align: TextAlign.right),
              ],
              rows: _baris
                  .map((b) => AppTableRowData(cells: [
                        AppTableCell.text('${b['waktu']}'.split('.').first,
                            flex: 2,
                            style: const TextStyle(fontSize: 11.5)),
                        AppTableCell.text('${b['jenis']}', flex: 3),
                        AppTableCell.text('${b['referensi'] ?? ''}', flex: 1),
                        AppTableCell.text(
                            _fmtQty.format((b['masuk'] as num?) ?? 0),
                            flex: 1,
                            align: TextAlign.right,
                            style: const TextStyle(
                                color: AppColors.success, fontSize: 12.5)),
                        AppTableCell.text(
                            _fmtQty.format((b['keluar'] as num?) ?? 0),
                            flex: 1,
                            align: TextAlign.right,
                            style: const TextStyle(
                                color: AppColors.danger, fontSize: 12.5)),
                        AppTableCell.text(
                            _fmtQty.format((b['saldo'] as num?) ?? 0),
                            flex: 1,
                            align: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]))
                  .toList(),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Tutup')),
          ),
        ],
      ),
    );
  }
}
