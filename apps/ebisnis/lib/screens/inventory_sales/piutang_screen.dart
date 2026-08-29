import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../services/outbox_is.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Piutang Customer (AR) -- layar legacy 32-38.</h3>
///
/// Cermin sisi jual dari layar Hutang Supplier: faktur piutang lahir dari
/// posting sales order (menu Penjualan Sales) / entri manual pemilik; outstanding
/// SELALU dihitung server (register event, pelunasan tidak menghapus dokumen).
/// 5 tab: Piutang (SCR-32/33 + deep-link SCR-31), Penerimaan (SCR-34, idempoten
/// kode_unik + alokasi multi-faktur), Riwayat+Kwitansi (SCR-35/36 PDF), Aging
/// Customer (SCR-37), Aging per Sales (SCR-38). Sales keliling otomatis
/// ter-scope data miliknya (ditegakkan server).
class PiutangScreen extends StatefulWidget {
  const PiutangScreen({super.key});

  @override
  State<PiutangScreen> createState() => _PiutangScreenState();
}

class _PiutangScreenState extends State<PiutangScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    // P7: kirim ulang antrean offline (kwitansi/biaya) begitu layar dibuka --
    // no-op saat kosong, aman dipanggil berulang (idempoten kode_unik).
    OutboxIs.flush();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.piutang,
      judul: 'Piutang Customer (AR)',
      subjudul:
          'Ledger piutang, penerimaan teralokasi, kwitansi, aging per customer & per sales (layar legacy 32-38)',
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
              Tab(text: 'Piutang'),
              Tab(text: 'Penerimaan'),
              Tab(text: 'Riwayat & Kwitansi'),
              Tab(text: 'Aging Customer'),
              Tab(text: 'Aging per Sales'),
              Tab(text: 'Laporan (Rekap Barang)'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tab, children: const [
            _TabPiutang(),
            _TabPenerimaan(),
            _TabRiwayat(),
            _TabAgingCustomer(),
            _TabAgingSales(),
            _TabLaporanPiutang(),
          ]),
        ),
      ]),
    );
  }
}

// =============================================================================
// TAB 1: PIUTANG (SCR-32/33) -- register faktur + filter lunas visual
// =============================================================================

class _TabPiutang extends StatefulWidget {
  const _TabPiutang();

  @override
  State<_TabPiutang> createState() => _TabPiutangState();
}

