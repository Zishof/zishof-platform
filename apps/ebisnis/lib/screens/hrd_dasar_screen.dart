import 'dart:convert';

import 'package:barcode/barcode.dart' as bc;
import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import 'anggota/member_biometric_panel.dart';
import 'attendance_photo_capture_screen.dart';
import '../services/biometric_capture_bridge.dart';
import '../services/hrd_local_first.dart';
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
                  ButtonSegment(
                      value: 5,
                      icon: Icon(Icons.trending_up_outlined),
                      label: Text('Karier & Gaji')),
                  ButtonSegment(
                      value: 6,
                      icon: Icon(Icons.task_alt_outlined),
                      label: Text('Kinerja')),
                  ButtonSegment(
                      value: 7,
                      icon: Icon(Icons.history_edu_outlined),
                      label: Text('Riwayat')),
                  ButtonSegment(
                      value: 8,
                      icon: Icon(Icons.account_tree_outlined),
                      label: Text('Master HRD')),
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
          _KarierGajiTab(),
          _KinerjaPegawaiTab(),
          _RiwayatPegawaiTab(),
          _MasterHrdTab(),
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
  bool _bolehKelola = false;

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
      final body = {'keyword': _cari.text.trim(), 'page_size': 200};
      await HrdLocalFirst.baca('hrd_pegawai_daftar', body, onData: (r) {
        setStateIfMounted(() {
          _data =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _bolehKelola = r['dariServer'] == true && r['bolehKelola'] == true;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _biometrik(Map<String, dynamic> pegawai) async {
    final userId = '${pegawai['akunUserId'] ?? ''}'.trim();
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Buat dan tautkan akun pegawai sebelum merekam biometrik.')));
      return;
    }
    await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 920, maxHeight: 760),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: Text('Biometrik ${pegawai['nama'] ?? '-'}'),
                      subtitle: Text('Akun $userId'),
                      trailing: IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close)),
                    ),
                    const Divider(height: 1),
                    Expanded(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: MemberBiometricPanel(
                                targetUserId: userId,
                                memberName: '${pegawai['nama'] ?? '-'}'))),
                  ])),
            ));
  }

  Future<void> _profil(Map<String, dynamic> pegawai) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _FormProfilPegawai(
            pegawaiId: (pegawai['id'] as num).toInt(),
            bolehKelola: _bolehKelola));
    if (ok == true) await _muat();
  }

  Future<void> _imporPegawai() async {
    final berubah = await showDialog<bool>(
        context: context, builder: (_) => const _DialogImporPegawaiZk());
    if (berubah == true) await _muat();
  }

  @override
  Widget build(BuildContext context) => _PanelDaftar(
        header: Row(children: [
          Expanded(
              child: TextField(
                  controller: _cari,
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Cari kode atau nama pegawai',
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh), onPressed: _muat)),
                  onSubmitted: (_) => _muat())),
          if (_bolehKelola) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
                onPressed: _imporPegawai,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Impor Pegawai ZK')),
          ]
        ]),
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
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Chip(
                        label: Text(p['aktif'] == true ? 'Aktif' : 'Nonaktif')),
                    IconButton(
                        tooltip: _bolehKelola
                            ? 'Lihat atau ubah profil pegawai'
                            : 'Lihat profil pegawai',
                        icon: const Icon(Icons.contact_page_outlined),
                        onPressed: () => _profil(p)),
                    if (_bolehKelola) ...[
                      const SizedBox(width: 6),
                      if (('${p['akunUserId'] ?? ''}').isNotEmpty)
                        IconButton(
                            tooltip: 'Kelola sidik jari dan wajah',
                            icon: const Icon(Icons.fingerprint),
                            onPressed: () => _biometrik(p)),
                      IconButton(
                          tooltip: ('${p['akunUserId'] ?? ''}').isEmpty
                              ? 'Buat akun pegawai'
                              : 'Perbarui akun pegawai',
                          icon: const Icon(Icons.manage_accounts_outlined),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => _FormAkunPegawai(pegawai: p));
                            if (ok == true) await _muat();
                          })
                    ]
                  ]),
                ))
            .toList(),
      );
}

class _DialogImporPegawaiZk extends StatefulWidget {
  const _DialogImporPegawaiZk();
  @override
  State<_DialogImporPegawaiZk> createState() => _DialogImporPegawaiZkState();
}

class _DialogImporPegawaiZkState extends State<_DialogImporPegawaiZk> {
  final _cari = TextEditingController();
  List<Map<String, dynamic>> _data = [];
  bool _memuat = true;
  int? _sedangTautkan;
  String? _error;

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
      final r = await ApiClient.instance.aksi('hrd_pegawai_tenant_kandidat',
          {'keyword': _cari.text.trim(), 'page_size': 200});
      setStateIfMounted(() => _data =
          ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _tautkan(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    setState(() => _sedangTautkan = id);
    try {
      await ApiClient.instance
          .aksi('hrd_pegawai_tenant_tautkan', {'pegawai_id': id});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _sedangTautkan = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Impor Pegawai dari ZK'),
          content: SizedBox(
              width: 700,
              height: 520,
              child: Column(children: [
                const Text(
                    'Hanya pegawai aktif yang belum terikat pada tenant lain yang ditampilkan.'),
                const SizedBox(height: 12),
                TextField(
                    controller: _cari,
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Cari kode atau nama pegawai lama',
                        suffixIcon: IconButton(
                            onPressed: _muat, icon: const Icon(Icons.refresh))),
                    onSubmitted: (_) => _muat()),
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
                                    child: Text(
                                        'Tidak ada pegawai ZK yang belum terikat.'))
                                : ListView.builder(
                                    itemCount: _data.length,
                                    itemBuilder: (_, i) {
                                      final row = _data[i];
                                      final id = (row['id'] as num).toInt();
                                      return ListTile(
                                          leading:
                                              const Icon(Icons.badge_outlined),
                                          title: Text('${row['nama'] ?? '-'}'),
                                          subtitle: Text(
                                              '${row['kode'] ?? '-'} · ${row['jabatan'] ?? '-'} · ${row['satuanKerja'] ?? '-'}'),
                                          trailing: FilledButton(
                                              onPressed: _sedangTautkan == null
                                                  ? () => _tautkan(row)
                                                  : null,
                                              child: Text(_sedangTautkan == id
                                                  ? 'Mengimpor…'
                                                  : 'Impor')));
                                    }))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Tutup'))
          ]);
}

class _FormProfilPegawai extends StatefulWidget {
  const _FormProfilPegawai(
      {required this.pegawaiId, required this.bolehKelola});
  final int pegawaiId;
  final bool bolehKelola;
  @override
  State<_FormProfilPegawai> createState() => _FormProfilPegawaiState();
}

class _FormProfilPegawaiState extends State<_FormProfilPegawai> {
  final Map<String, TextEditingController> _c = {};
  bool _memuat = true, _simpan = false;
  String? _error;

  TextEditingController _controller(String key) =>
      _c.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      await HrdLocalFirst.baca(
          'hrd_pegawai_detail', {'pegawai_id': widget.pegawaiId}, onData: (r) {
        final data = Map<String, dynamic>.from(r['data'] as Map? ?? const {});
        for (final entry in data.entries) {
          _controller(entry.key).text = '${entry.value ?? ''}';
        }
        setStateIfMounted(() {});
      });
    } catch (e) {
      _error = '$e';
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihTanggal() async {
    final awal = DateTime.tryParse(_controller('tanggalLahir').text) ??
        DateTime(1990, 1, 1);
    final tanggal = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(1940),
        lastDate: DateTime.now());
    if (tanggal != null) {
      _controller('tanggalLahir').text =
          DateFormat('yyyy-MM-dd').format(tanggal);
    }
  }

