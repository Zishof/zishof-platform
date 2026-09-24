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
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                  ButtonSegment(
                      value: 3,
                      icon: Icon(Icons.insights_outlined),
                      label: Text('Kedisiplinan')),
                  ButtonSegment(
                      value: 4,
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Payroll')),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              )),
        ),
        Expanded(
            child: IndexedStack(index: _tab, children: const [
          _PegawaiTab(),
          _CutiTab(),
          _KehadiranTab(),
          _KedisiplinanTab(),
          _PayrollTab(),
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
                      '${p['kode'] ?? '-'} · ${p['jabatan'] ?? '-'} · Masuk ${p['tanggalMasuk'] ?? '-'}\n'
                      'Akun: ${('${p['akunUserId'] ?? ''}').isEmpty ? 'belum ditautkan' : p['akunUserId']} · '
                      'Fingerprint: ${p['fingerprintTerdaftar'] == true ? 'terdaftar' : 'belum'}'),
                  isThreeLine: true,
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
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();
  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _pilihPeriode(bool mulai) async {
    final awal = mulai ? _dari : _sampai;
    final nilai = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (nilai == null) return;
    setState(() {
      if (mulai) {
        _dari = nilai;
        if (_sampai.isBefore(_dari)) _sampai = _dari;
      } else {
        _sampai = nilai;
        if (_dari.isAfter(_sampai)) _dari = _sampai;
      }
    });
    await _muat();
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
      header: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
        OutlinedButton.icon(
            onPressed: () => _pilihPeriode(true),
            icon: const Icon(Icons.date_range_outlined),
            label: Text(DateFormat('dd-MM-yyyy').format(_dari))),
        OutlinedButton.icon(
            onPressed: () => _pilihPeriode(false),
            icon: const Icon(Icons.event_available_outlined),
            label: Text(DateFormat('dd-MM-yyyy').format(_sampai))),
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

class _KedisiplinanTab extends StatefulWidget {
  const _KedisiplinanTab();
  @override
  State<_KedisiplinanTab> createState() => _KedisiplinanTabState();
}

class _KedisiplinanTabState extends State<_KedisiplinanTab> {
  bool _memuat = true;
  String? _error;
  Map<String, dynamic> _ringkasan = {};
  List<Map<String, dynamic>> _data = [];
  final DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month, 1);
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
      final r = await ApiClient.instance.aksi('hrd_kehadiran_ringkasan', {
        'dari': f.format(_dari),
        'sampai': f.format(_sampai),
        'page_size': 5000
      });
      final rows =
          ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      rows.sort((a, b) => ((b['tepatWaktu'] as num?) ?? 0)
          .compareTo((a['tepatWaktu'] as num?) ?? 0));
      setStateIfMounted(() {
        _ringkasan = r;
        _data = rows;
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Widget _kpi(String label, dynamic value, Color color) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${value ?? 0}',
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label)
          ])));

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Text(
                  'Kedisiplinan ${DateFormat('dd-MM-yyyy').format(_dari)} s.d. ${DateFormat('dd-MM-yyyy').format(_sampai)}',
                  style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: _muat, icon: const Icon(Icons.refresh))
        ]),
        const SizedBox(height: 12),
        if (!_memuat && _error == null)
          Wrap(spacing: 12, runSpacing: 12, children: [
            _kpi('Catatan presensi', _ringkasan['total'], Colors.blue),
            _kpi('Tepat waktu', _ringkasan['tepatWaktu'], Colors.green),
            _kpi('Terlambat', _ringkasan['terlambat'], Colors.orange),
            _kpi('Izin / cuti / sakit', _ringkasan['izin'], Colors.purple),
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
                            child: Text('Belum ada data pada periode ini.'))
                        : ListView.builder(
                            itemCount: _data.length,
                            itemBuilder: (_, i) {
                              final row = _data[i];
                              final total = (row['total'] as num?) ?? 0;
                              final tepat = (row['tepatWaktu'] as num?) ?? 0;
                              final rasio =
                                  total == 0 ? 0 : tepat * 100 / total;
                              return Card(
                                  child: ListTile(
                                      leading:
                                          CircleAvatar(child: Text('${i + 1}')),
                                      title: Text('${row['pegawai'] ?? '-'}'),
                                      subtitle: Text(
                                          'Tepat waktu ${row['tepatWaktu'] ?? 0} · Terlambat ${row['terlambat'] ?? 0} · Izin ${row['izin'] ?? 0}'),
                                      trailing: Text(
                                          '${rasio.toStringAsFixed(0)}%',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))));
                            }))
      ]));
}