class _TabPiutangState extends State<_TabPiutang> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  double _totalOutstanding = 0;
  String _kataKunci = '';
  bool _tampilkanLunas = false;
  // Diff emisi lokal-dulu: menggerakkan kilau baris + banner perubahan server.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

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
          'si_receivable_list',
          {
            if (_kataKunci.isNotEmpty) 'q': _kataKunci,
            'tampilkan_lunas': _tampilkanLunas,
            'page': 1,
            'page_size': 200,
          },
          'master:si_piutang:${_tampilkanLunas ? 'semua' : 'berjalan'}',
          fieldData: 'rows', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil, fieldData: 'rows');
          // Ringkasan hanya dikirim server -- jangan dinolkan oleh emisi lokal.
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
            Expanded(
              child: AppSearchField(
                hintText: 'Cari nomor faktur / nama customer...',
                onChanged: (v) {
                  _kataKunci = v.trim();
                  _muat();
                },
              ),
            ),
            const SizedBox(width: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                  value: _tampilkanLunas,
                  onChanged: (v) {
                    setStateIfMounted(() => _tampilkanLunas = v);
                    _muat();
                  }),
              const Text('Tampilkan Lunas', style: TextStyle(fontSize: 12.5)),
            ]),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: 260,
            child: AppKpiCard(
                icon: Icons.request_quote_outlined,
                warna: AppColors.danger,
                nilai: _fmtRp.format(_totalOutstanding),
                label: 'Total Piutang Berjalan'),
          ),
          const SizedBox(height: 10),
          BannerPerubahanServer(
            key: ValueKey('perubahan:${_diff.versi}'),
            baru: _diff.idBaru.length,
            berubah: _diff.idBerubah.length,
            dihapus: _diff.jumlahHapus,
          ),
          AppDataTable(
            minWidth: 1050,
            emptyText: _tampilkanLunas
                ? 'Belum ada faktur piutang.'
                : 'Tidak ada piutang berjalan. (Aktifkan "Tampilkan Lunas" untuk melihat yang selesai.)',
            columns: const [
              AppTableColumn('Customer', flex: 3),
              AppTableColumn('No. Faktur', flex: 2),
              AppTableColumn('Order Asal', flex: 2),
              AppTableColumn('Sales', flex: 2),
              AppTableColumn('Jatuh Tempo', flex: 2),
              AppTableColumn('Total', flex: 2, align: TextAlign.right),
              AppTableColumn('Dibayar', flex: 2, align: TextAlign.right),
              AppTableColumn('Sisa', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final r in _data)
                AppTableRowData(cells: [
                  AppTableCell(
                    flex: 3,
                    child: KilauBaris(
                      kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                      idBaru: _diff.idBaru,
                      idBerubah: _diff.idBerubah,
                      child: Text('${r['customerNama']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  AppTableCell.text('${r['nomor']}', flex: 2),
                  AppTableCell.text('${r['orderNomor'] ?? ''}', flex: 2),
                  AppTableCell.text('${r['salesNama'] ?? ''}', flex: 2),
                  AppTableCell.text('${r['jatuhTempo'] ?? '-'}', flex: 2),
                  AppTableCell.text(_fmtRp.format(r['totalFaktur'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(
                      _fmtRp.format(((r['dibayarAwal'] as num?) ?? 0) +
                          ((r['teralokasi'] as num?) ?? 0)),
                      flex: 2,
                      align: TextAlign.right),
                  AppTableCell(
                    flex: 2,
                    align: TextAlign.right,
                    child: Text(
                      _fmtRp.format(r['outstanding'] ?? 0),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: (r['lunas'] == true)
                              ? AppColors.success
                              : AppColors.danger),
                    ),
                  ),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 2: PENERIMAAN (SCR-34) -- pilih customer -> alokasi multi-faktur
// =============================================================================

class _TabPenerimaan extends StatefulWidget {
  const _TabPenerimaan();

  @override
  State<_TabPenerimaan> createState() => _TabPenerimaanState();
}

class _TabPenerimaanState extends State<_TabPenerimaan> with JejakGalat {
  int? _customerId;
  String _customerNama = '';
  List<Map<String, dynamic>> _faktur = [];
  final Map<int, TextEditingController> _alokasi = {};
  final Set<int> _dipilih = {};
  String _metode = 'TUNAI';
  final _noBg = TextEditingController();
  final _namaBank = TextEditingController();
  DateTime? _tanggalBg;
  final _keterangan = TextEditingController();
  bool _memuat = false;
  bool _menyimpan = false;
  String? _error;
  String? _sukses;

  /// Kunci idempoten DIBUAT ULANG tiap sukses simpan; retry "Simpan" yang sama
  /// memakai kunci yang sama sehingga server tidak menggandakan penerimaan.
  String _kodeUnik = 'KWT-${DateTime.now().millisecondsSinceEpoch}-0';
  int _urutKode = 0;

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

  Future<void> _pilihCustomer() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _DialogCariCustomerPiutang());
    if (pilihan == null) return;
    setStateIfMounted(() {
      _customerId = (pilihan['anggotaId'] as num).toInt();
      _customerNama = '${pilihan['nama']}';
      _sukses = null;
    });
    await _muatFaktur();
  }

  Future<void> _muatFaktur() async {
    if (_customerId == null) return;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
      _faktur = [];
      _dipilih.clear();
    });
    try {
      final hasil = await ApiClient.instance.aksi('si_receivable_list', {
        'customer_id': _customerId,
        'tampilkan_lunas': false,
        'page': 1,
        'page_size': 100,
      });
      setStateIfMounted(() {
        _faktur = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final f in _faktur) {
          final id = (f['id'] as num).toInt();
          _alokasi.putIfAbsent(id, () => TextEditingController());
          _alokasi[id]!.text =
              ((f['outstanding'] as num?) ?? 0).round().toString();
        }
      });
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  double get _totalAlokasi {
    var t = 0.0;
    for (final id in _dipilih) {
      t += double.tryParse(_alokasi[id]?.text ?? '') ?? 0;
    }
    return t;
  }

  Future<void> _simpan() async {
    if (_customerId == null || _dipilih.isEmpty) {
      setStateIfMounted(
          () => _error = 'Pilih customer dan minimal satu faktur.');
      return;
    }
    if (_totalAlokasi <= 0) {
      setStateIfMounted(() => _error = 'Nominal alokasi harus > 0.');
      return;
    }
    if (_metode == 'GIRO' && _noBg.text.trim().isEmpty) {
      setStateIfMounted(() => _error = 'Metode GIRO wajib mengisi No. BG.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
      _sukses = null;
    });
    try {
      // P7: idempoten kode_unik -> boleh diantre offline (OutboxIs).
      final hasil = await OutboxIs.kirimAtauAntre('si_collection_create', {
        'customer_id': _customerId,
        'nominal': _totalAlokasi,
        'metode': _metode,
        if (_metode == 'GIRO') 'no_bg': _noBg.text.trim(),
        if (_metode == 'GIRO' || _metode == 'TRANSFER')
          'nama_bank': _namaBank.text.trim(),
        if (_tanggalBg != null) 'tanggal_bg': _fmtTgl.format(_tanggalBg!),
        'keterangan': _keterangan.text.trim(),
        'kode_unik': _kodeUnik,
        'alokasi': [
          for (final id in _dipilih)
            {
              'piutang_id': id,
              'nominal': double.tryParse(_alokasi[id]?.text ?? '') ?? 0,
            }
        ],
      });
      _urutKode++;
      _kodeUnik = 'KWT-${DateTime.now().millisecondsSinceEpoch}-$_urutKode';
      setStateIfMounted(() => _sukses = hasil['offline'] == true
          ? 'Jaringan terputus — penerimaan DISIMPAN OFFLINE dan akan dikirim otomatis saat online (idempoten, tidak dobel).'
          : 'Penerimaan tersimpan: ${hasil['nomor'] ?? hasil['id']} — kwitansi bisa dicetak di tab Riwayat.');
      if (hasil['offline'] != true) await _muatFaktur();
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolehBuat = Sesi.instance.bolehAksiIs('piutang', 'create');
    if (!bolehBuat) {
      return const Center(
          child: Text('Akun Anda tidak berhak mencatat penerimaan piutang.'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _error!),
          ),
        if (_sukses != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppInfoBanner(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                text: _sukses!),
          ),
        AppFormSection(judul: 'Customer', children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_alt_outlined),
            title: Text(
                _customerNama.isEmpty ? 'Pilih customer...' : _customerNama),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pilihCustomer,
          ),
        ]),
        if (_memuat) const LinearProgressIndicator(),
        if (_customerId != null && !_memuat) ...[
          const SizedBox(height: 10),
          AppFormSection(
            judul: 'Faktur Outstanding',
            aksiJudul: TextButton(
                onPressed: () {
                  setStateIfMounted(() {
                    for (final f in _faktur) {
                      final id = (f['id'] as num).toInt();
                      _dipilih.add(id);
                      _alokasi[id]!.text =
                          ((f['outstanding'] as num?) ?? 0).round().toString();
                    }
                  });
                },
                child: const Text('Lunasi Semua')),
            children: [
              if (_faktur.isEmpty)
                Text('Tidak ada faktur outstanding untuk customer ini.',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context))),
              for (final f in _faktur)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Checkbox(
                      value: _dipilih.contains((f['id'] as num).toInt()),
                      onChanged: (v) => setStateIfMounted(() {
                        final id = (f['id'] as num).toInt();
                        if (v == true) {
                          _dipilih.add(id);
                        } else {
                          _dipilih.remove(id);
                        }
                      }),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${f['nomor']}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                'jt ${f['jatuhTempo'] ?? '-'} · sisa ${_fmtRp.format(f['outstanding'] ?? 0)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryOf(context))),
                          ]),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _alokasi[(f['id'] as num).toInt()],
                        keyboardType: TextInputType.number,
                        enabled: _dipilih.contains((f['id'] as num).toInt()),
                        decoration: const InputDecoration(labelText: 'Alokasi'),
                        onChanged: (_) => setStateIfMounted(() {}),
                      ),
                    ),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AppFormSection(judul: 'Metode Penerimaan', children: [
            DropdownButtonFormField<String>(
              value: _metode,
              decoration: const InputDecoration(labelText: 'Metode'),
              items: const [
                DropdownMenuItem(value: 'TUNAI', child: Text('Tunai')),
                DropdownMenuItem(value: 'TRANSFER', child: Text('Transfer')),
                DropdownMenuItem(value: 'GIRO', child: Text('Giro / BG')),
                DropdownMenuItem(
                    value: 'DISCOUNT', child: Text('Potongan (Discount)')),
                DropdownMenuItem(value: 'RETUR', child: Text('Retur')),
              ],
              onChanged: (v) => setStateIfMounted(() => _metode = v ?? 'TUNAI'),
            ),
            if (_metode == 'GIRO')
              TextField(
                  controller: _noBg,
                  decoration: const InputDecoration(labelText: 'No. BG')),
            if (_metode == 'GIRO' || _metode == 'TRANSFER')
              TextField(
                  controller: _namaBank,
                  decoration: const InputDecoration(labelText: 'Nama Bank')),
            if (_metode == 'GIRO')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(_tanggalBg == null
                    ? 'Tanggal jatuh tempo BG...'
                    : _fmtTgl.format(_tanggalBg!)),
                onTap: () async {
                  final t = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035));
                  if (t != null) setStateIfMounted(() => _tanggalBg = t);
                },
              ),
            TextField(
                controller: _keterangan,
                decoration:
                    const InputDecoration(labelText: 'Keterangan (opsional)')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text('Total penerimaan: ${_fmtRp.format(_totalAlokasi)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            ElevatedButton.icon(
              onPressed: _menyimpan ? null : _simpan,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 13)),
              icon: _menyimpan
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Terima Pembayaran'),
            ),
          ]),
        ],
      ],
    );
  }
}

