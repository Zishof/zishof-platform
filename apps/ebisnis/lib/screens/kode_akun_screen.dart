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

  Future<void> _unduhAkun() async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final peta = _kodeById;
      final bytes = buildSimpleXlsx(
        sheetName: 'Akun',
        headers: const [
          'Kode', 'Nama', 'Keterangan', 'Posisi', 'Grup Akun', 'Kode Induk'
        ],
        rows: _akun
            .map((a) => [
                  '${a['kode'] ?? ''}',
                  '${a['nama'] ?? ''}',
                  '${a['keterangan'] ?? ''}',
                  '${a['posisi'] ?? ''}',
                  '${a['grupAkun'] ?? ''}',
                  a['parentId'] == null ? '' : (peta['${a['parentId']}'] ?? ''),
                ])
            .toList(),
      );
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan Daftar Akun',
          fileName:
              'Kode_Akun_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
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
      String kol(int i) => r.length > i ? r[i].trim() : '';
      if (kol(0).isEmpty && kol(1).isEmpty) continue;
      baris.add({
        'kode': kol(0),
        'nama': kol(1),
        'keterangan': kol(2),
        'posisi': kol(3),
        'grupAkun': kol(4),
        'kodeParent': kol(5),
      });
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
        title: const Text('Unggah Daftar Akun'),
        content: Text('${baris.length} baris akan diproses. Kode yang belum ada '
            'akan DIBUAT, kode yang sudah ada akan DIPERBARUI. Tidak ada akun '
            'yang dihapus.'),
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
          await ApiClient.instance.aksi('kode_akun_impor', {'baris': baris});
      if (!mounted) return;
      final masalah = ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hasil Unggah Akun'),
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
              onPressed: _sibuk || _akun.isEmpty ? null : _unduhAkun,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download Excel')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unggahAkun,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Upload Excel')),
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
