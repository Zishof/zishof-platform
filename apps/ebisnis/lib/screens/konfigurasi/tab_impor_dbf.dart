import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import 'dbf_parser.dart';

/// <h3>Tab "Impor DBF" (Konfigurasi) -- migrasi master legacy INVENTORY CONTROL.</h3>
///
/// HANYA tampil saat login sebagai Pemilik Usaha Sales/Inventory (gerbang di
/// konfigurasi_screen; server menegakkan ulang di `si_import_legacy`).
///
/// Sumber: file ZIP arsip legacy ATAU folder (desktop) berisi berkas FoxPro
/// (mis. `C:\Users\...\Documents\5-Inventory--\5-Inventory`). HANYA berkas
/// `.DBF` yang dibaca -- CDX/EXE/BAT/dll diabaikan. Master serta transaksi
/// BELI/JUAL dikenali; DBF lain tetap ditampilkan sebagai "dilewati".
///
/// Urutan impor otomatis: Supplier -> Customer -> Sales -> Barang ->
/// Harga Beli -> Harga Jual -> Pembelian -> Penjualan (transaksi me-resolve
/// master supplier/customer/produk yang sudah diimpor lebih dahulu).
/// Idempoten: menjalankan ulang tidak menggandakan data (upsert by kode legacy);
/// record existing tidak ditimpa (hanya field kosong diisi).
class TabImporDbf extends StatefulWidget {
  const TabImporDbf({super.key});

  @override
  State<TabImporDbf> createState() => _TabImporDbfState();
}

class _BerkasDbf {
  final String nama;
  final String? jenis; // null = tidak dikenal
  final DbfTabel? tabel;
  final String? errorParse;
  bool dipilih;
  String hasil = '';
  _BerkasDbf(this.nama, this.jenis, this.tabel, this.errorParse)
      : dipilih = jenis != null;
}

