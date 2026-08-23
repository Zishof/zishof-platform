import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:core_db/core_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/penanda_data_tersimpan.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/dialog_analisis_data.dart';

/// Jalankan+tampilkan SATU laporan dari katalog (spec §Laporan-Laporan) --
/// form filter dibangun murni dari metadata katalog (`produk`/`pelanggan`/
/// `perToko` flags), TIDAK ada satu pun kode khusus per-laporan di sini.
/// Kontrak `laporan_jalankan`/`laporan_pdf` (r/tglMulai/tglSampai/qProduk/
/// qPelanggan/perToko -> kolom+baris+grup+grandTotal) generik utk ~150
/// laporan sekaligus -- lihat JavaDoc PosApi.prosesLaporanJalankan di server.
class LaporanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const LaporanDetailScreen({super.key, required this.item});

  @override
  State<LaporanDetailScreen> createState() => _LaporanDetailScreenState();
}

class _LaporanDetailScreenState extends State<LaporanDetailScreen> with JejakGalat {
  final _formatTgl = DateFormat('yyyy-MM-dd');
  DateTime? _tglMulai;
  DateTime? _tglSampai;
  final _controllerProduk = TextEditingController();
  final _controllerPelanggan = TextEditingController();
  bool _perToko = false;

  bool _memuat = false;
  bool _memprosesPdf = false;
  String? _pesanError;
  Map<String, dynamic>? _hasil;

  /// Benar selama yang tampil masih salinan lokal (server belum menjawab, atau
  /// gagal karena offline) -- menyalakan PenandaDataTersimpan.
  bool _dariCache = false;
  DateTime? _cacheDisimpanPada;

  bool get _adaFilterProduk => widget.item['produk'] == true;
  bool get _adaFilterPelanggan => widget.item['pelanggan'] == true;
  bool get _adaFilterPerToko => widget.item['perToko'] == true;

  @override
  void initState() {
    super.initState();
    final sekarang = DateTime.now();
    _tglMulai = DateTime(sekarang.year, sekarang.month, 1);
    _tglSampai = sekarang;
  }

  @override
  void dispose() {
    _controllerProduk.dispose();
    _controllerPelanggan.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buatPayload() {
    return {
      'r': widget.item['id'],
      if (_tglMulai != null) 'tglMulai': _formatTgl.format(_tglMulai!),
      if (_tglSampai != null) 'tglSampai': _formatTgl.format(_tglSampai!),
      if (_adaFilterProduk && _controllerProduk.text.trim().isNotEmpty)
        'qProduk': _controllerProduk.text.trim(),
      if (_adaFilterPelanggan && _controllerPelanggan.text.trim().isNotEmpty)
        'qPelanggan': _controllerPelanggan.text.trim(),
      if (_adaFilterPerToko && _perToko) 'perToko': 'true',
    };
  }

  /// Kunci cache "baca lokal dulu" utk SATU laporan + SATU kombinasi filter.
  /// WAJIB memuat seluruh parameter yang mengubah isi laporan (id laporan,
  /// periode, cari produk/pelanggan, per toko) -- salah kunci berarti hasil
  /// periode A menimpa periode B.
  String _kunciCache(Map<String, dynamic> payload) =>
      'laporan:jalankan:${payload['r']}'
      ':${payload['tglMulai'] ?? '-'}_${payload['tglSampai'] ?? '-'}'
      ':${payload['qProduk'] ?? '-'}:${payload['qPelanggan'] ?? '-'}'
      ':${payload['perToko'] ?? '-'}';

  Future<void> _tampilkan() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    final payload = _buatPayload();
    final kunci = _kunciCache(payload);
    // BACA LOKAL DULU (pola MasterOffline.daftarCacheDulu, dihitung MANUAL di
    // sini): `laporan_jalankan` mengembalikan satu AMPLOP utuh
    // (kolom+baris+grup+grandTotal+catatan) yang hanya bermakna bersama-sama,
    // sedangkan daftarCacheDulu menyimpan SATU daftar saja -- emisi lokalnya
    // akan kehilangan definisi `kolom` sehingga tabel tidak bisa dirender.
    // Preseden manual yang sama dipakai riwayat_penjualan_screen.dart dan
    // riwayat_sinkronisasi_screen.dart. TANPA kilau baris: `baris` di sini
    // berupa LIST posisional (bukan map ber-id), jadi tidak ada identitas baris
    // yang stabil untuk dianimasikan -- cukup cache-nya saja.
    var adaCacheLokal = false;
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(kunci);
    if (tersimpan != null) {
      try {
        final hasilLokal = jsonDecode(tersimpan) as Map<String, dynamic>;
        adaCacheLokal = true;
        final stempel =
            DateTime.tryParse('${hasilLokal['_disimpanPada'] ?? ''}');
        setStateIfMounted(() {
          _hasil = hasilLokal;
          _dariCache = true;
          _cacheDisimpanPada = stempel;
        });
      } catch (_) {
        adaCacheLokal = false; // cache rusak -- lanjut jalur server biasa.
      }
    }
    try {
      final hasil = await ApiClient.instance.aksi('laporan_jalankan', payload);
      setStateIfMounted(() {
        _hasil = hasil;
        // Angka server sudah terpasang -> penanda salinan tersimpan padam.
        _dariCache = false;
        _cacheDisimpanPada = null;
      });
      // Stempel waktu ikut disimpan DI DALAM amplop supaya pemuatan berikutnya
      // bisa memberi tahu KAPAN salinan ini dibuat. Kunci berawalan garis bawah
      // tidak pernah dibaca _TabelLaporan/ekspor (semua baca kunci spesifik).
      await CoreDb.instance.simpanCacheReferensi(
          kunci,
          jsonEncode({
            ...hasil,
            '_disimpanPada': DateTime.now().toIso8601String(),
          }));
    } on ApiException catch (e) {
      // Offline dgn snapshot sudah tampil -> cukup diam (indikator offline
      // global sudah menceritakan kondisinya).
      if (!e.offline || !adaCacheLokal) {
        setStateIfMounted(() => _pesanError = terapkanGalat(e));
      }
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _memprosesPdf = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('laporan_pdf', _buatPayload());
      final b64 = hasil['pdfBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan berkas PDF.');
      }
      final bytes = base64Decode(b64);
      if (!mounted) return;
      await Printing.layoutPdf(
          onLayout: (_) async => Uint8List.fromList(bytes),
          name: '${widget.item['id']}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memprosesPdf = false);
    }
  }

