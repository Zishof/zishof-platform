import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/safe_state.dart';
import 'nota_sales_screen.dart';

final _fmtRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Surat Perintah Sales Jalan / SPJ (layar legacy 39).</h3>
///
/// Pusat assignment: barang dibawa (bulk) + nota/invoice piutang dibawa (bulk,
/// satu invoice tak boleh dibawa dua SPJ aktif -- ditegakkan server). State
/// machine: DRAFT -> SUBMITTED -> APPROVED (Pemilik/Admin) -> mulai jalan
/// (si_trip_start, membuat Sesi Nota Sales) -> ... -> CLOSED.
class SpjScreen extends StatefulWidget {
  const SpjScreen({super.key});

  @override
  State<SpjScreen> createState() => _SpjScreenState();
}

const _statusSpj = [
  'SEMUA', 'DRAFT', 'SUBMITTED', 'APPROVED', 'ACTIVE', 'RETURNED',
  'RECONCILING', 'CLOSED', 'CANCELLED'
];

Color _warnaStatusSpj(String s) {
  switch (s) {
    case 'DRAFT':
      return Colors.blueGrey;
    case 'SUBMITTED':
      return Colors.blue;
    case 'APPROVED':
      return Colors.teal;
    case 'ACTIVE':
      return Colors.deepPurple;
    case 'RETURNED':
      return Colors.orange;
    case 'RECONCILING':
      return Colors.amber.shade800;
    case 'CLOSED':
      return AppColors.success;
    case 'CANCELLED':
      return AppColors.danger;
  }
  return Colors.grey;
}

class _SpjScreenState extends State<SpjScreen> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  String _filterStatus = 'SEMUA';

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
      final hasil = await ApiClient.instance.aksi('si_spj_list', {
        if (_filterStatus != 'SEMUA') 'status': _filterStatus,
      });
      setStateIfMounted(() {
        _data = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaForm({int? spjId}) async {
    final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _FormSpj(spjId: spjId)));
    if (ok == true) _muat();
  }

  Future<void> _bukaDetail(int spjId) async {
    final berubah = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _DetailSpj(spjId: spjId)));
    if (berubah == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final bolehBuat =
        Sesi.instance.bolehAksiIs('surat_perintah_sales', 'create');
    return AppShell(
      menuAktif: MenuEBisnis.suratPerintahSales,
      judul: 'Surat Perintah Sales Jalan (SPJ)',
      subjudul:
          'Assignment barang & nota dibawa per keberangkatan sales — layar legacy 39',
      scrollable: false,
      floatingActionButton: bolehBuat
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('SPJ Baru', style: TextStyle(color: Colors.white)),
            )
          : null,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              for (final s in _statusSpj)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    selected: _filterStatus == s,
                    onSelected: (_) {
                      setStateIfMounted(() => _filterStatus = s);
                      _muat();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _PanelError(pesan: _error!, onCoba: _muat)
                  : _data.isEmpty
                      ? Center(
                          child: Text('Belum ada SPJ.',
                              style: TextStyle(
                                  color: AppColors.textSecondaryOf(context))))
                      : RefreshIndicator(
                          onRefresh: _muat,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 80),
                            itemCount: _data.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final r = _data[i];
                              final status = '${r['status']}';
                              return Card(
                                margin: EdgeInsets.zero,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                        color:
                                            Theme.of(context).dividerColor)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () =>
                                      _bukaDetail((r['id'] as num).toInt()),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('${r['nomor']}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    fontSize: 13.5)),
                                            Text(
                                                'Sales: ${r['salesNama']} · ${r['jumlahBarang']} barang · ${r['jumlahNota']} nota',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors
                                                        .textSecondaryOf(
                                                            context))),
                                            Text(
                                                'Berangkat: ${'${r['tanggalBerangkat']}'.split('.').first} · Uang muka ${_fmtRp.format(r['uangMuka'] ?? 0)}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors
                                                        .textSecondaryOf(
                                                            context))),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: _warnaStatusSpj(status)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(status,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    _warnaStatusSpj(status))),
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

// =============================================================================
// DETAIL SPJ + transisi + nota assign + mulai jalan
// =============================================================================

class _DetailSpj extends StatefulWidget {
  final int spjId;
  const _DetailSpj({required this.spjId});

  @override
  State<_DetailSpj> createState() => _DetailSpjState();
}

