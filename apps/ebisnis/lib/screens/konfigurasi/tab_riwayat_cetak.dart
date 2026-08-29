import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

/// Register cetak append-only Inventory & Sales (P10).
///
/// Tab ini hanya dirakit layar Konfigurasi untuk Pemilik/Admin. Server
/// tetap menegakkan RBAC pada `si_print_log_list` agar akses tidak bergantung
/// pada visibilitas UI.
class TabRiwayatCetak extends StatefulWidget {
  const TabRiwayatCetak({super.key});

  @override
  State<TabRiwayatCetak> createState() => _TabRiwayatCetakState();
}

class _TabRiwayatCetakState extends State<TabRiwayatCetak> with JejakGalat {
  final _jenis = TextEditingController();
  final _referensi = TextEditingController();
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  bool _dariCache = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _jenis.dispose();
    _referensi.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final jenis = _jenis.text.trim();
      final referensi = _referensi.text.trim();
      if (jenis.isEmpty && referensi.isEmpty) {
        // Tanpa filter: baca lokal-dulu, server menyusul di latar (merge --
        // respons parsial tidak pernah menghapus baris lokal).
        await MasterOffline.daftarCacheDulu(
            'si_print_log_list', const {}, 'si_print_log',
            fieldData: 'rows', onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data = ((hasil['rows'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _dariCache = hasil['offline'] == true;
            _memuat = false;
          });
        });
      } else {
        // Pencarian berfilter tetap online: satu cache tak berfilter tidak
        // boleh disajikan sebagai hasil filter.
        final hasil = await ApiClient.instance.aksi('si_print_log_list', {
          if (jenis.isNotEmpty) 'jenis_dokumen': jenis,
          if (referensi.isNotEmpty) 'referensi': referensi,
        });
        setStateIfMounted(() {
          _data = ((hasil['rows'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _dariCache = false;
          _memuat = false;
        });
      }
    } catch (e) {
      setStateIfMounted(() {
        _error = terapkanGalat(e);
        _memuat = false;
      });
    }
  }

  void _bersihkanFilter() {
    _jenis.clear();
    _referensi.clear();
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PenandaDataTersimpan(tampil: _dariCache),
          AppFormSection(
            judul: 'Riwayat Cetak Inventory & Sales',
            deskripsi:
                'Register append-only untuk dokumen dan laporan yang pernah dicetak.',
            children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _jenis,
                    decoration: const InputDecoration(
                        labelText: 'Jenis dokumen',
                        hintText: 'mis. laporan_laba_rugi',
                        isDense: true),
                    onSubmitted: (_) => _muat(),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _referensi,
                    decoration: const InputDecoration(
                        labelText: 'Referensi', isDense: true),
                    onSubmitted: (_) => _muat(),
                  ),
                ),
                ElevatedButton.icon(
                    onPressed: _memuat ? null : _muat,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Terapkan')),
                TextButton(
                    onPressed: _memuat ? null : _bersihkanFilter,
                    child: const Text('Bersihkan')),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            AppInfoBanner(
              icon: Icons.error_outline,
              color: AppColors.danger,
              text: _error!,
              detail: detailUntuk(_error),
            )
          else if (_data.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Belum ada riwayat cetak.')),
            )
          else
            AppFormSection(
              judul: 'Hasil (${_data.length})',
              deskripsi: 'Maksimum 200 catatan terbaru dari server.',
              children: [
                for (final row in _data)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.print_outlined),
                    title: Text('${row['jenisDokumen']} · ${row['referensi']}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${row['waktu']} · ${row['userId']} · ${row['perangkat']}',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context))),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
