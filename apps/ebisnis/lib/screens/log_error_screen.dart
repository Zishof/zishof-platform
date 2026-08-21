import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../api_client.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/aksi_baris_menu.dart';

const _urlIssueBaruGithub =
    'https://github.com/Zishof/zishof-platform/issues/new';

String _formatWaktu(String iso) {
  try {
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

const _tingkatOpsi = ['ERROR', 'PERINGATAN', 'INFO'];

/// Layar Log Error (padanan log-error.html/log-error-renderer.js Electron) --
/// MURNI LOKAL (tabel `error_log` di core_db), tidak ada aksi server utk
/// membaca log ini kembali -- hanya ada pengiriman satu-arah fire-and-forget
/// ke server (`error_log_kirim`, dipakai job sinkronisasi terpisah, di luar
/// scope tampilan layar ini).
class LogErrorScreen extends StatefulWidget {
  const LogErrorScreen({super.key});
  @override
  State<LogErrorScreen> createState() => _LogErrorScreenState();
}

class _LogErrorScreenState extends State<LogErrorScreen> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  int _totalSemua = 0;
  int _totalError = 0;
  int _totalPeringatan = 0;
  int _totalInfo = 0;
  String? _tingkat;
  String _kataKunci = '';
  Map<String, dynamic>? _health;
  String? _healthError;
  bool _memuatHealth = false;

  @override
  void initState() {
    super.initState();
    _muat();
    _muatHealth();
  }

  Future<void> _muatHealth() async {
    setStateIfMounted(() {
      _memuatHealth = true;
      _healthError = null;
    });
    try {
      final value = await ApiClient.instance.aksi('error_log_health');
      setStateIfMounted(() => _health = value);
    } catch (e) {
      setStateIfMounted(() => _healthError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuatHealth = false);
    }
  }

  Future<void> _tampilkanHealth() async {
    if (_health == null) return;
    final detail = const JsonEncoder.withIndent('  ').convert(_health);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detail Kesehatan Server & Database'),
        content: SizedBox(
          width: 900,
          child: SingleChildScrollView(
              child: SelectableText(detail,
                  style: const TextStyle(fontFamily: 'monospace'))),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: detail));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Detail server disalin.')));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Salin Detail'),
          ),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    final data = await CoreDb.instance.listErrorLog(
      tingkat: _tingkat,
      kataKunci: _kataKunci.isEmpty ? null : _kataKunci,
      limit: _pageSize,
      offset: (_halaman - 1) * _pageSize,
    );
    final total = await CoreDb.instance.jumlahErrorLog(tingkat: _tingkat);
    final totalSemua = await CoreDb.instance.jumlahErrorLog();
    final totalError = await CoreDb.instance.jumlahErrorLog(tingkat: 'ERROR');
    final totalPeringatan =
        await CoreDb.instance.jumlahErrorLog(tingkat: 'PERINGATAN');
    final totalInfo = await CoreDb.instance.jumlahErrorLog(tingkat: 'INFO');
    if (mounted) {
      setStateIfMounted(() {
        _data = data.cast<Map<String, dynamic>>();
        _total = total;
        _totalSemua = totalSemua;
        _totalError = totalError;
        _totalPeringatan = totalPeringatan;
        _totalInfo = totalInfo;
        _memuat = false;
      });
    }
  }

  Future<void> _terapkanFilter() async {
    _halaman = 1;
    await _muat();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _hapus(int id) async {
    await CoreDb.instance.hapusErrorLog(id);
    await _muat();
  }

  Future<void> _bersihkanSemua() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bersihkan Semua Log?'),
        content: const Text(
            'Seluruh log error lokal di perangkat ini akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Hapus Semua')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    await CoreDb.instance.bersihkanErrorLog();
    _halaman = 1;
    await _muat();
  }

  Color _warnaTingkat(String? t) {
    switch (t) {
      case 'ERROR':
        return Colors.red;
      case 'PERINGATAN':
        return Colors.orange;
      default:
        return const Color(0xFF0284C7);
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  String _teksSatuError(Map<String, dynamic> e) =>
      '[${e['tingkat']}] ${_formatWaktu(e['waktu'] as String)} · ${e['sumber'] ?? '-'}\n${e['pesan']}${(e['detail'] as String?)?.isNotEmpty == true ? '\n${e['detail']}' : ''}';

  Future<void> _salinSemua() async {
    final teks = _data.map(_teksSatuError).join('\n\n---\n\n');
    await Clipboard.setData(ClipboardData(text: teks));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_data.length} baris disalin ke clipboard.')));
  }

  Future<void> _laporkanKeGithub(Map<String, dynamic> e) async {
    final judul = Uri.encodeComponent('[Error Log] ${e['pesan']}');
    final body = Uri.encodeComponent(_teksSatuError(e));
    final url = Uri.parse('$_urlIssueBaruGithub?title=$judul&body=$body');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _tampilkanAksiBaris(Map<String, dynamic> e) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((e['detail'] as String?)?.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Detail'),
                onTap: () {
                  Navigator.of(context).pop();
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('${e['pesan']}'),
                      content:
                          SingleChildScrollView(child: Text('${e['detail']}')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Tutup'))
                      ],
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Salin'),
              onTap: () async {
                Navigator.of(context).pop();
                await Clipboard.setData(ClipboardData(text: _teksSatuError(e)));
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Disalin ke clipboard.')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Laporkan ke GitHub'),
              onTap: () {
                Navigator.of(context).pop();
                _laporkanKeGithub(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Hapus'),
              onTap: () {
                Navigator.of(context).pop();
                _hapus(e['id'] as int);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.logError,
      judul: 'Log Error',
      subjudul: 'Riwayat error lokal perangkat ini',
      scrollable: false,
      actionsAppBar: [
        IconButton(
            icon: const Icon(Icons.monitor_heart_outlined),
            onPressed: _memuatHealth ? null : _muatHealth,
            tooltip: 'Muat Kesehatan Server'),
        IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _data.isEmpty ? null : _salinSemua,
            tooltip: 'Salin Semua Error'),
        IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _data.isEmpty ? null : _bersihkanSemua,
            tooltip: 'Bersihkan Semua'),
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: const Icon(Icons.monitor_heart_outlined),
            onPressed: _memuatHealth ? null : _muatHealth,
            tooltip: 'Muat Kesehatan Server'),
        IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _data.isEmpty ? null : _salinSemua,
            tooltip: 'Salin Semua Error'),
        IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _data.isEmpty ? null : _bersihkanSemua,
            tooltip: 'Bersihkan Semua'),
      ]),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.monitor_heart_outlined,
                                color: AppColors.primary),
                            const SizedBox(width: 8),
                            const Expanded(
                                child: Text('Kesehatan Server & Database',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700))),
                            if (_memuatHealth)
                              const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            IconButton(
                                onPressed: _memuatHealth ? null : _muatHealth,
                                icon: const Icon(Icons.refresh)),
                          ]),
                          if (_healthError != null)
                            Text(_healthError!,
                                style: const TextStyle(color: AppColors.danger))
                          else if (_health != null)
                            Wrap(spacing: 20, runSpacing: 8, children: [
                              Text(
                                  'Error 24 jam: ${_health!['error24Jam'] ?? 0}'),
                              Text(
                                  'Error 7 hari: ${_health!['error7Hari'] ?? 0}'),
                              Text(
                                  'Proses DB aktif: ${(_health!['aktivitasDatabase'] as List?)?.length ?? 0}'),
                              Text(
                                  'Query lambat tercatat: ${(_health!['queryLambat'] as List?)?.length ?? 0}'),
                              Text(
                                  'Sampel lambat 24 jam: ${(_health!['queryLambatSampel24Jam'] as List?)?.length ?? 0}'),
                              if (_health!['statistikQueryTersedia'] == false)
                                Text('${_health!['saranStatistik'] ?? ''}',
                                    style: const TextStyle(
                                        color: AppColors.warning)),
                              TextButton.icon(
                                  onPressed: _tampilkanHealth,
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Lihat Detail')),
                            ])
                          else
                            const Text(
                                'Tekan muat ulang untuk membaca kondisi server.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SizedBox(
                            width: 190,
                            child: AppKpiCard(
                                icon: Icons.list_alt_outlined,
                                warna: AppColors.primary,
                                nilai: '$_totalSemua',
                                label: 'Total Log')),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 190,
                            child: AppKpiCard(
                                icon: Icons.error_outline,
                                warna: AppColors.danger,
                                nilai: '$_totalError',
                                label: 'Error')),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 190,
                            child: AppKpiCard(
                                icon: Icons.warning_amber_outlined,
                                warna: AppColors.warning,
                                nilai: '$_totalPeringatan',
                                label: 'Peringatan')),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 190,
                            child: AppKpiCard(
                                icon: Icons.info_outline,
                                warna: AppColors.teal,
                                nilai: '$_totalInfo',
                                label: 'Info')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                          label: const Text('Semua'),
                          selected: _tingkat == null,
                          onSelected: (_) {
                            _tingkat = null;
                            _terapkanFilter();
                          }),
                      ..._tingkatOpsi.map((t) => ChoiceChip(
                            label: Text(t),
                            selected: _tingkat == t,
                            onSelected: (_) {
                              _tingkat = t;
                              _terapkanFilter();
                            },
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                        hintText: 'Cari pesan...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true),
                    onSubmitted: (v) {
                      _kataKunci = v;
                      _terapkanFilter();
                    },
                  ),
                  const SizedBox(height: 12),
                  AppDataTable(
                    minWidth: 860,
                    emptyText: 'Tidak ada log.',
                    columns: const [
                      AppTableColumn('Waktu', flex: 2),
                      AppTableColumn('Tingkat', flex: 2),
                      AppTableColumn('Sumber', flex: 2),
                      AppTableColumn('Pesan', flex: 5),
                      AppTableColumn('Aksi',
                          width: 64, align: TextAlign.center),
                    ],
                    rows: _data
                        .map((e) => AppTableRowData(
                              onTap: () => _tampilkanAksiBaris(e),
                              cells: [
                                AppTableCell.text(
                                    _formatWaktu(e['waktu'] as String),
                                    flex: 2),
                                AppTableCell(
                                  flex: 2,
                                  child: StatusPill(
                                    label: '${e['tingkat'] ?? '-'}',
                                    warna:
                                        _warnaTingkat(e['tingkat'] as String?),
                                  ),
                                ),
                                AppTableCell.text('${e['sumber'] ?? '-'}',
                                    flex: 2),
                                AppTableCell.text('${e['pesan']}',
                                    flex: 5, maxLines: 2),
                                AppTableCell(
                                  width: 64,
                                  align: TextAlign.center,
                                  /* Satu aksi saja, tetapi TETAP lewat menu: ikon
                                   * tong sampah polos ini dahulu menghapus log
                                   * seketika tanpa konfirmasi dan tanpa label.
                                   * Menu memberinya nama dan menjadikan
                                   * penghapusan sebuah pilihan, bukan refleks. */
                                  child: AksiBarisMenu(aksi: [
                                    AksiBaris(
                                        ikon: Icons.delete_outline,
                                        label: 'Hapus log ini',
                                        merusak: true,
                                        onTap: () => _hapus(e['id'] as int)),
                                  ]),
                                ),
                              ],
                            ))
                        .toList(),
                    pagination: AppTablePagination(
                      halaman: _halaman,
                      totalHalaman: _totalHalaman,
                      totalData: _total,
                      labelData: 'log',
                      onSebelumnya:
                          _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                      onBerikutnya: _halaman < _totalHalaman
                          ? () => _pindah(_halaman + 1)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
