import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_db/core_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_components.dart';
import '../widgets/rincian_intip_dialog.dart';
import '../widgets/safe_state.dart';

/// Tab SO Grand (Grand Stock Opname) — Audit Total Seluruh Fisik Barang Toko per Rak.
///
/// Fitur Lengkap:
/// 1. Daftar seluruh produk aktif toko beserta Rak penempatannya (`rakId`, `rakNama`).
///    Stok sistem yang ditampilkan pada baris adalah stok produk pada Rak tersebut
///    (bukan sekadar total produk), dengan sinkronisasi otomatis ke stok keseluruhan produk.
/// 2. Filter pencarian instan (kode/nama/barcode), Kategori, dan Rak (termasuk "Rak Belum Ditentukan" / "RAK Utama").
/// 3. Auto-save langsung saat entry stok fisik diisi (`so_grand_simpan_baris`) disertai
///    indikator tanda centang hijau (`Icons.check_circle`) ketika penyimpanan berhasil.
/// 4. Progress bar bertahap (`0%..100%`) beserta teks tahapan aktif saat Cetak KKSO PDF,
///    Download Excel, Upload Excel, Simpan Entri Fisik Tabel, dan Muat Ulang.
class TabSoGrand extends StatefulWidget {
  final int? filterRakId;
  final String filterRakNama;

  const TabSoGrand({
    super.key,
    this.filterRakId,
    this.filterRakNama = '',
  });

  @override
  State<TabSoGrand> createState() => _TabSoGrandState();
}

class _TabSoGrandState extends State<TabSoGrand> {
  final _formatAngka = NumberFormat('#,##0.##', 'id_ID');
  final _formatRupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  bool _menyimpan = false;
  bool _mengunduh = false;
  bool _mengunggah = false;
  bool _mencetak = false;
  String? _pesanError;

  // Indikator Progress Bar Bertahap (0.0 .. 1.0) & Keterangan Aktivitas
  bool _tampilProgres = false;
  double _nilaiProgres = 0.0;
  String _teksProgres = '';

  List<Map<String, dynamic>> _semuaProduk = [];
  List<Map<String, dynamic>> _filteredProduk = [];
  List<Map<String, dynamic>> _daftarRak = [];

  final Map<String, TextEditingController> _controllersFisik = {};
  final Map<String, TextEditingController> _controllersKet = {};
  final Map<String, Timer> _debounceAutoSave = {};
  // Status simpan per baris ('saving', 'saved', 'error')
  final Map<String, String> _statusSimpanBaris = {};
  final Map<String, String> _pesanSimpanBaris = {};
  Set<String> _checklistSelesai = <String>{};

  final TextEditingController _cariController = TextEditingController();
  String _kategoriTerpilih = '';
  String _rakFilterTerpilih = ''; // '' = Semua Rak, '0' = Rak Belum Ditentukan, atau ID rak
  List<String> _daftarKategori = [];

  double _totalStokSistem = 0;
  double _totalNilaiAset = 0;

  String get _kunciChecklist =>
      'so_grand_cek_v2_${Sesi.instance.idTokoTerpilih ?? 0}';

  String _kunciBaris(Map<String, dynamic> p) {
    final pId = (p['produkId'] as num?)?.toInt() ?? 0;
    final rId = (p['rakId'] as num?)?.toInt() ?? 0;
    return '${pId}_$rId';
  }

  @override
  void initState() {
    super.initState();
    if (widget.filterRakId != null) {
      _rakFilterTerpilih = '${widget.filterRakId}';
    }
    _muatData();
  }

