import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../widgets/app_shell.dart';
import '../riwayat_audit_screen.dart';
import 'delivery_apotik_screen.dart';
import 'membership_apotik_screen.dart';

class AuditPersetujuanApotikScreen extends StatefulWidget {
  const AuditPersetujuanApotikScreen({super.key});

  @override
  State<AuditPersetujuanApotikScreen> createState() =>
      _AuditPersetujuanApotikScreenState();
}

class _AuditPersetujuanApotikScreenState
    extends State<AuditPersetujuanApotikScreen> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _delivery = const [];
  List<Map<String, dynamic>> _member = const [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  bool _sukses(Map<String, dynamic> hasil) =>
      ApiClient.statusResponsSukses(hasil['status']);

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await Future.wait([
        ApiClient.instance.aksi('apotik_delivery_list', const {
          'page': 1,
          'page_size': 100,
        }),
        ApiClient.instance.aksi('apotik_membership_list', const {
          'page': 1,
          'page_size': 100,
        }),
      ]);
      if (!_sukses(hasil[0]) || !_sukses(hasil[1])) {
        throw Exception('Antrean persetujuan belum dapat dimuat.');
      }
      if (!mounted) return;
      setState(() {
        _delivery = _data(hasil[0]);
        _member = _data(hasil[1]);
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

  List<Map<String, dynamic>> _data(Map<String, dynamic> hasil) =>
      ((hasil['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AppShell(
        menuAktif: MenuEBisnis.manajemenFarmasiApotik,
        judul: 'Audit & Persetujuan Apotik',
        subjudul: 'Jejak perubahan, kontrol operasional, dan maker-checker',
        scrollable: false,
        actionsAppBar: [
          IconButton(
            tooltip: 'Segarkan antrean',
            onPressed: _memuat ? null : _muat,
            icon: const Icon(Icons.refresh),
          ),
        ],
        body: Column(children: [
          const Material(
            color: Colors.white,
            child: TabBar(tabs: [
              Tab(icon: Icon(Icons.history), text: 'Jejak Audit'),
              Tab(icon: Icon(Icons.approval_outlined), text: 'Persetujuan'),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              const RiwayatAuditScreen(
                entitasAwal: 'apotik_item',
                menuAktif: MenuEBisnis.manajemenFarmasiApotik,
                embedded: true,
                cariOtomatis: true,
              ),
              _persetujuan(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _persetujuan() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
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

    final deliveryAktif = _delivery
        .where((e) => !{'TERKIRIM', 'DIBATALKAN'}.contains('${e['status']}'))
        .length;
    final tanpaConsent =
        _member.where((e) => e['consentNotifikasi'] != true).length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _angka('Delivery dimuat', _delivery.length, Icons.delivery_dining,
              const Color(0xFF0369A1)),
          _angka('Perlu tindak lanjut', deliveryAktif, Icons.pending_actions,
              const Color(0xFFC2410C)),
          _angka('Member dimuat', _member.length, Icons.loyalty_outlined,
              const Color(0xFFBE185D)),
          _angka('Tanpa consent', tanpaConsent,
              Icons.notifications_off_outlined, const Color(0xFFB91C1C)),
        ]),
        const SizedBox(height: 14),
        Expanded(child: LayoutBuilder(builder: (context, batas) {
          final delivery = _daftarDelivery();
          final member = _daftarMember();
          if (batas.maxWidth < 900) {
            return ListView(children: [
              SizedBox(height: 430, child: delivery),
              const SizedBox(height: 12),
              SizedBox(height: 430, child: member),
            ]);
          }
          return Row(children: [
            Expanded(child: delivery),
            const SizedBox(width: 12),
            Expanded(child: member),
          ]);
        })),
      ]),
    );
  }

  Widget _angka(String label, int nilai, IconData ikon, Color warna) =>
      Container(
        width: 210,
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

  Widget _daftarDelivery() => _panel(
        judul: 'Kontrol Delivery',
        ikon: Icons.delivery_dining_outlined,
        warna: const Color(0xFF0369A1),
        onBuka: () => _buka(const DeliveryApotikScreen()),
        data: _delivery,
        item: (d) => ListTile(
          dense: true,
          leading: const Icon(Icons.local_shipping_outlined),
          title: Text('${d['kode']} · ${d['namaPenerima']}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${d['kurir']} · ${d['status']}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _buka(const DeliveryApotikScreen()),
        ),
      );

  Widget _daftarMember() => _panel(
        judul: 'Kontrol Member & Refill',
        ikon: Icons.loyalty_outlined,
        warna: const Color(0xFFBE185D),
        onBuka: () => _buka(const MembershipApotikScreen()),
        data: _member,
        item: (m) => ListTile(
          dense: true,
          leading: Icon(m['consentNotifikasi'] == true
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined),
          title: Text('${m['kode']} · ${m['nama']}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text('${m['status']} · refill ${m['tanggalRefillBerikut']}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _buka(const MembershipApotikScreen()),
        ),
      );

  Widget _panel({
    required String judul,
    required IconData ikon,
    required Color warna,
    required VoidCallback onBuka,
    required List<Map<String, dynamic>> data,
    required Widget Function(Map<String, dynamic>) item,
  }) =>
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            color: warna.withValues(alpha: .08),
            child: Row(children: [
              Icon(ikon, color: warna),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(judul,
                      style: const TextStyle(fontWeight: FontWeight.w900))),
              TextButton.icon(
                onPressed: onBuka,
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Buka'),
              ),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: data.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => item(data[i]),
            ),
          ),
        ]),
      );

  void _buka(Widget layar) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => layar),
      );
}
