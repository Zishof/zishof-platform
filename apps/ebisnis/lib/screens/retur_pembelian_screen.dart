import 'dart:typed_data';

import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../api_client.dart';
import '../parse_util.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../widgets/app_components.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/proses_simpan_master.dart';
import 'pengadaan_cetak_util.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatAngka = NumberFormat.decimalPattern('id_ID');

const _daftarAlasanRetur = [
  'Rusak',
  'Salah Kirim',
  'Tidak Sesuai Pesanan',
  'Kadaluarsa',
  'Lainnya',
];

class _ItemReturPembelian {
  final int produkId;
  final String nama;
  final String kode;
  double qty;
  final double harga;
  String alasan;
  final double? qtyMaksimal;
  bool dipilih;
  _ItemReturPembelian(
      {required this.produkId,
      required this.nama,
      this.kode = '',
      required this.qty,
      required this.harga,
      required this.alasan,
      this.qtyMaksimal,
      this.dipilih = true});
  double get total => qty * harga;
}

/// Tab "Retur Pembelian" (gap-closure roadmap Fase 3, permintaan user 2026-08-11) -- barang
/// dikembalikan KE SUPPLIER, kebalikan Retur Penjualan. Beda dari wizard Retur Penjualan (yg
/// WAJIB lacak transaksi penjualan asal lewat `laporan_order_list`/`detail_transaksi`) -- di sini
/// petugas langsung cari produk (pola sama Kulakan/Stok Opname), tanpa perlu jejak faktur
/// pengadaan yg jelas (barang titipan/data lama juga bisa diretur).
class ReturPembelianTab extends StatefulWidget {
  const ReturPembelianTab({super.key});
  @override
  State<ReturPembelianTab> createState() => _ReturPembelianTabState();
}

class _ReturPembelianTabState extends State<ReturPembelianTab> with JejakGalat {
  static const _pageSize = 15;

  final _barcodeController = TextEditingController();
  final _qtyController = TextEditingController();
  final _hargaController = TextEditingController();
  String _alasan = _daftarAlasanRetur.first;
  bool _mencari = false;
  String? _errorForm;
  Map<String, dynamic>? _produkDitemukan;
  final List<_ItemReturPembelian> _items = [];
  Map<String, dynamic>? _fakturTerpilih;
  bool _menyimpan = false;
  String? _idempotencyKey;

  bool _memuatRiwayat = true;
  String? _errorRiwayat;
  List<Map<String, dynamic>> _riwayat = [];
  int _halaman = 1;
  int _total = 0;
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (retur yang dicatat petugas lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    _muatRiwayat();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _qtyController.dispose();
    _hargaController.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    setStateIfMounted(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Jalur SIMPAN
      // dan HAPUS retur TETAP online-only lewat ApiClient (transaksional).
      await MasterOffline.daftarCacheDulu(
          'retur_pembelian_list',
          {'page': _halaman, 'page_size': _pageSize},
          'master:retur_pembelian', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _riwayat = _diff.terapkan(hasil);
          _total = _diff.total ?? _riwayat.length;
          _memuatRiwayat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _errorRiwayat = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuatRiwayat = false);
    }
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muatRiwayat();
  }

