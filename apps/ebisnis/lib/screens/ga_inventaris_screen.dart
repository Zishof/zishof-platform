import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

class GaInventarisScreen extends StatefulWidget {
  const GaInventarisScreen({super.key});
  @override
  State<GaInventarisScreen> createState() => _GaInventarisScreenState();
}

class _GaInventarisScreenState extends State<GaInventarisScreen> {
  final _cari = TextEditingController();
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _memuat = true, _bolehKelola = false;
  String? _error;
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
      final r = await ApiClient.instance.aksi('ga_inventaris_daftar',
          {'keyword': _cari.text.trim(), 'page_size': 500});
      setStateIfMounted(() {
        _data = ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _bolehKelola = r['bolehKelola'] == true;
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _tambah() async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => const _FormAsetGa());
    if (ok == true) await _muat();
  }

  Future<void> _ubah(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _FormUnitGa(data: row));
    if (ok == true) await _muat();
  }

  Future<void> _bukaPengajuan() async {
    await showDialog<void>(
        context: context, builder: (_) => _GaPengajuanDialog(aset: _data));
    await _muat();
  }

  @override
  Widget build(BuildContext context) => AppShell(
      menuAktif: MenuEBisnis.gaInventaris,
      judul: 'Inventaris General Affair',
      subjudul: 'Unit aset, barcode, status, lokasi, dan nilai per tenant',
      scrollable: false,
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _cari,
                      onSubmitted: (_) => _muat(),
                      decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Cari nama, jenis, atau barcode',
                          suffixIcon: IconButton(
                              onPressed: _muat,
                              icon: const Icon(Icons.refresh))))),
              if (_bolehKelola) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                    onPressed: _tambah,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Aset'))
              ],
              const SizedBox(width: 12),
              OutlinedButton.icon(
                  onPressed: _bukaPengajuan,
                  icon: const Icon(Icons.approval_outlined),
                  label: const Text('Pengajuan'))
            ]),
            const SizedBox(height: 12),
            Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)))
                        : _data.isEmpty
                            ? const Center(
                                child: Text(
                                    'Belum ada inventaris untuk tenant ini.'))
                            : ListView.builder(
                                itemCount: _data.length,
                                itemBuilder: (_, i) {
                                  final x = _data[i];
                                  return Card(
                                      child: ListTile(
                                          onTap: _bolehKelola
                                              ? () => _ubah(x)
                                              : null,
                                          leading: const Icon(
                                              Icons.devices_other_outlined),
                                          title: Text('${x['nama'] ?? '-'}'),
                                          subtitle: Text(
                                              '${x['jenis'] ?? '-'} · ${x['barcode'] ?? '-'}\n${x['status'] ?? '-'} · ${x['lokasi'] ?? '-'}'),
                                          isThreeLine: true,
                                          trailing: Text(_rupiah.format(
                                              (x['hargaBeli'] as num?) ?? 0))));
                                }))
          ])));
}

class _GaPengajuanDialog extends StatefulWidget {
  const _GaPengajuanDialog({required this.aset});
  final List<Map<String, dynamic>> aset;
  @override
  State<_GaPengajuanDialog> createState() => _GaPengajuanDialogState();
}

class _GaPengajuanDialogState extends State<_GaPengajuanDialog> {
  bool _memuat = true;
  String? _error;
  bool _bolehGa = false, _bolehKeuangan = false;
  List<Map<String, dynamic>> _data = [];

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
      final r = await ApiClient.instance
          .aksi('ga_inventaris_pengajuan_daftar', {'page_size': 500});
      setStateIfMounted(() {
        _data = ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _bolehGa = r['bolehSetujuiGa'] == true;
        _bolehKeuangan = r['bolehSetujuiKeuangan'] == true;
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _tambah() async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _FormPengajuanGa(aset: widget.aset));
    if (ok == true) await _muat();
  }

