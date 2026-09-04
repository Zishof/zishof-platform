import 'package:flutter/material.dart';

import '../../../api_client.dart';
import '../../../services/master_offline.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_lokal_dulu.dart';

typedef PanggilPasien = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

class ApotikPasienPage extends StatefulWidget {
  final PanggilPasien? panggil;
  final MuatDaftarApotik? muatDaftar;

  const ApotikPasienPage({super.key, this.panggil, this.muatDaftar});

  @override
  State<ApotikPasienPage> createState() => _ApotikPasienPageState();
}

class _ApotikPasienPageState extends State<ApotikPasienPage> {
  late final PanggilPasien _panggil = widget.panggil ?? ApiClient.instance.aksi;
  late final MuatDaftarApotik _muatDaftar =
      widget.muatDaftar ?? MasterOffline.daftarCacheDulu;
  final _cari = TextEditingController();
  List<Map<String, dynamic>> _daftar = [];
  Map<String, dynamic>? _terpilih;
  bool _memuat = false;
  bool _memuatDetail = false;
  String? _galat;
  String? _galatDetail;

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

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == 'success' || r['status'] == '00';

  List<Map<String, dynamic>> _rows(Object? value) =>
      ((value as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> _saring(
      List<Map<String, dynamic>> data, String keyword) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return data;
    return data.where((e) {
      for (final kolom in const ['nama', 'kode', 'noHp', 'noTelp']) {
        if ('${e[kolom] ?? ''}'.toLowerCase().contains(k)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _muat() async {
    final keyword = _cari.text.trim();
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await _muatDaftar(
        'apotik_pasien_cari',
        {'keyword': keyword, 'page_size': 100},
        kunciCachePasienApotik,
        onData: (r) {
          if (!mounted) return;
          var data = _rows(r['data']);
          if (r['dariServer'] != true) data = _saring(data, keyword);
          setStateIfMounted(() {
            _daftar = data;
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        if (_daftar.isEmpty) _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _pilih(Map<String, dynamic> pasien) async {
    setStateIfMounted(() {
      _terpilih = pasien;
      _memuatDetail = true;
      _galatDetail = null;
    });
    try {
      final r = await _panggil('apotik_pasien_detail', {'id': pasien['id']});
      if (!_sukses(r)) throw Exception(r['description'] ?? r['message']);
      setStateIfMounted(() {
        _terpilih = r['data'] is Map
            ? Map<String, dynamic>.from(r['data'] as Map)
            : pasien;
        _memuatDetail = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galatDetail = '$e';
        _memuatDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final desktop = c.maxWidth >= 900;
      final daftar = _panelDaftar();
      final detail = _panelDetail();
      if (desktop) {
        return Row(children: [
          SizedBox(width: 390, child: daftar),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ]);
      }
      return Column(children: [
        SizedBox(height: 330, child: daftar),
        const Divider(height: 1),
        Expanded(child: detail),
      ]);
    });
  }

  Widget _panelDaftar() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _cari,
          onSubmitted: (_) => _muat(),
          decoration: InputDecoration(
            hintText: 'Cari nama, RM, atau telepon pasien',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Cari',
              onPressed: _muat,
              icon: const Icon(Icons.arrow_forward),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('${_daftar.length} pasien',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_memuat)
            const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
      const SizedBox(height: 8),
      if (_galat != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_galat!, style: const TextStyle(color: Colors.red)),
        )
      else
        Expanded(
          child: ListView.separated(
            itemCount: _daftar.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = _daftar[i];
              final aktif = _terpilih?['id'] == p['id'];
              return ListTile(
                selected: aktif,
                leading: CircleAvatar(
                  child: Text(_inisial('${p['nama'] ?? ''}')),
                ),
                title: Text('${p['nama'] ?? '-'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${p['kode'] ?? '-'} • ${p['jenisKelamin'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pilih(p),
              );
            },
          ),
        ),
    ]);
  }

  String _inisial(String nama) {
    final parts = nama.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    return parts.take(2).map((e) => e[0].toUpperCase()).join();
  }

  Widget _panelDetail() {
    if (_terpilih == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.personal_injury_outlined, size: 58, color: Colors.grey),
          SizedBox(height: 12),
          Text('Pilih pasien untuk melihat profil klinis'),
        ]),
      );
    }
    if (_memuatDetail) return const Center(child: CircularProgressIndicator());
    if (_galatDetail != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_galatDetail!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _pilih(_terpilih!),
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ]),
      );
    }
    final p = _terpilih!;
    final alergi = _rows(p['alergi']);
    final diagnosa = _rows(p['diagnosa']);
    final alergiAktif = alergi
        .where((e) => '${e['statusKlinis']}'.toUpperCase() == 'AKTIF')
        .length;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 30,
            child: Text(_inisial('${p['nama'] ?? ''}'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['nama'] ?? '-'}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${p['kode'] ?? '-'} • ${p['jenisKelamin'] ?? '-'} • '
                  '${p['tanggalLahir'] ?? '-'}'),
              if ('${p['noHp'] ?? ''}'.isNotEmpty) Text('${p['noHp']}'),
            ]),
          ),
          Chip(
            avatar: Icon(
              alergiAktif > 0
                  ? Icons.warning_amber_rounded
                  : Icons.verified_user,
              size: 18,
              color: alergiAktif > 0 ? Colors.red : Colors.green,
            ),
            label: Text('$alergiAktif alergi aktif'),
          ),
        ]),
        const SizedBox(height: 22),
        _judul('Alergi & sensitivitas', Icons.warning_amber_rounded),
        const SizedBox(height: 8),
        if (alergi.isEmpty)
          _kosong(
              'Belum ada alergi yang tercatat. Konfirmasi tetap wajib dilakukan.')
        else
          ...alergi.map((a) => Card(
                child: ListTile(
                  leading: Icon(Icons.shield_outlined,
                      color: '${a['statusKlinis']}'.toUpperCase() == 'AKTIF'
                          ? Colors.red
                          : Colors.grey),
                  title: Text('${a['substansi'] ?? '-'}'),
                  subtitle: Text('${a['reaksi'] ?? '-'} • '
                      '${a['keparahan'] ?? '-'} • ${a['tanggalCatat'] ?? '-'}'),
                  trailing: Chip(label: Text('${a['statusKlinis'] ?? '-'}')),
                ),
              )),
        const SizedBox(height: 20),
        _judul('Riwayat klinis', Icons.history_edu_outlined),
        const SizedBox(height: 8),
        if (diagnosa.isEmpty)
          _kosong('Belum ada riwayat diagnosis yang dapat ditampilkan.')
        else
          ...diagnosa.map((d) => Card(
                child: ListTile(
                  leading: const Icon(Icons.medical_information_outlined),
                  title: Text('${d['kesimpulan'] ?? d['keluhan'] ?? '-'}'),
                  subtitle:
                      Text('${d['kode'] ?? '-'} • ${d['tanggal'] ?? '-'}'),
                ),
              )),
      ],
    );
  }

  Widget _judul(String teks, IconData ikon) => Row(children: [
        Icon(ikon, size: 20),
        const SizedBox(width: 8),
        Text(teks,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ]);

  Widget _kosong(String teks) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(teks),
      );
}
