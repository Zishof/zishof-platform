import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/histori_pelunasan.dart';
import '../../widgets/app_components.dart';
import 'tab_mutasi_tabungan.dart' show PilihAnggotaSheet;

class HistoriPelunasanScreen extends StatefulWidget {
  final DateTime dari;
  final DateTime sampai;
  final int? idAnggota;
  final String? namaAnggota;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? pemuat;
  const HistoriPelunasanScreen(
      {super.key,
      required this.dari,
      required this.sampai,
      this.idAnggota,
      this.namaAnggota,
      this.pemuat});

  @override
  State<HistoriPelunasanScreen> createState() => _HistoriPelunasanScreenState();
}

class _HistoriPelunasanScreenState extends State<HistoriPelunasanScreen> {
  late DateTime _dari;
  late DateTime _sampai;
  int? _id;
  String? _nama;
  Map<String, dynamic>? _hasil;
  String? _peringatan;
  bool _memuat = true;
  bool _menyegarkan = false;
  int _generasi = 0;
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Map<String, dynamic> get _filter => {
        'dari': DateFormat('yyyy-MM-dd').format(_dari),
        'sampai': DateFormat('yyyy-MM-dd').format(_sampai),
        if (_id != null) 'id_anggota': _id,
      };

  @override
  void initState() {
    super.initState();
    _dari = widget.dari;
    _sampai = widget.sampai;
    _id = widget.idAnggota;
    _nama = widget.namaAnggota;
    _muat();
  }

  Future<void> _muat() async {
    final generasi = ++_generasi;
    final filter = _filter;
    final key = kunciHistoriPelunasan(filter);
    setState(() {
      _memuat = true;
      _menyegarkan = true;
      _peringatan = null;
      _hasil = null;
    });
    bool aktif() => mounted && generasi == _generasi;
    try {
      final cache = await HistoriPelunasan.baca(key);
      if (!aktif()) return;
      setState(() {
        _hasil = cache;
        _memuat = false;
      });
      // Cache sudah dapat dilihat ketika server masih berjalan/lambat.
      await HistoriPelunasan.segarkan(key, filter, pemuat: widget.pemuat);
      if (!aktif()) return;
      final baru = await HistoriPelunasan.baca(key);
      if (!aktif()) return;
      setState(() => _hasil = baru);
    } catch (e) {
      if (aktif()) {
        setState(() => _peringatan =
            '${_hasil == null ? 'Histori belum dapat dimuat.' : 'Menampilkan salinan lokal; penyegaran belum berhasil.'} $e');
      }
    } finally {
      if (aktif()) {
        setState(() {
          _memuat = false;
          _menyegarkan = false;
        });
      }
    }
  }

  Future<void> _halaman(int halaman) async {
    final generasi = _generasi;
    final hasil = await HistoriPelunasan.baca(kunciHistoriPelunasan(_filter),
        halaman: halaman);
    if (mounted && generasi == _generasi) setState(() => _hasil = hasil);
  }

  Future<void> _tanggal() async {
    final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(start: _dari, end: _sampai));
    if (range == null || !mounted) return;
    _dari = range.start;
    _sampai = range.end;
    await _muat();
  }

  Future<void> _pelanggan() async {
    final pelanggan = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const PilihAnggotaSheet());
    if (pelanggan == null || !mounted) return;
    _id = (pelanggan['id'] as num).toInt();
    _nama = '${pelanggan['nama']}';
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        (_hasil?['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    final page = _hasil?['halaman'] as int? ?? 1;
    final pages = _hasil?['totalHalaman'] as int? ?? 1;
    final diperbarui = DateTime.tryParse('${_hasil?['diperbarui']}');
    return Scaffold(
      appBar: AppBar(title: const Text('Histori Pembayaran Piutang')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _tanggal,
              icon: const Icon(Icons.date_range),
              label: Text(
                  '${DateFormat('dd/MM/yyyy').format(_dari)} – ${DateFormat('dd/MM/yyyy').format(_sampai)}')),
          OutlinedButton.icon(
              onPressed: _pelanggan,
              icon: const Icon(Icons.person_search),
              label: Text(_nama ?? 'Semua Pelanggan')),
          if (_id != null)
            IconButton(
                tooltip: 'Semua Pelanggan',
                onPressed: () {
                  _id = null;
                  _nama = null;
                  _muat();
                },
                icon: const Icon(Icons.clear)),
          OutlinedButton.icon(
              onPressed: _menyegarkan ? null : _muat,
              icon: const Icon(Icons.refresh),
              label: const Text('Muat Ulang')),
        ]),
        const SizedBox(height: 12),
        const Text(
            'Hanya pelunasan yang sudah tercatat di server. Entri yang masih Pending/Gagal dapat diperiksa pada menu Sinkronisasi dan belum dihitung di sini.'),
        if (_menyegarkan)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator()),
        if (_peringatan != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_peringatan!,
                  key: const ValueKey('peringatan-histori'))),
        if (diperbarui != null)
          Text(
              'Salinan diperbarui: ${DateFormat('dd/MM/yyyy HH:mm').format(diperbarui)}'),
        if (_memuat)
          const Center(child: CircularProgressIndicator())
        else if (_hasil != null) ...[
          const SizedBox(height: 16),
          Text(
              '${_hasil!['total']} pembayaran • Total ${_rupiah.format(_hasil!['nominal'])}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 850,
            emptyText: 'Belum ada pembayaran pada filter ini.',
            columns: const [
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Pelanggan', flex: 3),
              AppTableColumn('Nominal', flex: 2, align: TextAlign.right),
              AppTableColumn('Keterangan', flex: 3),
            ],
            rows: rows
                .map((r) => AppTableRowData(cells: [
                      AppTableCell.text(
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(DateTime.parse('${r['waktu']}')),
                          flex: 2),
                      AppTableCell.text('${r['namaAnggota'] ?? '-'}', flex: 3),
                      AppTableCell.text(_rupiah.format(r['berkurang']),
                          flex: 2, align: TextAlign.right),
                      AppTableCell(
                          flex: 3,
                          child: TextButton(
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => AlertDialog(
                                      title:
                                          const Text('Keterangan Pembayaran'),
                                      content: SingleChildScrollView(
                                          child: Text(
                                              '${r['keterangan'] ?? '-'}')),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Tutup'))
                                      ],
                                    )),
                            child: Text('${r['keterangan'] ?? '-'}',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          )),
                    ]))
                .toList(),
            pagination: AppTablePagination(
                halaman: page,
                totalHalaman: pages,
                totalData: _hasil!['total'] as int,
                labelData: 'pembayaran',
                onSebelumnya: page > 1 ? () => _halaman(page - 1) : null,
                onBerikutnya: page < pages ? () => _halaman(page + 1) : null),
          ),
        ],
      ]),
    );
  }
}