// =============================================================================
// TAB 3: RIWAYAT + KWITANSI PDF (SCR-35/36)
// =============================================================================

class _TabRiwayat extends StatefulWidget {
  const _TabRiwayat();

  @override
  State<_TabRiwayat> createState() => _TabRiwayatState();
}

class _TabRiwayatState extends State<_TabRiwayat> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  double _totalNominal = 0;
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
      final hasil = await ApiClient.instance.aksi('si_collection_history', {
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
      });
      setStateIfMounted(() {
        _data = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totalNominal = (hasil['totalNominal'] as num?)?.toDouble() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  Future<void> _cetakKwitansi(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('si_collection_receipt', {'penerimaan_id': row['id']});
      final d = Map<String, dynamic>.from((hasil['data'] as Map?) ?? {});
      final alokasi = ((d['alokasi'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final doc = pw.Document();
      doc.addPage(pw.Page(
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('KWITANSI PENERIMAAN PIUTANG',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('No. Kwitansi: ${d['nomor']}'),
            pw.Text('Tanggal: ${d['tanggal']}'),
            pw.Text('Customer: ${d['customerKode']} — ${d['customerNama']}'),
            if ('${d['salesNama']}'.isNotEmpty)
              pw.Text('Sales penagih: ${d['salesNama']}'),
            pw.Text('Metode: ${d['metode']}'
                '${'${d['noBg']}'.isNotEmpty ? '  ·  BG: ${d['noBg']} ${d['namaBank']}' : ''}'),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['No. Faktur', 'Tgl Faktur', 'Total Faktur', 'Dibayar'],
              data: alokasi
                  .map((a) => [
                        '${a['fakturNomor']}',
                        '${a['fakturTanggal']}'.split(' ').first,
                        _fmtRp.format((a['totalFaktur'] as num?) ?? 0),
                        _fmtRp.format((a['nominal'] as num?) ?? 0),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
                'TOTAL DITERIMA: ${_fmtRp.format((d['nominal'] as num?) ?? 0)}',
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
                    pw.Text('( ${d['dibuatOleh']} )'),
                  ]),
                  pw.Column(children: [
                    pw.Text('Sales'),
                    pw.SizedBox(height: 36),
                    pw.Text(
                        '( ${'${d['salesNama']}'.isEmpty ? '................' : d['salesNama']} )'),
                  ]),
                  pw.Column(children: [
                    pw.Text('Customer'),
                    pw.SizedBox(height: 36),
                    pw.Text('( ................ )'),
                  ]),
                ]),
          ],
        ),
      ));
      await Printing.layoutPdf(
          onLayout: (_) => doc.save(), name: 'kwitansi-${d['nomor']}.pdf');
      // P10: register riwayat cetak (append-only) -- gagal log tidak
      // menggagalkan cetak (fire-and-forget).
      OutboxIs.kirimAtauAntre('si_print_log_create', {
        'jenis_dokumen': 'kwitansi_penerimaan',
        'referensi': '${d['nomor']}',
        'perangkat': 'flutter',
        'kode_unik': 'PRN-${DateTime.now().microsecondsSinceEpoch}',
      }).then((_) {}, onError: (_) {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal cetak kwitansi: $e')));
      }
    }
  }

  /// P10: reversal kwitansi posted (Pemilik/Admin; dokumen pembalik idempoten).
  Future<void> _reversal(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reversal Kwitansi ${r['nomor']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Kwitansi TIDAK dihapus — sistem menerbitkan dokumen pembalik '
              'dan saldo faktur dipulihkan.',
              style: TextStyle(fontSize: 12.5)),
          TextField(
              controller: ctrl,
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
    if (ya != true || ctrl.text.trim().isEmpty) return;
    try {
      // ONLINE-ONLY: pembalikan penagihan = "reversal" pada spec 13.3.
      await ApiClient.instance.aksi('si_collection_reverse', {
        'penerimaan_id': r['id'],
        'alasan': ctrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reversal diterbitkan.')));
      }
      _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  /// P10: siklus BG (giro) -- CAIR | TOLAK (TOLAK => reversal otomatis server).
  Future<void> _bgStatus(Map<String, dynamic> r, String status) async {
    try {
      await ApiClient.instance.aksi('si_collection_bg_status', {
        'id': r['id'],
        'status_bg': status,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'CAIR'
                ? 'BG ditandai CAIR.'
                : 'BG ditandai TOLAK — reversal otomatis diterbitkan.')));
      }
      _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
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
          Row(children: [
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
            const SizedBox(width: 8),
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
            const Spacer(),
            Text('Total: ${_fmtRp.format(_totalNominal)}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          AppDataTable(
            minWidth: 1000,
            emptyText: 'Belum ada penerimaan pada periode ini.',
            columns: const [
              AppTableColumn('No. Kwitansi', flex: 2),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Customer', flex: 3),
              AppTableColumn('Metode', flex: 1),
              AppTableColumn('Alokasi Faktur', flex: 3),
              AppTableColumn('Nominal', flex: 2, align: TextAlign.right),
              AppTableColumn('Kwitansi', flex: 1, align: TextAlign.center),
            ],
            rows: [
              for (final r in _data)
                AppTableRowData(cells: [
                  AppTableCell.text(
                      '${r['nomor']}'
                      '${'${r['statusDok']}' == 'DIBATALKAN' ? ' (DIBATALKAN)' : ''}'
                      '${'${r['statusDok']}' == 'REVERSAL' ? ' (REVERSAL)' : ''}'
                      '${'${r['statusBg']}'.isNotEmpty ? ' · BG ${r['statusBg']}' : ''}',
                      flex: 2,
                      maxLines: 2),
                  AppTableCell.text('${r['tanggal']}'.split('.').first,
                      flex: 2),
                  AppTableCell.text('${r['customerNama']}', flex: 3),
                  AppTableCell.text('${r['metode']}', flex: 1),
                  AppTableCell.text('${r['faktur']}', flex: 3, maxLines: 2),
                  AppTableCell.text(_fmtRp.format(r['nominal'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.print_outlined, size: 20),
                        tooltip: 'Cetak kwitansi (PDF)',
                        onPressed: () => _cetakKwitansi(r),
                      ),
                      if (!Sesi.instance.isSalesKeliling &&
                          '${r['statusDok']}' == 'AKTIF')
                        PopupMenuButton<String>(
                          tooltip: 'Aksi dokumen',
                          onSelected: (v) {
                            if (v == 'reversal') _reversal(r);
                            if (v == 'cair') _bgStatus(r, 'CAIR');
                            if (v == 'tolak') _bgStatus(r, 'TOLAK');
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'reversal',
                                child: Text('Reversal (batalkan)')),
                            if ('${r['metode']}' == 'GIRO' &&
                                ('${r['statusBg']}'.isEmpty ||
                                    '${r['statusBg']}' == 'DITERIMA')) ...[
                              const PopupMenuItem(
                                  value: 'cair', child: Text('BG Cair')),
                              const PopupMenuItem(
                                  value: 'tolak',
                                  child: Text('BG Tolak (auto-reversal)')),
                            ],
                          ],
                        ),
                    ]),
                  ),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 4: AGING CUSTOMER (SCR-37)
// =============================================================================

class _TabAgingCustomer extends StatefulWidget {
  const _TabAgingCustomer();

  @override
  State<_TabAgingCustomer> createState() => _TabAgingCustomerState();
}

class _TabAgingCustomerState extends State<_TabAgingCustomer> with JejakGalat {
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
      final hasil = await ApiClient.instance.aksi(
          'si_receivable_aging_customer', {'as_of': _fmtTgl.format(_asOf)});
      setStateIfMounted(() {
        _data = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _ringkasan =
            Map<String, dynamic>.from((hasil['ringkasan'] as Map?) ?? {});
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  Widget _kpi(String label, Object? nilai, Color warna) => SizedBox(
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
                    lastDate: DateTime(2035));
                if (t != null) {
                  setStateIfMounted(() => _asOf = t);
                  _muat();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('Per tanggal ${_fmtTgl.format(_asOf)}',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _kpi('Belum Jatuh Tempo', _ringkasan['BELUM'], AppColors.success),
            _kpi('1-30 Hari', _ringkasan['H1_30'], Colors.amber),
            _kpi('31-60 Hari', _ringkasan['H31_60'], Colors.orange),
            _kpi('61-90 Hari', _ringkasan['H61_90'], Colors.deepOrange),
            _kpi('> 90 Hari', _ringkasan['LEBIH_90'], AppColors.danger),
          ]),
          const SizedBox(height: 10),
          AppDataTable(
            minWidth: 1000,
            emptyText: 'Tidak ada piutang outstanding.',
            columns: const [
              AppTableColumn('Customer', flex: 3),
              AppTableColumn('Belum JT', flex: 2, align: TextAlign.right),
              AppTableColumn('1-30', flex: 2, align: TextAlign.right),
              AppTableColumn('31-60', flex: 2, align: TextAlign.right),
              AppTableColumn('61-90', flex: 2, align: TextAlign.right),
              AppTableColumn('> 90', flex: 2, align: TextAlign.right),
              AppTableColumn('Total', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final r in _data)
                AppTableRowData(cells: [
                  AppTableCell.text('${r['customerNama']}', flex: 3),
                  AppTableCell.text(_fmtRp.format(r['BELUM'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['H1_30'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['H31_60'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['H61_90'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['LEBIH_90'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['total'] ?? 0),
                      flex: 2,
                      align: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 5: AGING PER SALES (SCR-38)
// =============================================================================

class _TabAgingSales extends StatefulWidget {
  const _TabAgingSales();

  @override
  State<_TabAgingSales> createState() => _TabAgingSalesState();
}

class _TabAgingSalesState extends State<_TabAgingSales> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _ringkasan = {};

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
          await ApiClient.instance.aksi('si_receivable_aging_sales', {});
      setStateIfMounted(() {
        _data = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _ringkasan =
            Map<String, dynamic>.from((hasil['ringkasan'] as Map?) ?? {});
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
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(
              width: 220,
              child: AppKpiCard(
                  icon: Icons.assignment_outlined,
                  warna: AppColors.info,
                  nilai:
                      _fmtRp.format((_ringkasan['totalAssigned'] as num?) ?? 0),
                  label: 'Total Faktur Dibawa'),
            ),
            SizedBox(
              width: 220,
              child: AppKpiCard(
                  icon: Icons.payments_outlined,
                  warna: AppColors.success,
                  nilai:
                      _fmtRp.format((_ringkasan['totalTertagih'] as num?) ?? 0),
                  label: 'Total Tertagih'),
            ),
            SizedBox(
              width: 220,
              child: AppKpiCard(
                  icon: Icons.request_quote_outlined,
                  warna: AppColors.danger,
                  nilai: _fmtRp
                      .format((_ringkasan['totalOutstanding'] as num?) ?? 0),
                  label: 'Total Outstanding'),
            ),
          ]),
          const SizedBox(height: 10),
          AppDataTable(
            minWidth: 900,
            emptyText: 'Belum ada faktur piutang ber-sales.',
            columns: const [
              AppTableColumn('Sales', flex: 3),
              AppTableColumn('Jml Faktur', flex: 1, align: TextAlign.right),
              AppTableColumn('Lunas', flex: 1, align: TextAlign.right),
              AppTableColumn('Assigned', flex: 2, align: TextAlign.right),
              AppTableColumn('Tertagih', flex: 2, align: TextAlign.right),
              AppTableColumn('Outstanding', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final r in _data)
                AppTableRowData(cells: [
                  AppTableCell.text('${r['salesNama']}', flex: 3),
                  AppTableCell.text('${r['jumlahFaktur']}',
                      flex: 1, align: TextAlign.right),
                  AppTableCell.text('${r['jumlahLunas']}',
                      flex: 1, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['totalAssigned'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['totalTertagih'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['totalOutstanding'] ?? 0),
                      flex: 2,
                      align: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 6: LAPORAN PIUTANG (SCR-41/42) -- jenis eksplisit spt matriks paritas:
// Rekap Penjualan Barang (fungsi legacy layar 41) | Outstanding | Register Event
// (dua jenis terakhir tinggal pindah tab Piutang/Riwayat -- di sini rekap barang)
// =============================================================================

class _TabLaporanPiutang extends StatefulWidget {
  const _TabLaporanPiutang();

  @override
  State<_TabLaporanPiutang> createState() => _TabLaporanPiutangState();
}

class _TabLaporanPiutangState extends State<_TabLaporanPiutang>
    with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  double _totalQty = 0, _totalRp = 0;
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();
  String _urut = 'nama';
  String _q = '';

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
      final hasil = await ApiClient.instance.aksi('si_receivable_report', {
        'jenis': 'rekap_penjualan',
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
        'urut': _urut,
        if (_q.isNotEmpty) 'q': _q,
      });
      setStateIfMounted(() {
        _data = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totalQty = (hasil['totalQty'] as num?)?.toDouble() ?? 0;
        _totalRp = (hasil['totalRp'] as num?)?.toDouble() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  Future<void> _cetak() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Text(
            'REKAP PENJUALAN BARANG (Laporan Piutang — fungsi legacy layar 41)',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text(
            'Periode ${_fmtTgl.format(_dari)} s/d ${_fmtTgl.format(_sampai)} · urut ${_urut == 'qty' ? 'Fast Moving (QTY)' : 'Nama Barang'}'),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['#Brg', 'Nama Barang', 'QTY', 'Jumlah (Rp)'],
          data: [
            for (final r in _data)
              [
                '${r['produkId']}',
                '${r['namaProduk']}',
                '${r['qty']}',
                _fmtRp.format(r['jumlahRp'] ?? 0),
              ]
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text('TOTAL: $_totalQty unit · ${_fmtRp.format(_totalRp)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ));
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: 'rekap-penjualan-${_fmtTgl.format(_dari)}.pdf');
    OutboxIs.kirimAtauAntre('si_print_log_create', {
      'jenis_dokumen': 'rekap_penjualan_barang',
      'referensi': '${_fmtTgl.format(_dari)}_${_fmtTgl.format(_sampai)}',
      'parameter':
          'dari=${_fmtTgl.format(_dari)};sampai=${_fmtTgl.format(_sampai)};urut=$_urut;q=$_q',
      'perangkat': 'flutter',
      'kode_unik': 'PRN-${DateTime.now().microsecondsSinceEpoch}',
    }).then((_) {}, onError: (_) {});
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
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
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
                DropdownButton<String>(
                  value: _urut,
                  items: const [
                    DropdownMenuItem(
                        value: 'nama', child: Text('Urut Nama Barang')),
                    DropdownMenuItem(
                        value: 'qty', child: Text('Fast Moving (QTY)')),
                  ],
                  onChanged: (v) {
                    setStateIfMounted(() => _urut = v ?? 'nama');
                    _muat();
                  },
                ),
                SizedBox(
                  width: 220,
                  child: AppSearchField(
                    hintText: 'Cari nama barang...',
                    scanProduk: true,
                    onChanged: (v) {
                      _q = v.trim();
                      _muat();
                    },
                  ),
                ),
                IconButton(
                    onPressed: _cetak,
                    tooltip: 'Cetak PDF',
                    icon: const Icon(Icons.print_outlined)),
              ]),
          const SizedBox(height: 10),
          AppDataTable(
            minWidth: 700,
            emptyText: 'Tidak ada penjualan terfakturkan pada periode ini.',
            columns: const [
              AppTableColumn('#Brg', flex: 1),
              AppTableColumn('Nama Barang', flex: 4),
              AppTableColumn('QTY', flex: 1, align: TextAlign.right),
              AppTableColumn('Jumlah (Rp)', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final r in _data)
                AppTableRowData(cells: [
                  AppTableCell.text('${r['produkId']}', flex: 1),
                  AppTableCell.text('${r['namaProduk']}', flex: 4),
                  AppTableCell.text('${r['qty']}',
                      flex: 1, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['jumlahRp'] ?? 0),
                      flex: 2, align: TextAlign.right),
                ]),
            ],
          ),
          const SizedBox(height: 6),
          Text('TOTAL: $_totalQty unit · ${_fmtRp.format(_totalRp)}',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              'Outstanding Piutang = tab "Piutang"; Register Event = tab "Riwayat & Kwitansi" (jenis laporan dipilih eksplisit, tidak dicampur).',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Util bersama
// -----------------------------------------------------------------------------

class _DialogCariCustomerPiutang extends StatefulWidget {
  const _DialogCariCustomerPiutang();
  @override
  State<_DialogCariCustomerPiutang> createState() =>
      _DialogCariCustomerPiutangState();
}

class _DialogCariCustomerPiutangState
    extends State<_DialogCariCustomerPiutang> {
  List<Map<String, dynamic>> _rows = [];
  bool _memuat = false;

  Future<void> _cari(String q) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi('si_customer_list', {
        if (q.isNotEmpty) 'keyword': q,
        'aktif': 'aktif',
        'page': 1,
        'page_size': 20,
      });
      setStateIfMounted(() => _rows = ((hasil['rows'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } on ApiException catch (e) {
      // Offline: jatuh ke cache customer layar master ('master:si_customer').
      // Kwitansi offline (si_collection_create ber-outbox) tidak boleh
      // terblokir hanya karena pemilih customer tak bisa fetch.
      if (e.offline) {
        try {
          final tersimpan =
              await CoreDb.instance.ambilCacheReferensi('master:si_customer');
          if (tersimpan != null) {
            final kecil = q.trim().toLowerCase();
            final semua = (jsonDecode(tersimpan) as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .where((r) =>
                    kecil.isEmpty ||
                    '${r['nama'] ?? ''} ${r['kode'] ?? ''}'
                        .toLowerCase()
                        .contains(kecil))
                .take(20)
                .toList();
            setStateIfMounted(() => _rows = semua);
          }
        } catch (_) {
          // Cache rusak/kosong -- biarkan hasil lama.
        }
      }
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Customer'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          AppSearchField(
            hintText: 'Cari kode/nama/wilayah...',
            autofocus: true,
            onChanged: _cari,
          ),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  dense: true,
                  title: Text('${r['kode']} — ${r['nama']}'),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ]),
          ),
        ]),
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
