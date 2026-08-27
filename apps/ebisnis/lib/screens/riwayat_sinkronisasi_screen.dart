import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../services/pelayanan_transaksi.dart';
import '../services/sinkronisasi_tabel_service.dart';
import '../services/transaksi_outbox_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
  State<RiwayatSinkronisasiScreen> createState() =>
      _RiwayatSinkronisasiScreenState();
}

class _RiwayatSinkronisasiScreenState extends State<RiwayatSinkronisasiScreen> {
  static const _pageSize = 15;
  bool _memuat = true;
  bool _sinkronBerjalan = false;
  bool _auditMemuat = true;
  bool _tabSeluruhTabel = false;
  String? _tabelBerjalan;
  List<StatusSinkronTabel> _statusTabel = const [];
  List<Map<String, dynamic>> _cache = [];
  List<Map<String, dynamic>> _transaksi = [];
  Map<String, Map<String, dynamic>> _statusCadangan = {};
  int _halaman = 1;
  int _total = 0;
  int _totalPending = 0;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muatAudit() async {
    setStateIfMounted(() => _auditMemuat = true);
    try {
      final data = await SinkronisasiTabelService.instance.muat();
      if (mounted) setStateIfMounted(() => _statusTabel = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Audit tabel belum dapat dimuat: $e. Data tidak diubah. Buka Log Error, perbaiki penyebabnya, lalu tekan Periksa Ulang.'),
        ));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _auditMemuat = false);
    }
  }

  Future<void> _sinkronTabel(String nama) async {
    if (_tabelBerjalan != null) return;
    setStateIfMounted(() => _tabelBerjalan = nama);
    try {
      final pesan = await SinkronisasiTabelService.instance.sinkronkan(nama);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pesan)));
      }
      await _muatAudit();
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
              'Sinkron $nama belum selesai: $e Data lokal tetap aman. Ikuti petunjuk pada pesan, lalu tekan Sinkron Ulang.'),
        ));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _tabelBerjalan = null);
    }
  }

  Future<void> _sinkronSemuaTabel() async {
    if (_tabelBerjalan != null) return;
    setStateIfMounted(() => _tabelBerjalan = '*');
    try {
      final pesan = await SinkronisasiTabelService.instance.sinkronkanSemua();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Hasil sinkronisasi seluruh tabel'),
            content: SizedBox(
              width: 680,
              child: SelectableText(pesan.join('\n\n')),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'))
            ],
          ),
        );
        await _muatAudit();
        await _muat();
      }
    } finally {
      if (mounted) setStateIfMounted(() => _tabelBerjalan = null);
    }
  }

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    final cache = await CoreDb.instance.listCacheReferensi();
    final hasil = await CoreDb.instance.listTransaksiPending(
        limit: _pageSize,
        offset: (_halaman - 1) * _pageSize,
        status: _statusFilter);
    final totalPending = await CoreDb.instance.jumlahTransaksiPending();
    final statusCadangan =
        await _muatStatusCadangan(hasil.data.cast<Map<String, dynamic>>());
    if (mounted) {
      setStateIfMounted(() {
        _cache = cache.cast<Map<String, dynamic>>();
        _transaksi = hasil.data.cast<Map<String, dynamic>>();
        _total = hasil.total;
        _totalPending = totalPending;
        _statusCadangan = statusCadangan;
        _memuat = false;
      });
    }
  }

  String get _kunciCacheStatus =>
      'transaksi_backup_status_toko_${Sesi.instance.tokoId ?? 0}';

  Future<Map<String, Map<String, dynamic>>> _muatStatusCadangan(
      List<Map<String, dynamic>> transaksi) async {
    final status = <String, Map<String, dynamic>>{};
    try {
      final cache =
          await CoreDb.instance.ambilCacheReferensi(_kunciCacheStatus);
      if (cache != null && cache.isNotEmpty) {
        final decoded = jsonDecode(cache) as Map<String, dynamic>;
        decoded.forEach((kode, nilai) {
          if (nilai is Map) {
            status[kode.toLowerCase()] = Map<String, dynamic>.from(nilai);
          }
        });
      }
    } catch (_) {
      // Cache lama/korup tidak boleh menggagalkan halaman sinkronisasi.
    }
    if (!ApiClient.instance.sudahLogin || transaksi.isEmpty) return status;
    final kode = <String>[];
    for (final row in transaksi) {
      final nilai = '${row['kode_unik'] ?? ''}'.trim();
      if (nilai.isNotEmpty) kode.add(nilai);
    }
    if (kode.isEmpty) return status;
    try {
      final hasil = await ApiClient.instance.aksi('transaksi_backup_status', {
        'toko_id': Sesi.instance.tokoId,
        'kode_transaksi': kode,
        'id_perangkat': IdentitasMesin.instance.idMesin,
      });
      final data = (hasil['data'] as List?) ?? const <dynamic>[];
      for (final nilai in data) {
        if (nilai is! Map) continue;
        final row = Map<String, dynamic>.from(nilai);
        final kodeTransaksi = '${row['kodeTransaksi'] ?? ''}'.toLowerCase();
        if (kodeTransaksi.isNotEmpty) status[kodeTransaksi] = row;
      }
      await CoreDb.instance
          .simpanCacheReferensi(_kunciCacheStatus, jsonEncode(status));
    } catch (_) {
      // Saat offline tetap tampilkan acknowledgement terakhir dari cache.
    }
    return status;
  }

  Future<void> _terapkanFilter() async {
    _halaman = 1;
    await _muat();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _tandaiTerlayaniJikaPerlu(
      Map<String, dynamic> payload, Map<String, dynamic> hasil) async {
    await PelayananTransaksi.tandaiJikaPerlu(
      payload: payload,
      hasilBayar: hasil,
      percobaanCari: 1,
    );
  }

  Future<void> _sinkronkanSekarang() async {
    if (_sinkronBerjalan) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      final pending = await CoreDb.instance.transaksiPendingBelumSinkron();
      var berhasil = 0;
      for (final row in pending) {
        final kodeUnik = row['kode_unik'] as String;
        final payload =
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        try {
          payload['pengiriman_pending'] = true;
          final hasilBayar = await ApiClient.instance.aksi('bayar', payload);
          await _tandaiTerlayaniJikaPerlu(payload, hasilBayar);
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
      // Sapuan resmi outbox sekaligus menarik transaksi toko terbaru dan
      // mengirim acknowledgement perangkat ini.
      await TransaksiOutboxService.instance.sinkronkan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '$berhasil dari ${pending.length} transaksi berhasil disinkron.')));
      }
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

  Widget _pemilihTab() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.history),
                  label: Text('Riwayat Sinkronisasi')),
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.table_chart_outlined),
                  label: Text('Sinkronisasi Seluruh Tabel')),
            ],
            selected: {_tabSeluruhTabel},
            onSelectionChanged: (nilai) {
              setStateIfMounted(() => _tabSeluruhTabel = nilai.first);
              if (nilai.first) _muatAudit();
            },
          ),
        ),
      );

  Widget _buildAuditTabel() {
    if (_auditMemuat) {
      return const Center(child: CircularProgressIndicator());
    }
    final belumValid = _statusTabel.where((e) => e.belumValid).length;
    final tanpaAdapter = _statusTabel.where((e) => !e.dapatDisinkronkan).length;
    final totalLokal = _statusTabel.fold<int>(0, (n, e) => n + e.jumlahLokal);
    final pending = _statusTabel.fold<int>(0, (n, e) => n + e.pending);
    return RefreshIndicator(
      onRefresh: _muatAudit,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                  width: 190,
                  height: 96,
                  child: AppKpiCard(
                      icon: Icons.table_chart,
                      warna: AppColors.primary,
                      nilai: '${_statusTabel.length}',
                      label: 'Tabel Lokal')),
              SizedBox(
                  width: 190,
                  height: 96,
                  child: AppKpiCard(
                      icon: Icons.storage,
                      warna: AppColors.teal,
                      nilai: '$totalLokal',
                      label: 'Record Lokal')),
              SizedBox(
                  width: 190,
                  height: 96,
                  child: AppKpiCard(
                      icon: Icons.warning_amber,
                      warna: AppColors.warning,
                      nilai: '$belumValid',
                      label: 'Belum Valid')),
              SizedBox(
                  width: 190,
                  height: 96,
                  child: AppKpiCard(
                      icon: Icons.schedule_send,
                      warna:
                          pending == 0 ? AppColors.success : AppColors.warning,
                      nilai: '$pending',
                      label: 'Menunggu Kirim')),
              SizedBox(
                  width: 190,
                  height: 96,
                  child: AppKpiCard(
                      icon: Icons.extension_off_outlined,
                      warna: AppColors.textSecondary,
                      nilai: '$tanpaAdapter',
                      label: 'Lokal/Belum Didukung')),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFFFFBEB),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Cara membaca: jumlah server hanya tersedia untuk tabel yang benar-benar mempunyai pasangan API. Tabel konfigurasi, log, dan antrean tidak dibandingkan 1:1 karena memang sengaja lokal. Tabel baru otomatis muncul, tetapi tombol sinkron baru aktif setelah kontrak API, kunci unik, aturan konflik, dan lingkup toko ditentukan agar data tidak tertimpa.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Perbandingan Local vs Server',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Wrap(spacing: 6, children: [
                OutlinedButton.icon(
                  onPressed: _tabelBerjalan == null ? _muatAudit : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Periksa Ulang'),
                ),
                FilledButton.icon(
                  onPressed: _tabelBerjalan == null ? _sinkronSemuaTabel : null,
                  icon: _tabelBerjalan == '*'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync),
                  label: const Text('Sinkronkan Semua yang Didukung'),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          AppDataTable(
            minWidth: 1540,
            emptyText: 'Belum ada tabel lokal yang ditemukan.',
            columns: const [
              AppTableColumn('Tabel', flex: 3),
              AppTableColumn('Local', flex: 1, align: TextAlign.right),
              AppTableColumn('Server', flex: 1, align: TextAlign.right),
              AppTableColumn('Kolom', flex: 1, align: TextAlign.right),
              AppTableColumn('Pending', flex: 1, align: TextAlign.right),
              AppTableColumn('Gagal', flex: 1, align: TextAlign.right),
              AppTableColumn('Delete Lokal', flex: 1, align: TextAlign.right),
              AppTableColumn('Edit Lokal Terakhir', flex: 2),
              AppTableColumn('Validitas & Petunjuk', flex: 5),
              AppTableColumn('Aksi', flex: 2, align: TextAlign.center),
            ],
            rows: _statusTabel.map((t) {
              final warna = t.kendala != null
                  ? AppColors.danger
                  : t.belumValid
                      ? AppColors.warning
                      : t.dapatDisinkronkan
                          ? AppColors.success
                          : AppColors.textSecondary;
              final status = t.kendala != null
                  ? 'Perlu tindakan'
                  : t.belumValid
                      ? 'Belum sama'
                      : t.dapatDisinkronkan
                          ? 'Valid'
                          : 'Lokal / belum ada adapter';
              final petunjuk = t.kendala ??
                  (t.berbeda
                      ? 'Jumlah berbeda ${t.jumlahLokal} vs ${t.jumlahServer}. Tekan Sinkron Tabel, lalu Periksa Ulang.'
                      : t.keterangan);
              return AppTableRowData(cells: [
                AppTableCell.text(t.nama,
                    flex: 3,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                AppTableCell.text('${t.jumlahLokal}',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text(t.jumlahServer?.toString() ?? 'Tidak 1:1',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text('${t.jumlahKolom}',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text('${t.pending}',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text('${t.gagal}',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text('${t.terhapusLokal}',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text(
                    t.terbaruLokal == null
                        ? '-'
                        : _formatWaktu(t.terbaruLokal!),
                    flex: 2),
                AppTableCell(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      StatusPill(label: status, warna: warna),
                      const SizedBox(height: 4),
                      Text(petunjuk,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5)),
                    ],
                  ),
                ),
                AppTableCell(
                  flex: 2,
                  align: TextAlign.center,
                  child: t.dapatDisinkronkan
                      ? TextButton.icon(
                          onPressed: _tabelBerjalan == null
                              ? () => _sinkronTabel(t.nama)
                              : null,
                          icon: _tabelBerjalan == t.nama
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync, size: 17),
                          label: const Text('Sinkron Tabel'))
                      : Tooltip(
                          message: t.keterangan,
                          child: const Text('Tidak tersedia',
                              style: TextStyle(fontSize: 12))),
                ),
              ]);
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.riwayatSinkron,
      judul: 'Riwayat Sinkronisasi',
      subjudul: 'Transaksi tertunda & cache lokal perangkat ini',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      body: Column(
        children: [
          _pemilihTab(),
          Expanded(
            child: _tabSeluruhTabel
                ? _buildAuditTabel()
                : (_memuat
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
                                  SizedBox(
                                      width: 190,
                                      child: AppKpiCard(
                                          icon: Icons.cloud_download_outlined,
                                          warna: AppColors.primary,
                                          nilai: '${_cache.length}',
                                          label: 'Cache Lokal')),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                      width: 190,
                                      child: AppKpiCard(
                                          icon: Icons.pending_actions_outlined,
                                          warna: AppColors.warning,
                                          nilai: '$_totalPending',
                                          label: 'Tertunda')),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                      width: 190,
                                      child: AppKpiCard(
                                          icon: Icons.receipt_long,
                                          warna: AppColors.teal,
                                          nilai: '$_total',
                                          label: 'Total Transaksi')),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Sinkron Masuk',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
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
                                              const Icon(
                                                  Icons.cloud_download_outlined,
                                                  color: Color(0xFF0284C7),
                                                  size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                  child: Text(
                                                      _labelKunci(
                                                          '${c['kunci']}'),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 13))),
                                            ],
                                          ),
                                        ),
                                        AppTableCell.text(
                                            _formatWaktu(
                                                '${c['diperbarui_pada']}'),
                                            flex: 3),
                                      ]))
                                  .toList(),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sinkron Keluar (Transaksi)',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                TextButton.icon(
                                  onPressed: _sinkronBerjalan
                                      ? null
                                      : _sinkronkanSekarang,
                                  icon: _sinkronBerjalan
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.sync, size: 18),
                                  label: const Text('Sinkronkan Sekarang'),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 6,
                              children: [
                                ChoiceChip(
                                    label: const Text('Semua'),
                                    selected: _statusFilter == null,
                                    onSelected: (_) {
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
                              minWidth: 1240,
                              emptyText: 'Tidak ada riwayat transaksi.',
                              columns: const [
                                AppTableColumn('Kode', flex: 3),
                                AppTableColumn('Waktu', flex: 2),
                                AppTableColumn('Kasir', flex: 2),
                                AppTableColumn('Cadangan Kasir Lain', flex: 4),
                                AppTableColumn('Metode', flex: 2),
                                AppTableColumn('Total',
                                    flex: 2, align: TextAlign.right),
                                AppTableColumn('Status',
                                    flex: 2, align: TextAlign.center),
                              ],
                              rows: _transaksi.map((t) {
                                final payload =
                                    jsonDecode(t['payload_json'] as String)
                                        as Map<String, dynamic>;
                                final caraBayarId = payload['caraBayar'];
                                final cocok = Sesi.instance.caraBayar
                                    .where((c) => c.id == caraBayarId);
                                final namaCaraBayar =
                                    cocok.isEmpty ? '-' : cocok.first.nama;
                                final synced = t['status'] == 'SYNCED';
                                final pesanError =
                                    (t['pesan_error'] as String?) ?? '';
                                final kodeTransaksi =
                                    '${payload['kodeUnik'] ?? t['kode_unik']}'
                                        .toLowerCase();
                                final cadangan = _statusCadangan[kodeTransaksi];
                                final jumlahKasir =
                                    (cadangan?['jumlahKasir'] as num?)
                                            ?.toInt() ??
                                        0;
                                final jumlahMesin =
                                    (cadangan?['jumlahMesin'] as num?)
                                            ?.toInt() ??
                                        0;
                                final penerima =
                                    '${cadangan?['penerima'] ?? ''}'.trim();
                                return AppTableRowData(cells: [
                                  AppTableCell.text(
                                      '${payload['kodeUnik'] ?? t['kode_unik']}',
                                      flex: 3),
                                  AppTableCell.text(
                                      _formatWaktu('${t['dibuat_pada']}'),
                                      flex: 2),
                                  AppTableCell.text(
                                      '${payload['kasir'] ?? '-'}',
                                      flex: 2),
                                  AppTableCell(
                                    flex: 4,
                                    child: Tooltip(
                                      message: penerima.isEmpty
                                          ? 'Belum ada acknowledgement dari kasir/perangkat lain.'
                                          : penerima,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '$jumlahKasir kasir · $jumlahMesin mesin',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.5,
                                              color: jumlahMesin > 0
                                                  ? AppColors.success
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            penerima.isEmpty
                                                ? 'Belum tersalin ke POS lain'
                                                : penerima,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 11.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AppTableCell.text(
                                      pesanError.isEmpty
                                          ? namaCaraBayar
                                          : '$namaCaraBayar - $pesanError',
                                      flex: 2,
                                      maxLines: 2),
                                  AppTableCell.text(
                                      _formatRupiah
                                          .format(payload['total'] ?? 0),
                                      flex: 2,
                                      align: TextAlign.right,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5)),
                                  AppTableCell(
                                    flex: 2,
                                    align: TextAlign.center,
                                    child: StatusPill(
                                        label:
                                            synced ? 'Tersinkron' : 'Tertunda',
                                        warna: synced
                                            ? AppColors.success
                                            : AppColors.warning),
                                  ),
                                ]);
                              }).toList(),
                              pagination: AppTablePagination(
                                halaman: _halaman,
                                totalHalaman: _totalHalaman,
                                totalData: _total,
                                labelData: 'transaksi',
                                onSebelumnya: _halaman > 1
                                    ? () => _pindah(_halaman - 1)
                                    : null,
                                onBerikutnya: _halaman < _totalHalaman
                                    ? () => _pindah(_halaman + 1)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      )),
          ),
        ],
      ),
    );
  }
}