  Future<void> _cariProduk(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _errorForm = null;
      _produkDitemukan = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      setStateIfMounted(() {
        _produkDitemukan = hasil;
        _qtyController.clear();
        _hargaController.clear();
      });
    } catch (e) {
      setStateIfMounted(() => _errorForm = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _pilihFakturAsal() async {
    setStateIfMounted(() {
      _mencari = true;
      _errorForm = null;
    });
    try {
      List<Map<String, dynamic>> faktur = [];
      await MasterOffline.daftarCacheDulu(
        'kulakan_faktur_list',
        const {'page': 1, 'page_size': 100},
        'master:kulakan_faktur',
        kolomKunci: 'fakturId',
        onData: (hasil) {
          faktur = ((hasil['data'] as List?) ?? const [])
              .whereType<Map>()
              .map((baris) => baris.cast<String, dynamic>())
              .toList();
        },
      );
      if (!mounted) return;
      if (faktur.isEmpty) {
        setStateIfMounted(() => _errorForm =
            'Belum ada faktur pembelian yang dapat dipilih. Sinkronkan data Kulakan, lalu coba lagi.');
        return;
      }
      final dipilih = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pilih Faktur Pembelian'),
          content: SizedBox(
            width: 680,
            height: 480,
            child: ListView.separated(
              itemCount: faktur.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final f = faktur[index];
                return ListTile(
                  title: Text('${f['nomorFaktur'] ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${f['tanggalFaktur'] ?? '-'} · ${f['namaSupplier'] ?? 'Tanpa supplier'} · ${f['jumlahItem'] ?? 0} item'),
                  trailing: Text(_formatRupiah
                      .format(f['totalFakturFinal'] ?? f['totalHitung'] ?? 0)),
                  onTap: () => Navigator.of(dialogContext).pop(f),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Batal')),
          ],
        ),
      );
      if (dipilih == null || !mounted) return;
      final detail = await MasterOffline.objekDenganCache(
        'kulakan_faktur_detail',
        {'faktur_id': dipilih['fakturId']},
        'master:kulakan_faktur:detail:${dipilih['fakturId']}',
      );
      final header =
          (detail['header'] as Map?)?.cast<String, dynamic>() ?? dipilih;
      final baris = ((detail['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((e) => e['masterProdukTersedia'] != false)
          .toList();
      if (baris.isEmpty) {
        throw StateError(
            'Faktur tidak memiliki item produk yang dapat diretur. Periksa detail faktur asal.');
      }
      setStateIfMounted(() {
        _fakturTerpilih = {...dipilih, ...header};
        _items
          ..clear()
          ..addAll(baris.map((it) {
            final qty = (it['qty'] as num?)?.toDouble() ?? 0;
            return _ItemReturPembelian(
              produkId: (it['produkId'] as num).toInt(),
              kode: '${it['kodeProduk'] ?? ''}',
              nama: '${it['namaProduk'] ?? '-'}',
              qty: qty,
              qtyMaksimal: qty,
              harga: (it['hargaBeliSatuan'] as num?)?.toDouble() ?? 0,
              alasan: _daftarAlasanRetur.first,
              dipilih: false,
            );
          }));
        _idempotencyKey = null;
      });
    } catch (e) {
      setStateIfMounted(() => _errorForm = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context,
        judul: 'Scan Barcode Produk');
    if (!mounted) return;
    if (kode != null) {
      _barcodeController.text = kode;
      await _cariProduk(kode);
    }
  }

  void _tambahKeDaftar() {
    final p = _produkDitemukan;
    if (p == null) return;
    final qty = parseDesimal(_qtyController.text);
    final harga = parseDesimal(_hargaController.text) ?? 0;
    if (qty == null || qty <= 0) {
      setStateIfMounted(() => _errorForm = 'Jumlah retur harus lebih dari 0.');
      return;
    }
    setStateIfMounted(() {
      _items.add(_ItemReturPembelian(
          produkId: p['produkId'] as int,
          kode: '${p['kode'] ?? p['kodeProduk'] ?? ''}',
          nama: '${p['nama'] ?? ''}',
          qty: qty,
          harga: harga,
          alasan: _alasan));
      _produkDitemukan = null;
      _barcodeController.clear();
      _qtyController.clear();
      _hargaController.clear();
      _errorForm = null;
    });
  }

  void _hapusDariDaftar(int index) =>
      setStateIfMounted(() => _items.removeAt(index));

  List<_ItemReturPembelian> get _itemsAktif =>
      _items.where((it) => it.dipilih && it.qty > 0).toList();

  double get _totalNilai =>
      _itemsAktif.fold<double>(0, (a, it) => a + it.total);

  Future<Uint8List> _buatPdfRetur({
    required String nomor,
    required String supplier,
    required List<_ItemReturPembelian> items,
  }) async {
    final dokumen = pw.Document();
    dokumen.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text('RETUR PEMBELIAN',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('Faktur asal: $nomor'),
        pw.Text('Supplier: $supplier'),
        pw.Text(
            'Tanggal cetak: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}'),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: const ['Kode', 'Produk', 'Qty', 'Harga', 'Alasan', 'Total'],
          data: items
              .map((it) => [
                    it.kode,
                    it.nama,
                    _formatAngka.format(it.qty),
                    _formatRupiah.format(it.harga),
                    it.alasan,
                    _formatRupiah.format(it.total),
                  ])
              .toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellStyle: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
              'Total: ${_formatRupiah.format(items.fold<double>(0, (a, it) => a + it.total))}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ));
    return dokumen.save();
  }

  Future<void> _pratinjauItems(List<_ItemReturPembelian> items,
      {Map<String, dynamic>? faktur}) async {
    if (items.isEmpty) {
      setStateIfMounted(() =>
          _errorForm = 'Pilih minimal satu item sebelum membuka pratinjau.');
      return;
    }
    final f = faktur ?? _fakturTerpilih ?? const <String, dynamic>{};
    final nomor = '${f['nomorFaktur'] ?? f['kodeFakturAsal'] ?? 'Manual'}';
    final supplier = '${f['namaSupplier'] ?? 'Belum ditentukan'}';
    final bytes =
        await _buatPdfRetur(nomor: nomor, supplier: supplier, items: items);
    if (!mounted) return;
    await tampilkanPratinjauPdf(context, judul: 'Retur-$nomor', isi: bytes);
  }

  Future<void> _simpanRetur() async {
    final itemsSimpan = _itemsAktif;
    if (itemsSimpan.isEmpty) {
      setStateIfMounted(
          () => _errorForm = 'Belum ada barang yang dipilih untuk diretur.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _errorForm = null;
    });
    try {
      _idempotencyKey ??= 'RETUR-BELI-${DateTime.now().microsecondsSinceEpoch}';
      // LOKAL DULU: ditulis ke antrean perangkat, baru dikirim. Aman diulang
      // karena idempotency_key ikut terkirim, sehingga kiriman ganda tidak
      // melahirkan retur kedua.
      await prosesSimpanMaster(
        context,
        aksi: 'retur_pembelian_simpan',
        kunci: 'retur_pembelian:$_idempotencyKey',
        cacheKey: 'master:retur_pembelian',
        rowLokal: {
          'id': -DateTime.now().millisecondsSinceEpoch,
          'jumlahItem': itemsSimpan.length,
          'kodeFakturAsal': _fakturTerpilih?['nomorFaktur'],
          'total':
              itemsSimpan.fold<double>(0, (a, it) => a + it.qty * it.harga),
        },
        body: {
          'idempotency_key': _idempotencyKey,
          if (_fakturTerpilih?['fakturId'] != null)
            'faktur_pengadaan_id': _fakturTerpilih!['fakturId'],
          if (_fakturTerpilih?['nomorFaktur'] != null)
            'kode_faktur_asal': _fakturTerpilih!['nomorFaktur'],
          if (_fakturTerpilih?['supplierId'] != null)
            'supplier_id': _fakturTerpilih!['supplierId'],
          'items': itemsSimpan
              .map((it) => {
                    'produk_id': it.produkId,
                    'qty': it.qty,
                    'harga_satuan': it.harga,
                    'alasan': it.alasan
                  })
              .toList(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Retur Pembelian tersimpan (${itemsSimpan.length} item).')));
      }
      setStateIfMounted(() {
        _items.clear();
        _fakturTerpilih = null;
        _idempotencyKey = null;
      });
      _halaman = 1;
      await _muatRiwayat();
    } catch (e) {
      setStateIfMounted(() => _errorForm = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Future<void> _hapusBaris(Map<String, dynamic> r) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Retur?'),
        content: Text(
            'Hapus baris retur "${r['namaProduk']}"? Stok akan dikoreksi ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    if (!mounted) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'retur_pembelian_hapus',
        kunci: 'retur_pembelian:${r['id']}',
        cacheKey: 'master:retur_pembelian',
        rowLokal: {'id': r['id']},
        hapusLokal: true,
        body: {'id': r['id']},
      );
      await _muatRiwayat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menghapus: $e')));
      }
    }
  }

  Future<void> _cetakRiwayat(Map<String, dynamic> r) async {
    final kodeFaktur = '${r['kodeFakturAsal'] ?? ''}';
    final sumber = kodeFaktur.isEmpty
        ? [r]
        : _riwayat
            .where((it) => '${it['kodeFakturAsal'] ?? ''}' == kodeFaktur)
            .toList();
    final items = sumber
        .map((it) => _ItemReturPembelian(
              produkId: (it['produkId'] as num?)?.toInt() ?? 0,
              kode: '${it['kodeProduk'] ?? ''}',
              nama: '${it['namaProduk'] ?? '-'}',
              qty: (it['qty'] as num?)?.toDouble() ?? 0,
              harga: (it['hargaSatuan'] as num?)?.toDouble() ?? 0,
              alasan: '${it['alasan'] ?? '-'}',
            ))
        .toList();
    await _pratinjauItems(items, faktur: {
      'nomorFaktur': kodeFaktur.isEmpty ? 'Manual-${r['id']}' : kodeFaktur,
      'namaSupplier': r['namaSupplier'] ?? 'Supplier faktur asal',
    });
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muatRiwayat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (Sesi.instance.bolehKelola) ...[
            AppFormSection(
              judul: 'Retur Pembelian Baru',
              deskripsi:
                  'Utamakan pilih faktur asal agar seluruh item dapat diretur dalam satu permintaan dan dicetak. Pencarian produk manual tetap tersedia untuk data lama.',
              children: [
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _mencari ? null : _pilihFakturAsal,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(_fakturTerpilih == null
                          ? 'Pilih Faktur Pembelian'
                          : 'Ganti Faktur Pembelian'),
                    ),
                  ),
                  if (_fakturTerpilih != null) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Lepaskan faktur',
                      onPressed: () => setStateIfMounted(() {
                        _fakturTerpilih = null;
                        _items.clear();
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ]),
                if (_fakturTerpilih != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.latarLembut(AppColors.primary),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.receipt_long_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_fakturTerpilih!['nomorFaktur'] ?? '-'}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                              '${_fakturTerpilih!['namaSupplier'] ?? 'Tanpa supplier'} · ${_fakturTerpilih!['tanggalFaktur'] ?? '-'}',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                      'Centang item yang benar-benar dikembalikan. Jumlah retur tidak boleh melebihi jumlah pada faktur.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
                const SizedBox(height: 12),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tambahkan produk manual (opsional)',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: PencarianProdukBanbox(
                        controller: _barcodeController,
                        tampilkanScanner: false,
                        label: 'Kode / Barcode / Nama Produk',
                        icon: Icons.search,
                        onPilih: _cariProduk,
                        decorationBuilder: (context) =>
                            AppFormStyle.fieldDecoration(context,
                                labelText: 'Kode / Barcode / Nama Produk',
                                prefixIcon: const Icon(Icons.search)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _scanKamera,
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'Scan pakai kamera'),
                  ],
                ),
                if (_mencari)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Center(child: CircularProgressIndicator())),
                if (_errorForm != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_errorForm!,
                          style: TextStyle(color: Colors.red.shade700)),
                      AppDetailGalatOpsional(detail: detailUntuk(_errorForm)),
                    ]),
                  ),
                if (_produkDitemukan != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.warning),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_produkDitemukan!['nama'] ?? ''}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qtyController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: 'Jumlah Retur *',
                                    isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _hargaController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: 'Harga Satuan',
                                    isDense: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _alasan,
                          decoration: AppFormStyle.fieldDecoration(context,
                              labelText: 'Alasan', isDense: true),
                          items: _daftarAlasanRetur
                              .map((a) =>
                                  DropdownMenuItem(value: a, child: Text(a)))
                              .toList(),
                          onChanged: (v) =>
                              setStateIfMounted(() => _alasan = v ?? _alasan),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                              onPressed: _tambahKeDaftar,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Tambah ke Daftar')),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Barang yang Diretur',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ..._items.asMap().entries.map((e) {
                    final it = e.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          Checkbox(
                            value: it.dipilih,
                            onChanged: (v) => setStateIfMounted(
                                () => it.dipilih = v ?? false),
                          ),
                          Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it.nama,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  if (it.kode.isNotEmpty)
                                    Text(it.kode,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54)),
                                ],
                              )),
                          const SizedBox(width: 8),
                          SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: _formatAngka.format(it.qty),
                                enabled: it.dipilih,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: it.qtyMaksimal == null
                                        ? 'Qty'
                                        : 'Qty (maks ${_formatAngka.format(it.qtyMaksimal)})',
                                    isDense: true),
                                onChanged: (v) {
                                  final nilai = parseDesimal(v) ?? 0;
                                  setStateIfMounted(() {
                                    it.qty = it.qtyMaksimal == null
                                        ? nilai
                                        : nilai
                                            .clamp(0, it.qtyMaksimal!)
                                            .toDouble();
                                  });
                                },
                              )),
                          const SizedBox(width: 8),
                          SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                value: it.alasan,
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: 'Alasan',
                                    isDense: true),
                                items: _daftarAlasanRetur
                                    .map((a) => DropdownMenuItem(
                                        value: a, child: Text(a)))
                                    .toList(),
                                onChanged: it.dipilih
                                    ? (v) => setStateIfMounted(
                                        () => it.alasan = v ?? it.alasan)
                                    : null,
                              )),
                          const SizedBox(width: 8),
                          SizedBox(
                              width: 110,
                              child: Text(
                                _formatRupiah.format(it.total),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12),
                              )),
                          if (_fakturTerpilih == null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _hapusDariDaftar(e.key),
                            ),
                        ]),
                      ),
                    );
                  }),
                  const Divider(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Nilai Retur',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        Text(_formatRupiah.format(_totalNilai),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton.icon(
                      onPressed: _itemsAktif.isEmpty
                          ? null
                          : () => _pratinjauItems(_itemsAktif),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Pratinjau & Cetak'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _menyimpan || _itemsAktif.isEmpty
                          ? null
                          : _simpanRetur,
                      icon: _menyimpan
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Simpan Retur Pembelian'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12)),
                    ),
                  ]),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                  'Hanya admin/supervisor toko yang dapat mencatat Retur Pembelian. Riwayat di bawah tetap bisa dilihat.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic)),
            ),
          const Text('Riwayat Retur Pembelian',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          BannerPerubahanServer(
            key: ValueKey('perubahan:${_diff.versi}'),
            baru: _diff.idBaru.length,
            berubah: _diff.idBerubah.length,
            dihapus: _diff.jumlahHapus,
          ),
          if (_memuatRiwayat)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()))
          else if (_errorRiwayat != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_errorRiwayat!),
                  AppDetailGalatOpsional(detail: detailUntuk(_errorRiwayat)),
                ])))
          else
            AppDataTable(
              minWidth: 800,
              emptyText: 'Belum ada riwayat retur pembelian.',
              columns: const [
                AppTableColumn('Faktur Asal', flex: 2),
                AppTableColumn('Produk', flex: 3),
                AppTableColumn('Waktu', flex: 2),
                AppTableColumn('Qty', flex: 1, align: TextAlign.right),
                AppTableColumn('Alasan', flex: 2),
                AppTableColumn('Total', flex: 2, align: TextAlign.right),
                AppTableColumn('', flex: 1),
              ],
              rows: _riwayat.map((r) {
                return AppTableRowData(cells: [
                  AppTableCell.text('${r['kodeFakturAsal'] ?? '-'}', flex: 2),
                  AppTableCell(
                    flex: 3,
                    child: KilauBaris(
                      kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                      idBaru: _diff.idBaru,
                      idBerubah: _diff.idBerubah,
                      child: Text('${r['namaProduk']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  AppTableCell.text('${r['waktu']}', flex: 2),
                  AppTableCell.text('${_formatAngka.format(r['qty'] ?? 0)}x',
                      flex: 1, align: TextAlign.right),
                  AppTableCell.text('${r['alasan'] ?? '-'}', flex: 2),
                  AppTableCell.text(_formatRupiah.format(r['totalNilai'] ?? 0),
                      flex: 2,
                      align: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12.5)),
                  AppTableCell(
                    flex: 1,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Pratinjau & cetak retur',
                        icon: const Icon(Icons.print_outlined, size: 18),
                        onPressed: () => _cetakRiwayat(r),
                      ),
                      if (Sesi.instance.bolehKelola)
                        IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: AppColors.danger),
                            onPressed: () => _hapusBaris(r)),
                    ]),
                  ),
                ]);
              }).toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _total,
                labelData: 'retur',
                onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                onBerikutnya: _halaman < _totalHalaman
                    ? () => _pindah(_halaman + 1)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
