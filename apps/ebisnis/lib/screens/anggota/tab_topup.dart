import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../services/simple_xlsx.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/aksi_baris_menu.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggal = DateFormat('dd-MM-yyyy');

/// Tab "Topup" (padanan `_manajemen_topup.jsp`) -- riwayat pengisian saldo
/// member + entry baru. Gerbang tulis (tambah/ubah/hapus) memakai
/// `Sesi.instance.bolehEntryTopup` (padanan `Tbmrole.bolehEntryTopup`),
/// BEDA dari gerbang CRUD tab lain yg pakai `bolehKelola` -- melihat riwayat
/// tetap terbuka utk siapa saja yg bisa membuka layar Pelanggan (mode
/// "Hanya Baca" spt JSP saat `!canEdit`).
class AnggotaTabTopup extends StatefulWidget {
  const AnggotaTabTopup({super.key});

  @override
  State<AnggotaTabTopup> createState() => _AnggotaTabTopupState();
}

class _AnggotaTabTopupState extends State<AnggotaTabTopup> with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  bool _memprosesBerkas = false;
  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _muatDaftar();
  }

  /// Diff emisi "lokal dulu" -- menggerakkan animasi kilau baris (termasuk
  /// topup yang baru dicatat operator lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // Baca LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Baris deposit
      // sudah ber-kolom 'id' sehingga kolomKunci tidak perlu disetel.
      await MasterOffline.daftarCacheDulu(
          'deposit_list',
          {
            'keyword': _kataKunci.isEmpty ? null : _kataKunci,
            'page': _halaman,
            'page_size': _pageSize,
          },
          'master:deposit_topup', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _daftar = _diff.terapkan(hasil);
          _total = _diff.total ?? _daftar.length;
        });
      });
    } catch (e) {
      if (mounted) setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cariUlang(String v) async {
    setStateIfMounted(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muatDaftar();
  }

  Future<List<Map<String, dynamic>>> _ambilSemuaData() async {
    final semua = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final hasil = await ApiClient.instance.aksi('deposit_list', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': page,
        'page_size': 100,
      });
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      semua.addAll(data);
      final total = (hasil['total'] as num?)?.toInt() ?? semua.length;
      if (data.isEmpty || semua.length >= total) return semua;
      page++;
    }
  }

  void _info(String pesan) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  Future<void> _downloadExcel() async {
    setStateIfMounted(() => _memprosesBerkas = true);
    try {
      final data = await _ambilSemuaData();
      final bytes = buildSimpleXlsx(
        sheetName: 'Topup',
        headers: const [
          'ID_MEMBER',
          'KODE_MEMBER',
          'NAMA_MEMBER',
          'NOMINAL',
          'WAKTU',
          'TANGGAL_EXPIRED',
          'METODE_PEMBAYARAN',
          'KETERANGAN',
        ],
        rows: data
            .map((d) => <Object?>[
                  d['idMember'] ?? '',
                  d['kodeMember'] ?? '',
                  d['namaMember'] ?? '',
                  (d['nominal'] as num?) ?? 0,
                  d['waktu'] ?? '',
                  d['tanggalExpired'] ?? '',
                  d['jenisPembayaranNama'] ?? '',
                  d['keterangan'] ?? '',
                ])
            .toList(),
      );
      final lokasi = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Riwayat Topup',
        fileName:
            'Topup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (lokasi != null) {
        await File(lokasi).writeAsBytes(bytes);
        _info('${data.length} data topup berhasil diekspor.');
      }
    } catch (e) {
      _info('Excel belum berhasil dibuat. Silakan coba lagi. Detail: $e');
    } finally {
      setStateIfMounted(() => _memprosesBerkas = false);
    }
  }

  Future<void> _uploadExcel() async {
    final dipilih = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih Excel Topup',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (dipilih == null || dipilih.files.isEmpty) return;
    final file = dipilih.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      _info('File tidak dapat dibaca. Pilih kembali file Excel.');
      return;
    }
    setStateIfMounted(() => _memprosesBerkas = true);
    var berhasil = 0;
    var gagal = 0;
    final rincian = <String>[];
    try {
      final tabel = readSimpleXlsx(Uint8List.fromList(bytes));
      if (tabel.length < 2) {
        throw const FormatException('Excel tidak memiliki baris data.');
      }
      final header = <String, int>{};
      for (var i = 0; i < tabel.first.length; i++) {
        header[tabel.first[i].trim().toUpperCase()] = i;
      }
      final kolomKode = header['KODE_MEMBER'];
      final kolomId = header['ID_MEMBER'];
      final kolomNominal = header['NOMINAL'];
      if ((kolomKode == null && kolomId == null) || kolomNominal == null) {
        throw const FormatException(
            'Kolom ID_MEMBER atau KODE_MEMBER, serta NOMINAL wajib tersedia.');
      }
      final jumlahCalon = tabel.skip(1).where((row) {
        final kode = kolomKode != null && kolomKode < row.length
            ? row[kolomKode].trim()
            : '';
        final id =
            kolomId != null && kolomId < row.length ? row[kolomId].trim() : '';
        return kode.isNotEmpty || id.isNotEmpty;
      }).length;
      if (!mounted) return;
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Konfirmasi Upload Topup'),
          content: Text(
            'Ditemukan $jumlahCalon baris yang akan diperiksa. Setiap baris '
            'valid akan menambah saldo member dan tercatat sebagai transaksi '
            'baru. Pastikan file ini belum pernah diunggah agar saldo tidak '
            'bertambah dua kali.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ya, Proses'),
            ),
          ],
        ),
      );
      if (lanjut != true) return;
      var checksum = 2166136261;
      for (final byte in bytes) {
        checksum = ((checksum ^ byte) * 16777619) & 0xffffffff;
      }
      final referensiUpload = checksum.toRadixString(16);
      String nilai(List<String> row, String nama) {
        final index = header[nama];
        return index == null || index >= row.length ? '' : row[index].trim();
      }

      for (var i = 1; i < tabel.length; i++) {
        final row = tabel[i];
        final kode = kolomKode == null || kolomKode >= row.length
            ? ''
            : row[kolomKode].trim();
        final idMemberText = kolomId == null || kolomId >= row.length
            ? ''
            : row[kolomId].trim().replaceFirst(RegExp(r'\.0$'), '');
        int? idMember = int.tryParse(idMemberText);
        final nominalText = kolomNominal >= row.length
            ? ''
            : row[kolomNominal]
                .replaceAll(RegExp(r'[^0-9,.-]'), '')
                .replaceAll(',', '.');
        final nominal = double.tryParse(nominalText) ?? 0;
        if (kode.isEmpty && idMember == null && nominal == 0) continue;
        if ((kode.isEmpty && idMember == null) || nominal <= 0) {
          gagal++;
          rincian.add('Baris ${i + 1}: kode kosong atau nominal tidak valid.');
          continue;
        }
        try {
          if (idMember == null) {
            final cari = await ApiClient.instance.aksi('anggota_list', {
              'keyword': kode,
              'page_size': 10,
            });
            final anggota = ((cari['data'] as List?) ?? [])
                .cast<Map<String, dynamic>>()
                .where((m) => '${m['kode']}'.trim() == kode)
                .toList();
            if (anggota.isEmpty) {
              throw FormatException('kode member "$kode" tidak ditemukan.');
            }
            idMember = (anggota.first['id'] as num).toInt();
          }
          await ApiClient.instance.aksi('topup_saldo', {
            'idempotency_key': 'TOPUP-XLSX-$referensiUpload-$i',
            'id_member': idMember,
            'nominal': nominal,
            'keterangan': nilai(row, 'KETERANGAN'),
            if (nilai(row, 'WAKTU').isNotEmpty) 'waktu': nilai(row, 'WAKTU'),
            if (nilai(row, 'TANGGAL_EXPIRED').isNotEmpty)
              'tanggal_expired': nilai(row, 'TANGGAL_EXPIRED'),
          });
          berhasil++;
        } catch (e) {
          gagal++;
          rincian.add('Baris ${i + 1}: $e');
        }
      }
      _info('Upload selesai: $berhasil berhasil, $gagal gagal.'
          '${rincian.isEmpty ? '' : ' ${rincian.take(3).join(' ')}'}');
      await _muatDaftar();
    } catch (e) {
      _info(
          'Excel belum dapat diproses. Gunakan hasil Download Excel sebagai template. Detail: $e');
    } finally {
      setStateIfMounted(() => _memprosesBerkas = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _memprosesBerkas = true);
    try {
      final data = await _ambilSemuaData();
      if (data.isEmpty) {
        _info('Tidak ada data topup untuk dicetak.');
        return;
      }
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Riwayat Topup Member',
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (_kataKunci.isNotEmpty) pw.Text('Filter: $_kataKunci'),
            pw.Text(
                'Dicetak: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'Waktu',
              'Kode',
              'Member',
              'Nominal',
              'Metode',
              'Keterangan'
            ],
            data: data
                .map((d) => [
                      '${d['waktu'] ?? ''}',
                      '${d['kodeMember'] ?? ''}',
                      '${d['namaMember'] ?? ''}',
                      _formatRupiah.format((d['nominal'] as num?) ?? 0),
                      '${d['jenisPembayaranNama'] ?? ''}',
                      '${d['keterangan'] ?? ''}',
                    ])
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          )
        ],
      ));
      await Printing.layoutPdf(
          onLayout: (_) => doc.save(), name: 'Riwayat_Topup.pdf');
    } catch (e) {
      _info('PDF belum berhasil dibuat. Silakan coba lagi. Detail: $e');
    } finally {
      setStateIfMounted(() => _memprosesBerkas = false);
    }
  }

  Future<void> _bukaForm({Map<String, dynamic>? deposit}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormTopup(deposit: deposit),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _bukaTopupOnline() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FormTopupOnline(),
    );
    // Pembuatan VA belum merupakan topup. Daftar saldo sengaja tidak ditambah
    // secara optimistis; Deposit baru tampil sesudah callback resmi bank atau
    // gateway diterima server.
    if (mounted) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> d) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Entri Topup?'),
        content: Text(
            'Topup ${_formatRupiah.format((d['nominal'] as num?) ?? 0)} untuk "${d['namaMember']}" akan dihapus permanen dan MENGURANGI saldo member secara langsung.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    if (!mounted) return;
    try {
      // Lokal dulu, baru dikirim (pola master).
      await prosesSimpanMaster(
        context,
        aksi: 'deposit_hapus',
        body: {'id': d['id']},
        kunci: 'deposit:${d['id']}',
      );
      await _muatDaftar();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_pesanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_pesanError!, textAlign: TextAlign.center),
              AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _muatDaftar, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    final bolehEdit = Sesi.instance.bolehEntryTopup;
    return RefreshIndicator(
      onRefresh: _muatDaftar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (!bolehEdit)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.latarLembut(AppColors.warning),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mode Hanya Baca -- Anda tidak memiliki hak akses "Boleh Entry Topup". Hubungi admin untuk mengaktifkannya.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          LayoutBuilder(builder: (context, constraints) {
            final sempit = constraints.maxWidth < 850;
            final pencarian = AppSearchField(
              hintText: 'Cari nama member...',
              debounce: const Duration(milliseconds: 450),
              onChanged: _cariUlang,
            );
            final aksi = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _memprosesBerkas ? null : _downloadExcel,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Download Excel'),
                ),
                if (bolehEdit)
                  OutlinedButton.icon(
                    onPressed: _memprosesBerkas ? null : _uploadExcel,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Upload Excel'),
                  ),
                OutlinedButton.icon(
                  onPressed: _memprosesBerkas ? null : _cetakPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Cetak PDF'),
                ),
                if (bolehEdit)
                  ElevatedButton.icon(
                    onPressed: _memprosesBerkas ? null : () => _bukaForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Topup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (bolehEdit)
                  OutlinedButton.icon(
                    onPressed: _memprosesBerkas ? null : _bukaTopupOnline,
                    icon: const Icon(Icons.account_balance_outlined, size: 18),
                    label: const Text('Topup Online'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                    ),
                  ),
              ],
            );
            if (sempit) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pencarian,
                  const SizedBox(height: 8),
                  aksi,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: pencarian),
                const SizedBox(width: 8),
                Flexible(child: aksi),
              ],
            );
          }),
          if (_memprosesBerkas) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 900,
            emptyText: 'Belum ada riwayat topup.',
            columns: [
              const AppTableColumn('Waktu', flex: 2),
              const AppTableColumn('Member', flex: 3),
              const AppTableColumn('Nominal', flex: 2, align: TextAlign.right),
              const AppTableColumn('Metode / Ket.', flex: 3),
              AppTableColumn('Aksi',
                  width: bolehEdit ? 64 : 24, align: TextAlign.center),
            ],
            rows: _daftar.map((d) {
              final expired = d['tanggalExpired'] != null;
              return AppTableRowData(
                cells: [
                  AppTableCell(
                    flex: 2,
                    child: KilauBaris(
                      kunci: '${d['id'] ?? d['_kunci'] ?? ''}',
                      idBaru: _diff.idBaru,
                      idBerubah: _diff.idBerubah,
                      child: Text('${d['waktu'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  AppTableCell(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d['namaMember'] ?? '-'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        if (expired)
                          Text('Kadaluarsa: ${d['tanggalExpired']}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.warning)),
                      ],
                    ),
                  ),
                  AppTableCell.text(
                    _formatRupiah.format((d['nominal'] as num?) ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success),
                  ),
                  AppTableCell.text(
                    [
                      if ('${d['jenisPembayaranNama'] ?? ''}'.isNotEmpty)
                        d['jenisPembayaranNama'],
                      if ('${d['keterangan'] ?? ''}'.isNotEmpty)
                        d['keterangan'],
                    ].join(' · '),
                    flex: 3,
                    maxLines: 2,
                  ),
                  AppTableCell(
                    width: bolehEdit ? 64 : 24,
                    align: TextAlign.center,
                    child: AksiBarisMenu(aksi: [
                      AksiBaris(
                          ikon: Icons.edit_outlined,
                          label: 'Ubah topup',
                          onTap:
                              bolehEdit ? () => _bukaForm(deposit: d) : null),
                      AksiBaris(
                          ikon: Icons.delete_outline,
                          label: 'Hapus topup',
                          merusak: true,
                          onTap: bolehEdit ? () => _hapus(d) : null),
                    ]),
                  ),
                ],
              );
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'topup',
              onSebelumnya:
                  _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
              onBerikutnya: _halaman < _totalHalaman
                  ? () => _pindahHalaman(_halaman + 1)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormTopup extends StatefulWidget {
  final Map<String, dynamic>? deposit;
  const _FormTopup({required this.deposit});

  @override
  State<_FormTopup> createState() => _FormTopupState();
}

class _FormTopupState extends State<_FormTopup> {
  final _formKey = GlobalKey<FormState>();
  // Dibuat sekali saat form dibuka dan dipakai ulang pada retry tombol Simpan.
  // Server menjadikannya exactly-once sehingga timeout tidak menggandakan saldo.
  late final String _idempotencyKey =
      'TOPUP-${DateTime.now().microsecondsSinceEpoch}';
  late final TextEditingController _nominal;
  late final TextEditingController _keterangan;
  late final TextEditingController _cariMember;
  int? _idMember;
  String? _namaMemberDipilih;
  List<Map<String, dynamic>> _hasilCariMember = [];
  bool _mencariMember = false;
  DateTime _waktu = DateTime.now();
  DateTime? _tanggalExpired;
  bool _menyimpan = false;
  String? _pesanError;
  String? _detailGalat;
  Timer? _debounceCariMember;

  @override
  void initState() {
    super.initState();
    final d = widget.deposit;
    _nominal = TextEditingController(text: '${d?['nominal'] ?? ''}');
    _keterangan = TextEditingController(text: '${d?['keterangan'] ?? ''}');
    _cariMember = TextEditingController()..addListener(_saatCariMemberBerubah);
    if (d != null) {
      _idMember = d['idMember'] as int?;
      _namaMemberDipilih = '${d['namaMember'] ?? ''}';
      if (d['waktu'] != null) {
        try {
          _waktu =
              DateTime.parse((d['waktu'] as String).replaceFirst(' ', 'T'));
        } catch (_) {}
      }
      if (d['tanggalExpired'] != null) {
        try {
          _tanggalExpired = DateTime.parse('${d['tanggalExpired']}');
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _debounceCariMember?.cancel();
    _nominal.dispose();
    _keterangan.dispose();
    _cariMember.dispose();
    super.dispose();
  }

  void _saatCariMemberBerubah() {
    _debounceCariMember?.cancel();
    _debounceCariMember = Timer(const Duration(milliseconds: 400),
        () => _cariAnggota(_cariMember.text));
  }

  Future<void> _cariAnggota(String kata) async {
    if (kata.trim().length < 2) {
      setStateIfMounted(() => _hasilCariMember = []);
      return;
    }
    setStateIfMounted(() => _mencariMember = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('anggota_list', {'keyword': kata.trim(), 'page_size': 10});
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setStateIfMounted(() => _hasilCariMember = data);
    } catch (_) {
      // Pencarian gagal -- diamkan, user bisa coba lagi.
    } finally {
      if (mounted) setStateIfMounted(() => _mencariMember = false);
    }
  }

  Future<void> _pilihWaktu() async {
    final tanggal = await showDatePicker(
        context: context,
        initialDate: _waktu,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (tanggal == null || !mounted) return;
    final jam = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_waktu));
    setStateIfMounted(() => _waktu = DateTime(tanggal.year, tanggal.month,
        tanggal.day, jam?.hour ?? 0, jam?.minute ?? 0));
  }

  Future<void> _pilihTanggalExpired() async {
    final hasil = await showDatePicker(
        context: context,
        initialDate: _tanggalExpired ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (hasil != null) setStateIfMounted(() => _tanggalExpired = hasil);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.deposit == null && _idMember == null) {
      setStateIfMounted(() => _pesanError = 'Member wajib dipilih.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
      _detailGalat = null;
    });
    try {
      final ubah = widget.deposit != null;
      await ApiClient.instance.aksi(ubah ? 'deposit_ubah' : 'topup_saldo', {
        if (ubah) 'id': widget.deposit!['id'],
        if (!ubah) 'id_member': _idMember,
        if (!ubah) 'idempotency_key': _idempotencyKey,
        'nominal': double.tryParse(_nominal.text.trim()) ?? 0,
        'keterangan': _keterangan.text.trim(),
        'waktu': DateFormat('yyyy-MM-dd HH:mm:ss').format(_waktu),
        'tanggal_expired': _tanggalExpired == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_tanggalExpired!),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Server memisahkan kalimat untuk pengguna (`message` + `solusi`) dari
      // jejak teknis (`teknis`). Sebelumnya form ini hanya memakai
      // `e.toString()` sehingga `teknis` -- satu-satunya tempat alasan
      // penolakan muncul saat server menyamarkannya -- terbuang.
      final galat = GalatTampil.dari(e);
      setStateIfMounted(() {
        _pesanError = galat.pesan;
        _detailGalat = galat.detail;
      });
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.deposit != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Entri Topup' : 'Tambah Topup',
            subtitle: ubah
                ? 'Member: ${_namaMemberDipilih ?? '-'}'
                : 'Isi saldo member secara manual.',
            icon: Icons.add_card_outlined,
            errorText: _pesanError,
            errorDetail: _detailGalat,
            // Urutan ini mengikuti struktur form lama; children sengaja tetap
            // sebelum actions agar diff layar Topup mudah diaudit.
            // ignore: sort_child_properties_last
            children: [
              AppFormSection(
                judul: 'Member',
                children: [
                  if (ubah)
                    AppReadonlyField(
                        label: 'Member', value: _namaMemberDipilih ?? '-')
                  else ...[
                    AppFormTextField(
                      label: 'Cari Member *',
                      controller: _cariMember,
                      hintText: 'Ketik nama/kode member...',
                    ),
                    if (_mencariMember)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_idMember != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Chip(
                          avatar: const Icon(Icons.check_circle,
                              size: 16, color: Colors.white),
                          backgroundColor: AppColors.success,
                          label: Text(_namaMemberDipilih ?? '',
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    if (_hasilCariMember.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: AppColors.borderOf(context)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _hasilCariMember.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = _hasilCariMember[i];
                            return ListTile(
                              dense: true,
                              title: Text('${m['nama']}'),
                              subtitle: Text('${m['kode'] ?? ''}'),
                              onTap: () => setStateIfMounted(() {
                                _idMember = m['id'] as int;
                                _namaMemberDipilih = '${m['nama']}';
                                _hasilCariMember = [];
                                _cariMember.text = '${m['nama']}';
                              }),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Detail Topup',
                children: [
                  AppFormTextField(
                    label: 'Nominal *',
                    controller: _nominal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) return 'Nominal harus > 0';
                      return null;
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihWaktu,
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            'Waktu: ${_formatTanggal.format(_waktu)} ${_waktu.hour.toString().padLeft(2, '0')}:${_waktu.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihTanggalExpired,
                          icon: const Icon(Icons.event_busy, size: 16),
                          label: Text(
                            _tanggalExpired == null
                                ? 'Tanggal Kadaluarsa (opsional)'
                                : 'Kadaluarsa: ${_formatTanggal.format(_tanggalExpired!)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_tanggalExpired != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () =>
                              setStateIfMounted(() => _tanggalExpired = null),
                        ),
                    ],
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                    maxLines: 2,
                  ),
                ],
              ),
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
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form pembuatan tagihan topup melalui bank/gateway. Form ini tidak pernah
/// menulis saldo secara lokal maupun memanggil endpoint topup manual. Saldo
/// member hanya berubah melalui callback pembayaran resmi di server.
class _FormTopupOnline extends StatefulWidget {
  const _FormTopupOnline();

  @override
  State<_FormTopupOnline> createState() => _FormTopupOnlineState();
}

class _FormTopupOnlineState extends State<_FormTopupOnline> {
  final _formKey = GlobalKey<FormState>();
  final _cariMember = TextEditingController();
  final _nominal = TextEditingController();
  Timer? _debounceCariMember;
  int? _idMember;
  String? _namaMember;
  List<Map<String, dynamic>> _hasilCariMember = [];
  List<Map<String, dynamic>> _caraBayar = [];
  Map<String, dynamic>? _caraDipilih;
  Map<String, dynamic>? _hasilTopup;
  bool _mencariMember = false;
  bool _memuatCaraBayar = false;
  bool _membuatTagihan = false;
  bool _mengaturTeksMember = false;
  String? _pesanError;
  String? _detailGalat;

  @override
  void initState() {
    super.initState();
    _cariMember.addListener(_saatCariMemberBerubah);
  }

  @override
  void dispose() {
    _debounceCariMember?.cancel();
    _cariMember.dispose();
    _nominal.dispose();
    super.dispose();
  }

  void _saatCariMemberBerubah() {
    if (_mengaturTeksMember) return;
    _debounceCariMember?.cancel();
    _debounceCariMember = Timer(
      const Duration(milliseconds: 400),
      () => _cariAnggota(_cariMember.text),
    );
  }

  Future<void> _cariAnggota(String kata) async {
    if (kata.trim().length < 2) {
      setStateIfMounted(() => _hasilCariMember = []);
      return;
    }
    setStateIfMounted(() => _mencariMember = true);
    try {
      final hasil = await ApiClient.instance.aksi('anggota_list', {
        'keyword': kata.trim(),
        'page_size': 10,
      });
      final data = ((hasil['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setStateIfMounted(() => _hasilCariMember = data);
    } catch (_) {
      if (mounted) setStateIfMounted(() => _hasilCariMember = []);
    } finally {
      if (mounted) setStateIfMounted(() => _mencariMember = false);
    }
  }

  Future<void> _pilihMember(Map<String, dynamic> member) async {
    final id = (member['id'] as num?)?.toInt();
    if (id == null) return;
    _mengaturTeksMember = true;
    _cariMember.text = '${member['nama'] ?? member['kode'] ?? ''}';
    _mengaturTeksMember = false;
    setStateIfMounted(() {
      _idMember = id;
      _namaMember = '${member['nama'] ?? '-'}';
      _hasilCariMember = [];
      _caraBayar = [];
      _caraDipilih = null;
      _pesanError = null;
      _detailGalat = null;
      _memuatCaraBayar = true;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'topup_online_cara_bayar',
        {'id_member': id},
      );
      final daftar = ((hasil['list'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setStateIfMounted(() {
        _caraBayar = daftar;
        _caraDipilih = daftar.length == 1 ? daftar.first : null;
        if (daftar.isEmpty) {
          _pesanError =
              '${hasil['description'] ?? 'Belum ada cara pembayaran online untuk member ini.'}';
        }
      });
    } catch (e) {
      final galat = GalatTampil.dari(e);
      if (mounted) {
        setStateIfMounted(() {
          _pesanError = galat.pesan;
          _detailGalat = galat.detail;
        });
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memuatCaraBayar = false);
    }
  }

  double _nominalInput() {
    final angka = _nominal.text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(angka) ?? 0;
  }

  String _labelCaraBayar(Map<String, dynamic> cara) {
    final kanal =
        '${cara['nama_channel'] ?? cara['channel'] ?? cara['nama'] ?? '-'}';
    final metode = '${cara['nama'] ?? ''}'.trim();
    final biaya = (cara['biaya_admin'] as num?)?.toDouble() ?? 0;
    return [
      kanal,
      if (metode.isNotEmpty && metode != kanal) metode,
      if (biaya > 0) 'admin ${_formatRupiah.format(biaya)}',
    ].join(' · ');
  }

  Future<void> _buatTagihan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idMember == null) {
      setStateIfMounted(() => _pesanError = 'Member wajib dipilih.');
      return;
    }
    if (_caraDipilih == null) {
      setStateIfMounted(
          () => _pesanError = 'Cara pembayaran online wajib dipilih.');
      return;
    }
    setStateIfMounted(() {
      _membuatTagihan = true;
      _pesanError = null;
      _detailGalat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('topup_online_buat', {
        'id_member': _idMember,
        'cara_pembayaran_id': _caraDipilih!['id'],
        'channel': '${_caraDipilih!['channel'] ?? ''}',
        'nominal': _nominalInput(),
      });
      if (mounted) {
        setStateIfMounted(() => _hasilTopup = Map<String, dynamic>.from(hasil));
      }
    } catch (e) {
      final galat = GalatTampil.dari(e);
      if (mounted) {
        setStateIfMounted(() {
          _pesanError = galat.pesan;
          _detailGalat = galat.detail;
        });
      }
    } finally {
      if (mounted) setStateIfMounted(() => _membuatTagihan = false);
    }
  }

  void _salin(String label, String nilai) {
    Clipboard.setData(ClipboardData(text: nilai));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label berhasil disalin.')),
    );
  }

  Future<void> _bukaLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      setStateIfMounted(
          () => _pesanError = 'Tautan pembayaran dari server tidak valid.');
      return;
    }
    final terbuka = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!terbuka && mounted) {
      setStateIfMounted(() => _pesanError =
          'Tautan pembayaran belum dapat dibuka pada perangkat ini.');
    }
  }

  void _buatLagi() {
    setStateIfMounted(() {
      _hasilTopup = null;
      _nominal.clear();
      _pesanError = null;
      _detailGalat = null;
    });
  }

  Widget _barisHasil(String label, String nilai, {bool dapatDisalin = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              nilai.isEmpty ? '-' : nilai,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (dapatDisalin && nilai.isNotEmpty)
            IconButton(
              tooltip: 'Salin $label',
              onPressed: () => _salin(label, nilai),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _isiHasil() {
    final hasil = _hasilTopup!;
    final topup = hasil['topup'] is Map
        ? Map<String, dynamic>.from(hasil['topup'] as Map)
        : const <String, dynamic>{};
    final nominal = (topup['nilai'] as num?)?.toDouble() ?? _nominalInput();
    final admin = (hasil['biayaAdministrasi'] as num?)?.toDouble() ?? 0;
    final total = (hasil['total'] as num?)?.toDouble() ?? nominal + admin;
    final va = '${hasil['va'] ?? ''}'.trim();
    final link = '${hasil['link'] ?? ''}'.trim();
    final vaBankLain = '${hasil['va_bank_lain'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.latarLembut(AppColors.warning),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_outlined, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tagihan online berhasil dibuat dan masih menunggu pembayaran. Saldo member belum bertambah. Saldo akan masuk otomatis hanya setelah bank/gateway mengonfirmasi pembayaran berhasil.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppFormSection(
          judul: 'Rincian Tagihan Online',
          children: [
            _barisHasil('Member', '${hasil['member'] ?? _namaMember ?? '-'}'),
            _barisHasil('Nominal topup', _formatRupiah.format(nominal)),
            _barisHasil('Biaya admin', _formatRupiah.format(admin)),
            _barisHasil('Total bayar', _formatRupiah.format(total)),
            _barisHasil('Berlaku sampai', '${hasil['billExpired'] ?? '-'}'),
            _barisHasil('Nomor VA', va, dapatDisalin: true),
            if (vaBankLain.isNotEmpty)
              _barisHasil('Prefix bank lain', vaBankLain, dapatDisalin: true),
            if (link.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _bukaLink(link),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Buka Halaman Pembayaran'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _isiForm() {
    return Column(
      children: [
        AppFormSection(
          judul: 'Member',
          children: [
            AppFormTextField(
              label: 'Cari Member *',
              controller: _cariMember,
              hintText: 'Ketik nama/kode member...',
            ),
            if (_mencariMember || _memuatCaraBayar)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (_idMember != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Chip(
                  avatar: const Icon(Icons.check_circle,
                      size: 16, color: Colors.white),
                  backgroundColor: AppColors.success,
                  label: Text(
                    _namaMember ?? '',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            if (_hasilCariMember.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderOf(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _hasilCariMember.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final member = _hasilCariMember[i];
                    return ListTile(
                      dense: true,
                      title: Text('${member['nama'] ?? '-'}'),
                      subtitle: Text('${member['kode'] ?? ''}'),
                      onTap: () => _pilihMember(member),
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AppFormSection(
          judul: 'Pembayaran',
          children: [
            AppFormTextField(
              label: 'Nominal Topup *',
              controller: _nominal,
              keyboardType: TextInputType.number,
              hintText: 'Contoh: 100000',
              validator: (_) =>
                  _nominalInput() <= 0 ? 'Nominal harus lebih dari 0' : null,
            ),
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _caraDipilih,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Cara Bayar / Kanal *'),
              items: _caraBayar
                  .map((cara) => DropdownMenuItem<Map<String, dynamic>>(
                        value: cara,
                        child: Text(
                          _labelCaraBayar(cara),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _memuatCaraBayar
                  ? null
                  : (nilai) => setStateIfMounted(() => _caraDipilih = nilai),
              validator: (nilai) =>
                  nilai == null ? 'Cara pembayaran wajib dipilih' : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Biaya administrasi pada pilihan hanya informasi awal. Nilai final selalu dihitung ulang oleh server saat tagihan dibuat.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selesai = _hasilTopup != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: selesai ? 'Tagihan Topup Online' : 'Topup Online',
            subtitle: selesai
                ? 'Berikan VA atau tautan pembayaran kepada member.'
                : 'Buat tagihan bank/gateway untuk member terpilih.',
            icon: Icons.account_balance_outlined,
            errorText: _pesanError,
            errorDetail: _detailGalat,
            actions: selesai
                ? [
                    OutlinedButton.icon(
                      onPressed: _buatLagi,
                      icon: const Icon(Icons.add_card_outlined, size: 18),
                      label: const Text('Buat Topup Lain'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Selesai'),
                    ),
                  ]
                : [
                    OutlinedButton.icon(
                      onPressed: _membuatTagihan
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Batal'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _membuatTagihan ? null : _buatTagihan,
                      icon: _membuatTagihan
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.account_balance_outlined,
                              size: 18),
                      label: const Text('Buat Tagihan Online'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
            children: [selesai ? _isiHasil() : _isiForm()],
          ),
        ),
      ),
    );
  }
}
