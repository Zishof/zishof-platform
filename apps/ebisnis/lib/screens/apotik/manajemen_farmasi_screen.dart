import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../widgets/app_shell.dart';
import 'kasir_apotik_screen.dart';
import 'laporan_apotik_screen.dart';
import 'menu_apotik_screen.dart';
import 'pasien_apotik_screen.dart';
import 'persediaan_apotik_screen.dart';

/// Pusat kerja tahap awal untuk seluruh pengembangan lanjutan Apotik.
///
/// Halaman langsung merender modul agar tetap dapat dipakai saat jaringan
/// terputus. Angka operasional adalah penyegaran read-only dari server; tidak
/// ada mutasi kritis yang diantrikan atau ditampilkan sukses secara lokal.
class ManajemenFarmasiScreen extends StatefulWidget {
  const ManajemenFarmasiScreen({super.key});

  @override
  State<ManajemenFarmasiScreen> createState() => _ManajemenFarmasiScreenState();
}

class _ManajemenFarmasiScreenState extends State<ManajemenFarmasiScreen> {
  bool _memuat = false;
  String? _pesan;
  final Map<String, num> _angka = {};

  static const _modul = <_ModulFarmasi>[
    _ModulFarmasi('Pasien & Alergi', 'Profil pasien dan riwayat alergi aktif',
        Icons.personal_injury_outlined, Color(0xFF7C3AED), 'pasien', 'pasien'),
    _ModulFarmasi('Telaah Klinis', 'Peringatan alergi dan daftar periksa resep',
        Icons.health_and_safety_outlined, Color(0xFFDC2626), 'resep', 'resep'),
    _ModulFarmasi(
        'Konseling & Histori',
        'Pemeriksaan kedua, konseling, dan jejak dispensing',
        Icons.record_voice_over_outlined,
        Color(0xFF2563EB),
        'resep',
        'resep'),
    _ModulFarmasi('Formula Racikan', 'Komposisi, biaya, dan penjualan racikan',
        Icons.science_outlined, Color(0xFF0891B2), 'racikan', 'racikan'),
    _ModulFarmasi(
        'Produksi & QC',
        'Formula produksi, batch hasil, dan kendali mutu',
        Icons.factory_outlined,
        Color(0xFF0F766E),
        'produksi',
        'produksi'),
    _ModulFarmasi(
        'Recall & Karantina',
        'Penahanan lot dan pengendalian obat bermasalah',
        Icons.report_gmailerrorred_outlined,
        Color(0xFFB91C1C),
        'batch',
        'batch'),
    _ModulFarmasi('Cold Chain', 'Pemantauan item suhu khusus dan kedaluwarsa',
        Icons.thermostat_outlined, Color(0xFF0284C7), 'batch', 'batch'),
    _ModulFarmasi(
        'Lokasi & Transfer',
        'Stok toko, gudang, rak, dan perpindahan',
        Icons.multiple_stop_outlined,
        Color(0xFF4F46E5),
        'item',
        'persediaan'),
    _ModulFarmasi('Perencanaan Stok', 'Stok minimum dan prioritas pemesanan',
        Icons.auto_graph_outlined, Color(0xFF15803D), 'item', 'persediaan'),
    _ModulFarmasi(
        'Supplier & Procurement',
        'PBF, penerimaan, retur, dan rekonsiliasi dokumen',
        Icons.local_shipping_outlined,
        Color(0xFFC2410C),
        'item',
        'pengadaan'),
    _ModulFarmasi('Kas & Handover', 'Sesi kas, pembayaran, dan serah terima',
        Icons.point_of_sale_outlined, Color(0xFF047857), 'penjualan', 'kas'),
    _ModulFarmasi(
        'Audit & Persetujuan',
        'Jejak transaksi, idempotensi, dan maker-checker',
        Icons.fact_check_outlined,
        Color(0xFF475569),
        'penjualan',
        'laporan'),
    _ModulFarmasi(
        'Integrasi & Delivery',
        'Antrean resep, status penyiapan, dan pengiriman',
        Icons.hub_outlined,
        Color(0xFF0369A1),
        'resep',
        'resep'),
    _ModulFarmasi(
        'Membership & Refill',
        'Pengingat obat rutin dan layanan pelanggan',
        Icons.loyalty_outlined,
        Color(0xFFBE185D),
        'pasien',
        'pasien'),
    _ModulFarmasi(
        'Business Intelligence',
        'Penjualan, stok, kedaluwarsa, dan performa farmasi',
        Icons.insights_outlined,
        Color(0xFF4338CA),
        'penjualan',
        'laporan'),
  ];

  @override
  void initState() {
    super.initState();
    _segarkan();
  }

