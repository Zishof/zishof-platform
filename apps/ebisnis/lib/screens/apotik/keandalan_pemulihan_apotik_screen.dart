import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../services/transaksi_outbox_service.dart';
import '../../widgets/app_shell.dart';

class KeandalanPemulihanApotikScreen extends StatefulWidget {
  const KeandalanPemulihanApotikScreen({super.key});

  @override
  State<KeandalanPemulihanApotikScreen> createState() =>
      _KeandalanPemulihanApotikScreenState();
}

class _KeandalanPemulihanApotikScreenState
    extends State<KeandalanPemulihanApotikScreen> {
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _memuat = true;
  bool _menyinkronkan = false;
  String? _error;
  List<Map<String, dynamic>> _backup = const [];
  List<Map<String, Object?>> _arsipLokal = const [];
  int _pending = 0;
  int _gagal = 0;
  int _totalServer = 0;
  num _nilaiServer = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final server = await ApiClient.instance.aksi(
        'transaksi_backup_toko_list',
        const {'page': 1, 'pageSize': 100},
      );
      if (!ApiClient.statusResponsSukses(server['status'])) {
        throw Exception(server['message'] ?? 'Backup server gagal dimuat.');
      }
      final tertahan = await TransaksiOutboxService.instance.hitungTertahan();
      final arsip = await CoreDb.instance.transaksiArsipLokal(
        akunKunci: Sesi.instance.userId,
        tokoId: Sesi.instance.tokoId,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _backup = ((server['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _arsipLokal = arsip;
        _pending = tertahan.pending;
        _gagal = tertahan.gagal;
        _totalServer = (server['total'] as num?)?.toInt() ?? _backup.length;
        _nilaiServer = (server['totalNilai'] as num?) ?? 0;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _memuat = false;
      });
    }
  }

  Future<void> _sinkronkan() async {
    setState(() => _menyinkronkan = true);
    try {
      final hasil =
          await TransaksiOutboxService.instance.sinkronkan(sertakanGagal: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${hasil.berhasil} dari ${hasil.total} transaksi pulih.')),
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _menyinkronkan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Keandalan & Pemulihan',
      subjudul: 'Outbox lokal, replika transaksi, dan pemulihan otomatis',
      scrollable: false,
      actionsAppBar: [
        OutlinedButton.icon(
          onPressed: _memuat || _menyinkronkan ? null : _sinkronkan,
          icon: _menyinkronkan
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: const Text('Pulihkan & Sinkronkan'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Segarkan',
          onPressed: _memuat ? null : _muat,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _isi(),
    );
  }

  Widget _isi() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 10),
          Text(_error!),
          TextButton.icon(
            onPressed: _muat,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ]),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          _kpi('Backup server', _totalServer, Icons.cloud_done_outlined,
              const Color(0xFF0369A1)),
          _kpi('Sampel tervalidasi', _backup.length, Icons.verified_outlined,
              const Color(0xFF15803D)),
          _kpi('Arsip perangkat', _arsipLokal.length, Icons.computer_outlined,
              const Color(0xFF7C3AED)),
          _kpi(
              'Pending / gagal',
              _pending + _gagal,
              Icons.sync_problem_outlined,
              _gagal > 0 ? const Color(0xFFB91C1C) : const Color(0xFFC2410C)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF334155)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.shield_outlined, color: Colors.white, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Replika server ${_rupiah.format(_nilaiServer)} · '
                '$_pending transaksi menunggu · $_gagal perlu pemulihan',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Card(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: const Color(0xFFF1F5F9),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(children: [
                Expanded(
                    flex: 2,
                    child: Text('Transaksi / Waktu',
                        style: TextStyle(fontWeight: FontWeight.w900))),
                Expanded(
                    flex: 2,
                    child: Text('Perangkat / Kasir',
                        style: TextStyle(fontWeight: FontWeight.w900))),
                Expanded(
                    flex: 2,
                    child: Text('Pembeli / Metode',
                        style: TextStyle(fontWeight: FontWeight.w900))),
                Expanded(
                    child: Text('Qty / Total',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w900))),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _backup.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _baris(_backup[i]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _kpi(String label, int nilai, IconData ikon, Color warna) => Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: warna.withValues(alpha: .18)),
        ),
        child: Row(children: [
          Icon(ikon, color: warna),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$nilai',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ]),
      );

  Widget _baris(Map<String, dynamic> d) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
            flex: 2,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['nomorNota'] ?? d['kodeUnik']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${d['waktu']}', style: const TextStyle(fontSize: 11)),
            ]),
          ),
          Expanded(
            flex: 2,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['namaMesin'] ?? '-'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${d['kasir'] ?? d['kasirUserId'] ?? '-'}',
                  style: const TextStyle(fontSize: 11)),
            ]),
          ),
          Expanded(
            flex: 2,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['pembeli'] ?? '-'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${d['metode'] ?? '-'}',
                  style: const TextStyle(fontSize: 11)),
            ]),
          ),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${d['qty'] ?? 0} item'),
              Text(_rupiah.format((d['totalBiaya'] as num?) ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      );
}