  Future<void> _kirim() async {
    if (_controller('nama').text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama pegawai wajib diisi.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('hrd_pegawai_profil_simpan', {
        'pegawai_id': widget.pegawaiId,
        'nama': _controller('nama').text.trim(),
        'email': _controller('email').text.trim(),
        'hp': _controller('hp').text.trim(),
        'telepon': _controller('telepon').text.trim(),
        'kelamin': _controller('kelamin').text.trim(),
        'tempat_lahir': _controller('tempatLahir').text.trim(),
        'tanggal_lahir': _controller('tanggalLahir').text.trim(),
        'alamat': _controller('alamat').text.trim(),
        'ktp': _controller('ktp').text.trim(),
        'status_perkawinan': _controller('statusPerkawinan').text.trim(),
        'golongan_darah': _controller('golonganDarah').text.trim(),
        'nomor_kk': _controller('nomorKk').text.trim(),
        'nama_ibu': _controller('namaIbu').text.trim(),
        'nama_darurat': _controller('namaDarurat').text.trim(),
        'telepon_darurat': _controller('teleponDarurat').text.trim(),
        'status_darurat': _controller('statusDarurat').text.trim(),
        'keterangan': _controller('keterangan').text.trim(),
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

  Widget _field(String key, String label,
          {int maxLines = 1, bool readOnly = false, VoidCallback? onTap}) =>
      SizedBox(
          width: maxLines > 1 ? 700 : 330,
          child: TextField(
              controller: _controller(key),
              enabled: widget.bolehKelola || readOnly,
              readOnly: readOnly || !widget.bolehKelola,
              onTap: onTap,
              maxLines: maxLines,
              decoration: InputDecoration(labelText: label)));

  @override
  Widget build(BuildContext context) => Dialog(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 760),
          child: Column(children: [
            ListTile(
                leading: const Icon(Icons.contact_page_outlined),
                title: const Text('Profil Pegawai'),
                subtitle: Text(widget.bolehKelola
                    ? 'Data induk pegawai dari modul HRD ZK'
                    : 'Mode baca'),
                trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))),
            const Divider(height: 1),
            Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Wrap(spacing: 12, runSpacing: 12, children: [
                              _field('kode', 'Kode pegawai', readOnly: true),
                              _field('nama', 'Nama lengkap *'),
                              _field('jabatan', 'Jabatan', readOnly: true),
                              _field('golongan', 'Golongan', readOnly: true),
                              _field('email', 'Email'),
                              _field('hp', 'Nomor HP'),
                              _field('telepon', 'Telepon'),
                              _field('kelamin', 'Jenis kelamin'),
                              _field('tempatLahir', 'Tempat lahir'),
                              _field('tanggalLahir', 'Tanggal lahir',
                                  readOnly: true,
                                  onTap: widget.bolehKelola
                                      ? _pilihTanggal
                                      : null),
                              _field('ktp', 'Nomor KTP'),
                              _field('nomorKk', 'Nomor kartu keluarga'),
                              _field('statusPerkawinan', 'Status perkawinan'),
                              _field('golonganDarah', 'Golongan darah'),
                              _field('namaIbu', 'Nama ibu kandung'),
                              _field('namaDarurat', 'Kontak darurat'),
                              _field('teleponDarurat', 'Telepon darurat'),
                              _field(
                                  'statusDarurat', 'Hubungan kontak darurat'),
                              _field('alamat', 'Alamat', maxLines: 3),
                              _field('keterangan', 'Keterangan', maxLines: 3),
                            ]))),
            if (widget.bolehKelola) ...[
              const Divider(height: 1),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed:
                            _simpan ? null : () => Navigator.pop(context),
                        child: const Text('Batal')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                        onPressed: _simpan ? null : _kirim,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_simpan ? 'Menyimpan…' : 'Simpan Profil')),
                  ]))
            ]
          ])));
}

class _FormAkunPegawai extends StatefulWidget {
  const _FormAkunPegawai({required this.pegawai});
  final Map<String, dynamic> pegawai;
  @override
  State<_FormAkunPegawai> createState() => _FormAkunPegawaiState();
}

class _FormAkunPegawaiState extends State<_FormAkunPegawai> {
  late final TextEditingController _userId, _nama, _email;
  final _password = TextEditingController();
  bool _aktif = true, _simpan = false, _sembunyikan = true;

  bool get _baru => ('${widget.pegawai['akunUserId'] ?? ''}').trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _userId =
        TextEditingController(text: '${widget.pegawai['akunUserId'] ?? ''}');
    _nama = TextEditingController(text: '${widget.pegawai['nama'] ?? ''}');
    _email = TextEditingController();
    _aktif = widget.pegawai['akunAktif'] != false;
  }

  @override
  void dispose() {
    _userId.dispose();
    _nama.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _kirim() async {
    if (_userId.text.trim().length < 4 ||
        (_baru && _password.text.length < 8)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Username minimal 4 karakter dan password awal minimal 8 karakter.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('hrd_akun_pegawai_simpan', {
        'pegawai_id': widget.pegawai['id'],
        'user_id': _userId.text.trim(),
        'nama': _nama.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        'aktif': _aktif,
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
        title: Text(_baru ? 'Buat Akun Pegawai' : 'Perbarui Akun Pegawai'),
        content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${widget.pegawai['nama'] ?? '-'}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                  controller: _userId,
                  enabled: _baru,
                  decoration: const InputDecoration(labelText: 'Username *')),
              const SizedBox(height: 12),
              TextField(
                  controller: _nama,
                  decoration:
                      const InputDecoration(labelText: 'Nama tampilan')),
              const SizedBox(height: 12),
              TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
              if (_baru) ...[
                const SizedBox(height: 12),
                TextField(
                    controller: _password,
                    obscureText: _sembunyikan,
                    decoration: InputDecoration(
                        labelText: 'Password awal *',
                        suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _sembunyikan = !_sembunyikan),
                            icon: Icon(_sembunyikan
                                ? Icons.visibility
                                : Icons.visibility_off))))
              ],
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _aktif,
                  onChanged: (v) => setState(() => _aktif = v),
                  title: const Text('Akun aktif')),
            ])),
        actions: [
          TextButton(
              onPressed: _simpan ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _simpan ? null : _kirim,
              child: Text(_simpan ? 'Menyimpan…' : 'Simpan')),
        ],
      );
}

class _CutiTab extends StatefulWidget {
  const _CutiTab();
  @override
  State<_CutiTab> createState() => _CutiTabState();
}

class _CutiTabState extends State<_CutiTab> {
  bool _memuat = true;
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
      await HrdLocalFirst.baca('hrd_cuti_daftar', const {'page_size': 200},
          onData: (r) {
        setStateIfMounted(() {
          _data =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        });
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

  Future<void> _putusan(
      Map<String, dynamic> row, String tahap, bool setujui) async {
    final catatan = TextEditingController();
    final lanjut = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(
                  '${setujui ? 'Setujui' : 'Tolak'} sebagai ${tahap == 'ATASAN' ? 'Atasan' : 'HRD'}'),
              content: TextField(
                  controller: catatan,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                      labelText: setujui
                          ? 'Catatan (opsional)'
                          : 'Catatan penolakan (wajib)',
                      hintText: 'Tuliskan hasil pemeriksaan pengajuan')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () {
                      if (!setujui && catatan.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                    child: Text(setujui ? 'Setujui' : 'Tolak'))
              ],
            ));
    if (lanjut != true) {
      catatan.dispose();
      return;
    }
    try {
      await ApiClient.instance.aksi('hrd_cuti_putusan', {
        'id': row['id'],
        'tahap': tahap,
        'setujui': setujui,
        'catatan': catatan.text.trim()
      });
      await _muat();
    } finally {
      catatan.dispose();
    }
  }

  Color _warna(String status) => status == 'DISETUJUI'
      ? Colors.green
      : status.startsWith('DITOLAK')
          ? Colors.red
          : Colors.orange;

