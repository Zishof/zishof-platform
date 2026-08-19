import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

/// Konfigurasi Kode Akun untuk POS Desktop/Android -- padanan layar ZK
/// `pages/master/akunting/akun.zul` yang dijadikan RUJUKAN bentuk datanya.
///
/// Empat tab: Akun (pohon), Daftar Akun (datar), Bank, dan Jenis Transaksi.
/// Tab Akun menyediakan unduh Excel (seluruh kolom + kode induk) dan unggah
/// Excel untuk membuat/memperbarui akun secara massal.
class KodeAkunScreen extends StatefulWidget {
  const KodeAkunScreen({super.key});

  @override
  State<KodeAkunScreen> createState() => _KodeAkunScreenState();
}

class _KodeAkunScreenState extends State<KodeAkunScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _memuat = true;
  String? _galat;
  String _cari = '';
  bool _sibuk = false;

  List<Map<String, dynamic>> _akun = [];
  List<Map<String, dynamic>> _bank = [];
  List<Map<String, dynamic>> _jenisTransaksi = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    // Label & sasaran tombol unduh/unggah mengikuti tab aktif, jadi tampilan
    // harus dibangun ulang setiap tab berpindah.
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setStateIfMounted(() {});
    });
    _muat();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final body = _cari.trim().isEmpty ? <String, dynamic>{} : {'cari': _cari.trim()};
      final akun = await ApiClient.instance.aksi('kode_akun_daftar', body);
      final bank = await ApiClient.instance.aksi('kode_akun_bank', body);
      final jt = await ApiClient.instance.aksi('kode_akun_jenis_transaksi', body);
      if (!mounted) return;
      setStateIfMounted(() {
        _akun = ((akun['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _bank = ((bank['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _jenisTransaksi = ((jt['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  /// Peta id -> kode akun, dipakai mengisi kolom "Kode Induk" saat mengunduh
  /// supaya berkasnya bisa langsung diunggah kembali tanpa penyuntingan manual.
  Map<String, String> get _kodeById {
    final peta = <String, String>{};
    for (final a in _akun) {
      peta['${a['id']}'] = '${a['kode'] ?? ''}';
    }
    return peta;
  }

  // ---- Definisi unduh/unggah per tab -------------------------------------
  // Urutan kolom di bawah menjadi KONTRAK berkas Excel: hasil unduh dapat
  // langsung disunting lalu diunggah kembali tanpa penyesuaian manual.
  // Tab 0 (Akun) dan 1 (Daftar Akun) memakai definisi sama; datanya sama,
  // hanya tampilannya yang berbeda.

  String get _defJudul => _tab.index == 2
      ? 'Bank'
      : (_tab.index == 3 ? 'Jenis Transaksi' : 'Akun');

  String get _defAksiImpor => _tab.index == 2
      ? 'kode_akun_bank_impor'
      : (_tab.index == 3 ? 'kode_akun_jenis_transaksi_impor' : 'kode_akun_impor');

  List<String> get _defKolom {
    if (_tab.index == 2) {
      return const ['Nama Bank', 'Keterangan', 'Kode Akun', 'Aktif'];
    }
    if (_tab.index == 3) {
      return const ['Kode', 'Nama', 'Keterangan', 'Kode Akun', 'Aktif'];
    }
    return const ['Kode', 'Nama', 'Keterangan', 'Posisi', 'Grup Akun', 'Kode Induk'];
  }

  List<List<String>> _defBaris() {
    if (_tab.index == 2) {
      return _bank
          .map((b) => [
                '${b['nama'] ?? ''}',
                '${b['keterangan'] ?? ''}',
                '${b['akunKode'] ?? ''}',
                b['aktif'] == true ? 'Ya' : 'Tidak',
              ])
          .toList();
    }
    if (_tab.index == 3) {
      return _jenisTransaksi
          .map((t) => [
                '${t['kode'] ?? ''}',
                '${t['nama'] ?? ''}',
                '${t['keterangan'] ?? ''}',
                '${t['akunKode'] ?? ''}',
                t['aktif'] == true ? 'Ya' : 'Tidak',
              ])
          .toList();
    }
    final peta = _kodeById;
    return _akun
        .map((a) => [
              '${a['kode'] ?? ''}',
              '${a['nama'] ?? ''}',
              '${a['keterangan'] ?? ''}',
              '${a['posisi'] ?? ''}',
              '${a['grupAkun'] ?? ''}',
              a['parentId'] == null ? '' : (peta['${a['parentId']}'] ?? ''),
            ])
        .toList();
  }

  Map<String, dynamic> _defKeBaris(List<String> r) {
    String k(int i) => r.length > i ? r[i] : '';
    if (_tab.index == 2) {
      return {'nama': k(0), 'keterangan': k(1), 'kodeAkun': k(2), 'aktif': k(3)};
    }
    if (_tab.index == 3) {
      return {
        'kode': k(0),
        'nama': k(1),
        'keterangan': k(2),
        'kodeAkun': k(3),
        'aktif': k(4)
      };
    }
    return {
      'kode': k(0),
      'nama': k(1),
      'keterangan': k(2),
      'posisi': k(3),
      'grupAkun': k(4),
      'kodeParent': k(5)
    };
  }

  Future<void> _unduhAkun() async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final bytes = buildSimpleXlsx(
        sheetName: _defJudul,
        headers: _defKolom,
        rows: _defBaris(),
      );
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan $_defJudul',
          fileName:
              '${_defJudul.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          bytes: bytes);
      if (path != null) await File(path).writeAsBytes(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunduh: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _unggahAkun() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final raw = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (raw == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berkas Excel tidak dapat dibaca.')));
      }
      return;
    }
    final rows = readSimpleXlsx(Uint8List.fromList(raw));
    final baris = <Map<String, dynamic>>[];
    for (final r in rows.skip(1)) {
      final bersih = r.map((e) => e.trim()).toList();
      if (bersih.every((e) => e.isEmpty)) continue;
      baris.add(_defKeBaris(bersih));
    }
    if (baris.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada baris berisi di berkas itu.')));
      }
      return;
    }
    if (!mounted) return;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unggah $_defJudul'),
        content: Text('${baris.length} baris akan diproses. Data yang belum ada '
            'akan DIBUAT, yang sudah ada akan DIPERBARUI. Tidak ada data yang dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('Proses')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil =
          await ApiClient.instance.aksi(_defAksiImpor, {'baris': baris});
      if (!mounted) return;
      final masalah = ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Hasil Unggah $_defJudul'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dibuat: ${hasil['dibuat'] ?? 0}'),
                Text('Diperbarui: ${hasil['diperbarui'] ?? 0}'),
                Text('Ditolak: ${hasil['ditolak'] ?? 0}'),
                if (masalah.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Baris yang ditolak:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final m in masalah)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('• $m', style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
          ],
        ),
      );
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunggah: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Pohon akun: baris anak diberi indentasi sesuai kedalaman induknya,
  /// meniru tampilan hierarki pada layar ZK.
  List<Map<String, dynamic>> get _akunPohon {
    final anakDari = <String, List<Map<String, dynamic>>>{};
    final akar = <Map<String, dynamic>>[];
    final semuaId = _akun.map((a) => '${a['id']}').toSet();
    for (final a in _akun) {
      final p = a['parentId'];
      if (p == null || !semuaId.contains('$p')) {
        akar.add(a);
      } else {
        anakDari.putIfAbsent('$p', () => []).add(a);
      }
    }
    final hasil = <Map<String, dynamic>>[];
    void telusuri(Map<String, dynamic> node, int level) {
      hasil.add({...node, '_level': level});
      for (final anak in (anakDari['${node['id']}'] ?? const [])) {
        telusuri(anak, level + 1);
      }
    }
    for (final a in akar) {
      telusuri(a, 0);
    }
    return hasil;
  }

  Widget _tabelAkun({required bool pohon}) {
    final data = pohon ? _akunPohon : _akun;
    return AppDataTable(
      minWidth: 900,
      emptyText: 'Tidak ada akun untuk filter ini.',
      columns: const [
        AppTableColumn('Akun', flex: 4),
        AppTableColumn('Debet/Credit', flex: 2),
        AppTableColumn('Keterangan', flex: 3),
        AppTableColumn('Grup Akun', flex: 3),
        AppTableColumn('Dipakai', flex: 1, align: TextAlign.right),
      ],
      rows: data
          .map((a) => AppTableRowData(cells: [
                AppTableCell.text(
                    '${'    ' * ((a['_level'] as int?) ?? 0)}${a['kode'] ?? ''} - ${a['nama'] ?? ''}',
                    flex: 4),
                AppTableCell.text('${a['posisi'] ?? ''}', flex: 2),
                AppTableCell.text('${a['keterangan'] ?? ''}', flex: 3),
                AppTableCell.text('${a['grupAkun'] ?? ''}', flex: 3),
                AppTableCell.text('${a['jumlahDipakai'] ?? 0}',
                    flex: 1, align: TextAlign.right),
              ]))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(
                  labelText: 'Cari kode / nama',
                  prefixIcon: Icon(Icons.search),
                  isDense: true),
              onChanged: (v) => _cari = v,
              onSubmitted: (_) => _muat(),
            ),
          ),
          FilledButton.icon(
              onPressed: _memuat ? null : _muat,
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Terapkan')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unduhAkun,
              icon: const Icon(Icons.download, size: 18),
              label: Text('Download $_defJudul')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unggahAkun,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text('Upload $_defJudul')),
          if (_sibuk)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
      TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
        Tab(text: 'Akun'),
        Tab(text: 'Daftar Akun'),
        Tab(text: 'Bank'),
        Tab(text: 'Jenis Transaksi'),
      ]),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ))
                : TabBarView(controller: _tab, children: [
                    _tabelAkun(pohon: true),
                    _tabelAkun(pohon: false),
                    AppDataTable(
                      minWidth: 720,
                      emptyText: 'Belum ada data bank.',
                      columns: const [
                        AppTableColumn('Bank', flex: 3),
                        AppTableColumn('Akun Kas', flex: 4),
                        AppTableColumn('Keterangan', flex: 3),
                        AppTableColumn('Aktif', flex: 1),
                      ],
                      rows: _bank
                          .map((b) => AppTableRowData(cells: [
                                AppTableCell.text('${b['nama'] ?? ''}', flex: 3),
                                AppTableCell.text(
                                    '${b['akunKode'] ?? ''} ${b['akunNama'] ?? ''}'.trim(),
                                    flex: 4),
                                AppTableCell.text('${b['keterangan'] ?? ''}', flex: 3),
                                AppTableCell.text(
                                    b['aktif'] == true ? 'Ya' : 'Tidak', flex: 1),
                              ]))
                          .toList(),
                    ),
                    AppDataTable(
                      minWidth: 820,
                      emptyText: 'Belum ada jenis transaksi.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Nama', flex: 3),
                        AppTableColumn('Akun', flex: 4),
                        AppTableColumn('Keterangan', flex: 3),
                        AppTableColumn('Aktif', flex: 1),
                      ],
                      rows: _jenisTransaksi
                          .map((t) => AppTableRowData(cells: [
                                AppTableCell.text('${t['kode'] ?? ''}', flex: 2),
                                AppTableCell.text('${t['nama'] ?? ''}', flex: 3),
                                AppTableCell.text(
                                    '${t['akunKode'] ?? ''} ${t['akunNama'] ?? ''}'.trim(),
                                    flex: 4),
                                AppTableCell.text('${t['keterangan'] ?? ''}', flex: 3),
                                AppTableCell.text(
                                    t['aktif'] == true ? 'Ya' : 'Tidak', flex: 1),
                              ]))
                          .toList(),
                    ),
                  ]),
      ),
    ]);
  }
}