  Future<void> _putusan(
      Map<String, dynamic> row, String tahap, bool setujui) async {
    try {
      await ApiClient.instance.aksi('ga_inventaris_pengajuan_putusan', {
        'id': row['id'],
        'tahap': tahap,
        'setujui': setujui,
      });
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
      child: SizedBox(
          width: 920,
          height: 680,
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Text('Pengajuan Inventaris Outlet',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(onPressed: _muat, icon: const Icon(Icons.refresh)),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                      onPressed: _tambah,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajukan')),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                const SizedBox(height: 12),
                Expanded(
                    child: _memuat
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: Text(_error!,
                                    style: const TextStyle(color: Colors.red)))
                            : _data.isEmpty
                                ? const Center(
                                    child:
                                        Text('Belum ada pengajuan inventaris.'))
                                : ListView.builder(
                                    itemCount: _data.length,
                                    itemBuilder: (_, i) {
                                      final x = _data[i];
                                      final status =
                                          '${x['status'] ?? 'DIAJUKAN'}';
                                      return Card(
                                          child: ListTile(
                                              leading: Icon(status
                                                      .contains('DITOLAK')
                                                  ? Icons.cancel_outlined
                                                  : status ==
                                                          'DISETUJUI_KEUANGAN'
                                                      ? Icons.verified_outlined
                                                      : Icons.hourglass_top),
                                              title: Text(
                                                  '${x['jenis'] ?? '-'} · ${x['nama'] ?? '-'}'),
                                              subtitle: Text(
                                                  '${x['tanggal'] ?? '-'} · Jumlah ${x['jumlah'] ?? 1}\n$status · ${x['alasan'] ?? ''}'),
                                              isThreeLine: true,
                                              trailing: _aksi(x, status)));
                                    }))
              ]))));

  Widget? _aksi(Map<String, dynamic> row, String status) {
    if (_bolehGa && status == 'DIAJUKAN') {
      return PopupMenuButton<bool>(
          onSelected: (v) => _putusan(row, 'GA', v),
          itemBuilder: (_) => const [
                PopupMenuItem(value: true, child: Text('Setujui GA')),
                PopupMenuItem(value: false, child: Text('Tolak GA')),
              ]);
    }
    if (_bolehKeuangan && status == 'DISETUJUI_GA') {
      return PopupMenuButton<bool>(
          onSelected: (v) => _putusan(row, 'KEUANGAN', v),
          itemBuilder: (_) => const [
                PopupMenuItem(value: true, child: Text('Setujui Keuangan')),
                PopupMenuItem(value: false, child: Text('Tolak Keuangan')),
              ]);
    }
    return null;
  }
}

class _FormPengajuanGa extends StatefulWidget {
  const _FormPengajuanGa({required this.aset});
  final List<Map<String, dynamic>> aset;
  @override
  State<_FormPengajuanGa> createState() => _FormPengajuanGaState();
}

class _FormPengajuanGaState extends State<_FormPengajuanGa> {
  String _jenis = 'PERMINTAAN';
  int? _asetId;
  final _nama = TextEditingController();
  final _jumlah = TextEditingController(text: '1');
  final _alasan = TextEditingController();
  final _tokoTujuan = TextEditingController();
  bool _simpan = false;

  @override
  void dispose() {
    _nama.dispose();
    _jumlah.dispose();
    _alasan.dispose();
    _tokoTujuan.dispose();
    super.dispose();
  }

  Future<void> _kirim() async {
    if (_nama.text.trim().isEmpty ||
        (_jenis != 'PERMINTAAN' && _asetId == null) ||
        (_jenis == 'PERPINDAHAN' && int.tryParse(_tokoTujuan.text) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lengkapi jenis, aset, dan keterangannya.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('ga_inventaris_pengajuan_simpan', {
        'jenis': _jenis,
        'nama': _nama.text.trim(),
        'jumlah': int.tryParse(_jumlah.text) ?? 1,
        'alasan': _alasan.text.trim(),
        if (_asetId != null) 'asset_detail_id': _asetId,
        if (_jenis == 'PERPINDAHAN')
          'toko_tujuan_id': int.tryParse(_tokoTujuan.text),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _simpan = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Ajukan Inventaris'),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                    value: _jenis,
                    decoration:
                        const InputDecoration(labelText: 'Jenis pengajuan'),
                    items: const [
                      DropdownMenuItem(
                          value: 'PERMINTAAN',
                          child: Text('Permintaan inventaris')),
                      DropdownMenuItem(
                          value: 'RETUR', child: Text('Retur inventaris')),
                      DropdownMenuItem(
                          value: 'PERPINDAHAN',
                          child: Text('Perpindahan inventaris')),
                    ],
                    onChanged: (v) => setState(() {
                          _jenis = v ?? 'PERMINTAAN';
                          if (_jenis == 'PERMINTAAN') _asetId = null;
                        })),
                if (_jenis != 'PERMINTAAN') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                      value: _asetId,
                      decoration:
                          const InputDecoration(labelText: 'Unit aset *'),
                      items: widget.aset
                          .map((x) => DropdownMenuItem<int>(
                              value: (x['id'] as num).toInt(),
                              child: Text('${x['nama']} · ${x['barcode']}')))
                          .toList(),
                      onChanged: (v) => setState(() {
                            _asetId = v;
                            Map<String, dynamic>? row;
                            for (final item in widget.aset) {
                              if ((item['id'] as num?)?.toInt() == v) {
                                row = item;
                                break;
                              }
                            }
                            if (row != null) {
                              _nama.text = '${row['nama'] ?? ''}';
                            }
                          }))
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: _nama,
                    decoration: const InputDecoration(
                        labelText: 'Nama / keterangan aset *')),
                const SizedBox(height: 10),
                TextField(
                    controller: _jumlah,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah')),
                if (_jenis == 'PERPINDAHAN') ...[
                  const SizedBox(height: 10),
                  TextField(
                      controller: _tokoTujuan,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'ID toko tujuan *'))
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: _alasan,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Alasan / catatan'))
              ]))),
          actions: [
            TextButton(
                onPressed: _simpan ? null : () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(
                onPressed: _simpan ? null : _kirim,
                child: Text(_simpan ? 'Menyimpan…' : 'Kirim Pengajuan'))
          ]);
}