class _PayrollTab extends StatefulWidget {
  const _PayrollTab();
  @override
  State<_PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<_PayrollTab> {
  bool _memuat = true, _bolehKelola = false;
  String? _error;
  List<Map<String, dynamic>> _slip = [], _pengajuan = [];
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
      final hasil = await Future.wait([
        ApiClient.instance.aksi('hrd_payroll_daftar', {'page_size': 100}),
        ApiClient.instance.aksi('hrd_pengajuan_daftar', {'page_size': 100}),
      ]);
      setStateIfMounted(() {
        _slip = ((hasil[0]['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        _pengajuan = ((hasil[1]['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        _bolehKelola = hasil[1]['bolehKelola'] == true;
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaSlip(Map<String, dynamic> slip) async {
    final r =
        await ApiClient.instance.aksi('hrd_slip_detail', {'id': slip['id']});
    if (!mounted) return;
    final item =
        ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
    await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Slip Gaji · ${r['pegawai'] ?? '-'}'),
              content: SizedBox(
                  width: 560,
                  height: 420,
                  child: Column(children: [
                    Expanded(
                        child: ListView.separated(
                            itemCount: item.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => ListTile(
                                  title: Text('${item[i]['nama'] ?? '-'}'),
                                  subtitle:
                                      Text('${item[i]['keterangan'] ?? ''}'),
                                  trailing: Text(_rupiah
                                      .format((item[i]['nilai'] as num?) ?? 0)),
                                ))),
                    const Divider(),
                    ListTile(
                        title: const Text('Take Home Pay',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text(
                            _rupiah.format((r['nilaiFinal'] as num?) ?? 0),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)))
                  ])),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'))
              ],
            ));
  }

  Future<void> _ajukan() async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => const _FormPengajuanPayroll());
    if (ok == true) await _muat();
  }

  Future<void> _putusanPengajuan(Map<String, dynamic> row) async {
    try {
      await ApiClient.instance
          .aksi('hrd_pengajuan_putusan', {'id': row['id'], 'setujui': true});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Pengajuan disetujui untuk diproses payroll; belum dicairkan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Text('Slip gaji dan pengajuan pegawai',
                  style: Theme.of(context).textTheme.titleMedium)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: _ajukan,
              icon: const Icon(Icons.add),
              label: const Text('Ajukan Lembur / Kasbon'))
        ]),
        const SizedBox(height: 12),
        Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)))
                    : Row(children: [
                        Expanded(child: _daftarSlip(context)),
                        const VerticalDivider(width: 24),
                        Expanded(child: _daftarPengajuan(context)),
                      ]))
      ]));

  Widget _daftarSlip(BuildContext context) => Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: Text('Slip Gaji',
                style: Theme.of(context).textTheme.titleSmall)),
        const SizedBox(height: 8),
        Expanded(
            child: _slip.isEmpty
                ? const Center(child: Text('Belum ada slip gaji.'))
                : ListView.builder(
                    itemCount: _slip.length,
                    itemBuilder: (_, i) {
                      final s = _slip[i];
                      return Card(
                          child: ListTile(
                              onTap: () => _bukaSlip(s),
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text(
                                  '${s['pegawai'] ?? '-'} · ${s['bulan'] ?? '-'}/${s['tahun'] ?? '-'}'),
                              subtitle: Text(s['dibayar'] == true
                                  ? 'Sudah dibayar ${s['tanggalBayar'] ?? ''}'
                                  : 'Belum dibayar'),
                              trailing: Text(_rupiah
                                  .format((s['nilaiFinal'] as num?) ?? 0))));
                    }))
      ]);

  Widget _daftarPengajuan(BuildContext context) => Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: Text('Pengajuan',
                style: Theme.of(context).textTheme.titleSmall)),
        const SizedBox(height: 8),
        Expanded(
            child: _pengajuan.isEmpty
                ? const Center(child: Text('Belum ada pengajuan payroll.'))
                : ListView.builder(
                    itemCount: _pengajuan.length,
                    itemBuilder: (_, i) {
                      final p = _pengajuan[i];
                      return Card(
                          child: ListTile(
                              leading: Icon(
                                  p['status'] == 'DISETUJUI'
                                      ? Icons.check_circle_outline
                                      : Icons.hourglass_top,
                                  color: p['status'] == 'DISETUJUI'
                                      ? Colors.green
                                      : Colors.orange),
                              title: Text(
                                  '${p['jenis'] ?? '-'} · ${p['pegawai'] ?? '-'}'),
                              subtitle: Text(
                                  '${p['tanggal'] ?? '-'} · ${p['status'] ?? 'MENUNGGU'}\n${p['keterangan'] ?? ''}'),
                              isThreeLine: true,
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_rupiah
                                        .format((p['nilai'] as num?) ?? 0)),
                                    if (_bolehKelola &&
                                        p['status'] != 'DISETUJUI') ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                          tooltip:
                                              'Setujui untuk proses payroll',
                                          onPressed: () => _putusanPengajuan(p),
                                          icon: const Icon(
                                              Icons.approval_outlined))
                                    ]
                                  ])));
                    }))
      ]);
}

