import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/sesi.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';
import '../widgets/app_shell.dart';
import '../widgets/navigasi.dart';

/// Ringkasan belanja member: jumlah transaksi, pengeluaran, penghematan,
/// total topup, tren 6 bulan, dan toko favorit (aksi `kantin_dashboard`).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _memuat = true;
  String? _galat;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final res = await ApiClient.instance.aksi('kantin_dashboard', const {});
      final d = res['data'];
      _data = d is Map ? d.map((k, v) => MapEntry('$k', v)) : {};
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  List<Map<String, dynamic>> _daftar(String kunci) {
    final v = _data[kunci];
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => e.map((k, x) => MapEntry('$k', x)))
          .toList();
    }
    return const [];
  }

  num _num(String kunci) {
    final v = _data[kunci];
    return v is num ? v : 0;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuAnggota.ringkasan,
      judul: 'Ringkasan Belanja',
      subjudul: 'Rekap transaksi, penghematan, dan toko favorit Anda.',
      onPilihMenu: navigasiMenu,
      child: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: PanelGalat(pesan: _galat!, onCobaLagi: _muat),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 1.9,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        children: [
                          _kartu('Jumlah transaksi',
                              angka(_num('jml_trx')), Icons.receipt_long),
                          _kartu('Total pengeluaran',
                              rupiah(_num('total_pengeluaran')),
                              Icons.payments_outlined),
                          _kartu('Total hemat', rupiah(_num('total_hemat')),
                              Icons.savings_outlined),
                          _kartu('Total isi ${Sesi.instance.labelSaldo}',
                              rupiah(_num('total_topup')),
                              Icons.account_balance_wallet_outlined),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('Tren 6 bulan terakhir',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _tren(),
                      const SizedBox(height: 20),
                      const Text('Toko favorit',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _tokoFavorit(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _kartu(String label, String nilai, IconData ikon) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(ikon,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(nilai,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Batang sederhana relatif terhadap bulan tertinggi -- cukup untuk
  /// membandingkan besaran tanpa menambah pustaka grafik.
  Widget _tren() {
    final data = _daftar('trend');
    if (data.isEmpty) return const Text('Belum ada data.');
    final maks = data
        .map((e) => (e['total_nominal'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      children: data.map((e) {
        final nilai = (e['total_nominal'] as num?)?.toDouble() ?? 0;
        final rasio = maks <= 0 ? 0.0 : nilai / maks;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text('${e['bulan_label'] ?? ''}',
                    style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: rasio,
                    minHeight: 14,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(rupiah(nilai),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _tokoFavorit() {
    final data = _daftar('toko_favorit');
    if (data.isEmpty) return const Text('Belum ada data.');
    return Column(
      children: data
          .map((e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: Text('${e['nama_toko'] ?? '-'}'),
                trailing: Text(
                    rupiah((e['total_nominal'] as num?)?.toDouble() ?? 0)),
              ))
          .toList(),
    );
  }
}
