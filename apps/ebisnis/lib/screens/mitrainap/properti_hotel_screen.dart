import 'package:flutter/material.dart';

import '../../services/master_offline.dart';
import '../../widgets/indikator_sinkron_master.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Master Properti Hotel -- daftar + form (aksi hotel_properti_list/simpan).
/// Satu akun boleh mengelola lebih dari satu properti (keputusan handover
/// §2.4); nonaktif = soft-delete, tidak ada hapus fisik.
class PropertiHotelScreen extends StatefulWidget {
  const PropertiHotelScreen({super.key});

  @override
  State<PropertiHotelScreen> createState() => _PropertiHotelScreenState();
}

class _PropertiHotelScreenState extends State<PropertiHotelScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final data = await muatDaftarHotel(
          'hotel_properti_list', {'termasuk_nonaktif': true});
      setStateIfMounted(() {
        _daftar = data;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _simpan(Map<String, dynamic>? awal) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormPropertiDialog(awal: awal),
    );
    if (hasil == null) return;
    try {
      final res = await MasterOffline.simpanAtauAntre(
          'hotel_properti_simpan', hasil,
          kunci: hasil['id'] != null
              ? 'hotel_properti:${hasil['id']}'
              : 'hotel_properti:baru:${DateTime.now().microsecondsSinceEpoch}');
      final sukses = apiSukses(res);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['offline'] == true
            ? 'Tersimpan lokal — akan dikirim otomatis saat online.'
            : sukses
                ? apiPesan(res, 'Properti tersimpan.')
                : 'Gagal: ${apiPesan(res, res['status'].toString())}'),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error,
      ));
      if (sukses && res['offline'] != true) _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Properti Hotel'),
        actions: [
          const IndikatorSinkronMaster(),
          IconButton(
              onPressed: _muat,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _simpan(null),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Properti'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ),
                )
              : _daftar.isEmpty
                  ? const Center(
                      child: Text(
                          'Belum ada properti. Tambahkan properti/penginapan '
                          'pertama Anda\nuntuk mulai mengelola kamar dan '
                          'reservasi.',
                          textAlign: TextAlign.center))
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: _daftar.length,
                        itemBuilder: (context, i) {
                          final p = _daftar[i];
                          final aktif = p['aktif'] != false;
                          return Card(
                            child: ListTile(
                              leading: Icon(Icons.apartment_outlined,
                                  color: aktif
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).disabledColor),
                              title: Text('${p['nama'] ?? '-'}'
                                  '${aktif ? '' : '  (nonaktif)'}'),
                              subtitle: Text([
                                if ((p['kode'] ?? '').toString().isNotEmpty)
                                  'Kode: ${p['kode']}',
                                if ((p['kota'] ?? '').toString().isNotEmpty)
                                  '${p['kota']}',
                                'Kamar: ${p['jumlah_kamar'] ?? 0}',
                              ].join(' • ')),
                              trailing: const Icon(Icons.edit_outlined),
                              onTap: () => _simpan(p),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _FormPropertiDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  const _FormPropertiDialog({this.awal});

  @override
  State<_FormPropertiDialog> createState() => _FormPropertiDialogState();
}

class _FormPropertiDialogState extends State<_FormPropertiDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _alamat;
  late final TextEditingController _kota;
  late final TextEditingController _telp;
  late final TextEditingController _email;
  late final TextEditingController _keterangan;
  late final TextEditingController _jumlahLantai;
  late bool _aktif;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _kode = TextEditingController(text: '${a?['kode'] ?? ''}');
    _nama = TextEditingController(text: '${a?['nama'] ?? ''}');
    _alamat = TextEditingController(text: '${a?['alamat'] ?? ''}');
    _kota = TextEditingController(text: '${a?['kota'] ?? ''}');
    _telp = TextEditingController(text: '${a?['telp'] ?? ''}');
    _email = TextEditingController(text: '${a?['email'] ?? ''}');
    _keterangan = TextEditingController(text: '${a?['keterangan'] ?? ''}');
    _jumlahLantai =
        TextEditingController(text: '${a?['jumlah_lantai'] ?? ''}');
    _aktif = a?['aktif'] != false;
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _alamat.dispose();
    _kota.dispose();
    _telp.dispose();
    _email.dispose();
    _keterangan.dispose();
    _jumlahLantai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.awal == null ? 'Tambah Properti' : 'Ubah Properti'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(labelText: 'Nama properti *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              TextFormField(
                controller: _kode,
                decoration: const InputDecoration(
                    labelText: 'Kode', hintText: 'mis. MI-001 (opsional)'),
              ),
              TextFormField(
                controller: _alamat,
                decoration: const InputDecoration(labelText: 'Alamat'),
              ),
              TextFormField(
                controller: _kota,
                decoration: const InputDecoration(labelText: 'Kota'),
              ),
              TextFormField(
                controller: _telp,
                decoration: const InputDecoration(labelText: 'Telepon'),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextFormField(
                controller: _jumlahLantai,
                decoration:
                    const InputDecoration(labelText: 'Jumlah lantai'),
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
              'kode': _kode.text.trim(),
              'nama': _nama.text.trim(),
              'alamat': _alamat.text.trim(),
              'kota': _kota.text.trim(),
              'telp': _telp.text.trim(),
              'email': _email.text.trim(),
              'keterangan': _keterangan.text.trim(),
              'jumlah_lantai': int.tryParse(_jumlahLantai.text.trim()),
              'aktif': _aktif,
            });
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
