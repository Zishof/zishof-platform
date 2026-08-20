import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
                  width: bolehEdit ? 88 : 24, align: TextAlign.center),
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
                    width: bolehEdit ? 88 : 24,
                    align: TextAlign.center,
                    child: bolehEdit
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _bukaForm(deposit: d),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.danger),
                                onPressed: () => _hapus(d),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
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
