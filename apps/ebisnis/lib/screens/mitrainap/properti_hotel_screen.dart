import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../sesi.dart';
import '../../widgets/app_components.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/indikator_sinkron_master.dart';
import '../../widgets/kilau_perubahan.dart';
import 'mitrainap_common.dart';
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
    await showDialog<void>(
      context: context,
      builder: (_) => _FormPropertiDialog(
        awal: awal,
        onSubmit: (hasil) async {
          try {
            final res = await prosesSimpanMaster(
              context,
              aksi: 'hotel_properti_simpan',
              body: hasil,
              kunci: hasil['id'] != null
                  ? 'hotel_properti:${hasil['id']}'
                  : 'hotel_properti:baru:${DateTime.now().microsecondsSinceEpoch}',
            );
            if (!mounted) return false;
            if (res['offline'] != true) _muat();
            return true;
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Gagal menyimpan: $e'),
                  backgroundColor: Theme.of(context).colorScheme.error));
            }
            return false;
          }
        },
      ),
    );
  }

  /// Generator data contoh (ADMIN saja, aksi hotel_data_contoh -- dijaga ulang
  /// server dgn Common.getApakahAdminLain). Membuat SATU properti contoh baru
  /// lengkap: 3 tipe kamar, 9 kamar, 3 tamu, 2 reservasi, 2 kontrak pemilik.
  /// Butuh koneksi (bukan mutasi master biasa -- tidak diantre offline).
  Future<void> _buatDataContoh() async {
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Buat data contoh?'),
        content: const Text(
            'Akan dibuat SATU properti contoh baru berisi 3 tipe kamar, '
            '9 kamar, 3 tamu, 2 reservasi, dan 2 kontrak pemilik.\n\n'
            'Data properti yang sudah ada tidak diubah. Hapus atau nonaktifkan '
            'properti contoh bila tidak diperlukan lagi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Buat')),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;
    setStateIfMounted(() => _memuat = true);
    try {
      final res = await ApiClient.instance.aksi('hotel_data_contoh', {});
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${res['description'] ?? (sukses ? 'Data contoh dibuat.' : res['status'])}'),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error,
      ));
      if (sukses) {
        await _muat();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal membuat data contoh: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
    if (mounted) setStateIfMounted(() => _memuat = false);
  }

  @override
  Widget build(BuildContext context) {
    final admin = Sesi.instance.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Properti Hotel'),
        actions: [
          const IndikatorSinkronMaster(),
          if (admin)
            IconButton(
                onPressed: _memuat ? null : _buatDataContoh,
                tooltip: 'Buat data contoh (admin)',
                icon: const Icon(Icons.auto_awesome_outlined)),
          IconButton(
              onPressed: _muat,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Tombol data contoh menonjol saat daftar masih kosong -- admin baru
          // biasanya ingin melihat bentuk datanya dulu sebelum entri manual.
          if (admin && _daftar.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.extended(
                heroTag: 'fab-contoh-hotel',
                onPressed: _memuat ? null : _buatDataContoh,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Isi Data Contoh'),
              ),
            ),
          if (bolehHotel('hotel_properti', 'create'))
            FloatingActionButton.extended(
              heroTag: 'fab-tambah-properti',
              onPressed: () => _simpan(null),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Properti'),
            ),
        ],
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
  final Future<bool> Function(Map<String, dynamic>) onSubmit;
  const _FormPropertiDialog({this.awal, required this.onSubmit});

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

  Future<bool> _simpan() async {
    if (!_formKey.currentState!.validate()) return false;
    return widget.onSubmit(<String, dynamic>{
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
      actions: [AppCrudDialogActions(onSubmit: _simpan)],
    );
  }
}