class _DetailSpjState extends State<_DetailSpj> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _proses = false;
  bool _berubah = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final hasil =
          await ApiClient.instance.aksi('si_spj_detail', {'spj_id': widget.spjId});
      setStateIfMounted(
          () => _d = Map<String, dynamic>.from(hasil['data'] as Map));
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    }
  }

  Future<void> _aksi(String namaAksi, Map<String, dynamic> body,
      {String? sukses}) async {
    setStateIfMounted(() => _proses = true);
    try {
      await ApiClient.instance.aksi(namaAksi, body);
      _berubah = true;
      if (sukses != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(sukses)));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  Future<void> _aturNota() async {
    final dipilih = await showDialog<List<int>>(
        context: context,
        builder: (_) => _DialogPilihNota(
            terpilih: ((_d?['nota'] as List?) ?? [])
                .map((e) => ((e as Map)['piutangDocId'] as num).toInt())
                .toList()));
    if (dipilih == null) return;
    await _aksi('si_spj_nota_assign',
        {'spj_id': widget.spjId, 'piutang_doc_ids': dipilih},
        sukses: 'Nota dibawa diperbarui.');
  }

  Future<void> _mulaiJalan() async {
    setStateIfMounted(() => _proses = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('si_trip_start', {'spj_id': widget.spjId});
      _berubah = true;
      if (mounted) {
        final sessionId = (hasil['sessionId'] as num).toInt();
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DetailSesiNotaSales(sessionId: sessionId)));
        await _muat();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final bolehUbah =
        Sesi.instance.bolehAksiIs('surat_perintah_sales', 'update');
    final pemilik = !Sesi.instance.isSalesKeliling;
    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? 'Detail SPJ' : '${d['nomor']}'),
        leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_berubah)),
      ),
      body: _error != null
          ? _PanelError(pesan: _error!, onCoba: _muat)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    Expanded(
                        child: Text('Sales: ${d['salesNama']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _warnaStatusSpj('${d['status']}')
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('${d['status']}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _warnaStatusSpj('${d['status']}'))),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('Berangkat: ${'${d['tanggalBerangkat']}'.split('.').first}'),
                  if ('${d['rute']}'.isNotEmpty) Text('Rute: ${d['rute']}'),
                  if ('${d['kendaraan']}'.isNotEmpty)
                    Text('Kendaraan: ${d['kendaraan']}'),
                  Text('Uang muka: ${_fmtRp.format(d['uangMuka'] ?? 0)}'),
                  if ('${d['catatan']}'.isNotEmpty)
                    Text('Catatan: ${d['catatan']}'),
                  if ('${d['alasanBatal']}'.isNotEmpty)
                    Text('Alasan batal: ${d['alasanBatal']}',
                        style: TextStyle(color: AppColors.danger)),
                  const Divider(height: 22),
                  Text('Barang Dibawa (${(d['barang'] as List).length})',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  AppDataTable(
                    minWidth: 700,
                    emptyText: 'Belum ada barang.',
                    columns: const [
                      AppTableColumn('Produk', flex: 3),
                      AppTableColumn('Rencana', flex: 1, align: TextAlign.right),
                      AppTableColumn('Dimuat', flex: 1, align: TextAlign.right),
                      AppTableColumn('Terjual', flex: 1, align: TextAlign.right),
                      AppTableColumn('Kembali', flex: 1, align: TextAlign.right),
                      AppTableColumn('Harga Jual', flex: 2, align: TextAlign.right),
                    ],
                    rows: [
                      for (final b in (d['barang'] as List))
                        AppTableRowData(cells: [
                          AppTableCell.text('${(b as Map)['namaProduk']}', flex: 3),
                          AppTableCell.text('${b['qtyRencana']}',
                              flex: 1, align: TextAlign.right),
                          AppTableCell.text('${b['qtyDimuat']}',
                              flex: 1, align: TextAlign.right),
                          AppTableCell.text('${b['qtyTerjual']}',
                              flex: 1, align: TextAlign.right),
                          AppTableCell.text('${b['qtyKembali']}',
                              flex: 1, align: TextAlign.right),
                          AppTableCell.text(_fmtRp.format(b['hargaJual'] ?? 0),
                              flex: 2, align: TextAlign.right),
                        ]),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Nota/Invoice Dibawa (${(d['nota'] as List).length})',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  AppDataTable(
                    minWidth: 760,
                    emptyText: 'Belum ada nota dibawa.',
                    columns: const [
                      AppTableColumn('Faktur', flex: 2),
                      AppTableColumn('Customer', flex: 3),
                      AppTableColumn('Saldo Dibawa', flex: 2, align: TextAlign.right),
                      AppTableColumn('Tertagih', flex: 2, align: TextAlign.right),
                      AppTableColumn('Status', flex: 2),
                    ],
                    rows: [
                      for (final n in (d['nota'] as List))
                        AppTableRowData(cells: [
                          AppTableCell.text('${(n as Map)['fakturNomor']}', flex: 2),
                          AppTableCell.text('${n['customerNama']}', flex: 3),
                          AppTableCell.text(
                              _fmtRp.format(n['saldoSaatAssign'] ?? 0),
                              flex: 2,
                              align: TextAlign.right),
                          AppTableCell.text(_fmtRp.format(n['nilaiTertagih'] ?? 0),
                              flex: 2, align: TextAlign.right),
                          AppTableCell.text('${n['status']}', flex: 2),
                        ]),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_proses) const LinearProgressIndicator(),
                  if (!_proses && bolehUbah)
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if ('${d['status']}' == 'DRAFT' ||
                          '${d['status']}' == 'SUBMITTED') ...[
                        OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          _FormSpj(spjId: widget.spjId)));
                              if (ok == true) {
                                _berubah = true;
                                _muat();
                              }
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Ubah')),
                        OutlinedButton.icon(
                            onPressed: _aturNota,
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18),
                            label: const Text('Atur Nota Dibawa')),
                      ],
                      if ('${d['status']}' == 'APPROVED')
                        OutlinedButton.icon(
                            onPressed: _aturNota,
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18),
                            label: const Text('Atur Nota Dibawa')),
                      if ('${d['status']}' == 'DRAFT')
                        ElevatedButton(
                            onPressed: () => _aksi('si_spj_status',
                                {'spj_id': widget.spjId, 'status': 'SUBMITTED'}),
                            child: const Text('Ajukan (SUBMIT)')),
                      if ('${d['status']}' == 'SUBMITTED' && pemilik)
                        ElevatedButton(
                            onPressed: () => _aksi('si_spj_status',
                                {'spj_id': widget.spjId, 'status': 'APPROVED'}),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white),
                            child: const Text('Setujui (APPROVE)')),
                      if ('${d['status']}' == 'APPROVED')
                        ElevatedButton.icon(
                            onPressed: _mulaiJalan,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Mulai Jalan (Buka Sesi)')),
                      if (d['sessionId'] != null)
                        OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => DetailSesiNotaSales(
                                          sessionId:
                                              (d['sessionId'] as num).toInt())));
                              _muat();
                            },
                            icon: const Icon(Icons.route_outlined, size: 18),
                            label: Text(
                                'Buka Sesi (${d['sessionStatus']})')),
                      if ('${d['status']}' == 'DRAFT' ||
                          '${d['status']}' == 'SUBMITTED' ||
                          '${d['status']}' == 'APPROVED')
                        TextButton.icon(
                            onPressed: () async {
                              final ctrl = TextEditingController();
                              final ya = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Batalkan SPJ?'),
                                  content: TextField(
                                      controller: ctrl,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Alasan (wajib bila sudah APPROVED)')),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(c).pop(false),
                                        child: const Text('Tidak')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(c).pop(true),
                                        child: const Text('Ya')),
                                  ],
                                ),
                              );
                              if (ya == true) {
                                _aksi('si_spj_status', {
                                  'spj_id': widget.spjId,
                                  'status': 'CANCELLED',
                                  'alasan': ctrl.text.trim(),
                                });
                              }
                            },
                            icon: Icon(Icons.cancel_outlined,
                                size: 18, color: AppColors.danger),
                            label: Text('Batalkan',
                                style: TextStyle(color: AppColors.danger))),
                    ]),
                ]),
    );
  }
}

