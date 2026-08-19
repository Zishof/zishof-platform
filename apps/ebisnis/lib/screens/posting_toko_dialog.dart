import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

/// Dialog posting jurnal untuk rantai pengadaan &rarr; pembayaran toko:
/// kulakan, pembayaran hutang supplier, penerimaan piutang customer, dan
/// penyesuaian persediaan (retur beli/jual, selisih opname, mutasi antar outlet).
///
/// Pola tampilannya menyusul Posting HPP/Penjualan yang sudah ada: draf jurnal
/// ditampilkan PER DOKUMEN lebih dulu lengkap dengan akun debet/kreditnya, baris
/// yang belum siap tetap terlihat beserta alasannya, dan posting bisa dilakukan
/// per baris atau sekaligus untuk yang sudah siap.
class PostingTokoDialog extends StatefulWidget {
  const PostingTokoDialog({super.key, required this.jenis, required this.judul});

  /// `kulakan` | `bayar_hutang` | `terima_piutang` | `penyesuaian`
  final String jenis;
  final String judul;

  @override
  State<PostingTokoDialog> createState() => _PostingTokoDialogState();
}

class _PostingTokoDialogState extends State<PostingTokoDialog> {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  late DateTime _mulai;
  DateTime _sampai = DateTime.now();
  bool _sibuk = false;
  String? _galat;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _mulai = DateTime(kini.year, kini.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatDraf());
  }

  List<Map<String, dynamic>> get _rincian => ((_data?['rincian'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _pilihTanggal(bool awal) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: awal ? _mulai : _sampai,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() {
      if (awal) {
        _mulai = hasil;
      } else {
        _sampai = hasil;
      }
      _data = null;
    });
    await _muatDraf();
  }

  Future<void> _muatDraf() async {
    setStateIfMounted(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'posting_${widget.jenis}_draft',
        {'mulai': _fmt.format(_mulai), 'sampai': _fmt.format(_sampai)},
      );
      if (!mounted) return;
      setStateIfMounted(() => _data = Map<String, dynamic>.from(hasil));
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = e.toString());
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// [ids] kosong berarti "semua yang siap".
  Future<void> _posting(List<dynamic> ids) async {
    final satu = ids.length == 1;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(satu ? 'Posting dokumen ini?' : 'Posting semua yang siap?'),
        content: Text(satu
            ? 'Dokumen ini akan dijurnal tersendiri. Dokumen lain yang akunnya '
                'belum lengkap tidak ikut terhalang.'
            : 'Semua dokumen berstatus SIAP pada periode ini akan dijurnal. '
                'Dokumen yang belum siap dilewati.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Posting')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setStateIfMounted(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final body = <String, dynamic>{
        'mulai': _fmt.format(_mulai),
        'sampai': _fmt.format(_sampai),
      };
      if (ids.isNotEmpty) body['posting_ids'] = ids;
      final hasil =
          await ApiClient.instance.aksi('posting_${widget.jenis}_terapkan', body);
      if (!mounted) return;
      final masalah =
          ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${hasil['diposting'] ?? 0} jurnal terbentuk'
              '${masalah.isEmpty ? '.' : ', ${masalah.length} gagal: ${masalah.first}'}')));
      await _muatDraf();
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = e.toString());
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rincian = _rincian;
    final siap = rincian.where((r) => r['siap'] == true).toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(widget.judul,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${_data?['message'] ?? 'Menyiapkan draf jurnal...'}'
                  '  •  Draf hanya menghitung; jurnal baru ditulis saat tombol Posting ditekan.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: _sibuk ? null : () => _pilihTanggal(true),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Mulai ${_fmt.format(_mulai)}')),
                OutlinedButton.icon(
                    onPressed: _sibuk ? null : () => _pilihTanggal(false),
                    icon: const Icon(Icons.event_available, size: 18),
                    label: Text('Sampai ${_fmt.format(_sampai)}')),
                OutlinedButton.icon(
                    onPressed: _sibuk ? null : _muatDraf,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Muat ulang')),
                FilledButton.icon(
                    onPressed: _sibuk || siap.isEmpty ? null : () => _posting(const []),
                    icon: const Icon(Icons.post_add, size: 18),
                    label: Text('Posting semua yang siap (${siap.length})')),
                if (_sibuk)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              if (_galat != null) ...[
                const SizedBox(height: 8),
                Text(_galat!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: rincian.isEmpty
                    ? Center(
                        child: Text(_sibuk
                            ? 'Menghitung...'
                            : 'Tidak ada dokumen yang belum diposting pada periode ini.'))
                    : AppDataTable(
                        minWidth: 940,
                        emptyText: 'Tidak ada draf.',
                        columns: const [
                          AppTableColumn('Tanggal', flex: 2),
                          AppTableColumn('Referensi', flex: 3),
                          AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                          AppTableColumn('Debet', flex: 4),
                          AppTableColumn('Kredit', flex: 4),
                          AppTableColumn('Status', flex: 4),
                          AppTableColumn('Aksi', flex: 2),
                        ],
                        rows: rincian.map((r) {
                          final bisa = r['siap'] == true;
                          return AppTableRowData(cells: [
                            AppTableCell.text('${r['tanggal'] ?? ''}', flex: 2),
                            AppTableCell.text('${r['referensi'] ?? ''}', flex: 3),
                            AppTableCell.text(
                                _uang.format((r['nilai'] as num?)?.toDouble() ?? 0),
                                flex: 2,
                                align: TextAlign.right),
                            AppTableCell.text('${r['debet'] ?? ''}', flex: 4),
                            AppTableCell.text('${r['kredit'] ?? ''}', flex: 4),
                            AppTableCell.text(
                                bisa ? 'Siap diposting' : '${r['alasan'] ?? ''}',
                                flex: 4),
                            AppTableCell(
                              flex: 2,
                              child: bisa
                                  ? TextButton(
                                      onPressed: _sibuk
                                          ? null
                                          : () => _posting([r['id']]),
                                      child: const Text('Posting'))
                                  : const SizedBox.shrink(),
                            ),
                          ]);
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
