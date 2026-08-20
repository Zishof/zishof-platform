import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _fmtRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Laba Rugi varian Inventory &amp; Sales (layar legacy 45-48).</h3>
///
/// Parameter periode/sales (SCR-45), Laba Kotor per produk/customer/sales dari
/// HPP snapshot baris order (SCR-46), Laporan Laba/Rugi operasional varian
/// (SCR-47) + cetak PDF (SCR-48). Laporan keuangan penuh (Neraca/Arus Kas/
/// Buku Besar) tetap lewat menu Laporan Keuangan existing.
class LabaRugiScreen extends StatefulWidget {
  const LabaRugiScreen({super.key});

  @override
  State<LabaRugiScreen> createState() => _LabaRugiScreenState();
}

class _LabaRugiScreenState extends State<LabaRugiScreen> with JejakGalat {
  DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _sampai = DateTime.now();
  int? _salesId;
  List<Map<String, dynamic>> _pilihanSales = [];
  String _groupBy = 'produk';

  bool _memuat = true;
  String? _error;
  Map<String, dynamic> _labaRugi = {};
  List<Map<String, dynamic>> _labaKotor = [];
  Map<String, dynamic> _ringkasKotor = {};
  List<Map<String, dynamic>> _detail = [];
  final _hppTambah = TextEditingController(text: '0');
  String _filterDetail = 'semua'; // semua | jual_rugi
  String _statusLunas = ''; // '' | lunas | belum

  /// Benar selama yang tampil masih salinan lokal (server belum menjawab, atau
  /// gagal karena offline) -- menyalakan PenandaDataTersimpan.
  bool _dariCache = false;
  DateTime? _cacheDisimpanPada;

  @override
  void initState() {
    super.initState();
    _muatParams();
    _muat();
  }

