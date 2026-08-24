import 'dart:async';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/safe_state.dart';
import '../../services/layar_farmasi_launcher.dart';
import 'pos_help.dart';

/// Konsol petugas untuk antrean obat jadi/racikan yang disiarkan ke pasien.
class AntreanFarmasiScreen extends StatefulWidget {
  const AntreanFarmasiScreen({super.key});

  @override
  State<AntreanFarmasiScreen> createState() => _AntreanFarmasiScreenState();
}

class _AntreanFarmasiScreenState extends State<AntreanFarmasiScreen> {
  Timer? _poll;
  bool _memuat = true;
  bool _mengubah = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _muat();
    _poll =
        Timer.periodic(const Duration(seconds: 5), (_) => _muat(diam: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _muat({bool diam = false}) async {
    if (!diam) setStateIfMounted(() => _memuat = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('apotik_antrean_farmasi_list', {
        'toko_id': Sesi.instance.tokoId,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _error = null;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _error = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _ubahStatus(Map<String, dynamic> a, String status) async {
    if (_mengubah) return;
    setStateIfMounted(() => _mengubah = true);
    try {
      await ApiClient.instance.aksi('apotik_antrean_farmasi_status', {
        'toko_id': Sesi.instance.tokoId,
        'id': a['id'],
        'status': status,
      });
      await _muat(diam: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _mengubah = false);
    }
  }

  Future<void> _hapus(Map<String, dynamic> a) async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus antrean?'),
        content: Text(
            'Antrean ${a['kodeAntrean']} • ${a['namaPasien']} akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (setuju != true) return;
    try {
      await ApiClient.instance.aksi('apotik_antrean_farmasi_hapus', {
        'toko_id': Sesi.instance.tokoId,
        'id': a['id'],
      });
      await _muat(diam: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _form([Map<String, dynamic>? awal]) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormAntreanFarmasi(awal: awal),
    );
    if (hasil == null || !mounted) return;
    try {
      await ApiClient.instance.aksi('apotik_antrean_farmasi_simpan', {
        'toko_id': Sesi.instance.tokoId,
        ...hasil,
      });
      await _muat(diam: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final aktif = _data.where((e) => e['status'] != 'SELESAI').toList();
    final selesai = _data.where((e) => e['status'] == 'SELESAI').toList();
    return AppShell(
      menuAktif: MenuEBisnis.berandaApotik,
      judul: 'Antrean & Layar Farmasi',
      subjudul: 'Siaran obat jadi dan racikan untuk pasien/keluarga pasien',
      scrollable: false,
      actionsAppBar: [
        PosHelp.button(context, 'apotik_antrean_farmasi', compact: true),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat Ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader: Wrap(spacing: 8, runSpacing: 8, children: [
        PosHelp.button(context, 'apotik_antrean_farmasi'),
        OutlinedButton.icon(
          onPressed: () => pilihDanBukaLayarFarmasi(context),
          icon: const Icon(Icons.connected_tv_outlined),
          label: const Text('Buka Layar Publik'),
        ),
        FilledButton.icon(
          onPressed: () => _form(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah Antrean'),
        ),
      ]),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data.isEmpty
              ? Center(child: Text(_error!))
              : Column(children: [
                  _ringkasan(aktif),
                  const SizedBox(height: 10),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _muat,
                      child: ListView(
                        children: [
                          if (_error != null)
                            AppInfoBanner(
                                icon: Icons.cloud_off,
                                color: AppColors.warning,
                                text:
                                    'Pembaruan otomatis gagal. Data terakhir tetap ditampilkan.'),
                          if (aktif.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(48),
                              child: Column(children: [
                                Icon(Icons.hourglass_empty,
                                    size: 52, color: Colors.blueGrey),
                                SizedBox(height: 12),
                                Text('Belum ada antrean aktif',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17)),
                                SizedBox(height: 5),
                                Text(
                                    'Tambahkan pasien atau muat data dari resep untuk mulai menyiarkan ke layar publik.'),
                              ]),
                            ),
                          ...aktif.map(_kartu),
                          if (selesai.isNotEmpty) ...[
                            const Padding(
                                padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                                child: Text('SELESAI HARI INI',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.blueGrey))),
                            ...selesai.map(_kartu),
                          ],
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ]),
    );
  }

  Widget _ringkasan(List<Map<String, dynamic>> aktif) {
    int hitung(String s) => aktif.where((e) => e['status'] == s).length;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      _stat('Menunggu', hitung('MENUNGGU'), Icons.hourglass_top,
          const Color(0xFF64748B)),
      _stat('Disiapkan', hitung('DISIAPKAN'), Icons.science_outlined,
          const Color(0xFFF59E0B)),
      _stat('Siap Diambil', hitung('SIAP'), Icons.notifications_active_outlined,
          const Color(0xFF16A34A)),
      _stat('Total Aktif', aktif.length, Icons.people_alt_outlined,
          const Color(0xFF0284C7)),
    ]);
  }

  Widget _stat(String label, int nilai, IconData icon, Color warna) =>
      Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: warna.withValues(alpha: .08),
            border: Border.all(color: warna.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: warna),
          const SizedBox(width: 9),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$nilai',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: warna)),
            Text(label, style: const TextStyle(fontSize: 11.5))
          ])
        ]),
      );

  Widget _kartu(Map<String, dynamic> a) {
    final status = '${a['status']}';
    final obat = ((a['obat'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final warna = switch (status) {
      'DISIAPKAN' => const Color(0xFFF59E0B),
      'SIAP' => const Color(0xFF16A34A),
      'SELESAI' => const Color(0xFF94A3B8),
      _ => const Color(0xFF64748B),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 66,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                  color: warna, borderRadius: BorderRadius.circular(10)),
              child: Text('${a['kodeAntrean']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${a['namaPasien']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15)),
                      _chip(
                          '${a['jenis']}',
                          a['jenis'] == 'RACIKAN'
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF0284C7)),
                      _chip(status, warna),
                    ]),
                Text(
                    'RM ${('${a['nomorRekamMedis']}').isEmpty ? '-' : a['nomorRekamMedis']} • masuk ${a['waktuMasuk']} • ${('${a['loket']}').isEmpty ? 'loket belum ditentukan' : a['loket']}',
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.blueGrey)),
                if (obat.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: obat
                              .map((o) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                      '${o['nama'] ?? '-'}${('${o['jumlah'] ?? ''}').isEmpty ? '' : ' × ${o['jumlah']}'}',
                                      style: const TextStyle(fontSize: 10.5))))
                              .toList())),
              ])),
          const SizedBox(width: 8),
          Wrap(spacing: 5, runSpacing: 5, children: [
            if (status == 'MENUNGGU')
              FilledButton.tonal(
                  onPressed:
                      _mengubah ? null : () => _ubahStatus(a, 'DISIAPKAN'),
                  child: const Text('Siapkan')),
            if (status == 'DISIAPKAN')
              FilledButton(
                  onPressed: _mengubah ? null : () => _ubahStatus(a, 'SIAP'),
                  child: const Text('Panggil')),
            if (status == 'SIAP')
              FilledButton.tonal(
                  onPressed: _mengubah ? null : () => _ubahStatus(a, 'SELESAI'),
                  child: const Text('Selesai')),
            IconButton(
                onPressed: () => _form(a),
                tooltip: 'Ubah',
                icon: const Icon(Icons.edit_outlined)),
            IconButton(
                onPressed: () => _hapus(a),
                tooltip: 'Hapus',
                icon: const Icon(Icons.delete_outline, color: Colors.red)),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(String teks, Color warna) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: warna.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12)),
      child: Text(teks,
          style: TextStyle(
              color: warna, fontSize: 10, fontWeight: FontWeight.w800)));
}

