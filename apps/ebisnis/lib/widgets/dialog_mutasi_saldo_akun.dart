import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../screens/pengadaan_cetak_util.dart';
import '../services/simpan_berkas_helper.dart';
import '../theme/app_colors.dart';
import 'app_components.dart';
import 'safe_state.dart';

/// Ukuran halaman buku besar mutasi saldo akun sesuai spesifikasi bisnis (15 data/halaman).
const int kUkuranHalamanMutasiSaldoAkun = 15;

/// Membuka jendela popup interaktif **Rincian Mutasi & Saldo Akun (Buku Besar)**
/// ketika angka pada kolom `SALDO` di layar Kode Akun diklik.
///
/// Menampilkan:
/// 1. **Saldo Awal** sebelum tanggal mulai periode,
/// 2. **Mutasi Debet & Mutasi Kredit** selama periode berjalan beserta **Saldo Berjalan** per baris,
/// 3. **Saldo Akhir** pada akhir periode,
/// 4. Navigasi **paging 15 data per halaman**,
/// 5. Tombol **Cetak PDF** (membuka pratinjau cetak resmi) dan **Download Excel (.xlsx)**.
Future<void> bukaDialogMutasiSaldoAkun(
  BuildContext context,
  Map<String, dynamic> akun, {
  Future<Map<String, dynamic>> Function(String action, Map<String, dynamic> body)?
      pemanggilApi,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => DialogMutasiSaldoAkun(
      akun: akun,
      pemanggilApi: pemanggilApi,
    ),
  );
}

class DialogMutasiSaldoAkun extends StatefulWidget {
  final Map<String, dynamic> akun;
  final Future<Map<String, dynamic>> Function(
      String action, Map<String, dynamic> body)? pemanggilApi;

  const DialogMutasiSaldoAkun({
    super.key,
    required this.akun,
    this.pemanggilApi,
  });

  @override
  State<DialogMutasiSaldoAkun> createState() => _DialogMutasiSaldoAkunState();
}

class _DialogMutasiSaldoAkunState extends State<DialogMutasiSaldoAkun> {
  static final NumberFormat _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final DateFormat _fmtIso = DateFormat('yyyy-MM-dd');
  static final DateFormat _fmtTampil = DateFormat('dd MMM yyyy', 'id_ID');

  late DateTime _tglMulai;
  late DateTime _tglSampai;
  late bool _punyaAnak;
  late bool _termasukAnak;
  final TextEditingController _cariCtrl = TextEditingController();

  bool _memuat = true;
  bool _sedangEkspor = false;
  String? _galat;

  int _halaman = 1;
  int _totalHalaman = 1;
  int _totalData = 0;

  double _saldoAwal = 0;
  double _mutasiDebet = 0;
  double _mutasiKredit = 0;
  double _saldoAkhir = 0;
  String _tglMulaiTampil = '-';
  String _tglSampaiTampil = '-';
  String _akunKode = '';
  String _akunNama = '';
  String _posisi = 'Debet';
  String _grupAkun = '';
  List<Map<String, dynamic>> _baris = const [];