  Future<Map<String, dynamic>> _aman(
      String aksi, Map<String, dynamic> body) async {
    try {
      return await ApiClient.instance.aksi(aksi, body);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  int _jumlah(Map<String, dynamic> r) {
    final total = r['total'];
    if (total is num) return total.toInt();
    return ((r['data'] as List?) ?? const []).length;
  }

  Future<void> _segarkan() async {
    if (_memuat) return;
    setState(() {
      _memuat = true;
      _pesan = null;
    });
    final hasil = await Future.wait([
      _aman('apotik_item_cari', const {'page_size': 100}),
      _aman('apotik_resep_list',
          const {'hanya_menunggu': true, 'page_size': 100}),
      _aman('apotik_pasien_cari', const {'page_size': 100}),
      _aman('apotik_racikan_list', const {'page_size': 100}),
      _aman('apotik_produksi_katalog', const {'page_size': 100}),
      _aman('apotik_batch_monitor', const {'page_size': 100}),
      _aman('apotik_laporan_penjualan', const {'page_size': 100}),
    ]);
    if (!mounted) return;
    final semuaKosong = hasil.every((e) => e.isEmpty);
    setState(() {
      _angka
        ..clear()
        ..addAll({
          'item': _jumlah(hasil[0]),
          'resep': _jumlah(hasil[1]),
          'pasien': _jumlah(hasil[2]),
          'racikan': _jumlah(hasil[3]),
          'produksi': _jumlah(hasil[4]),
          'batch': _jumlah(hasil[5]),
          'penjualan': _jumlah(hasil[6]),
        });
      _memuat = false;
      if (semuaKosong) {
        _pesan = 'Modul tetap tersedia. Angka operasional akan diperbarui '
            'saat server dapat dihubungi.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Manajemen Farmasi',
      subjudul: 'Keselamatan klinis, operasional, supply chain, dan analitik',
      scrollable: false,
      actionsAppBar: [
        IconButton(
          tooltip: 'Segarkan angka operasional',
          onPressed: _memuat ? null : _segarkan,
          icon: _memuat
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
        ),
      ],
      body: LayoutBuilder(builder: (context, constraints) {
        final kolom = constraints.maxWidth >= 1500
            ? 4
            : constraints.maxWidth >= 980
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _RingkasanFarmasi(angka: _angka, pesan: _pesan),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _kartu(_modul[index]),
                childCount: _modul.length,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: kolom,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: kolom == 1 ? 2.7 : 1.65,
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _kartu(_ModulFarmasi modul) {
    final angka = _angka[modul.kunciAngka];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _buka(modul),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: modul.warna.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(modul.ikon, color: modul.warna),
              ),
              const Spacer(),
              if (angka != null)
                Text('$angka data',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: modul.warna)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ]),
            const Spacer(),
            Text(modul.nama,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(modul.deskripsi,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  void _buka(_ModulFarmasi modul) {
    final Widget tujuan = switch (modul.tujuan) {
      'pasien' => const PasienApotikScreen(),
      'resep' => const TebusResepApotikScreen(),
      'racikan' => const RacikanApotikScreen(),
      'produksi' => const ProduksiFarmasiApotikScreen(),
      'batch' => const PersediaanApotikScreen(tabAwal: 1),
      'pengadaan' => const PersediaanApotikScreen(tabAwal: 2),
      'persediaan' => const PersediaanApotikScreen(),
      'kas' =>
        const LaporanApotikScreen(tabAwal: LaporanApotikScreen.tabRekonsiliasi),
      'laporan' => const LaporanApotikScreen(),
      _ => const KasirApotikScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => tujuan));
  }
}

class _RingkasanFarmasi extends StatelessWidget {
  final Map<String, num> angka;
  final String? pesan;
  const _RingkasanFarmasi({required this.angka, required this.pesan});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF0F766E)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 28,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const SizedBox(
              width: 330,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pusat Kendali Apotik',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  SizedBox(height: 5),
                  Text(
                      'Satu ruang kerja untuk pelayanan pasien, stok, kas, '
                      'mutu, dan pengembangan bisnis.',
                      style: TextStyle(color: Color(0xFFD1FAE5), height: 1.4)),
                ],
              ),
            ),
            for (final e in const [
              ('item', 'Obat'),
              ('resep', 'Resep'),
              ('racikan', 'Racikan'),
              ('batch', 'Batch'),
            ])
              SizedBox(
                width: 82,
                child: Column(children: [
                  Text('${angka[e.$1] ?? '—'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  Text(e.$2,
                      style: const TextStyle(
                          color: Color(0xFFD1FAE5), fontSize: 11.5)),
                ]),
              ),
            if (pesan != null)
              SizedBox(
                width: 320,
                child: Text(pesan!,
                    style: const TextStyle(
                        color: Color(0xFFFEF3C7), fontSize: 11.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModulFarmasi {
  final String nama;
  final String deskripsi;
  final IconData ikon;
  final Color warna;
  final String kunciAngka;
  final String tujuan;
  const _ModulFarmasi(this.nama, this.deskripsi, this.ikon, this.warna,
      this.kunciAngka, this.tujuan);
}
