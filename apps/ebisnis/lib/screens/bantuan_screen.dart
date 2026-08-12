import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bantuan_content.dart';
import 'bantuan_kontekstual.dart';

/// Pusat bantuan POS yang tetap tersedia offline. Setiap artikel platform
/// memuat >= 1.000 kata, workflow, ilustrasi layar, checklist, dan diagnosis.
class BantuanScreen extends StatefulWidget {
  final String? menuId;
  final String? menuJudul;
  const BantuanScreen({super.key, this.menuId, this.menuJudul});

  @override
  State<BantuanScreen> createState() => _BantuanScreenState();
}

class _BantuanScreenState extends State<BantuanScreen> {
  int _terpilih = defaultTargetPlatform == TargetPlatform.android ? 1 : 0;
  String _cari = '';

  @override
  Widget build(BuildContext context) {
    final platformId =
        defaultTargetPlatform == TargetPlatform.android ? 'android' : 'desktop';
    final artikel = widget.menuId == null
        ? artikelBantuan[_terpilih]
        : artikelBantuanUntukMenu(
            widget.menuId!, widget.menuJudul ?? 'Halaman', platformId);
    final query = _cari.toLowerCase().trim();
    final bagian = artikel.bagian
        .where((b) =>
            query.isEmpty ||
            b.judul.toLowerCase().contains(query) ||
            b.isi.toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pusat Bantuan POS'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Semantics(
                label: '${artikel.jumlahKata} kata',
                child: Chip(label: Text('${artikel.jumlahKata} kata')),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final lebar = constraints.maxWidth >= 900;
          final navigasi = _NavigasiArtikel(
            terpilih: _terpilih,
            onPilih: (nilai) => setState(() {
              _terpilih = nilai;
              _cari = '';
            }),
          );
          final konten = _IsiArtikel(
            artikel: artikel,
            bagian: bagian,
            query: _cari,
            onCari: (nilai) => setState(() => _cari = nilai),
          );
          if (widget.menuId != null) return konten;
          return lebar
              ? Row(children: [
                  SizedBox(width: 290, child: navigasi),
                  const VerticalDivider(width: 1),
                  Expanded(child: konten),
                ])
              : Column(children: [
                  SizedBox(height: 96, child: navigasi),
                  const Divider(height: 1),
                  Expanded(child: konten),
                ]);
        },
      ),
    );
  }
}

class _NavigasiArtikel extends StatelessWidget {
  final int terpilih;
  final ValueChanged<int> onPilih;
  const _NavigasiArtikel({required this.terpilih, required this.onPilih});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final horizontal = c.maxWidth < 900;
      final cards = List.generate(artikelBantuan.length, (index) {
        final artikel = artikelBantuan[index];
        final aktif = terpilih == index;
        return SizedBox(
          width: horizontal ? 210 : null,
          child: Card(
            elevation: 0,
            color: aktif
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            child: ListTile(
              leading: Icon(
                index == 0
                    ? Icons.desktop_windows_outlined
                    : index == 1
                        ? Icons.phone_android_outlined
                        : Icons.language_outlined,
              ),
              title: Text(artikel.judul,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${artikel.jumlahKata} kata'),
              selected: aktif,
              onTap: () => onPilih(index),
            ),
          ),
        );
      });
      return horizontal
          ? ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: cards,
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('PILIH PLATFORM',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2)),
                ),
                ...cards,
              ],
            );
    });
  }
}

class _IsiArtikel extends StatelessWidget {
  final ArtikelBantuan artikel;
  final List<BagianBantuan> bagian;
  final String query;
  final ValueChanged<String> onCari;
  const _IsiArtikel({
    required this.artikel,
    required this.bagian,
    required this.query,
    required this.onCari,
  });

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        children: [
          Text(artikel.judul,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
          const SizedBox(height: 6),
          Text(artikel.ringkasan,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          TextField(
            onChanged: onCari,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Cari topik, misalnya offline, retur, atau printer',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          _WorkflowDiagram(langkahKonteks: artikel.workflow),
          const SizedBox(height: 20),
          _IlustrasiLayar(platform: artikel.id, areaKonteks: artikel.ilustrasi),
          const SizedBox(height: 20),
          if (bagian.isEmpty)
            const _InfoKosong()
          else
            ...bagian.asMap().entries.map((entry) => _BagianArtikel(
                  nomor: entry.key + 1,
                  bagian: entry.value,
                  terbuka: query.isNotEmpty || entry.key < 2,
                )),
          const SizedBox(height: 20),
          _Checklist(platform: artikel.judul),
        ],
      ),
    );
  }
}

