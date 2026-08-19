import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bantuan_content.dart';
import 'bantuan_kontekstual.dart';

/// Pusat bantuan POS yang tetap tersedia offline. Setiap artikel platform
/// memuat >= 3.500 kata, workflow, arus data, flowchart keputusan, ilustrasi
/// layar, checklist, dan diagnosis dalam bahasa operasional nonteknis.
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
          // Dua diagram khusus akuntansi: siklus dari transaksi sampai laporan, dan
          // aturan debet/kredit. Hanya tampil di menu akuntansi supaya halaman bantuan
          // menu lain tidak jadi panjang tanpa alasan.
          if (const [
            'jurnalUmum',
            'postingHpp',
            'postingPenjualan',
            'kodeAkun',
            'grupAkun',
            'jenisTransaksi',
            'bankAkun',
            'laporanKeuangan',
          ].contains(artikel.id)) ...[
            const _DiagramSiklusAkuntansi(),
            const SizedBox(height: 20),
            const _DiagramDebetKredit(),
            const SizedBox(height: 20),
          ],
          const _DiagramArusData(),
          const SizedBox(height: 20),
          const _DiagramKeputusan(),
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

/// Siklus akuntansi dari kejadian di toko sampai laporan keuangan.
///
/// Dibuat karena pertanyaan paling sering dari pengguna toko adalah "kenapa angka di
/// laporan belum berubah padahal transaksinya sudah ada": jawabannya hampir selalu ada
/// pada tahap POSTING yang belum dijalankan. Diagram ini menegaskan posisi tahap itu.
class _DiagramSiklusAkuntansi extends StatelessWidget {
  const _DiagramSiklusAkuntansi();

  static const tahap = <(String, String, IconData)>[
    ('1. Kejadian di toko', 'Penjualan kasir, kulakan, retur, opname, bayar utang',
        Icons.storefront_outlined),
    ('2. Jurnal', 'Kejadian diterjemahkan jadi debet & kredit — otomatis lewat Posting, atau manual lewat Jurnal Umum',
        Icons.edit_note),
    ('3. Posting', 'Jurnal draf resmi masuk buku besar. Sebelum tahap ini, laporan BELUM berubah',
        Icons.check_circle_outline),
    ('4. Buku Besar', 'Tiap akun terkumpul mutasi dan saldonya',
        Icons.menu_book_outlined),
    ('5. Neraca Saldo', 'Total debet harus sama dengan total kredit',
        Icons.balance),
    ('6. Laporan', 'Laba Rugi, Neraca, dan Arus Kas terbentuk dari saldo tiap akun',
        Icons.assessment_outlined),
  ];

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: const Color(0xFFEFF7EE),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Diagram siklus akuntansi: dari transaksi sampai laporan',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Angka pada laporan keuangan tidak muncul begitu saja dari transaksi kasir. '
                'Ia melewati enam tahap berikut. Bila laporan terasa belum berubah, periksa '
                'tahap 3: jurnalnya kemungkinan masih berstatus draf dan belum diposting.'),
            const SizedBox(height: 14),
            ...tahap.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFD8BD))),
                      child: Icon(t.$3, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.$1,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(t.$2,
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                    ),
                  ]),
                )),
            const Divider(height: 20),
            const Text(
                'Catatan: menghapus transaksi bukan cara mengoreksi. Koreksi dilakukan dengan '
                'membatalkan posting lalu memperbaiki, atau dengan membuat jurnal koreksi, '
                'supaya jejak pemeriksaan tetap utuh.',
                style: TextStyle(fontStyle: FontStyle.italic)),
          ]),
        ),
      );
}

/// Aturan debet/kredit dalam bentuk tabel ringkas — bagian yang paling sering
/// ditanyakan petugas non-akuntansi saat mengisi Jurnal Umum.
class _DiagramDebetKredit extends StatelessWidget {
  const _DiagramDebetKredit();