  /// Ekspor Excel (.xlsx) SUNGGUHAN -- sebelumnya tombol ini menyimpan CSV
  /// (data koma) berekstensi .csv; sekarang benar-benar berkas OOXML yang
  /// bisa dibuka Excel/LibreOffice langsung. Dibangun MANUAL dari XML minimal
  /// (BUKAN lewat package `excel`, yang SETIAP versinya mewajibkan
  /// `archive ^3.x`, padahal proyek ini sudah terkunci ke `archive ^4.0.9`
  /// demi rantai `image`/pdf/printing -- lihat komentar dependency di
  /// pubspec.yaml, jangan downgrade). Format .xlsx sendiri cuma ZIP berisi
  /// beberapa file XML (OOXML) -- `archive` package yang SUDAH ada cukup utk
  /// nge-zip-nya, tak perlu dependency baru. Data dari `_hasil` yg sudah
  /// dimuat lewat "Tampilkan" (kolom/baris SAMA persis dgn `_TabelLaporan`).
  /// Membuka popup rekap. Memakai `kolom`/`baris` yang SAMA dengan tabel dan
  /// dengan ekspor Excel -- bukan memanggil ulang server -- supaya angka di
  /// popup tidak mungkin berbeda dari angka yang sedang dilihat pengguna.
  void _bukaAnalisis() {
    final hasil = _hasil;
    if (hasil == null) return;
    final kolom = ((hasil['kolom'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final baris = ((hasil['baris'] as List?) ?? [])
        .map((e) => List<dynamic>.from(e as List))
        .toList();
    if (kolom.isEmpty) return;
    tampilkanAnalisisData(
      context,
      judul: '${widget.item['judul'] ?? 'Laporan'}',
      subjudul: '${hasil['catatan'] ?? widget.item['ket'] ?? ''}',
      kolom: kolom,
      baris: baris,
    );
  }

  Future<void> _eksporExcel() async {
    final hasil = _hasil;
    if (hasil == null) return;
    final kolom = ((hasil['kolom'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final baris = ((hasil['baris'] as List?) ?? [])
        .map((e) => List<dynamic>.from(e as List))
        .toList();
    if (kolom.isEmpty) return;

    try {
      final bytes = _bangunXlsx(kolom, baris);
      final namaFile =
          '${(widget.item['judul'] as String? ?? widget.item['id']).toString().replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')}.xlsx';
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan Laporan (Excel)',
          fileName: namaFile,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['xlsx']);
      if (path == null) return;
      // Sama seperti ekspor Excel Produk -- Desktop hanya mengembalikan path,
      // mobile sudah menulis via `bytes`; tulis ulang idempoten (isi sama).
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Excel disimpan: $path')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengekspor Excel: $e')));
      }
    }
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = (mulai ? _tglMulai : _tglSampai) ?? DateTime.now();
    final dipilih = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100));
    if (dipilih != null) {
      setStateIfMounted(() {
        if (mulai) {
          _tglMulai = dipilih;
        } else {
          _tglSampai = dipilih;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: Text(widget.item['judul'] as String? ?? 'Laporan',
            overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((widget.item['ket'] as String? ?? '').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(widget.item['ket'] as String,
                      style: TextStyle(
                          color: AppColors.textSecondaryOf(context)))),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _kotakTanggal('Tanggal Mulai', _tglMulai,
                              () => _pilihTanggal(mulai: true))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _kotakTanggal('Tanggal Sampai', _tglSampai,
                              () => _pilihTanggal(mulai: false))),
                    ],
                  ),
                  if (_adaFilterProduk) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: _controllerProduk,
                        decoration: const InputDecoration(
                            labelText: 'Cari Produk',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ],
                  if (_adaFilterPelanggan) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: _controllerPelanggan,
                        decoration: const InputDecoration(
                            labelText: 'Cari Pelanggan',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ],
                  if (_adaFilterPerToko)
                    CheckboxListTile(
                        value: _perToko,
                        onChanged: (v) =>
                            setStateIfMounted(() => _perToko = v ?? false),
                        title: const Text('Tampilkan per Toko'),
                        contentPadding: EdgeInsets.zero,
                        dense: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _memuat ? null : _tampilkan,
                          icon: _memuat
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.play_arrow),
                          label: const Text('Tampilkan'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed:
                            _hasil == null || _memprosesPdf ? null : _cetakPdf,
                        icon: _memprosesPdf
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _hasil == null ? null : _eksporExcel,
                        icon: const Icon(Icons.grid_on_outlined),
                        label: const Text('Excel'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _hasil == null ? null : _bukaAnalisis,
                        icon: const Icon(Icons.insights_outlined),
                        label: const Text('Analisis Data'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_pesanError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.danger),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_pesanError!,
                    style: const TextStyle(color: AppColors.danger)),
                  AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
                ]),
              ),
            // Penanda salinan tersimpan -- di kolom utama, tepat DI ATAS tabel
            // laporan, supaya angkanya tidak terbaca sebagai data terkini.
            PenandaDataTersimpan(
                tampil: _dariCache, diperbaruiPada: _cacheDisimpanPada),
            if (_hasil != null)
              _TabelLaporan(
                  hasil: _hasil!,
                  idLaporan: '${widget.item['id']}',
                  payloadFilter: _buatPayload()),
          ],
        ),
      ),
    );
  }

  Widget _kotakTanggal(String label, DateTime? nilai, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true),
        child:
            Text(nilai == null ? '-' : DateFormat('dd-MM-yyyy').format(nilai)),
      ),
    );
  }
}

