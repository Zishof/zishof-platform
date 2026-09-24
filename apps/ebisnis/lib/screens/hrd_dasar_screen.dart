import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

/// Layar HRD dasar memakai tabel yang sama dengan modul ZK: Pegawai,
/// CutiDanIzin, dan StatuskehadiranKaryawanHarian.
class HrdDasarScreen extends StatefulWidget {
  const HrdDasarScreen({super.key});

  @override
  State<HrdDasarScreen> createState() => _HrdDasarScreenState();
}

class _HrdDasarScreenState extends State<HrdDasarScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.hrdDasar,
      judul: 'SDM / HRD',
      subjudul: 'Pegawai, cuti/izin, dan riwayat kehadiran',
      scrollable: false,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.badge_outlined),
                  label: Text('Pegawai')),
              ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.event_available_outlined),
                  label: Text('Cuti & Izin')),
              ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.access_time_outlined),
                  label: Text('Kehadiran')),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
        ),
        Expanded(
            child: IndexedStack(index: _tab, children: const [
          _PegawaiTab(),
          _CutiTab(),
          _KehadiranTab(),
        ])),
      ]),
    );
  }
}

class _PegawaiTab extends StatefulWidget {
  const _PegawaiTab();
  @override
  State<_PegawaiTab> createState() => _PegawaiTabState();
}

class _PegawaiTabState extends State<_PegawaiTab> {
  final _cari = TextEditingController();
  bool _memuat = true;
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
      final r = await ApiClient.instance.aksi('hrd_pegawai_daftar',
          {'keyword': _cari.text.trim(), 'page_size': 200});
      setStateIfMounted(() => _data =
          ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PanelDaftar(
        header: TextField(
            controller: _cari,
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Cari kode atau nama pegawai',
                suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh), onPressed: _muat)),
            onSubmitted: (_) => _muat()),
        memuat: _memuat,
        error: _error,
        kosong: 'Belum ada pegawai yang dapat diakses.',
        children: _data
            .map((p) => ListTile(
                  leading: CircleAvatar(
                      child: Text('${p['nama'] ?? '?'}'.trim().isEmpty
                          ? '?'
                          : '${p['nama']}'.trim()[0].toUpperCase())),
                  title: Text('${p['nama'] ?? '-'}'),
                  subtitle: Text(
                      '${p['kode'] ?? '-'} · ${p['jabatan'] ?? '-'} · Masuk ${p['tanggalMasuk'] ?? '-'}'),
                  trailing: Chip(
                      label: Text(p['aktif'] == true ? 'Aktif' : 'Nonaktif')),
                ))
            .toList(),
      );
}

class _CutiTab extends StatefulWidget {
  const _CutiTab();
  @override
  State<_CutiTab> createState() => _CutiTabState();
}

class _CutiTabState extends State<_CutiTab> {
  bool _memuat = true, _bolehKelola = false;
  String? _error;
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
      final r =
          await ApiClient.instance.aksi('hrd_cuti_daftar', {'page_size': 200});
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
        context: context, builder: (_) => const _FormCuti());
    if (ok == true) await _muat();
  }

  Future<void> _putusan(Map<String, dynamic> row, bool setujui) async {
    await ApiClient.instance
        .aksi('hrd_cuti_putusan', {'id': row['id'], 'setujui': setujui});
    await _muat();
  }

  Color _warna(String status) => status == 'DISETUJUI'
      ? Colors.green
      : status == 'DITOLAK'
          ? Colors.red
          : Colors.orange;

  @override
  Widget build(BuildContext context) => _PanelDaftar(
        header: Row(children: [
          Expanded(
              child: Text('Pengajuan cuti dan izin',
                  style: Theme.of(context).textTheme.titleMedium)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: _tambah,
              icon: const Icon(Icons.add),
              label: const Text('Ajukan'))
        ]),
        memuat: _memuat,
        error: _error,
        kosong: 'Belum ada pengajuan cuti atau izin.',
        children: _data.map((r) {
          final status = '${r['status'] ?? 'MENUNGGU'}';
          return Card(
              child: ListTile(
            title:
                Text('${r['pegawai'] ?? '-'} · ${r['jenis'] ?? 'Cuti/Izin'}'),
            subtitle: Text(
                '${r['mulai'] ?? '-'} s.d. ${r['sampai'] ?? '-'}\n${r['keterangan'] ?? ''}'),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Chip(
                  label: Text(status),
                  labelStyle: TextStyle(color: _warna(status))),
              if (_bolehKelola && status == 'MENUNGGU')
                PopupMenuButton<bool>(
                    onSelected: (v) => _putusan(r, v),
                    itemBuilder: (_) => const [
                          PopupMenuItem(value: true, child: Text('Setujui')),
                          PopupMenuItem(value: false, child: Text('Tolak'))
                        ]),
            ]),
          ));
        }).toList(),
      );
}