  String _riwayat(Map<String, dynamic> r) {
    final bagian = <String>[];
    final atasan = '${r['atasanOleh'] ?? ''}'.trim();
    final hrd = '${r['hrdOleh'] ?? ''}'.trim();
    if (atasan.isNotEmpty) {
      bagian.add(
          'Atasan: $atasan · ${r['tanggalAtasan'] ?? '-'}${'${r['catatanAtasan'] ?? ''}'.trim().isEmpty ? '' : ' · ${r['catatanAtasan']}'}');
    }
    if (hrd.isNotEmpty) {
      bagian.add(
          'HRD: $hrd · ${r['tanggalHrd'] ?? '-'}${'${r['catatanHrd'] ?? ''}'.trim().isEmpty ? '' : ' · ${r['catatanHrd']}'}');
    }
    return bagian.isEmpty
        ? 'Alur: menunggu keputusan atasan'
        : bagian.join('\n');
  }

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
                '${r['mulai'] ?? '-'} s.d. ${r['sampai'] ?? '-'}\n${r['keterangan'] ?? ''}\n${_riwayat(r)}'),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Chip(
                  label: Text(status),
                  labelStyle: TextStyle(color: _warna(status))),
              if (r['bolehPutusAtasan'] == true)
                PopupMenuButton<bool>(
                    tooltip: 'Keputusan atasan',
                    onSelected: (v) => _putusan(r, 'ATASAN', v),
                    itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: true, child: Text('Atasan: Setujui')),
                          PopupMenuItem(
                              value: false, child: Text('Atasan: Tolak'))
                        ]),
              if (r['bolehPutusHrd'] == true)
                PopupMenuButton<bool>(
                    tooltip: 'Keputusan HRD',
                    onSelected: (v) => _putusan(r, 'HRD', v),
                    itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: true, child: Text('HRD: Setujui')),
                          PopupMenuItem(value: false, child: Text('HRD: Tolak'))
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
    await HrdLocalFirst.baca('hrd_jenis_cuti_daftar', const {}, onData: (r) {
      setStateIfMounted(() {
        _jenis =
            ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (_jenis.isNotEmpty) _jenisId = (_jenis.first['id'] as num).toInt();
      });
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
  bool _memuat = true, _memproses = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  String _qrPresensi = '';
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
      final body = {
        'dari': f.format(_dari),
        'sampai': f.format(_sampai),
        'page_size': 500
      };
      await HrdLocalFirst.baca('hrd_kehadiran_daftar', body, onData: (r) {
        setStateIfMounted(() {
          _data =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _qrPresensi = '${r['qrPresensi'] ?? ''}';
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<String?> _pilihArah() => showDialog<String>(
      context: context,
      builder: (context) =>
          SimpleDialog(title: const Text('Pilih jenis presensi'), children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, '0'),
                child: const ListTile(
                    leading: Icon(Icons.login), title: Text('Masuk'))),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, '1'),
                child: const ListTile(
                    leading: Icon(Icons.logout), title: Text('Pulang')))
          ]));

  Future<void> _presensi(String metode) async {
    if (_memproses) return;
    final state = await _pilihArah();
    if (state == null || !mounted) return;
    final payload = <String, dynamic>{
      'state': state,
      'metode': metode,
      'captured_at_epoch': DateTime.now().millisecondsSinceEpoch,
      'clientMutationId':
          'hrd-presensi-${DateTime.now().microsecondsSinceEpoch}'
    };
    try {
      setStateIfMounted(() => _memproses = true);
      String aksi = 'absen';
      if (metode == 'FOTO') {
        final bytes = await AttendancePhotoCaptureScreen.ambil(context);
        if (bytes == null) return;
        payload['foto_base64'] = base64Encode(bytes);
      } else if (metode == 'QR') {
        final kode = await BarcodeScannerScreen.pindai(context,
            judul: 'Scan QR Presensi Toko');
        if (kode == null || kode.trim().isEmpty) return;
        payload['kode_qr'] = kode.trim();
      } else if (metode == 'FINGERPRINT') {
        final bridge = PosBiometricCaptureBridge();
        final device = await bridge.capabilities();
        final server = await ApiClient.instance.aksi('biometrik_kemampuan');
        final readiness = PosBiometricReadiness(device: device, server: server);
        if (!readiness.verificationReady('FINGERPRINT')) {
          throw StateError(readiness.reason('FINGERPRINT', enrollment: false));
        }
        final sample = await bridge.capture('FINGERPRINT');
        payload.addAll({
          'modality': sample.modality,
          'probe_base64': sample.templateBase64,
          'template_format': sample.templateFormat,
          'provider': sample.provider,
          'liveness_score': sample.livenessScore,
        });
        aksi = 'biometrik_absen';
      }
      final hasil = await ApiClient.instance.aksi(aksi, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${hasil['description'] ?? 'Presensi tersimpan.'}')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _memproses = false);
    }
  }

  Future<void> _tampilkanKodeQr() async {
    if (_qrPresensi.isEmpty) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('QR Presensi Toko'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: CustomPaint(
                        size: const Size.square(220),
                        painter: _QrPresensiPainter(_qrPresensi))),
                const SizedBox(height: 12),
                const Text(
                    'Tampilkan atau cetak QR ini di area presensi toko.'),
                const SizedBox(height: 8),
                SelectableText(_qrPresensi)
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => _PanelDaftar(
      header: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
        FilledButton.icon(
            onPressed: _memproses ? null : () => _presensi('FOTO'),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Presensi Foto')),
        OutlinedButton.icon(
            onPressed: _memproses ? null : () => _presensi('QR'),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR')),
        OutlinedButton.icon(
            onPressed: _memproses ? null : () => _presensi('FINGERPRINT'),
            icon: const Icon(Icons.fingerprint),
            label: const Text('Fingerprint')),
        if (_qrPresensi.isNotEmpty)
          IconButton(
              onPressed: _tampilkanKodeQr,
              tooltip: 'Lihat kode QR toko',
              icon: const Icon(Icons.qr_code_2)),
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

class _QrPresensiPainter extends CustomPainter {
  const _QrPresensiPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    for (final element in bc.Barcode.qrCode()
        .make(data, width: size.width, height: size.height, drawText: false)) {
      if (element is bc.BarcodeBar && element.black) {
        canvas.drawRect(
            Rect.fromLTWH(
                element.left, element.top, element.width, element.height),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPresensiPainter oldDelegate) =>
      oldDelegate.data != data;
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
      final body = {
        'dari': f.format(_dari),
        'sampai': f.format(_sampai),
        'page_size': 5000
      };
      await HrdLocalFirst.baca('hrd_kehadiran_ringkasan', body, onData: (r) {
        final rows =
            ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        rows.sort((a, b) => ((b['tepatWaktu'] as num?) ?? 0)
            .compareTo((a['tepatWaktu'] as num?) ?? 0));
        setStateIfMounted(() {
          _ringkasan = r;
          _data = rows;
        });
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
      await Future.wait([
        HrdLocalFirst.baca('hrd_payroll_daftar', const {'page_size': 100},
            onData: (r) => setStateIfMounted(() => _slip =
                ((r['data'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>())),
        HrdLocalFirst.baca('hrd_pengajuan_daftar', const {'page_size': 100},
            onData: (r) => setStateIfMounted(() {
                  _pengajuan = ((r['data'] as List?) ?? const [])
                      .cast<Map<String, dynamic>>();
                  _bolehKelola =
                      r['dariServer'] == true && r['bolehKelola'] == true;
                })),
      ]);
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaSlip(Map<String, dynamic> slip) async {
    Map<String, dynamic>? r;
    await HrdLocalFirst.baca('hrd_slip_detail', {'id': slip['id']},
        onData: (hasil) => r = hasil);
    final detail = r;
    if (detail == null) return;
    if (!mounted) return;
    final item =
        ((detail['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
    await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Slip Gaji · ${detail['pegawai'] ?? '-'}'),
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
                            _rupiah.format((detail['nilaiFinal'] as num?) ?? 0),
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

  Future<void> _putusanPengajuan(Map<String, dynamic> row, bool setujui) async {
    final lanjut = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(setujui ? 'Setujui pengajuan' : 'Tolak pengajuan'),
              content: Text(setujui
                  ? 'Persetujuan akan membentuk ${row['jumlahAngsur'] ?? 1} angsuran payroll dan mengunci pengajuan. Nilai serta jadwal tidak dapat diubah setelah ini.'
                  : 'Pengajuan akan ditolak sebelum masuk payroll. Pegawai perlu membuat pengajuan baru bila ada koreksi.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(setujui ? 'Setujui & Kunci' : 'Tolak'))
              ],
            ));
    if (lanjut != true) return;
    try {
      final hasil = await ApiClient.instance
          .aksi('hrd_pengajuan_putusan', {'id': row['id'], 'setujui': setujui});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(setujui
                ? '${hasil['angsuranDibuat'] ?? 0} angsuran payroll dibuat dan pengajuan dikunci.'
                : 'Pengajuan ditolak sebelum masuk payroll.')));
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
                                  p['status'] == 'DISETUJUI_TERKUNCI'
                                      ? Icons.check_circle_outline
                                      : p['status'] == 'DITOLAK'
                                          ? Icons.cancel_outlined
                                          : Icons.hourglass_top,
                                  color: p['status'] == 'DISETUJUI_TERKUNCI'
                                      ? Colors.green
                                      : p['status'] == 'DITOLAK'
                                          ? Colors.red
                                          : Colors.orange),
                              title: Text(
                                  '${p['jenis'] ?? '-'} · ${p['pegawai'] ?? '-'}'),
                              subtitle: Text(
                                  '${p['tanggal'] ?? '-'} · ${p['status'] ?? 'MENUNGGU'}\n'
                                  '${p['keterangan'] ?? ''}\n'
                                  'Angsuran: ${p['angsuranPayroll'] ?? 0} · Masuk slip: ${p['masukSlip'] ?? 0} · Diposting: ${p['diposting'] ?? 0}'),
                              isThreeLine: true,
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_rupiah
                                        .format((p['nilai'] as num?) ?? 0)),
                                    if (_bolehKelola &&
                                        p['status'] == 'MENUNGGU') ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                          tooltip: 'Tolak sebelum payroll',
                                          onPressed: () =>
                                              _putusanPengajuan(p, false),
                                          icon: const Icon(Icons.close)),
                                      IconButton(
                                          tooltip: 'Setujui dan kunci payroll',
                                          onPressed: () =>
                                              _putusanPengajuan(p, true),
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
    await HrdLocalFirst.baca('hrd_pengajuan_jenis', const {}, onData: (r) {
      setStateIfMounted(() {
        _jenis =
            ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (_jenis.isNotEmpty) _jenisId = (_jenis.first['id'] as num).toInt();
      });
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

class _KarierGajiTab extends StatefulWidget {
  const _KarierGajiTab();
  @override
  State<_KarierGajiTab> createState() => _KarierGajiTabState();
}

class _KarierGajiTabState extends State<_KarierGajiTab> {
  bool _memuat = true, _bolehKelola = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
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
      await HrdLocalFirst.baca(
          'hrd_kenaikan_gaji_daftar', const {'page_size': 300}, onData: (r) {
        setStateIfMounted(() {
          _data =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _bolehKelola = r['dariServer'] == true && r['bolehKelola'] == true;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _tambah() async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => const _FormKenaikanGaji());
    if (ok == true) await _muat();
  }

  Future<void> _putusan(Map<String, dynamic> row, bool setujui) async {
    try {
      await ApiClient.instance.aksi(
          'hrd_kenaikan_gaji_putusan', {'id': row['id'], 'setujui': setujui});
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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
              child: Text('Kenaikan gaji berkala',
                  style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: _muat, icon: const Icon(Icons.refresh)),
          if (_bolehKelola)
            FilledButton.icon(
                onPressed: _tambah,
                icon: const Icon(Icons.add_chart),
                label: const Text('Ajukan Kenaikan')),
        ]),
        memuat: _memuat,
        error: _error,
        kosong: 'Belum ada riwayat kenaikan gaji.',
        children: _data.map((r) {
          final status = '${r['status'] ?? 'BELUM DIPROSES'}';
          return Card(
              child: ListTile(
            leading: CircleAvatar(
                child: Icon(status == 'DISETUJUI'
                    ? Icons.trending_up
                    : Icons.schedule)),
            title: Text('${r['pegawai'] ?? '-'} · SK ${r['noSk'] ?? '-'}'),
            subtitle: Text(
                'TMT ${r['tmt'] ?? '-'} · Masa kerja ${r['masaKerjaTahun'] ?? 0} th ${r['masaKerjaBulan'] ?? 0} bln\n'
                '${_rupiah.format((r['gajiLama'] as num?) ?? 0)} → ${_rupiah.format((r['gajiBaru'] as num?) ?? 0)}'
                '${('${r['keterangan'] ?? ''}').isEmpty ? '' : ' · ${r['keterangan']}'}'),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Chip(
                  label: Text(status),
                  labelStyle: TextStyle(color: _warna(status))),
              if (_bolehKelola && status == 'BELUM DIPROSES')
                PopupMenuButton<bool>(
                    onSelected: (v) => _putusan(r, v),
                    itemBuilder: (_) => const [
                          PopupMenuItem(value: true, child: Text('Setujui')),
                          PopupMenuItem(value: false, child: Text('Tolak')),
                        ])
            ]),
          ));
        }).toList(),
      );
}

class _FormKenaikanGaji extends StatefulWidget {
  const _FormKenaikanGaji();
  @override
  State<_FormKenaikanGaji> createState() => _FormKenaikanGajiState();
}

class _FormKenaikanGajiState extends State<_FormKenaikanGaji> {
  List<Map<String, dynamic>> _pegawai = [], _gaji = [];
  int? _pegawaiId, _gajiLamaId, _gajiBaruId;
  final _noSk = TextEditingController(),
      _tahun = TextEditingController(text: '0'),
      _bulan = TextEditingController(text: '0'),
      _keterangan = TextEditingController();
  DateTime _tanggalSk = DateTime.now(),
      _tmt = DateTime.now(),
      _berikutnya = DateTime(
          DateTime.now().year + 2, DateTime.now().month, DateTime.now().day);
  bool _memuat = true, _simpan = false;
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _muatPilihan();
  }

  @override
  void dispose() {
    _noSk.dispose();
    _tahun.dispose();
    _bulan.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _muatPilihan() async {
    try {
      await Future.wait([
        HrdLocalFirst.baca('hrd_pegawai_daftar', const {'page_size': 200},
            onData: (r) {
          setStateIfMounted(() {
            _pegawai =
                ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
            if (_pegawai.isNotEmpty && _pegawaiId == null) {
              _pegawaiId = (_pegawai.first['id'] as num).toInt();
            }
          });
        }),
        HrdLocalFirst.baca('hrd_gaji_pokok_daftar', const {}, onData: (r) {
          setStateIfMounted(() {
            _gaji =
                ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
            if (_gaji.isNotEmpty) {
              _gajiLamaId ??= (_gaji.first['id'] as num).toInt();
              _gajiBaruId ??= (_gaji.first['id'] as num).toInt();
            }
          });
        }),
      ]);
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<DateTime> _pilih(DateTime awal) async =>
      await showDatePicker(
          context: context,
          initialDate: awal,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100)) ??
      awal;

  String _labelGaji(Map<String, dynamic> g) =>
      '${g['golongan'] ?? '-'} · ${g['masaKerja'] ?? 0} th · ${_rupiah.format((g['gaji'] as num?) ?? 0)}';

  Future<void> _kirim() async {
    final tahun = int.tryParse(_tahun.text) ?? -1,
        bulan = int.tryParse(_bulan.text) ?? -1;
    if (_pegawaiId == null ||
        _gajiLamaId == null ||
        _gajiBaruId == null ||
        _noSk.text.trim().isEmpty ||
        tahun < 0 ||
        bulan < 0 ||
        bulan > 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Lengkapi pegawai, SK, masa kerja, dan gaji lama/baru.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      final f = DateFormat('yyyy-MM-dd');
      await ApiClient.instance.aksi('hrd_kenaikan_gaji_simpan', {
        'pegawai_id': _pegawaiId,
        'no_sk': _noSk.text.trim(),
        'tanggal_sk': f.format(_tanggalSk),
        'tmt': f.format(_tmt),
        'naik_berikutnya': f.format(_berikutnya),
        'masa_kerja_tahun': tahun,
        'masa_kerja_bulan': bulan,
        'gaji_lama_id': _gajiLamaId,
        'gaji_baru_id': _gajiBaruId,
        'keterangan': _keterangan.text.trim(),
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
        title: const Text('Ajukan Kenaikan Gaji Berkala'),
        content: SizedBox(
            width: 620,
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                        value: _pegawaiId,
                        decoration:
                            const InputDecoration(labelText: 'Pegawai *'),
                        isExpanded: true,
                        items: _pegawai
                            .map((p) => DropdownMenuItem(
                                value: (p['id'] as num).toInt(),
                                child: Text('${p['nama'] ?? '-'}')))
                            .toList(),
                        onChanged: (v) => setState(() => _pegawaiId = v)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _noSk,
                        decoration:
                            const InputDecoration(labelText: 'Nomor SK *')),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pilih(_tanggalSk);
                            setStateIfMounted(() => _tanggalSk = d);
                          },
                          icon: const Icon(Icons.event),
                          label: Text(
                              'Tanggal SK ${DateFormat('dd-MM-yyyy').format(_tanggalSk)}')),
                      OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pilih(_tmt);
                            setStateIfMounted(() => _tmt = d);
                          },
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(
                              'TMT ${DateFormat('dd-MM-yyyy').format(_tmt)}')),
                      OutlinedButton.icon(
                          onPressed: () async {
                            final d = await _pilih(_berikutnya);
                            setStateIfMounted(() => _berikutnya = d);
                          },
                          icon: const Icon(Icons.upcoming_outlined),
                          label: Text(
                              'Berikutnya ${DateFormat('dd-MM-yyyy').format(_berikutnya)}')),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: _tahun,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Masa kerja tahun *'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _bulan,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Masa kerja bulan (0-11) *'))),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                        value: _gajiLamaId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Gaji pokok lama *'),
                        items: _gaji
                            .map((g) => DropdownMenuItem(
                                value: (g['id'] as num).toInt(),
                                child: Text(_labelGaji(g))))
                            .toList(),
                        onChanged: (v) => setState(() => _gajiLamaId = v)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                        value: _gajiBaruId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Gaji pokok baru *'),
                        items: _gaji
                            .map((g) => DropdownMenuItem(
                                value: (g['id'] as num).toInt(),
                                child: Text(_labelGaji(g))))
                            .toList(),
                        onChanged: (v) => setState(() => _gajiBaruId = v)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _keterangan,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: 'Keterangan')),
                  ]))),
        actions: [
          TextButton(
              onPressed: _simpan ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _simpan || _memuat ? null : _kirim,
              child: Text(_simpan ? 'Menyimpan…' : 'Kirim')),
        ],
      );
}

class _KinerjaPegawaiTab extends StatefulWidget {
  const _KinerjaPegawaiTab();
  @override
  State<_KinerjaPegawaiTab> createState() => _KinerjaPegawaiTabState();
}

class _KinerjaPegawaiTabState extends State<_KinerjaPegawaiTab> {
  bool _memuat = true, _bolehKelola = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  DateTime _periode = DateTime.now();

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
      final body = {
        'tahun': _periode.year,
        'bulan': _periode.month,
        'page_size': 500,
      };
      await HrdLocalFirst.baca('hrd_kinerja_daftar', body, onData: (r) {
        setStateIfMounted(() {
          _data =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _bolehKelola = r['dariServer'] == true && r['bolehKelola'] == true;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _gantiBulan(int delta) async {
    setState(() => _periode = DateTime(_periode.year, _periode.month + delta));
    await _muat();
  }

  Future<void> _tambah() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _FormRealisasiKinerja(periode: _periode));
    if (ok == true) await _muat();
  }

  Future<void> _verifikasi(Map<String, dynamic> row) async {
    final catatan = TextEditingController();
    final lanjut = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Verifikasi Kinerja'),
              content: TextField(
                  controller: catatan,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Catatan verifikator')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Verifikasi')),
              ],
            ));
    if (lanjut != true) {
      catatan.dispose();
      return;
    }
    try {
      await ApiClient.instance.aksi('hrd_kinerja_putusan', {
        'id': row['id'],
        'verifikasi': true,
        'catatan': catatan.text.trim(),
      });
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      catatan.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => _PanelDaftar(
        header: Row(children: [
          IconButton(
              onPressed: () => _gantiBulan(-1),
              icon: const Icon(Icons.chevron_left)),
          Text(DateFormat('MMMM yyyy', 'id_ID').format(_periode),
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(
              onPressed: () => _gantiBulan(1),
              icon: const Icon(Icons.chevron_right)),
          const Spacer(),
          IconButton(onPressed: _muat, icon: const Icon(Icons.refresh)),
          FilledButton.icon(
              onPressed: _tambah,
              icon: const Icon(Icons.add_task),
              label: const Text('Catat Realisasi')),
        ]),
        memuat: _memuat,
        error: _error,
        kosong: 'Belum ada realisasi kinerja pada periode ini.',
        children: _data
            .map((r) => Card(
                    child: ListTile(
                  leading: Icon(
                      r['terverifikasi'] == true
                          ? Icons.verified
                          : Icons.pending_actions,
                      color: r['terverifikasi'] == true
                          ? Colors.green
                          : Colors.orange),
                  title: Text('${r['tugas'] ?? '-'} · ${r['pegawai'] ?? '-'}'),
                  subtitle: Text(
                      '${r['tanggal'] ?? '-'} · Kuantitas ${r['kuantitas'] ?? 0} · Waktu ${r['waktu'] ?? 0}\n'
                      '${r['keterangan'] ?? ''}${('${r['catatan'] ?? ''}').isEmpty ? '' : '\nCatatan: ${r['catatan']}'}'),
                  isThreeLine: true,
                  trailing: r['terverifikasi'] == true
                      ? const Chip(label: Text('TERVERIFIKASI'))
                      : _bolehKelola
                          ? IconButton(
                              onPressed: () => _verifikasi(r),
                              tooltip: 'Verifikasi kinerja',
                              icon: const Icon(Icons.approval_outlined))
                          : const Chip(label: Text('MENUNGGU')),
                )))
            .toList(),
      );
}

class _RiwayatPegawaiTab extends StatefulWidget {
  const _RiwayatPegawaiTab();
  @override
  State<_RiwayatPegawaiTab> createState() => _RiwayatPegawaiTabState();
}

class _RiwayatPegawaiTabState extends State<_RiwayatPegawaiTab> {
  bool _memuat = true, _bolehKelola = false;
  String? _error;
  List<Map<String, dynamic>> _pegawai = [];
  int? _pegawaiId;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _muatPegawai();
  }

  Future<void> _muatPegawai() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      await HrdLocalFirst.baca('hrd_pegawai_daftar', const {'page_size': 500},
          onData: (r) {
        setStateIfMounted(() {
          _pegawai =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final saya = (r['pegawaiSayaId'] as num?)?.toInt();
          _pegawaiId = saya ??
              (_pegawai.isEmpty ? null : (_pegawai.first['id'] as num).toInt());
        });
        if (_pegawaiId != null) _muatRiwayat(aturMemuat: false);
      });
    } catch (e) {
      _error = '$e';
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatRiwayat({bool aturMemuat = true}) async {
    if (_pegawaiId == null) return;
    if (aturMemuat) setStateIfMounted(() => _memuat = true);
    try {
      await HrdLocalFirst.baca(
          'hrd_riwayat_pegawai', {'pegawai_id': _pegawaiId}, onData: (r) {
        setStateIfMounted(() {
          _data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
          _bolehKelola = r['dariServer'] == true && r['bolehKelola'] == true;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      if (aturMemuat) setStateIfMounted(() => _memuat = false);
    }
  }

  List<Map<String, dynamic>> _rows(String key) =>
      ((_data[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _form(String jenis, [Map<String, dynamic>? row]) async {
    if (_pegawaiId == null) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _FormRiwayatPegawai(
            jenis: jenis,
            pegawaiId: _pegawaiId!,
            pegawai: _pegawai,
            data: row));
    if (ok == true) await _muatRiwayat();
  }

  Future<void> _hapus(String jenis, Map<String, dynamic> row) async {
    final ya = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                    title: const Text('Hapus riwayat?'),
                    content: Text(
                        '${row['nama'] ?? 'Data'} akan dihapus dari riwayat pegawai.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Hapus'))
                    ])) ??
        false;
    if (!ya) return;
    await ApiClient.instance
        .aksi('hrd_riwayat_hapus', {'jenis': jenis, 'id': row['id']});
    await _muatRiwayat();
  }

  Future<void> _putusanKarier(
      String jenis, Map<String, dynamic> row, bool setujui) async {
    final ya = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                    title:
                        Text(setujui ? 'Terapkan keputusan' : 'Tolak usulan'),
                    content: Text(setujui
                        ? 'Keputusan $jenis akan langsung memengaruhi profil pegawai dan tidak dapat dibatalkan dari POS.'
                        : 'Usulan $jenis akan ditandai belum diproses tanpa mengubah profil pegawai.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(setujui ? 'Terapkan' : 'Tolak'))
                    ])) ??
        false;
    if (!ya) return;
    await ApiClient.instance.aksi('hrd_karier_putusan',
        {'jenis': jenis, 'id': row['id'], 'setujui': setujui});
    await _muatRiwayat();
  }

  Widget _bagian(
      String jenis,
      String judul,
      IconData icon,
      List<Map<String, dynamic>> rows,
      String Function(Map<String, dynamic>) subtitle) {
    final dapatUbah = _bolehKelola &&
        const {
          'PENDIDIKAN',
          'PELATIHAN',
          'KELUARGA',
          'PEKERJAAN',
          'PELANGGARAN',
          'PENILAIAN'
        }.contains(jenis);
    final dapatPutus =
        _bolehKelola && const {'PANGKAT', 'MUTASI', 'PENSIUN'}.contains(jenis);
    return Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
            initiallyExpanded: true,
            leading: Icon(icon),
            title: Row(children: [
              Expanded(child: Text(judul)),
              if (dapatUbah)
                IconButton(
                    tooltip: 'Tambah $judul',
                    onPressed: () => _form(jenis),
                    icon: const Icon(Icons.add_circle_outline))
            ]),
            subtitle: Text('${rows.length} data'),
            children: rows.isEmpty
                ? const [
                    Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Belum ada data.'))
                  ]
                : rows
                    .map((row) => ListTile(
                        dense: true,
                        title: Text('${row['nama'] ?? '-'}'),
                        subtitle: Text(subtitle(row)),
                        trailing: dapatUbah
                            ? PopupMenuButton<String>(
                                onSelected: (aksi) => aksi == 'edit'
                                    ? _form(jenis, row)
                                    : _hapus(jenis, row),
                                itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'edit', child: Text('Ubah')),
                                      PopupMenuItem(
                                          value: 'hapus', child: Text('Hapus'))
                                    ])
                            : dapatPutus && row['status'] != 'DISETUJUI'
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        IconButton(
                                            tooltip: 'Tolak usulan',
                                            onPressed: () => _putusanKarier(
                                                jenis, row, false),
                                            icon: const Icon(Icons.close)),
                                        FilledButton.icon(
                                            onPressed: () => _putusanKarier(
                                                jenis, row, true),
                                            icon: const Icon(Icons.task_alt),
                                            label: const Text('Terapkan'))
                                      ])
                                : row['status'] == 'DISETUJUI'
                                    ? const Chip(label: Text('Berlaku'))
                                    : null))
                    .toList()));
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<int>(
                  value: _pegawaiId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Pegawai yang dilihat'),
                  items: _pegawai
                      .map((p) => DropdownMenuItem<int>(
                          value: (p['id'] as num).toInt(),
                          child: Text(
                              '${p['nama'] ?? '-'} · ${p['kode'] ?? '-'}')))
                      .toList(),
                  onChanged: (v) async {
                    setState(() => _pegawaiId = v);
                    await _muatRiwayat();
                  })),
          const SizedBox(width: 8),
          IconButton(onPressed: _muatRiwayat, icon: const Icon(Icons.refresh))
        ]),
        const SizedBox(height: 12),
        Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)))
                    : ListView(children: [
                        _bagian('PENDIDIKAN', 'Pendidikan',
                            Icons.school_outlined, _rows('pendidikan'), (r) {
                          final periode =
                              '${r['mulai'] ?? '-'}–${r['selesai'] ?? '-'}';
                          return '$periode · ${r['jurusan'] ?? '-'} · Ijazah ${r['nomor'] ?? '-'}';
                        }),
                        _bagian(
                            'PELATIHAN',
                            'Pelatihan & Sertifikasi',
                            Icons.workspace_premium_outlined,
                            _rows('pelatihan'), (r) {
                          return '${r['jenis'] ?? '-'} · ${r['mulai'] ?? '-'} s.d. ${r['selesai'] ?? '-'}'
                              '${r['sertifikasi'] == true ? ' · Bersertifikat' : ''}';
                        }),
                        _bagian(
                            'KELUARGA',
                            'Keluarga',
                            Icons.family_restroom_outlined,
                            _rows('keluarga'), (r) {
                          return '${r['hubungan'] ?? '-'} · ${r['tanggalLahir'] ?? '-'} · ${r['pekerjaan'] ?? '-'}';
                        }),
                        _bagian(
                            'PEKERJAAN',
                            'Riwayat Pekerjaan',
                            Icons.work_history_outlined,
                            _rows('pekerjaan'), (r) {
                          return '${r['jabatan'] ?? '-'} · ${r['mulai'] ?? '-'}–${r['selesai'] ?? '-'} · Pimpinan ${r['pimpinan'] ?? '-'}';
                        }),
                        _bagian(
                            'PANGKAT',
                            'Kenaikan Pangkat',
                            Icons.military_tech_outlined,
                            _rows('pangkat'), (r) {
                          return 'TMT ${r['tmt'] ?? '-'} · SK ${r['nomor'] ?? '-'} tanggal ${r['tanggalSk'] ?? '-'}';
                        }),
                        _bagian('MUTASI', 'Mutasi', Icons.swap_horiz_outlined,
                            _rows('mutasi'), (r) {
                          return 'TMT ${r['tmt'] ?? '-'} · ${r['status'] ?? '-'} · Surat ${r['nomor'] ?? '-'}';
                        }),
                        _bagian('PENSIUN', 'Pensiun', Icons.elderly_outlined,
                            _rows('pensiun'), (r) {
                          return 'TMT ${r['tmt'] ?? '-'} · ${r['status'] ?? '-'} · Surat ${r['nomor'] ?? '-'}';
                        }),
                        _bagian('PELANGGARAN', 'Pelanggaran & Hukuman',
                            Icons.gavel_outlined, _rows('pelanggaran'), (r) {
                          return '${r['tanggal'] ?? '-'} · ${r['aktif'] == true ? 'Aktif' : 'Selesai'} · ${r['keterangan'] ?? ''}';
                        }),
                        _bagian('PENILAIAN', 'Penilaian Pelaksanaan Pekerjaan',
                            Icons.assessment_outlined, _rows('penilaian'), (r) {
                          return 'Nilai ${r['nilai'] ?? '-'} · ${r['predikat'] ?? '-'} · Penilai ${r['penilai'] ?? '-'}';
                        }),
                      ]))
      ]));
}