class _FormAsetGa extends StatefulWidget {
  const _FormAsetGa();
  @override
  State<_FormAsetGa> createState() => _FormAsetGaState();
}

class _FormAsetGaState extends State<_FormAsetGa> {
  final _nama = TextEditingController(),
      _kode = TextEditingController(),
      _jumlah = TextEditingController(text: '1'),
      _harga = TextEditingController(text: '0'),
      _ket = TextEditingController();
  bool _simpan = false, _dipinjam = true;
  @override
  void dispose() {
    for (final c in [_nama, _kode, _jumlah, _harga, _ket]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kirim() async {
    if (_nama.text.trim().isEmpty) return;
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('ga_inventaris_simpan', {
        'nama': _nama.text.trim(),
        'kode': _kode.text.trim(),
        'jumlah': int.tryParse(_jumlah.text) ?? 1,
        'harga_beli':
            double.tryParse(_harga.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        'keterangan': _ket.text.trim(),
        'boleh_dipinjam': _dipinjam
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _simpan = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Tambah Aset General Affair'),
          content: SizedBox(
              width: 480,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: _nama,
                    decoration:
                        const InputDecoration(labelText: 'Nama aset *')),
                const SizedBox(height: 10),
                TextField(
                    controller: _kode,
                    decoration:
                        const InputDecoration(labelText: 'Kode (opsional)')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _jumlah,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Jumlah unit'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: _harga,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Harga beli/unit')))
                ]),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _dipinjam,
                    onChanged: (v) => setState(() => _dipinjam = v),
                    title: const Text('Boleh dipinjam')),
                TextField(
                    controller: _ket,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Keterangan'))
              ])),
          actions: [
            TextButton(
                onPressed: _simpan ? null : () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(
                onPressed: _simpan ? null : _kirim,
                child: Text(_simpan ? 'Menyimpan…' : 'Simpan'))
          ]);
}

class _FormUnitGa extends StatefulWidget {
  const _FormUnitGa({required this.data});
  final Map<String, dynamic> data;
  @override
  State<_FormUnitGa> createState() => _FormUnitGaState();
}

class _FormUnitGaState extends State<_FormUnitGa> {
  late final TextEditingController _nama, _ket;
  List<Map<String, dynamic>> _status = [], _lokasi = [];
  int? _statusId, _lokasiId;
  bool _simpan = false;
  @override
  void initState() {
    super.initState();
    _nama = TextEditingController(text: '${widget.data['nama'] ?? ''}');
    _ket = TextEditingController(text: '${widget.data['keterangan'] ?? ''}');
    _muat();
  }

  @override
  void dispose() {
    _nama.dispose();
    _ket.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    final r = await ApiClient.instance.aksi('ga_inventaris_referensi', {});
    setStateIfMounted(() {
      _status =
          ((r['statusAset'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _lokasi =
          ((r['lokasi'] as List?) ?? const []).cast<Map<String, dynamic>>();
    });
  }

  Future<void> _kirim() async {
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('ga_inventaris_ubah', {
        'id': widget.data['id'],
        'nama': _nama.text.trim(),
        'keterangan': _ket.text.trim(),
        'status_id': _statusId,
        'lokasi_id': _lokasiId
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _simpan = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Ubah Unit Inventaris'),
          content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: _nama,
                    decoration: const InputDecoration(labelText: 'Nama unit')),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                    value: _statusId,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: _status
                        .map((x) => DropdownMenuItem(
                            value: (x['id'] as num).toInt(),
                            child: Text('${x['nama']}')))
                        .toList(),
                    onChanged: (v) => setState(() => _statusId = v)),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                    value: _lokasiId,
                    decoration: const InputDecoration(labelText: 'Lokasi'),
                    items: _lokasi
                        .map((x) => DropdownMenuItem(
                            value: (x['id'] as num).toInt(),
                            child: Text('${x['nama']}')))
                        .toList(),
                    onChanged: (v) => setState(() => _lokasiId = v)),
                const SizedBox(height: 10),
                TextField(
                    controller: _ket,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Keterangan'))
              ])),
          actions: [
            TextButton(
                onPressed: _simpan ? null : () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(
                onPressed: _simpan ? null : _kirim,
                child: Text(_simpan ? 'Menyimpan…' : 'Simpan'))
          ]);
}