class _TabImporDbfState extends State<TabImporDbf> {
  String _sumber = '';
  List<_BerkasDbf> _berkas = [];
  bool _memindai = false;
  bool _mengimpor = false;
  bool _opnameAwal = true;
  double _progres = 0;
  String _statusProgres = '';
  final List<String> _exceptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pindaiFolderBawaan());
  }

  Future<void> _pindaiFolderBawaan() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    final home = Platform.environment['USERPROFILE'];
    if (home == null || home.trim().isEmpty) return;
    final kandidat = <String>[
      '$home\\Downloads\\5-Inventory--\\5-Inventory',
      '$home\\Downloads\\5-Inventory--',
    ];
    for (final lokasi in kandidat) {
      if (await Directory(lokasi).exists()) {
        await _bacaFolder(lokasi, otomatis: true);
        return;
      }
    }
  }

  Future<void> _pilihZip() async {
    final pilih = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pilih arsip ZIP berisi berkas DBF legacy',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true);
    if (pilih == null || pilih.files.isEmpty) return;
    final f = pilih.files.first;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    setStateIfMounted(() {
      _memindai = true;
      _sumber = 'ZIP: ${f.name}';
      _berkas = [];
      _exceptions.clear();
    });
    try {
      final arsip = ZipDecoder().decodeBytes(bytes);
      final hasil = <_BerkasDbf>[];
      for (final entry in arsip) {
        if (!entry.isFile) continue;
        final nama = entry.name.split(RegExp(r'[\\/]+')).last;
        if (!nama.toLowerCase().endsWith('.dbf')) continue; // hanya DBF dibaca
        hasil.add(_parse(nama, Uint8List.fromList(entry.content as List<int>)));
      }
      setStateIfMounted(() => _berkas = _urutkan(hasil));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membaca ZIP: $e')));
      }
    } finally {
      setStateIfMounted(() => _memindai = false);
    }
  }

  Future<void> _pilihFolder() async {
    final dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Pilih folder berisi berkas DBF legacy');
    if (dir == null) return;
    await _bacaFolder(dir);
  }

  Future<void> _bacaFolder(String dir, {bool otomatis = false}) async {
    setStateIfMounted(() {
      _memindai = true;
      _sumber =
          '${otomatis ? 'Folder bawaan terdeteksi otomatis' : 'Folder'}: $dir';
      _berkas = [];
      _exceptions.clear();
    });
    try {
      final hasil = <_BerkasDbf>[];
      await for (final ent in Directory(dir).list()) {
        if (ent is! File) continue;
        final nama = ent.uri.pathSegments.last;
        if (!nama.toLowerCase().endsWith('.dbf')) continue; // hanya DBF dibaca
        hasil.add(_parse(nama, await ent.readAsBytes()));
      }
      setStateIfMounted(() => _berkas = _urutkan(hasil));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membaca folder: $e')));
      }
    } finally {
      setStateIfMounted(() => _memindai = false);
    }
  }

  _BerkasDbf _parse(String nama, Uint8List bytes) {
    final jenis = PetaDbfLegacy.jenisDariNamaFile(nama);
    if (jenis == null) return _BerkasDbf(nama, null, null, null);
    try {
      return _BerkasDbf(nama, jenis, DbfParser.parse(nama, bytes), null);
    } catch (e) {
      return _BerkasDbf(nama, jenis, null, e.toString());
    }
  }

  List<_BerkasDbf> _urutkan(List<_BerkasDbf> daftar) {
    daftar.sort((a, b) {
      final ia =
          a.jenis == null ? 999 : PetaDbfLegacy.urutanImpor.indexOf(a.jenis!);
      final ib =
          b.jenis == null ? 999 : PetaDbfLegacy.urutanImpor.indexOf(b.jenis!);
      return ia != ib ? ia.compareTo(ib) : a.nama.compareTo(b.nama);
    });
    return daftar;
  }

  Future<void> _impor() async {
    final antre = _berkas
        .where((b) => b.dipilih && b.jenis != null && b.tabel != null)
        .toList();
    if (antre.isEmpty) return;
    setStateIfMounted(() {
      _mengimpor = true;
      _progres = 0;
      _exceptions.clear();
      for (final b in _berkas) {
        b.hasil = '';
      }
    });
    var selesai = 0;
    try {
      for (final b in antre) {
        final jenis = b.jenis!;
        final barisNormal = <Map<String, dynamic>>[];
        var dilewatiKlien = 0;
        for (final r in b.tabel!.rows) {
          final n = PetaDbfLegacy.normalisasi(jenis, r);
          if (n == null) {
            dilewatiKlien++;
          } else {
            barisNormal.add(n);
          }
        }
        var dibuat = 0, diperbarui = 0, dilewati = dilewatiKlien, gagal = 0;
        for (var i = 0; i < barisNormal.length; i += 400) {
          final batch = barisNormal.sublist(
              i, i + 400 > barisNormal.length ? barisNormal.length : i + 400);
          setStateIfMounted(() {
            _statusProgres =
                '${PetaDbfLegacy.labelJenis[jenis]}: ${i + batch.length}/${barisNormal.length} baris...';
          });
          final hasil = await ApiClient.instance.aksi('si_import_legacy', {
            'jenis': jenis,
            'rows': batch,
            'buat_opname_awal': _opnameAwal,
          });
          dibuat += (hasil['dibuat'] as num?)?.toInt() ?? 0;
          diperbarui += (hasil['diperbarui'] as num?)?.toInt() ?? 0;
          dilewati += (hasil['dilewati'] as num?)?.toInt() ?? 0;
          gagal += (hasil['gagal'] as num?)?.toInt() ?? 0;
          for (final ex in ((hasil['exceptions'] as List?) ?? [])) {
            if (_exceptions.length < 100) _exceptions.add('$ex');
          }
        }
        b.hasil =
            'dibuat $dibuat · diperbarui $diperbarui · dilewati $dilewati · gagal $gagal';
        selesai++;
        setStateIfMounted(() => _progres = selesai / antre.length);
      }
      setStateIfMounted(() => _statusProgres = 'Impor selesai.');
    } catch (e) {
      setStateIfMounted(() => _statusProgres = 'Impor terhenti: $e');
    } finally {
      setStateIfMounted(() => _mengimpor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppFormSection(
          judul: 'Impor Data Legacy (DBF)',
          children: [
            Text(
                'Migrasi master dari aplikasi lama INVENTORY CONTROL (FoxPro) ke toko ini. '
                'Pilih arsip ZIP atau folder legacy (mis. folder "5-Inventory") -- HANYA berkas '
                '.DBF yang dibaca; berkas lain diabaikan. Berkas dikenal: SUPPLIER, CUSTOMER, '
                'SALES, STOK, masterbl, masterjl, BELI, dan JUAL. Folder bawaan '
                'Downloads\\5-Inventory-- dipindai otomatis pada Desktop. Aman dijalankan '
                'ulang (tidak menggandakan '
                'data; data yang sudah ada tidak ditimpa).',
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(
                onPressed: _memindai || _mengimpor ? null : _pilihZip,
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Pilih File ZIP'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0),
              ),
              OutlinedButton.icon(
                onPressed:
                    (!desktop || _memindai || _mengimpor) ? null : _pilihFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(
                    desktop ? 'Pilih Folder' : 'Pilih Folder (khusus Desktop)'),
              ),
            ]),
            if (_sumber.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Sumber: $_sumber',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
            if (_memindai) const LinearProgressIndicator(),
          ],
        ),
        if (_berkas.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppFormSection(
            judul: 'Berkas DBF Terdeteksi',
            children: [
              AppFormSwitchTile(
                title: 'Jadikan saldo STOK legacy sebagai Stok Opname awal',
                subtitle:
                    'Hanya untuk barang BARU: saldo AWAL+MASUK-KELUAR dicatat lewat ledger opname "Migrasi DBF" (bukan menimpa stok berjalan).',
                value: _opnameAwal,
                onChanged: _mengimpor
                    ? null
                    : (v) => setStateIfMounted(() => _opnameAwal = v),
              ),
              for (final b in _berkas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Checkbox(
                      value: b.dipilih,
                      onChanged: b.jenis == null ||
                              b.tabel == null ||
                              _mengimpor
                          ? null
                          : (v) =>
                              setStateIfMounted(() => b.dipilih = v == true),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              b.jenis == null
                                  ? '${b.nama} — dilewati (bukan master yang dikenal)'
                                  : '${PetaDbfLegacy.labelJenis[b.jenis]} — ${b.nama}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: b.jenis == null
                                      ? AppColors.textSecondaryOf(context)
                                      : AppColors.textPrimaryOf(context))),
                          Text(
                              b.errorParse != null
                                  ? 'GAGAL BACA: ${b.errorParse}'
                                  : b.tabel != null
                                      ? '${b.tabel!.rows.length} baris'
                                          '${b.hasil.isNotEmpty ? ' → ${b.hasil}' : ''}'
                                      : '',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: b.errorParse != null
                                      ? AppColors.danger
                                      : AppColors.textSecondaryOf(context))),
                        ],
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
              if (_mengimpor) ...[
                LinearProgressIndicator(value: _progres == 0 ? null : _progres),
                const SizedBox(height: 6),
              ],
              if (_statusProgres.isNotEmpty)
                Text(_statusProgres,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _mengimpor ? null : _impor,
                icon: _mengimpor
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Impor ke Toko Ini'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12)),
              ),
            ],
          ),
        ],
        if (_exceptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppFormSection(
            judul: 'Baris Bermasalah (${_exceptions.length})',
            children: [
              for (final e in _exceptions.take(50))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(e,
                      style: TextStyle(fontSize: 11, color: AppColors.danger)),
                ),
              if (_exceptions.length > 50)
                Text('... dan ${_exceptions.length - 50} lainnya',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryOf(context))),
            ],
          ),
        ],
      ],
    );
  }
}