class _FormRiwayatPegawai extends StatefulWidget {
  const _FormRiwayatPegawai(
      {required this.jenis,
      required this.pegawaiId,
      required this.pegawai,
      this.data});
  final String jenis;
  final int pegawaiId;
  final List<Map<String, dynamic>> pegawai;
  final Map<String, dynamic>? data;
  @override
  State<_FormRiwayatPegawai> createState() => _FormRiwayatPegawaiState();
}

class _FormRiwayatPegawaiState extends State<_FormRiwayatPegawai> {
  late final TextEditingController _nama,
      _rincian,
      _mulai,
      _selesai,
      _nomor,
      _pekerjaan,
      _keterangan;
  late final Map<String, TextEditingController> _nilai;
  bool _sertifikasi = false, _aktif = true, _simpan = false;
  int? _penilaiId, _atasanPenilaiId;

  static const _unsurPenilaian = <String, String>{
    'kesetiaan': 'Kesetiaan',
    'prestasi_kerja': 'Prestasi Kerja',
    'tanggung_jawab': 'Tanggung Jawab',
    'ketaatan': 'Ketaatan',
    'kejujuran': 'Kejujuran',
    'kerjasama': 'Kerjasama',
    'prakarsa': 'Prakarsa',
    'kepimpinan': 'Kepemimpinan',
  };