class _FormAntreanFarmasi extends StatefulWidget {
  final Map<String, dynamic>? awal;
  const _FormAntreanFarmasi({this.awal});

  @override
  State<_FormAntreanFarmasi> createState() => _FormAntreanFarmasiState();
}

class _FormAntreanFarmasiState extends State<_FormAntreanFarmasi> {
  late final TextEditingController _nama;
  late final TextEditingController _rm;
  late final TextEditingController _kode;
  late final TextEditingController _loket;
  late final TextEditingController _catatan;
  late final TextEditingController _obat;
  String _jenis = 'JADI';
  int? _resepId;
  bool _memuatResep = false;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _nama = TextEditingController(text: '${a?['namaPasien'] ?? ''}');
    _rm = TextEditingController(text: '${a?['nomorRekamMedis'] ?? ''}');
    _kode = TextEditingController(text: '${a?['kodeAntrean'] ?? ''}');
    _loket = TextEditingController(text: '${a?['loket'] ?? ''}');
    _catatan = TextEditingController(text: '${a?['catatanPublik'] ?? ''}');
    final obat = ((a?['obat'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map));
    _obat = TextEditingController(
        text: obat
            .map((o) =>
                '${o['nama'] ?? ''}${('${o['jumlah'] ?? ''}').isEmpty ? '' : ' | ${o['jumlah']}'}')
            .join('\n'));
    _jenis = '${a?['jenis'] ?? 'JADI'}';
    _resepId = (a?['resepId'] as num?)?.toInt();
  }

