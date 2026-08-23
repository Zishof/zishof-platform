import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/safe_state.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/aksi_baris_menu.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Hutang Supplier (AP) -- layar legacy 20-29 (Pembelian/Hutang Dagang).</h3>
///
/// Register event: faktur kulakan ber-jenis DP/CREDIT menambah hutang; pembayaran
/// teralokasi (+dibayar awal) mengurangi. Outstanding SELALU dihitung server.
/// 5 tab: Hutang (SCR-21..23), Pembayaran+voucher (SCR-24..26), Aging (SCR-27),
/// Faktur (SCR-20 termin/jenis/DP + SCR-28 cetak faktur), Laporan (SCR-29).
class HutangSupplierScreen extends StatefulWidget {
  const HutangSupplierScreen({super.key});

  @override
  State<HutangSupplierScreen> createState() => _HutangSupplierScreenState();
}

class _HutangSupplierScreenState extends State<HutangSupplierScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.hutangSupplier,
      judul: 'Hutang Supplier (AP)',
      subjudul:
          'Register hutang, pembayaran teralokasi, aging, termin faktur, laporan pembelian (layar legacy 20-29)',
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
              Tab(text: 'Hutang'),
              Tab(text: 'Pembayaran'),
              Tab(text: 'Aging'),
              Tab(text: 'Faktur (Termin/Cetak)'),
              Tab(text: 'Laporan Pembelian'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tab, children: const [
            _TabHutang(),
            _TabPembayaran(),
            _TabAging(),
            _TabFaktur(),
            _TabLaporanPembelian(),
          ]),
        ),
      ]),
    );
  }
}

// =============================================================================
// TAB 1: HUTANG (register per faktur; tampilkan/sembunyikan lunas)
// =============================================================================

class _TabHutang extends StatefulWidget {
  const _TabHutang();

  @override
  State<_TabHutang> createState() => _TabHutangState();
}

