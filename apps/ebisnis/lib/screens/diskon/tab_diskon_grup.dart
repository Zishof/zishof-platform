import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/simple_xlsx.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/safe_state.dart';

final _rupiahGrup =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Master-detail promo massal. Daftar dipaging 15 baris di server; detail
/// produk baru dimuat ketika editor dibuka agar ribuan produk tidak membebani
/// halaman awal.
class TabDiskonGrup extends StatefulWidget {
  const TabDiskonGrup({super.key});
  @override
  State<TabDiskonGrup> createState() => _TabDiskonGrupState();
}

class _TabDiskonGrupState extends State<TabDiskonGrup> {
  static const _pageSize = 15;
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  String? _error;
  int _page = 1, _total = 0;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setStateIfMounted(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiClient.instance.aksi('diskon_grup_list', {
        'page': _page,
        'page_size': _pageSize,
        if (_keyword.isNotEmpty) 'keyword': _keyword,
      });
      setStateIfMounted(() {
        _data = ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (r['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _loading = false);
    }
  }

  Future<void> _open([Map<String, dynamic>? item]) async {
    List<Map<String, dynamic>> detail = [];
    if (item != null) {
      try {
        final r = await ApiClient.instance
            .aksi('diskon_grup_detail', {'id': item['id']});
        detail = ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        if (r['snapshotSesuai'] == false && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Peringatan audit: snapshot JSON berbeda dengan tabel detail. Simpan ulang grup setelah memeriksa daftar produk.'),
              backgroundColor: AppColors.danger));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
        return;
      }
    }
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormDiskonGrup(item: item, detailAwal: detail),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = (_total / _pageSize).ceil().clamp(1, 999999);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: _load, child: const Text('Coba Lagi'))
      ]));
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Sesi.instance.bolehKelola
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Tambah Grup Diskon'))
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Cari nama grup diskon...',
                  border: OutlineInputBorder(),
                  isDense: true),
              onSubmitted: (v) {
                _keyword = v.trim();
                _page = 1;
                _load();
              },
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('GRUP DISKON')),
                    DataColumn(label: Text('PERIODE')),
                    DataColumn(label: Text('PRODUK'), numeric: true),
                    DataColumn(label: Text('NILAI')),
                    DataColumn(label: Text('JENIS')),
                    DataColumn(label: Text('PRIORITAS')),
                    DataColumn(label: Text('STATUS')),
                  ],
                  rows: _data.map((e) {
                    final p = (e['persentase'] as num?) ?? 0;
                    final nilai = p > 0
                        ? '${p.toString()}%'
                        : _rupiahGrup.format(e['nominal'] ?? 0);
                    final periode =
                        '${_tanggal(e['tanggalMulai'])} s/d ${_tanggal(e['tanggalSelesai'])}';
                    return DataRow(
                      onSelectChanged:
                          Sesi.instance.bolehKelola ? (_) => _open(e) : null,
                      cells: [
                        DataCell(SizedBox(
                            width: 240,
                            child: Text('${e['namaGrup']}',
                                overflow: TextOverflow.ellipsis))),
                        DataCell(Text(periode)),
                        DataCell(Text('${e['jumlahProduk'] ?? 0}')),
                        DataCell(Text(nilai,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text(e['potonganLangsung'] == true
                            ? 'Potong struk'
                            : 'Cashback')),
                        DataCell(Text(
                            '${e['prioritas'] ?? 100}${e['dapatDigabung'] == true ? ' • Gabung' : ' • Tunggal'}')),
                        DataCell(Chip(
                            label: Text(
                                e['aktif'] == true ? 'Aktif' : 'Nonaktif'))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_data.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada Diskon Grup.'))),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  onPressed: _page > 1
                      ? () {
                          _page--;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left)),
              Text('Halaman $_page / $pages - $_total grup'),
              IconButton(
                  onPressed: _page < pages
                      ? () {
                          _page++;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right)),
            ])
          ],
        ),
      ),
    );
  }

  String _tanggal(dynamic value) {
    final s = '${value ?? ''}';
    if (s.isEmpty) return 'Tanpa batas';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }
}

class _FormDiskonGrup extends StatefulWidget {
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> detailAwal;
  const _FormDiskonGrup({required this.item, required this.detailAwal});
  @override
  State<_FormDiskonGrup> createState() => _FormDiskonGrupState();
}

