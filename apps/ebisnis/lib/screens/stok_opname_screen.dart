import 'dart:convert';
import 'dart:io';

import 'package:core_hw/core_hw.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';

final _formatAngka = NumberFormat.decimalPattern('id_ID');
final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar Stok Opname (padanan stokopname.html/stokopname-renderer.js Electron)
/// -- 3 sub-tab: Kartu Mutasi Stok (dasbor), Input Opname (satu produk per
/// simpan), SO by Scan (antrean batch -- scan banyak produk berturut-turut,
/// baru disimpan SEMUA sekaligus lewat tombol "Simpan Semua", padanan mode
/// cepat versi Electron utk opname banyak barang tanpa menunggu round-trip
/// server tiap satu scan). Beda dari Electron: kamera di sini NATIVE
/// (mobile_scanner/MLKit lewat core_hw.BarcodeScannerScreen), bukan
/// Html5Qrcode berbasis web -- pengalaman scan harusnya lebih responsif.
class StokOpnameScreen extends StatefulWidget {
  const StokOpnameScreen({super.key});

  @override
  State<StokOpnameScreen> createState() => _StokOpnameScreenState();
}

class _StokOpnameScreenState extends State<StokOpnameScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(_saatTabBerubah);
  }

  void _saatTabBerubah() {
    if (!_tab.indexIsChanging && mounted) setStateIfMounted(() {});
  }

  @override
  void dispose() {
    _tab.removeListener(_saatTabBerubah);
    _tab.dispose();
    super.dispose();
  }

  /// "Unduh Excel" (gap-closure, padanan tombol yg sudah ada di JSP
  /// `kantin/stok/index.jsp` -- lihat JavaDoc server `KantinHelper.soEksporExcel`).
  /// BEDA dari riwayat hari ini yg tampil di tab Input Opname -- ini SELURUH
  /// riwayat toko, bukan cuma hari ini, supaya unduhan berguna sbg arsip.
  Future<void> _eksporExcel() async {
    try {
      final hasil = await ApiClient.instance.aksi('so_ekspor_excel', {});
      final b64 = hasil['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan berkas.');
      }
      final bytes = base64Decode(b64);
      final namaFile = (hasil['namaFile'] as String?) ?? 'StokOpname.xlsx';
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan Stok Opname Excel',
          fileName: namaFile,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['xlsx']);
      if (path == null) return;
      // Desktop: saveFile hanya mengembalikan path (belum menulis) -- mobile
      // sudah menulis via `bytes`, tulis ulang di sini idempoten (byte sama)
      // supaya satu jalur kode bekerja di kedua platform (pola sama produk_screen.dart).
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Stok Opname disimpan: $path')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    }
  }

  /// "Unggah Excel" (gap-closure) -- SENGAJA insert-only (tiap baris file
  /// selalu jadi catatan baru lewat `so_impor_excel`/`StokOpnameScanUtil.simpanOpname`
  /// server, TIDAK PERNAH meng-update baris lama), TANPA layar tinjau terpisah
  /// (beda dari Impor Excel Produk) krn tak ada risiko "menimpa data lama
  /// diam-diam" yg perlu ditinjau dulu -- konsisten dgn Electron/JSP.
  Future<void> _unggahExcel() async {
    try {
      final hasilPilih = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      if (hasilPilih == null ||
          hasilPilih.files.isEmpty ||
          hasilPilih.files.first.bytes == null) {
        return;
      }
      final bytes = hasilPilih.files.first.bytes!;
      final hasil = await ApiClient.instance
          .aksi('so_impor_excel', {'file_base64': base64Encode(bytes)});
      final disimpan = (hasil['disimpan'] as num?)?.toInt() ?? 0;
      final dilewati = (hasil['dilewati'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Tersimpan $disimpan baris${dilewati > 0 ? ', dilewati $dilewati baris (tidak lengkap/gagal)' : ''}.')));
      setStateIfMounted(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunggah: $e')));
      }
    }
  }

  /// "Cetak PDF" (gap-closure) -- riwayat HARI INI (sama cakupan dgn kartu
  /// "Progres Opname Hari Ini"/tab Input Opname), dibangun client-side lewat
  /// paket `pdf`/`printing` (pola sama `tab_mutasi_tabungan.dart`).
  Future<void> _cetakPdf() async {
    try {
      final hasil = await ApiClient.instance.aksi('so_riwayat', {'limit': 200});
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tidak ada data untuk dicetak.')));
        }
        return;
      }
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: const PdfPageFormat(842, 595.2, marginAll: 24),
          header: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Riwayat Stok Opname Hari Ini',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
              ]),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: const [
                'Waktu Opname',
                'Produk',
                'Stok Sistem',
                'Stok Fisik',
                'Selisih',
                'Keterangan'
              ],
              data: data.map((r) {
                final selisih = (r['selisih'] as num?)?.toDouble() ?? 0;
                final kode = (r['kode'] as String?)?.isNotEmpty == true
                    ? ' [${r['kode']}]'
                    : '';
                return [
                  '${r['waktu'] ?? ''}',
                  '${r['nama'] ?? ''}$kode',
                  '${r['stokSistem'] ?? 0}',
                  '${r['stokFisik'] ?? 0}',
                  '${selisih >= 0 ? '+' : ''}$selisih',
                  '${r['keterangan'] ?? ''}',
                ];
              }).toList(),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
          onLayout: (_) async => doc.save(), name: 'Stok_Opname.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mencetak: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tombolAksi = <Widget>[
      if (Sesi.instance.bolehKelola) ...[
        HeaderActionButton(
          icon: Icons.download_outlined,
          label: 'Unduh Excel',
          onPressed: _eksporExcel,
        ),
        HeaderActionButton(
          icon: Icons.upload_file_outlined,
          label: 'Unggah Excel',
          onPressed: _unggahExcel,
        ),
        HeaderActionButton(
          icon: Icons.picture_as_pdf_outlined,
          label: 'Cetak PDF',
          onPressed: _cetakPdf,
        ),
      ],
    ];
    return AppShell(
      menuAktif: MenuEBisnis.stokOpname,
      judul: 'Stok Opname',
      subjudul: 'Kartu mutasi stok & input hasil hitung fisik',
      aksiHeader: tombolAksi.isEmpty
          ? null
          : Wrap(
              alignment: WrapAlignment.end,
              runSpacing: 8,
              children: tombolAksi),
      actionsAppBar: tombolAksi.isEmpty ? null : tombolAksi,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Kartu Mutasi Stok'),
              Tab(text: 'Monitor Keluar/Masuk'),
              Tab(text: 'Input Opname'),
              Tab(text: 'SO by Scan'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              const _TabMutasiStok(),
              const _TabMonitorBarang(),
              const _TabInputOpname(),
              _TabSoByScan(aktif: _tab.index == 3),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TabMutasiStok extends StatefulWidget {
  const _TabMutasiStok();

  @override
  State<_TabMutasiStok> createState() => _TabMutasiStokState();
}

class _TabMutasiStokState extends State<_TabMutasiStok> with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  Map<String, dynamic>? _dasbor;
  Map<String, dynamic>? _ringkasanHariIni;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.aksi('stok_dashboard', {'periode': 'month'}),
        ApiClient.instance.aksi('so_ringkasan'),
      ]);
      setStateIfMounted(() {
        _dasbor = results[0];
        _ringkasanHariIni = results[1];
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

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
              Text(_pesanError!, textAlign: TextAlign.center),
              AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    final d = _dasbor!;
    final r = _ringkasanHariIni!;
    final top5 = (d['top5Keluar'] as List?) ?? [];
    final maksTop5 = top5.isEmpty
        ? 1.0
        : top5
            .map((e) => (e['qty'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.call_received,
                    warna: const Color(0xFF2E7D32),
                    nilai: _formatAngka.format(d['barangMasuk'] ?? 0),
                    label: 'Barang Masuk',
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.call_made,
                    warna: const Color(0xFFC0563D),
                    nilai: _formatAngka.format(d['barangKeluar'] ?? 0),
                    label: 'Barang Keluar',
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.inventory_2_outlined,
                    warna: const Color(0xFF1E3A5F),
                    nilai: _formatAngka.format(d['totalStok'] ?? 0),
                    label: 'Total Stok',
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.warning_amber_rounded,
                    warna: Colors.red,
                    nilai: '${d['stokKritis'] ?? 0}',
                    label: 'Stok Kritis (<10)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Progres Opname Hari Ini',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                      '${r['jumlahProduk'] ?? 0} produk dicatat (${r['jumlahCatatan'] ?? 0} kali)'),
                  Text(
                      'Selisih bersih: ${_formatAngka.format(r['selisihBersih'] ?? 0)} unit'),
                  Text(
                      'Lebih: +${_formatAngka.format(r['totalLebih'] ?? 0)} · Kurang: -${_formatAngka.format(r['totalKurang'] ?? 0)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (top5.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Top 5 Barang Keluar',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    ...top5.map((e) {
                      final qty = (e['qty'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e['nama']} (${_formatAngka.format(qty)})',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 2),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: qty / maksTop5,
                                minHeight: 8,
                                backgroundColor: AppColors.borderOf(context),
                                color: const Color(0xFF1E3A5F),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Monitor Keluar/Masuk Barang" (gap-closure, permintaan user 2026-08-12) -- buku besar mutasi
/// stok yang menyatukan SEMUA sumber (Pengadaan, Stok Opname, Penjualan, Pemakaian Bahan Baku,
/// Retur Penjualan/Pembelian, Mutasi Antar Outlet) jadi satu daftar kronologis, lewat aksi server
/// baru `stok_mutasi_ledger` (lihat JavaDoc `KantinHelper.stokMutasiLedger`). BEDA dari tab "Kartu
/// Mutasi Stok" (agregat KPI saja) -- ini baris-per-baris, kasir/admin bisa lihat KENAPA stok satu
/// produk berubah tanpa buka 5+ layar berbeda.
class _TabMonitorBarang extends StatefulWidget {
  const _TabMonitorBarang();

  @override
  State<_TabMonitorBarang> createState() => _TabMonitorBarangState();
}

class _TabMonitorBarangState extends State<_TabMonitorBarang> with JejakGalat {
  bool _memuat = true;
  bool _memuatLagi = false;
  String? _pesanError;
  List<Map<String, dynamic>> _data = [];
  bool _adaLagi = false;
  int _hari = 30;
  final _cariController = TextEditingController();
  String _kataKunci = '';
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (mutasi dari kasir/gudang lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Cache dipisah
      // per PERIODE supaya rentang 7/30/90/365 hari tidak saling menimpa.
      // "Muat Lebih Banyak" (offset >0) TETAP online -- hanya halaman pertama
      // yang punya snapshot lokal.
      await MasterOffline.daftarCacheDulu(
          'stok_mutasi_ledger',
          {'hari': _hari, 'limit': 100, 'offset': 0},
          'master:stok_mutasi_ledger:$_hari', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil);
          // 'adaLagi' hanya dikirim server -- emisi lokal tidak boleh
          // mematikan tombol "Muat Lebih Banyak" secara keliru.
          if (_diff.dariServer) _adaLagi = hasil['adaLagi'] == true;
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatLebihBanyak() async {
    setStateIfMounted(() => _memuatLagi = true);
    try {
      final hasil = await ApiClient.instance.aksi('stok_mutasi_ledger',
          {'hari': _hari, 'limit': 100, 'offset': _data.length});
      setStateIfMounted(() {
        _data.addAll(
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
        _adaLagi = hasil['adaLagi'] == true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat lebih banyak: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memuatLagi = false);
    }
  }

  List<Map<String, dynamic>> get _tersaring {
    final k = _kataKunci.trim().toLowerCase();
    if (k.isEmpty) return _data;
    return _data.where((r) {
      return '${r['produkNama'] ?? ''}'.toLowerCase().contains(k) ||
          '${r['produkKode'] ?? ''}'.toLowerCase().contains(k) ||
          '${r['jenis'] ?? ''}'.toLowerCase().contains(k) ||
          '${r['keterangan'] ?? ''}'.toLowerCase().contains(k);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: _cariController,
                  hintText: 'Cari produk/jenis/keterangan...',
                  onChanged: (v) => setStateIfMounted(() => _kataKunci = v),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: _hari,
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 hari')),
                  DropdownMenuItem(value: 30, child: Text('30 hari')),
                  DropdownMenuItem(value: 90, child: Text('90 hari')),
                  DropdownMenuItem(value: 365, child: Text('1 tahun')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setStateIfMounted(() => _hari = v);
                  _muat();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pesanError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(_pesanError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _muat, child: const Text('Coba Lagi')),
                ],
              ),
            )
          else ...[
            BannerPerubahanServer(
              key: ValueKey('perubahan:${_diff.versi}'),
              baru: _diff.idBaru.length,
              berubah: _diff.idBerubah.length,
              dihapus: _diff.jumlahHapus,
            ),
            AppDataTable(
              minWidth: 1480,
              emptyText: 'Tidak ada mutasi stok dalam periode ini.',
              columns: const [
                AppTableColumn('Waktu', flex: 2),
                AppTableColumn('Jenis', flex: 2),
                AppTableColumn('Produk', flex: 3),
                AppTableColumn('Qty', flex: 1, align: TextAlign.right),
                AppTableColumn('Harga Jual', flex: 2, align: TextAlign.right),
                AppTableColumn('Total Jual', flex: 2, align: TextAlign.right),
                AppTableColumn('Harga Beli', flex: 2, align: TextAlign.right),
                AppTableColumn('Total Beli', flex: 2, align: TextAlign.right),
                AppTableColumn('Keterangan', flex: 3),
              ],
              rows: _tersaring.map((r) {
                final qty = (r['qty'] as num?)?.toDouble() ?? 0;
                final masuk = qty >= 0;
                return AppTableRowData(cells: [
                  AppTableCell(
                    flex: 2,
                    child: KilauBaris(
                      kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                      idBaru: _diff.idBaru,
                      idBerubah: _diff.idBerubah,
                      child: Text('${r['waktu'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  AppTableCell(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.latarLembut(
                              masuk ? AppColors.success : AppColors.danger),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('${r['jenis'] ?? ''}',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: masuk
                                  ? AppColors.success
                                  : AppColors.danger)),
                    ),
                  ),
                  AppTableCell.text(
                      '${r['produkNama'] ?? ''}${(r['produkKode'] ?? '').toString().isEmpty ? '' : ' (${r['produkKode']})'}',
                      flex: 3),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.right,
                    child: Text(
                        '${masuk ? '+' : ''}${_formatAngka.format(qty)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color:
                                masuk ? AppColors.success : AppColors.danger)),
                  ),
                  AppTableCell.text(
                    _formatRupiah.format(r['hargaJual'] ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                  ),
                  AppTableCell.text(
                    _formatRupiah.format(r['totalHargaJual'] ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  AppTableCell.text(
                    _formatRupiah.format(r['hargaBeli'] ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                  ),
                  AppTableCell.text(
                    _formatRupiah.format(r['totalHargaBeli'] ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  AppTableCell.text(
                      '${r['keterangan'] ?? ''}'.isEmpty
                          ? '-'
                          : '${r['keterangan']}',
                      flex: 3),
                ]);
              }).toList(),
            ),
            if (_adaLagi) ...[
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton(
                  onPressed: _memuatLagi ? null : _muatLebihBanyak,
                  child: _memuatLagi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Muat Lebih Banyak'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TabInputOpname extends StatefulWidget {
  const _TabInputOpname();

  @override
  State<_TabInputOpname> createState() => _TabInputOpnameState();
}

class _TabInputOpnameState extends State<_TabInputOpname> with JejakGalat {
  final _barcodeController = TextEditingController();
  final _stokFisikController = TextEditingController();
  final _keteranganController = TextEditingController();
  bool _mencari = false;
  bool _menyimpan = false;
  String? _pesanError;
  Map<String, dynamic>? _produkDitemukan;
  List<Map<String, dynamic>> _riwayatHariIni = [];
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (opname yang dicatat petugas lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    _muatRiwayat();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _stokFisikController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    try {
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Jalur SIMPAN
      // opname TETAP online-only lewat ApiClient (transaksional).
      await MasterOffline.daftarCacheDulu(
          'so_riwayat', {'limit': 30}, 'master:so_riwayat', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() => _riwayatHariIni = _diff.terapkan(hasil));
      });
    } catch (_) {
      // riwayat gagal dimuat bukan blocker utk input baru.
    }
  }

  Future<void> _cariProduk(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _pesanError = null;
      _produkDitemukan = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      setStateIfMounted(() {
        _produkDitemukan = hasil;
        _stokFisikController.text = '';
        _keteranganController.text = '';
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context,
        judul: 'Scan Barcode Produk');
    if (kode != null) {
      _barcodeController.text = kode;
      await _cariProduk(kode);
    }
  }

  Future<void> _simpanOpname() async {
    final p = _produkDitemukan;
    if (p == null) return;
    final stokFisik = double.tryParse(
        _stokFisikController.text.replaceAll(RegExp('[^0-9.]'), ''));
    if (stokFisik == null) {
      setStateIfMounted(() => _pesanError = 'Stok fisik wajib diisi angka.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      /* LOKAL DULU. Opname kerap dikerjakan di gudang yang tidak bersinyal,
       * jadi hitungannya harus tetap tercatat. Selisih biasanya datang dari
       * server; saat offline dihitung sendiri dari stok sistem yang memang
       * sudah ada di layar, lalu ditegaskan ulang begitu tersinkron. */
      final hasil = await MasterOffline.simpanAtauAntre(
        'so_simpan',
        {
          'produk_id': p['produkId'],
          'stok_fisik': stokFisik,
          'keterangan': _keteranganController.text.trim(),
        },
        kunci: 'so:${p['produkId']}',
      );
      final offline = hasil['offline'] == true;
      final selisih = (hasil['selisih'] as num?)?.toDouble() ??
          (stokFisik - ((p['stokSistem'] as num?)?.toDouble() ?? 0));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Tersimpan${offline ? ' di perangkat, menunggu kirim' : ''}. '
              'Selisih: ${selisih > 0 ? "+" : ""}${_formatAngka.format(selisih)}'),
        ));
      }
      setStateIfMounted(() {
        _produkDitemukan = null;
        _barcodeController.clear();
        _stokFisikController.clear();
        _keteranganController.clear();
      });
      await _muatRiwayat();
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  /// Tabel "Riwayat Hari Ini" -- dipakai baik di jalur admin/manager maupun
  /// jalur read-only, mengikuti pola [AppDataTable] yg sama spt halaman
  /// Pelanggan/Produk supaya tampilan list konsisten di seluruh aplikasi.
  Widget _riwayatTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BannerPerubahanServer(
          key: ValueKey('perubahan:${_diff.versi}'),
          baru: _diff.idBaru.length,
          berubah: _diff.idBerubah.length,
          dihapus: _diff.jumlahHapus,
        ),
        _riwayatTabelData(),
      ],
    );
  }

  Widget _riwayatTabelData() {
    return AppDataTable(
      minWidth: 820,
      emptyText: 'Belum ada catatan hari ini.',
      columns: const [
        AppTableColumn('Waktu', flex: 2),
        AppTableColumn('Kode', flex: 1),
        AppTableColumn('Produk', flex: 3),
        AppTableColumn('Sistem', flex: 1, align: TextAlign.right),
        AppTableColumn('Fisik', flex: 1, align: TextAlign.right),
        AppTableColumn('Selisih', flex: 1, align: TextAlign.right),
        AppTableColumn('Keterangan', flex: 2),
      ],
      rows: _riwayatHariIni.map((k) {
        final selisih = (k['selisih'] as num?)?.toDouble() ?? 0;
        final warnaSelisih = selisih == 0
            ? AppColors.textSecondaryOf(context)
            : (selisih > 0 ? AppColors.success : AppColors.danger);
        return AppTableRowData(
          cells: [
            AppTableCell(
              flex: 2,
              child: KilauBaris(
                kunci: '${k['id'] ?? k['_kunci'] ?? ''}',
                idBaru: _diff.idBaru,
                idBerubah: _diff.idBerubah,
                child: Text('${k['waktu'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            AppTableCell.text('${k['kode'] ?? ''}',
                flex: 1,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    fontSize: 12.5)),
            AppTableCell.text('${k['nama'] ?? ''}', flex: 3, maxLines: 2),
            AppTableCell.text(_formatAngka.format(k['stokSistem'] ?? 0),
                flex: 1, align: TextAlign.right),
            AppTableCell.text(_formatAngka.format(k['stokFisik'] ?? 0),
                flex: 1, align: TextAlign.right),
            AppTableCell.text(
              '${selisih > 0 ? "+" : ""}${_formatAngka.format(selisih)}',
              flex: 1,
              align: TextAlign.right,
              style:
                  TextStyle(fontWeight: FontWeight.w700, color: warnaSelisih),
            ),
            AppTableCell.text('${k['keterangan'] ?? ''}', flex: 2, maxLines: 2),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.warning),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Hanya admin/manager atau supervisor toko yang bisa mencatat hasil Stok Opname.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimaryOf(context)))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Riwayat Hari Ini',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _riwayatTable(),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: PencarianProdukBanbox(
                controller: _barcodeController,
                label: 'Kode / Barcode / Nama Produk',
                icon: Icons.search,
                onPilih: _cariProduk,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _scanKamera,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan pakai kamera',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_mencari) const Center(child: CircularProgressIndicator()),
        if (_pesanError != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Text(_pesanError!,
                style: TextStyle(color: Colors.red.shade700)),
          ),
        if (_produkDitemukan != null) ...[
          Card(
            color: AppColors.latarLembut(AppColors.warning),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_produkDitemukan!['nama'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Kode: ${_produkDitemukan!['kode'] ?? ''}'),
                  Text(
                      'Stok Sistem: ${_formatAngka.format(_produkDitemukan!['stokSistem'] ?? 0)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stokFisikController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Stok Fisik (hasil hitung) *',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keteranganController,
                    decoration: const InputDecoration(
                        labelText: 'Keterangan (opsional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _menyimpan ? null : _simpanOpname,
                      child: _menyimpan
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Simpan Hasil Opname'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text('Riwayat Hari Ini',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _riwayatTable(),
      ],
    );
  }
}

/// "SO by Scan" -- antrean batch: tiap scan/entry kode HANYA ditambah ke
/// daftar lokal (`_antrean`), stok fisik diisi INLINE per baris, dan baru
/// dikirim ke server (satu panggilan `so_simpan` per baris, berurutan) saat
/// kasir menekan "Simpan Semua" -- padanan mode cepat versi Electron utk
/// menghitung banyak produk berturut-turut tanpa menunggu tiap simpan
/// selesai sebelum scan berikutnya (beda dari _TabInputOpname yg simpan
/// LANGSUNG per satu produk).
class _TabSoByScan extends StatefulWidget {
  final bool aktif;

  const _TabSoByScan({required this.aktif});

  @override
  State<_TabSoByScan> createState() => _TabSoByScanState();
}

class _AntreanSo {
  final Map<String, dynamic> produk;
  final TextEditingController stokFisik;
  final TextEditingController keterangan;
  String? statusKirim; // null=belum, 'ok', atau pesan error
  _AntreanSo(this.produk)
      : stokFisik = TextEditingController(),
        keterangan = TextEditingController();
}

class _TabSoByScanState extends State<_TabSoByScan>
    with WidgetsBindingObserver, JejakGalat {
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode(debugLabel: 'so-by-scan-barcode');
  bool _mencari = false;
  bool _mengirim = false;
  String? _pesanError;
  final List<_AntreanSo> _antrean = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fokusBarcode();
  }

  @override
  void didUpdateWidget(covariant _TabSoByScan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.aktif && widget.aktif) _fokusBarcode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fokusBarcode();
  }

  void _fokusBarcode() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.aktif || _mencari || _mengirim) return;
      _barcodeFocus.requestFocus();
      _barcodeController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _barcodeController.text.length,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barcodeFocus.dispose();
    _barcodeController.dispose();
    for (final a in _antrean) {
      a.stokFisik.dispose();
      a.keterangan.dispose();
    }
    super.dispose();
  }

  Future<void> _tambahKeAntrean(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _pesanError = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      if (_antrean.any((a) => a.produk['produkId'] == hasil['produkId'])) {
        setStateIfMounted(
            () => _pesanError = '${hasil['nama']} sudah ada di antrean.');
      } else {
        setStateIfMounted(() => _antrean.insert(0, _AntreanSo(hasil)));
      }
      _barcodeController.clear();
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) {
        setStateIfMounted(() => _mencari = false);
        _fokusBarcode();
      }
    }
  }

  Future<void> _scanKamera() async {
    try {
      final kode = await BarcodeScannerScreen.pindai(context,
          judul: 'Scan Barcode Produk');
      if (kode != null) await _tambahKeAntrean(kode);
    } finally {
      _fokusBarcode();
    }
  }

  void _hapusDariAntrean(_AntreanSo a) {
    setStateIfMounted(() => _antrean.remove(a));
    a.stokFisik.dispose();
    a.keterangan.dispose();
    _fokusBarcode();
  }

  Future<void> _simpanSemua() async {
    final belumDikirim = _antrean.where((a) => a.statusKirim != 'ok').toList();
    if (belumDikirim.isEmpty) return;
    setStateIfMounted(() => _mengirim = true);
    var berhasil = 0;
    for (final a in belumDikirim) {
      final stok =
          double.tryParse(a.stokFisik.text.replaceAll(RegExp('[^0-9.]'), ''));
      if (stok == null) {
        setStateIfMounted(() => a.statusKirim = 'Stok fisik wajib diisi');
        continue;
      }
      try {
        final r = await MasterOffline.simpanAtauAntre(
          'so_simpan',
          {
            'produk_id': a.produk['produkId'],
            'stok_fisik': stok,
            'keterangan': a.keterangan.text.trim(),
          },
          kunci: 'so:${a.produk['produkId']}',
        );
        // Baris yang baru mengantre TIDAK diakui "ok" -- statusnya dibedakan
        // supaya petugas tahu mana yang benar-benar sudah sampai server.
        setStateIfMounted(
            () => a.statusKirim = r['offline'] == true ? 'antre' : 'ok');
        berhasil++;
      } catch (e) {
        setStateIfMounted(() => a.statusKirim = e.toString());
      }
    }
    setStateIfMounted(() => _mengirim = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('$berhasil dari ${belumDikirim.length} baris tersimpan.')));
      setStateIfMounted(
          () => _antrean.removeWhere((a) => a.statusKirim == 'ok'));
      _fokusBarcode();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Hanya admin/manager atau supervisor toko yang bisa mencatat hasil Stok Opname.',
          style: TextStyle(
              fontSize: 12, color: AppColors.textSecondaryOf(context)),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: PencarianProdukBanbox(
                  controller: _barcodeController,
                  focusNode: _barcodeFocus,
                  autofocus: true,
                  label: 'Scan / Ketik Kode / Nama Produk',
                  icon: Icons.qr_code,
                  aktif: !_mencari,
                  onPilih: _tambahKeAntrean,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: _mencari ? null : _scanKamera,
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Scan pakai kamera'),
            ],
          ),
        ),
        if (_mencari) const LinearProgressIndicator(),
        if (_pesanError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_pesanError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        Expanded(
          child: _antrean.isEmpty
              ? const Center(
                  child: Text('Antrean kosong -- scan produk utk mulai.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _antrean.length,
                  itemBuilder: (context, i) {
                    final a = _antrean[i];
                    final sukses = a.statusKirim == 'ok';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: sukses ? Colors.green.shade50 : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${a.produk['nama']}  ·  Sistem ${_formatAngka.format(a.produk['stokSistem'] ?? 0)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ),
                                if (!sukses)
                                  IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => _hapusDariAntrean(a)),
                              ],
                            ),
                            if (a.statusKirim != null && !sukses)
                              Text(a.statusKirim!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 11)),
                            if (!sukses)
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: a.stokFisik,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText: 'Stok Fisik',
                                          isDense: true,
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: a.keterangan,
                                      decoration: const InputDecoration(
                                          labelText: 'Keterangan',
                                          isDense: true,
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_antrean.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _mengirim ? null : _simpanSemua,
                child: _mengirim
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Simpan Semua (${_antrean.length})'),
              ),
            ),
          ),
      ],
    );
  }
}