  @override
  void didUpdateWidget(covariant TabSoGrand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRakId != widget.filterRakId) {
      _rakFilterTerpilih =
          widget.filterRakId != null ? '${widget.filterRakId}' : '';
      _terapkanFilter();
    }
  }

  @override
  void dispose() {
    _cariController.dispose();
    for (final t in _debounceAutoSave.values) {
      t.cancel();
    }
    for (final c in _controllersFisik.values) {
      c.dispose();
    }
    for (final c in _controllersKet.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _aturProgres(bool tampil, {double nilai = 0.0, String teks = ''}) {
    if (!mounted) return;
    setStateIfMounted(() {
      _tampilProgres = tampil;
      _nilaiProgres = nilai.clamp(0.0, 1.0);
      _teksProgres = teks;
    });
  }

  Future<void> _muatChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kunciChecklist) ?? [];
    _checklistSelesai = list.toSet();
  }

  Future<void> _simpanChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kunciChecklist, _checklistSelesai.toList());
  }

  Future<void> _muatData() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    _aturProgres(true,
        nilai: 0.15, teks: 'Memuat daftar rak & konfigurasi SO Grand (15%)...');

    try {
      await _muatChecklist();
      final payload = <String, dynamic>{};
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }
      if (_rakFilterTerpilih.isNotEmpty && _rakFilterTerpilih != '0') {
        final rId = int.tryParse(_rakFilterTerpilih);
        if (rId != null && rId > 0) {
          payload['rak_id'] = rId;
        }
      }

      try {
        final resRak = await ApiClient.instance.aksi('rak_list', payload);
        _daftarRak = ((resRak['data'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}

      _aturProgres(true,
          nilai: 0.45,
          teks: 'Mengambil daftar produk per Rak dari server (45%)...');

      List<Map<String, dynamic>> list = [];
      double totalStok = 0;
      double totalAset = 0;

      try {
        final res = await ApiClient.instance.aksi('so_grand_daftar', payload);
        final rawList = (res['data'] as List?) ?? [];
        list = rawList
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        totalStok = (res['totalStokSistem'] as num?)?.toDouble() ?? 0;
        totalAset = (res['totalNilaiAset'] as num?)?.toDouble() ?? 0;
      } catch (_) {
        try {
          final resKat = await ApiClient.instance.aksi('katalog', payload);
          final rawKat =
              (resKat['produk'] as List?) ?? (resKat['data'] as List?) ?? [];
          for (final item in rawKat.whereType<Map>()) {
            final m = Map<String, dynamic>.from(item);
            final pId = (m['produkId'] as num?)?.toInt() ??
                (m['id'] as num?)?.toInt() ??
                0;
            if (pId <= 0) continue;
            final stok = (m['stokRak'] as num?)?.toDouble() ??
                (m['stokSistem'] as num?)?.toDouble() ??
                (m['stok'] as num?)?.toDouble() ??
                0;
            final hb = (m['hargaBeli'] as num?)?.toDouble() ??
                (m['harga_beli'] as num?)?.toDouble() ??
                (m['harga'] as num?)?.toDouble() ??
                0;
            final hj = (m['hargaJual'] as num?)?.toDouble() ??
                (m['harga_jual'] as num?)?.toDouble() ??
                (m['harga'] as num?)?.toDouble() ??
                0;
            final nilai = stok * hb;
            totalStok += stok;
            totalAset += nilai;
            list.add({
              'produkId': pId,
              'kode': '${m['kode'] ?? '-'}',
              'barcode': '${m['barcode'] ?? ''}',
              'nama': '${m['nama'] ?? '-'}',
              'kategori': '${m['kategori'] ?? m['jenis'] ?? 'Umum'}',
              'satuan': '${m['satuan'] ?? 'PCS'}',
              'rakId': (m['rakId'] as num?)?.toInt() ??
                  (m['rakUtamaId'] as num?)?.toInt(),
              'rakKode': '${m['rakKode'] ?? ''}',
              'rakNama':
                  '${m['rakNama'] ?? m['rakUtamaNama'] ?? 'Rak Belum Ditentukan'}',
              'stokRak': stok,
              'stokSistem': stok,
              'stokTotalProduk': (m['stokTotalProduk'] as num?)?.toDouble() ??
                  (m['stok'] as num?)?.toDouble() ??
                  stok,
              'hargaBeli': hb,
              'hargaJual': hj,
              'nilaiAset': nilai,
            });
          }
        } catch (_) {
          final cacheProduk =
              await CoreDb.instance.produkCache(keyword: '', limit: 100000);
          for (final p in cacheProduk) {
            final pId = (p['id'] as num?)?.toInt() ?? 0;
            if (pId <= 0) continue;
            final stok = (p['stok'] as num?)?.toDouble() ?? 0;
            final hb = (p['harga_beli'] as num?)?.toDouble() ?? 0;
            final hj = (p['harga_jual'] as num?)?.toDouble() ?? 0;
            final hbEfektif = hb > 0 ? hb : hj;
            final nilai = stok * hbEfektif;
            totalStok += stok;
            totalAset += nilai;
            list.add({
              'produkId': pId,
              'kode': '${p['kode'] ?? '-'}',
              'barcode': '${p['barcode'] ?? ''}',
              'nama': '${p['nama'] ?? '-'}',
              'kategori': '${p['kategori_nama'] ?? p['jenis_nama'] ?? 'Umum'}',
              'satuan': '${p['satuan_nama'] ?? 'PCS'}',
              'rakId': null,
              'rakKode': '',
              'rakNama': 'Rak Belum Ditentukan',
              'stokRak': stok,
              'stokSistem': stok,
              'stokTotalProduk': stok,
              'hargaBeli': hbEfektif,
              'hargaJual': hj,
              'nilaiAset': nilai,
            });
          }
        }
      }

      _aturProgres(true,
          nilai: 0.80,
          teks: 'Menyiapkan ${list.length} baris produk & rak (80%)...');

      final kategoriSet = <String>{};
      for (final item in list) {
        final kat = (item['kategori'] as String?)?.trim() ?? '';
        if (kat.isNotEmpty) kategoriSet.add(kat);

        final kBaris = _kunciBaris(item);
        if (!_controllersFisik.containsKey(kBaris)) {
          _controllersFisik[kBaris] = TextEditingController();
        }
        if (!_controllersKet.containsKey(kBaris)) {
          _controllersKet[kBaris] = TextEditingController();
        }
      }

      _aturProgres(true, nilai: 1.0, teks: 'Selesai memuat data (100%).');

      if (!mounted) return;
      setStateIfMounted(() {
        _semuaProduk = list;
        _totalStokSistem = totalStok;
        _totalNilaiAset = totalAset;
        _daftarKategori = kategoriSet.toList()..sort();
        _terapkanFilter();
      });
    } catch (e) {
      if (mounted) {
        setStateIfMounted(() => _pesanError = 'Gagal memuat SO Grand: $e');
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _memuat = false);
        Future.delayed(const Duration(milliseconds: 500), () {
          _aturProgres(false);
        });
      }
    }
  }

  void _terapkanFilter() {
    final kw = _cariController.text.trim().toLowerCase();
    setStateIfMounted(() {
      _filteredProduk = _semuaProduk.where((p) {
        final nama = (p['nama'] as String?)?.toLowerCase() ?? '';
        final kode = (p['kode'] as String?)?.toLowerCase() ?? '';
        final barcode = (p['barcode'] as String?)?.toLowerCase() ?? '';
        final kat = (p['kategori'] as String?) ?? '';
        final rakNama =
            (p['rakNama'] as String?)?.trim() ?? 'Rak Belum Ditentukan';
        final rakId = (p['rakId'] as num?)?.toInt();

        final cocokKw = kw.isEmpty ||
            nama.contains(kw) ||
            kode.contains(kw) ||
            barcode.contains(kw) ||
            rakNama.toLowerCase().contains(kw);
        final cocokKat =
            _kategoriTerpilih.isEmpty || kat == _kategoriTerpilih;

        bool cocokRak = true;
        if (_rakFilterTerpilih == '0') {
          cocokRak = rakId == null ||
              rakId <= 0 ||
              rakNama.toLowerCase().contains('belum ditentukan');
        } else if (_rakFilterTerpilih.isNotEmpty) {
          cocokRak = '$rakId' == _rakFilterTerpilih;
        }
        return cocokKw && cocokKat && cocokRak;
      }).toList();
    });
  }

  Future<void> _ubahChecklist(String kBaris, bool checked) async {
    setStateIfMounted(() {
      if (checked) {
        _checklistSelesai.add(kBaris);
      } else {
        _checklistSelesai.remove(kBaris);
      }
    });
    await _simpanChecklist();
  }

  /// Auto-save baris secara langsung ketika pengguna mengisi angka Stok Fisik
  /// (dengan debounce singkat 650ms atau seketika saat tekan Enter).
  void _jadwalkanSimpanBarisOtomatis(Map<String, dynamic> p,
      {bool langsung = false}) {
    final kBaris = _kunciBaris(p);
    _debounceAutoSave[kBaris]?.cancel();
    if (langsung) {
      _simpanSatuBarisOtomatis(p);
    } else {
      _debounceAutoSave[kBaris] = Timer(const Duration(milliseconds: 650), () {
        _simpanSatuBarisOtomatis(p);
      });
    }
  }

  Future<void> _simpanSatuBarisOtomatis(Map<String, dynamic> p) async {
    final kBaris = _kunciBaris(p);
    final pId = (p['produkId'] as num?)?.toInt() ?? 0;
    if (pId <= 0) return;
    final rId = (p['rakId'] as num?)?.toInt();
    final teksFisik = _controllersFisik[kBaris]?.text.trim() ?? '';
    if (teksFisik.isEmpty) return;

    final fisik = double.tryParse(teksFisik.replaceAll(',', '.'));
    if (fisik == null || fisik < 0) return;

    final ket = _controllersKet[kBaris]?.text.trim() ?? '';
    setStateIfMounted(() {
      _statusSimpanBaris[kBaris] = 'saving';
      _pesanSimpanBaris.remove(kBaris);
    });

    try {
      final payload = <String, dynamic>{
        'produk_id': pId,
        'produkId': pId,
        'stok_fisik': fisik,
        'stokFisik': fisik,
        'keterangan': ket.isEmpty ? 'Auto-Save SO Grand' : ket,
        if (rId != null && rId > 0) 'rak_id': rId,
        if (rId != null && rId > 0) 'rakId': rId,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      };
      final res =
          await ApiClient.instance.aksi('so_grand_simpan_baris', payload);
      final stokBaru = (res['stokFisik'] as num?)?.toDouble() ?? fisik;
      final stokTotalBaru =
          (res['stokTotalProduk'] as num?)?.toDouble() ?? stokBaru;
      if (!mounted) return;
      setStateIfMounted(() {
        p['stokRak'] = stokBaru;
        p['stokSistem'] = stokBaru;
        p['stokTotalProduk'] = stokTotalBaru;
        if (res['rakId'] != null) p['rakId'] = res['rakId'];
        if (res['rakNama'] != null && '${res['rakNama']}'.isNotEmpty) {
          p['rakNama'] = '${res['rakNama']}';
        }
        _statusSimpanBaris[kBaris] = 'saved';
        _checklistSelesai.add(kBaris);
      });
      await _simpanChecklist();
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _statusSimpanBaris[kBaris] = 'error';
        _pesanSimpanBaris[kBaris] = '$e';
      });
    }
  }

  Future<void> _simpanBatchEntry() async {
    final items = <Map<String, dynamic>>[];
    for (final p in _filteredProduk) {
      final kBaris = _kunciBaris(p);
      final pId = (p['produkId'] as num).toInt();
      final rId = (p['rakId'] as num?)?.toInt();
      final ctrl = _controllersFisik[kBaris];
      final teksFisik = ctrl?.text.trim() ?? '';
      if (teksFisik.isNotEmpty) {
        final fisik = double.tryParse(teksFisik.replaceAll(',', '.'));
        if (fisik != null && fisik >= 0) {
          items.add({
            'produkId': pId,
            'produk_id': pId,
            if (rId != null && rId > 0) 'rakId': rId,
            if (rId != null && rId > 0) 'rak_id': rId,
            'stokFisik': fisik,
            'stok_fisik': fisik,
            'keterangan': _controllersKet[kBaris]?.text.trim() ?? '',
            '_kBaris': kBaris,
          });
        }
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Belum ada stok fisik yang diisi pada baris tabel.')));
      return;
    }

    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan Entri SO Grand?'),
        content: Text(
            'Akan menyimpan penyesuaian stok per Rak untuk ${items.length} baris yang telah diisi fisik.\n\nStok per Rak dan stok total produk akan langsung diselaraskan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ya, Simpan Penyesuaian',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (konfirmasi != true) return;

    setStateIfMounted(() => _menyimpan = true);
    try {
      const ukuranChunk = 40;
      var totalDisimpan = 0;
      var totalDilewati = 0;

      for (var i = 0; i < items.length; i += ukuranChunk) {
        final akhir =
            (i + ukuranChunk < items.length) ? i + ukuranChunk : items.length;
        final chunk = items.sublist(i, akhir);
        final proporsi = akhir / items.length;
        _aturProgres(
          true,
          nilai: proporsi,
          teks:
              'Menyimpan entri fisik SO Grand: $akhir / ${items.length} baris (${(proporsi * 100).toStringAsFixed(0)}%)...',
        );

        final payload = <String, dynamic>{
          'items': chunk,
          'keterangan': 'Entry Cepat SO Grand per Rak',
        };
        final tokoId = Sesi.instance.idTokoTerpilih;
        if (tokoId != null && tokoId > 0) {
          payload['toko_id'] = tokoId;
        }

        final res =
            await ApiClient.instance.aksi('so_grand_simpan_batch', payload);
        totalDisimpan += (res['disimpan'] as num?)?.toInt() ?? chunk.length;
        totalDilewati += (res['dilewati'] as num?)?.toInt() ?? 0;

        for (final it in chunk) {
          final kb = '${it['_kBaris']}';
          _checklistSelesai.add(kb);
          _statusSimpanBaris[kb] = 'saved';
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Berhasil menyimpan $totalDisimpan item SO Grand${totalDilewati > 0 ? ' ($totalDilewati dilewati)' : ''}.')));

      await _simpanChecklist();
      await _muatData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan SO Grand: $e')));
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _menyimpan = false);
        _aturProgres(false);
      }
    }
  }

  Future<void> _unduhExcel() async {
    setStateIfMounted(() => _mengunduh = true);
    _aturProgres(true,
        nilai: 0.20,
        teks: 'Menyiapkan data SO Grand per Rak untuk diunduh (20%)...');
    try {
      final payload = <String, dynamic>{};
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }
      if (_rakFilterTerpilih.isNotEmpty && _rakFilterTerpilih != '0') {
        final rId = int.tryParse(_rakFilterTerpilih);
        if (rId != null && rId > 0) payload['rak_id'] = rId;
      }

      Uint8List bytes;
      String nama = 'SO-Grand-Per-Rak.xlsx';
      try {
        _aturProgres(true,
            nilai: 0.55,
            teks: 'Mengunduh berkas Excel SO Grand dari server (55%)...');
        final res =
            await ApiClient.instance.aksi('so_grand_download_excel', payload);
        final b64 = res['fileBase64'] as String?;
        if (b64 == null || b64.isEmpty) {
          throw Exception('Server tidak mengembalikan berkas SO Grand.');
        }
        bytes = base64Decode(b64);
        nama = '${res['namaFile'] ?? 'SO-Grand-Per-Rak.xlsx'}';
      } catch (_) {
        _aturProgres(true,
            nilai: 0.70,
            teks:
                'Menyusun berkas Excel lokal (${_filteredProduk.length} baris) (70%)...');
        final headersXls = <String>[
          'No',
          'Produk ID',
          'Kode Produk',
          'Barcode',
          'Nama Produk',
          'Rak',
          'Kategori',
          'Satuan',
          'Stok Rak Sistem',
          'Stok Fisik (Isi Hasil Hitung)',
          'Harga Beli',
          'Harga Jual',
          'Keterangan',
        ];
        final rowsXls = <List<Object?>>[];
        for (var i = 0; i < _filteredProduk.length; i++) {
          final p = _filteredProduk[i];
          final kBaris = _kunciBaris(p);
          final pId = (p['produkId'] as num?)?.toInt() ?? 0;
          final teksFisik = _controllersFisik[kBaris]?.text.trim() ?? '';
          final teksKet = _controllersKet[kBaris]?.text.trim() ?? '';
          rowsXls.add([
            i + 1,
            pId,
            '${p['kode'] ?? ''}',
            '${p['barcode'] ?? ''}',
            '${p['nama'] ?? ''}',
            '${p['rakNama'] ?? 'Rak Belum Ditentukan'}',
            '${p['kategori'] ?? ''}',
            '${p['satuan'] ?? 'PCS'}',
            (p['stokRak'] as num?)?.toDouble() ??
                (p['stokSistem'] as num?)?.toDouble() ??
                0,
            teksFisik.isNotEmpty
                ? (double.tryParse(teksFisik) ?? teksFisik)
                : '',
            (p['hargaBeli'] as num?)?.toDouble() ?? 0,
            (p['hargaJual'] as num?)?.toDouble() ?? 0,
            teksKet,
          ]);
        }
        bytes = buildSimpleXlsx(
          sheetName: 'SO Grand per Rak',
          headers: headersXls,
          rows: rowsXls,
        );
      }

      _aturProgres(true,
          nilai: 0.90, teks: 'Membuka dialog penyimpanan berkas (90%)...');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Lembar Kerja SO Grand Excel',
        fileName: nama,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      _aturProgres(true, nilai: 1.0, teks: 'Unduhan Excel selesai (100%).');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Form SO Grand disimpan: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengunduh SO Grand Excel: $e')));
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _mengunduh = false);
        Future.delayed(const Duration(milliseconds: 500), () {
          _aturProgres(false);
        });
      }
    }
  }

  Future<void> _unggahExcel() async {
    final hasilPilih = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (hasilPilih == null || hasilPilih.files.isEmpty) return;
    final bytes = hasilPilih.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setStateIfMounted(() => _mengunggah = true);
    _aturProgres(true,
        nilai: 0.25,
        teks:
            'Mengenkode berkas Excel (${(bytes.length / 1024).toStringAsFixed(1)} KB) (25%)...');
    try {
      final payload = <String, dynamic>{
        'file_base64': base64Encode(bytes),
        'keterangan': 'Unggah Excel SO Grand per Rak',
      };
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }
      if (_rakFilterTerpilih.isNotEmpty && _rakFilterTerpilih != '0') {
        final rId = int.tryParse(_rakFilterTerpilih);
        if (rId != null && rId > 0) payload['rak_id'] = rId;
      }

      _aturProgres(true,
          nilai: 0.65,
          teks:
              'Mengunggah & memproses penyesuaian stok per Rak di server (65%)...');
      final res =
          await ApiClient.instance.aksi('so_grand_upload_excel', payload);
      _aturProgres(true,
          nilai: 1.0, teks: 'Pemrosesan unggah Excel selesai (100%).');

      final disimpan = (res['disimpan'] as num?)?.toInt() ?? 0;
      final dilewati = (res['dilewati'] as num?)?.toInt() ?? 0;
      final masalahRaw = res['masalah'];
      final masalahList = masalahRaw is List
          ? masalahRaw
              .whereType<Map>()
              .map((b) => Map<String, dynamic>.from(b))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      if (dilewati > 0 || masalahList.isNotEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hasil Unggah SO Grand'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tersimpan: $disimpan baris\nDilewati / Gagal: $dilewati baris',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (masalahList.isNotEmpty) ...[
                      const Text('Rincian baris bermasalah:',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      ...masalahList.take(20).map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• Baris ${m['baris'] ?? '-'}: [${m['produk'] ?? '-'}] — ${m['alasan'] ?? 'Gagal'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'SO Grand berhasil disimpan: $disimpan baris tersinkronisasi.')));
      }

      await _muatData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memproses unggah SO Grand: $e')));
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _mengunggah = false);
        _aturProgres(false);
      }
    }
  }

  /// Cetak KKSO PDF secara bertahap (chunked per 250 baris) dengan progress bar
  /// agar UI tidak membeku saat mencetak ribuan produk.
  Future<void> _cetakPdf() async {
    if (_mencetak || _filteredProduk.isEmpty) return;
    setStateIfMounted(() => _mencetak = true);
    try {
      final doc = pw.Document();
      final items = _filteredProduk;
      final total = items.length;
      final tokoNama = Sesi.instance.tokoNama.isNotEmpty
          ? Sesi.instance.tokoNama
          : 'Toko Al-Bahjah';

      _aturProgres(true,
          nilai: 0.05,
          teks: 'Menyiapkan dokumen KKSO PDF ($total baris) (5%)...');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const ukuranHalamanChunk = 250;
      for (var awal = 0; awal < total; awal += ukuranHalamanChunk) {
        final akhir =
            (awal + ukuranHalamanChunk < total) ? awal + ukuranHalamanChunk : total;
        final potongan = items.sublist(awal, akhir);
        final proporsi = akhir / total;
        _aturProgres(
          true,
          nilai: (proporsi * 0.85).clamp(0.05, 0.90),
          teks:
              'Menyusun halaman PDF KKSO: $akhir / $total produk (${(proporsi * 100).toStringAsFixed(0)}%)...',
        );
        // Beri kesempatan event loop UI merender progress bar
        await Future<void>.delayed(const Duration(milliseconds: 16));

        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (ctx) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        'KERTAS KERJA STOK OPNAME (KKSO) - SO GRAND PER RAK',
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        'Toko: $tokoNama · Baris ${awal + 1}–$akhir dari $total Item',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Text(
                    'Tanggal Cetak: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          build: (ctx) => [
            pw.TableHelper.fromTextArray(
              headers: [
                'NO',
                'KODE',
                'BARCODE',
                'NAMA BARANG',
                'RAK',
                'KATEGORI',
                'SATUAN',
                'STOK RAK',
                'STOK FISIK',
                'SELISIH',
                'PARAF',
                'CATATAN'
              ],
              data: List.generate(potongan.length, (i) {
                final idx = awal + i + 1;
                final r = potongan[i];
                final stokRak = (r['stokRak'] as num?)?.toDouble() ??
                    (r['stokSistem'] as num?)?.toDouble() ??
                    0;
                return [
                  '$idx',
                  '${r['kode'] ?? ''}',
                  '${r['barcode'] ?? ''}',
                  '${r['nama'] ?? ''}',
                  '${r['rakNama'] ?? 'Rak Belum Ditentukan'}',
                  '${r['kategori'] ?? '-'}',
                  '${r['satuan'] ?? '-'}',
                  _formatAngka.format(stokRak),
                  '',
                  '',
                  '',
                  '',
                ];
              }),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerStyle:
                  pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ));
      }

      _aturProgres(true,
          nilai: 0.95, teks: 'Merender & membuka pratinjau cetak PDF (95%)...');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final pdfBytes = await doc.save();
      _aturProgres(true, nilai: 1.0, teks: 'Siap mencetak PDF (100%).');

      await Printing.layoutPdf(
          onLayout: (_) async => pdfBytes, name: 'Lembar-SO-Grand-Per-Rak.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mencetak KKSO PDF: $e')));
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _mencetak = false);
        _aturProgres(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalProduk = _semuaProduk.length;
    final jumlahDicek =
        _semuaProduk.where((p) => _checklistSelesai.contains(_kunciBaris(p))).length;
    final persenSelesai =
        totalProduk > 0 ? (jumlahDicek / totalProduk * 100).clamp(0, 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Baris Aksi Atas + Filter Rak & Kategori
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    child: TextField(
                      controller: _cariController,
                      decoration: InputDecoration(
                        hintText: 'Cari nama / kode / barcode / rak...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => _terapkanFilter(),
                    ),
                  ),
                  DropdownButton<String>(
                    value:
                        _rakFilterTerpilih.isEmpty ? null : _rakFilterTerpilih,
                    hint: const Text('Semua Rak'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Semua Rak')),
                      const DropdownMenuItem(
                          value: '0', child: Text('Rak Belum Ditentukan')),
                      ..._daftarRak.map((r) => DropdownMenuItem(
                            value: '${r['id']}',
                            child: Text(
                                '${r['nama'] ?? 'Rak'}${('${r['kode'] ?? ''}').isNotEmpty ? ' [${r['kode']}]' : ''}'),
                          )),
                    ],
                    onChanged: (val) {
                      setStateIfMounted(() => _rakFilterTerpilih = val ?? '');
                      _terapkanFilter();
                    },
                  ),
                  if (_daftarKategori.isNotEmpty)
                    DropdownButton<String>(
                      value: _kategoriTerpilih.isEmpty
                          ? null
                          : _kategoriTerpilih,
                      hint: const Text('Semua Kategori'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Semua Kategori')),
                        ..._daftarKategori.map(
                            (k) => DropdownMenuItem(value: k, child: Text(k))),
                      ],
                      onChanged: (val) {
                        setStateIfMounted(() => _kategoriTerpilih = val ?? '');
                        _terapkanFilter();
                      },
                    ),
                ],
              ),
            ),
            AksiBarisMenu(
              tooltip: 'Aksi SO Grand',
              aksi: [
                AksiBaris(
                  ikon: Icons.refresh,
                  label: 'Muat Ulang Data',
                  onTap: _memuat ? null : _muatData,
                ),
                AksiBaris(
                  ikon: Icons.save_outlined,
                  label: 'Simpan Entri Fisik Tabel',
                  onTap: _menyimpan ? null : _simpanBatchEntry,
                ),
                AksiBaris(
                  ikon: Icons.download_outlined,
                  label: 'Unduh Excel SO Grand (100% Produk)',
                  onTap: _mengunduh ? null : _unduhExcel,
                ),
                AksiBaris(
                  ikon: Icons.upload_file_outlined,
                  label: 'Unggah Excel Hasil Fisik',
                  onTap: _mengunggah ? null : _unggahExcel,
                ),
                AksiBaris(
                  ikon: Icons.picture_as_pdf_outlined,
                  label: 'Cetak KKSO (Kertas Kerja SO PDF)',
                  onTap: (_filteredProduk.isEmpty || _mencetak)
                      ? null
                      : _cetakPdf,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Progress Bar Bertahap untuk Cetak PDF, Download/Upload Excel, Simpan, & Muat Ulang
        if (_tampilProgres)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.primary),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _teksProgres,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${(_nilaiProgres * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _nilaiProgres,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

        // Banner Penjelasan SO Grand per Rak & Auto-Save Centang Hijau
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            border: Border.all(color: const Color(0xFF86EFAC)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      color: Color(0xFF15803D), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SO Grand per Produk & Rak — Auto-Save Instan dengan Indikator Centang Hijau',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Menampilkan jumlah stok produk per Rak (bukan sekadar total gabungan). '
                'Saat Anda mengisi kolom Input Stok Fisik, sistem otomatis menyimpan ke server dan menampilkan tanda centang hijau (✓) saat berhasil, '
                'serta menyelaraskan stok Rak dengan total stok produk secara otomatis.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Kartu Ringkasan & Progres (Klik untuk rincian + Excel & PDF)
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: 0,
                color: AppColors.latarLembut(AppColors.primary),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => tampilkanRincianKlikDialog(
                    context,
                    judul: 'Rincian Total Baris Produk & Rak SO Grand',
                    subjudul:
                        'Total ${_semuaProduk.length} baris produk-rak aktif di toko',
                    kolom: const [
                      'Kode',
                      'Barcode',
                      'Nama Produk',
                      'Rak',
                      'Kategori',
                      'Satuan',
                      'Stok Rak',
                      'Status Cek',
                    ],
                    baris: _semuaProduk
                        .map((p) => <Object?>[
                              p['kode'] ?? '-',
                              p['barcode'] ?? '-',
                              p['nama'] ?? '-',
                              p['rakNama'] ?? 'Rak Belum Ditentukan',
                              p['kategori'] ?? '-',
                              p['satuan'] ?? '-',
                              _formatAngka.format(
                                  p['stokRak'] ?? p['stokSistem'] ?? 0),
                              _checklistSelesai.contains(_kunciBaris(p))
                                  ? 'Sudah Dicek'
                                  : 'Belum Dicek',
                            ])
                        .toList(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Produk & Rak Aktif',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatAngka.format(totalProduk)} Baris',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Menampilkan ${_filteredProduk.length} baris · Klik rincian',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                elevation: 0,
                color: AppColors.latarLembut(AppColors.warning),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => tampilkanRincianKlikDialog(
                    context,
                    judul: 'Rincian Stok Rak & Nilai Aset SO Grand',
                    subjudul:
                        'Total Stok: ${_formatAngka.format(_totalStokSistem)} | Nilai Aset: ${_formatRupiah.format(_totalNilaiAset)}',
                    kolom: const [
                      'Kode',
                      'Nama Produk',
                      'Rak',
                      'Kategori',
                      'Stok Rak',
                      'Harga Beli',
                      'Nilai Persediaan',
                    ],
                    baris: _semuaProduk.map((p) {
                      final stok = (p['stokRak'] as num?)?.toDouble() ??
                          (p['stokSistem'] as num?)?.toDouble() ??
                          0;
                      final hb = (p['hargaBeli'] as num?)?.toDouble() ?? 0;
                      return <Object?>[
                        p['kode'] ?? '-',
                        p['nama'] ?? '-',
                        p['rakNama'] ?? 'Rak Belum Ditentukan',
                        p['kategori'] ?? '-',
                        _formatAngka.format(stok),
                        _formatRupiah.format(hb),
                        _formatRupiah.format(stok * hb),
                      ];
                    }).toList(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Stok Sistem (Seluruh Rak)',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          _formatAngka.format(_totalStokSistem),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Estimasi Nilai: ${_formatRupiah.format(_totalNilaiAset)}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                elevation: 0,
                color: AppColors.latarLembut(AppColors.success),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final sudah = _semuaProduk
                        .where((p) => _checklistSelesai.contains(_kunciBaris(p)))
                        .toList();
                    tampilkanRincianKlikDialog(
                      context,
                      judul: 'Rincian Progres Penghitungan Fisik SO Grand',
                      subjudul:
                          '$jumlahDicek dari $totalProduk baris produk-rak sudah dicek (${persenSelesai.toStringAsFixed(1)}%)',
                      kolom: const [
                        'Kode',
                        'Nama Produk',
                        'Rak',
                        'Kategori',
                        'Stok Rak',
                        'Status',
                      ],
                      baris: sudah
                          .map((p) => <Object?>[
                                p['kode'] ?? '-',
                                p['nama'] ?? '-',
                                p['rakNama'] ?? 'Rak Belum Ditentukan',
                                p['kategori'] ?? '-',
                                _formatAngka.format(
                                    p['stokRak'] ?? p['stokSistem'] ?? 0),
                                'Sudah Dicek',
                              ])
                          .toList(),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Progres Penghitungan Fisik',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          '$jumlahDicek / $totalProduk (${persenSelesai.toStringAsFixed(1)}%)',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: totalProduk > 0
                              ? (jumlahDicek / totalProduk)
                              : 0,
                          backgroundColor: Colors.grey.shade200,
                          color: AppColors.success,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_pesanError != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: AppColors.latarLembut(AppColors.danger),
                borderRadius: BorderRadius.circular(8)),
            child: Text(_pesanError!,
                style: const TextStyle(color: AppColors.danger)),
          ),

        if (_memuat)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!_memuat && _filteredProduk.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
                child: Text('Tidak ada produk yang cocok dengan pencarian.')),
          ),

        // Tabel Entry SO Grand per Produk & Rak
        if (!_memuat && _filteredProduk.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daftar Barang & Kolom Entry Fisik per Rak (${_filteredProduk.length} Baris)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Simpan Entri Fisik Tabel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _menyimpan ? null : _simpanBatchEntry,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppDataTable(
            minWidth: 1280,
            emptyText: 'Belum ada produk.',
            columns: const [
              AppTableColumn('Cek', flex: 1),
              AppTableColumn('Kode / Barcode', flex: 2),
              AppTableColumn('Nama Produk', flex: 4),
              AppTableColumn('Rak', flex: 2),
              AppTableColumn('Kategori', flex: 2),
              AppTableColumn('Satuan', flex: 1),
              AppTableColumn('Stok Rak', flex: 2, align: TextAlign.right),
              AppTableColumn('Input Stok Fisik',
                  flex: 2, align: TextAlign.center),
              AppTableColumn('Catatan / Keterangan', flex: 3),
            ],
            rows: _filteredProduk.map((p) {
              final kBaris = _kunciBaris(p);
              final dicek = _checklistSelesai.contains(kBaris);
              final ctrlFisik = _controllersFisik.putIfAbsent(
                  kBaris, () => TextEditingController());
              final ctrlKet = _controllersKet.putIfAbsent(
                  kBaris, () => TextEditingController());
              final stokRak = (p['stokRak'] as num?)?.toDouble() ??
                  (p['stokSistem'] as num?)?.toDouble() ??
                  0.0;
              final rakNama =
                  '${p['rakNama'] ?? 'Rak Belum Ditentukan'}'.trim();
              final belumAdaRak =
                  rakNama.isEmpty || rakNama.toLowerCase().contains('belum');
              final statusBaris = _statusSimpanBaris[kBaris];

              return AppTableRowData(cells: [
                AppTableCell(
                  flex: 1,
                  child: Checkbox(
                    value: dicek,
                    onChanged: (v) => _ubahChecklist(kBaris, v == true),
                  ),
                ),
                AppTableCell.text(
                  '${p['kode'] ?? ''}${('${p['barcode'] ?? ''}').isEmpty ? '' : '\n${p['barcode']}'}',
                  flex: 2,
                  maxLines: 2,
                ),
                AppTableCell.text('${p['nama'] ?? ''}', flex: 4, maxLines: 2),
                AppTableCell(
                  flex: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.latarLembut(
                          belumAdaRak ? AppColors.warning : AppColors.primary),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      belumAdaRak ? 'Rak Belum Ditentukan' : rakNama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color:
                            belumAdaRak ? AppColors.warning : AppColors.primary,
                      ),
                    ),
                  ),
                ),
                AppTableCell.text('${p['kategori'] ?? '-'}', flex: 2),
                AppTableCell.text('${p['satuan'] ?? '-'}', flex: 1),
                AppTableCell.text(
                  _formatAngka.format(stokRak),
                  flex: 2,
                  align: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                AppTableCell(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrlFisik,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              hintText: '0',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              enabledBorder: statusBaris == 'saved'
                                  ? OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Colors.green, width: 1.5),
                                    )
                                  : null,
                            ),
                            onChanged: (teks) {
                              final val =
                                  double.tryParse(teks.replaceAll(',', '.'));
                              if (val != null) {
                                _ubahChecklist(kBaris, true);
                                _jadwalkanSimpanBarisOtomatis(p);
                              }
                            },
                            onSubmitted: (_) {
                              _jadwalkanSimpanBarisOtomatis(p, langsung: true);
                            },
                          ),
                        ),
                        if (statusBaris == 'saving') ...[
                          const SizedBox(width: 6),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ] else if (statusBaris == 'saved') ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'Tersimpan otomatis ke server',
                            child: Icon(Icons.check_circle,
                                color: Colors.green, size: 20),
                          ),
                        ] else if (statusBaris == 'error') ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                _pesanSimpanBaris[kBaris] ?? 'Gagal menyimpan',
                            child: const Icon(Icons.error_outline,
                                color: Colors.red, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                AppTableCell(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: ctrlKet,
                      decoration: InputDecoration(
                        hintText: 'Alasan / paraf...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      onSubmitted: (_) {
                        if (ctrlFisik.text.trim().isNotEmpty) {
                          _jadwalkanSimpanBarisOtomatis(p, langsung: true);
                        }
                      },
                    ),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ],
      ],
    );
  }
}