  @override
  void dispose() {
    for (final c in [_nama, _rm, _kode, _loket, _catatan, _obat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pilihResep() async {
    setState(() => _memuatResep = true);
    try {
      final list = await ApiClient.instance.aksi(
          'apotik_resep_list', {'hanya_menunggu': true, 'page_size': 100});
      if (!mounted) return;
      final data = ((list['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final pilih = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Resep Menunggu'),
          content: SizedBox(
              width: 520,
              height: 420,
              child: data.isEmpty
                  ? const Center(child: Text('Tidak ada resep menunggu.'))
                  : ListView.separated(
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = data[i];
                        return ListTile(
                            title: Text('${r['kode']}'),
                            subtitle: Text('${r['jumlahBaris']} baris'),
                            onTap: () => Navigator.pop(ctx, r));
                      })),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Batal'))
          ],
        ),
      );
      if (pilih == null) return;
      final detail = await ApiClient.instance
          .aksi('apotik_resep_detail', {'resep_id': pilih['id']});
      final rows = ((detail['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final adaJadi = rows.any((e) => e['racikan'] != true);
      final adaRacikan = rows.any((e) => e['racikan'] == true);
      setState(() {
        _resepId = (pilih['id'] as num).toInt();
        _kode.text = '${pilih['kode']}';
        _jenis = adaJadi && adaRacikan
            ? 'CAMPURAN'
            : (adaRacikan ? 'RACIKAN' : 'JADI');
        _obat.text = rows
            .map((e) => '${e['nama'] ?? '-'} | ${e['jumlah'] ?? ''}')
            .join('\n');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _memuatResep = false);
    }
  }

  List<Map<String, dynamic>> _uraiObat() => _obat.text
      .split('\n')
      .map((baris) {
        final bagian = baris.split('|');
        return {
          'nama': bagian.first.trim(),
          if (bagian.length > 1 && bagian[1].trim().isNotEmpty)
            'jumlah': bagian[1].trim()
        };
      })
      .where((e) => '${e['nama']}'.isNotEmpty)
      .toList();

  void _simpan() {
    if (_nama.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama pasien wajib diisi.')));
      return;
    }
    Navigator.pop(context, {
      if (widget.awal?['id'] != null) 'id': widget.awal!['id'],
      if (_resepId != null) 'resep_id': _resepId,
      'nama_pasien': _nama.text.trim(),
      'nomor_rekam_medis': _rm.text.trim(),
      'kode_antrean': _kode.text.trim(),
      'jenis': _jenis,
      'loket': _loket.text.trim(),
      'catatan_publik': _catatan.text.trim(),
      'obat': _uraiObat(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.awal == null
            ? 'Tambah Antrean Farmasi'
            : 'Ubah Antrean Farmasi'),
        content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
                child: Column(children: [
              AppInfoBanner(
                  icon: Icons.privacy_tip_outlined,
                  color: AppColors.info,
                  text:
                      'Nama dan nomor RM akan otomatis disamarkan pada layar publik. Jangan masukkan diagnosis, alamat, nomor telepon, atau informasi sensitif ke catatan publik.'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _nama,
                        decoration: const InputDecoration(
                            labelText: 'Nama pasien *',
                            border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _rm,
                        decoration: const InputDecoration(
                            labelText: 'Nomor rekam medis',
                            border: OutlineInputBorder())))
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _kode,
                        decoration: const InputDecoration(
                            labelText: 'Kode antrean (otomatis bila kosong)',
                            border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(
                    child: DropdownButtonFormField<String>(
                        value: _jenis,
                        decoration: const InputDecoration(
                            labelText: 'Jenis', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(
                              value: 'JADI', child: Text('Obat Jadi')),
                          DropdownMenuItem(
                              value: 'RACIKAN', child: Text('Obat Racikan')),
                          DropdownMenuItem(
                              value: 'CAMPURAN', child: Text('Jadi + Racikan'))
                        ],
                        onChanged: (v) => setState(() => _jenis = v!)))
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _loket,
                        decoration: const InputDecoration(
                            labelText: 'Loket penyerahan',
                            hintText: 'Contoh: Loket 2',
                            border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                    onPressed: _memuatResep ? null : _pilihResep,
                    icon: _memuatResep
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.description_outlined),
                    label: Text(_resepId == null
                        ? 'Muat dari Resep'
                        : 'Resep $_resepId'))
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: _obat,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                      labelText: 'Daftar obat publik',
                      helperText:
                          'Satu baris per obat: Nama obat | jumlah. Jangan tulis diagnosis.',
                      border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: _catatan,
                  maxLength: 240,
                  decoration: const InputDecoration(
                      labelText: 'Catatan publik (opsional)',
                      hintText: 'Contoh: Mohon siapkan kartu identitas',
                      border: OutlineInputBorder())),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton.icon(
              onPressed: _simpan,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Simpan'))
        ],
      );
}
