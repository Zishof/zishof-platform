import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import 'cetak_util.dart';
import '../../widgets/jejak_galat.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Master & Analisis Harga -- layar legacy 11-13 & 17-19.</h3>
///
/// Tab 1 Analisis Harga (`si_price_analysis`): beli vs jual vs margin per produk
/// + harga efektif terkini dari master berversi; filter stok ada/nol/margin
/// negatif (harga beli hanya utk peran berwenang -- server yang menegakkan).
/// Tab 2 Harga Beli Supplier (`si_supplier_price_*`, pola masterbl.DBF):
/// versi effective-dated per supplier-produk; overlap ditolak; versi tersimpan
/// terkunci (perubahan = versi baru); "hapus versi" = nonaktif.
/// Tab 3 Harga Jual Customer (`si_customer_price_*`): sama, per customer-produk;
/// baris tanpa customer = daftar harga UMUM (dasar layar 13).
class HargaScreen extends StatefulWidget {
  const HargaScreen({super.key});

  @override
  State<HargaScreen> createState() => _HargaScreenState();
}

class _HargaScreenState extends State<HargaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.harga,
      judul: 'Master & Analisis Harga',
      subjudul:
          'Harga beli supplier, harga jual customer/umum berversi, dan margin (layar legacy 11-13, 17-19)',
      scrollable: false,
      body: Column(children: [
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            tabs: const [
              Tab(text: 'Analisis Harga'),
              Tab(text: 'Harga Beli Supplier'),
              Tab(text: 'Harga Jual Customer'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tab, children: const [
            _TabAnalisisHarga(),
            _TabHargaVersi(jenis: 'beli'),
            _TabHargaVersi(jenis: 'jual'),
          ]),
        ),
      ]),
    );
  }
}

class _TabAnalisisHarga extends StatefulWidget {
  const _TabAnalisisHarga();

  @override
  State<_TabAnalisisHarga> createState() => _TabAnalisisHargaState();
}

