import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../services/dynamic_report.dart';
import '../../services/master_offline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

/// Tab "Saldo Voucher" -- daftar SALDO AKHIR voucher/tabungan tiap anggota
/// (pegawai) pada rentang tanggal terpilih. Mengklik satu anggota membuka
/// riwayat transaksi voucher miliknya.
///
/// Sengaja TIDAK menambah aksi server baru: memakai `mutasi_tabungan_list`
/// yang sudah mengembalikan rekap per anggota sekaligus baris mutasinya,
/// sehingga saldo di halaman ini dijamin identik dengan tab Mutasi Voucher --
/// satu sumber angka, bukan dua rumus yang bisa berbeda.
///
/// Unduhan memakai DynamicReportDesigner yang sama dengan Laporan Transaksi
/// (Preview, Atur Model, PDF, Excel, Word) sehingga kolom dan judulnya dapat
/// dikustomisasi pengguna.
class AnggotaTabSaldoVoucher extends StatefulWidget {
  const AnggotaTabSaldoVoucher({super.key});

  @override
  State<AnggotaTabSaldoVoucher> createState() => _AnggotaTabSaldoVoucherState();
}

class _AnggotaTabSaldoVoucherState extends State<AnggotaTabSaldoVoucher> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _fmtTgl = DateFormat('yyyy-MM-dd');
  static final _fmtTglTampil = DateFormat('dd/MM/yy');

  late DateTime _dari;
  late DateTime _sampai;
  bool _memuat = true;
  String? _galat;
  String _cari = '';
  bool _menyiapkanLaporan = false;
  DynamicReportModel? _modelLaporan;

  List<Map<String, dynamic>> _mutasi = [];

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _dari = DateTime(kini.year, kini.month, 1);
    _sampai = DateTime(kini.year, kini.month, kini.day);
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'mutasi_tabungan_list',
        {'dari': _fmtTgl.format(_dari), 'sampai': _fmtTgl.format(_sampai)},
        'master:saldo_voucher:${_fmtTgl.format(_dari)}-${_fmtTgl.format(_sampai)}',
        responsLengkap: true,
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat = '${res['description'] ?? 'Gagal memuat saldo voucher.'}';
              _memuat = false;
            });
            return;
          }
          setStateIfMounted(() {
            _mutasi = ((res['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  double _angka(dynamic v) => (v as num?)?.toDouble() ?? 0;

  /// Rekap per anggota: masuk/keluar dijumlahkan, saldo akhir diambil dari
  /// saldo berjalan baris terakhir milik anggota tsb.
  List<Map<String, dynamic>> get _saldoPerAnggota {
    final peta = <String, Map<String, dynamic>>{};
    for (final m in _mutasi) {
      final kunci = '${m['idAnggota'] ?? m['namaAnggota'] ?? '-'}';
      final entri = peta.putIfAbsent(
          kunci,
          () => <String, dynamic>{
                'idAnggota': m['idAnggota'],
                'namaAnggota': '${m['namaAnggota'] ?? '-'}',
                'saldoAwal': _angka(m['saldoAwal']),
                'masuk': 0.0,
                'keluar': 0.0,
                'saldoAkhir': 0.0,
                'jumlahTransaksi': 0,
              });
      entri['masuk'] = (entri['masuk'] as double) + _angka(m['masuk']);
      entri['keluar'] = (entri['keluar'] as double) + _angka(m['keluar']);
      entri['saldoAkhir'] = _angka(m['saldoPerPenabung']);
      entri['jumlahTransaksi'] = (entri['jumlahTransaksi'] as int) + 1;
    }
    final daftar = peta.values.toList();
    final kunciCari = _cari.trim().toLowerCase();
    final hasil = kunciCari.isEmpty
        ? daftar
        : daftar
            .where(
                (r) => '${r['namaAnggota']}'.toLowerCase().contains(kunciCari))
            .toList();
    hasil.sort((a, b) =>
        (b['saldoAkhir'] as double).compareTo(a['saldoAkhir'] as double));
    return hasil;
  }

  DynamicReportData _dataLaporan() => DynamicReportData(
        title: 'Saldo Voucher Anggota',
        subtitle:
            'Periode ${_fmtTglTampil.format(_dari)} s.d. ${_fmtTglTampil.format(_sampai)}',
        columns: const [
          DynamicReportColumn('namaAnggota', 'Anggota'),
          DynamicReportColumn('saldoAwal', 'Saldo Awal', numeric: true),
          DynamicReportColumn('masuk', 'Masuk', numeric: true),
          DynamicReportColumn('keluar', 'Keluar', numeric: true),
          DynamicReportColumn('saldoAkhir', 'Saldo Akhir', numeric: true),
          DynamicReportColumn('jumlahTransaksi', 'Jml Transaksi',
              numeric: true),
        ],
        rows: _saldoPerAnggota,
      );

  Future<void> _aturAtauPreview({required bool preview}) async {
    setStateIfMounted(() => _menyiapkanLaporan = true);
    try {
      final model = await DynamicReportDesigner.show(context,
          data: _dataLaporan(),
          initial: _modelLaporan,
          initialTab: preview ? 0 : 1);
      if (model != null) setStateIfMounted(() => _modelLaporan = model);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyiapkan laporan: $e')));
      }
    } finally {
      setStateIfMounted(() => _menyiapkanLaporan = false);
    }
  }

  Future<void> _ekspor(String format) async {
    setStateIfMounted(() => _menyiapkanLaporan = true);
    try {
      final data = _dataLaporan();
      final model = _modelLaporan ?? DynamicReportModel.fromData(data);
      _modelLaporan = model;
      const slug = 'saldo-voucher-anggota';
      if (format == 'pdf') {
        await DynamicReportDesigner.exportPdf(data, model, '$slug.pdf');
      } else if (format == 'excel') {
        if (!mounted) return;
        await DynamicReportDesigner.exportExcel(
            context, data, model, '$slug.xlsx');
      } else {
        if (!mounted) return;
        await DynamicReportDesigner.exportWord(
            context, data, model, '$slug.doc');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    } finally {
      setStateIfMounted(() => _menyiapkanLaporan = false);
    }
  }

  Future<void> _pilihRentang() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dari, end: _sampai),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() {
      _dari = hasil.start;
      _sampai = hasil.end;
    });
    await _muat();
  }

  /// Riwayat transaksi voucher SATU anggota -- diambil dari baris mutasi yang
  /// sudah dimuat, jadi tidak menembak server lagi saat baris diklik.
  void _bukaRiwayat(Map<String, dynamic> anggota) {
    final id = anggota['idAnggota'];
    final nama = '${anggota['namaAnggota'] ?? '-'}';
    final riwayat = _mutasi
        .where((m) => id == null
            ? '${m['namaAnggota']}' == nama
            : '${m['idAnggota']}' == '$id')
        .toList()
      ..sort((a, b) => '${a['waktu']}'.compareTo('${b['waktu']}'));
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Riwayat Voucher: $nama'),
        content: SizedBox(
          width: 760,
          height: 440,
          child: riwayat.isEmpty
              ? const Center(
                  child: Text('Belum ada transaksi pada rentang ini.'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        'Saldo akhir ${_fmtRp.format(anggota['saldoAkhir'] ?? 0)}  -  ${riwayat.length} transaksi',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(label: Text('Waktu')),
                          DataColumn(label: Text('Jenis')),
                          DataColumn(label: Text('Keterangan')),
                          DataColumn(label: Text('Masuk'), numeric: true),
                          DataColumn(label: Text('Keluar'), numeric: true),
                          DataColumn(label: Text('Saldo'), numeric: true),
                        ],
                        rows: [
                          for (final m in riwayat)
                            DataRow(cells: [
                              DataCell(Text('${m['waktu'] ?? '-'}')),
                              DataCell(Text('${m['jenisMutasi'] ?? '-'}')),
                              DataCell(SizedBox(
                                  width: 220,
                                  child: Text('${m['keterangan'] ?? '-'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis))),
                              DataCell(Text(_fmtRp.format(_angka(m['masuk'])))),
                              DataCell(
                                  Text(_fmtRp.format(_angka(m['keluar'])))),
                              DataCell(Text(_fmtRp
                                  .format(_angka(m['saldoPerPenabung'])))),
                            ])
                        ],
                      ),
                    ),
                  ),
                ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
        ],
      ),
    );
  }

  /// Buka dialog penyesuaian saldo. [baris] boleh diisi bila dipanggil dari satu baris
  /// anggota, sehingga membernya langsung terpilih.
  Future<void> _bukaPenyesuaian([Map<String, dynamic>? baris]) async {
    final berubah = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogPenyesuaianSaldo(
        idAnggota: baris == null ? null : baris['idAnggota'],
        namaAnggota: baris == null ? null : '${baris['namaAnggota'] ?? ''}',
        daftarAnggota: _saldoPerAnggota,
      ),
    );
    if (berubah == true) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final daftar = _saldoPerAnggota;
    final totalSaldo =
        daftar.fold<double>(0, (s, r) => s + (r['saldoAkhir'] as double));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _memuat ? null : _pilihRentang,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                  '${_fmtTglTampil.format(_dari)} - ${_fmtTglTampil.format(_sampai)}')),
          SizedBox(
            width: 240,
            child: AppSearchField(
              hintText: 'Cari anggota',
              debounce: Duration.zero,
              onChanged: (v) => setStateIfMounted(() => _cari = v),
            ),
          ),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan
                  ? null
                  : () => _aturAtauPreview(preview: true),
              icon: const Icon(Icons.preview_outlined, size: 18),
              label: const Text('Preview')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan
                  ? null
                  : () => _aturAtauPreview(preview: false),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Atur Model')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan ? null : () => _ekspor('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan ? null : () => _ekspor('excel'),
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: const Text('Excel')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan ? null : () => _ekspor('word'),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Word')),
          // Penyesuaian Saldo = "stok opname" untuk saldo voucher. Hanya tampil bagi
          // pengguna yang boleh menambah & mengubah topup/deposit; server menegakkan
          // gerbang yang sama (Tbmrole.bolehEntryTopup), jadi ini murni penyaring tampilan.
          if (Sesi.instance.bolehEntryTopup)
            FilledButton.icon(
                onPressed: _memuat ? null : () => _bukaPenyesuaian(),
                icon: const Icon(Icons.rule, size: 18),
                label: const Text('Penyesuaian Saldo')),
          IconButton(
              onPressed: _memuat ? null : _muat,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (!_memuat && _galat == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Text('${daftar.length} anggota',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('Total saldo akhir: ${_fmtRp.format(totalSaldo)}',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
        ),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ))
                : daftar.isEmpty
                    ? const Center(
                        child: Text(
                            'Belum ada saldo voucher pada rentang tanggal ini.'))
                    : AppDataTable(
                        minWidth: 820,
                        emptyText: 'Tidak ada data pada rentang ini.',
                        columns: const [
                          AppTableColumn('Anggota', flex: 4),
                          AppTableColumn('Saldo Awal',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Masuk',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Keluar',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Saldo Akhir',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Aksi', width: 70),
                        ],
                        rows: daftar
                            .map((r) => AppTableRowData(
                                  onTap: () => _bukaRiwayat(r),
                                  cells: [
                                    AppTableCell.text('${r['namaAnggota']}',
                                        flex: 4),
                                    AppTableCell.text(
                                        _fmtRp.format(r['saldoAwal'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right),
                                    AppTableCell.text(
                                        _fmtRp.format(r['masuk'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right),
                                    AppTableCell.text(
                                        _fmtRp.format(r['keluar'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right),
                                    AppTableCell.text(
                                        _fmtRp.format(r['saldoAkhir'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    AppTableCell(
                                      width: 70,
                                      align: TextAlign.center,
                                      child: IconButton(
                                          tooltip: 'Lihat riwayat transaksi',
                                          icon: const Icon(
                                              Icons.receipt_long_outlined,
                                              size: 18),
                                          onPressed: () => _bukaRiwayat(r)),
                                    ),
                                  ],
                                ))
                            .toList(),
                      ),
      ),
    ]);
  }
}

/// Dialog **Penyesuaian Saldo** — opname saldo voucher/deposit member.
///
/// Alurnya sengaja dibuat sama dengan Stok Opname barang: pilih objeknya, sistem menampilkan
/// nilai menurut catatan, petugas mengisi nilai yang seharusnya, selisih dihitung otomatis dan
/// wajib diberi alasan. Bedanya hanya cara koreksi diterapkan — saldo member dihitung dari
/// mutasi, jadi server membuat satu baris deposit senilai selisihnya (positif menambah, negatif
/// mengurangi) supaya riwayat mutasi tetap utuh.
///
/// Saldo sistem SELALU dibaca ulang dari server saat member dipilih dan diperiksa lagi saat
/// menyimpan, sehingga angka di layar yang sudah basi tidak akan ikut terpakai.
class _DialogPenyesuaianSaldo extends StatefulWidget {
  const _DialogPenyesuaianSaldo({
    this.idAnggota,
    this.namaAnggota,
    required this.daftarAnggota,
  });

  final Object? idAnggota;
  final String? namaAnggota;
  final List<Map<String, dynamic>> daftarAnggota;

  @override
  State<_DialogPenyesuaianSaldo> createState() =>
      _DialogPenyesuaianSaldoState();
}

class _DialogPenyesuaianSaldoState extends State<_DialogPenyesuaianSaldo> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  final _saldoFisik = TextEditingController();
  final _keterangan = TextEditingController();
  final _cariAnggota = TextEditingController();

  Object? _idAnggota;
  String _namaAnggota = '';
  double? _saldoSistem;
  bool _memuatSaldo = false;
  bool _menyimpan = false;
  String? _pesan;
  List<Map<String, dynamic>> _riwayat = [];

  @override
  void initState() {
    super.initState();
    _idAnggota = widget.idAnggota;
    _namaAnggota = widget.namaAnggota ?? '';
    if (_idAnggota != null) _cekSaldo();
    _muatRiwayat();
  }

  @override
  void dispose() {
    _saldoFisik.dispose();
    _keterangan.dispose();
    _cariAnggota.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('penyesuaian_saldo_list', {'limit': 25});
      if (!mounted) return;
      setStateIfMounted(() => _riwayat =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // Riwayat hanya pelengkap; kegagalannya tidak boleh menghalangi penyesuaian.
    }
  }

  Future<void> _cekSaldo() async {
    if (_idAnggota == null) return;
    setStateIfMounted(() {
      _memuatSaldo = true;
      _pesan = null;
    });
    try {
      final hasil = await ApiClient.instance
          .aksi('penyesuaian_saldo_cek', {'id_member': '$_idAnggota'});
      if (!mounted) return;
      setStateIfMounted(() {
        _saldoSistem = ((hasil['saldoSistem'] as num?) ?? 0).toDouble();
        final nama = '${hasil['namaMember'] ?? ''}';
        if (nama.isNotEmpty) _namaAnggota = nama;
        _memuatSaldo = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _pesan = 'Gagal membaca saldo: $e';
        _memuatSaldo = false;
      });
    }
  }

  double get _fisik =>
      double.tryParse(
          _saldoFisik.text.replaceAll('.', '').replaceAll(',', '.')) ??
      0;
  double get _selisih => _saldoSistem == null ? 0 : _fisik - _saldoSistem!;
  bool get _siap =>
      _idAnggota != null &&
      _saldoSistem != null &&
      _saldoFisik.text.trim().isNotEmpty &&
      _selisih.abs() >= 0.005 &&
      _keterangan.text.trim().isNotEmpty;

  Future<void> _simpan() async {
    setStateIfMounted(() {
      _menyimpan = true;
      _pesan = null;
    });
    try {
      // LOKAL DULU. Saat offline hasilnya {'status':'success','offline':true},
      // jadi pemeriksaan status di bawah TIDAK boleh lagi menuntut '00' -- kalau
      // dituntut, penyesuaian yang sah akan dilaporkan "ditolak server".
      final hasil = await MasterOffline.simpanAtauAntre(
        'penyesuaian_saldo_simpan',
        {
          'id_member': '$_idAnggota',
          'saldo_fisik': '$_fisik',
          'keterangan': _keterangan.text.trim(),
        },
        kunci: 'penyesuaian_saldo:$_idAnggota',
      );
      if (!mounted) return;
      final offline = hasil['offline'] == true;
      final st = '${hasil['status']}';
      if (!offline && st != '00' && st != 'success') {
        setStateIfMounted(() => _pesan =
            '${hasil['description'] ?? 'Penyesuaian ditolak server.'}');
        return;
      }
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(offline
              ? 'Penyesuaian tersimpan di perangkat, akan dikirim otomatis.'
              : '${hasil['description'] ?? 'Saldo disesuaikan.'}')));
    } catch (e) {
      setStateIfMounted(() => _pesan = 'Gagal menyimpan: $e');
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kunci = _cariAnggota.text.trim().toLowerCase();
    final pilihan = kunci.isEmpty
        ? widget.daftarAnggota.take(30).toList()
        : widget.daftarAnggota
            .where((r) => '${r['namaAnggota']}'.toLowerCase().contains(kunci))
            .take(30)
            .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(
                  child: Text('Penyesuaian Saldo (Opname Saldo Voucher)',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(
                  onPressed: _menyimpan
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Isi saldo yang SEHARUSNYA menurut hasil pemeriksaan. Sistem akan membuat satu '
                'mutasi senilai selisihnya, bukan menimpa saldo, sehingga riwayat mutasi tetap utuh.'),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 4,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSearchField(
                        controller: _cariAnggota,
                        hintText: 'Cari anggota',
                        debounce: Duration.zero,
                        onChanged: (_) => setStateIfMounted(() {}),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 210,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListView.builder(
                            itemCount: pilihan.length,
                            itemBuilder: (_, i) {
                              final r = pilihan[i];
                              final terpilih =
                                  '${r['idAnggota']}' == '$_idAnggota';
                              return ListTile(
                                dense: true,
                                selected: terpilih,
                                title: Text('${r['namaAnggota'] ?? ''}',
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    'Saldo tampil: ${_fmtRp.format(r['saldoAkhir'] ?? 0)}',
                                    style: const TextStyle(fontSize: 11)),
                                onTap: () {
                                  setStateIfMounted(() {
                                    _idAnggota = r['idAnggota'];
                                    _namaAnggota = '${r['namaAnggota'] ?? ''}';
                                    _saldoSistem = null;
                                    _saldoFisik.clear();
                                  });
                                  _cekSaldo();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppInfoBanner(
                        icon: Icons.person_outline,
                        color: AppColors.primary,
                        text: _idAnggota == null
                            ? 'Pilih anggota di sebelah kiri.'
                            : 'Anggota: $_namaAnggota',
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Expanded(child: Text('Saldo menurut sistem')),
                        _memuatSaldo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(
                                _saldoSistem == null
                                    ? '-'
                                    : _fmtRp.format(_saldoSistem),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _saldoFisik,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                            labelText: 'Saldo seharusnya *',
                            isDense: true,
                            border: OutlineInputBorder()),
                        onChanged: (_) => setStateIfMounted(() {}),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Expanded(child: Text('Selisih')),
                        Text(
                          _saldoSistem == null ? '-' : _fmtRp.format(_selisih),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _selisih < 0
                                  ? AppColors.danger
                                  : AppColors.success),
                        ),
                      ]),
                      if (_saldoSistem != null && _selisih.abs() >= 0.005)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              _selisih > 0
                                  ? 'Saldo anggota akan DITAMBAH sebesar selisih ini.'
                                  : 'Saldo anggota akan DIKURANGI sebesar selisih ini.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _keterangan,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Alasan penyesuaian *',
                            hintText: 'mis. koreksi topup ganda 19 Agustus',
                            isDense: true,
                            border: OutlineInputBorder()),
                        onChanged: (_) => setStateIfMounted(() {}),
                      ),
                      if (_pesan != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_pesan!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                    ]),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Riwayat penyesuaian terakhir',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Expanded(
              child: _riwayat.isEmpty
                  ? const Center(child: Text('Belum ada penyesuaian saldo.'))
                  : ListView.separated(
                      itemCount: _riwayat.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _riwayat[i];
                        final selisih =
                            ((r['selisih'] as num?) ?? 0).toDouble();
                        return ListTile(
                          dense: true,
                          title: Text(
                              '${r['namaMember'] ?? '-'} — ${_fmtRp.format(selisih)}',
                              style: TextStyle(
                                  color: selisih < 0
                                      ? AppColors.danger
                                      : AppColors.success)),
                          subtitle: Text(
                              '${r['waktu'] ?? ''} • ${_fmtRp.format(r['saldoSistem'] ?? 0)} '
                              '→ ${_fmtRp.format(r['saldoFisik'] ?? 0)} • ${r['keterangan'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: _menyimpan
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Tutup')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _siap && !_menyimpan ? _simpan : null,
                icon: _menyimpan
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan Penyesuaian'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