class _WorkflowDiagram extends StatelessWidget {
  final List<String> langkahKonteks;
  const _WorkflowDiagram({this.langkahKonteks = const []});
  static const langkah = [
    ('1', 'Buka sesi', Icons.lock_open_outlined),
    ('2', 'Scan produk', Icons.qr_code_scanner),
    ('3', 'Cek keranjang', Icons.shopping_cart_outlined),
    ('4', 'Pilih bayar', Icons.payments_outlined),
    ('5', 'Validasi server', Icons.verified_user_outlined),
    ('6', 'Struk & sinkron', Icons.receipt_long_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final data = langkahKonteks.isEmpty
        ? langkah
        : List.generate(
            langkahKonteks.length,
            (i) => (
                  '${i + 1}',
                  langkahKonteks[i],
                  langkah[i % langkah.length].$3
                ));
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Diagram workflow transaksi',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
              'Ikuti dari kiri ke kanan. Bila satu tahap gagal, perbaiki tahap itu dan periksa riwayat sebelum mengulang.'),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                  data.length,
                  (i) => Row(children: [
                        Container(
                          width: 126,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                          ),
                          child: Column(children: [
                            CircleAvatar(
                              radius: 18,
                              child: Icon(data[i].$3, size: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(data[i].$1,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800)),
                            Text(data[i].$2,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        if (i < data.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5),
                            child: Icon(Icons.arrow_forward, size: 18),
                          ),
                      ])),
            ),
          ),
        ]),
      ),
    );
  }
}

class _IlustrasiLayar extends StatelessWidget {
  final String platform;
  final List<String> areaKonteks;
  const _IlustrasiLayar({required this.platform, this.areaKonteks = const []});

  @override
  Widget build(BuildContext context) {
    final mobile = platform == 'android';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ilustrasi cara membaca halaman',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(mobile
              ? 'Pada Android panel dibaca dari atas ke bawah dan dapat digulir.'
              : 'Pada layar lebar, katalog dan keranjang dibaca berdampingan.'),
          const SizedBox(height: 14),
          Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: mobile ? 360 : 760),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF172B4D),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _IlustrasiArea(mobile: mobile, areaKonteks: areaKonteks),
            ),
          ),
        ]),
      ),
    );
  }
}

class _IlustrasiArea extends StatelessWidget {
  final bool mobile;
  final List<String> areaKonteks;
  const _IlustrasiArea({required this.mobile, required this.areaKonteks});

  @override
  Widget build(BuildContext context) {
    final area = areaKonteks.isEmpty
        ? const [
            'Menu & status',
            'Pencarian',
            'Area data',
            'Ringkasan',
            'Tindakan utama'
          ]
        : areaKonteks;
    final warna = const [
      Color(0xFFEAF2FF),
      Color(0xFFFFFFFF),
      Color(0xFFF4F7FB),
      Color(0xFFFFF4E8),
      Color(0xFFE8FFF3)
    ];
    if (mobile) {
      return Column(
          children: List.generate(
              area.length,
              (i) => _MockArea('${i + 1}. ${area[i]}', warna[i % warna.length],
                  i == 2 ? 120 : 58)));
    }
    return Column(children: [
      _MockArea('1. ${area.first}', warna.first, 54),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 3,
            child: _MockArea(
                area
                    .skip(1)
                    .take(2)
                    .toList()
                    .asMap()
                    .entries
                    .map((e) => '${e.key + 2}. ${e.value}')
                    .join('\n'),
                warna[2],
                220)),
        Expanded(
            flex: 2,
            child: _MockArea(
                area
                    .skip(3)
                    .toList()
                    .asMap()
                    .entries
                    .map((e) => '${e.key + 4}. ${e.value}')
                    .join('\n'),
                warna[3],
                220)),
      ]),
    ]);
  }
}

class _MockArea extends StatelessWidget {
  final String label;
  final Color color;
  final double height;
  const _MockArea(this.label, this.color, this.height);
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        margin: const EdgeInsets.all(4),
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF172B4D), fontWeight: FontWeight.w700)),
      );
}

class _BagianArtikel extends StatelessWidget {
  final int nomor;
  final BagianBantuan bagian;
  final bool terbuka;
  const _BagianArtikel(
      {required this.nomor, required this.bagian, required this.terbuka});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          initiallyExpanded: terbuka,
          leading: CircleAvatar(radius: 16, child: Text('$nomor')),
          title: Text(bagian.judul,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(bagian.isi,
                  textAlign: TextAlign.justify,
                  style: const TextStyle(height: 1.65, fontSize: 15)),
            ),
          ],
        ),
      );
}

class _Checklist extends StatelessWidget {
  final String platform;
  const _Checklist({required this.platform});
  @override
  Widget build(BuildContext context) {
    const items = [
      'Outlet, pengguna, tanggal, sesi kas, dan koneksi sudah benar.',
      'Produk, jumlah, pelanggan, promo, pajak, dan total sudah dibaca ulang.',
      'Metode pembayaran serta nominal diterima sudah dikonfirmasi.',
      'Status transaksi diperiksa sebelum cetak ulang atau mencoba kembali.',
      'Antrean sinkronisasi kosong sebelum sesi ditutup.',
    ];
    return Card(
      color: const Color(0xFFE8FFF3),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Checklist cepat $platform',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF155B3D))),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 18, color: Color(0xFF16875D)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item)),
                    ]),
              )),
        ]),
      ),
    );
  }
}

class _InfoKosong extends StatelessWidget {
  const _InfoKosong();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(36),
        child: Center(child: Text('Topik tidak ditemukan. Coba kata lain.')),
      );
}