  Future<void> _muatParams() async {
    try {
      final hasil =
          await ApiClient.instance.aksi('si_profit_loss_params', {});
      setStateIfMounted(() => _pilihanSales = ((hasil['sales'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {}
  }

  /// Sebar satu amplop gabungan (pl/gp/dt) ke state layar. Dipanggil DI DALAM
  /// setState -- baik utk snapshot lokal maupun hasil server.
  void _terapkanHasil(Map<String, dynamic> hasil) {
    final pl = Map<String, dynamic>.from((hasil['pl'] as Map?) ?? const {});
    final gp = Map<String, dynamic>.from((hasil['gp'] as Map?) ?? const {});
    final dt = Map<String, dynamic>.from((hasil['dt'] as Map?) ?? const {});
    _labaRugi = Map<String, dynamic>.from((pl['data'] as Map?) ?? const {});
    _labaKotor = ((gp['rows'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _ringkasKotor =
        Map<String, dynamic>.from((gp['ringkasan'] as Map?) ?? const {});
    _detail = ((dt['rows'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    final body = {
      'dari': _fmtTgl.format(_dari),
      'sampai': _fmtTgl.format(_sampai),
      if (_salesId != null) 'sales_id': _salesId,
    };
    // BACA LOKAL DULU (pola MasterOffline.daftarCacheDulu, dihitung MANUAL di
    // sini): satu layar = TIGA aksi yang saling melengkapi (laba/rugi
    // operasional berupa objek `data`, laba kotor berupa rows+ringkasan, dan
    // grid rincian per baris faktur). Ketiganya disimpan sbg SATU amplop --
    // dengan daftarCacheDulu (satu daftar saja) kegagalan aksi pertama tetap
    // menggagalkan seluruh layar, dan emisi lokalnya menampilkan KPI/ringkasan
    // nol yang menyesatkan di atas tabel yang terisi.
    //
    // Kunci cache memuat SELURUH parameter yang mengubah isi laporan: periode,
    // sales, group by, HPP tambah, dan kedua filter grid rincian.
    //
    // TANPA kilau baris: baris "Laba Kotor per X" murni rekap agregat, dan
    // baris grid rincian tidak punya identitas stabil dari server (tidak ada
    // id baris faktur) -- cukup cache-nya saja.
    final kunci = 'laporan:si_laba_rugi:'
        '${_fmtTgl.format(_dari)}_${_fmtTgl.format(_sampai)}'
        ':${_salesId ?? 'semua'}:$_groupBy:${_hppTambah.text.trim()}'
        ':$_filterDetail:${_statusLunas.isEmpty ? 'semua' : _statusLunas}';
    var adaCacheLokal = false;
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(kunci);
    if (tersimpan != null) {
      try {
        final lokal = jsonDecode(tersimpan) as Map<String, dynamic>;
        adaCacheLokal = true;
        final stempel = DateTime.tryParse('${lokal['_disimpanPada'] ?? ''}');
        setStateIfMounted(() {
          _terapkanHasil(lokal);
          _dariCache = true;
          _cacheDisimpanPada = stempel;
          _memuat = false;
        });
      } catch (_) {
        adaCacheLokal = false; // cache rusak -- lanjut jalur server biasa.
      }
    }
    try {
      final pl = await ApiClient.instance.aksi('si_profit_loss_report', body);
      final gp = await ApiClient.instance.aksi('si_gross_profit_report', {
        ...body,
        'group_by': _groupBy,
        // "HPP Tambah (%)" legacy layar 45/46 -- markup eksplisit atas HPP snapshot.
        'hpp_tambah_persen': double.tryParse(_hppTambah.text) ?? 0,
      });
      final dt = await ApiClient.instance.aksi('si_profit_loss_detail', {
        ...body,
        if (_filterDetail == 'jual_rugi') 'filter': 'jual_rugi',
        if (_statusLunas.isNotEmpty) 'status_lunas': _statusLunas,
      });
      final gabungan = <String, dynamic>{'pl': pl, 'gp': gp, 'dt': dt};
      setStateIfMounted(() {
        _terapkanHasil(gabungan);
        // Angka server sudah terpasang -> penanda salinan tersimpan padam.
        _dariCache = false;
        _cacheDisimpanPada = null;
        _memuat = false;
      });
      // Stempel waktu ikut disimpan DI DALAM amplop supaya pemuatan berikutnya
      // bisa memberi tahu KAPAN salinan ini dibuat -- _terapkanHasil hanya
      // membaca kunci pl/gp/dt, jadi kunci tambahan ini tak mengganggu.
      await CoreDb.instance.simpanCacheReferensi(
          kunci,
          jsonEncode({
            ...gabungan,
            '_disimpanPada': DateTime.now().toIso8601String(),
          }));
    } catch (e) {
      // Offline dgn snapshot sudah tampil -> cukup diam (indikator offline
      // global sudah menceritakan kondisinya).
      if (e is ApiException && e.offline && adaCacheLokal) {
        setStateIfMounted(() => _memuat = false);
        return;
      }
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  Future<void> _cetakPdf() async {
    final d = _labaRugi;
    final beban = ((d['beban'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Text('LAPORAN LABA / RUGI — INVENTORY & SALES',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.Text(
            'Periode: ${_fmtTgl.format(_dari)} s/d ${_fmtTgl.format(_sampai)}'
            '${_salesId != null ? '  ·  Sales terpilih' : '  ·  Semua sales'}'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          data: [
            ['Pendapatan faktur (AR)', _fmtRp.format(d['pendapatanFaktur'] ?? 0)],
            ['Penjualan tunai lapangan', _fmtRp.format(d['penjualanTunai'] ?? 0)],
            ['TOTAL PENDAPATAN', _fmtRp.format(d['totalPendapatan'] ?? 0)],
            ['HPP (snapshot)', _fmtRp.format(d['hpp'] ?? 0)],
            ['LABA KOTOR', _fmtRp.format(d['labaKotor'] ?? 0)],
            for (final b in beban)
              ['Beban: ${b['kategori']}', _fmtRp.format(b['nilai'] ?? 0)],
            ['TOTAL BEBAN SESI', _fmtRp.format(d['totalBeban'] ?? 0)],
            ['LABA BERSIH', _fmtRp.format(d['labaBersih'] ?? 0)],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text('${d['catatan'] ?? ''}',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 12),
        pw.Text('LABA KOTOR PER ${_groupBy.toUpperCase()}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Nama', 'Qty', 'Penjualan', 'HPP', 'Laba Kotor', 'Margin %'],
          data: [
            for (final r in _labaKotor)
              [
                '${r['grupNama']}',
                '${r['qty']}',
                _fmtRp.format(r['penjualan'] ?? 0),
                _fmtRp.format(r['hpp'] ?? 0),
                _fmtRp.format(r['labaKotor'] ?? 0),
                ((r['marginPersen'] as num?) ?? 0).toStringAsFixed(1),
              ]
          ],
        ),
      ],
    ));
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: 'laba-rugi-${_fmtTgl.format(_dari)}-${_fmtTgl.format(_sampai)}.pdf');
    ApiClient.instance.aksi('si_print_log_create', {
      'jenis_dokumen': 'laporan_laba_rugi',
      'referensi':
          '${_fmtTgl.format(_dari)}_${_fmtTgl.format(_sampai)}',
      'parameter':
          'dari=${_fmtTgl.format(_dari)};sampai=${_fmtTgl.format(_sampai)};sales_id=${_salesId ?? ''};group_by=$_groupBy',
      'perangkat': 'flutter',
    }).then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.labaRugi,
      judul: 'Laba Rugi',
      subjudul:
          'Laba kotor (HPP snapshot) + laba/rugi operasional varian — layar legacy 45-48',
      scrollable: false,
      aksiHeader: IconButton(
          onPressed: _memuat ? null : _cetakPdf,
          tooltip: 'Cetak PDF',
          icon: const Icon(Icons.print_outlined)),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _PanelErrorLr(pesan: _error!, detail: detailUntuk(_error), onCoba: _muat)
              : RefreshIndicator(
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
                                lastDate: DateTime(2035));
                            if (t != null) {
                              setStateIfMounted(() => _dari = t);
                              _muat();
                            }
                          },
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Dari ${_fmtTgl.format(_dari)}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showDatePicker(
                                context: context,
                                initialDate: _sampai,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035));
                            if (t != null) {
                              setStateIfMounted(() => _sampai = t);
                              _muat();
                            }
                          },
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('s/d ${_fmtTgl.format(_sampai)}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        DropdownButton<int?>(
                          value: _salesId,
                          hint: const Text('Semua sales',
                              style: TextStyle(fontSize: 12)),
                          items: [
                            const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Semua sales',
                                    style: TextStyle(fontSize: 12))),
                            for (final s in _pilihanSales)
                              DropdownMenuItem<int?>(
                                  value: (s['id'] as num).toInt(),
                                  child: Text('${s['kode']} — ${s['nama']}',
                                      style: const TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) {
                            setStateIfMounted(() => _salesId = v);
                            _muat();
                          },
                        ),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: _hppTambah,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                                labelText: 'HPP Tambah (%)', isDense: true),
                            onSubmitted: (_) => _muat(),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      // Penanda salinan tersimpan -- di kolom utama laporan,
                      // tepat DI ATAS kartu KPI dan rincian, supaya angka
                      // rupiah tidak terbaca sebagai data terkini.
                      PenandaDataTersimpan(
                          tampil: _dariCache,
                          diperbaruiPada: _cacheDisimpanPada),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        SizedBox(
                          width: 230,
                          child: AppKpiCard(
                              icon: Icons.trending_up,
                              warna: AppColors.info,
                              nilai: _fmtRp
                                  .format(_labaRugi['totalPendapatan'] ?? 0),
                              label: 'Total Pendapatan'),
                        ),
                        SizedBox(
                          width: 210,
                          child: AppKpiCard(
                              icon: Icons.inventory_2_outlined,
                              warna: Colors.orange,
                              nilai: _fmtRp.format(_labaRugi['hpp'] ?? 0),
                              label: 'HPP (snapshot)'),
                        ),
                        SizedBox(
                          width: 210,
                          child: AppKpiCard(
                              icon: Icons.receipt_outlined,
                              warna: AppColors.danger,
                              nilai:
                                  _fmtRp.format(_labaRugi['totalBeban'] ?? 0),
                              label: 'Beban Sesi'),
                        ),
                        SizedBox(
                          width: 220,
                          child: AppKpiCard(
                              icon: Icons.savings_outlined,
                              warna: AppColors.success,
                              nilai:
                                  _fmtRp.format(_labaRugi['labaBersih'] ?? 0),
                              label: 'Laba Bersih'),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      AppFormSection(judul: 'Rincian Laba/Rugi', children: [
                        _baris('Pendapatan faktur (AR)',
                            _labaRugi['pendapatanFaktur']),
                        _baris('Penjualan tunai lapangan',
                            _labaRugi['penjualanTunai']),
                        _baris('Total pendapatan', _labaRugi['totalPendapatan'],
                            tebal: true),
                        _baris('HPP', _labaRugi['hpp']),
                        _baris('Laba kotor', _labaRugi['labaKotor'],
                            tebal: true),
                        for (final b in ((_labaRugi['beban'] as List?) ?? []))
                          _baris('Beban: ${(b as Map)['kategori']}', b['nilai']),
                        _baris('Total beban sesi', _labaRugi['totalBeban']),
                        _baris('LABA BERSIH', _labaRugi['labaBersih'],
                            tebal: true),
                        const SizedBox(height: 6),
                        Text('${_labaRugi['catatan'] ?? ''}',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(context))),
                      ]),
                      const SizedBox(height: 10),
                      AppFormSection(
                        judul: 'Laba Kotor per ${_groupBy[0].toUpperCase()}${_groupBy.substring(1)}',
                        aksiJudul: DropdownButton<String>(
                          value: _groupBy,
                          items: const [
                            DropdownMenuItem(
                                value: 'produk', child: Text('Per Produk')),
                            DropdownMenuItem(
                                value: 'customer', child: Text('Per Customer')),
                            DropdownMenuItem(
                                value: 'sales', child: Text('Per Sales')),
                          ],
                          onChanged: (v) {
                            setStateIfMounted(() => _groupBy = v ?? 'produk');
                            _muat();
                          },
                        ),
                        children: [
                          AppDataTable(
                            minWidth: 860,
                            emptyText:
                                'Belum ada order terfakturkan pada periode ini.',
                            columns: const [
                              AppTableColumn('Nama', flex: 3),
                              AppTableColumn('Qty', flex: 1,
                                  align: TextAlign.right),
                              AppTableColumn('Penjualan', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('HPP', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('Laba Kotor', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('Margin %', flex: 1,
                                  align: TextAlign.right),
                            ],
                            rows: [
                              for (final r in _labaKotor)
                                AppTableRowData(cells: [
                                  AppTableCell.text('${r['grupNama']}', flex: 3),
                                  AppTableCell.text('${r['qty']}',
                                      flex: 1, align: TextAlign.right),
                                  AppTableCell.text(
                                      _fmtRp.format(r['penjualan'] ?? 0),
                                      flex: 2,
                                      align: TextAlign.right),
                                  AppTableCell.text(_fmtRp.format(r['hpp'] ?? 0),
                                      flex: 2, align: TextAlign.right),
                                  AppTableCell.text(
                                      _fmtRp.format(r['labaKotor'] ?? 0),
                                      flex: 2,
                                      align: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700)),
                                  AppTableCell.text(
                                      ((r['marginPersen'] as num?) ?? 0)
                                          .toStringAsFixed(1),
                                      flex: 1,
                                      align: TextAlign.right),
                                ]),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                              'Total: penjualan ${_fmtRp.format(_ringkasKotor['penjualan'] ?? 0)} · HPP ${_fmtRp.format(_ringkasKotor['hpp'] ?? 0)} (+${((_ringkasKotor['hppTambahPersen'] as num?) ?? 0)}% tambah) · laba kotor ${_fmtRp.format(_ringkasKotor['labaKotor'] ?? 0)} (${((_ringkasKotor['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%)',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppFormSection(
                        judul: 'Rincian per Baris Faktur (grid legacy layar 47)',
                        aksiJudul:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButton<String>(
                            value: _filterDetail,
                            items: const [
                              DropdownMenuItem(
                                  value: 'semua', child: Text('Semua')),
                              DropdownMenuItem(
                                  value: 'jual_rugi',
                                  child: Text('Jual Rugi saja')),
                            ],
                            onChanged: (v) {
                              setStateIfMounted(
                                  () => _filterDetail = v ?? 'semua');
                              _muat();
                            },
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _statusLunas,
                            items: const [
                              DropdownMenuItem(
                                  value: '', child: Text('Lunas & Belum')),
                              DropdownMenuItem(
                                  value: 'lunas', child: Text('Lunas')),
                              DropdownMenuItem(
                                  value: 'belum', child: Text('Belum Lunas')),
                            ],
                            onChanged: (v) {
                              setStateIfMounted(() => _statusLunas = v ?? '');
                              _muat();
                            },
                          ),
                        ]),
                        children: [
                          AppDataTable(
                            minWidth: 1100,
                            emptyText: _filterDetail == 'jual_rugi'
                                ? 'Tidak ada baris jual rugi pada periode ini.'
                                : 'Tidak ada baris faktur pada periode ini.',
                            columns: const [
                              AppTableColumn('Sales', flex: 2),
                              AppTableColumn('Tanggal', flex: 2),
                              AppTableColumn('No. Faktur', flex: 2),
                              AppTableColumn('Nama Barang', flex: 3),
                              AppTableColumn('HPP', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('Hrg. Jual', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('Jumlah', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('Rugi/Laba', flex: 2,
                                  align: TextAlign.right),
                              AppTableColumn('Customer', flex: 2),
                            ],
                            rows: [
                              for (final r in _detail)
                                AppTableRowData(cells: [
                                  AppTableCell.text('${r['salesNama']}', flex: 2),
                                  AppTableCell.text(
                                      '${r['tanggal']}'.split(' ').first,
                                      flex: 2),
                                  AppTableCell.text('${r['fakturNomor']}',
                                      flex: 2),
                                  AppTableCell.text('${r['namaProduk']}',
                                      flex: 3),
                                  AppTableCell.text(
                                      _fmtRp.format(r['hppSatuan'] ?? 0),
                                      flex: 2,
                                      align: TextAlign.right),
                                  AppTableCell.text(
                                      _fmtRp.format(r['hargaJual'] ?? 0),
                                      flex: 2,
                                      align: TextAlign.right),
                                  AppTableCell.text(
                                      _fmtRp.format(r['jumlah'] ?? 0),
                                      flex: 2,
                                      align: TextAlign.right),
                                  AppTableCell(
                                    flex: 2,
                                    align: TextAlign.right,
                                    child: Text(
                                      _fmtRp.format(r['labaRugi'] ?? 0),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: ((r['labaRugi'] as num?) ??
                                                      0) <
                                                  0
                                              ? AppColors.danger
                                              : AppColors.success),
                                    ),
                                  ),
                                  AppTableCell.text('${r['customerNama']}',
                                      flex: 2),
                                ]),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _baris(String label, Object? nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: tebal ? FontWeight.w800 : FontWeight.w400))),
        Text(_fmtRp.format((nilai as num?) ?? 0),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: tebal ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
  }
}

class _PanelErrorLr extends StatelessWidget {
  final String pesan;
  final VoidCallback onCoba;
  final String? detail;
  const _PanelErrorLr(
      {required this.pesan, required this.onCoba, this.detail});

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