  static const _kunciDataPenilaian = <String, String>{
    'kesetiaan': 'kesetiaan',
    'prestasi_kerja': 'prestasiKerja',
    'tanggung_jawab': 'tanggungJawab',
    'ketaatan': 'ketaatan',
    'kejujuran': 'kejujuran',
    'kerjasama': 'kerjasama',
    'prakarsa': 'prakarsa',
    'kepimpinan': 'kepimpinan',
  };

  bool get _tanggal =>
      widget.jenis == 'PELATIHAN' || widget.jenis == 'PELANGGARAN';
  bool get _keluarga => widget.jenis == 'KELUARGA';
  bool get _pelanggaran => widget.jenis == 'PELANGGARAN';
  bool get _penilaian => widget.jenis == 'PENILAIAN';

  @override
  void initState() {
    super.initState();
    final d = widget.data ?? const <String, dynamic>{};
    _nama = TextEditingController(text: '${d['nama'] ?? ''}');
    _rincian = TextEditingController(
        text:
            '${d[_keluarga ? 'hubungan' : widget.jenis == 'PEKERJAAN' ? 'jabatan' : 'jurusan'] ?? ''}');
    _mulai = TextEditingController(
        text:
            '${d[_keluarga ? 'tanggalLahir' : _pelanggaran ? 'tanggal' : 'mulai'] ?? ''}');
    _selesai = TextEditingController(text: '${d['selesai'] ?? ''}');
    _nomor = TextEditingController(
        text:
            '${d[_keluarga ? 'kelamin' : widget.jenis == 'PEKERJAAN' ? 'pimpinan' : 'nomor'] ?? ''}');
    _pekerjaan = TextEditingController(text: '${d['pekerjaan'] ?? ''}');
    _keterangan = TextEditingController(text: '${d['keterangan'] ?? ''}');
    _sertifikasi = d['sertifikasi'] == true;
    _aktif = d['aktif'] != false;
    final penilaiId = (d['penilaiId'] as num?)?.toInt();
    final atasanPenilaiId = (d['atasanPenilaiId'] as num?)?.toInt();
    _penilaiId =
        widget.pegawai.any((p) => p['id'] == penilaiId) ? penilaiId : null;
    _atasanPenilaiId = widget.pegawai.any((p) => p['id'] == atasanPenilaiId)
        ? atasanPenilaiId
        : null;
    _nilai = {
      for (final kunci in _unsurPenilaian.keys)
        kunci: TextEditingController(
            text: '${d[_kunciDataPenilaian[kunci]] ?? ''}')
    };
  }