// =============================================================================
// FORM SPJ (create/update) + barang bulk
// =============================================================================

class _BarisBarang {
  int produkId;
  String nama;
  double qty;
  _BarisBarang(this.produkId, this.nama, this.qty);
}

class _FormSpj extends StatefulWidget {
  final int? spjId;
  const _FormSpj({this.spjId});

  @override
  State<_FormSpj> createState() => _FormSpjState();
}

class _FormSpjState extends State<_FormSpj> {
  int? _salesId;
  String _salesNama = '';
  DateTime _berangkat = DateTime.now();
  final _rute = TextEditingController();
  final _kendaraan = TextEditingController();
  final _uangMuka = TextEditingController(text: '0');
  final _catatan = TextEditingController();
  final List<_BarisBarang> _barang = [];
  bool _memuat = false;
  bool _menyimpan = false;
  String? _error;

  late final String _kodeUnik =
      'SPJ-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    if (widget.spjId != null) _muatSpj();
  }

  Future<void> _muatSpj() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('si_spj_detail', {'spj_id': widget.spjId});
      final d = Map<String, dynamic>.from(hasil['data'] as Map);
      setStateIfMounted(() {
        _salesId = (d['salesId'] as num?)?.toInt();
        _salesNama = '${d['salesNama']}';
        _rute.text = '${d['rute']}';
        _kendaraan.text = '${d['kendaraan']}';
        _uangMuka.text = '${((d['uangMuka'] as num?) ?? 0).round()}';
        _catatan.text = '${d['catatan']}';
        _barang.clear();
        for (final b in (d['barang'] as List? ?? [])) {
          final m = Map<String, dynamic>.from(b as Map);
          _barang.add(_BarisBarang((m['produkId'] as num).toInt(),
              '${m['namaProduk']}', (m['qtyRencana'] as num?)?.toDouble() ?? 0));
        }
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihSales() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _DialogCariSalesSpj());
    if (pilihan != null) {
      setStateIfMounted(() {
        _salesId = (pilihan['id'] as num).toInt();
        _salesNama = '${pilihan['nama']}';
      });
    }
  }

  Future<void> _tambahBarang() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _DialogCariProdukSpj());
    if (pilihan == null) return;
    setStateIfMounted(() => _barang.add(_BarisBarang(
        (pilihan['id'] as num).toInt(), '${pilihan['nama']}', 1)));
  }

  Future<void> _simpan() async {
    if (_barang.isEmpty) {
      setStateIfMounted(() => _error = 'Minimal satu barang dibawa.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      await ApiClient.instance
          .aksi(widget.spjId == null ? 'si_spj_create' : 'si_spj_update', {
        if (widget.spjId != null) 'spj_id': widget.spjId,
        if (widget.spjId == null && _salesId != null) 'sales_id': _salesId,
        if (widget.spjId == null) 'kode_unik': _kodeUnik,
        'tanggal_berangkat_rencana': _fmtTgl.format(_berangkat),
        'rute': _rute.text.trim(),
        'kendaraan': _kendaraan.text.trim(),
        'uang_muka_operasional': double.tryParse(_uangMuka.text) ?? 0,
        'catatan': _catatan.text.trim(),
        'barang': [
          for (final b in _barang)
            {'produk_id': b.produkId, 'qty_rencana': b.qty}
        ],
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tampilkanSales =
        !Sesi.instance.isSalesKeliling && widget.spjId == null;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.spjId == null ? 'SPJ Baru' : 'Ubah SPJ')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppInfoBanner(
                      icon: Icons.error_outline,
                      color: AppColors.danger,
                      text: _error!),
                ),
              AppFormSection(judul: 'Keberangkatan', children: [
                if (tampilkanSales)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(
                        _salesNama.isEmpty ? 'Pilih sales...' : _salesNama),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pilihSales,
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text('Berangkat: ${_fmtTgl.format(_berangkat)}'),
                  onTap: () async {
                    final t = await showDatePicker(
                        context: context,
                        initialDate: _berangkat,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035));
                    if (t != null) setStateIfMounted(() => _berangkat = t);
                  },
                ),
                TextField(
                    controller: _rute,
                    decoration: const InputDecoration(
                        labelText: 'Rute / wilayah tujuan')),
                TextField(
                    controller: _kendaraan,
                    decoration:
                        const InputDecoration(labelText: 'Kendaraan (opsional)')),
                TextField(
                    controller: _uangMuka,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Uang muka operasional (Rp)')),
                TextField(
                    controller: _catatan,
                    decoration:
                        const InputDecoration(labelText: 'Catatan (opsional)')),
              ]),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Barang Dibawa (rencana)',
                aksiJudul: TextButton.icon(
                    onPressed: _tambahBarang,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah')),
                children: [
                  if (_barang.isEmpty)
                    Text('Belum ada barang — tekan "Tambah".',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context))),
                  for (var i = 0; i < _barang.length; i++)
                    Row(children: [
                      Expanded(
                          flex: 3,
                          child: Text(_barang[i].nama,
                              style: const TextStyle(fontSize: 12.5))),
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: _barang[i].qty % 1 == 0
                              ? '${_barang[i].qty.round()}'
                              : '${_barang[i].qty}',
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Qty'),
                          onChanged: (v) => setStateIfMounted(() =>
                              _barang[i].qty = double.tryParse(v) ?? 0),
                        ),
                      ),
                      IconButton(
                          onPressed: () =>
                              setStateIfMounted(() => _barang.removeAt(i)),
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: AppColors.danger)),
                    ]),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan SPJ'),
              ),
            ]),
    );
  }
}

