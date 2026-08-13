import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'laporan_detail_screen.dart';
import '../widgets/safe_state.dart';

/// Katalog ~150 laporan (32 kategori) -- padanan `laporan.html`/`laporan-renderer.js`
/// Electron & `laporan_laporan.jsp`. Metadata katalog (`laporan_katalog`) SEPENUHNYA
/// data-driven (id/judul/ket/produk?/pelanggan?/perToko?/url?), jadi layar ini
/// generik utk semua laporan -- TIDAK ada kode khusus per-laporan (lihat JavaDoc
/// LaporanKatalogData di server). ~13 item punya `url` (laporan akuntansi resmi
/// ZK/JRXML) -- ini dibuka EKSTERNAL via browser, bukan lewat alur jalankan/PDF
/// generik, karena bukan bagian dari kontrak kolom/baris yang sama.
class LaporanScreen extends StatefulWidget {
  /// Aksi server sumber katalog: `laporan_katalog` (semua) atau
  /// `laporan_keuangan_katalog` (subset keuangan). Membuat layar ini bisa dipakai
  /// ulang untuk menu "Laporan Keuangan" tanpa menduplikasi logika render/run.
  final String aksiKatalog;
  final MenuEBisnis menuAktif;
  final String judul;
  final String subjudul;
  const LaporanScreen({
    super.key,
    this.aksiKatalog = 'laporan_katalog',
    this.menuAktif = MenuEBisnis.laporanLaporan,
    this.judul = 'Laporan-Laporan',
    this.subjudul = 'Katalog laporan siap pakai',
  });

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _kategori = [];
  final _controllerCari = TextEditingController();
  String _kategoriDipilih = '';
  int _halaman = 1;
  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _controllerCari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(widget.aksiKatalog);
      final arr = (hasil['kategori'] as List?) ?? [];
      setStateIfMounted(() {
        _kategori =
            arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (_kategoriDipilih.isNotEmpty &&
            !_kategori
                .any((e) => (e['kat'] as String? ?? '') == _kategoriDipilih)) {
          _kategoriDipilih = '';
        }
        _halaman = 1;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaItem(Map<String, dynamic> item) async {
    final url = item['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final origin = Uri.parse(ApiClient.baseUrl).origin;
      final uri = Uri.parse('$origin$url');
      final berhasil =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!berhasil && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Tidak bisa membuka $uri')));
      }
      return;
    }
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LaporanDetailScreen(item: item)));
  }

  List<_LaporanKatalogBaris> get _terfilter {
    final kw = _controllerCari.text.trim().toLowerCase();
    final hasil = <_LaporanKatalogBaris>[];
    for (final k in _kategori) {
      final kat = k['kat'] as String? ?? '';
      final items = ((k['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (_kategoriDipilih.isNotEmpty && kat != _kategoriDipilih) {
        continue;
      }
      final cocokKategori = kat.toLowerCase().contains(kw);
      for (final item in items) {
        final judul = (item['judul'] as String? ?? '').toLowerCase();
        final ket = (item['ket'] as String? ?? '').toLowerCase();
        if (kw.isEmpty ||
            cocokKategori ||
            judul.contains(kw) ||
            ket.contains(kw)) {
          hasil.add(_LaporanKatalogBaris(kategori: kat, item: item));
        }
      }
    }
    return hasil;
  }

  int _totalHalaman(int total) {
    if (total <= 0) return 1;
    return ((total - 1) ~/ _pageSize) + 1;
  }

  List<_LaporanKatalogBaris> _halamanData(List<_LaporanKatalogBaris> data) {
    final totalHalaman = _totalHalaman(data.length);
    if (_halaman > totalHalaman) _halaman = totalHalaman;
    final mulai = (_halaman - 1) * _pageSize;
    final sampai = (mulai + _pageSize).clamp(0, data.length) as int;
    if (mulai >= data.length) return const [];
    return data.sublist(mulai, sampai);
  }

  Color _warnaBiruGelap(BuildContext context) => AppColors.gelap(context)
      ? AppColors.darkTextPrimary
      : AppColors.sidebarBg;

  List<String> get _opsiKategori {
    final kategori = _kategori
        .map((e) => e['kat'] as String? ?? '')
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return kategori;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: widget.menuAktif,
      judul: widget.judul,
      subjudul: widget.subjudul,
      aksiHeader: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _muat,
          tooltip: 'Muat ulang'),
      actionsAppBar: [
        IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _muat,
            tooltip: 'Muat ulang')
      ],
      scrollable: true,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(child: Text('Gagal memuat: $_pesanError'))
              : Builder(
                  builder: (context) {
                    final data = _terfilter;
                    final totalHalaman = _totalHalaman(data.length);
                    final halamanData = _halamanData(data);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final sempit = constraints.maxWidth < 720;
                              final kategoriDropdown =
                                  DropdownButtonFormField<String>(
                                value: _kategoriDipilih,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Kategori',
                                  prefixIcon: Icon(Icons.category_outlined),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Semua kategori'),
                                  ),
                                  ..._opsiKategori.map(
                                    (kategori) => DropdownMenuItem(
                                      value: kategori,
                                      child: Text(
                                        kategori,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) => setStateIfMounted(() {
                                  _kategoriDipilih = value ?? '';
                                  _halaman = 1;
                                }),
                              );
                              final pencarian = TextField(
                                controller: _controllerCari,
                                decoration: const InputDecoration(
                                    hintText: 'Cari laporan...',
                                    prefixIcon: Icon(Icons.search),
                                    border: OutlineInputBorder(),
                                    isDense: true),
                                onChanged: (_) =>
                                    setStateIfMounted(() => _halaman = 1),
                              );
                              if (sempit) {
                                return Column(
                                  children: [
                                    kategoriDropdown,
                                    const SizedBox(height: 8),
                                    pencarian,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  SizedBox(width: 320, child: kategoriDropdown),
                                  const SizedBox(width: 10),
                                  Expanded(child: pencarian),
                                ],
                              );
                            },
                          ),
                        ),
                        AppDataTable(
                          minWidth: 920,
                          emptyText: 'Tidak ada laporan yang cocok.',
                          columns: const [
                            AppTableColumn('Kategori', flex: 2),
                            AppTableColumn('Laporan', flex: 3),
                            AppTableColumn('Keterangan', flex: 4),
                            AppTableColumn('Format',
                                width: 96, align: TextAlign.center),
                            AppTableColumn('Aksi',
                                width: 82, align: TextAlign.center),
                          ],
                          rows: halamanData.map((baris) {
                            final item = baris.item;
                            final adaUrl =
                                (item['url'] as String? ?? '').isNotEmpty;
                            return AppTableRowData(
                              onTap: () => _bukaItem(item),
                              cells: [
                                AppTableCell.text(
                                  baris.kategori,
                                  flex: 2,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                AppTableCell.text(
                                  item['judul'] as String? ?? '-',
                                  flex: 3,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _warnaBiruGelap(context),
                                  ),
                                ),
                                AppTableCell.text(
                                  item['ket'] as String? ?? '-',
                                  flex: 4,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                                AppTableCell(
                                  width: 96,
                                  align: TextAlign.center,
                                  child: StatusPill(
                                    label: adaUrl ? 'Link' : 'Data',
                                    warna: adaUrl
                                        ? AppColors.info
                                        : AppColors.primary,
                                  ),
                                ),
                                AppTableCell(
                                  width: 82,
                                  align: TextAlign.center,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: adaUrl
                                        ? 'Buka laporan'
                                        : 'Jalankan laporan',
                                    icon: Icon(
                                      adaUrl
                                          ? Icons.open_in_new
                                          : Icons.chevron_right,
                                      size: 20,
                                      color: _warnaBiruGelap(context),
                                    ),
                                    onPressed: () => _bukaItem(item),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                          pagination: AppTablePagination(
                            halaman: _halaman,
                            totalHalaman: totalHalaman,
                            totalData: data.length,
                            labelData: 'laporan',
                            onSebelumnya: _halaman > 1
                                ? () => setStateIfMounted(() => _halaman--)
                                : null,
                            onBerikutnya: _halaman < totalHalaman
                                ? () => setStateIfMounted(() => _halaman++)
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _LaporanKatalogBaris {
  final String kategori;
  final Map<String, dynamic> item;

  const _LaporanKatalogBaris({
    required this.kategori,
    required this.item,
  });
}