  @override
  void dispose() {
    for (final c in [
      _nama,
      _rincian,
      _mulai,
      _selesai,
      _nomor,
      _pekerjaan,
      _keterangan,
      ..._nilai.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kirim() async {
    if (_nama.text.trim().isEmpty) return;
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('hrd_riwayat_simpan', {
        if (widget.data?['id'] != null) 'id': widget.data!['id'],
        'jenis': widget.jenis,
        'pegawai_id': widget.pegawaiId,
        'nama': _nama.text.trim(),
        'rincian': _rincian.text.trim(),
        'mulai': _mulai.text.trim(),
        'selesai': _selesai.text.trim(),
        'nomor': _nomor.text.trim(),
        'pekerjaan': _pekerjaan.text.trim(),
        'sertifikasi': _sertifikasi,
        'aktif': _aktif,
        if (_penilaian) 'penilai_id': _penilaiId,
        if (_penilaian) 'atasan_penilai_id': _atasanPenilaiId,
        if (_penilaian)
          for (final item in _nilai.entries)
            item.key: double.tryParse(item.value.text.replaceAll(',', '.')),
        'keterangan': _keterangan.text.trim(),
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

  String get _judul =>
      const {
        'PENDIDIKAN': 'Pendidikan',
        'PELATIHAN': 'Pelatihan / Sertifikasi',
        'KELUARGA': 'Keluarga',
        'PEKERJAAN': 'Riwayat Pekerjaan',
        'PELANGGARAN': 'Pelanggaran & Hukuman',
        'PENILAIAN': 'Penilaian Pelaksanaan Pekerjaan'
      }[widget.jenis] ??
      widget.jenis;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.data == null ? 'Tambah' : 'Ubah'} $_judul'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _nama,
                  decoration: InputDecoration(
                      labelText: _keluarga
                          ? 'Nama anggota keluarga *'
                          : _penilaian
                              ? 'Nama / periode penilaian *'
                              : 'Nama *')),
              const SizedBox(height: 10),
              if (_penilaian) ...[
                DropdownButtonFormField<int>(
                    value: _penilaiId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Pejabat penilai *'),
                    items: widget.pegawai
                        .map((p) => DropdownMenuItem<int>(
                            value: (p['id'] as num).toInt(),
                            child: Text('${p['nama'] ?? '-'}')))
                        .toList(),
                    onChanged: (v) => setState(() => _penilaiId = v)),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                    value: _atasanPenilaiId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Atasan pejabat penilai *'),
                    items: widget.pegawai
                        .map((p) => DropdownMenuItem<int>(
                            value: (p['id'] as num).toInt(),
                            child: Text('${p['nama'] ?? '-'}')))
                        .toList(),
                    onChanged: (v) => setState(() => _atasanPenilaiId = v)),
                const SizedBox(height: 10),
                ..._unsurPenilaian.entries.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                        controller: _nilai[item.key],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: '${item.value} (0–100) *')))),
              ] else if (!_pelanggaran) ...[
                TextField(
                    controller: _rincian,
                    decoration: InputDecoration(
                        labelText: _keluarga
                            ? 'Hubungan'
                            : widget.jenis == 'PEKERJAAN'
                                ? 'Jabatan'
                                : 'Jurusan / bidang')),
                const SizedBox(height: 10),
              ],
              if (!_penilaian)
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _mulai,
                          decoration: InputDecoration(
                              labelText: _keluarga
                                  ? 'Tanggal lahir (yyyy-MM-dd)'
                                  : _pelanggaran
                                      ? 'Tanggal pelanggaran (yyyy-MM-dd)'
                                      : _tanggal
                                          ? 'Tanggal mulai (yyyy-MM-dd)'
                                          : 'Tahun mulai'))),
                  if (!_keluarga && !_pelanggaran) ...[
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _selesai,
                            decoration: InputDecoration(
                                labelText: _tanggal
                                    ? 'Tanggal selesai (yyyy-MM-dd)'
                                    : 'Tahun selesai')))
                  ]
                ]),
              if (!_pelanggaran && !_penilaian) ...[
                const SizedBox(height: 10),
                TextField(
                    controller: _nomor,
                    decoration: InputDecoration(
                        labelText: _keluarga
                            ? 'Jenis kelamin'
                            : widget.jenis == 'PEKERJAAN'
                                ? 'Nama pimpinan'
                                : 'Nomor ijazah / sertifikat')),
              ],
              if (_keluarga && !_penilaian) ...[
                const SizedBox(height: 10),
                TextField(
                    controller: _pekerjaan,
                    decoration: const InputDecoration(labelText: 'Pekerjaan'))
              ],
              if (widget.jenis == 'PELATIHAN' && !_penilaian)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _sertifikasi,
                    onChanged: (v) => setState(() => _sertifikasi = v == true),
                    title: const Text('Pelatihan bersertifikat')),
              if (_pelanggaran && !_penilaian)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _aktif,
                    onChanged: (v) => setState(() => _aktif = v == true),
                    title: const Text('Pelanggaran / hukuman masih aktif')),
              const SizedBox(height: 10),
              TextField(
                  controller: _keterangan,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Keterangan')),
            ]))),
        actions: [
          TextButton(
              onPressed: _simpan ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _simpan ? null : _kirim,
              child: Text(_simpan ? 'Menyimpan…' : 'Simpan'))
        ],
      );
}