class _FormDiskonGrupState extends State<_FormDiskonGrup> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nama,
      _ket,
      _persen,
      _nominal,
      _cashback,
      _maks,
      _prioritas,
      _grupEksklusif;
  late List<Map<String, dynamic>> _produk;
  DateTime? _mulai, _selesai;
  bool _langsung = true,
      _aktif = true,
      _khususMember = false,
      _dapatDigabung = false,
      _saving = false,
      _loadingKriteria = true;
  String _dasarPerhitungan = 'SETELAH_DISKON';
  List<Map<String, dynamic>> _jenisMember = [], _tipeMember = [];
  final Set<int> _jenisTerpilih = {}, _tipeTerpilih = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.item;
    _nama = TextEditingController(text: '${a?['namaGrup'] ?? ''}');
    _ket = TextEditingController(text: '${a?['keterangan'] ?? ''}');
    _persen = TextEditingController(text: '${a?['persentase'] ?? 0}');
    _nominal = TextEditingController(text: '${a?['nominal'] ?? 0}');
    _cashback = TextEditingController(text: '${a?['cashback'] ?? 0}');
    _maks = TextEditingController(text: '${a?['maksimalPotongan'] ?? 0}');
    _prioritas = TextEditingController(text: '${a?['prioritas'] ?? 100}');
    _grupEksklusif =
        TextEditingController(text: '${a?['grupEksklusif'] ?? ''}');
    _langsung = a?['potonganLangsung'] ?? true;
    _aktif = a?['aktif'] ?? true;
    _khususMember = a?['khususMember'] ?? false;
    _dapatDigabung = a?['dapatDigabung'] ?? false;
    _dasarPerhitungan = '${a?['dasarPerhitungan'] ?? 'SETELAH_DISKON'}';
    for (final x in (a?['jenisMemberJson'] as List?) ?? const []) {
      if (x is num) _jenisTerpilih.add(x.toInt());
    }
    for (final x in (a?['tipeMemberJson'] as List?) ?? const []) {
      if (x is num) _tipeTerpilih.add(x.toInt());
    }
    _mulai = DateTime.tryParse('${a?['tanggalMulai'] ?? ''}');
    _selesai = DateTime.tryParse('${a?['tanggalSelesai'] ?? ''}');
    _produk = List<Map<String, dynamic>>.from(widget.detailAwal);
    _muatKriteriaMember();
  }

  Future<void> _muatKriteriaMember() async {
    try {
      final r = await ApiClient.instance.aksi('diskon_grup_opsi_member', {});
      setStateIfMounted(() {
        _jenisMember =
            ((r['jenisMember'] as List?) ?? []).cast<Map<String, dynamic>>();
        _tipeMember =
            ((r['tipeMember'] as List?) ?? []).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      setStateIfMounted(() => _error = 'Pilihan member gagal dimuat: $e');
    } finally {
      setStateIfMounted(() => _loadingKriteria = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nama,
      _ket,
      _persen,
      _nominal,
      _cashback,
      _maks,
      _prioritas,
      _grupEksklusif
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(DateTime? d) =>
      d == null ? '' : DateFormat("yyyy-MM-dd'T'HH:mm").format(d);

  Future<void> _pick(bool awal) async {
    final current = (awal ? _mulai : _selesai) ?? DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (d == null) return;
    setStateIfMounted(() {
      final v = DateTime(d.year, d.month, d.day, awal ? 0 : 23, awal ? 0 : 59);
      if (awal) {
        _mulai = v;
      } else {
        _selesai = v;
      }
    });
  }

  Future<void> _cariProduk() async {
    final q = TextEditingController();
    List<Map<String, dynamic>> result = [];
    bool loading = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) {
        Future<void> cari() async {
          setLocal(() => loading = true);
          try {
            final r = await ApiClient.instance
                .aksi('diskon_grup_produk_cari', {'keyword': q.text.trim()});
            result = ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          } finally {
            setLocal(() => loading = false);
          }
        }

        return AlertDialog(
          title: const Text('Tambah Produk'),
          content: SizedBox(
            width: 650,
            height: 430,
            child: Column(children: [
              TextField(
                  controller: q,
                  autofocus: true,
                  onSubmitted: (_) => cari(),
                  decoration: InputDecoration(
                      hintText: 'Kode, barcode, atau nama',
                      suffixIcon: IconButton(
                          onPressed: cari, icon: const Icon(Icons.search)))),
              const SizedBox(height: 8),
              Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: result.length,
                          itemBuilder: (_, i) {
                            final p = result[i];
                            final selected =
                                _produk.any((x) => x['id'] == p['id']);
                            return ListTile(
                              title: Text('${p['nama']}'),
                              subtitle: Text(
                                  '${p['kode']} | ${p['barcode']} | ${p['tokoNama']}'),
                              trailing: Icon(selected
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline),
                              onTap: selected
                                  ? null
                                  : () {
                                      setStateIfMounted(() => _produk.add(p));
                                      setLocal(() {});
                                    },
                            );
                          })),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Selesai'))
          ],
        );
      }),
    );
    q.dispose();
  }

  Future<void> _download() async {
    final bytes = buildSimpleXlsx(
      sheetName: 'Produk Diskon Grup',
      headers: const ['Kode Produk', 'Barcode', 'Nama Produk'],
      rows: _produk
          .map((p) => [p['kode'] ?? '', p['barcode'] ?? '', p['nama'] ?? ''])
          .toList(),
    );
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Produk Diskon Grup',
        fileName:
            'Diskon_Grup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes);
    if (path != null) await File(path).writeAsBytes(bytes);
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final raw =
        f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (raw == null) throw 'File Excel tidak dapat dibaca.';
    final rows = readSimpleXlsx(Uint8List.fromList(raw));
    final keys = <String>[];
    for (final row in rows.skip(1)) {
      final kode = row.isNotEmpty ? row[0].trim() : '';
      final barcode = row.length > 1 ? row[1].trim() : '';
      if (kode.isNotEmpty || barcode.isNotEmpty) {
        keys.add(kode.isNotEmpty ? kode : barcode);
      }
    }
    final r = await ApiClient.instance
        .aksi('diskon_grup_produk_resolve', {'kunci': keys});
    final found = ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    final missing =
        ((r['tidakDitemukan'] as List?) ?? []).map((e) => '$e').toList();
    setStateIfMounted(() {
      for (final p in found) {
        if (!_produk.any((x) => x['id'] == p['id'])) _produk.add(p);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(missing.isEmpty
              ? '${found.length} produk berhasil dibaca dari Excel.'
              : '${found.length} ditemukan; ${missing.length} tidak ditemukan: ${missing.take(5).join(', ')}')));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_produk.isEmpty) {
      setStateIfMounted(() => _error = 'Tambahkan minimal satu produk.');
      return;
    }
    setStateIfMounted(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.aksi('diskon_grup_simpan', {
        if (widget.item != null) 'id': widget.item!['id'],
        'nama_grup': _nama.text.trim(),
        'keterangan': _ket.text.trim(),
        'persentase': double.tryParse(_persen.text.replaceAll(',', '.')) ?? 0,
        'nominal': double.tryParse(_nominal.text.replaceAll(',', '.')) ?? 0,
        'cashback': double.tryParse(_cashback.text.replaceAll(',', '.')) ?? 0,
        'maksimal_potongan':
            double.tryParse(_maks.text.replaceAll(',', '.')) ?? 0,
        'prioritas': int.tryParse(_prioritas.text) ?? 100,
        'dapat_digabung': _dapatDigabung,
        'dasar_perhitungan': _dasarPerhitungan,
        'grup_eksklusif': _grupEksklusif.text.trim(),
        'potongan_langsung': _langsung,
        'tanggal_mulai': _iso(_mulai),
        'tanggal_selesai': _iso(_selesai),
        'berlaku_semua_member': !_khususMember,
        'khusus_member': _khususMember,
        'jenis_member_ids': _jenisTerpilih.toList(),
        'tipe_member_ids': _tipeTerpilih.toList(),
        'aktif': _aktif,
        'produk': _produk.map((p) => {'id': p['id']}).toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy');
    return DraggableScrollableSheet(
      initialChildSize: .94,
      maxChildSize: .98,
      expand: false,
      builder: (_, sc) => Material(
        child: Form(
          key: _form,
          child: ListView(
              controller: sc,
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                    widget.item == null
                        ? 'Tambah Grup Diskon'
                        : 'Ubah Grup Diskon',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Text(
                    'Satu periode dan nilai promo untuk banyak produk. Semua perubahan header, detail, dan snapshot JSON disimpan atomik.'),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red))),
                TextFormField(
                    controller: _nama,
                    decoration:
                        const InputDecoration(labelText: 'Nama Grup Diskon *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Wajib diisi' : null),
                TextFormField(
                    controller: _ket,
                    decoration: const InputDecoration(labelText: 'Keterangan'),
                    maxLines: 2),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(
                      width: 210,
                      child: TextFormField(
                          controller: _persen,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Persentase (%)'))),
                  SizedBox(
                      width: 210,
                      child: TextFormField(
                          controller: _nominal,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Nominal Diskon'))),
                  SizedBox(
                      width: 210,
                      child: TextFormField(
                          controller: _cashback,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Cashback per item'))),
                  SizedBox(
                      width: 210,
                      child: TextFormField(
                          controller: _maks,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Maksimal Potongan'))),
                  OutlinedButton.icon(
                      onPressed: () => _pick(true),
                      icon: const Icon(Icons.event),
                      label: Text(
                          _mulai == null ? 'Mulai' : date.format(_mulai!))),
                  OutlinedButton.icon(
                      onPressed: () => _pick(false),
                      icon: const Icon(Icons.event_available),
                      label: Text(_selesai == null
                          ? 'Selesai'
                          : date.format(_selesai!))),
                ]),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Boleh digabung dengan promo lain'),
                    subtitle: const Text(
                        'Default mati. Jika aktif, aturan dihitung dari prioritas terbesar ke terkecil.'),
                    value: _dapatDigabung,
                    onChanged: (v) =>
                        setStateIfMounted(() => _dapatDigabung = v)),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(
                    width: 210,
                    child: TextFormField(
                      controller: _prioritas,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Prioritas',
                          helperText: 'Lebih besar dihitung lebih dahulu'),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      value: _dasarPerhitungan,
                      decoration: const InputDecoration(
                          labelText: 'Dasar perhitungan promo berikutnya'),
                      items: const [
                        DropdownMenuItem(
                            value: 'SETELAH_DISKON',
                            child: Text('Harga setelah diskon sebelumnya')),
                        DropdownMenuItem(
                            value: 'HARGA_AWAL', child: Text('Harga awal')),
                      ],
                      onChanged: (v) => setStateIfMounted(
                          () => _dasarPerhitungan = v ?? 'SETELAH_DISKON'),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextFormField(
                      controller: _grupEksklusif,
                      decoration: const InputDecoration(
                          labelText: 'Grup eksklusif (opsional)',
                          helperText: 'Kode sama tidak dapat ditumpuk'),
                    ),
                  ),
                ]),
                const Text(
                    'Contoh: promo 50% prioritas 200 lalu promo 20% prioritas 100 dengan dasar harga setelah diskon menghasilkan potongan efektif 60%.'),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Potong langsung di struk'),
                    subtitle:
                        const Text('Matikan untuk menjadikannya cashback.'),
                    value: _langsung,
                    onChanged: (v) => setStateIfMounted(() => _langsung = v)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Khusus untuk member'),
                    subtitle: const Text(
                        'Jika mati, promo berlaku juga untuk pembeli umum. Jika aktif, jenis dan tipe member dapat dibatasi.'),
                    value: _khususMember,
                    onChanged: (v) =>
                        setStateIfMounted(() => _khususMember = v)),
                if (_khususMember) ...[
                  const SizedBox(height: 8),
                  Text('Jenis Member (boleh lebih dari satu)',
                      style: Theme.of(context).textTheme.titleSmall),
                  if (_loadingKriteria)
                    const LinearProgressIndicator()
                  else
                    Wrap(
                        spacing: 8,
                        children: _jenisMember.map((e) {
                          final id = (e['id'] as num).toInt();
                          return FilterChip(
                              label: Text('${e['nama']}'),
                              selected: _jenisTerpilih.contains(id),
                              onSelected: (v) => setStateIfMounted(() => v
                                  ? _jenisTerpilih.add(id)
                                  : _jenisTerpilih.remove(id)));
                        }).toList()),
                  const SizedBox(height: 8),
                  Text('Tipe Member (boleh lebih dari satu)',
                      style: Theme.of(context).textTheme.titleSmall),
                  Wrap(
                      spacing: 8,
                      children: _tipeMember.map((e) {
                        final id = (e['id'] as num).toInt();
                        return FilterChip(
                            label: Text('${e['nama']}'),
                            selected: _tipeTerpilih.contains(id),
                            onSelected: (v) => setStateIfMounted(() => v
                                ? _tipeTerpilih.add(id)
                                : _tipeTerpilih.remove(id)));
                      }).toList()),
                  const Text(
                      'Jika tidak ada pilihan, promo berlaku untuk semua member. Pilihan disimpan sebagai JSON agar mendukung banyak kriteria.'),
                ],
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif'),
                    value: _aktif,
                    onChanged: (v) => setStateIfMounted(() => _aktif = v)),
                const Divider(),
                Row(children: [
                  Expanded(
                      child: Text('Produk (${_produk.length})',
                          style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Excel')),
                  TextButton.icon(
                      onPressed: _upload,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload Excel')),
                  FilledButton.icon(
                      onPressed: _cariProduk,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah Produk')),
                ]),
                const Text(
                    'Format Excel: Kode Produk, Barcode, Nama Produk. Kode atau barcode dipakai untuk pencocokan; baris yang tidak ditemukan dilaporkan dan tidak disimpan.'),
                const SizedBox(height: 8),
                ..._produk.map((p) => Card(
                    child: ListTile(
                        title: Text('${p['nama']}'),
                        subtitle: Text(
                            '${p['kode']} | ${p['barcode']} | ${p['tokoNama']}'),
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger),
                            onPressed: () => setStateIfMounted(() => _produk
                                .removeWhere((x) => x['id'] == p['id'])))))),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Batal')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: const Text('Simpan Grup Diskon')),
                ])
              ]),
        ),
      ),
    );
  }
}
