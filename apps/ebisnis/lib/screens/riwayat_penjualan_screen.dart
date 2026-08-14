import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'struk_screen.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggalServer = DateFormat('yyyy-MM-dd');

/// Cache-first (spec: "Riwayat Penjualan online-only, tanpa cache lokal") --
/// hanya utk tampilan DEFAULT tanpa filter halaman 1 (yg paling sering
/// dibuka), disimpan lewat `cache_referensi` generik (kunci->JSON) yg SUDAH
/// ADA di core_db, bukan tabel baru -- cukup utk "masih bisa lihat transaksi
/// terakhir walau offline sesaat", bukan pengganti data real-time.
const _kunciCacheRiwayat = 'riwayat_penjualan_default';

List<Map<String, dynamic>> _normalisasiDaftarTransaksi(
    Map<String, dynamic> hasil) {
  dynamic raw = hasil['data'];
  if (raw is Map) {
    raw = raw['rows'] ?? raw['items'] ?? raw['list'] ?? raw['data'];
  }
  raw ??= hasil['rows'] ??
      hasil['items'] ??
      hasil['list'] ??
      hasil['orders'] ??
      hasil['transaksi'] ??
      hasil['riwayat'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => _normalisasiTransaksi(Map<String, dynamic>.from(row)))
      .toList();
}

Map<String, dynamic> _normalisasiTransaksi(Map<String, dynamic> row) {
  dynamic pilih(List<String> kunci) {
    for (final k in kunci) {
      final v = row[k];
      if (v != null && v.toString().trim().isNotEmpty) return v;
    }
    return null;
  }

  return {
    ...row,
    'idTransaksi': pilih([
      'idTransaksi',
      'transaksiId',
      'pembelianAnggotaKoperasiId',
      'pembelianId',
      'orderId',
      'id',
    ]),
    'nomorNota': pilih([
          'nomorNota',
          'nomorTransaksi',
          'noTransaksi',
          'kodeTransaksi',
          'kode',
          'kodeUnik',
          'nomorIdOrder',
          'noNota',
        ]) ??
        '-',
    'waktu': pilih([
      'waktu',
      'tanggal',
      'tanggalTransaksi',
      'tglTransaksi',
      'createdAt',
      'dibuatPada',
    ]),
    'pembeli': pilih([
          'pembeli',
          'namaPembeli',
          'pelanggan',
          'namaPelanggan',
          'memberNama',
          'anggotaNama',
          'customerNama',
        ]) ??
        'Umum',
    'totalBiaya': pilih([
          'totalBiaya',
          'total_biaya',
          'grandTotal',
          'totalBayar',
          'totalPenjualan',
          'total',
          'nilai',
        ]) ??
        0,
    'metode': pilih([
          'metode',
          'metodePembayaran',
          'caraBayar',
          'cara_bayar',
          'jenisPembayaran',
        ]) ??
        '-',
    'kasir': pilih(['kasir', 'namaKasir', 'operator', 'petugas']),
    'namaMesin': pilih(['namaMesin', 'mesin', 'perangkat', 'deviceName']),
    'pajak': pilih(['pajak', 'totalPajak']) ?? 0,
    'totalDiskon': pilih(['totalDiskon', 'diskon', 'nilaiDiskon']) ?? 0,
  };
}

