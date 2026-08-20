import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

/// Riwayat sesi kas seluruh kasir pada toko aktif. Kasir hanya membaca,
/// sedangkan supervisor/admin dapat melakukan koreksi berjejak audit.
class TabSesiKasir extends StatefulWidget {
  const TabSesiKasir({super.key});

  @override
  State<TabSesiKasir> createState() => _TabSesiKasirState();
}

class _TabSesiKasirState extends State<TabSesiKasir> with JejakGalat {
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _formatTanggalServer = DateFormat('yyyy-MM-dd');
  final _cariController = TextEditingController();
  final _cariFocus = FocusNode();
  Timer? _debounceCari;
  bool _memuat = true;
  bool _menghitungUlang = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  String _filter = 'SEMUA';
  String _kataKunci = '';

  bool get _bolehKoreksi => Sesi.instance.bolehKelola;

  @override
  void initState() {
    super.initState();
    _cariController.addListener(_jadwalkanFilterCari);
    _muat();
  }

  @override
  void dispose() {
    _debounceCari?.cancel();
    _cariController.removeListener(_jadwalkanFilterCari);
    _cariController.dispose();
    _cariFocus.dispose();
    super.dispose();
  }

  void _jadwalkanFilterCari() {
    _debounceCari?.cancel();
    _debounceCari = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final value = _cariController.text;
      if (value == _kataKunci) return;
      setStateIfMounted(() => _kataKunci = value);
    });
  }

  double _angka(dynamic nilai) => nilai is num
      ? nilai.toDouble()
      : double.tryParse('$nilai'.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;

  dynamic _nilaiPertama(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      if (!row.containsKey(key)) continue;
      final value = row[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  double _nominalTerbaik(Map<String, dynamic> row, List<String> keys) {
    dynamic nolPertama;
    for (final key in keys) {
      if (!row.containsKey(key)) continue;
      final value = row[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      final angka = _angka(value);
      if (angka != 0) return angka;
      nolPertama ??= value;
    }
    return _angka(nolPertama);
  }

  double _modalAwal(Map<String, dynamic> row) => _nominalTerbaik(row, const [
        'modalAwal',
        'modal_awal',
        'modal',
      ]);

  double _tunai(Map<String, dynamic> row) => _nominalTerbaik(row, const [
        'totalTunai',
        'total_tunai',
        'penjualanTunai',
        'penjualan_tunai',
        'tunai',
      ]);

  double _nonTunai(Map<String, dynamic> row) => _nominalTerbaik(row, const [
        'totalNonTunai',
        'total_non_tunai',
        'penjualanNonTunai',
        'penjualan_non_tunai',
        'nonTunai',
        'non_tunai',
      ]);

  double _nilaiSesi(Map<String, dynamic> row) {
    final langsung = _nominalTerbaik(row, const [
      'totalTransaksi',
      'total_transaksi',
      'nilaiTransaksi',
      'nilai_transaksi',
      'nilai',
    ]);
    if (langsung != 0) return langsung;
    return _tunai(row) + _nonTunai(row);
  }

  double _kasSeharusnya(Map<String, dynamic> row) {
    final langsung = _nominalTerbaik(row, const [
      'kasSeharusnya',
      'kas_seharusnya',
      'kasSistem',
      'kas_sistem',
    ]);
    if (langsung != 0) return langsung;
    return _modalAwal(row) + _tunai(row);
  }

  double _kasClosing(Map<String, dynamic> row) => _nominalTerbaik(row, const [
        'kasClosing',
        'kas_closing',
        'uangFisik',
        'uang_fisik',
      ]);

  int _jumlahTransaksi(Map<String, dynamic> row) =>
      _angka(_nilaiPertama(row, const [
        'jumlahTransaksi',
        'jumlah_transaksi',
        'trx',
        'transaksi',
      ])).toInt();
  DateTime? _tanggalDari(dynamic value) {
    final teks = '$value'.trim();
    if (teks.isEmpty || teks == 'null') return null;
    return DateTime.tryParse(teks.replaceFirst(' ', 'T'));
  }

  Future<Map<int, Map<String, dynamic>>> _ambilRekonsiliasiSesi(
      List<Map<String, dynamic>> sesi) async {
    final tanggal = <DateTime>[];
    for (final row in sesi) {
      final buka = _tanggalDari(row['waktuBuka']);
      final tutup = _tanggalDari(row['waktuTutup']);
      if (buka != null) tanggal.add(DateTime(buka.year, buka.month, buka.day));
      if (tutup != null) {
        tanggal.add(DateTime(tutup.year, tutup.month, tutup.day));
      }
    }
    if (tanggal.isEmpty) return const {};
    tanggal.sort();
    final hasil = await ApiClient.instance.aksi(
      'laporan_transaksi_per_kasir_detail',
      {
        'tglMulai': _formatTanggalServer.format(tanggal.first),
        'tglSampai': _formatTanggalServer.format(tanggal.last),
        'komponen': 'semua',
      },
    );
    final map = <int, Map<String, dynamic>>{};
    final regex = RegExp(r'Sesi #(\d+)');
    for (final item in (hasil['data'] as List?) ?? const []) {
      final row = Map<String, dynamic>.from(item as Map);
      final match = regex.firstMatch('${row['referensi'] ?? ''}');
      if (match == null) continue;
      final id = int.tryParse(match.group(1)!);
      if (id == null) continue;
      map[id] = row;
    }
    return map;
  }

  Map<String, dynamic> _payloadRekonsiliasiServer(
    Map<String, dynamic> row,
    Map<String, dynamic> laporan,
  ) {
    return {
      'id_sesi': row['id'],
      'kasir_nama': laporan['kasir'] ?? row['kasirNama'],
      'total_transaksi': _angka(laporan['totalTransaksi']),
      'nilai': _angka(laporan['totalTransaksi']),
      'modal_awal': _angka(laporan['modalAwal']),
      'penjualan_tunai': _angka(laporan['tunai']),
      'penjualan_non_tunai': _angka(laporan['nonTunai']),
      'kas_seharusnya': _angka(laporan['kasSeharusnya']),
      'kas_closing': _angka(laporan['kasClosing']),
      'uang_fisik': _angka(laporan['kasClosing']),
      'jumlah_transaksi': _angka(laporan['jumlahTransaksi']).toInt(),
      'selisih': _angka(laporan['selisih']),
      'sumber': 'laporan_transaksi_per_kasir_detail',
      'alasan_koreksi': 'Hitung ulang dari Laporan Transaksi Per Kasir',
    };
  }

  Future<void> _simpanRekonsiliasiKeServer(
    Map<String, dynamic> row,
    Map<String, dynamic> laporan,
  ) async {
    await ApiClient.instance.aksi(
      'sesi_kas_rekonsiliasi_simpan',
      _payloadRekonsiliasiServer(row, laporan),
    );
  }

  String _pesanError(Object error) {
    if (error is ApiException) {
      final detail = error.kodeReferensi == null || error.kodeReferensi!.isEmpty
          ? ''
          : ' Referensi: ${error.kodeReferensi}.';
      return '${error.pesan}$detail';
    }
    return error.toString();
  }

  bool _berbedaDenganRekonsiliasi(
    Map<String, dynamic> row,
    Map<String, dynamic> laporan,
  ) {
    return _nilaiSesi(row) != _angka(laporan['totalTransaksi']) ||
        _modalAwal(row) != _angka(laporan['modalAwal']) ||
        _tunai(row) != _angka(laporan['tunai']) ||
        _nonTunai(row) != _angka(laporan['nonTunai']) ||
        _kasSeharusnya(row) != _angka(laporan['kasSeharusnya']) ||
        _kasClosing(row) != _angka(laporan['kasClosing']) ||
        _jumlahTransaksi(row) != _angka(laporan['jumlahTransaksi']).toInt();
  }

  Future<void> _hitungUlangDariLaporan() async {
    setStateIfMounted(() => _menghitungUlang = true);
    try {
      final rekonsiliasi = await _ambilRekonsiliasiSesi(_data);
      if (rekonsiliasi.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tidak ada data rekonsiliasi sesi dari laporan.')));
        return;
      }

      final review = <Map<String, dynamic>>[];
      for (final row in _data) {
        final id = _angka(row['id']).toInt();
        final laporan = rekonsiliasi[id];
        if (laporan == null) continue;
        if (!_berbedaDenganRekonsiliasi(row, laporan)) continue;
        review.add({'sesi': row, 'laporan': laporan});
      }

      if (review.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Semua sesi yang ditemukan sudah sesuai laporan.')));
        return;
      }

      Future<void> simpanDanVerifikasi(
        Map<String, dynamic> row,
        Map<String, dynamic> laporan,
      ) async {
        final id = _angka(row['id']).toInt();
        await _simpanRekonsiliasiKeServer(row, laporan);
        if (!mounted) return;
        await _muat();
        if (!mounted) return;
        Map<String, dynamic>? sesiTersimpan;
        for (final itemData in _data) {
          if ('${itemData['id']}' == '${row['id']}') {
            sesiTersimpan = itemData;
            break;
          }
        }
        if (sesiTersimpan == null ||
            _berbedaDenganRekonsiliasi(sesiTersimpan, laporan)) {
          throw StateError(
              'Server menerima request, tetapi data sesi #$id belum berubah saat dimuat ulang. Pastikan API baru sudah ter-deploy pada endpoint yang dipakai aplikasi.');
        }
      }

      if (!mounted) return;
      String? pesanDialog;
      int? idSedangDiproses;
      final terapkan = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: const EdgeInsets.all(16),
            title: const Text('Review Hasil Hitung Ulang Sesi Kasir'),
            content: SizedBox(
              width: MediaQuery.sizeOf(dialogContext).width * .92,
              height: MediaQuery.sizeOf(dialogContext).height * .70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppInfoBanner(
                    icon: Icons.fact_check_outlined,
                    color: AppColors.info,
                    text:
                        'Angka diambil dari Laporan Transaksi - Transaksi Per Kasir. Tekan Terapkan untuk menyimpan hasil hitung ulang ke server.',
                  ),
                  if (pesanDialog != null) ...[
                    const SizedBox(height: 10),
                    AppInfoBanner(
                      icon: Icons.error_outline,
                      color: AppColors.danger,
                      text: pesanDialog!,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AppDataTable(
                        minWidth: 1210,
                        columns: const [
                          AppTableColumn('Sesi', width: 70),
                          AppTableColumn('Kasir', flex: 2),
                          AppTableColumn('Trx',
                              width: 60, align: TextAlign.right),
                          AppTableColumn('Nilai',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Modal',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Tunai',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Non Tunai',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Kas Seharusnya',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Kas Closing',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Aksi',
                              width: 90, align: TextAlign.center),
                        ],
                        rows: review.map((item) {
                          final row = item['sesi'] as Map<String, dynamic>;
                          final laporan =
                              item['laporan'] as Map<String, dynamic>;
                          final id = _angka(row['id']).toInt();
                          return AppTableRowData(cells: [
                            AppTableCell.text('${row['id']}', width: 70),
                            AppTableCell.text(
                              '${laporan['kasir'] ?? row['kasirNama'] ?? '-'}',
                              flex: 2,
                              maxLines: 2,
                            ),
                            AppTableCell.text(
                              '${laporan['jumlahTransaksi'] ?? 0}',
                              width: 60,
                              align: TextAlign.right,
                            ),
                            AppTableCell.text(
                              _rupiah.format(_angka(laporan['totalTransaksi'])),
                              flex: 2,
                              align: TextAlign.right,
                            ),
                            AppTableCell.text(
                              _rupiah.format(_angka(laporan['modalAwal'])),
                              flex: 2,
                              align: TextAlign.right,
                            ),
                            AppTableCell.text(
                              _rupiah.format(_angka(laporan['tunai'])),
                              flex: 2,
                              align: TextAlign.right,
                            ),
                            AppTableCell.text(
                              _rupiah.format(_angka(laporan['nonTunai'])),
                              flex: 2,
                              align: TextAlign.right,
                            ),
                            AppTableCell.text(
                              _rupiah.format(_angka(laporan['kasSeharusnya'])),
                              flex: 2,
                              align: TextAlign.right,
                            ),
                            AppTableCell.text(
                              _rupiah.format(_angka(laporan['kasClosing'])),
                              flex: 2,
                              align: TextAlign.right,
                            ),
                            AppTableCell(
                              width: 90,
                              align: TextAlign.center,
                              child: IconButton(
                                tooltip: 'Terapkan baris ini',
                                icon: idSedangDiproses == id
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle_outline),
                                onPressed: idSedangDiproses != null
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          idSedangDiproses = id;
                                          pesanDialog = null;
                                        });
                                        try {
                                          await simpanDanVerifikasi(
                                              row, laporan);
                                          if (!mounted) return;
                                          setDialogState(
                                              () => review.remove(item));
                                          if (review.isEmpty &&
                                              dialogContext.mounted) {
                                            Navigator.pop(dialogContext, false);
                                          }
                                        } catch (e) {
                                          if (!mounted) return;
                                          setDialogState(() {
                                            pesanDialog =
                                                'Gagal menyimpan sesi #$id. ${_pesanError(e)}';
                                          });
                                        } finally {
                                          if (mounted) {
                                            setDialogState(() {
                                              idSedangDiproses = null;
                                            });
                                          }
                                        }
                                      },
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: idSedangDiproses == null
                    ? () => Navigator.pop(dialogContext, false)
                    : null,
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                onPressed: idSedangDiproses == null
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Terapkan Hasil Hitung Ulang'),
              ),
            ],
          ),
        ),
      );
      if (terapkan != true) return;
      for (final item in review) {
        await simpanDanVerifikasi(
          item['sesi'] as Map<String, dynamic>,
          item['laporan'] as Map<String, dynamic>,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${review.length} sesi berhasil disimpan ke server.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal hitung ulang: ${_pesanError(e)}')));
    } finally {
      if (mounted) setStateIfMounted(() => _menghitungUlang = false);
    }
  }

  bool _cocokKataKunci(Map<String, dynamic> row) {
    final q = _kataKunci.trim().toLowerCase();
    if (q.isEmpty) return true;
    final gabungan = [
      row['id'],
      row['kasirNama'],
      row['kasirUserId'],
      row['statusSesi'],
      row['waktuBuka'],
      row['waktuTutup'],
      row['perangkat'],
      row['keterangan'],
      _nilaiSesi(row),
      _tunai(row),
      _nonTunai(row),
      _kasSeharusnya(row),
      _kasClosing(row),
    ].map((e) => '$e'.toLowerCase()).join(' ');
    return gabungan.contains(q);
  }

  Widget _statusChip(BuildContext context, Map<String, dynamic> row) {
    final buka = '${row['statusSesi']}' == 'BUKA';
    final color = buka ? AppColors.success : AppColors.textSecondaryOf(context);
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.latarLembut(color),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              buka ? Icons.lock_open_outlined : Icons.lock_outline,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              buka ? 'BUKA' : 'TUTUP',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_list', {
        if (Sesi.instance.tokoId != null) 'id_toko': Sesi.instance.tokoId,
      });
      setStateIfMounted(() {
        _data = ((hasil['sesi'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _error = terapkanGalat(e);
        _memuat = false;
      });
    }
  }

  Future<void> _koreksi(Map<String, dynamic> row) async {
    var status = '${row['statusSesi']}' == 'TUTUP' ? 'TUTUP' : 'BUKA';
    final modal =
        TextEditingController(text: _modalAwal(row).toStringAsFixed(0));
    final tunai = TextEditingController(text: _tunai(row).toStringAsFixed(0));
    final fisik =
        TextEditingController(text: _kasClosing(row).toStringAsFixed(0));
    final alasan = TextEditingController();
    try {
      final simpan = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Koreksi Sesi ${row['kasirNama']}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppInfoBanner(
                      icon: Icons.admin_panel_settings_outlined,
                      color: AppColors.warning,
                      text:
                          'Perubahan status dan nominal dicatat sebagai koreksi supervisor. Membuka kembali sesi ditolak bila kasir atau perangkat memiliki sesi aktif lain.',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(
                          labelText: 'Status sesi',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'BUKA', child: Text('BUKA')),
                        DropdownMenuItem(value: 'TUTUP', child: Text('TUTUP')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => status = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Modal awal (Rp)',
                          border: OutlineInputBorder()),
                    ),
                    if (status == 'TUTUP') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tunai,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Penjualan tunai hasil koreksi (Rp)',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: fisik,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Uang fisik (Rp)',
                            border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: alasan,
                      maxLength: 200,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Alasan koreksi supervisor *',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Simpan Koreksi')),
            ],
          ),
        ),
      );
      if (simpan != true) return;
      if (alasan.text.trim().length < 5) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Alasan koreksi wajib minimal 5 karakter.')));
        return;
      }
      final modalNilai = double.tryParse(modal.text.trim());
      final tunaiNilai = double.tryParse(tunai.text.trim());
      final fisikNilai = double.tryParse(fisik.text.trim());
      if (modalNilai == null ||
          modalNilai < 0 ||
          (status == 'TUTUP' &&
              (tunaiNilai == null ||
                  tunaiNilai < 0 ||
                  fisikNilai == null ||
                  fisikNilai < 0))) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Seluruh nominal harus berupa angka nol atau lebih.')));
        return;
      }
      final hasilSimpan = await ApiClient.instance.aksi('sesi_kas_koreksi', {
        'id_sesi': row['id'],
        'status_sesi': status,
        'modal_awal': modalNilai,
        'penjualan_tunai': tunaiNilai ?? 0,
        'uang_fisik': fisikNilai ?? 0,
        'alasan_koreksi': alasan.text.trim(),
      });
      if ('${hasilSimpan['statusSesi']}' != status) {
        throw StateError(
            'Server belum mengonfirmasi perubahan status sesi menjadi $status.');
      }
      await _muat();
      if (!mounted) return;
      Map<String, dynamic>? sesiTersimpan;
      for (final item in _data) {
        if ('${item['id']}' == '${row['id']}') {
          sesiTersimpan = item;
          break;
        }
      }
      if (sesiTersimpan == null || '${sesiTersimpan['statusSesi']}' != status) {
        throw StateError(
            'Data sesi belum berubah menjadi $status setelah dimuat ulang. Silakan coba kembali.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koreksi sesi kas berhasil disimpan.')));
    } catch (e) {
      if (!mounted) return;
      snackbarGalat(context, e);
    } finally {
      modal.dispose();
      tunai.dispose();
      fisik.dispose();
      alasan.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tampil = _data.where((e) {
      final cocokStatus = _filter == 'SEMUA' || '${e['statusSesi']}' == _filter;
      return cocokStatus && _cocokKataKunci(e);
    }).toList();
    final terbuka = _data.where((e) => '${e['statusSesi']}' == 'BUKA').length;
    final totalTunai =
        tampil.fold<double>(0, (jumlah, e) => jumlah + _tunai(e));
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppFormSection(
            judul: 'Sesi Kasir',
            deskripsi:
                'Sesi buka dan tutup pada ${Sesi.instance.tokoNama}. Tarik ke bawah atau tekan Muat Ulang untuk menyegarkan nominal.',
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text('$terbuka sesi masih terbuka')),
                  Chip(label: Text('${tampil.length} sesi ditampilkan')),
                  Chip(label: Text('Tunai ${_rupiah.format(totalTunai)}')),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'SEMUA', label: Text('Semua')),
                      ButtonSegment(value: 'BUKA', label: Text('Buka')),
                      ButtonSegment(value: 'TUTUP', label: Text('Tutup')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) =>
                        setStateIfMounted(() => _filter = v.first),
                  ),
                  OutlinedButton.icon(
                      onPressed: _memuat ? null : _muat,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Muat Ulang')),
                  OutlinedButton.icon(
                      onPressed: _memuat || _menghitungUlang
                          ? null
                          : _hitungUlangDariLaporan,
                      icon: _menghitungUlang
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.manage_search_outlined),
                      label: const Text('Hitung Ulang')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cariController,
                focusNode: _cariFocus,
                enabled: true,
                readOnly: false,
                textInputAction: TextInputAction.search,
                decoration: AppFormStyle.fieldDecoration(
                  context,
                  labelText: 'Cari Sesi Kasir',
                  hintText:
                      'Cari ID sesi, kasir, user, perangkat, waktu, atau keterangan...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              ),
              if (!_bolehKoreksi) ...[
                const SizedBox(height: 10),
                const Text(
                    'Mode lihat saja. Hanya supervisor/admin yang dapat mengoreksi status dan nominal sesi.'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _error!,
                detail: detailUntuk(_error))
          else
            AppDataTable(
              minWidth: 1340,
              emptyText: 'Belum ada sesi kas pada filter ini.',
              columns: [
                const AppTableColumn('ID Sesi', flex: 2),
                const AppTableColumn('Kasir', flex: 2),
                const AppTableColumn('Waktu', flex: 3),
                const AppTableColumn('Perangkat', flex: 2),
                const AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                const AppTableColumn('Modal', flex: 2, align: TextAlign.right),
                const AppTableColumn('Tunai', flex: 2, align: TextAlign.right),
                const AppTableColumn('Non Tunai',
                    flex: 2, align: TextAlign.right),
                const AppTableColumn('Kas Seharusnya',
                    flex: 2, align: TextAlign.right),
                const AppTableColumn('Uang Fisik',
                    flex: 2, align: TextAlign.right),
                const AppTableColumn('Trx', flex: 1, align: TextAlign.right),
                const AppTableColumn('Status',
                    width: 100, align: TextAlign.center),
                if (_bolehKoreksi)
                  const AppTableColumn('Aksi',
                      width: 70, align: TextAlign.center),
              ],
              rows: tampil.map((row) {
                final waktuTutup = row['waktuTutup'] ?? 'masih berjalan';
                final keterangan = '${row['keterangan'] ?? ''}'.trim();
                return AppTableRowData(
                  cells: [
                    AppTableCell.text('${row['id']}', flex: 2),
                    AppTableCell.text(
                      '${row['kasirNama']} (${row['kasirUserId']})',
                      flex: 2,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    AppTableCell.text(
                      '${row['waktuBuka']} - $waktuTutup',
                      flex: 3,
                      maxLines: 2,
                    ),
                    AppTableCell.text('${row['perangkat']}', flex: 2),
                    AppTableCell.text(_rupiah.format(_nilaiSesi(row)),
                        flex: 2, align: TextAlign.right),
                    AppTableCell.text(_rupiah.format(_modalAwal(row)),
                        flex: 2, align: TextAlign.right),
                    AppTableCell.text(_rupiah.format(_tunai(row)),
                        flex: 2, align: TextAlign.right),
                    AppTableCell.text(_rupiah.format(_nonTunai(row)),
                        flex: 2, align: TextAlign.right),
                    AppTableCell.text(_rupiah.format(_kasSeharusnya(row)),
                        flex: 2, align: TextAlign.right),
                    AppTableCell.text(
                        '${row['statusSesi']}' == 'TUTUP'
                            ? _rupiah.format(_kasClosing(row))
                            : '-',
                        flex: 2,
                        align: TextAlign.right),
                    AppTableCell.text('${_jumlahTransaksi(row)}',
                        flex: 1, align: TextAlign.right),
                    AppTableCell(
                      width: 100,
                      align: TextAlign.center,
                      child: _statusChip(context, row),
                    ),
                    if (_bolehKoreksi)
                      AppTableCell(
                        width: 70,
                        align: TextAlign.center,
                        child: IconButton(
                          onPressed: () => _koreksi(row),
                          tooltip: 'Koreksi supervisor',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ),
                  ],
                  onTap: keterangan.isEmpty
                      ? null
                      : () => ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(keterangan))),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