class _TabAnalisisHargaState extends State<_TabAnalisisHarga> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  String _filter = '';

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
      final hasil = await ApiClient.instance.aksi('si_price_analysis', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        if (_filter.isNotEmpty) 'filter': _filter,
        'page': _halaman,
        'page_size': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  /// Ambil seluruh baris sesuai filter (maks 1000, tanpa silent truncation).
  Future<(List<Map<String, dynamic>>, bool)> _ambilSemua() async {
    final semua = <Map<String, dynamic>>[];
    bool terpotong = false;
    for (var p = 1; p <= 10; p++) {
      final hasil = await ApiClient.instance.aksi('si_price_analysis', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        if (_filter.isNotEmpty) 'filter': _filter,
        'page': p,
        'page_size': 100,
      });
      final baris =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      semua.addAll(baris);
      final total = (hasil['total'] as num?)?.toInt() ?? 0;
      if (semua.length >= total || baris.isEmpty) break;
      if (p == 10 && semua.length < total) terpotong = true;
    }
    return (semua, terpotong);
  }

  /// SCR-12/13/14: pilih jenis cetak (Harga Jual umum / + Harga Beli berizin),
  /// parameter diteruskan APA ADANYA ke PDF/Excel; menyembunyikan kolom beli
  /// tidak mengubah kolom lain.
  Future<void> _cetakAtauEkspor({required bool pdf}) async {
    final sertakanBeli = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pdf ? 'Cetak Daftar Harga' : 'Ekspor Harga (Excel)'),
        content: const Text(
            'Sertakan kolom Harga Beli? (Harga beli adalah data terbatas -- '
            'hanya untuk peran berwenang; pilih "Jual Saja" untuk daftar harga customer/umum.)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Jual Saja')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sertakan Harga Beli')),
        ],
      ),
    );
    if (sertakanBeli == null) return;
    try {
      final (data, terpotong) = await _ambilSemua();
      final headers = [
        'Kode',
        'Nama Barang',
        'Sat',
        'Stok',
        if (sertakanBeli) 'Hrg Beli',
        'Hrg Jual',
        'Jual Umum Efektif',
        if (sertakanBeli) 'Margin %',
      ];
      final rows = data
          .map((p) => [
                '${p['kode']}',
                '${p['nama']}',
                '${p['satuan'] ?? ''}',
                '${p['stok'] ?? 0}',
                if (sertakanBeli) _fmtRp.format((p['hargaBeli'] as num?) ?? 0),
                _fmtRp.format((p['hargaJual'] as num?) ?? 0),
                p['hargaJualUmumEfektif'] == null
                    ? '-'
                    : _fmtRp.format(p['hargaJualUmumEfektif']),
                if (sertakanBeli)
                  p['marginPersen'] == null
                      ? '-'
                      : (p['marginPersen'] as num).toStringAsFixed(1),
              ])
          .toList();
      final parameter =
          '${_kataKunci.isNotEmpty ? 'cari "$_kataKunci" · ' : ''}filter ${_filter.isEmpty ? 'semua' : _filter}'
          '${terpotong ? ' · TERPOTONG 1000 baris' : ''}';
      if (!mounted) return;
      if (pdf) {
        await CetakUtilIs.cetakPdfTabel(
          judul:
              sertakanBeli ? 'ANALISIS HARGA BELI & JUAL' : 'DAFTAR HARGA JUAL',
          parameter: parameter,
          headers: headers,
          rows: rows,
          namaFile:
              sertakanBeli ? 'analisis-harga.pdf' : 'daftar-harga-jual.pdf',
        );
      } else {
        await CetakUtilIs.eksporExcel(
          context: context,
          namaFile:
              sertakanBeli ? 'analisis-harga.xlsx' : 'daftar-harga-jual.xlsx',
          headers: headers,
          rows: rows,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            AppDetailGalatOpsional(detail: detailUntuk(_error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'Cari kode / nama barang...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true),
                onSubmitted: (v) {
                  _kataKunci = v.trim();
                  _halaman = 1;
                  _muat();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: 'Preview/Cetak PDF (Daftar Harga Jual / Analisis)',
                onPressed: () => _cetakAtauEkspor(pdf: true)),
            IconButton(
                icon: const Icon(Icons.table_view_outlined),
                tooltip: 'Ekspor Excel harga',
                onPressed: () => _cetakAtauEkspor(pdf: false)),
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _filter,
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Filter',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Semua')),
                  DropdownMenuItem(value: 'stok_ada', child: Text('Stok ada')),
                  DropdownMenuItem(value: 'stok_nol', child: Text('Stok nol')),
                  DropdownMenuItem(
                      value: 'margin_negatif', child: Text('Margin negatif')),
                ],
                onChanged: (v) {
                  _filter = v ?? '';
                  _halaman = 1;
                  _muat();
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 980,
            emptyText: 'Tidak ada data.',
            columns: const [
              AppTableColumn('Kode', flex: 1),
              AppTableColumn('Nama Barang', flex: 3),
              AppTableColumn('Sat', flex: 1),
              AppTableColumn('Stok', flex: 1, align: TextAlign.right),
              AppTableColumn('Hrg Beli', flex: 2, align: TextAlign.right),
              AppTableColumn('Hrg Jual', flex: 2, align: TextAlign.right),
              AppTableColumn('Jual Umum Efektif',
                  flex: 2, align: TextAlign.right),
              AppTableColumn('Margin', flex: 1, align: TextAlign.right),
            ],
            rows: _data.map((p) {
              final margin = p['marginPersen'] as num?;
              final negatif = margin != null && margin < 0;
              return AppTableRowData(cells: [
                AppTableCell.text('${p['kode']}',
                    flex: 1,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                AppTableCell.text('${p['nama']}', flex: 3, maxLines: 2),
                AppTableCell.text('${p['satuan'] ?? ''}', flex: 1),
                AppTableCell.text('${p['stok'] ?? 0}',
                    flex: 1, align: TextAlign.right),
                AppTableCell.text(_fmtRp.format((p['hargaBeli'] as num?) ?? 0),
                    flex: 2, align: TextAlign.right),
                AppTableCell.text(_fmtRp.format((p['hargaJual'] as num?) ?? 0),
                    flex: 2, align: TextAlign.right),
                AppTableCell.text(
                    p['hargaJualUmumEfektif'] == null
                        ? '-'
                        : _fmtRp.format(p['hargaJualUmumEfektif']),
                    flex: 2,
                    align: TextAlign.right),
                AppTableCell(
                  flex: 1,
                  align: TextAlign.right,
                  child: Text(
                    margin == null ? '-' : '${margin.toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: negatif ? AppColors.danger : AppColors.success),
                  ),
                ),
              ]);
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'produk',
              onSebelumnya: _halaman > 1
                  ? () {
                      _halaman--;
                      _muat();
                    }
                  : null,
              onBerikutnya: _halaman < _totalHalaman
                  ? () {
                      _halaman++;
                      _muat();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab master harga berversi -- dipakai DUA arah ([jenis]='beli' supplier /
/// 'jual' customer+umum) karena strukturnya kembar (Matriks layar 18 vs 19).
class _TabHargaVersi extends StatefulWidget {
  final String jenis;
  const _TabHargaVersi({required this.jenis});

  @override
  State<_TabHargaVersi> createState() => _TabHargaVersiState();
}

class _TabHargaVersiState extends State<_TabHargaVersi> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  bool _hanyaUmum = false;
  // Diff emisi lokal-dulu: menggerakkan kilau baris + banner perubahan server.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  bool get _beli => widget.jenis == 'beli';

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
      // Baca LOKAL DULU (lihat MasterOffline.daftarCacheDulu): snapshot cache
      // tampil seketika, hasil server menyusul + diff utk kilau baris.
      await MasterOffline.daftarCacheDulu(
          _beli ? 'si_supplier_price_list' : 'si_customer_price_list',
          {
            if (!_beli && _hanyaUmum) 'hanya_umum': true,
            'page': _halaman,
            'page_size': _pageSize,
          },
          'master:si_harga_versi:${widget.jenis}'
              '${!_beli && _hanyaUmum ? ':umum' : ''}', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil);
          _total = _diff.total ?? _data.length;
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Future<void> _nonaktifkan(Map<String, dynamic> v,
      {required bool aktifkan}) async {
    try {
      await ApiClient.instance.aksi(
          _beli ? 'si_supplier_price_save' : 'si_customer_price_save',
          {'id': v['id'], 'aktif': aktifkan});
      if (mounted) await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  Future<void> _tambahVersi() async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormVersiHarga(beli: _beli),
    );
    if (tersimpan == true) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final bolehKelola = Sesi.instance.bolehAksiIs('harga', 'create') ||
        Sesi.instance.bolehAksiIs('harga', 'update');
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: bolehKelola
          ? FloatingActionButton.extended(
              onPressed: _tambahVersi,
              icon: const Icon(Icons.add),
              label: Text(_beli ? 'Versi Harga Beli' : 'Versi Harga Jual'))
          : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  _beli
                      ? 'Versi harga beli per supplier-produk (pola masterbl.DBF). Versi tersimpan terkunci -- perubahan harga = versi baru.'
                      : 'Versi harga jual per customer-produk; baris "(Umum)" = daftar harga jual umum (dasar cetak Daftar Harga Jual).',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
              ),
              if (!_beli)
                FilterChip(
                  label: const Text('Hanya umum'),
                  selected: _hanyaUmum,
                  onSelected: (v) {
                    _hanyaUmum = v;
                    _halaman = 1;
                    _muat();
                  },
                ),
            ]),
            const SizedBox(height: 12),
            BannerPerubahanServer(
              key: ValueKey('perubahan:${_diff.versi}'),
              baru: _diff.idBaru.length,
              berubah: _diff.idBerubah.length,
              dihapus: _diff.jumlahHapus,
            ),
            AppDataTable(
              minWidth: 960,
              emptyText: 'Belum ada versi harga.',
              columns: [
                AppTableColumn(_beli ? 'Supplier' : 'Customer', flex: 2),
                const AppTableColumn('Produk', flex: 3),
                const AppTableColumn('Harga', flex: 2, align: TextAlign.right),
                const AppTableColumn('Tgl Efektif', flex: 2),
                const AppTableColumn('Status',
                    flex: 1, align: TextAlign.center),
                const AppTableColumn('', flex: 1, align: TextAlign.center),
              ],
              rows: _data.map((v) {
                final aktif = v['aktif'] == true;
                return AppTableRowData(cells: [
                  AppTableCell(
                    flex: 2,
                    child: KilauBaris(
                      kunci: '${v['id'] ?? v['_kunci'] ?? ''}',
                      idBaru: _diff.idBaru,
                      idBerubah: _diff.idBerubah,
                      child: Text(
                          _beli
                              ? '${v['supplierKode']} ${v['supplierNama']}'
                              : '${v['customerKode']} ${v['customerNama']}'
                                  .trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  AppTableCell.text('${v['produkKode']} — ${v['produkNama']}',
                      flex: 3, maxLines: 2),
                  AppTableCell.text(_fmtRp.format((v['harga'] as num?) ?? 0),
                      flex: 2,
                      align: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5)),
                  AppTableCell.text('${v['tanggalEfektif']}', flex: 2),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: StatusPill(
                        label: aktif ? 'Aktif' : 'Nonaktif',
                        warna: aktif ? AppColors.success : AppColors.danger),
                  ),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: bolehKelola
                        ? IconButton(
                            icon: Icon(
                                aktif
                                    ? Icons.block
                                    : Icons.check_circle_outline,
                                size: 18,
                                color: aktif ? Colors.red : AppColors.success),
                            tooltip: aktif
                                ? 'Nonaktifkan versi (padanan aman Hapus Versi)'
                                : 'Aktifkan versi',
                            onPressed: () => _nonaktifkan(v, aktifkan: !aktif),
                          )
                        : const SizedBox.shrink(),
                  ),
                ]);
              }).toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _total,
                labelData: 'versi harga',
                onSebelumnya: _halaman > 1
                    ? () {
                        _halaman--;
                        _muat();
                      }
                    : null,
                onBerikutnya: _halaman < _totalHalaman
                    ? () {
                        _halaman++;
                        _muat();
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormVersiHarga extends StatefulWidget {
  final bool beli;
  const _FormVersiHarga({required this.beli});

  @override
  State<_FormVersiHarga> createState() => _FormVersiHargaState();
}

class _FormVersiHargaState extends State<_FormVersiHarga> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  final _harga = TextEditingController();
  final _keterangan = TextEditingController();
  DateTime _tanggal = DateTime.now();
  Map<String, dynamic>? _pihak; // supplier (beli) / customer (jual, null=umum)
  Map<String, dynamic>? _produk;
  bool _menyimpan = false;
  String? _error;

  @override
  void dispose() {
    _harga.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _pilihPihak() async {
    final hasil = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetCari(
          judul: widget.beli ? 'Pilih Supplier' : 'Pilih Customer',
          aksi: widget.beli ? 'si_supplier_list' : 'si_customer_list',
          labelBaris: (r) => widget.beli
              ? '${r['kode']} — ${r['nama']}'
              : '${r['kode']} — ${r['nama']}'),
    );
    if (hasil != null) setStateIfMounted(() => _pihak = hasil);
  }

  Future<void> _pilihProduk() async {
    final hasil = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetCari(
          judul: 'Pilih Produk',
          aksi: 'si_price_analysis',
          labelBaris: (r) => '${r['kode']} — ${r['nama']}'),
    );
    if (hasil != null) setStateIfMounted(() => _produk = hasil);
  }

  Future<void> _simpan() async {
    if (_produk == null) {
      setStateIfMounted(() => _error = 'Pilih produk terlebih dahulu.');
      return;
    }
    if (widget.beli && _pihak == null) {
      setStateIfMounted(() => _error = 'Pilih supplier terlebih dahulu.');
      return;
    }
    final harga = double.tryParse(_harga.text.replaceAll(',', '.'));
    if (harga == null || harga <= 0) {
      setStateIfMounted(() => _error = 'Harga wajib diisi > 0.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      await ApiClient.instance.aksi(
          widget.beli ? 'si_supplier_price_save' : 'si_customer_price_save', {
        if (widget.beli) 'supplier_id': _pihak!['id'],
        if (!widget.beli && _pihak != null) 'anggota_id': _pihak!['anggotaId'],
        'produk_id': _produk!['produkId'] ?? _produk!['id'],
        'harga': harga,
        'tanggal_efektif': _fmtTgl.format(_tanggal),
        'keterangan': _keterangan.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        expand: false,
        builder: (context, sc) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: sc,
            title: widget.beli
                ? 'Versi Harga Beli Supplier'
                : 'Versi Harga Jual Customer/Umum',
            subtitle:
                'Overlap tanggal efektif yang sama ditolak; histori tidak pernah ditimpa.',
            icon: Icons.price_change_outlined,
            errorText: _error,
            errorDetail: detailUntuk(_error),
            children: [
              AppFormSection(judul: 'Versi Harga', children: [
                OutlinedButton.icon(
                  onPressed: _pilihPihak,
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_pihak == null
                      ? (widget.beli
                          ? 'Pilih Supplier *'
                          : 'Pilih Customer (kosong = harga UMUM)')
                      : '${_pihak!['kode']} — ${_pihak!['nama']}'),
                ),
                if (!widget.beli && _pihak != null)
                  TextButton(
                      onPressed: () => setStateIfMounted(() => _pihak = null),
                      child: const Text('Jadikan harga umum (lepas customer)')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pilihProduk,
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(_produk == null
                      ? 'Pilih Produk *'
                      : '${_produk!['kode']} — ${_produk!['nama']}'),
                ),
                const SizedBox(height: 12),
                AppFormTextField(
                    label: 'Harga *',
                    controller: _harga,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true)),
                OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showDatePicker(
                        context: context,
                        initialDate: _tanggal,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (t != null) setStateIfMounted(() => _tanggal = t);
                  },
                  icon: const Icon(Icons.event, size: 16),
                  label: Text('Tgl Efektif: ${_fmtTgl.format(_tanggal)}'),
                ),
                const SizedBox(height: 12),
                AppFormTextField(
                    label: 'Keterangan / alasan perubahan',
                    controller: _keterangan,
                    maxLines: 2),
              ]),
            ],
            actions: [
              OutlinedButton.icon(
                onPressed:
                    _menyimpan ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan Versi'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet pencarian generik server-side (reuse aksi list existing) -- pop
/// dengan Map baris terpilih.
class _SheetCari extends StatefulWidget {
  final String judul;
  final String aksi;
  final String Function(Map<String, dynamic>) labelBaris;
  const _SheetCari(
      {required this.judul, required this.aksi, required this.labelBaris});

  @override
  State<_SheetCari> createState() => _SheetCariState();
}

class _SheetCariState extends State<_SheetCari> {
  List<Map<String, dynamic>> _hasil = [];
  bool _memuat = false;

  Future<void> _cari(String v) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance
          .aksi(widget.aksi, {'keyword': v.trim(), 'page_size': 30});
      setStateIfMounted(() => _hasil =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // Gagal cari -- biarkan hasil lama.
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, sc) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(widget.judul,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Ketik untuk mencari...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: _cari,
          ),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: _hasil.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                title: Text(widget.labelBaris(_hasil[i])),
                onTap: () => Navigator.pop(context, _hasil[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
