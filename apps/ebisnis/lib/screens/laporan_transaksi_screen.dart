import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';
import 'struk_screen.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggalServer = DateFormat('yyyy-MM-dd');

String _formatWaktu(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

/// Layar Laporan Transaksi (padanan laporan-transaksi.html/-renderer.js
/// Electron) -- dasbor KPI (`transaksi_statistik`) di atas, lalu 3 sub-tab
/// server-side paginated: Report Order (`laporan_order_list`), Report Sesi
/// (`laporan_sesi_list`), Report Payment (`laporan_payment_list`). Ketiganya
/// TIDAK dicache offline (laporan historis, selalu online) -- beda dari
/// Produk/Anggota/Pesanan yang punya cache lokal.
class LaporanTransaksiScreen extends StatefulWidget {
  const LaporanTransaksiScreen({super.key});

  @override
  State<LaporanTransaksiScreen> createState() => _LaporanTransaksiScreenState();
}

class _LaporanTransaksiScreenState extends State<LaporanTransaksiScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, dynamic>? _statistik;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _muatStatistik();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _muatStatistik() async {
    try {
      final hasil = await ApiClient.instance.aksi('transaksi_statistik');
      if (mounted) setStateIfMounted(() => _statistik = hasil);
    } catch (_) {
      // dasbor KPI gagal muat bukan blocker utk 3 tab laporan di bawahnya.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.laporanTransaksi,
      judul: 'Laporan Transaksi',
      subjudul: 'Analitik order, sesi kas, dan metode pembayaran',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statistik != null)
            _KartuStatistikTransaksi(statistik: _statistik!),
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Report Order'),
              Tab(text: 'Report Sesi'),
              Tab(text: 'Report Payment'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              _TabOrder(),
              _TabSesi(),
              _TabPayment(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _KartuStatistikTransaksi extends StatelessWidget {
  final Map<String, dynamic> statistik;
  const _KartuStatistikTransaksi({required this.statistik});

  @override
  Widget build(BuildContext context) {
    final kartu = <(String, String, Color)>[
      (
        'Transaksi Hari Ini',
        '${statistik['trxHariIni'] ?? 0}',
        const Color(0xFF1E3A5F)
      ),
      (
        'Omzet Hari Ini',
        _formatRupiah.format(statistik['omzetHariIni'] ?? 0),
        const Color(0xFF2E7D32)
      ),
      (
        'Transaksi 30 Hari',
        '${statistik['trx30Hari'] ?? 0}',
        const Color(0xFF0284C7)
      ),
      (
        'Omzet 30 Hari',
        _formatRupiah.format(statistik['omzet30Hari'] ?? 0),
        const Color(0xFFC0563D)
      ),
    ];
    final byKasir =
        ((statistik['byKasir'] as List?) ?? []).cast<Map<String, dynamic>>();
    final byMesin =
        ((statistik['byMesin'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kartu.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (label, nilai, warna) = kartu[i];
                return Container(
                  width: 150,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: warna.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(nilai,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: warna)),
                      Text(
                        label,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (byKasir.isNotEmpty || byMesin.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (byKasir.isNotEmpty)
                    Expanded(
                        child: _panelPeringkat(
                            context, 'Omzet per Kasir (30 hari)', byKasir)),
                  if (byKasir.isNotEmpty && byMesin.isNotEmpty)
                    const SizedBox(width: 8),
                  if (byMesin.isNotEmpty)
                    Expanded(
                        child: _panelPeringkat(
                            context, 'Omzet per Mesin (30 hari)', byMesin)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelPeringkat(
      BuildContext context, String judul, List<Map<String, dynamic>> data) {
    final maksNilai = data
        .map((e) => (e['nilai'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(judul,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            ...data.take(5).map((e) {
              final nilai = (e['nilai'] as num).toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e['label']}', style: const TextStyle(fontSize: 11)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maksNilai > 0 ? nilai / maksNilai : 0,
                        minHeight: 6,
                        backgroundColor: AppColors.borderOf(context),
                        color: const Color(0xFF1E3A5F),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Bar filter tanggal (+opsional kata kunci pembeli) dipakai oleh ke-3 tab.
class _FilterTanggal extends StatelessWidget {
  final DateTime? mulai;
  final DateTime? sampai;
  final bool pakaiCariPembeli;
  final ValueChanged<DateTime?> onMulaiBerubah;
  final ValueChanged<DateTime?> onSampaiBerubah;
  final ValueChanged<String>? onCariPembeli;
  final VoidCallback onTerapkan;

  const _FilterTanggal({
    required this.mulai,
    required this.sampai,
    required this.onMulaiBerubah,
    required this.onSampaiBerubah,
    required this.onTerapkan,
    this.pakaiCariPembeli = false,
    this.onCariPembeli,
  });

  Future<void> _pilihTanggal(BuildContext context, DateTime? awal,
      ValueChanged<DateTime?> onBerubah) async {
    final d = await showDatePicker(
      context: context,
      initialDate: awal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) onBerubah(d);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _pilihTanggal(context, mulai, onMulaiBerubah),
                  child: Text(mulai == null
                      ? 'Dari Tanggal'
                      : _formatTanggalServer.format(mulai!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _pilihTanggal(context, sampai, onSampaiBerubah),
                  child: Text(sampai == null
                      ? 'Sampai Tanggal'
                      : _formatTanggalServer.format(sampai!)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: onTerapkan, child: const Text('Terapkan')),
            ],
          ),
          if (pakaiCariPembeli)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppSearchField(
                hintText: 'Cari nama pembeli...',
                debounce: const Duration(milliseconds: 450),
                onChanged: onCariPembeli ?? (_) {},
              ),
            ),
        ],
      ),
    );
  }
}

Widget _kartuStatusMuat(
    {required bool memuat, String? error, required VoidCallback onCoba}) {
  if (memuat) {
    return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()));
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 8),
          Text(error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ],
      ),
    ),
  );
}

class _TabOrder extends StatefulWidget {
  const _TabOrder();
  @override
  State<_TabOrder> createState() => _TabOrderState();
}

class _TabOrderState extends State<_TabOrder> {
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
        'includePembayaran': true,
        'includeSplitPembayaran': true,
        'sertakanPembayaran': true,
        'withPayments': true,
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muat();
  }

  Future<void> _terapkan() async {
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

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
                    _chipRingkasan(
                        'Metode',
                        StrukScreen.labelPembayaran(hasil, row),
                        AppColors.primary),
                    _chipRingkasan('Diskon', _formatRupiah.format(diskonHeader),
                        Colors.orange),
                    _chipRingkasan('Pajak', _formatRupiah.format(pajakHeader),
                        Colors.blueGrey),
                    _chipRingkasan(
                        'Bayar',
                        _formatRupiah.format(hasil['totalBiaya'] ?? 0),
                        const Color(0xFF2E7D32)),
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
                            'Harga ${_formatRupiah.format(i['harga'])} - Diskon ${_formatRupiah.format(i['diskon'] ?? 0)} - Pajak ${_formatRupiah.format(pajakBaris)} - Subtotal ${_formatRupiah.format(subtotal)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(context),
                            ),
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
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'))
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

  Widget _chipRingkasan(String label, String nilai, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $nilai',
          style: TextStyle(
              color: warna, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _tabelOrder() {
    return AppDataTable(
      minWidth: 980,
      emptyText: 'Belum ada order pada rentang ini.',
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
            AppTableCell.text(
              '${row['nomorNota'] ?? '-'}',
              flex: 4,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
            AppTableCell.text('${row['pembeli'] ?? 'Umum'}', flex: 2),
            AppTableCell.text(kasirMesin, flex: 2),
            AppTableCell(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: StrukScreen.labelPembayaran(row),
                  warna: AppColors.primary,
                ),
              ),
            ),
            AppTableCell.text(
              _formatRupiah.format(row['totalBiaya'] ?? 0),
              flex: 2,
              align: TextAlign.right,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            AppTableCell(
              width: 74,
              align: TextAlign.center,
              child: Tooltip(
                message: 'Detail transaksi',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
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
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            pakaiCariPembeli: true,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d),
            onCariPembeli: (v) {
              _cariPembeli = v;
              _terapkan();
            },
            onTerapkan: _terapkan,
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _tabelOrder(),
            ),
        ],
      ),
    );
  }
}

class _TabSesi extends StatefulWidget {
  const _TabSesi();
  @override
  State<_TabSesi> createState() => _TabSesiState();
}

class _TabSesiState extends State<_TabSesi> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  DateTime? _mulai;
  DateTime? _sampai;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_sesi_list', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muat();
  }

  Future<void> _terapkan() async {
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _tabelSesi() {
    return AppDataTable(
      minWidth: 920,
      emptyText: 'Belum ada sesi pada rentang ini.',
      columns: const [
        AppTableColumn('Kode Sesi', flex: 3),
        AppTableColumn('Kasir', flex: 2),
        AppTableColumn('Waktu Buka', flex: 2),
        AppTableColumn('Waktu Tutup', flex: 2),
        AppTableColumn('Status', flex: 2),
        AppTableColumn('Saldo Akhir', flex: 2, align: TextAlign.right),
      ],
      rows: _data.map((row) {
        final tutup = row['status']?.toString().toUpperCase() == 'TUTUP';
        final proyeksi = row['saldoAkhirDikonfirmasi'] != true;
        final labelStatus = proyeksi ? 'Proyeksi' : (tutup ? 'Tutup' : 'Buka');
        final warnaStatus = tutup
            ? AppColors.textSecondaryOf(context)
            : const Color(0xFF2E7D32);
        return AppTableRowData(
          cells: [
            AppTableCell.text(
              '${row['sesiKode'] ?? '-'}',
              flex: 3,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            AppTableCell.text('${row['kasir'] ?? '-'}', flex: 2),
            AppTableCell.text(_formatWaktu(row['waktuBuka']), flex: 2),
            AppTableCell.text(_formatWaktu(row['waktuTutup']), flex: 2),
            AppTableCell(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(label: labelStatus, warna: warnaStatus),
              ),
            ),
            AppTableCell.text(
              _formatRupiah.format(row['saldoAkhir'] ?? 0),
              flex: 2,
              align: TextAlign.right,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ],
        );
      }).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'sesi',
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d),
            onTerapkan: _terapkan,
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _tabelSesi(),
            ),
        ],
      ),
    );
  }
}

class _TabPayment extends StatefulWidget {
  const _TabPayment();
  @override
  State<_TabPayment> createState() => _TabPaymentState();
}

class _TabPaymentState extends State<_TabPayment> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  DateTime? _mulai;
  DateTime? _sampai;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_payment_list', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muat();
  }

  Future<void> _terapkan() async {
    setStateIfMounted(() => _halaman = 1);
    await _muat();
  }

  int get _totalHalaman =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _tabelPayment() {
    return AppDataTable(
      minWidth: 860,
      emptyText: 'Belum ada pembayaran pada rentang ini.',
      columns: const [
        AppTableColumn('Order', flex: 3),
        AppTableColumn('Waktu', flex: 2),
        AppTableColumn('Sesi', flex: 2),
        AppTableColumn('Metode', flex: 2),
        AppTableColumn('Jumlah', flex: 2, align: TextAlign.right),
      ],
      rows: _data.map((row) {
        return AppTableRowData(
          cells: [
            AppTableCell.text(
              '${row['orderKode'] ?? '-'}',
              flex: 3,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
            AppTableCell.text('${row['sesiKode'] ?? '-'}', flex: 2),
            AppTableCell(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: StrukScreen.labelPembayaran(row),
                  warna: AppColors.primary,
                ),
              ),
            ),
            AppTableCell.text(
              _formatRupiah.format(row['jumlah'] ?? 0),
              flex: 2,
              align: TextAlign.right,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ],
        );
      }).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'pembayaran',
              onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
              onBerikutnya:
                  _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _FilterTanggal(
            mulai: _mulai,
            sampai: _sampai,
            onMulaiBerubah: (d) => setStateIfMounted(() => _mulai = d),
            onSampaiBerubah: (d) => setStateIfMounted(() => _sampai = d),
            onTerapkan: _terapkan,
          ),
          if (_memuat || _error != null)
            _kartuStatusMuat(memuat: _memuat, error: _error, onCoba: _muat)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _tabelPayment(),
            ),
        ],
      ),
    );
  }
}