class _FormCuti extends StatefulWidget {
  const _FormCuti();
  @override
  State<_FormCuti> createState() => _FormCutiState();
}

class _FormCutiState extends State<_FormCuti> {
  DateTime _mulai = DateTime.now(), _sampai = DateTime.now();
  final _ket = TextEditingController();
  List<Map<String, dynamic>> _jenis = [];
  int? _jenisId;
  bool _simpan = false;
  @override
  void initState() {
    super.initState();
    _muatJenis();
  }

  @override
  void dispose() {
    _ket.dispose();
    super.dispose();
  }

  Future<void> _muatJenis() async {
    final r = await ApiClient.instance.aksi('hrd_jenis_cuti_daftar', {});
    setStateIfMounted(() {
      _jenis = ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (_jenis.isNotEmpty) _jenisId = (_jenis.first['id'] as num).toInt();
    });
  }

  Future<DateTime> _pilih(DateTime awal) async =>
      await showDatePicker(
          context: context,
          initialDate: awal,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100)) ??
      awal;
  Future<void> _kirim() async {
    if (_ket.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alasan/keterangan wajib diisi.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      final f = DateFormat('yyyy-MM-dd');
      await ApiClient.instance.aksi('hrd_cuti_simpan', {
        'jenis_id': _jenisId,
        'mulai': f.format(_mulai),
        'sampai': f.format(_sampai),
        'keterangan': _ket.text.trim()
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
        title: const Text('Ajukan Cuti / Izin'),
        content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                  value: _jenisId,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: _jenis
                      .map((j) => DropdownMenuItem(
                          value: (j['id'] as num).toInt(),
                          child: Text('${j['nama']}')))
                      .toList(),
                  onChanged: (v) => setState(() => _jenisId = v)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () async {
                          final nilai = await _pilih(_mulai);
                          setStateIfMounted(() => _mulai = nilai);
                        },
                        child: Text(
                            'Mulai ${DateFormat('dd-MM-yyyy').format(_mulai)}'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton(
                        onPressed: () async {
                          final nilai = await _pilih(_sampai);
                          setStateIfMounted(() => _sampai = nilai);
                        },
                        child: Text(
                            'Sampai ${DateFormat('dd-MM-yyyy').format(_sampai)}')))
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: _ket,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Alasan / keterangan')),
            ])),
        actions: [
          TextButton(
              onPressed: _simpan ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _simpan ? null : _kirim,
              child: Text(_simpan ? 'Menyimpan…' : 'Kirim Pengajuan'))
        ],
      );
}

class _KehadiranTab extends StatefulWidget {
  const _KehadiranTab();
  @override
  State<_KehadiranTab> createState() => _KehadiranTabState();
}

class _KehadiranTabState extends State<_KehadiranTab> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  final DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  final DateTime _sampai = DateTime.now();
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
      final f = DateFormat('yyyy-MM-dd');
      final r = await ApiClient.instance.aksi('hrd_kehadiran_daftar', {
        'dari': f.format(_dari),
        'sampai': f.format(_sampai),
        'page_size': 500
      });
      setStateIfMounted(() => _data =
          ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PanelDaftar(
      header: Row(children: [
        Expanded(
            child: Text('Riwayat 30 hari terakhir',
                style: Theme.of(context).textTheme.titleMedium)),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ]),
      memuat: _memuat,
      error: _error,
      kosong: 'Belum ada data kehadiran pada periode ini.',
      children: _data
          .map((r) => ListTile(
              leading: Icon(
                  r['terlambat'] == true
                      ? Icons.warning_amber
                      : Icons.check_circle_outline,
                  color: r['terlambat'] == true ? Colors.orange : Colors.green),
              title: Text('${r['pegawai'] ?? '-'} · ${r['status'] ?? '-'}'),
              subtitle: Text(
                  '${r['tanggal'] ?? '-'} · Masuk ${_jam(r['masuk'])} · Pulang ${_jam(r['pulang'])}\n${r['keterangan'] ?? ''}'),
              isThreeLine: true))
          .toList());
  String _jam(dynamic v) {
    final s = '${v ?? ''}';
    if (s.isEmpty) return '-';
    return s.length >= 16 ? s.substring(11, 16) : s;
  }
}

class _PanelDaftar extends StatelessWidget {
  const _PanelDaftar(
      {required this.header,
      required this.memuat,
      required this.error,
      required this.kosong,
      required this.children});
  final Widget header;
  final bool memuat;
  final String? error, kosong;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        header,
        const SizedBox(height: 12),
        Expanded(
            child: memuat
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Text(error!,
                            style: const TextStyle(color: Colors.red)))
                    : children.isEmpty
                        ? Center(child: Text(kosong!))
                        : ListView(children: children))
      ]));
}