/// Render generik tabel `kolom`/`baris` + logika grup/subtotal/grand-total
/// (padanan `laporan-renderer.js`/`LaporanKantinPdf.buildTable` -- lihat
/// JavaDoc kelas ini di server utk aturan lengkap): kolom `t=="tgl"` sudah
/// diformat server (`dd-MM-yyyy HH:mm`), `t=="num"` diformat id-ID di sini
/// (integer utk label berawalan Jml/Jumlah, 2 desimal lainnya, negatif
/// dikurung). Kolom `grup>=0` memicu baris header-grup + subtotal per
/// perubahan nilai; `grandTotal` menambah baris total keseluruhan di akhir.
class _TabelLaporan extends StatefulWidget {
  final Map<String, dynamic> hasil;

  /// Id laporan + filter aktif -- agar popup rincian memanggil laporan penyusun
  /// di server dengan FILTER YANG SAMA (lihat _bukaRincianBaris).
  final String idLaporan;
  final Map<String, dynamic> payloadFilter;
  const _TabelLaporan(
      {required this.hasil,
      required this.idLaporan,
      required this.payloadFilter});

  @override
  State<_TabelLaporan> createState() => _TabelLaporanState();
}

class _TabelLaporanState extends State<_TabelLaporan> {
  static const _lebarKolom = 150.0;
  static const _pageSize = 15;