// =============================================================================
// Dialog pilih nota (multi) / sales / produk
// =============================================================================

class _DialogPilihNota extends StatefulWidget {
  final List<int> terpilih;
  const _DialogPilihNota({required this.terpilih});
  @override
  State<_DialogPilihNota> createState() => _DialogPilihNotaState();
}

class _DialogPilihNotaState extends State<_DialogPilihNota> {
  List<Map<String, dynamic>> _rows = [];
  final Set<int> _dipilih = {};
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _dipilih.addAll(widget.terpilih);
    _muat();
  }

  Future<void> _muat() async {
    try {
      final hasil = await ApiClient.instance.aksi('si_receivable_list', {
        'tampilkan_lunas': false,
        'page': 1,
        'page_size': 100,
      });
      setStateIfMounted(() => _rows = ((hasil['rows'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Nota/Invoice Dibawa'),
      content: SizedBox(
        width: 480,
        height: 440,
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                for (final r in _rows)
                  CheckboxListTile(
                    dense: true,
                    value: _dipilih.contains((r['id'] as num).toInt()),
                    title: Text('${r['nomor']} — ${r['customerNama']}',
                        style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(
                        'sisa ${_fmtRp.format(r['outstanding'] ?? 0)} · jt ${r['jatuhTempo'] ?? '-'}',
                        style: const TextStyle(fontSize: 11)),
                    onChanged: (v) => setStateIfMounted(() {
                      final id = (r['id'] as num).toInt();
                      if (v == true) {
                        _dipilih.add(id);
                      } else {
                        _dipilih.remove(id);
                      }
                    }),
                  ),
              ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(_dipilih.toList()..sort()),
            child: Text('Pakai (${_dipilih.length})')),
      ],
    );
  }
}

class _DialogCariSalesSpj extends StatefulWidget {
  const _DialogCariSalesSpj();
  @override
  State<_DialogCariSalesSpj> createState() => _DialogCariSalesSpjState();
}

class _DialogCariSalesSpjState extends State<_DialogCariSalesSpj> {
  List<Map<String, dynamic>> _rows = [];
  bool _memuat = false;

  Future<void> _cari(String q) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi('si_sales_list', {
        if (q.isNotEmpty) 'keyword': q,
        'aktif': 'aktif',
        'page': 1,
        'page_size': 20,
      });
      setStateIfMounted(() => _rows = ((hasil['rows'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Sales'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Cari kode/nama...', prefixIcon: Icon(Icons.search)),
              onSubmitted: _cari),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  dense: true,
                  title: Text('${r['kode']} — ${r['nama']}'),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DialogCariProdukSpj extends StatefulWidget {
  const _DialogCariProdukSpj();
  @override
  State<_DialogCariProdukSpj> createState() => _DialogCariProdukSpjState();
}

class _DialogCariProdukSpjState extends State<_DialogCariProdukSpj> {
  List<Map<String, dynamic>> _rows = [];
  bool _memuat = false;

  Future<void> _cari(String q) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('katalog', {if (q.isNotEmpty) 'keyword': q});
      setStateIfMounted(() => _rows = ((hasil['produk'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(30)
          .toList());
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Produk'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Cari kode/nama produk...',
                  prefixIcon: Icon(Icons.search)),
              onSubmitted: _cari),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  dense: true,
                  title: Text('${r['kode']} — ${r['nama']}'),
                  subtitle: Text(
                      '${_fmtRp.format(r['hargaJual'] ?? 0)} · stok ${r['stok'] ?? 0}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  final String pesan;
  final VoidCallback onCoba;
  const _PanelError({required this.pesan, required this.onCoba});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(pesan, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ]),
      ),
    );
  }
}