  @override
  void initState() {
    super.initState();
    final skrg = DateTime.now();
    _tglSampai = DateTime(skrg.year, skrg.month, skrg.day);
    _tglMulai = DateTime(skrg.year, skrg.month, 1);
    _punyaAnak = widget.akun['punyaAnak'] == true ||
        widget.akun['_punyaAnak'] == true;
    _termasukAnak = _punyaAnak;
    _akunKode = '${widget.akun['kode'] ?? ''}';
    _akunNama = '${widget.akun['nama'] ?? ''}';
    _posisi = '${widget.akun['posisi'] ?? 'Debet'}';
    _grupAkun = '${widget.akun['grupAkun'] ?? ''}';
    _muatHalaman(resetKeSatu: true);
  }

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }

  int get _idAkun => (widget.akun['id'] as num?)?.toInt() ?? 0;

  Future<Map<String, dynamic>> _kirimAksi(
      String action, Map<String, dynamic> body) {
    final fn = widget.pemanggilApi;
    if (fn != null) return fn(action, body);
    return ApiClient.instance.aksi(action, body);
  }

  Future<void> _muatHalaman({bool resetKeSatu = false}) async {
    if (_idAkun <= 0) {
      setStateIfMounted(() {
        _memuat = false;
        _galat =
            'Akun ini belum tersinkron ke server (masih antrean lokal) sehingga belum memiliki mutasi buku besar.';
      });
      return;
    }
    if (resetKeSatu) _halaman = 1;
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final res = await _kirimAksi('kode_akun_mutasi', {
        'akunId': _idAkun,
        'tglMulai': _fmtIso.format(_tglMulai),
        'tglSampai': _fmtIso.format(_tglSampai),
        'cari': _cariCtrl.text.trim(),
        'termasukAnak': _termasukAnak,
        'page': _halaman,
        'pageSize': kUkuranHalamanMutasiSaldoAkun,
      });
      if (!mounted) return;
      if (res['status'] != null &&
          res['status'] != '00' &&
          res['status'] != 'success') {
        throw Exception(
            '${res['description'] ?? res['message'] ?? 'Gagal memuat rincian mutasi saldo akun.'}');
      }
      setStateIfMounted(() {
        _akunKode = '${res['akunKode'] ?? _akunKode}';
        _akunNama = '${res['akunNama'] ?? _akunNama}';
        _posisi = '${res['posisi'] ?? _posisi}';
        _grupAkun = '${res['grupAkun'] ?? _grupAkun}';
        _punyaAnak = res['punyaAnak'] == true;
        _termasukAnak = res['termasukAnak'] == true;

        final serverMulai = DateTime.tryParse('${res['tglMulai'] ?? ''}');
        final serverSampai = DateTime.tryParse('${res['tglSampai'] ?? ''}');
        if (serverMulai != null) _tglMulai = serverMulai;
        if (serverSampai != null) _tglSampai = serverSampai;

        _tglMulaiTampil = '${res['tglMulaiTampil'] ?? _fmtTampil.format(_tglMulai)}';
        _tglSampaiTampil =
            '${res['tglSampaiTampil'] ?? _fmtTampil.format(_tglSampai)}';
        _saldoAwal = (res['saldoAwal'] as num?)?.toDouble() ?? 0;
        _mutasiDebet = (res['mutasiDebet'] as num?)?.toDouble() ?? 0;
        _mutasiKredit = (res['mutasiKredit'] as num?)?.toDouble() ?? 0;
        _saldoAkhir = (res['saldoAkhir'] as num?)?.toDouble() ?? 0;
        _halaman = (res['page'] as num?)?.toInt() ?? _halaman;
        _totalHalaman = (res['totalPages'] as num?)?.toInt() ?? 1;
        if (_totalHalaman < 1) _totalHalaman = 1;
        _totalData = (res['total'] as num?)?.toInt() ?? 0;
        _baris = ((res['data'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = mulai ? _tglMulai : _tglSampai;
    final hasil = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: mulai ? 'Pilih Tanggal Mulai' : 'Pilih Tanggal Sampai',
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() {
      if (mulai) {
        _tglMulai = hasil;
        if (_tglMulai.isAfter(_tglSampai)) _tglSampai = _tglMulai;
      } else {
        _tglSampai = hasil;
        if (_tglSampai.isBefore(_tglMulai)) _tglMulai = _tglSampai;
      }
    });
    await _muatHalaman(resetKeSatu: true);
  }

  Future<void> _cetakPdf() async {
    if (_sedangEkspor || _idAkun <= 0) return;
    setStateIfMounted(() => _sedangEkspor = true);
    try {
      final res = await _kirimAksi('kode_akun_mutasi_pdf', {
        'akunId': _idAkun,
        'tglMulai': _fmtIso.format(_tglMulai),
        'tglSampai': _fmtIso.format(_tglSampai),
        'cari': _cariCtrl.text.trim(),
        'termasukAnak': _termasukAnak,
      });
      if (!mounted) return;
      if (res['status'] != '00' && res['status'] != 'success') {
        throw Exception(
            '${res['description'] ?? res['message'] ?? 'Gagal membuat PDF mutasi akun.'}');
      }
      final b64 = '${res['fileBase64'] ?? ''}';
      if (b64.isEmpty) {
        throw Exception('Berkas PDF kosong dari server.');
      }
      final bytes = Uint8List.fromList(base64Decode(b64));
      final nama =
          '${res['fileName'] ?? 'Mutasi_Akun_${_akunKode.isEmpty ? _idAkun : _akunKode}.pdf'}';
      await tampilkanPratinjauPdf(
        context,
        judul: nama.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
        isi: bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mencetak PDF: $e')));
      }
    } finally {
      setStateIfMounted(() => _sedangEkspor = false);
    }
  }

  Future<void> _unduhExcel() async {
    if (_sedangEkspor || _idAkun <= 0) return;
    setStateIfMounted(() => _sedangEkspor = true);
    try {
      final res = await _kirimAksi('kode_akun_mutasi_excel', {
        'akunId': _idAkun,
        'tglMulai': _fmtIso.format(_tglMulai),
        'tglSampai': _fmtIso.format(_tglSampai),
        'cari': _cariCtrl.text.trim(),
        'termasukAnak': _termasukAnak,
      });
      if (!mounted) return;
      if (res['status'] != '00' && res['status'] != 'success') {
        throw Exception(
            '${res['description'] ?? res['message'] ?? 'Gagal menyiapkan Excel mutasi akun.'}');
      }
      final b64 = '${res['fileBase64'] ?? ''}';
      if (b64.isEmpty) {
        throw Exception('Berkas Excel kosong dari server.');
      }
      final bytes = Uint8List.fromList(base64Decode(b64));
      final namaDefault =
          '${res['fileName'] ?? 'Mutasi_Akun_${_akunKode.isEmpty ? _idAkun : _akunKode}.xlsx'}';
      final simpanPath = await SimpanBerkasHelper.simpanBytes(
        dialogTitle: 'Download Excel Mutasi Saldo Akun',
        fileName: namaDefault,
        bytes: bytes,
        allowedExtensions: const ['xlsx'],
      );
      if (simpanPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel berhasil disimpan: $simpanPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunduh Excel: $e')));
      }
    } finally {
      setStateIfMounted(() => _sedangEkspor = false);
    }
  }

  Widget _kartuRingkasan({
    required String judul,
    required double nilai,
    required IconData ikon,
    required Color warna,
  }) {
    final negatif = nilai < -0.005;
    final warnaTeks = negatif ? AppColors.danger : AppColors.textPrimaryOf(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 195),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.latarLembut(warna),
              shape: BoxShape.circle,
            ),
            child: Icon(ikon, color: warna, size: 19),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  judul,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _fmtRp.format(nilai),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: warnaTeks,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bangunTabelMutasi() {
    final gabung = _termasukAnak && _punyaAnak;
    final kolom = <AppTableColumn>[
      const AppTableColumn('No', width: 58, align: TextAlign.center),
      const AppTableColumn('Tanggal', width: 106),
      const AppTableColumn('No. Bukti', flex: 2),
      if (gabung) const AppTableColumn('Sub-Akun', flex: 3),
      const AppTableColumn('Keterangan', flex: 4),
      const AppTableColumn('Debet', flex: 2, align: TextAlign.right),
      const AppTableColumn('Kredit', flex: 2, align: TextAlign.right),
      const AppTableColumn('Saldo', flex: 2, align: TextAlign.right),
    ];

    final semuaBaris = <AppTableRowData>[
      // Baris 1: SALDO AWAL
      AppTableRowData(
        cells: [
          AppTableCell.text('-', width: 58, align: TextAlign.center),
          AppTableCell.text(_tglMulaiTampil, width: 106),
          AppTableCell(
            flex: 2,
            child: Text(
              'SALDO AWAL',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: AppColors.primary,
              ),
            ),
          ),
          if (gabung) AppTableCell.text('-', flex: 3),
          AppTableCell(
            flex: 4,
            child: Text(
              'Saldo Awal sebelum $_tglMulaiTampil',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          AppTableCell.text('-', flex: 2, align: TextAlign.right),
          AppTableCell.text('-', flex: 2, align: TextAlign.right),
          AppTableCell(
            flex: 2,
            align: TextAlign.right,
            child: Text(
              _fmtRp.format(_saldoAwal),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: _saldoAwal < 0
                    ? AppColors.danger
                    : AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    ];

    if (_baris.isEmpty) {
      semuaBaris.add(
        AppTableRowData(
          cells: [
            AppTableCell.text('-', width: 58, align: TextAlign.center),
            AppTableCell.text('-', width: 106),
            AppTableCell.text('-', flex: 2),
            if (gabung) AppTableCell.text('-', flex: 3),
            AppTableCell(
              flex: 4,
              child: Text(
                'Tidak ada transaksi mutasi pada periode ini.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 12.5,
                ),
              ),
            ),
            AppTableCell.text('Rp 0', flex: 2, align: TextAlign.right),
            AppTableCell.text('Rp 0', flex: 2, align: TextAlign.right),
            AppTableCell.text(_fmtRp.format(_saldoAkhir),
                flex: 2, align: TextAlign.right),
          ],
        ),
      );
    } else {
      for (var i = 0; i < _baris.length; i++) {
        final r = _baris[i];
        final noUrut = (r['noUrut'] as num?)?.toInt() ??
            ((_halaman - 1) * kUkuranHalamanMutasiSaldoAkun + i + 1);
        final debet = (r['debet'] as num?)?.toDouble() ?? 0;
        final kredit = (r['kredit'] as num?)?.toDouble() ?? 0;
        final saldo = (r['saldo'] as num?)?.toDouble() ?? 0;
        semuaBaris.add(
          AppTableRowData(
            cells: [
              AppTableCell.text('$noUrut', width: 58, align: TextAlign.center),
              AppTableCell.text('${r['tanggalTampil'] ?? r['tanggal'] ?? '-'}',
                  width: 106),
              AppTableCell(
                flex: 2,
                child: Text(
                  '${r['kode'] ?? '-'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
              if (gabung)
                AppTableCell.text(
                  '${r['akunKode'] ?? ''} - ${r['akunNama'] ?? ''}'.trim(),
                  flex: 3,
                ),
              AppTableCell.text('${r['keterangan'] ?? '-'}', flex: 4),
              AppTableCell(
                flex: 2,
                align: TextAlign.right,
                child: Text(
                  _fmtRp.format(debet),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: debet > 0 ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 12.5,
                    color: debet > 0
                        ? AppColors.success
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
              AppTableCell(
                flex: 2,
                align: TextAlign.right,
                child: Text(
                  _fmtRp.format(kredit),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: kredit > 0 ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 12.5,
                    color: kredit > 0
                        ? Colors.orange.shade800
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
              AppTableCell(
                flex: 2,
                align: TextAlign.right,
                child: Text(
                  _fmtRp.format(saldo),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: saldo < 0
                        ? AppColors.danger
                        : AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    // Baris Penutup: TOTAL MUTASI PERIODE & SALDO AKHIR
    semuaBaris.add(
      AppTableRowData(
        cells: [
          AppTableCell.text('', width: 58, align: TextAlign.center),
          AppTableCell.text(_tglSampaiTampil, width: 106),
          AppTableCell(
            flex: 2,
            child: Text(
              'SALDO AKHIR',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: AppColors.primary,
              ),
            ),
          ),
          if (gabung) AppTableCell.text('', flex: 3),
          AppTableCell(
            flex: 4,
            child: Text(
              'Total Mutasi Periode ($_totalData transaksi) & Saldo Akhir',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          AppTableCell(
            flex: 2,
            align: TextAlign.right,
            child: Text(
              _fmtRp.format(_mutasiDebet),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: AppColors.success,
              ),
            ),
          ),
          AppTableCell(
            flex: 2,
            align: TextAlign.right,
            child: Text(
              _fmtRp.format(_mutasiKredit),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: Colors.orange.shade800,
              ),
            ),
          ),
          AppTableCell(
            flex: 2,
            align: TextAlign.right,
            child: Text(
              _fmtRp.format(_saldoAkhir),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: _saldoAkhir < 0 ? AppColors.danger : Colors.blue.shade800,
              ),
            ),
          ),
        ],
      ),
    );

    return AppDataTable(
      minWidth: gabung ? 1040 : 900,
      emptyText: 'Tidak ada mutasi.',
      // Paging 15 baris mutasi per halaman dikelola oleh server + bilah footer
      // dialog di bawah sehingga baris ringkasan SALDO AWAL + 15 mutasi +
      // SALDO AKHIR tetap utuh tampil dalam satu halaman tabel tanpa terpotong.
      pagingOtomatis: false,
      columns: kolom,
      rows: semuaBaris,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ukuran = MediaQuery.of(context).size;
    final fmtBtnTgl = DateFormat('dd MMM yyyy', 'id_ID');
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (ukuran.width * 0.92).clamp(340.0, 1140.0),
        height: (ukuran.height * 0.90).clamp(420.0, 860.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Popup
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              color: AppColors.primary,
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'RINCIAN SALDO AWAL, MUTASI & SALDO AKHIR AKUN',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_akunKode.isEmpty ? '' : '$_akunKode - '}$_akunNama',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Saldo Normal: $_posisi${_grupAkun.isEmpty ? '' : ' • $_grupAkun'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Baris Filter + Cetak PDF + Download Excel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.pageBgOf(context),
                border: Border(
                  bottom: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _memuat ? null : () => _pilihTanggal(mulai: true),
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text('Dari: ${fmtBtnTgl.format(_tglMulai)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _memuat ? null : () => _pilihTanggal(mulai: false),
                    icon: const Icon(Icons.event_outlined, size: 16),
                    label: Text('Sampai: ${fmtBtnTgl.format(_tglSampai)}'),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _cariCtrl,
                      onSubmitted: (_) => _muatHalaman(resetKeSatu: true),
                      decoration: InputDecoration(
                        hintText: 'Cari no. bukti / keterangan...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  if (_punyaAnak)
                    FilterChip(
                      label: const Text('Gabungkan Sub-Akun'),
                      selected: _termasukAnak,
                      onSelected: _memuat
                          ? null
                          : (v) {
                              setStateIfMounted(() => _termasukAnak = v);
                              _muatHalaman(resetKeSatu: true);
                            },
                    ),
                  FilledButton.icon(
                    onPressed:
                        _memuat ? null : () => _muatHalaman(resetKeSatu: true),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('Terapkan'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: (_memuat || _sedangEkspor || _idAkun <= 0)
                        ? null
                        : _cetakPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Cetak PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_memuat || _sedangEkspor || _idAkun <= 0)
                        ? null
                        : _unduhExcel,
                    icon: const Icon(Icons.table_view_outlined, size: 18),
                    label: const Text('Download Excel'),
                  ),
                  if (_sedangEkspor)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),

            // Kartu Ringkasan: Saldo Awal | Mutasi Debet | Mutasi Kredit | Saldo Akhir
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _kartuRingkasan(
                    judul: 'Saldo Awal',
                    nilai: _saldoAwal,
                    ikon: Icons.history_toggle_off,
                    warna: Colors.blueGrey,
                  ),
                  _kartuRingkasan(
                    judul: 'Mutasi Debet',
                    nilai: _mutasiDebet,
                    ikon: Icons.south_west,
                    warna: AppColors.success,
                  ),
                  _kartuRingkasan(
                    judul: 'Mutasi Kredit',
                    nilai: _mutasiKredit,
                    ikon: Icons.north_east,
                    warna: Colors.orange.shade800,
                  ),
                  _kartuRingkasan(
                    judul: 'Saldo Akhir',
                    nilai: _saldoAkhir,
                    ikon: Icons.account_balance_outlined,
                    warna: Colors.blue.shade700,
                  ),
                ],
              ),
            ),

            // Area Tabel Buku Besar
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _galat != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline,
                                      color: AppColors.danger, size: 36),
                                  const SizedBox(height: 8),
                                  Text(_galat!, textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        _muatHalaman(resetKeSatu: false),
                                    icon: const Icon(Icons.refresh, size: 17),
                                    label: const Text('Coba Lagi'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _bangunTabelMutasi(),
              ),
            ),

            // Footer Paging (15 data per halaman)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.pageBgOf(context),
                border: Border(
                  top: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    'Halaman $_halaman dari $_totalHalaman  •  Total $_totalData mutasi ($kUkuranHalamanMutasiSaldoAkun data/halaman)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (!_memuat && _halaman > 1)
                            ? () {
                                _halaman--;
                                _muatHalaman();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: const Text('Sebelumnya'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: (!_memuat && _halaman < _totalHalaman)
                            ? () {
                                _halaman++;
                                _muatHalaman();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: const Text('Berikutnya'),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Tutup'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