  int _halaman = 1;

  @override
  void didUpdateWidget(covariant _TabelLaporan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hasil, widget.hasil)) _halaman = 1;
  }

  /// Popup "data penghitungan" saat angka laporan diklik. Bila baris ini terdaftar
  /// punya laporan RINCIAN di server (mis. HPP Laba Rugi), rincian itu diambil dgn
  /// filter yang sama; selain itu ditampilkan asal-usul baris (seluruh kolomnya).
  Future<void> _bukaRincianBaris(
      BuildContext context,
      List<Map<String, dynamic>> kolom,
      List<dynamic> baris,
      int kolomKe) async {
    final labelBaris =
        (baris.isNotEmpty ? '${baris[0] ?? ''}' : '').trim().toLowerCase();
    String? idRincian;
    for (final e in (_petaRincianLaporan[widget.idLaporan] ?? const [])) {
      if (labelBaris.contains(e[0])) {
        idRincian = e[1];
        break;
      }
    }
    final judul = baris.isNotEmpty && '${baris[0] ?? ''}'.trim().isNotEmpty
        ? '${baris[0]}'.trim()
        : (kolom.length > kolomKe ? '${kolom[kolomKe]['l'] ?? ''}' : 'Rincian');

    if (idRincian == null) {
      if (!context.mounted) return;
      // Dimensi baris dikenali dari LABEL kolomnya, lalu dikirim ke aksi
      // laporan_rincian_transaksi supaya popup menampilkan NOTA-nya, bukan
      // sekadar mengulang isi baris ringkasan (permintaan 21-08-2026).
      // Rincian transaksi butuh RENTANG TANGGAL. Laporan yang tidak punya
      // filter tanggal (mis. stok, data master) tidak mengirimnya, dan
      // memaksakan permintaan hanya menghasilkan pesan error membingungkan.
      final adaRentang =
          '${widget.payloadFilter['tglMulai'] ?? ''}'.isNotEmpty &&
              '${widget.payloadFilter['tglSampai'] ?? ''}'.isNotEmpty;
      final dimensi =
          adaRentang ? _dimensiBaris(kolom, baris) : const <String, dynamic>{};
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Asal Angka: $judul'),
          content: SizedBox(
            width: dimensi.isEmpty ? 460 : 860,
            height: dimensi.isEmpty ? null : 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < kolom.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(
                          width: 170,
                          child: Text('${kolom[i]['l'] ?? ''}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12))),
                      Expanded(
                          child: Text(
                              i < baris.length
                                  ? _fmtSel(
                                      baris[i],
                                      '${kolom[i]['t'] ?? 'text'}',
                                      '${kolom[i]['l'] ?? ''}')
                                  : '',
                              style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
                if (dimensi.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                        'Angka ini tidak berasal dari transaksi penjualan '
                        '(mis. stok atau data master), sehingga tidak ada '
                        'nota penyusun yang bisa ditampilkan.',
                        style: TextStyle(fontSize: 11)),
                  ),
                if (dimensi.isNotEmpty) ...[
                  const Divider(height: 22),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Transaksi penyusun angka ini',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  const SizedBox(height: 6),
                  _RincianTransaksi(
                      payloadFilter: widget.payloadFilter, dimensi: dimensi),
                ],
                if ('${widget.hasil['catatan'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('${widget.hasil['catatan']}',
                        style: const TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
          ],
        ),
      );
      return;
    }

    final payload = Map<String, dynamic>.from(widget.payloadFilter);
    payload['r'] = idRincian;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Rincian: $judul'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: FutureBuilder<Map<String, dynamic>>(
            future: ApiClient.instance.aksi('laporan_jalankan', payload),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                    child: Text('Gagal memuat rincian: ${snap.error}'));
              }
              final d = snap.data ?? const <String, dynamic>{};
              final kol = ((d['kolom'] as List?) ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              final rows = ((d['baris'] as List?) ?? [])
                  .map((e) => List<dynamic>.from(e as List))
                  .toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Tidak ada data penyusun.'));
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ('${d['catatan'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${d['catatan']}',
                            style: const TextStyle(
                                fontSize: 11, fontStyle: FontStyle.italic)),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 18,
                            columns: [
                              for (final k in kol)
                                DataColumn(
                                    label: Text('${k['l'] ?? ''}',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700)))
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(cells: [
                                  for (var i = 0; i < kol.length; i++)
                                    DataCell(Text(
                                        i < r.length
                                            ? _fmtSel(
                                                r[i],
                                                '${kol[i]['t'] ?? 'text'}',
                                                '${kol[i]['l'] ?? ''}')
                                            : '',
                                        style: const TextStyle(fontSize: 11.5)))
                                ])
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${rows.length} baris penyusun.',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ]);
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
        ],
      ),
    );
  }

  int _totalHalaman(int total) {
    if (total <= 0) return 1;
    return ((total - 1) ~/ _pageSize) + 1;
  }

  bool _isHitungKolom(String label) {
    final l = label.trim().toLowerCase();
    return l.startsWith('jml') || l.startsWith('jumlah');
  }

  String _fmtNum(num? v, bool hitung) {
    if (v == null) return '';
    final neg = v < 0;
    final abs = v.abs();
    final formatter = hitung
        ? NumberFormat.decimalPattern('id_ID')
        : NumberFormat('#,##0.00', 'id_ID');
    final s = formatter.format(abs);
    return neg ? '($s)' : s;
  }

  String _fmtSel(dynamic v, String tipe, String label) {
    if (v == null) return '';
    if (tipe == 'num') return _fmtNum(v as num, _isHitungKolom(label));
    return v.toString();
  }

  Color _warnaBiruGelap(BuildContext context) => AppColors.gelap(context)
      ? AppColors.darkTextPrimary
      : AppColors.sidebarBg;

  @override
  Widget build(BuildContext context) {
    final kolom = ((widget.hasil['kolom'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final baris = ((widget.hasil['baris'] as List?) ?? [])
        .map((e) => List<dynamic>.from(e as List))
        .toList();
    final catatan = widget.hasil['catatan'] as String?;
    final grup = (widget.hasil['grup'] as num?)?.toInt() ?? -1;
    final grandTotal = widget.hasil['grandTotal'] == true;
    final judul = widget.hasil['judul'] as String?;

    if (kolom.isEmpty) {
      return AppSectionCard(
        child: Center(
          child: Text(
            'Tidak ada kolom pada laporan ini.',
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }
    if (baris.isEmpty) {
      return AppSectionCard(
        child: Center(
          child: Text(
            'Tidak ada data untuk filter yang dipilih.',
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }

    final numIdx = <int>[
      for (var i = 0; i < kolom.length; i++)
        if (kolom[i]['t'] == 'num') i
    ];
    final semuaBaris = <AppTableRowData>[];

    List<AppTableCell> selKosong({String? labelAwal, TextStyle? styleAwal}) {
      return List.generate(kolom.length, (i) {
        return AppTableCell.text(
          i == 0 ? (labelAwal ?? '') : '',
          width: _lebarKolom,
          maxLines: 2,
          style: i == 0 ? styleAwal : null,
        );
      });
    }

    AppTableRowData barisData(List<dynamic> r) {
      return AppTableRowData(
        cells: List.generate(kolom.length, (i) {
          final tipe = kolom[i]['t'] as String? ?? 'text';
          final label = kolom[i]['l'] as String? ?? '';
          final isNum = tipe == 'num';
          final teksSel = i < r.length ? _fmtSel(r[i], tipe, label) : '';
          final gaya = TextStyle(
            fontSize: 12.5,
            color: AppColors.textPrimaryOf(context),
            fontFamily: isNum ? 'monospace' : null,
          );
          // SETIAP ANGKA BISA DIKLIK: popup memperlihatkan data penghitungannya --
          // seluruh kolom baris tsb + catatan rumus laporan, dan untuk laporan yang
          // punya rincian server (mis. HPP Laba Rugi) dibuka rincian penyusunnya.
          if (!isNum || teksSel.isEmpty) {
            return AppTableCell.text(teksSel,
                width: _lebarKolom,
                align: isNum ? TextAlign.right : TextAlign.left,
                maxLines: 2,
                style: gaya);
          }
          return AppTableCell(
            width: _lebarKolom,
            align: TextAlign.right,
            child: _SelAngkaRincian(
              teks: teksSel,
              gaya: gaya,
              onTap: () => _bukaRincianBaris(context, kolom, r, i),
            ),
          );
        }),
      );
    }

    void tambahBarisPita(String teks) {
      semuaBaris.add(AppTableRowData(
        cells: selKosong(
          labelAwal: teks,
          styleAwal: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: _warnaBiruGelap(context),
          ),
        ),
      ));
    }

    void tambahBarisSubtotal(String key, Map<int, double> sums) {
      semuaBaris.add(AppTableRowData(
        cells: List.generate(kolom.length, (i) {
          String teks = '';
          if (i == grup) {
            teks = 'Subtotal $key';
          } else if (sums.containsKey(i)) {
            teks = _fmtNum(
                sums[i], _isHitungKolom(kolom[i]['l'] as String? ?? ''));
          }
          final isNum = kolom[i]['t'] == 'num';
          return AppTableCell.text(
            teks,
            width: _lebarKolom,
            align: isNum ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryOf(context),
            ),
          );
        }),
      ));
    }

    if (grup >= 0 && grup < kolom.length) {
      String? kunciSaatIni;
      final jumlahSaatIni = <int, double>{};
      for (final r in baris) {
        final kunci = r[grup]?.toString() ?? '';
        if (kunciSaatIni == null) {
          tambahBarisPita(kunci);
          kunciSaatIni = kunci;
        } else if (kunci != kunciSaatIni) {
          tambahBarisSubtotal(kunciSaatIni, jumlahSaatIni);
          jumlahSaatIni.clear();
          tambahBarisPita(kunci);
          kunciSaatIni = kunci;
        }
        for (final i in numIdx) {
          jumlahSaatIni[i] =
              (jumlahSaatIni[i] ?? 0) + ((r[i] as num?)?.toDouble() ?? 0);
        }
        final rSalinan = List<dynamic>.from(r);
        rSalinan[grup] = null;
        semuaBaris.add(barisData(rSalinan));
      }
      if (kunciSaatIni != null) {
        tambahBarisSubtotal(kunciSaatIni, jumlahSaatIni);
      }
    } else {
      for (final r in baris) {
        semuaBaris.add(barisData(r));
      }
    }

    if (grandTotal && numIdx.isNotEmpty) {
      final total = <int, double>{};
      for (final r in baris) {
        for (final i in numIdx) {
          total[i] = (total[i] ?? 0) + ((r[i] as num?)?.toDouble() ?? 0);
        }
      }
      semuaBaris.add(AppTableRowData(
        cells: List.generate(kolom.length, (i) {
          String teks = '';
          if (i == 0) {
            teks = 'TOTAL';
          } else if (total.containsKey(i)) {
            teks = _fmtNum(
                total[i], _isHitungKolom(kolom[i]['l'] as String? ?? ''));
          }
          final isNum = kolom[i]['t'] == 'num';
          return AppTableCell.text(
            teks,
            width: _lebarKolom,
            align: isNum ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: _warnaBiruGelap(context),
            ),
          );
        }),
      ));
    }

    final totalHalaman = _totalHalaman(semuaBaris.length);
    if (_halaman > totalHalaman) _halaman = totalHalaman;
    final mulai = (_halaman - 1) * _pageSize;
    final sampai = (mulai + _pageSize).clamp(0, semuaBaris.length) as int;
    final rows = mulai >= semuaBaris.length
        ? <AppTableRowData>[]
        : semuaBaris.sublist(mulai, sampai);
    final minWidth =
        (_lebarKolom * kolom.length) < 760 ? 760.0 : _lebarKolom * kolom.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (judul != null || (catatan != null && catatan.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (judul != null)
                    Text(
                      judul,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  if (catatan != null && catatan.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        catatan,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        AppDataTable(
          minWidth: minWidth,
          emptyText: 'Tidak ada data untuk halaman ini.',
          columns: kolom
              .map((k) => AppTableColumn(
                    k['l'] as String? ?? '',
                    width: _lebarKolom,
                    align: k['t'] == 'num' ? TextAlign.right : TextAlign.left,
                  ))
              .toList(),
          rows: rows,
          pagination: AppTablePagination(
            halaman: _halaman,
            totalHalaman: totalHalaman,
            totalData: baris.length,
            labelData: 'baris',
            onSebelumnya:
                _halaman > 1 ? () => setStateIfMounted(() => _halaman--) : null,
            onBerikutnya: _halaman < totalHalaman
                ? () => setStateIfMounted(() => _halaman++)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Ubah index kolom 0-based jadi huruf kolom Excel (0->A, 25->Z, 26->AA, dst).
String _kolomExcel(int index) {
  var i = index;
  var s = '';
  while (true) {
    s = String.fromCharCode(65 + (i % 26)) + s;
    i = i ~/ 26 - 1;
    if (i < 0) break;
  }
  return s;
}

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Bangun .xlsx SATU sheet dari kontrak `kolom`/`baris` yang sama dgn
/// [_TabelLaporan] -- kolom `t=="num"` ditulis sbg sel numerik ASLI (bukan
/// teks berformat) supaya bisa dihitung/diurutkan langsung di Excel, sisanya
/// (termasuk `t=="tgl"`, sudah diformat server) sbg teks apa adanya. String
/// inline (`t="inlineStr"`) dipakai drpd `sharedStrings.xml` -- lebih
/// sederhana utk laporan sekali-pakai spt ini (tak perlu tabel string
/// terpisah), tetap valid OOXML.
Uint8List _bangunXlsx(
  List<Map<String, dynamic>> kolom,
  List<List<dynamic>> baris,
) {
  final sheetXml = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetData>')
    ..write('<row r="1">');
  for (var i = 0; i < kolom.length; i++) {
    final label = _escapeXml((kolom[i]['l'] as String?) ?? '');
    sheetXml.write(
        '<c r="${_kolomExcel(i)}1" t="inlineStr" s="1"><is><t xml:space="preserve">$label</t></is></c>');
  }
  sheetXml.write('</row>');

  for (var r = 0; r < baris.length; r++) {
    final row = baris[r];
    final excelRow = r + 2;
    sheetXml.write('<row r="$excelRow">');
    for (var i = 0; i < kolom.length; i++) {
      final v = i < row.length ? row[i] : null;
      if (v == null) continue;
      final ref = '${_kolomExcel(i)}$excelRow';
      final tipe = kolom[i]['t'] as String? ?? 'text';
      if (tipe == 'num' && v is num) {
        sheetXml.write('<c r="$ref"><v>$v</v></c>');
      } else {
        final teks = _escapeXml(v.toString());
        sheetXml.write(
            '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">$teks</t></is></c>');
      }
    }
    sheetXml.write('</row>');
  }
  sheetXml
    ..write('</sheetData>')
    ..write('</worksheet>');

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  const workbookXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="Laporan" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';

  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  const stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '</cellXfs>'
      '</styleSheet>';

  final archive = Archive()
    ..addFile(
        ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRels)))
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbookXml)))
    ..addFile(ArchiveFile.bytes(
        'xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)))
    ..addFile(ArchiveFile.bytes('xl/styles.xml', utf8.encode(stylesXml)))
    ..addFile(ArchiveFile.bytes(
        'xl/worksheets/sheet1.xml', utf8.encode(sheetXml.toString())));

  return ZipEncoder().encodeBytes(archive);
}

/// Sel angka laporan yang dapat diklik (bergaris putus-putus + kursor tangan),
/// seragam dgn gaya angka clickable di Laporan Transaksi.
class _SelAngkaRincian extends StatelessWidget {
  final String teks;
  final TextStyle gaya;
  final VoidCallback onTap;
  const _SelAngkaRincian(
      {required this.teks, required this.gaya, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Klik untuk melihat data penghitungannya',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(
              teks,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: gaya.copyWith(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Peta baris laporan ringkasan -> id laporan RINCIAN di server. Menambah
/// drill-down baru cukup mendaftarkannya di sini (padanan PETA_RINCIAN di
/// laporan_laporan.jsp) + membuat cabangnya di LaporanKantinUtil.
/// Kenali dimensi baris laporan dari LABEL kolomnya, supaya satu aksi server
/// dapat melayani seluruh keluarga laporan berbasis transaksi tanpa daftar
/// khusus per laporan. Label dicocokkan longgar (mengandung kata kunci) karena
/// tiap laporan memakai penyebutan yang berbeda-beda.
///
/// Mengembalikan peta kosong bila baris tidak punya dimensi yang dapat dipakai
/// menyaring transaksi (mis. laporan stok atau baris total) -- pemanggil lalu
/// menampilkan asal-usul baris apa adanya spt sebelumnya.
Map<String, dynamic> _dimensiBaris(
    List<Map<String, dynamic>> kolom, List<dynamic> baris) {
  final hasil = <String, dynamic>{};
  for (var i = 0; i < kolom.length && i < baris.length; i++) {
    final label = '${kolom[i]['l'] ?? ''}'.toLowerCase();
    final tipe = '${kolom[i]['t'] ?? 'text'}';
    if (tipe != 'text') {
      continue;
    }
    final nilai = '${baris[i] ?? ''}'.trim();
    if (nilai.isEmpty || nilai == '-') {
      continue;
    }
    if (label.contains('kode') && !hasil.containsKey('kodeProduk')) {
      hasil['kodeProduk'] = nilai;
    } else if ((label.contains('nama produk') || label.contains('barang')) &&
        !hasil.containsKey('namaProduk')) {
      hasil['namaProduk'] = nilai;
    } else if (label.contains('kasir') && !hasil.containsKey('kasir')) {
      hasil['kasir'] = nilai;
    } else if ((label.contains('metode') || label.contains('kas/bank')) &&
        !hasil.containsKey('metode')) {
      hasil['metode'] = nilai;
    } else if ((label.contains('pelanggan') ||
            label.contains('anggota') ||
            label.contains('member')) &&
        !hasil.containsKey('pelanggan')) {
      hasil['pelanggan'] = nilai;
    }
  }
  return hasil;
}

/// Daftar transaksi penyusun satu angka laporan.
class _RincianTransaksi extends StatelessWidget {
  final Map<String, dynamic> payloadFilter;
  final Map<String, dynamic> dimensi;

  const _RincianTransaksi({required this.payloadFilter, required this.dimensi});

  @override
  Widget build(BuildContext context) {
    final payload = <String, dynamic>{
      'tglMulai': payloadFilter['tglMulai'],
      'tglSampai': payloadFilter['tglSampai'],
      ...dimensi,
    };
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiClient.instance.aksi('laporan_rincian_transaksi', payload),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Rincian transaksi tidak dapat dimuat: ${snap.error}',
                style: const TextStyle(fontSize: 12)),
          );
        }
        final data = ((snap.data?['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        if (data.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
                'Tidak ada transaksi yang cocok. Angka ini kemungkinan berasal '
                'dari sumber selain penjualan (mis. stok atau data master).',
                style: TextStyle(fontSize: 12)),
          );
        }
        final rp = NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 34,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 40,
                columns: const [
                  DataColumn(label: Text('Waktu')),
                  DataColumn(label: Text('No. Nota')),
                  DataColumn(label: Text('Kasir')),
                  DataColumn(label: Text('Pelanggan')),
                  DataColumn(label: Text('Produk')),
                  DataColumn(label: Text('Qty'), numeric: true),
                  DataColumn(label: Text('Harga'), numeric: true),
                  DataColumn(label: Text('Total'), numeric: true),
                ],
                rows: [
                  for (final r in data)
                    DataRow(cells: [
                      DataCell(Text('${r['waktu'] ?? ''}'.split('.').first)),
                      DataCell(Text('${r['nota'] ?? ''}')),
                      DataCell(Text('${r['kasir'] ?? ''}')),
                      DataCell(Text('${r['pelanggan'] ?? ''}')),
                      DataCell(Text('${r['produk'] ?? ''}')),
                      DataCell(Text('${(r['qty'] as num?)?.toDouble() ?? 0}')),
                      DataCell(Text(
                          rp.format((r['harga'] as num?)?.toDouble() ?? 0))),
                      DataCell(Text(
                          rp.format((r['total'] as num?)?.toDouble() ?? 0))),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${data.length} baris transaksi  ·  total '
              '${rp.format((snap.data?['totalNilai'] as num?)?.toDouble() ?? 0)}'
              '${snap.data?['dibatasi'] == true ? '  (dibatasi, masih ada baris lain)' : ''}',
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        );
      },
    );
  }
}

const Map<String, List<List<String>>> _petaRincianLaporan = {
  'fin_laba_rugi': [
    ['hpp', 'fin_laba_rugi_rincian_hpp'],
    ['penjualan', 'fin_laba_rugi_rincian_penjualan'],
    ['pendapatan bersih', 'fin_laba_rugi_rincian_penjualan'],
  ],
};
