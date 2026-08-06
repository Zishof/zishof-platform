import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
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
  static const _pageSize = 20;
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
      final hasil = await ApiClient.instance.aksi('laporan_order_list', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        if (_cariPembeli.isNotEmpty) 'cariPembeli': _cariPembeli,
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
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
          setStateIfMounted(() {
            _data =
                ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            _total = (hasil['total'] as num?)?.toInt() ?? 0;
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
            else if (_data.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('Belum ada transaksi pada rentang ini.')))
            else ...[
              ..._data.map((row) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text('${row['nomorNota']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                          '${_formatWaktu(row['waktu'])} · ${row['pembeli']}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatRupiah.format(row['totalBiaya'] ?? 0),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${row['metode']}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.primary)),
                        ],
                      ),
                      onTap: () => _lihatDetail(row),
                    ),
                  )),
              if (_total > _pageSize)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _halaman > 1
                              ? () => _pindah(_halaman - 1)
                              : null),
                      Text(
                          'Halaman $_halaman / $_totalHalaman ($_total transaksi)'),
                      IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _halaman < _totalHalaman
                              ? () => _pindah(_halaman + 1)
                              : null),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
