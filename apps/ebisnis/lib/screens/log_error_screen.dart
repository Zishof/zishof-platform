import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

class _LogErrorScreenState extends State<LogErrorScreen> {
  static const _pageSize = 30;
  bool _memuat = true;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  int _totalError = 0;
  String? _tingkat;
  String _kataKunci = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() => _memuat = true);
    final data = await CoreDb.instance.listErrorLog(
      tingkat: _tingkat,
      kataKunci: _kataKunci.isEmpty ? null : _kataKunci,
      limit: _pageSize,
      offset: (_halaman - 1) * _pageSize,
    );
    final total = await CoreDb.instance.jumlahErrorLog(tingkat: _tingkat);
    final totalError = await CoreDb.instance.jumlahErrorLog(tingkat: 'ERROR');
    if (mounted) {
      setState(() {
        _data = data.cast<Map<String, dynamic>>();
        _total = total;
        _totalError = totalError;
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
        content: const Text('Seluruh log error lokal di perangkat ini akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, Hapus Semua')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Error'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), onPressed: _data.isEmpty ? null : _bersihkanSemua, tooltip: 'Bersihkan Semua'),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: Text('$_totalError Error', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: Text('$_total Total', style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(label: const Text('Semua'), selected: _tingkat == null, onSelected: (_) {
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
                    decoration: const InputDecoration(hintText: 'Cari pesan...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                    onSubmitted: (v) {
                      _kataKunci = v;
                      _terapkanFilter();
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_data.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Tidak ada log.')))
                  else
                    ..._data.map((e) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.circle, size: 10, color: _warnaTingkat(e['tingkat'] as String?)),
                            title: Text('${e['pesan']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            subtitle: Text('${_formatWaktu(e['waktu'] as String)} · ${e['sumber'] ?? '-'}'),
                            trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _hapus(e['id'] as int)),
                            onTap: (e['detail'] as String?)?.isNotEmpty == true
                                ? () => showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text('${e['pesan']}'),
                                        content: SingleChildScrollView(child: Text('${e['detail']}')),
                                        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup'))],
                                      ),
                                    )
                                : null,
                          ),
                        )),
                  if (_total > _pageSize)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _halaman > 1 ? () => _pindah(_halaman - 1) : null),
                          Text('Halaman $_halaman / $_totalHalaman'),
                          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
