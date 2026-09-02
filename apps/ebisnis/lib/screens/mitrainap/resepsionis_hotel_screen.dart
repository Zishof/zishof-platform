import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../widgets/app_components.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Resepsionis (front desk) -- tamu in-house per properti: walk-in check-in,
/// folio (bayar/penyesuaian), pindah kamar, dan check-out (aksi
/// hotel_menginap_list, hotel_checkin, hotel_folio_get,
/// hotel_folio_transaksi_tambah, hotel_pindah_kamar, hotel_checkout).
/// Server yang menegakkan aturan uang: checkout ditolak (status 91) selama
/// saldo folio masih positif -- layar ini menampilkan sisanya, tidak
/// mencoba pintar sendiri.
class ResepsionisHotelScreen extends StatefulWidget {
  const ResepsionisHotelScreen({super.key});

  @override
  State<ResepsionisHotelScreen> createState() => _ResepsionisHotelScreenState();
}

class _ResepsionisHotelScreenState extends State<ResepsionisHotelScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _properti = [];
  int? _propertiId;
  List<Map<String, dynamic>> _daftar = [];
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (check-in/out dari shift lain).
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
      final id =
          _propertiId ?? (data.isNotEmpty ? idInt(data.first['id']) : null);
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
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris (tamu yang
      // baru di-check-in shift lain langsung berpendar). Cache dipisah per
      // PROPERTI. Jalur CHECK-IN/CHECK-OUT/FOLIO/PINDAH KAMAR TETAP online-only
      // lewat ApiClient -- server penjaga aturan uang & alokasi kamar.
      await MasterOffline.daftarCacheDulu(
          'hotel_menginap_list',
          {'properti_id': pid, 'status': 'IN_HOUSE'},
          'master:hotel_menginap:$pid', onData: (hasil) {
        if (!mounted) return;
        if (hasil['data'] is! List) {
          // Penolakan bisnis server (kontrak status PosApi) -- tampilkan
          // pesannya spt perilaku muatDaftarHotel sebelumnya.
          setStateIfMounted(() {
            _galat =
                '${hasil['description'] ?? 'Gagal memuat data (hotel_menginap_list).'}';
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

  Future<List<Map<String, dynamic>>> _kamarVacant() async {
    final kamar =
        await muatDaftarHotel('hotel_kamar_list', {'properti_id': _propertiId});
    return kamar
        .where((k) =>
            k['aktif'] != false &&
            '${k['status_hunian'] ?? 'VACANT'}' == 'VACANT')
        .toList();
  }

  /// Walk-in: tamu datang tanpa reservasi -- pilih/daftarkan tamu, pilih
  /// kamar VACANT, harga per malam opsional (kosong = harga dasar tipe).
  Future<void> _walkIn() async {
    final pid = _propertiId;
    if (pid == null) return;
    List<Map<String, dynamic>> tamu;
    List<Map<String, dynamic>> kosong;
    try {
      tamu = await muatDaftarHotel('hotel_tamu_list', {'properti_id': pid});
      kosong = await _kamarVacant();
    } catch (e) {
      _info('Gagal memuat data pendukung: $e', galat: true);
      return;
    }
    if (kosong.isEmpty) {
      _info('Tidak ada kamar VACANT.', galat: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _FormWalkInDialog(
        propertiId: pid,
        daftarTamu: tamu,
        daftarKamar: kosong,
        onSubmit: (hasil) async {
          // ONLINE-ONLY -- ATURAN KAMAR: penempatan kamar adalah perebutan
          // sumber daya fisik yang hanya boleh dipegang satu tamu.
          final res = await ApiClient.instance.aksi('hotel_checkin', hasil);
          if (!apiSukses(res)) {
            throw Exception(apiPesan(res, res['status'].toString()));
          }
          _info('Check-in walk-in berhasil. Folio dibuka.');
          await _muat();
          return true;
        },
      ),
    );
  }

  Future<void> _lihatFolio(Map<String, dynamic> stay) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FolioDialog(menginapId: idInt(stay['id'])!),
    );
    _muat();
  }

  Future<void> _pindahKamar(Map<String, dynamic> stay) async {
    List<Map<String, dynamic>> kosong;
    try {
      kosong = await _kamarVacant();
    } catch (e) {
      _info('Gagal memuat kamar: $e', galat: true);
      return;
    }
    if (kosong.isEmpty) {
      _info('Tidak ada kamar VACANT.', galat: true);
      return;
    }
    if (!mounted) return;
    int? kamarId = idInt(kosong.first['id']);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Pindah kamar — ${stay['tamu_nama'] ?? ''}'),
        content: StatefulBuilder(
          builder: (c2, setD) => DropdownButtonFormField<int>(
            value: kamarId,
            decoration:
                const InputDecoration(labelText: 'Kamar tujuan (VACANT)'),
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
          AppCrudDialogActions(
            submitLabel: 'Pindahkan',
            onSubmit: () async {
              if (kamarId == null) {
                throw Exception('Pilih kamar tujuan.');
              }
              final res = await ApiClient.instance.aksi('hotel_pindah_kamar', {
                'menginap_id': stay['id'],
                'kamar_baru_id': kamarId,
              });
              if (!apiSukses(res)) {
                throw Exception(apiPesan(res, res['status'].toString()));
              }
              _info('Kamar dipindahkan.');
              await _muat();
              return true;
            },
          )
        ],
      ),
    );
  }

  Future<void> _checkout(Map<String, dynamic> stay) async {
    final bayar = TextEditingController();
    final metode = TextEditingController(text: 'TUNAI');
    final saldo = angka(stay['saldo_folio']);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Check-out — ${stay['tamu_nama'] ?? ''}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Saldo folio saat ini: ${formatRupiahHotel.format(saldo)}\n'
              'Room charge malam berjalan dihitung server saat check-out.'),
          TextField(
            controller: bayar,
            decoration: const InputDecoration(
                labelText: 'Bayar sekarang (Rp)',
                hintText: 'Kosongkan bila sudah lunas'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: metode,
            decoration: const InputDecoration(labelText: 'Metode bayar'),
          ),
        ]),
        actions: [
          AppCrudDialogActions(
            submitLabel: 'Check-out',
            onSubmit: () async {
              final body = <String, dynamic>{'menginap_id': stay['id']};
              final jumlah = double.tryParse(
                  bayar.text.trim().replaceAll('.', '').replaceAll(',', '.'));
              if (jumlah != null && jumlah > 0) {
                body['bayar_sekarang'] = jumlah;
                body['metode_bayar'] = metode.text.trim();
              }
              final res = await ApiClient.instance.aksi('hotel_checkout', body);
              if ('${res['status']}' == '91') {
                throw Exception('Folio masih bersaldo '
                    '${formatRupiahHotel.format(angka(res['saldo']))}. '
                    'Lunasi lewat tombol Folio dulu.');
              }
              if (!apiSukses(res)) {
                throw Exception(apiPesan(res, res['status'].toString()));
              }
              _info('Check-out selesai. ${res['malam'] ?? ''} malam, '
                  'room charge '
                  '${formatRupiahHotel.format(angka(res['room_charge']))}.');
              await _muat();
              return true;
            },
          )
        ],
      ),
    );
    bayar.dispose();
    metode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in / Check-out'),
        actions: [
          IconButton(
              onPressed: _muatProperti,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _propertiId == null ||
              !bolehHotel('hotel_checkin', 'create')
          ? null
          : FloatingActionButton.extended(
              onPressed: _walkIn,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Check-in Walk-in'),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: PilihPropertiHotel(
            daftar: _properti,
            nilai: _propertiId,
            onUbah: (v) {
              setState(() => _propertiId = v);
              _muat();
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
                          ? const Center(
                              child: Text('Tidak ada tamu in-house. Gunakan '
                                  'Check-in Walk-in atau menu Reservasi.'))
                          : RefreshIndicator(
                              onRefresh: _muat,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 4, 12, 88),
                                itemCount: _daftar.length + 1,
                                itemBuilder: (context, i) {
                                  if (i == 0) {
                                    return BannerPerubahanServer(
                                      key: ValueKey('perubahan:${_diff.versi}'),
                                      baru: _diff.idBaru.length,
                                      berubah: _diff.idBerubah.length,
                                      dihapus: _diff.jumlahHapus,
                                    );
                                  }
                                  final s = _daftar[i - 1];
                                  final saldo = angka(s['saldo_folio']);
                                  final kartu = Card(
                                    child: ListTile(
                                      leading: const Icon(Icons.hotel_outlined,
                                          color: Colors.green),
                                      title: Text('${s['tamu_nama'] ?? '-'} — '
                                          'Kamar ${s['kamar_nomor'] ?? '-'}'),
                                      subtitle: Text([
                                        'Masuk: ${s['checkin_pada'] ?? '-'}',
                                        'Saldo: '
                                            '${formatRupiahHotel.format(saldo)}',
                                      ].join(' • ')),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (v) {
                                          switch (v) {
                                            case 'folio':
                                              _lihatFolio(s);
                                              break;
                                            case 'pindah':
                                              _pindahKamar(s);
                                              break;
                                            default:
                                              _checkout(s);
                                          }
                                        },
                                        // Tiga kunci menu berbeda dalam satu
                                        // menu: folio punya kunci sendiri,
                                        // sedangkan pindah kamar dan check-out
                                        // menutup/menggeser PENEMPATAN yang sama
                                        // dengan check-in.
                                        itemBuilder: (_) => [
                                          if (bolehHotel('hotel_folio', 'create'))
                                            const PopupMenuItem(
                                                value: 'folio',
                                                child: Text(
                                                    'Folio / Pembayaran')),
                                          if (bolehHotel(
                                              'hotel_checkin', 'update')) ...[
                                            const PopupMenuItem(
                                                value: 'pindah',
                                                child: Text('Pindah Kamar')),
                                            const PopupMenuItem(
                                                value: 'checkout',
                                                child: Text('Check-out')),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                  // Kilau: tamu yang baru di-check-in / berubah
                                  // saldo folionya di server berpendar sesaat.
                                  return KilauBaris(
                                    kunci: '${s['id'] ?? s['_kunci'] ?? ''}',
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

class _FormWalkInDialog extends StatefulWidget {
  final int propertiId;
  final List<Map<String, dynamic>> daftarTamu;
  final List<Map<String, dynamic>> daftarKamar;
  final Future<bool> Function(Map<String, dynamic> data) onSubmit;
  const _FormWalkInDialog({
    required this.propertiId,
    required this.daftarTamu,
    required this.daftarKamar,
    required this.onSubmit,
  });

  @override
  State<_FormWalkInDialog> createState() => _FormWalkInDialogState();
}

class _FormWalkInDialogState extends State<_FormWalkInDialog> {
  final _formKey = GlobalKey<FormState>();
  late List<Map<String, dynamic>> _tamu;
  int? _tamuId;
  int? _kamarId;
  final _harga = TextEditingController();
  final _catatan = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tamu = List.of(widget.daftarTamu);
    _tamuId = _tamu.isNotEmpty ? idInt(_tamu.first['id']) : null;
    _kamarId = idInt(widget.daftarKamar.first['id']);
  }

  @override
  void dispose() {
    _harga.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _tamuBaru() async {
    final nama = TextEditingController();
    final noIdentitas = TextEditingController();
    final telp = TextEditingController();
    await showDialog<void>(
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
          AppCrudDialogActions(onSubmit: () async {
            if (nama.text.trim().isEmpty) {
              throw Exception('Nama tamu wajib diisi.');
            }
            final res = await ApiClient.instance.aksi('hotel_tamu_simpan', {
              'properti_id': widget.propertiId,
              'nama': nama.text.trim(),
              'jenis_identitas': 'KTP',
              'no_identitas': noIdentitas.text.trim(),
              'telp': telp.text.trim(),
            });
            if (!apiSukses(res)) {
              throw Exception(apiPesan(res, 'Gagal menyimpan tamu.'));
            }
            final ulang = await muatDaftarHotel(
                'hotel_tamu_list', {'properti_id': widget.propertiId});
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
            return true;
          })
        ],
      ),
    );
    nama.dispose();
    noIdentitas.dispose();
    telp.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Check-in Walk-in'),
      content: SizedBox(
        width: 440,
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
                value: _kamarId,
                decoration:
                    const InputDecoration(labelText: 'Kamar (VACANT) *'),
                items: widget.daftarKamar
                    .map((k) => DropdownMenuItem<int>(
                          value: idInt(k['id']),
                          child: Text('Kamar ${k['nomor']}'
                              ' — ${k['tipe_kamar_nama'] ?? '-'}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _kamarId = v),
                validator: (v) => v == null ? 'Pilih kamar' : null,
              ),
              TextFormField(
                controller: _harga,
                decoration: const InputDecoration(
                    labelText: 'Harga per malam (Rp)',
                    hintText: 'Kosongkan = harga dasar tipe kamar'),
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
        AppCrudDialogActions(
          submitLabel: 'Check-in',
          onSubmit: () async {
            if (!_formKey.currentState!.validate()) return false;
            final harga = double.tryParse(
                _harga.text.trim().replaceAll('.', '').replaceAll(',', '.'));
            return widget.onSubmit(<String, dynamic>{
              'kamar_id': _kamarId,
              'tamu_id': _tamuId,
              if (harga != null) 'harga_per_malam': harga,
              'catatan': _catatan.text.trim(),
            });
          },
        )
      ],
    );
  }
}

/// Rincian folio satu stay: daftar transaksi + tombol Bayar / Penyesuaian.
/// Baris folio append-only di server; dialog ini tidak pernah mengedit atau
/// menghapus baris, hanya menambah PAYMENT/ADJUSTMENT.
class _FolioDialog extends StatefulWidget {
  final int menginapId;
  const _FolioDialog({required this.menginapId});

  @override
  State<_FolioDialog> createState() => _FolioDialogState();
}

class _FolioDialogState extends State<_FolioDialog> {
  bool _memuat = true;
  String? _galat;
  Map<String, dynamic>? _folio;

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
      final res = await ApiClient.instance
          .aksi('hotel_folio_get', {'menginap_id': widget.menginapId});
      if (!apiSukses(res)) {
        throw Exception(apiPesan(res, 'Gagal memuat folio.'));
      }
      setStateIfMounted(() {
        _folio = res;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _tambah(String jenis) async {
    final folioId = idInt(_folio?['folio_id']);
    if (folioId == null) return;
    final jumlah = TextEditingController();
    final keterangan = TextEditingController(
        text: jenis == 'PAYMENT' ? 'Pembayaran tunai' : '');
    bool mengurangi = false;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
            jenis == 'PAYMENT' ? 'Terima Pembayaran' : 'Penyesuaian Tagihan'),
        content: StatefulBuilder(
          builder: (c2, setD) =>
              Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: jumlah,
              decoration: const InputDecoration(labelText: 'Jumlah (Rp) *'),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            TextField(
              controller: keterangan,
              decoration: const InputDecoration(labelText: 'Keterangan'),
            ),
            if (jenis == 'ADJUSTMENT')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mengurangi tagihan (diskon/koreksi)'),
                value: mengurangi,
                onChanged: (v) => setD(() => mengurangi = v ?? false),
              ),
          ]),
        ),
        actions: [
          AppCrudDialogActions(onSubmit: () async {
            final nilai = double.tryParse(
                jumlah.text.trim().replaceAll('.', '').replaceAll(',', '.'));
            if (nilai == null || nilai <= 0) {
              throw Exception('Jumlah harus angka lebih dari 0.');
            }
            final res = await MasterOffline.simpanAtauAntre(
                'hotel_folio_transaksi_tambah',
                {
                  'folio_id': folioId,
                  'jenis': jenis,
                  'jumlah': nilai,
                  'keterangan': keterangan.text.trim(),
                  if (jenis == 'ADJUSTMENT') 'mengurangi': mengurangi,
                },
                kunci: 'folio_transaksi:$folioId:'
                    '${DateTime.now().microsecondsSinceEpoch}');
            if (res['offline'] != true && !apiSukses(res)) {
              throw Exception(apiPesan(res, 'Gagal menyimpan transaksi.'));
            }
            await _muat();
            return true;
          })
        ],
      ),
    );
    jumlah.dispose();
    keterangan.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transaksi = (_folio?['transaksi'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final saldo = angka(_folio?['saldo']);
    final terbuka = '${_folio?['status_folio'] ?? 'OPEN'}' == 'OPEN';
    return AlertDialog(
      title: Text('Folio Tamu'
          '${_folio == null ? '' : ' #${_folio!['folio_id']}'}'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(child: Text(_galat!, textAlign: TextAlign.center))
                : Column(children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Saldo: ${formatRupiahHotel.format(saldo)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: saldo > 0
                                  ? Theme.of(context).colorScheme.error
                                  : Colors.green)),
                      subtitle: Text(terbuka
                          ? 'Folio OPEN — beban positif, pembayaran negatif'
                          : 'Folio CLOSED'),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: transaksi.isEmpty
                          ? const Center(
                              child: Text('Belum ada transaksi folio.'))
                          : ListView.builder(
                              itemCount: transaksi.length,
                              itemBuilder: (context, i) {
                                final t = transaksi[i];
                                final jumlah = angka(t['jumlah']);
                                return ListTile(
                                  dense: true,
                                  title: Text('${t['jenis'] ?? '-'}'
                                      '${(t['keterangan'] ?? '').toString().isEmpty ? '' : ' — ${t['keterangan']}'}'),
                                  subtitle: Text('${t['waktu'] ?? ''}'),
                                  trailing: Text(
                                    NumberFormat.currency(
                                            locale: 'id_ID',
                                            symbol: '',
                                            decimalDigits: 0)
                                        .format(jumlah),
                                    style: TextStyle(
                                        color:
                                            jumlah < 0 ? Colors.green : null),
                                  ),
                                );
                              },
                            ),
                    ),
                  ]),
      ),
      actions: [
        if (terbuka &&
            !_memuat &&
            _galat == null &&
            bolehHotel('hotel_folio', 'create')) ...[
          TextButton.icon(
            onPressed: () => _tambah('ADJUSTMENT'),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Penyesuaian'),
          ),
          FilledButton.icon(
            onPressed: () => _tambah('PAYMENT'),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Bayar'),
          ),
        ],
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup')),
      ],
    );
  }
}