class _TabHutangState extends State<_TabHutang> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  double _totalOutstanding = 0;
  String _kataKunci = '';
  bool _tampilkanLunas = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  final DiffDaftarLokal _diff = DiffDaftarLokal();

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // Baca LOKAL DULU (MasterOffline.daftarCacheDulu) + diff utk kilau.
      // Baris faktur hutang tidak ber-'id' -> identitasnya 'fakturId'.
      await MasterOffline.daftarCacheDulu(
          'si_payable_list',
          {
            if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
            'tampilkan_lunas': _tampilkanLunas,
            'page': _halaman,
            'page_size': _pageSize,
          },
          'master:si_hutang:${_tampilkanLunas ? 'semua' : 'berjalan'}',
          kolomKunci: 'fakturId', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil);
          _total = _diff.total ?? _data.length;
          if (_diff.dariServer) {
            _totalOutstanding =
                (hasil['totalOutstanding'] as num?)?.toDouble() ?? 0;
          }
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

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _PanelError(
          pesan: _error!, detail: detailUntuk(_error), onCoba: _muat);
    }
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(children: [
            Expanded(
              child: AppSearchField(
                hintText: 'Cari supplier / no. faktur...',
                onChanged: (v) {
                  _kataKunci = v.trim();
                  _halaman = 1;
                  _muat();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Tampilkan Lunas'),
              selected: _tampilkanLunas,
              onSelected: (v) {
                // Hanya mengubah FILTER tampilan -- event settled tetap tersimpan
                // (paritas legacy "Lunas Muncul/Lunas Tutup").
                _tampilkanLunas = v;
                _halaman = 1;
                _muat();
              },
            ),
            const SizedBox(width: 8),
            AppDetailChip(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Outstanding: ${_fmtRp.format(_totalOutstanding)}',
                color: AppColors.danger),
          ]),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 1020,
            emptyText: _tampilkanLunas
                ? 'Belum ada faktur ber-hutang.'
                : 'Tidak ada hutang berjalan. (Aktifkan "Tampilkan Lunas" untuk melihat yang selesai.)',
            columns: const [
              AppTableColumn('Supplier', flex: 2),
              AppTableColumn('No. Faktur', flex: 2),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Jatuh Tempo', flex: 2),
              AppTableColumn('Jenis', flex: 1),
              AppTableColumn('Total', flex: 2, align: TextAlign.right),
              AppTableColumn('Dibayar', flex: 2, align: TextAlign.right),
              AppTableColumn('Sisa', flex: 2, align: TextAlign.right),
              AppTableColumn('Status', flex: 1, align: TextAlign.center),
            ],
            rows: _data.map((h) {
              final lunas = h['lunas'] == true;
              final dibayar = ((h['dibayarAwal'] as num?)?.toDouble() ?? 0) +
                  ((h['dibayarAlokasi'] as num?)?.toDouble() ?? 0);
              return AppTableRowData(cells: [
                AppTableCell(
                  flex: 2,
                  child: KilauBaris(
                    kunci: MasterOffline.kunciBaris(h, 'fakturId'),
                    idBaru: _diff.idBaru,
                    idBerubah: _diff.idBerubah,
                    child: Text(
                        '${h['supplierKode']} ${h['supplierNama']}'.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                AppTableCell.text('${h['nomorFaktur']}', flex: 2),
                AppTableCell.text('${h['tanggalFaktur']}'.split(' ').first,
                    flex: 2),
                AppTableCell.text('${h['jatuhTempo']}', flex: 2),
                AppTableCell.text('${h['jenisPembayaran']}', flex: 1),
                AppTableCell.text(
                    _fmtRp.format((h['totalFaktur'] as num?) ?? 0),
                    flex: 2,
                    align: TextAlign.right),
                AppTableCell.text(_fmtRp.format(dibayar),
                    flex: 2, align: TextAlign.right),
                AppTableCell.text(
                    _fmtRp.format((h['outstanding'] as num?) ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: lunas ? AppColors.success : AppColors.danger)),
                AppTableCell(
                  flex: 1,
                  align: TextAlign.center,
                  child: StatusPill(
                      label: lunas ? 'Lunas' : 'Belum',
                      warna: lunas ? AppColors.success : AppColors.warning),
                ),
              ]);
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'faktur',
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

// =============================================================================
// TAB 2: PEMBAYARAN (riwayat + form alokasi multi-faktur + voucher PDF)
// =============================================================================

class _TabPembayaran extends StatefulWidget {
  const _TabPembayaran();

  @override
  State<_TabPembayaran> createState() => _TabPembayaranState();
}

class _TabPembayaranState extends State<_TabPembayaran> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _metode = 'SEMUA';
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();

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
      final hasil =
          await ApiClient.instance.aksi('si_payable_payment_history', {
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
        'metode': _metode,
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

  Future<void> _cetakVoucher(Map<String, dynamic> bayar) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('si_payable_payment_receipt', {'id': bayar['id']});
      final d = (hasil['data'] as Map<String, dynamic>?) ?? {};
      final alokasi =
          ((d['alokasi'] as List?) ?? []).cast<Map<String, dynamic>>();
      final doc = pw.Document();
      doc.addPage(pw.Page(
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('VOUCHER PEMBAYARAN HUTANG SUPPLIER',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('No. Voucher: PHS-${d['id']}  ·  Ref: ${d['kodeUnik']}'),
            pw.Text('Tanggal: ${d['tanggal']}'),
            pw.Text('Supplier: ${d['supplierKode']} — ${d['supplierNama']}'),
            pw.Text('Metode: ${d['metode']}'
                '${'${d['noBg']}'.isNotEmpty ? '  ·  BG: ${d['noBg']} ${d['namaBank']} jt ${d['tanggalBg']}' : ''}'),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['No. Faktur', 'Tgl Faktur', 'Jatuh Tempo', 'Alokasi'],
              data: alokasi
                  .map((a) => [
                        '${a['nomorFaktur']}',
                        '${a['tanggalFaktur']}'.split(' ').first,
                        '${a['jatuhTempo']}',
                        _fmtRp.format((a['nominalAlokasi'] as num?) ?? 0),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
                'TOTAL DIBAYAR: ${_fmtRp.format((d['nominal'] as num?) ?? 0)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if ('${d['keterangan']}'.isNotEmpty)
              pw.Text('Keterangan: ${d['keterangan']}'),
            pw.SizedBox(height: 24),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(children: [
                    pw.Text('Dibuat oleh'),
                    pw.SizedBox(height: 36),
                    pw.Text('( ${d['oleh']} )'),
                  ]),
                  pw.Column(children: [
                    pw.Text('Disetujui'),
                    pw.SizedBox(height: 36),
                    pw.Text('( ................ )'),
                  ]),
                  pw.Column(children: [
                    pw.Text('Penerima (Supplier)'),
                    pw.SizedBox(height: 36),
                    pw.Text('( ................ )'),
                  ]),
                ]),
          ],
        ),
      ));
      await Printing.layoutPdf(
          onLayout: (_) => doc.save(), name: 'voucher-hutang-${d['id']}.pdf');
      ApiClient.instance.aksi('si_print_log_create', {
        'jenis_dokumen': 'voucher_pembayaran_hutang',
        'referensi': 'PHS-${d['id']}',
        'parameter': 'kode_unik=${d['kodeUnik']}',
        'perangkat': 'flutter',
      }).then((_) {}, onError: (_) {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal cetak voucher: $e')));
      }
    }
  }

  /// P10: pembayaran posted tetap disimpan; reversal menerbitkan dokumen
  /// pembalik negatif yang idempoten di server.
  Future<void> _reversal(Map<String, dynamic> pembayaran) async {
    final alasan = TextEditingController();
    final dikonfirmasi = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reversal pembayaran #${pembayaran['id']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Pembayaran tidak dihapus. Sistem menerbitkan dokumen pembalik '
              'dan memulihkan saldo hutang supplier.',
              style: TextStyle(fontSize: 12.5)),
          TextField(
              controller: alasan,
              decoration:
                  const InputDecoration(labelText: 'Alasan reversal (wajib)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              child: const Text('Reversal')),
        ],
      ),
    );
    if (dikonfirmasi != true || alasan.text.trim().isEmpty) return;
    try {
      // ONLINE-ONLY: pembalikan pembayaran = "reversal" pada spec 13.3.
      // Membatalkan uang yang mungkin sudah dipakai alokasi lain tidak boleh
      // ditunda: server harus memutuskan saat itu juga.
      await ApiClient.instance.aksi('si_payable_payment_reverse', {
        'pembayaran_id': pembayaran['id'],
        'alasan': alasan.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reversal pembayaran diterbitkan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  /// P10: BG hanya dapat berpindah dari DITERIMA ke CAIR/TOLAK. Penolakan
  /// menerbitkan reversal pembayaran secara otomatis dan idempoten di server.
  Future<void> _ubahStatusBg(
      Map<String, dynamic> pembayaran, String status) async {
    try {
      await ApiClient.instance.aksi('si_payable_bg_status', {
        'id': pembayaran['id'],
        'status_bg': status,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'CAIR'
                ? 'BG ditandai CAIR.'
                : 'BG ditandai TOLAK — reversal otomatis diterbitkan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  Future<void> _formBayar() async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FormPembayaranHutang(),
    );
    if (tersimpan == true) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final bolehBayar = Sesi.instance.bolehAksiIs('hutang', 'create');
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return _PanelError(
          pesan: _error!, detail: detailUntuk(_error), onCoba: _muat);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: bolehBayar
          ? FloatingActionButton.extended(
              onPressed: _formBayar,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Bayar Hutang'))
          : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final t = await showDatePicker(
                      context: context,
                      initialDate: _dari,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (t != null) {
                    _dari = t;
                    _muat();
                  }
                },
                icon: const Icon(Icons.event, size: 16),
                label: Text('Dari: ${_fmtTgl.format(_dari)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final t = await showDatePicker(
                      context: context,
                      initialDate: _sampai,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (t != null) {
                    _sampai = t;
                    _muat();
                  }
                },
                icon: const Icon(Icons.event, size: 16),
                label: Text('Sampai: ${_fmtTgl.format(_sampai)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  value: _metode,
                  isDense: true,
                  decoration: const InputDecoration(
                      labelText: 'Metode',
                      isDense: true,
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'SEMUA', child: Text('Semua')),
                    DropdownMenuItem(value: 'TUNAI', child: Text('Tunai')),
                    DropdownMenuItem(
                        value: 'TRANSFER', child: Text('Transfer')),
                    DropdownMenuItem(value: 'GIRO', child: Text('Giro/BG')),
                    DropdownMenuItem(
                        value: 'DISCOUNT', child: Text('Discount')),
                    DropdownMenuItem(value: 'RETUR', child: Text('Retur')),
                  ],
                  onChanged: (v) {
                    _metode = v ?? 'SEMUA';
                    _halaman = 1;
                    _muat();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            AppDataTable(
              minWidth: 1000,
              emptyText: 'Belum ada pembayaran pada periode ini.',
              columns: const [
                AppTableColumn('Tanggal', flex: 2),
                AppTableColumn('Supplier', flex: 3),
                AppTableColumn('Metode', flex: 1),
                AppTableColumn('BG/Bank', flex: 2),
                AppTableColumn('Alokasi Faktur', flex: 3),
                AppTableColumn('Nominal', flex: 2, align: TextAlign.right),
                AppTableColumn('', flex: 1, align: TextAlign.center),
              ],
              rows: _data
                  .map((b) => AppTableRowData(cells: [
                        AppTableCell.text('${b['tanggal']}'.split('.').first,
                            flex: 2, style: const TextStyle(fontSize: 11.5)),
                        AppTableCell.text(
                            '${b['supplierKode']} ${b['supplierNama']}'.trim(),
                            flex: 3,
                            maxLines: 2),
                        AppTableCell.text(
                            '${b['metode']}'
                            '${'${b['statusDok']}' == 'DIBATALKAN' ? ' · DIBATALKAN' : ''}'
                            '${'${b['statusDok']}' == 'REVERSAL' ? ' · REVERSAL' : ''}'
                            '${'${b['statusBg']}'.isNotEmpty ? ' · BG ${b['statusBg']}' : ''}',
                            flex: 1,
                            maxLines: 3),
                        AppTableCell.text(
                            '${b['noBg']} ${b['namaBank']}'.trim(),
                            flex: 2),
                        AppTableCell.text('${b['alokasiRingkas']}',
                            flex: 3, maxLines: 2),
                        AppTableCell.text(
                            _fmtRp.format((b['nominal'] as num?) ?? 0),
                            flex: 2,
                            align: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        AppTableCell(
                          flex: 1,
                          align: TextAlign.center,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.receipt_long_outlined,
                                  size: 18),
                              tooltip: 'Cetak Voucher (PDF)',
                              onPressed: () => _cetakVoucher(b),
                            ),
                            if (!Sesi.instance.isSalesKeliling &&
                                '${b['statusDok']}' == 'AKTIF')
                              PopupMenuButton<String>(
                                tooltip: 'Aksi dokumen',
                                onSelected: (aksi) {
                                  if (aksi == 'reversal') _reversal(b);
                                  if (aksi == 'cair') {
                                    _ubahStatusBg(b, 'CAIR');
                                  }
                                  if (aksi == 'tolak') {
                                    _ubahStatusBg(b, 'TOLAK');
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'reversal',
                                      child: Text('Reversal (batalkan)')),
                                  if ('${b['metode']}' == 'GIRO' &&
                                      ('${b['statusBg']}'.isEmpty ||
                                          '${b['statusBg']}' ==
                                              'DITERIMA')) ...[
                                    const PopupMenuItem(
                                        value: 'cair', child: Text('BG Cair')),
                                    const PopupMenuItem(
                                        value: 'tolak',
                                        child:
                                            Text('BG Tolak (auto-reversal)')),
                                  ],
                                ],
                              ),
                          ]),
                        ),
                      ]))
                  .toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _total,
                labelData: 'pembayaran',
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

/// Form pembayaran: pilih supplier -> muat faktur outstanding -> centang faktur
/// + nominal alokasi per faktur -> metode (+BG) -> simpan (idempoten kode_unik).
class _FormPembayaranHutang extends StatefulWidget {
  const _FormPembayaranHutang();

  @override
  State<_FormPembayaranHutang> createState() => _FormPembayaranHutangState();
}

class _FormPembayaranHutangState extends State<_FormPembayaranHutang>
    with JejakGalat {
  Map<String, dynamic>? _supplier;
  List<Map<String, dynamic>> _fakturs = [];
  final Map<int, TextEditingController> _alokasi = {};
  String _metode = 'TUNAI';
  final _noBg = TextEditingController();
  final _namaBank = TextEditingController();
  DateTime? _tanggalBg;
  final _keterangan = TextEditingController();
  bool _menyimpan = false;
  String? _error;

  /// Kunci idempoten DIBUAT SEKALI saat form dibuka -- retry Simpan yang sama
  /// memakai kunci yang sama sehingga server tidak menggandakan pembayaran.
  late final String _kodeUnik =
      'PHS-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void dispose() {
    _noBg.dispose();
    _namaBank.dispose();
    _keterangan.dispose();
    for (final c in _alokasi.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalAlokasi {
    double t = 0;
    for (final c in _alokasi.values) {
      t += double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
    }
    return t;
  }

  Future<void> _pilihSupplier() async {
    final hasil = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetPilihSupplierHutang(),
    );
    if (hasil == null) return;
    setStateIfMounted(() {
      _supplier = hasil;
      _fakturs = [];
      for (final c in _alokasi.values) {
        c.dispose();
      }
      _alokasi.clear();
    });
    try {
      final res = await ApiClient.instance.aksi('si_payable_list', {
        'supplier_id': hasil['id'] ?? hasil['supplierId'],
        'tampilkan_lunas': false,
        'page_size': 100,
      });
      setStateIfMounted(() => _fakturs =
          ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    }
  }

  Future<void> _simpan() async {
    if (_supplier == null) {
      setStateIfMounted(() => _error = 'Pilih supplier dahulu.');
      return;
    }
    final alokasi = <Map<String, dynamic>>[];
    for (final f in _fakturs) {
      final id = (f['fakturId'] as num).toInt();
      final c = _alokasi[id];
      final n =
          c == null ? 0.0 : (double.tryParse(c.text.replaceAll(',', '.')) ?? 0);
      if (n > 0) {
        alokasi.add({'faktur_id': id, 'nominal': n});
      }
    }
    if (alokasi.isEmpty) {
      setStateIfMounted(
          () => _error = 'Isi nominal alokasi minimal pada satu faktur.');
      return;
    }
    if (_metode == 'GIRO' && _noBg.text.trim().isEmpty) {
      setStateIfMounted(() => _error = 'Metode Giro wajib mengisi No. BG.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      // LOKAL DULU. Aman diulang: payload membawa `kode_unik` sehingga kiriman
      // ganda akibat retry tidak menghasilkan pembayaran dobel di server.
      await prosesSimpanMaster(
        context,
        aksi: 'si_payable_payment_create',
        kunci: 'si_payable_payment:$_kodeUnik',
        body: {
        'supplier_id': _supplier!['id'] ?? _supplier!['supplierId'],
        'nominal': _totalAlokasi,
        'metode': _metode,
        'no_bg': _noBg.text.trim(),
        'nama_bank': _namaBank.text.trim(),
        if (_tanggalBg != null) 'tanggal_bg': _fmtTgl.format(_tanggalBg!),
        'keterangan': _keterangan.text.trim(),
        'kode_unik': _kodeUnik,
          'alokasi': alokasi,
        },
      );
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
        initialChildSize: 0.92,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, sc) => AppFormSheet(
          scrollController: sc,
          title: 'Pembayaran Hutang Supplier',
          subtitle:
              'Alokasi tidak boleh melebihi outstanding tiap faktur; total pembayaran = jumlah alokasi. Retry aman (idempoten).',
          icon: Icons.payments_outlined,
          errorText: _error,
          errorDetail: detailUntuk(_error),
          children: [
            AppFormSection(judul: 'Supplier & Faktur', children: [
              OutlinedButton.icon(
                onPressed: _pilihSupplier,
                icon: const Icon(Icons.search, size: 16),
                label: Text(_supplier == null
                    ? 'Pilih Supplier *'
                    : '${_supplier!['kode']} — ${_supplier!['nama']}'),
              ),
              const SizedBox(height: 8),
              if (_supplier != null && _fakturs.isEmpty)
                Text('Tidak ada faktur outstanding untuk supplier ini.',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context))),
              for (final f in _fakturs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${f['nomorFaktur']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12.5)),
                          Text(
                              'Sisa: ${_fmtRp.format((f['outstanding'] as num?) ?? 0)} · JT ${f['jatuhTempo']}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondaryOf(context))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _alokasi.putIfAbsent(
                            (f['fakturId'] as num).toInt(),
                            () => TextEditingController()),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Alokasi (Rp)',
                            isDense: true,
                            border: OutlineInputBorder()),
                        onChanged: (_) => setStateIfMounted(() {}),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_check, size: 18),
                      tooltip: 'Isi penuh (lunasi faktur ini)',
                      onPressed: () {
                        _alokasi[(f['fakturId'] as num).toInt()]!.text =
                            '${(f['outstanding'] as num?)?.toDouble() ?? 0}';
                        setStateIfMounted(() {});
                      },
                    ),
                  ]),
                ),
            ]),
            const SizedBox(height: 12),
            AppFormSection(judul: 'Metode Pembayaran', children: [
              DropdownButtonFormField<String>(
                value: _metode,
                decoration:
                    AppFormStyle.fieldDecoration(context, labelText: 'Metode'),
                items: const [
                  DropdownMenuItem(value: 'TUNAI', child: Text('Tunai')),
                  DropdownMenuItem(value: 'TRANSFER', child: Text('Transfer')),
                  DropdownMenuItem(value: 'GIRO', child: Text('Giro / BG')),
                  DropdownMenuItem(
                      value: 'DISCOUNT', child: Text('Discount (pengurang)')),
                  DropdownMenuItem(
                      value: 'RETUR', child: Text('Retur (pengurang)')),
                ],
                onChanged: (v) =>
                    setStateIfMounted(() => _metode = v ?? 'TUNAI'),
              ),
              if (_metode == 'GIRO' || _metode == 'TRANSFER') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: AppFormTextField(
                          label: _metode == 'GIRO' ? 'No. BG *' : 'Referensi',
                          controller: _noBg)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: AppFormTextField(
                          label: 'Bank', controller: _namaBank)),
                ]),
                if (_metode == 'GIRO')
                  OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showDatePicker(
                          context: context,
                          initialDate: _tanggalBg ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (t != null) setStateIfMounted(() => _tanggalBg = t);
                    },
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(_tanggalBg == null
                        ? 'BG Jatuh Tempo'
                        : 'BG JT: ${_fmtTgl.format(_tanggalBg!)}'),
                  ),
              ],
              const SizedBox(height: 12),
              AppFormTextField(
                  label: 'Keterangan', controller: _keterangan, maxLines: 2),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('TOTAL PEMBAYARAN: ${_fmtRp.format(_totalAlokasi)}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
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
              label: const Text('Simpan Pembayaran'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetPilihSupplierHutang extends StatefulWidget {
  const _SheetPilihSupplierHutang();

  @override
  State<_SheetPilihSupplierHutang> createState() =>
      _SheetPilihSupplierHutangState();
}

class _SheetPilihSupplierHutangState extends State<_SheetPilihSupplierHutang> {
  List<Map<String, dynamic>> _hasil = [];
  bool _memuat = false;

  Future<void> _cari(String v) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('si_supplier_list', {'keyword': v.trim(), 'page_size': 30});
      setStateIfMounted(() => _hasil =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // biarkan hasil lama
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
          const Text('Pilih Supplier',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          AppSearchField(
            hintText: 'Cari kode / nama supplier...',
            autofocus: true,
            debounce: Duration.zero,
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
                title: Text('${_hasil[i]['kode']} — ${_hasil[i]['nama']}'),
                onTap: () => Navigator.pop(context, _hasil[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// TAB 3: AGING
// =============================================================================

class _TabAging extends StatefulWidget {
  const _TabAging();

  @override
  State<_TabAging> createState() => _TabAgingState();
}

class _TabAgingState extends State<_TabAging> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _ringkasan = {};
  DateTime _asOf = DateTime.now();

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
      final hasil = await ApiClient.instance
          .aksi('si_payable_aging', {'as_of': _fmtTgl.format(_asOf)});
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _ringkasan = (hasil['ringkasan'] as Map<String, dynamic>?) ??
            <String, dynamic>{};
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  Widget _kartu(String label, dynamic nilai, Color warna) => SizedBox(
        width: 190,
        child: AppKpiCard(
            icon: Icons.schedule_outlined,
            warna: warna,
            nilai: _fmtRp.format((nilai as num?) ?? 0),
            label: label),
      );

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return _PanelError(
          pesan: _error!, detail: detailUntuk(_error), onCoba: _muat);
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(children: [
            OutlinedButton.icon(
              onPressed: () async {
                final t = await showDatePicker(
                    context: context,
                    initialDate: _asOf,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (t != null) {
                  _asOf = t;
                  _muat();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('As of: ${_fmtTgl.format(_asOf)}'),
            ),
            const SizedBox(width: 12),
            Text('Total: ${_fmtRp.format((_ringkasan['total'] as num?) ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _kartu('Belum Jth Tempo', _ringkasan['belumJatuhTempo'],
                  AppColors.success),
              const SizedBox(width: 8),
              _kartu('1-30 hari', _ringkasan['b1_30'], AppColors.teal),
              const SizedBox(width: 8),
              _kartu('31-60 hari', _ringkasan['b31_60'], AppColors.warning),
              const SizedBox(width: 8),
              _kartu('61-90 hari', _ringkasan['b61_90'], AppColors.info),
              const SizedBox(width: 8),
              _kartu('> 90 hari', _ringkasan['b90'], AppColors.danger),
            ]),
          ),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 900,
            emptyText: 'Tidak ada hutang outstanding pada tanggal acuan.',
            columns: const [
              AppTableColumn('Supplier', flex: 3),
              AppTableColumn('No. Faktur', flex: 2),
              AppTableColumn('Tgl Faktur', flex: 2),
              AppTableColumn('Jatuh Tempo', flex: 2),
              AppTableColumn('Bucket', flex: 2),
              AppTableColumn('Outstanding', flex: 2, align: TextAlign.right),
            ],
            rows: _data.map((a) {
              const labelBucket = {
                'BELUM': 'Belum Jth Tempo',
                'B1_30': '1-30',
                'B31_60': '31-60',
                'B61_90': '61-90',
                'B90': '> 90',
              };
              return AppTableRowData(cells: [
                AppTableCell.text(
                    '${a['supplierKode']} ${a['supplierNama']}'.trim(),
                    flex: 3,
                    maxLines: 2),
                AppTableCell.text('${a['nomorFaktur']}', flex: 2),
                AppTableCell.text('${a['tanggalFaktur']}'.split(' ').first,
                    flex: 2),
                AppTableCell.text('${a['jatuhTempo']}', flex: 2),
                AppTableCell.text(labelBucket['${a['bucket']}'] ?? '-',
                    flex: 2),
                AppTableCell.text(
                    _fmtRp.format((a['outstanding'] as num?) ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]);
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 4: FAKTUR -- termin/jenis/DP per faktur kulakan (SCR-20) + cetak (SCR-28)
// =============================================================================

class _TabFaktur extends StatefulWidget {
  const _TabFaktur();

  @override
  State<_TabFaktur> createState() => _TabFakturState();
}

class _TabFakturState extends State<_TabFaktur> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  String _kataKunci = '';

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
      final hasil = await ApiClient.instance.aksi('kulakan_faktur_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  Future<void> _aturTermin(Map<String, dynamic> f) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormTerminFaktur(faktur: f),
    );
    if (tersimpan == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Termin/jenis pembayaran faktur tersimpan (hutang terdaftar).')));
    }
  }

  Future<void> _cetakFaktur(Map<String, dynamic> f) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('kulakan_faktur_detail', {'faktur_id': f['fakturId']});
      final h = (hasil['header'] as Map<String, dynamic>?) ?? {};
      final items =
          ((hasil['items'] as List?) ?? []).cast<Map<String, dynamic>>();
      final doc = pw.Document();
      doc.addPage(pw.Page(
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FAKTUR PEMBELIAN (KULAKAN)',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('No. Faktur: ${h['nomorFaktur']}'),
            pw.Text('Tanggal: ${h['tanggalFaktur']}'),
            pw.Text('Supplier: ${h['namaSupplier']}'),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['Barang', 'Qty', 'Harga Satuan', 'Jumlah'],
              data: items
                  .map((it) => [
                        '${it['namaProduk']}',
                        '${it['qty']}',
                        _fmtRp.format((it['hargaBeliSatuan'] as num?) ?? 0),
                        _fmtRp.format((it['totalHarga'] as num?) ?? 0),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 8),
            if (((h['diskon'] as num?) ?? 0) > 0)
              pw.Text('Diskon/Potongan: ${_fmtRp.format(h['diskon'])}'),
            pw.Text(
                'TOTAL: ${_fmtRp.format((h['totalFakturFinal'] as num?) ?? 0)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if ('${h['keterangan'] ?? ''}'.isNotEmpty)
              pw.Text('Keterangan: ${h['keterangan']}'),
          ],
        ),
      ));
      await Printing.layoutPdf(
          onLayout: (_) => doc.save(),
          name: 'faktur-kulakan-${h['fakturId']}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal cetak faktur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return _PanelError(
          pesan: _error!, detail: detailUntuk(_error), onCoba: _muat);
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          AppSearchField(
            hintText: 'Cari no. faktur / supplier...',
            onChanged: (v) {
              _kataKunci = v.trim();
              _halaman = 1;
              _muat();
            },
          ),
          const SizedBox(height: 8),
          Text(
              'Faktur kulakan (entry lewat menu Kulakan/Pembelian Supplier). Atur jenis '
              'CASH/DP/CREDIT + termin di sini agar porsi belum dibayar terdaftar sebagai hutang.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 860,
            emptyText: 'Belum ada faktur kulakan.',
            columns: const [
              AppTableColumn('No. Faktur', flex: 2),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Supplier', flex: 3),
              AppTableColumn('Total', flex: 2, align: TextAlign.right),
              AppTableColumn('Aksi', flex: 2, align: TextAlign.center),
            ],
            rows: _data.map((f) {
              final total = (f['totalFakturFinal'] as num?) ??
                  (f['totalFakturManual'] as num?) ??
                  (f['totalHitung'] as num?) ??
                  0;
              return AppTableRowData(cells: [
                AppTableCell.text('${f['nomorFaktur'] ?? ''}', flex: 2),
                AppTableCell.text('${f['tanggalFaktur'] ?? ''}', flex: 2),
                AppTableCell.text('${f['namaSupplier'] ?? ''}',
                    flex: 3, maxLines: 2),
                AppTableCell.text(_fmtRp.format(total),
                    flex: 2, align: TextAlign.right),
                AppTableCell(
                    child: AksiBarisMenu(aksi: [
                  AksiBaris(
                      ikon: Icons.schedule_outlined,
                      label: 'Atur Termin / Jenis Pembayaran (Hutang)',
                      onTap: () => _aturTermin(f)),
                  AksiBaris(
                      ikon: Icons.print_outlined,
                      label: 'Cetak Faktur Pembelian (PDF)',
                      onTap: () => _cetakFaktur(f))
                ])),
              ]);
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: _halaman > 1
                    ? () {
                        _halaman--;
                        _muat();
                      }
                    : null,
                child: const Text('Sebelumnya')),
            Text('Hal. $_halaman'),
            TextButton(
                onPressed: _data.length >= _pageSize
                    ? () {
                        _halaman++;
                        _muat();
                      }
                    : null,
                child: const Text('Berikutnya')),
          ]),
        ],
      ),
    );
  }
}

class _FormTerminFaktur extends StatefulWidget {
  final Map<String, dynamic> faktur;
  const _FormTerminFaktur({required this.faktur});

  @override
  State<_FormTerminFaktur> createState() => _FormTerminFakturState();
}

class _FormTerminFakturState extends State<_FormTerminFaktur> with JejakGalat {
  String _jenis = 'CREDIT';
  final _termin = TextEditingController(text: '30');
  final _dibayarAwal = TextEditingController(text: '0');
  final _keterangan = TextEditingController();
  bool _menyimpan = false;
  String? _error;

  @override
  void dispose() {
    _termin.dispose();
    _dibayarAwal.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      // Lokal dulu, baru dikirim. Kuncinya per faktur supaya penyuntingan
      // termin berulang hanya menyisakan keadaan terakhir di antrean.
      await prosesSimpanMaster(
        context,
        aksi: 'si_purchase_terms_save',
        body: {
          'faktur_id': widget.faktur['fakturId'],
          'jenis_pembayaran': _jenis,
          'termin_hari': int.tryParse(_termin.text.trim()) ?? 0,
          if (_jenis == 'DP')
            'dibayar_awal':
                double.tryParse(_dibayarAwal.text.replaceAll(',', '.')) ?? 0,
          'keterangan': _keterangan.text.trim(),
        },
        kunci: 'si_purchase_terms:${widget.faktur['fakturId']}',
      );
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
        initialChildSize: 0.7,
        expand: false,
        builder: (context, sc) => AppFormSheet(
          scrollController: sc,
          title: 'Termin Faktur ${widget.faktur['nomorFaktur'] ?? ''}',
          subtitle:
              'CASH = lunas saat faktur (tanpa hutang); DP = sebagian dibayar; CREDIT = penuh jadi hutang. Jatuh tempo = tanggal faktur + termin.',
          icon: Icons.schedule_outlined,
          errorText: _error,
          errorDetail: detailUntuk(_error),
          children: [
            AppFormSection(judul: 'Jenis Pembayaran', children: [
              DropdownButtonFormField<String>(
                value: _jenis,
                decoration:
                    AppFormStyle.fieldDecoration(context, labelText: 'Jenis'),
                items: const [
                  DropdownMenuItem(
                      value: 'CASH', child: Text('CASH (lunas saat faktur)')),
                  DropdownMenuItem(
                      value: 'DP', child: Text('DP (sebagian dibayar)')),
                  DropdownMenuItem(
                      value: 'CREDIT', child: Text('CREDIT (hutang penuh)')),
                ],
                onChanged: (v) =>
                    setStateIfMounted(() => _jenis = v ?? 'CREDIT'),
              ),
              const SizedBox(height: 12),
              AppFormTextField(
                  label: 'Termin (hari)',
                  controller: _termin,
                  keyboardType: TextInputType.number),
              if (_jenis == 'DP')
                AppFormTextField(
                    label: 'Dibayar Awal / DP (Rp) *',
                    controller: _dibayarAwal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true)),
              AppFormTextField(
                  label: 'Keterangan', controller: _keterangan, maxLines: 2),
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
              label: const Text('Simpan'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAB 5: LAPORAN PEMBELIAN PER PERIODE (SCR-29)
// =============================================================================

class _TabLaporanPembelian extends StatefulWidget {
  const _TabLaporanPembelian();

  @override
  State<_TabLaporanPembelian> createState() => _TabLaporanPembelianState();
}

class _TabLaporanPembelianState extends State<_TabLaporanPembelian>
    with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _ringkasan = {};
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();

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
      final hasil = await ApiClient.instance.aksi('si_purchase_report', {
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _ringkasan = (hasil['ringkasan'] as Map<String, dynamic>?) ??
            <String, dynamic>{};
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return _PanelError(
          pesan: _error!, detail: detailUntuk(_error), onCoba: _muat);
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final t = await showDatePicker(
                    context: context,
                    initialDate: _dari,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (t != null) {
                  _dari = t;
                  _muat();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('Dari: ${_fmtTgl.format(_dari)}',
                  style: const TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final t = await showDatePicker(
                    context: context,
                    initialDate: _sampai,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (t != null) {
                  _sampai = t;
                  _muat();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('Sampai: ${_fmtTgl.format(_sampai)}',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              SizedBox(
                  width: 190,
                  child: AppKpiCard(
                      icon: Icons.shopping_cart_outlined,
                      warna: AppColors.primary,
                      nilai: _fmtRp.format((_ringkasan['total'] as num?) ?? 0),
                      label: 'Total Pembelian')),
              const SizedBox(width: 8),
              SizedBox(
                  width: 170,
                  child: AppKpiCard(
                      icon: Icons.money_outlined,
                      warna: AppColors.success,
                      nilai: _fmtRp.format((_ringkasan['cash'] as num?) ?? 0),
                      label: 'Cash')),
              const SizedBox(width: 8),
              SizedBox(
                  width: 170,
                  child: AppKpiCard(
                      icon: Icons.hourglass_bottom_outlined,
                      warna: AppColors.warning,
                      nilai: _fmtRp.format((_ringkasan['dp'] as num?) ?? 0),
                      label: 'DP')),
              const SizedBox(width: 8),
              SizedBox(
                  width: 170,
                  child: AppKpiCard(
                      icon: Icons.credit_card_outlined,
                      warna: AppColors.info,
                      nilai: _fmtRp.format((_ringkasan['credit'] as num?) ?? 0),
                      label: 'Credit')),
              const SizedBox(width: 8),
              SizedBox(
                  width: 190,
                  child: AppKpiCard(
                      icon: Icons.account_balance_wallet_outlined,
                      warna: AppColors.danger,
                      nilai: _fmtRp
                          .format((_ringkasan['sisaHutang'] as num?) ?? 0),
                      label: 'Sisa Hutang')),
            ]),
          ),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 960,
            emptyText: 'Tidak ada pembelian pada periode ini.',
            columns: const [
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('No. Faktur', flex: 2),
              AppTableColumn('Supplier', flex: 3),
              AppTableColumn('Jenis', flex: 1),
              AppTableColumn('Total', flex: 2, align: TextAlign.right),
              AppTableColumn('Dibayar', flex: 2, align: TextAlign.right),
              AppTableColumn('Sisa', flex: 2, align: TextAlign.right),
            ],
            rows: _data
                .map((r) => AppTableRowData(cells: [
                      AppTableCell.text(
                          '${r['tanggalFaktur']}'.split(' ').first,
                          flex: 2),
                      AppTableCell.text('${r['nomorFaktur']}', flex: 2),
                      AppTableCell.text(
                          '${r['supplierKode']} ${r['supplierNama']}'.trim(),
                          flex: 3,
                          maxLines: 2),
                      AppTableCell.text('${r['jenisPembayaran']}', flex: 1),
                      AppTableCell.text(
                          _fmtRp.format((r['totalFaktur'] as num?) ?? 0),
                          flex: 2,
                          align: TextAlign.right),
                      AppTableCell.text(
                          _fmtRp.format((r['dibayar'] as num?) ?? 0),
                          flex: 2,
                          align: TextAlign.right),
                      AppTableCell.text(
                          _fmtRp.format((r['sisaHutang'] as num?) ?? 0),
                          flex: 2,
                          align: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ]))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  final String pesan;
  final VoidCallback onCoba;
  final String? detail;
  const _PanelError({required this.pesan, required this.onCoba, this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(pesan, textAlign: TextAlign.center),
          AppDetailGalatOpsional(detail: detail),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ]),
      ),
    );
  }
}
