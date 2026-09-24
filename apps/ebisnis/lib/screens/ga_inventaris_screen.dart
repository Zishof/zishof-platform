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
              ]
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