class _FormPengajuanPayroll extends StatefulWidget {
  const _FormPengajuanPayroll();
  @override
  State<_FormPengajuanPayroll> createState() => _FormPengajuanPayrollState();
}

class _FormPengajuanPayrollState extends State<_FormPengajuanPayroll> {
  List<Map<String, dynamic>> _jenis = [];
  int? _jenisId;
  final _nilai = TextEditingController(),
      _angsuran = TextEditingController(text: '1'),
      _keterangan = TextEditingController();
  DateTime _jatuhTempo = DateTime.now().add(const Duration(days: 30));
  bool _simpan = false;

  @override
  void initState() {
    super.initState();
    _muatJenis();
  }

  @override
  void dispose() {
    _nilai.dispose();
    _angsuran.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _muatJenis() async {
    final r = await ApiClient.instance.aksi('hrd_pengajuan_jenis', {});
    setStateIfMounted(() {
      _jenis = ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (_jenis.isNotEmpty) _jenisId = (_jenis.first['id'] as num).toInt();
    });
  }

  Future<void> _kirim() async {
    final nilai =
        double.tryParse(_nilai.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final angsuran = int.tryParse(_angsuran.text) ?? 1;
    if (_jenisId == null || nilai <= 0 || _keterangan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Jenis, nilai, dan keterangan wajib diisi.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('hrd_pengajuan_simpan', {
        'jenis_id': _jenisId,
        'nilai': nilai,
        'jumlah_angsur': angsuran,
        'jatuh_tempo': DateFormat('yyyy-MM-dd').format(_jatuhTempo),
        'keterangan': _keterangan.text.trim()
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
        title: const Text('Pengajuan Payroll'),
        content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                  value: _jenisId,
                  decoration:
                      const InputDecoration(labelText: 'Jenis pengajuan'),
                  items: _jenis
                      .map((j) => DropdownMenuItem<int>(
                          value: (j['id'] as num).toInt(),
                          child: Text('${j['nama'] ?? '-'}')))
                      .toList(),
                  onChanged: (v) => setState(() => _jenisId = v)),
              const SizedBox(height: 12),
              TextField(
                  controller: _nilai,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nilai (Rp)')),
              const SizedBox(height: 12),
              TextField(
                  controller: _angsuran,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Jumlah angsuran')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: _jatuhTempo,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100));
                    if (d != null) setStateIfMounted(() => _jatuhTempo = d);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                      'Jatuh tempo ${DateFormat('dd-MM-yyyy').format(_jatuhTempo)}')),
              const SizedBox(height: 12),
              TextField(
                  controller: _keterangan,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Keterangan / alasan'))
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
