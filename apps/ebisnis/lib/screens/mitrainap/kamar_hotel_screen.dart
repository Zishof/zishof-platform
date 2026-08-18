import 'package:flutter/material.dart';

import '../../services/master_offline.dart';
import '../../widgets/indikator_sinkron_master.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Kamar & Tipe Kamar per properti -- dua tab di atas satu pilihan properti
/// (aksi hotel_tipe_kamar_list/simpan + hotel_kamar_list/simpan).
/// status_hunian kamar hanya DITAMPILKAN di sini: kolom itu dipelihara aksi
/// check-in/checkout/pindah-kamar server, bukan diedit bebas dari master.
class KamarHotelScreen extends StatefulWidget {
  const KamarHotelScreen({super.key});

  @override
  State<KamarHotelScreen> createState() => _KamarHotelScreenState();
}

class _KamarHotelScreenState extends State<KamarHotelScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _properti = [];
  int? _propertiId;
  List<Map<String, dynamic>> _tipe = [];
  List<Map<String, dynamic>> _kamar = [];

  @override
  void initState() {
    super.initState();
    _muatProperti();
  }

  Future<void> _muatProperti() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final data = await muatDaftarHotel('hotel_properti_list', {});
      final id = _propertiId ??
          (data.isNotEmpty ? idInt(data.first['id']) : null);
      setStateIfMounted(() {
        _properti = data;
        _propertiId = id;
      });
      await _muatIsi();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muatIsi() async {
    final pid = _propertiId;
    if (pid == null) {
      setStateIfMounted(() {
        _tipe = [];
        _kamar = [];
        _memuat = false;
      });
      return;
    }
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final tipe =
          await muatDaftarHotel('hotel_tipe_kamar_list', {'properti_id': pid});
      final kamar =
          await muatDaftarHotel('hotel_kamar_list', {'properti_id': pid});
      setStateIfMounted(() {
        _tipe = tipe;
        _kamar = kamar;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  /// Offline-first (pola MasterOffline seragam semua master): server dulu,
  /// putus jaringan -> antre outbox_master + snackbar "tersimpan lokal";
  /// pengiriman latar + indikator animasi ditangani IndikatorSinkronMaster.
  Future<void> _kirim(String aksi, Map<String, dynamic> body,
      String pesanSukses, {required String kunci}) async {
    try {
      final res = await MasterOffline.simpanAtauAntre(aksi, body, kunci: kunci);
      final sukses = apiSukses(res);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['offline'] == true
            ? 'Tersimpan lokal — akan dikirim otomatis saat online.'
            : sukses
                ? apiPesan(res, pesanSukses)
                : 'Gagal: ${apiPesan(res, res['status'].toString())}'),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error,
      ));
      if (sukses && res['offline'] != true) _muatIsi();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  Future<void> _simpanTipe(Map<String, dynamic>? awal) async {
    final pid = _propertiId;
    if (pid == null) return;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormTipeKamarDialog(awal: awal),
    );
    if (hasil == null) return;
    hasil['properti_id'] = pid;
    await _kirim('hotel_tipe_kamar_simpan', hasil, 'Tipe kamar tersimpan.',
        kunci: hasil['id'] != null
            ? 'hotel_tipe_kamar:${hasil['id']}'
            : 'hotel_tipe_kamar:baru:${DateTime.now().microsecondsSinceEpoch}');
  }

  Future<void> _simpanKamar(Map<String, dynamic>? awal) async {
    final pid = _propertiId;
    if (pid == null) return;
    if (_tipe.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Buat Tipe Kamar dulu sebelum menambah kamar.')));
      return;
    }
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormKamarDialog(awal: awal, daftarTipe: _tipe),
    );
    if (hasil == null) return;
    hasil['properti_id'] = pid;
    await _kirim('hotel_kamar_simpan', hasil, 'Kamar tersimpan.',
        kunci: hasil['id'] != null
            ? 'hotel_kamar:${hasil['id']}'
            : 'hotel_kamar:baru:${DateTime.now().microsecondsSinceEpoch}');
  }

  Widget _daftarTipe() {
    if (_tipe.isEmpty) {
      return const Center(
          child: Text('Belum ada tipe kamar untuk properti ini.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _tipe.length,
      itemBuilder: (context, i) {
        final t = _tipe[i];
        final aktif = t['aktif'] != false;
        return Card(
          child: ListTile(
            leading: Icon(Icons.king_bed_outlined,
                color: aktif
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor),
            title: Text('${t['nama'] ?? '-'}${aktif ? '' : '  (nonaktif)'}'),
            subtitle: Text([
              if ((t['kode'] ?? '').toString().isNotEmpty) 'Kode: ${t['kode']}',
              formatRupiahHotel.format(angka(t['harga_dasar'])),
              'Kapasitas: ${t['kapasitas'] ?? '-'}',
            ].join(' • ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _simpanTipe(t),
          ),
        );
      },
    );
  }

  Widget _daftarKamar() {
    if (_kamar.isEmpty) {
      return const Center(child: Text('Belum ada kamar untuk properti ini.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _kamar.length,
      itemBuilder: (context, i) {
        final k = _kamar[i];
        final aktif = k['aktif'] != false;
        final status = '${k['status_hunian'] ?? 'VACANT'}';
        return Card(
          child: ListTile(
            leading: Icon(Icons.meeting_room_outlined,
                color: aktif
                    ? _warnaStatus(context, status)
                    : Theme.of(context).disabledColor),
            title: Text('Kamar ${k['nomor'] ?? '-'}'
                '${aktif ? '' : '  (nonaktif)'}'),
            subtitle: Text([
              '${k['tipe_kamar_nama'] ?? '-'}',
              if (k['lantai'] != null) 'Lantai ${k['lantai']}',
            ].join(' • ')),
            trailing: Wrap(spacing: 8, crossAxisAlignment:
                WrapCrossAlignment.center, children: [
              Chip(
                label: Text(status, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
              const Icon(Icons.edit_outlined),
            ]),
            onTap: () => _simpanKamar(k),
          ),
        );
      },
    );
  }

  static Color _warnaStatus(BuildContext context, String status) {
    switch (status) {
      case 'OCCUPIED':
        return Colors.orange;
      case 'DIRTY':
        return Colors.brown;
      case 'OUT_OF_ORDER':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Kamar & Tipe Kamar'),
            actions: [
              const IndikatorSinkronMaster(),
              IconButton(
                  onPressed: _muatProperti,
                  tooltip: 'Muat ulang',
                  icon: const Icon(Icons.refresh)),
            ],
            bottom: const TabBar(tabs: [
              Tab(text: 'Tipe Kamar'),
              Tab(text: 'Kamar'),
            ]),
          ),
          floatingActionButton: _propertiId == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () {
                    final tab = DefaultTabController.of(context).index;
                    if (tab == 0) {
                      _simpanTipe(null);
                    } else {
                      _simpanKamar(null);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah'),
                ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: PilihPropertiHotel(
                daftar: _properti,
                nilai: _propertiId,
                onUbah: (v) {
                  setState(() => _propertiId = v);
                  _muatIsi();
                },
              ),
            ),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _galat != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_galat!, textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                      onPressed: _muatProperti,
                                      child: const Text('Coba lagi')),
                                ]),
                          ),
                        )
                      : _propertiId == null
                          ? const Center(
                              child: Text(
                                  'Belum ada properti. Buat properti dulu di '
                                  'menu Properti Hotel.'))
                          : TabBarView(children: [
                              _daftarTipe(),
                              _daftarKamar(),
                            ]),
            ),
          ]),
        );
      }),
    );
  }
}

