import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../services/transaksi_outbox_service.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

final _rupiahPengajuan =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Antrean persetujuan transaksi member yang melampaui limit Tipe Member.
/// Daftar dibaca local-first; keputusan sengaja online-only karena merupakan
/// tindakan otorisasi finansial dan harus menolak keputusan bersamaan.
class AnggotaTabPengajuanLimit extends StatefulWidget {
  const AnggotaTabPengajuanLimit({super.key});

  @override
  State<AnggotaTabPengajuanLimit> createState() =>
      _AnggotaTabPengajuanLimitState();
}

class _AnggotaTabPengajuanLimitState extends State<AnggotaTabPengajuanLimit> {
  static const _pageSize = 25;
  final _cari = TextEditingController();
  List<Map<String, dynamic>> _data = [];
  bool _memuat = true;
  bool _memutuskan = false;
  String? _galat;
  String _status = 'MENUNGGU';
  int _halaman = 1;
  int _total = 0;

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

  String get _cacheKey {
    final kata = Uri.encodeComponent(_cari.text.trim().toLowerCase());
    return 'master:pengajuan_limit_member:${Sesi.instance.userId}:$_status:$kata';
  }

  Future<void> _muat() async {
    if (!Sesi.instance.bolehVerifikasiLimitMember) {
      setStateIfMounted(() => _memuat = false);
      return;
    }
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'pengajuan_limit_member_list',
        {
          'page': _halaman,
          'page_size': _pageSize,
          'status': _status,
          'keyword': _cari.text.trim(),
        },
        _cacheKey,
        onData: (hasil) {
          if (!mounted) return;
          final rows =
              ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          setStateIfMounted(() {
            _data = rows;
            _total = hasil['dariServer'] == true
                ? ((hasil['total'] as num?)?.toInt() ?? rows.length)
                : rows.length;
            _memuat = false;
          });
        },
      );
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<String?> _mintaCatatan(bool setuju) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(setuju ? 'Setujui pengajuan?' : 'Tolak pengajuan?'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            autofocus: !setuju,
            decoration: InputDecoration(
              labelText: setuju ? 'Catatan (opsional)' : 'Alasan penolakan',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              style: FilledButton.styleFrom(
                  backgroundColor:
                      setuju ? AppColors.primary : AppColors.danger),
              child: Text(setuju ? 'Setujui' : 'Tolak'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _putuskan(Map<String, dynamic> row, bool setuju) async {
    final catatan = await _mintaCatatan(setuju);
    if (catatan == null || !mounted) return;
    setStateIfMounted(() => _memutuskan = true);
    try {
      final hasil = await ApiClient.instance.aksi(
        'pengajuan_limit_member_putuskan',
        {
          'id': row['id'],
          'keputusan': setuju ? 'SETUJUI' : 'TOLAK',
          'catatan': catatan,
        },
      );
      var pesan = '${hasil['description'] ?? 'Keputusan tersimpan.'}';
      if (setuju) {
        final kirim = await TransaksiOutboxService.instance
            .kirimSatuManual('${row['kodeTransaksi'] ?? ''}');
        pesan = kirim.berhasil > 0
            ? '$pesan Transaksi asal langsung berhasil dikirim.'
            : '$pesan ${kirim.pesan} Jika transaksi biometrik tidak tersimpan '
                'di antrean perangkat, kasir asal cukup menekan Bayar kembali; '
                'kode pengajuan yang sama akan dipakai otomatis.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(pesan)));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memutuskan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehVerifikasiLimitMember) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings_outlined, size: 52),
              SizedBox(height: 12),
              Text(
                  'Role Anda belum diizinkan memverifikasi transaksi member yang melebihi limit.',
                  textAlign: TextAlign.center),
              SizedBox(height: 6),
              Text(
                  'Aktifkan hak tersebut pada Grup Pengguna (Tbmrole), lalu login ulang.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cari,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari nama member atau kode transaksi...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    _halaman = 1;
                    _muat();
                  },
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'MENUNGGU', child: Text('Menunggu')),
                  DropdownMenuItem(
                      value: 'DISETUJUI', child: Text('Disetujui')),
                  DropdownMenuItem(value: 'DITOLAK', child: Text('Ditolak')),
                  DropdownMenuItem(
                      value: 'DIPAKAI', child: Text('Sudah dipakai')),
                  DropdownMenuItem(value: 'SEMUA', child: Text('Semua status')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setStateIfMounted(() {
                    _status = v;
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
              IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: _memuat ? null : _muat,
                  icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 10),
          if (_galat != null)
            AppSectionCard(
              judul: 'Data belum dapat dimuat',
              child: Text(_galat!),
            ),
          Expanded(
            child: _memuat && _data.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _data.isEmpty
                    ? const Center(
                        child: Text('Tidak ada pengajuan pada status ini.'))
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Member')),
                              DataColumn(label: Text('Kode Transaksi')),
                              DataColumn(label: Text('Nominal')),
                              DataColumn(label: Text('Limit / Pemakaian')),
                              DataColumn(label: Text('Diajukan')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Aksi')),
                            ],
                            rows: _data.map((r) {
                              final menunggu = '${r['status']}' == 'MENUNGGU';
                              return DataRow(cells: [
                                DataCell(SizedBox(
                                  width: 190,
                                  child: Text(
                                      '${r['namaMember'] ?? '-'}\n${r['kodeMember'] ?? ''}'),
                                )),
                                DataCell(Text('${r['kodeTransaksi'] ?? '-'}')),
                                DataCell(Text(_rupiahPengajuan
                                    .format(r['nominal'] ?? 0))),
                                DataCell(Text(
                                    '${r['periode'] ?? ''}: ${_rupiahPengajuan.format(r['limit'] ?? 0)}\n'
                                    'Terpakai ${_rupiahPengajuan.format(r['pemakaianBerjalan'] ?? 0)}')),
                                DataCell(Text(
                                    '${r['tanggalPengajuan'] ?? '-'}\n${r['diajukanOleh'] ?? ''}')),
                                DataCell(Text('${r['status'] ?? '-'}')),
                                DataCell(menunggu
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                            IconButton(
                                              tooltip: 'Setujui',
                                              onPressed: _memutuskan
                                                  ? null
                                                  : () => _putuskan(r, true),
                                              icon: const Icon(
                                                  Icons.check_circle_outline,
                                                  color: Colors.green),
                                            ),
                                            IconButton(
                                              tooltip: 'Tolak',
                                              onPressed: _memutuskan
                                                  ? null
                                                  : () => _putuskan(r, false),
                                              icon: const Icon(
                                                  Icons.cancel_outlined,
                                                  color: Colors.red),
                                            ),
                                          ])
                                    : Text('${r['diputuskanOleh'] ?? '-'}')),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
          ),
          if (_total > _pageSize)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('$_total pengajuan · halaman $_halaman'),
                IconButton(
                    onPressed: _halaman <= 1
                        ? null
                        : () {
                            _halaman--;
                            _muat();
                          },
                    icon: const Icon(Icons.chevron_left)),
                IconButton(
                    onPressed: _halaman * _pageSize >= _total
                        ? null
                        : () {
                            _halaman++;
                            _muat();
                          },
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
        ],
      ),
    );
  }
}