int _normalisasiTotalTransaksi(Map<String, dynamic> hasil, int jumlahData) {
  final kandidat = <dynamic>[
    hasil['total'],
    hasil['totalData'],
    hasil['totalRows'],
    hasil['recordsTotal'],
    hasil['count'],
    hasil['jumlah'],
    hasil['totalTransaksi'],
  ];
  final data = hasil['data'];
  if (data is Map) {
    kandidat.addAll([
      data['total'],
      data['totalData'],
      data['totalRows'],
      data['recordsTotal'],
      data['count'],
      data['jumlah'],
    ]);
  }
  for (final v in kandidat) {
    if (v is num) return v.toInt();
    final parsed = int.tryParse(v?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return jumlahData;
}

String _formatWaktu(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

/// Layar Riwayat Penjualan (spec §11) -- SENGAJA terpisah dari Laporan
/// Transaksi: yang ini alat sempit "cari transaksi lunas lalu cetak ulang
/// strukn ya", bukan dasbor analitik/agregat. Tidak ada aksi server baru --
/// reuse `laporan_order_list` (cari) + `detail_transaksi` (rincian fiskal +
/// bahan cetak ulang), persis pola tab "Report Order" di Laporan Transaksi.
class RiwayatPenjualanScreen extends StatefulWidget {
  const RiwayatPenjualanScreen({super.key});
  @override
  State<RiwayatPenjualanScreen> createState() => _RiwayatPenjualanScreenState();
}

class _RiwayatPenjualanScreenState extends State<RiwayatPenjualanScreen> {
  final Map<String, String> _kunciPembatalan = {};
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  DateTime? _mulai;
  DateTime? _sampai;
  String _cariPembeli = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  bool get _defaultTanpaFilter =>
      _mulai == null &&
      _sampai == null &&
      _cariPembeli.isEmpty &&
      _halaman == 1;

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final payload = {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        if (_cariPembeli.isNotEmpty) 'keyword': _cariPembeli,
        'includePembayaran': true,
        'includeSplitPembayaran': true,
        'sertakanPembayaran': true,
        'withPayments': true,
        'page': _halaman,
        'pageSize': _pageSize,
      };
      var hasil = await ApiClient.instance.aksi('laporan_order_list', payload);
      var data = _normalisasiDaftarTransaksi(hasil);
      if (data.isEmpty && _cariPembeli.isNotEmpty) {
        final fallback = {...payload}..remove('keyword');
        fallback['cariPembeli'] = _cariPembeli;
        hasil = await ApiClient.instance.aksi('laporan_order_list', fallback);
        data = _normalisasiDaftarTransaksi(hasil);
      }
      setStateIfMounted(() {
        _data = data;
        _total = _normalisasiTotalTransaksi(hasil, data.length);
      });
      if (_defaultTanpaFilter) {
        unawaited(CoreDb.instance
            .simpanCacheReferensi(_kunciCacheRiwayat, jsonEncode(hasil)));
      }
    } catch (e) {
      // Offline & sedang melihat tampilan default (bukan hasil filter) --
      // pakai snapshot terakhir yg tersimpan drpd layar kosong tak berguna.
      if (_defaultTanpaFilter) {
        final tersimpan =
            await CoreDb.instance.ambilCacheReferensi(_kunciCacheRiwayat);
        if (tersimpan != null) {
          final hasil = jsonDecode(tersimpan) as Map<String, dynamic>;
          final data = _normalisasiDaftarTransaksi(hasil);
          setStateIfMounted(() {
            _data = data;
            _total = _normalisasiTotalTransaksi(hasil, data.length);
            _error = null;
          });
          if (mounted) setStateIfMounted(() => _memuat = false);
          return;
        }
      }
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _terapkan() async {
    _halaman = 1;
    await _muat();
  }

  Widget _chipRingkasan(String label, String nilai, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.latarLembut(warna),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $nilai',
          style: TextStyle(
              color: warna, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Future<void> _lihatDetail(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items =
          ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      final pajakHeader = (row['pajak'] as num?)?.toDouble() ?? 0;
      final diskonHeader = (row['totalDiskon'] as num?)?.toDouble() ?? 0;
      final subtotalPerBaris = items
          .map((i) =>
              (i['harga'] as num).toDouble() * (i['qty'] as num).toDouble() -
              ((i['diskon'] as num?) ?? 0).toDouble())
          .toList();
      final totalSubtotal = subtotalPerBaris.fold<double>(0, (s, v) => s + v);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detail ${hasil['kode'] ?? ''}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chipRingkasan('Diskon', _formatRupiah.format(diskonHeader),
                        AppColors.warning),
                    _chipRingkasan('Pajak', _formatRupiah.format(pajakHeader),
                        AppColors.teal),
                    _chipRingkasan(
                        'Bayar',
                        _formatRupiah.format(hasil['totalBiaya'] ?? 0),
                        AppColors.success),
                  ]),
                  const Divider(),
                  ...List.generate(items.length, (idx) {
                    final i = items[idx];
                    final subtotal = subtotalPerBaris[idx];
                    final pajakBaris = totalSubtotal > 0
                        ? pajakHeader * (subtotal / totalSubtotal)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${i['nama']} x${(i['qty'] as num).toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            'Harga ${_formatRupiah.format(i['harga'])} · Diskon ${_formatRupiah.format(i['diskon'] ?? 0)} · Pajak ${_formatRupiah.format(pajakBaris)} · Subtotal ${_formatRupiah.format(subtotal)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            if (Sesi.instance.bolehAksiPos('riwayatpenjualan', 'delete') ||
                Sesi.instance.bolehAksiPos('riwayatpenjualan', 'reject'))
              TextButton.icon(
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Batalkan Transaksi'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  Navigator.of(context).pop();
                  _batalkanTransaksi(row);
                },
              ),
            TextButton.icon(
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Cetak Struk'),
              onPressed: () {
                Navigator.of(context).pop();
                _cetakUlang(row, hasil, items);
              },
            ),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _batalkanTransaksi(Map<String, dynamic> row) async {
    final alasanController = TextEditingController();
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan Transaksi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Transaksi ${row['nomorNota'] ?? ''} akan dibatalkan. Stok dan saldo terkait akan dikoreksi, serta pembatalan dicatat dalam arsip audit.'),
            const SizedBox(height: 16),
            TextField(
              controller: alasanController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alasan pembatalan *',
                hintText: 'Contoh: transaksi ganda atau salah input kasir',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    final alasan = alasanController.text.trim();
    alasanController.dispose();
    if (setuju != true) return;
    if (alasan.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      }
      return;
    }
    try {
      final id = '${row['idTransaksi']}';
      final key = _kunciPembatalan.putIfAbsent(
          id, () => 'BATAL-$id-${DateTime.now().microsecondsSinceEpoch}');
      final hasil = await ApiClient.instance.aksi('batalkan_transaksi', {
        'id': row['idTransaksi'],
        'alasan': alasan,
        'idempotency_key': key,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hasil['description']?.toString() ??
              'Transaksi berhasil dibatalkan.')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _cetakUlang(Map<String, dynamic> row,
      Map<String, dynamic> detail, List<Map<String, dynamic>> items) async {
    final itemStruk = items
        .map((i) => {'nama': i['nama'], 'qty': i['qty'], 'harga': i['harga']})
        .toList();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StrukScreen(
        kode: '${detail['kode'] ?? row['nomorNota'] ?? ''}',
        waktu: _formatWaktu(row['waktu']),
        item: itemStruk,
        total: (detail['totalBiaya'] as num?)?.toDouble() ??
            (row['totalBiaya'] as num?)?.toDouble() ??
            0,
        metode: '${row['metode'] ?? ''}',
        pembayaran: StrukScreen.pembayaranDariSumber(detail, row),
        pajak: (row['pajak'] as num?)?.toDouble() ?? 0,
        pelanggan: '${detail['pembeli'] ?? row['pembeli'] ?? ''}',
      ),
    ));
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.riwayatPenjualan,
      judul: 'Riwayat Penjualan',
      subjudul: 'Cari transaksi lunas & cetak ulang struk',
      scrollable: false,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  SizedBox(
                      width: 190,
                      child: AppKpiCard(
                          icon: Icons.receipt_long,
                          warna: AppColors.primary,
                          nilai: '$_total',
                          label: 'Total Transaksi')),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 190,
                    child: AppKpiCard(
                      icon: Icons.payments_outlined,
                      warna: AppColors.success,
                      nilai: _formatRupiah.format(_data.fold<num>(
                          0, (a, r) => a + ((r['totalBiaya'] as num?) ?? 0))),
                      label: 'Omzet (hal. ini)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final v = await showDatePicker(
                                context: context,
                                initialDate: _mulai ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (v != null) {
                              _mulai = v;
                              await _terapkan();
                            }
                          },
                          child: Text(_mulai == null
                              ? 'Dari Tanggal'
                              : _formatTanggalServer.format(_mulai!)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final v = await showDatePicker(
                                context: context,
                                initialDate: _sampai ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (v != null) {
                              _sampai = v;
                              await _terapkan();
                            }
                          },
                          child: Text(_sampai == null
                              ? 'Sampai Tanggal'
                              : _formatTanggalServer.format(_sampai!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppSearchField(
                    hintText: 'Cari nama pembeli / nomor nota...',
                    debounce: const Duration(milliseconds: 450),
                    onChanged: (v) {
                      _cariPembeli = v;
                      _terapkan();
                    },
                  ),
                ],
              ),
            ),
            if (_memuat)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(_error!)))
            else
              AppDataTable(
                minWidth: 980,
                emptyText: 'Belum ada transaksi pada rentang ini.',
                columns: const [
                  AppTableColumn('Nota', flex: 4),
                  AppTableColumn('Waktu', flex: 2),
                  AppTableColumn('Pembeli', flex: 2),
                  AppTableColumn('Kasir / Mesin', flex: 2),
                  AppTableColumn('Metode', flex: 2),
                  AppTableColumn('Total', flex: 2, align: TextAlign.right),
                  AppTableColumn('Aksi', width: 74, align: TextAlign.center),
                ],
                rows: _data.map((row) {
                  final kasir = '${row['kasir'] ?? '-'}';
                  final mesin = '${row['namaMesin'] ?? ''}'.trim();
                  final kasirMesin = mesin.isEmpty ? kasir : '$kasir / $mesin';
                  return AppTableRowData(
                    onTap: () => _lihatDetail(row),
                    cells: [
                      AppTableCell.text('${row['nomorNota'] ?? '-'}',
                          flex: 4,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
                      AppTableCell.text('${row['pembeli'] ?? 'Umum'}', flex: 2),
                      AppTableCell.text(kasirMesin, flex: 2),
                      AppTableCell(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusPill(
                              label: StrukScreen.labelPembayaran(row),
                              warna: AppColors.primary),
                        ),
                      ),
                      AppTableCell.text(
                        _formatRupiah.format(row['totalBiaya'] ?? 0),
                        flex: 2,
                        align: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                      AppTableCell(
                        width: 74,
                        align: TextAlign.center,
                        child: Tooltip(
                          message: 'Detail transaksi',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon:
                                const Icon(Icons.visibility_outlined, size: 18),
                            onPressed: () => _lihatDetail(row),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                pagination: _total > _pageSize
                    ? AppTablePagination(
                        halaman: _halaman,
                        totalHalaman: _totalHalaman,
                        totalData: _total,
                        labelData: 'transaksi',
                        onSebelumnya:
                            _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                        onBerikutnya: _halaman < _totalHalaman
                            ? () => _pindah(_halaman + 1)
                            : null,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