class _FormTipeKamarDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  const _FormTipeKamarDialog({this.awal});

  @override
  State<_FormTipeKamarDialog> createState() => _FormTipeKamarDialogState();
}

class _FormTipeKamarDialogState extends State<_FormTipeKamarDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _kode;
  late final TextEditingController _harga;
  late final TextEditingController _kapasitas;
  late final TextEditingController _keterangan;
  late bool _aktif;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _nama = TextEditingController(text: '${a?['nama'] ?? ''}');
    _kode = TextEditingController(text: '${a?['kode'] ?? ''}');
    _harga = TextEditingController(
        text: a?['harga_dasar'] == null
            ? ''
            : angka(a!['harga_dasar']).toStringAsFixed(0));
    _kapasitas = TextEditingController(text: '${a?['kapasitas'] ?? ''}');
    _keterangan = TextEditingController(text: '${a?['keterangan'] ?? ''}');
    _aktif = a?['aktif'] != false;
  }

  @override
  void dispose() {
    _nama.dispose();
    _kode.dispose();
    _harga.dispose();
    _kapasitas.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.awal == null ? 'Tambah Tipe Kamar' : 'Ubah Tipe Kamar'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(
                    labelText: 'Nama tipe *', hintText: 'mis. Deluxe Twin'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              TextFormField(
                controller: _kode,
                decoration: const InputDecoration(labelText: 'Kode'),
              ),
              TextFormField(
                controller: _harga,
                decoration: const InputDecoration(
                    labelText: 'Harga dasar per malam (Rp)'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _kapasitas,
                decoration:
                    const InputDecoration(labelText: 'Kapasitas (orang)'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _keterangan,
                decoration: const InputDecoration(labelText: 'Keterangan'),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(<String, dynamic>{
              if (widget.awal?['id'] != null) 'id': widget.awal!['id'],
              'nama': _nama.text.trim(),
              'kode': _kode.text.trim(),
              'harga_dasar': double.tryParse(
                  _harga.text.trim().replaceAll('.', '').replaceAll(',', '.')),
              'kapasitas': int.tryParse(_kapasitas.text.trim()),
              'keterangan': _keterangan.text.trim(),
              'aktif': _aktif,
            });
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _FormKamarDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final List<Map<String, dynamic>> daftarTipe;
  const _FormKamarDialog({this.awal, required this.daftarTipe});

  @override
  State<_FormKamarDialog> createState() => _FormKamarDialogState();
}

class _FormKamarDialogState extends State<_FormKamarDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomor;
  late final TextEditingController _lantai;
  late final TextEditingController _keterangan;
  int? _tipeId;
  late bool _aktif;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _nomor = TextEditingController(text: '${a?['nomor'] ?? ''}');
    _lantai = TextEditingController(text: '${a?['lantai'] ?? ''}');
    _keterangan = TextEditingController(text: '${a?['keterangan'] ?? ''}');
    _tipeId = idInt(a?['tipe_kamar_id']) ??
        (widget.daftarTipe.isNotEmpty
            ? idInt(widget.daftarTipe.first['id'])
            : null);
    _aktif = a?['aktif'] != false;
  }

  @override
  void dispose() {
    _nomor.dispose();
    _lantai.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.awal == null ? 'Tambah Kamar' : 'Ubah Kamar'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _nomor,
                decoration: const InputDecoration(
                    labelText: 'Nomor kamar *', hintText: 'mis. 101'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _tipeId,
                decoration: const InputDecoration(labelText: 'Tipe kamar *'),
                items: widget.daftarTipe
                    .map((t) => DropdownMenuItem<int>(
                          value: idInt(t['id']),
                          child: Text('${t['nama'] ?? t['id']}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _tipeId = v),
                validator: (v) => v == null ? 'Pilih tipe kamar' : null,
              ),
              TextFormField(
                controller: _lantai,
                decoration: const InputDecoration(labelText: 'Lantai'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _keterangan,
                decoration: const InputDecoration(labelText: 'Keterangan'),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(<String, dynamic>{
              if (widget.awal?['id'] != null) 'id': widget.awal!['id'],
              'nomor': _nomor.text.trim(),
              'tipe_kamar_id': _tipeId,
              'lantai': int.tryParse(_lantai.text.trim()),
              'keterangan': _keterangan.text.trim(),
              'aktif': _aktif,
            });
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
