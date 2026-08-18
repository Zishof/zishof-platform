import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

/// Tab "Notifikasi" (padanan `notifikasi.jsp`) -- log/riwayat notifikasi yg
/// SUDAH dikirim ke member (mis. peringatan wajib-belanja-rutin dari Tab
/// Jenis Member), BUKAN layar konfigurasi. Halaman JSP asalnya ADMIN-ONLY
/// (toko==null) -- gerbang direplikasi PERSIS di sini via `Sesi.instance.isAdmin`,
/// TIDAK dilonggarkan ke supervisor toko.
class AnggotaTabNotifikasi extends StatefulWidget {
  const AnggotaTabNotifikasi({super.key});

  @override
  State<AnggotaTabNotifikasi> createState() => _AnggotaTabNotifikasiState();
}

class _AnggotaTabNotifikasiState extends State<AnggotaTabNotifikasi> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    if (Sesi.instance.isAdmin) _muatDaftar();
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('notifikasi_list', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      });
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        setStateIfMounted(() {
          _daftar = data;
          _total = (hasil['total'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      if (mounted) setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cariUlang(String v) async {
    setStateIfMounted(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> n) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Notifikasi?'),
        content: const Text('Log notifikasi ini akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      await MasterOffline.simpanAtauAntre('notifikasi_hapus', {'id': n['id']},
          kunci: 'notifikasi:${n['id']}');
      await _muatDaftar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Color _warnaTipe(String tipe) {
    switch (tipe.toUpperCase()) {
      case 'WARNING':
        return AppColors.warning;
      case 'DANGER':
        return AppColors.danger;
      case 'SUCCESS':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 48, color: AppColors.textSecondaryOf(context)),
              const SizedBox(height: 12),
              const Text('Hanya admin yang dapat melihat log Notifikasi.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_pesanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_pesanError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _muatDaftar, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muatDaftar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          AppSearchField(
            hintText: 'Cari userid/isi notifikasi/nama member...',
            debounce: const Duration(milliseconds: 450),
            onChanged: _cariUlang,
          ),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 900,
            emptyText: 'Belum ada log notifikasi.',
            columns: const [
              AppTableColumn('Waktu', flex: 2),
              AppTableColumn('Penerima', flex: 3),
              AppTableColumn('Isi Notifikasi', flex: 4),
              AppTableColumn('Tipe', flex: 1, align: TextAlign.center),
              AppTableColumn('Status', flex: 1, align: TextAlign.center),
              AppTableColumn('Aksi', width: 48, align: TextAlign.center),
            ],
            rows: _daftar.map((n) {
              final dibaca = n['buka'] == true;
              return AppTableRowData(
                cells: [
                  AppTableCell.text('${n['waktu'] ?? '-'}', flex: 2),
                  AppTableCell(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${n['namaMember'] ?? ''}'.isEmpty
                                ? '${n['userid'] ?? '-'}'
                                : '${n['namaMember']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        Text('${n['userid'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  AppTableCell.text('${n['keterangan'] ?? '-'}',
                      flex: 4, maxLines: 2),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: StatusPill(
                      label: '${n['tipe'] ?? 'INFO'}',
                      warna: _warnaTipe('${n['tipe'] ?? ''}'),
                    ),
                  ),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: StatusPill(
                      label: dibaca ? 'Dibaca' : 'Belum',
                      warna:
                          dibaca ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                  AppTableCell(
                    width: 48,
                    align: TextAlign.center,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      onPressed: () => _hapus(n),
                    ),
                  ),
                ],
              );
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'notifikasi',
              onSebelumnya:
                  _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
              onBerikutnya: _halaman < _totalHalaman
                  ? () => _pindahHalaman(_halaman + 1)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