class _MasterHrdTab extends StatefulWidget {
  const _MasterHrdTab();

  @override
  State<_MasterHrdTab> createState() => _MasterHrdTabState();
}

class _MasterHrdTabState extends State<_MasterHrdTab> {
  bool _memuat = true;
  String? _error;
  String _cakupan = '';
  Map<String, List<Map<String, dynamic>>> _kelompok = {};

  static const _judul = <String, (String, IconData)>{
    'unitKerja': ('Unit Kerja', Icons.account_tree_outlined),
    'departemen': ('Departemen Payroll', Icons.apartment_outlined),
    'jabatan': ('Jabatan Fungsional', Icons.workspace_premium_outlined),
    'levelJabatan': ('Level Jabatan', Icons.stairs_outlined),
    'golongan': ('Golongan & Pangkat', Icons.military_tech_outlined),
    'tipePegawai': ('Tipe Pegawai', Icons.groups_outlined),
    'jenisCuti': ('Jenis Cuti & Izin', Icons.event_available_outlined),
    'jenisShift': ('Pola Shift Pegawai', Icons.calendar_month_outlined),
    'waktuShift': ('Jam Shift', Icons.schedule_outlined),
    'liburNasional': ('Libur Nasional', Icons.flag_outlined),
    'liburRutin': ('Libur Rutin', Icons.weekend_outlined),
  };

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
      await HrdLocalFirst.baca('hrd_master_daftar', const {}, onData: (r) {
        final data = <String, List<Map<String, dynamic>>>{};
        for (final key in _judul.keys) {
          data[key] = ((r[key] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        setStateIfMounted(() {
          _kelompok = data;
          _cakupan = '${r['cakupan'] ?? ''}';
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  String _rincian(String key, Map<String, dynamic> row) {
    switch (key) {
      case 'unitKerja':
        return 'Induk: ${row['parent']?.toString().trim().isEmpty == false ? row['parent'] : '-'} · Level ${row['level'] ?? '-'}';
      case 'golongan':
        return '${row['kode'] ?? '-'} · Pangkat ${row['pangkat']?.toString().trim().isEmpty == false ? row['pangkat'] : '-'}';
      case 'jabatan':
        return '${row['kode'] ?? '-'} · Level ${row['level'] ?? '-'} · Induk ${row['parent']?.toString().trim().isEmpty == false ? row['parent'] : '-'}';
      case 'tipePegawai':
        return '${row['kode'] ?? '-'} · Presensi ${row['presensi'] == true ? 'Ya' : 'Tidak'} · Lembur ${row['lembur'] == true ? 'Ya' : 'Tidak'} · Konsumsi ${row['konsumsi'] == true ? 'Ya' : 'Tidak'}';
      case 'jenisCuti':
        return '${row['kode'] ?? '-'} · ${row['keterangan'] ?? ''}';
      case 'jenisShift':
        return '${row['jumlahShift'] ?? 0} shift · ${row['berlakuMulai'] ?? '-'} s.d. ${row['berlakuSampai']?.toString().isEmpty == false ? row['berlakuSampai'] : '-'} · ${row['berotasi'] == true ? 'Rotasi' : 'Tetap'}';
      case 'waktuShift':
        return '${row['kode'] ?? '-'} · ${row['mulai'] ?? '-'}–${row['sampai'] ?? '-'} · ${row['jam'] ?? 0} jam';
      case 'liburNasional':
        return '${row['tanggal'] ?? '-'}${row['sampai']?.toString().isEmpty == false ? ' s.d. ${row['sampai']}' : ''}${row['liburPanjang'] == true ? ' · Libur panjang' : ''}';
      case 'liburRutin':
        return 'Nomor hari ${row['hari'] ?? '-'} · ${row['libur'] == true ? 'Libur' : 'Hari kerja'}';
      default:
        return '${row['keterangan'] ?? ''}';
    }
  }

  @override
  Widget build(BuildContext context) => _PanelDaftar(
        header: Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_cakupan.isEmpty
                          ? 'Master organisasi dan jadwal kerja dari modul ZK.'
                          : _cakupan)),
                  IconButton(
                      tooltip: 'Muat ulang master HRD',
                      onPressed: _muat,
                      icon: const Icon(Icons.refresh)),
                ]))),
        memuat: _memuat,
        error: _error,
        kosong: 'Belum ada master HRD yang tersedia.',
        children: _judul.entries.map((entry) {
          final rows = _kelompok[entry.key] ?? const [];
          return Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                  leading: Icon(entry.value.$2),
                  title: Text(entry.value.$1),
                  subtitle: Text('${rows.length} data dari modul ZK'),
                  children: rows.isEmpty
                      ? const [ListTile(title: Text('Belum ada data.'))]
                      : rows
                          .map((row) => ListTile(
                                dense: true,
                                title: Text('${row['nama'] ?? '-'}'),
                                subtitle: Text(_rincian(entry.key, row)),
                              ))
                          .toList()));
        }).toList(),
      );
}

