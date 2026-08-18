import 'package:flutter/material.dart';

import '../../services/master_offline.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/indikator_sinkron_master.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/safe_state.dart';

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
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan pengelola lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

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
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('hotel_properti_list',
          {'termasuk_nonaktif': true}, 'master:hotel_properti',
          onData: (hasil) {
        if (!mounted) return;
        if (hasil['data'] is! List) {
          // Penolakan bisnis server (kontrak status PosApi) -- tampilkan
          // pesannya spt perilaku muatDaftarHotel sebelumnya.
          setStateIfMounted(() {
            _galat =
                '${hasil['description'] ?? 'Gagal memuat data (hotel_properti_list).'}';
            _memuat = false;
          });
          return;
        }
        final data = ((hasil['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _daftar = data;
          _idBaru = dariServer
              ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(
                  hasil['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus =
              dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
          if (dariServer &&
              (_idBaru.isNotEmpty ||
                  _idBerubah.isNotEmpty ||
                  _jumlahHapus > 0)) {
            _versiPerubahan++;
          }
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _simpan(Map<String, dynamic>? awal) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormPropertiDialog(awal: awal),
    );
    if (hasil == null || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      // Saat offline daftar TIDAK dimuat ulang (snapshot cache belum memuat
      // mutasi yang masih antre, jadi memuat ulang hanya menampilkan data lama).
      final res = await prosesSimpanMaster(
        context,
        aksi: 'hotel_properti_simpan',
        body: hasil,
        kunci: hasil['id'] != null
            ? 'hotel_properti:${hasil['id']}'
            : 'hotel_properti:baru:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      if (res['offline'] != true) _muat();
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
                        itemCount: _daftar.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return BannerPerubahanServer(
                              key: ValueKey('perubahan:$_versiPerubahan'),
                              baru: _idBaru.length,
                              berubah: _idBerubah.length,
                              dihapus: _jumlahHapus,
                            );
                          }
                          final p = _daftar[i - 1];
                          final aktif = p['aktif'] != false;
                          return KilauBaris(
                            kunci: '${p['id'] ?? p['_kunci'] ?? ''}',
                            idBaru: _idBaru,
                            idBerubah: _idBerubah,
                            child: Card(
                              child: ListTile(
                                leading: Icon(Icons.apartment_outlined,
                                    color: aktif
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).disabledColor),
                                title: Row(children: [
                                  Expanded(
                                      child: Text('${p['nama'] ?? '-'}'
                                          '${aktif ? '' : '  (nonaktif)'}')),
                                  IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip:
                                          'Riwayat data ini (AuditTrails)',
                                      icon: const Icon(Icons.history,
                                          size: 16),
                                      onPressed: () => tampilkanRiwayatData(
                                          context,
                                          entitas: 'hotel_properti',
                                          id: p['id'],
                                          judul: '${p['nama'] ?? ''}')),
                                ]),
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
