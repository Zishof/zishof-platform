import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Tamu & Reservasi -- daftar booking per properti + buat/batalkan/check-in
/// (aksi hotel_reservasi_list/buat/batalkan, hotel_tamu_list/simpan,
/// hotel_checkin). Transisi status divalidasi SERVER; layar ini hanya
/// menawarkan aksi yang masuk akal utk status baris (BOOKED/CONFIRMED).
class ReservasiHotelScreen extends StatefulWidget {
  const ReservasiHotelScreen({super.key});

  @override
  State<ReservasiHotelScreen> createState() => _ReservasiHotelScreenState();
}

class _ReservasiHotelScreenState extends State<ReservasiHotelScreen> {
  static const _semua = 'SEMUA';

  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _properti = [];
  int? _propertiId;
  String _filterStatus = _semua;
  List<Map<String, dynamic>> _daftar = [];
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (reservasi dari resepsionis lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

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
      await _muat();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muat() async {
    final pid = _propertiId;
    if (pid == null) {
      setStateIfMounted(() {
        _daftar = [];
        _memuat = false;
      });
      return;
    }
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final body = <String, dynamic>{'properti_id': pid};
      if (_filterStatus != _semua) body['status'] = _filterStatus;
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Cache dipisah
      // per PROPERTI dan FILTER STATUS. Jalur BUAT/BATALKAN/CHECK-IN tetap
      // online-only lewat ApiClient (butuh alokasi kamar real-time server).
      await MasterOffline.daftarCacheDulu('hotel_reservasi_list', body,
          'master:hotel_reservasi:$pid:$_filterStatus', onData: (hasil) {
        if (!mounted) return;
        if (hasil['data'] is! List) {
          // Penolakan bisnis server (kontrak status PosApi) -- tampilkan
          // pesannya spt perilaku muatDaftarHotel sebelumnya.
          setStateIfMounted(() {
            _galat =
                '${hasil['description'] ?? 'Gagal memuat data (hotel_reservasi_list).'}';
            _memuat = false;
          });
          return;
        }
        setStateIfMounted(() {
          _daftar = _diff.terapkan(hasil);
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  void _info(String pesan, {bool galat = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(pesan),
      backgroundColor: galat ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _buatReservasi() async {
    final pid = _propertiId;
    if (pid == null) return;
    List<Map<String, dynamic>> tamu;
    List<Map<String, dynamic>> tipe;
    try {
      tamu = await muatDaftarHotel('hotel_tamu_list', {'properti_id': pid});
      tipe =
          await muatDaftarHotel('hotel_tipe_kamar_list', {'properti_id': pid});
    } catch (e) {
      _info('Gagal memuat data pendukung: $e', galat: true);
      return;
    }
    if (tipe.isEmpty) {
      _info('Buat Tipe Kamar dulu di menu Kamar & Tipe Kamar.', galat: true);
      return;
    }
    if (!mounted) return;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormReservasiDialog(
          propertiId: pid, daftarTamu: tamu, daftarTipe: tipe),
    );
    if (hasil == null) return;
    try {
      final res = await ApiClient.instance.aksi('hotel_reservasi_buat', hasil);
      if (apiSukses(res)) {
        _info('Reservasi dibuat: ${res['kode'] ?? ''}');
        _muat();
      } else {
        _info('Gagal: ${apiPesan(res, res['status'].toString())}',
            galat: true);
      }
    } catch (e) {
      _info('Gagal membuat reservasi: $e', galat: true);
    }
  }

  Future<void> _batalkan(Map<String, dynamic> r) async {
    final alasan = TextEditingController();
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Batalkan reservasi ${r['kode']}?'),
        content: TextField(
          controller: alasan,
          decoration: const InputDecoration(labelText: 'Alasan (opsional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Ya, batalkan')),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      // LOKAL DULU. Ketersediaan kamar tetap diputuskan server: selama antrean
      // belum terkirim, kamar masih terpesan di sisi server.
      final res = await prosesSimpanMaster(
        context,
        aksi: 'hotel_reservasi_batalkan',
        kunci: 'hotel_reservasi:${r['id']}',
        body: {
          'id': r['id'],
          'alasan': alasan.text.trim(),
        },
      );
      if (apiSukses(res)) {
        _info('Reservasi dibatalkan.');
        _muat();
      } else {
        _info('Gagal: ${apiPesan(res, res['status'].toString())}',
            galat: true);
      }
    } catch (e) {
      _info('Gagal membatalkan: $e', galat: true);
    }
  }

  Future<void> _checkin(Map<String, dynamic> r) async {
    final pid = _propertiId;
    if (pid == null) return;
    List<Map<String, dynamic>> kamar;
    try {
      kamar = await muatDaftarHotel('hotel_kamar_list', {'properti_id': pid});
    } catch (e) {
      _info('Gagal memuat kamar: $e', galat: true);
      return;
    }
    final kosong = kamar
        .where((k) =>
            k['aktif'] != false &&
            '${k['status_hunian'] ?? 'VACANT'}' == 'VACANT')
        .toList();
    if (kosong.isEmpty) {
      _info('Tidak ada kamar VACANT. Selesaikan housekeeping dulu.',
          galat: true);
      return;
    }
    if (!mounted) return;
    // Kamar setipe reservasi ditaruh paling atas, tapi kamar tipe lain tetap
    // boleh dipilih (upgrade/downgrade diputuskan resepsionis).
    final tipeId = idInt(r['tipe_kamar_id']);
    kosong.sort((a, b) {
      final sa = idInt(a['tipe_kamar_id']) == tipeId ? 0 : 1;
      final sb = idInt(b['tipe_kamar_id']) == tipeId ? 0 : 1;
      return sa != sb ? sa - sb : '${a['nomor']}'.compareTo('${b['nomor']}');
    });
    int? kamarId = idInt(kosong.first['id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Check-in ${r['tamu_nama'] ?? ''}'),
        content: StatefulBuilder(
          builder: (c2, setD) => DropdownButtonFormField<int>(
            value: kamarId,
            decoration: const InputDecoration(labelText: 'Kamar (VACANT)'),
            items: kosong
                .map((k) => DropdownMenuItem<int>(
                      value: idInt(k['id']),
                      child: Text('Kamar ${k['nomor']}'
                          ' — ${k['tipe_kamar_nama'] ?? '-'}'),
                    ))
                .toList(),
            onChanged: (v) => setD(() => kamarId = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Check-in')),
        ],
      ),
    );
    if (ok != true || kamarId == null) return;
    try {
      final res = await ApiClient.instance.aksi('hotel_checkin', {
        'kamar_id': kamarId,
        'reservasi_id': r['id'],
      });
      if (apiSukses(res)) {
        _info('Check-in berhasil. Folio dibuka.');
        _muat();
      } else {
        _info('Gagal: ${apiPesan(res, res['status'].toString())}',
            galat: true);
      }
    } catch (e) {
      _info('Gagal check-in: $e', galat: true);
    }
  }

  static Color _warnaStatus(BuildContext context, String status) {
    switch (status) {
      case 'CHECKED_IN':
        return Colors.green;
      case 'CONFIRMED':
        return Colors.blue;
      case 'CANCELLED':
      case 'NO_SHOW':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tamu & Reservasi'),
        actions: [
          IconButton(
              onPressed: _muatProperti,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _propertiId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _buatReservasi,
              icon: const Icon(Icons.add),
              label: const Text('Buat Reservasi'),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: PilihPropertiHotel(
                daftar: _properti,
                nilai: _propertiId,
                onUbah: (v) {
                  setState(() => _propertiId = v);
                  _muat();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _filterStatus,
                decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: const [
                  DropdownMenuItem(value: _semua, child: Text('Semua')),
                  DropdownMenuItem(value: 'BOOKED', child: Text('BOOKED')),
                  DropdownMenuItem(
                      value: 'CONFIRMED', child: Text('CONFIRMED')),
                  DropdownMenuItem(
                      value: 'CHECKED_IN', child: Text('CHECKED_IN')),
                  DropdownMenuItem(
                      value: 'CANCELLED', child: Text('CANCELLED')),
                  DropdownMenuItem(value: 'NO_SHOW', child: Text('NO_SHOW')),
                ],
                onChanged: (v) {
                  setState(() => _filterStatus = v ?? _semua);
                  _muat();
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _galat != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
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
                          child: Text('Belum ada properti. Buat properti dulu '
                              'di menu Properti Hotel.'))
                      : _daftar.isEmpty
                          ? const Center(child: Text('Tidak ada reservasi.'))
                          : RefreshIndicator(
                              onRefresh: _muat,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 4, 12, 88),
                                itemCount: _daftar.length + 1,
                                itemBuilder: (context, i) {
                                  if (i == 0) {
                                    return BannerPerubahanServer(
                                      key: ValueKey(
                                          'perubahan:${_diff.versi}'),
                                      baru: _diff.idBaru.length,
                                      berubah: _diff.idBerubah.length,
                                      dihapus: _diff.jumlahHapus,
                                    );
                                  }
                                  final r = _daftar[i - 1];
                                  final status = '${r['status'] ?? 'BOOKED'}';
                                  final bolehAksi = status == 'BOOKED' ||
                                      status == 'CONFIRMED';
                                  final kartu = Card(
                                    child: ListTile(
                                      title: Text(
                                          '${r['tamu_nama'] ?? '-'} — '
                                          '${r['tipe_kamar_nama'] ?? '-'}'),
                                      subtitle: Text([
                                        '${r['kode'] ?? ''}',
                                        '${r['tanggal_checkin'] ?? ''} s.d. '
                                            '${r['tanggal_checkout'] ?? ''}',
                                        if (r['kamar_nomor'] != null)
                                          'Kamar ${r['kamar_nomor']}',
                                        formatRupiahHotel.format(
                                            angka(r['harga_per_malam'])),
                                      ].join(' • ')),
                                      leading: Icon(Icons.event_outlined,
                                          color:
                                              _warnaStatus(context, status)),
                                      trailing: Wrap(
                                          spacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Chip(
                                              label: Text(status,
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            if (bolehAksi)
                                              PopupMenuButton<String>(
                                                onSelected: (v) {
                                                  if (v == 'checkin') {
                                                    _checkin(r);
                                                  } else {
                                                    _batalkan(r);
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                      value: 'checkin',
                                                      child:
                                                          Text('Check-in')),
                                                  PopupMenuItem(
                                                      value: 'batal',
                                                      child: Text(
                                                          'Batalkan')),
                                                ],
                                              ),
                                          ]),
                                    ),
                                  );
                                  // Kilau: reservasi baru/berubah di server
                                  // (dibuat resepsionis lain) berpendar sesaat.
                                  return KilauBaris(
                                    kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                                    idBaru: _diff.idBaru,
                                    idBerubah: _diff.idBerubah,
                                    child: kartu,
                                  );
                                },
                              ),
                            ),
        ),
      ]),
    );
  }
}

class _FormReservasiDialog extends StatefulWidget {
  final int propertiId;
  final List<Map<String, dynamic>> daftarTamu;
  final List<Map<String, dynamic>> daftarTipe;
  const _FormReservasiDialog({
    required this.propertiId,
    required this.daftarTamu,
    required this.daftarTipe,
  });

  @override
  State<_FormReservasiDialog> createState() => _FormReservasiDialogState();
}

class _FormReservasiDialogState extends State<_FormReservasiDialog> {
  final _formKey = GlobalKey<FormState>();
  late List<Map<String, dynamic>> _tamu;
  int? _tamuId;
  int? _tipeId;
  DateTime _checkin = DateTime.now();
  DateTime _checkout = DateTime.now().add(const Duration(days: 1));
  final _jumlahTamu = TextEditingController(text: '1');
  final _harga = TextEditingController();
  final _catatan = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tamu = List.of(widget.daftarTamu);
    _tamuId = _tamu.isNotEmpty ? idInt(_tamu.first['id']) : null;
    _tipeId = idInt(widget.daftarTipe.first['id']);
  }

  @override
  void dispose() {
    _jumlahTamu.dispose();
    _harga.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _tamuBaru() async {
    final nama = TextEditingController();
    final noIdentitas = TextEditingController();
    final telp = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tamu Baru'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nama,
              decoration: const InputDecoration(labelText: 'Nama *')),
          TextField(
              controller: noIdentitas,
              decoration:
                  const InputDecoration(labelText: 'No. identitas (KTP)')),
          TextField(
              controller: telp,
              decoration: const InputDecoration(labelText: 'Telepon'),
              keyboardType: TextInputType.phone),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || nama.text.trim().isEmpty || !mounted) return;
    try {
      // Master TAMU offline-first lewat prosesSimpanMaster (lokal dulu +
      // dialog animasi kirim). Alur reservasi/check-in tetap online-only
      // (butuh validasi state kamar real-time server), jadi saat offline tamu
      // diantre tapi reservasi TIDAK bisa dilanjutkan dulu.
      final res = await prosesSimpanMaster(context, aksi: 'hotel_tamu_simpan',
          body: {
            'properti_id': widget.propertiId,
            'nama': nama.text.trim(),
            'jenis_identitas': 'KTP',
            'no_identitas': noIdentitas.text.trim(),
            'telp': telp.text.trim(),
          },
          kunci:
              'hotel_tamu:baru:${DateTime.now().microsecondsSinceEpoch}');
      if (res['offline'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Reservasi butuh koneksi — lanjutkan setelah tamu tersinkron.')));
        return;
      }
      if (!apiSukses(res)) {
        throw Exception(apiPesan(res, 'Gagal menyimpan tamu.'));
      }
      final ulang = await muatDaftarHotel(
          'hotel_tamu_list', {'properti_id': widget.propertiId});
      // Pilih otomatis tamu yang baru dibuat: id terbesar dgn nama sama
      // (hotel_tamu_simpan tidak mengembalikan id).
      int? baru;
      for (final t in ulang) {
        if ('${t['nama']}'.toLowerCase() ==
            nama.text.trim().toLowerCase()) {
          final tid = idInt(t['id']);
          if (baru == null || (tid != null && tid > baru)) baru = tid;
        }
      }
      setStateIfMounted(() {
        _tamu = ulang;
        _tamuId = baru ?? _tamuId;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menambah tamu: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  Future<void> _pilihTanggal(bool masuk) async {
    final awal = masuk ? _checkin : _checkout;
    final pilihan = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (pilihan == null) return;
    setState(() {
      if (masuk) {
        _checkin = pilihan;
        if (!_checkout.isAfter(_checkin)) {
          _checkout = _checkin.add(const Duration(days: 1));
        }
      } else {
        _checkout = pilihan;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? tipeTerpilih;
    for (final t in widget.daftarTipe) {
      if (idInt(t['id']) == _tipeId) tipeTerpilih = t;
    }
    return AlertDialog(
      title: const Text('Buat Reservasi'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _tamuId,
                    decoration: const InputDecoration(labelText: 'Tamu *'),
                    items: _tamu
                        .map((t) => DropdownMenuItem<int>(
                              value: idInt(t['id']),
                              child: Text('${t['nama'] ?? t['id']}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _tamuId = v),
                    validator: (v) => v == null ? 'Pilih tamu' : null,
                  ),
                ),
                IconButton(
                  onPressed: _tamuBaru,
                  tooltip: 'Tamu baru',
                  icon: const Icon(Icons.person_add_alt),
                ),
              ]),
              DropdownButtonFormField<int>(
                value: _tipeId,
                decoration:
                    const InputDecoration(labelText: 'Tipe kamar *'),
                items: widget.daftarTipe
                    .map((t) => DropdownMenuItem<int>(
                          value: idInt(t['id']),
                          child: Text('${t['nama']} — '
                              '${formatRupiahHotel.format(angka(t['harga_dasar']))}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _tipeId = v),
                validator: (v) => v == null ? 'Pilih tipe kamar' : null,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pilihTanggal(true),
                    icon: const Icon(Icons.login, size: 18),
                    label:
                        Text('Masuk: ${formatTanggalHotel.format(_checkin)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pilihTanggal(false),
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(
                        'Keluar: ${formatTanggalHotel.format(_checkout)}'),
                  ),
                ),
              ]),
              TextFormField(
                controller: _jumlahTamu,
                decoration:
                    const InputDecoration(labelText: 'Jumlah tamu'),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _harga,
                decoration: InputDecoration(
                  labelText: 'Harga per malam (Rp)',
                  hintText: tipeTerpilih == null
                      ? null
                      : 'Kosongkan = ikut harga dasar '
                          '${formatRupiahHotel.format(angka(tipeTerpilih['harga_dasar']))}',
                ),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _catatan,
                decoration: const InputDecoration(labelText: 'Catatan'),
                maxLines: 2,
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
            if (!_checkout.isAfter(_checkin)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('Tanggal keluar harus setelah tanggal masuk.')));
              return;
            }
            final harga = double.tryParse(_harga.text
                .trim()
                .replaceAll('.', '')
                .replaceAll(',', '.'));
            Navigator.of(context).pop(<String, dynamic>{
              'properti_id': widget.propertiId,
              'tamu_id': _tamuId,
              'tipe_kamar_id': _tipeId,
              'tanggal_checkin': formatTanggalHotel.format(_checkin),
              'tanggal_checkout': formatTanggalHotel.format(_checkout),
              'jumlah_tamu': int.tryParse(_jumlahTamu.text.trim()) ?? 1,
              if (harga != null) 'harga_per_malam': harga,
              'catatan': _catatan.text.trim(),
            });
          },
          child: const Text('Buat'),
        ),
      ],
    );
  }
}
