import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

String _formatWaktu(String iso) {
  try {
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

const _statusOpsi = ['PENDING', 'SYNCED'];

/// Layar Riwayat Sinkronisasi (padanan riwayat-sinkronisasi.html/-renderer.js
/// Electron) -- MURNI LOKAL, tidak ada aksi server sama sekali (persis JSDoc
/// Electron-nya: "TIDAK ADA fetch()/XHR di sini"). 2 bagian: "Sinkron Masuk"
/// (snapshot `cache_referensi` terakhir per kunci -- saat ini belum ada layar
/// lain di app ini yg menulis ke tabel ini, jadi biasanya kosong; viewer tetap
/// dibangun generik supaya otomatis terisi begitu ada fitur cache lain nanti)
/// dan "Sinkron Keluar" (riwayat `transaksi_pending`, sumber data yg sama
/// dipakai tombol "Sinkronkan Sekarang" di Kasir).
class RiwayatSinkronisasiScreen extends StatefulWidget {
  const RiwayatSinkronisasiScreen({super.key});
  @override
  State<RiwayatSinkronisasiScreen> createState() => _RiwayatSinkronisasiScreenState();
}

class _RiwayatSinkronisasiScreenState extends State<RiwayatSinkronisasiScreen> {
  static const _pageSize = 20;
  bool _memuat = true;
  bool _sinkronBerjalan = false;
  List<Map<String, dynamic>> _cache = [];
  List<Map<String, dynamic>> _transaksi = [];
  int _halaman = 1;
  int _total = 0;
  int _totalPending = 0;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    final cache = await CoreDb.instance.listCacheReferensi();
    final hasil = await CoreDb.instance.listTransaksiPending(limit: _pageSize, offset: (_halaman - 1) * _pageSize, status: _statusFilter);
    final totalPending = await CoreDb.instance.jumlahTransaksiPending();
    if (mounted) {
      setStateIfMounted(() {
        _cache = cache.cast<Map<String, dynamic>>();
        _transaksi = hasil.data.cast<Map<String, dynamic>>();
        _total = hasil.total;
        _totalPending = totalPending;
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

  Future<void> _sinkronkanSekarang() async {
    if (_sinkronBerjalan) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      final pending = await CoreDb.instance.transaksiPendingBelumSinkron();
      var berhasil = 0;
      for (final row in pending) {
        final kodeUnik = row['kode_unik'] as String;
        final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        try {
          await ApiClient.instance.aksi('bayar', payload);
          await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
          berhasil++;
        } catch (e) {
          final pesan = e.toString();
          if (pesan.toLowerCase().contains('sudah tercatat')) {
            await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
            berhasil++;
          } else {
            await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
            if (e is ApiException && e.offline) break;
          }
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$berhasil dari ${pending.length} transaksi berhasil disinkron.')));
      await _muat();
    } finally {
      if (mounted) setStateIfMounted(() => _sinkronBerjalan = false);
    }
  }

  String _labelKunci(String kunci) {
    switch (kunci) {
      case 'katalog':
        return 'Katalog Produk';
      case 'konfigurasi':
        return 'Konfigurasi Toko';
      case 'ringkasan':
        return 'Ringkasan Dasbor';
      case 'pesanan':
        return 'Pesanan';
      default:
        return kunci;
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.riwayatSinkron,
      judul: 'Riwayat Sinkronisasi',
      subjudul: 'Transaksi tertunda & cache lokal perangkat ini',
      scrollable: false,
      actionsAppBar: [IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SizedBox(width: 190, child: AppKpiCard(icon: Icons.cloud_download_outlined, warna: AppColors.primary, nilai: '${_cache.length}', label: 'Cache Lokal')),
                        const SizedBox(width: 8),
                        SizedBox(width: 190, child: AppKpiCard(icon: Icons.pending_actions_outlined, warna: AppColors.warning, nilai: '$_totalPending', label: 'Tertunda')),
                        const SizedBox(width: 8),
                        SizedBox(width: 190, child: AppKpiCard(icon: Icons.receipt_long, warna: AppColors.teal, nilai: '$_total', label: 'Total Transaksi')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Sinkron Masuk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  AppDataTable(
                    minWidth: 720,
                    emptyText: 'Belum ada data cache tersimpan.',
                    columns: const [
                      AppTableColumn('Jenis Cache', flex: 3),
                      AppTableColumn('Diperbarui', flex: 3),
                    ],
                    rows: _cache
                        .map((c) => AppTableRowData(cells: [
                              AppTableCell(
                                flex: 3,
                                child: Row(
                                  children: [
                                    const Icon(Icons.cloud_download_outlined, color: Color(0xFF0284C7), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(_labelKunci('${c['kunci']}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                  ],
                                ),
                              ),
                              AppTableCell.text(_formatWaktu('${c['diperbarui_pada']}'), flex: 3),
                            ]))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sinkron Keluar (Transaksi)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      TextButton.icon(
                        onPressed: _sinkronBerjalan ? null : _sinkronkanSekarang,
                        icon: _sinkronBerjalan ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
                        label: const Text('Sinkronkan Sekarang'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(label: const Text('Semua'), selected: _statusFilter == null, onSelected: (_) {
                        _statusFilter = null;
                        _terapkanFilter();
                      }),
                      ..._statusOpsi.map((s) => ChoiceChip(
                            label: Text(s),
                            selected: _statusFilter == s,
                            onSelected: (_) {
                              _statusFilter = s;
                              _terapkanFilter();
                            },
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppDataTable(
                    minWidth: 940,
                    emptyText: 'Tidak ada riwayat transaksi.',
                    columns: const [
                      AppTableColumn('Kode', flex: 3),
                      AppTableColumn('Waktu', flex: 2),
                      AppTableColumn('Kasir', flex: 2),
                      AppTableColumn('Metode', flex: 2),
                      AppTableColumn('Total', flex: 2, align: TextAlign.right),
                      AppTableColumn('Status', flex: 2, align: TextAlign.center),
                    ],
                    rows: _transaksi.map((t) {
                      final payload = jsonDecode(t['payload_json'] as String) as Map<String, dynamic>;
                      final caraBayarId = payload['caraBayar'];
                      final cocok = Sesi.instance.caraBayar.where((c) => c.id == caraBayarId);
                      final namaCaraBayar = cocok.isEmpty ? '-' : cocok.first.nama;
                      final synced = t['status'] == 'SYNCED';
                      final pesanError = (t['pesan_error'] as String?) ?? '';
                      return AppTableRowData(cells: [
                        AppTableCell.text('${payload['kodeUnik'] ?? t['kode_unik']}', flex: 3),
                        AppTableCell.text(_formatWaktu('${t['dibuat_pada']}'), flex: 2),
                        AppTableCell.text('${payload['kasir'] ?? '-'}', flex: 2),
                        AppTableCell.text(pesanError.isEmpty ? namaCaraBayar : '$namaCaraBayar - $pesanError', flex: 2, maxLines: 2),
                        AppTableCell.text(_formatRupiah.format(payload['total'] ?? 0), flex: 2, align: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        AppTableCell(
                          flex: 2,
                          align: TextAlign.center,
                          child: StatusPill(label: synced ? 'Tersinkron' : 'Tertunda', warna: synced ? AppColors.success : AppColors.warning),
                        ),
                      ]);
                    }).toList(),
                    pagination: AppTablePagination(
                      halaman: _halaman,
                      totalHalaman: _totalHalaman,
                      totalData: _total,
                      labelData: 'transaksi',
                      onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                      onBerikutnya: _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