  static const baris = <(String, String, String)>[
    ('Harta / Aset (kas, bank, persediaan, piutang)', 'Bertambah', 'Berkurang'),
    ('Utang / Kewajiban (utang supplier, utang pajak)', 'Berkurang', 'Bertambah'),
    ('Modal / Ekuitas', 'Berkurang', 'Bertambah'),
    ('Pendapatan (penjualan, jasa, bunga)', 'Berkurang', 'Bertambah'),
    ('Beban / Biaya (HPP, listrik, gaji)', 'Bertambah', 'Berkurang'),
  ];

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: const Color(0xFFFFF6E6),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Diagram aturan debet dan kredit',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Setiap jurnal selalu punya dua sisi yang nilainya sama. Tabel ini menjawab '
                'pertanyaan "yang ini masuk debet atau kredit?".'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingRowHeight: 38,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 46,
                columns: const [
                  DataColumn(label: Text('Jenis akun')),
                  DataColumn(label: Text('Bila di DEBET')),
                  DataColumn(label: Text('Bila di KREDIT')),
                ],
                rows: baris
                    .map((b) => DataRow(cells: [
                          DataCell(Text(b.$1)),
                          DataCell(Text(b.$2)),
                          DataCell(Text(b.$3)),
                        ]))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
                'Contoh 1 — menerima uang sewa tunai Rp250.000: Kas (harta, bertambah) di '
                'DEBET 250.000; Pendapatan Sewa (pendapatan, bertambah) di KREDIT 250.000.\n'
                'Contoh 2 — membayar listrik tunai Rp300.000: Beban Listrik (beban, bertambah) '
                'di DEBET 300.000; Kas (harta, berkurang) di KREDIT 300.000.\n'
                'Contoh 3 — membayar utang supplier Rp1.000.000 lewat bank: Utang Supplier '
                '(kewajiban, berkurang) di DEBET 1.000.000; Bank (harta, berkurang) di '
                'KREDIT 1.000.000.'),
          ]),
        ),
      );
}

class _DiagramArusData extends StatelessWidget {
  const _DiagramArusData();

  static const tahap = <(String, IconData)>[
    ('Perangkat pengguna', Icons.devices_outlined),
    ('Penyimpanan lokal', Icons.storage_outlined),
    ('Pemeriksaan server', Icons.rule_folder_outlined),
    ('Database & audit', Icons.verified_outlined),
    ('Laporan & tindak lanjut', Icons.assessment_outlined),
  ];

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: const Color(0xFFEAF2FF),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Diagram arus data',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Data bergerak melalui urutan ini. Respons berhasil dari server menjadi tanda bahwa data pusat sudah menerima transaksi.'),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  tahap.length,
                  (index) => Row(children: [
                    Container(
                      width: 138,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB8C9E6)),
                      ),
                      child: Column(children: [
                        Icon(tahap[index].$2,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 7),
                        Text(tahap[index].$1,
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (index < tahap.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 5),
                        child: Icon(Icons.arrow_forward, size: 19),
                      ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}

class _DiagramKeputusan extends StatelessWidget {
  const _DiagramKeputusan();

  Widget _kotak(String teks, Color warna, {IconData? ikon}) => Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: warna,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ikon != null) ...[Icon(ikon, size: 19), const SizedBox(width: 8)],
          Flexible(
              child: Text(teks,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Flowchart saat muncul kendala',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Gunakan alur keputusan ini agar transaksi tidak dibuat dua kali dan bukti masalah tetap lengkap.'),
            const SizedBox(height: 14),
            Center(
                child: _kotak('Muncul peringatan atau proses terasa lama',
                    const Color(0xFFFFF4E0),
                    ikon: Icons.warning_amber_rounded)),
            const Center(child: Icon(Icons.arrow_downward, size: 20)),
            Center(
                child: _kotak('Apakah server sudah menyatakan berhasil?',
                    const Color(0xFFEAF2FF),
                    ikon: Icons.help_outline)),
            const Center(child: Icon(Icons.arrow_downward, size: 20)),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _kotak(
                    'YA — buka riwayat, gunakan data yang sama, lalu cetak ulang bila perlu.',
                    const Color(0xFFE8FFF3),
                    ikon: Icons.check_circle_outline),
                _kotak(
                    'BELUM / TIDAK PASTI — jangan ulangi. Periksa antrean lokal, koneksi, dan Informasi Teknis.',
                    const Color(0xFFFFECEC),
                    ikon: Icons.pause_circle_outline),
              ],
            ),
            const SizedBox(height: 12),
            Center(
                child: _kotak(
                    'Perbaiki penyebab → sinkronkan dengan kode yang sama → periksa riwayat → hubungi admin bila tetap gagal',
                    const Color(0xFFF2F0FF),
                    ikon: Icons.support_agent_outlined)),
          ]),
        ),
      );
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