class _FormRealisasiKinerja extends StatefulWidget {
  const _FormRealisasiKinerja({required this.periode});
  final DateTime periode;
  @override
  State<_FormRealisasiKinerja> createState() => _FormRealisasiKinerjaState();
}

class _FormRealisasiKinerjaState extends State<_FormRealisasiKinerja> {
  List<Map<String, dynamic>> _tugas = [];
  int? _tugasId;
  DateTime _tanggal = DateTime.now();
  final _kuantitas = TextEditingController(text: '1'),
      _waktu = TextEditingController(text: '0'),
      _biaya = TextEditingController(text: '0'),
      _keterangan = TextEditingController();
  bool _memuat = true, _simpan = false;

  @override
  void initState() {
    super.initState();
    _muatTugas();
  }

  @override
  void dispose() {
    _kuantitas.dispose();
    _waktu.dispose();
    _biaya.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _muatTugas() async {
    try {
      await HrdLocalFirst.baca('hrd_tugas_kinerja_daftar', const {},
          onData: (r) {
        setStateIfMounted(() {
          _tugas =
              ((r['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
          if (_tugas.isNotEmpty) {
            _tugasId = (_tugas.first['id'] as num).toInt();
            _kuantitas.text = '${_tugas.first['kuantitasDefault'] ?? 1}';
            _waktu.text = '${_tugas.first['waktuDefault'] ?? 0}';
          }
        });
      });
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  void _pilihTugas(int? id) {
    Map<String, dynamic>? tugas;
    for (final kandidat in _tugas) {
      if ((kandidat['id'] as num?)?.toInt() == id) {
        tugas = kandidat;
        break;
      }
    }
    setState(() {
      _tugasId = id;
      if (tugas != null) {
        _kuantitas.text = '${tugas['kuantitasDefault'] ?? 1}';
        _waktu.text = '${tugas['waktuDefault'] ?? 0}';
      }
    });
  }

  Future<void> _kirim() async {
    final kuantitas =
        double.tryParse(_kuantitas.text.replaceAll(',', '.')) ?? -1;
    final waktu = double.tryParse(_waktu.text.replaceAll(',', '.')) ?? -1;
    final biaya =
        double.tryParse(_biaya.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? -1;
    if (_tugasId == null ||
        kuantitas < 0 ||
        waktu < 0 ||
        biaya < 0 ||
        _keterangan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Tugas, nilai realisasi, dan keterangan wajib diisi.')));
      return;
    }
    setState(() => _simpan = true);
    try {
      await ApiClient.instance.aksi('hrd_kinerja_simpan', {
        'tugas_id': _tugasId,
        'tanggal': DateFormat('yyyy-MM-dd').format(_tanggal),
        'kuantitas': kuantitas,
        'waktu': waktu,
        'biaya': biaya,
        'keterangan': _keterangan.text.trim(),
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
        title: const Text('Catat Realisasi Kinerja'),
        content: SizedBox(
            width: 560,
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                        value: _tugasId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Tugas jabatan *'),
                        items: _tugas
                            .map((t) => DropdownMenuItem(
                                value: (t['id'] as num).toInt(),
                                child: Text('${t['nama'] ?? '-'}')))
                            .toList(),
                        onChanged: _pilihTugas),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate: _tanggal,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100));
                          if (d != null) setStateIfMounted(() => _tanggal = d);
                        },
                        icon: const Icon(Icons.event),
                        label: Text(
                            'Tanggal ${DateFormat('dd-MM-yyyy').format(_tanggal)}')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: _kuantitas,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Kuantitas'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _waktu,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Waktu'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _biaya,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Biaya'))),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _keterangan,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Keterangan realisasi *')),
                  ]))),
        actions: [
          TextButton(
              onPressed: _simpan ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _simpan || _memuat ? null : _kirim,
              child: Text(_simpan ? 'Menyimpan…' : 'Simpan')),
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
