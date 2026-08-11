import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

final _rp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Kasir Apotik -- FASE A varian "POS Apotik".</h3>
///
/// Empat aturan yang MEMBEDAKAN apotek (perintah awal LANGKAH 3), semuanya
/// ditegakkan server (`apotik_bayar`) dan dicerminkan UI ini:
/// - TEBUS RESEP: memilih resep (`apotik_resep_list/detail`), bukan mengetik
///   obat satu per satu; baris racikan ditampilkan TERKUNCI dgn alasan jujur
///   (penyerahan racikan menyusul -- flag `adaRacikan` dari server).
/// - BATCH & KEDALUWARSA: item ber-batch wajib pilih batch; urutan FEFO
///   (terdekat kedaluwarsa dulu) dgn prefill otomatis; batch kedaluwarsa
///   TIDAK BISA dipilih sama sekali (dan server tetap menolaknya).
/// - OBAT TERKENDALI: menambah item narkotika/psikotropika memunculkan blok
///   register (pembeli + dokter/resep) yang WAJIB terisi -- transaksi DITAHAN
///   server bila register tak bisa dibuat.
/// - LASA: nama obat mirip ditampilkan BERBEDA (badge kuning + huruf tebal
///   sebagian) supaya tidak tertukar di daftar hasil cari.
class KasirApotikScreen extends StatefulWidget {
  const KasirApotikScreen({super.key});

  @override
  State<KasirApotikScreen> createState() => _KasirApotikScreenState();
}

class _BarisKeranjang {
  final Map<String, dynamic> item;
  double qty;
  double harga;
  // batch terpilih: [{kadaluarsa_id, qty, tanggal}]
  List<Map<String, dynamic>> batch;
  _BarisKeranjang(this.item, this.qty, this.harga, this.batch);

  bool get terkendali => item['terkendali'] == true;
  double get subtotal => qty * harga;
}

class _KasirApotikScreenState extends State<KasirApotikScreen> {
  final _cari = TextEditingController();
  final _namaPembeli = TextEditingController();
  final _alamatPembeli = TextEditingController();
  final _namaDokter = TextEditingController();
  Timer? _debounce;
  bool _mencari = false;
  List<Map<String, dynamic>> _hasilCari = [];
  final List<_BarisKeranjang> _keranjang = [];
  int? _resepId;
  String _resepKode = '';
  bool _memproses = false;

  bool get _adaTerkendali => _keranjang.any((b) => b.terkendali);

  @override
  void dispose() {
    _debounce?.cancel();
    _cari.dispose();
    _namaPembeli.dispose();
    _alamatPembeli.dispose();
    _namaDokter.dispose();
    super.dispose();
  }

  void _cariBerubah(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _jalankanCari(v));
  }

  Future<void> _jalankanCari(String v) async {
    if (v.trim().isEmpty) {
      setStateIfMounted(() => _hasilCari = []);
      return;
    }
    setStateIfMounted(() => _mencari = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('apotik_item_cari', {'keyword': v.trim(), 'page_size': 20});
      setStateIfMounted(() =>
          _hasilCari = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal cari: $e')));
      }
    } finally {
      setStateIfMounted(() => _mencari = false);
    }
  }

  /// Tambah item; item ber-batch membuka sheet pilih batch (FEFO prefill).
  Future<void> _tambahItem(Map<String, dynamic> item, {double qty = 1}) async {
    List<Map<String, dynamic>> batchTerpilih = [];
    try {
      final hasil = await ApiClient.instance
          .aksi('apotik_item_batch', {'item_id': item['id']});
      final batches =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (batches.isNotEmpty) {
        if (!mounted) return;
        final pilihan = await showModalBottomSheet<List<Map<String, dynamic>>>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _SheetPilihBatch(
              namaItem: '${item['nama']}', batches: batches, qtyDiminta: qty),
        );
        if (pilihan == null) return; // batal
        batchTerpilih = pilihan;
        qty = pilihan.fold<double>(0, (a, b) => a + (b['qty'] as double));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal muat batch: $e')));
      }
      return;
    }
    setStateIfMounted(() {
      _keranjang.add(_BarisKeranjang(
          item, qty, ((item['hargaJual'] as num?) ?? 0).toDouble(), batchTerpilih));
    });
  }

  Future<void> _bukaTebusResep() async {
    final resep = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetPilihResep(),
    );
    if (resep == null || !mounted) return;
    try {
      final detail = await ApiClient.instance
          .aksi('apotik_resep_detail', {'resep_id': resep['id']});
      final rows =
          ((detail['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (detail['adaRacikan'] == true && mounted) {
        // Jujur, bukan diam-diam melewatkan baris (keterbatasan FASE A tercatat server).
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Resep memuat RACIKAN -- baris racikan belum bisa diserahkan lewat kasir ini dan dilewati.')));
      }
      setStateIfMounted(() {
        _resepId = (resep['id'] as num).toInt();
        _resepKode = '${resep['kode']}';
      });
      for (final r in rows.where((r) => r['racikan'] != true)) {
        await _tambahItem({
          'id': r['itemId'],
          'kode': r['kode'],
          'nama': r['nama'],
          'satuan': r['satuan'],
          'hargaJual': r['hargaJual'],
          'stok': r['stok'],
          'golonganObat': r['golonganObat'],
          'terkendali': r['terkendali'],
          'lasa': r['lasa'],
        }, qty: ((r['jumlah'] as num?) ?? 1).toDouble());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal muat resep: $e')));
      }
    }
  }

  Future<void> _bayar() async {
    if (_keranjang.isEmpty) return;
    if (_adaTerkendali) {
      if (_namaPembeli.text.trim().isEmpty ||
          (_resepId == null && _namaDokter.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Obat terkendali: nama pembeli WAJIB, plus resep atau nama dokter. Transaksi ditahan.')));
        return;
      }
    }
    setStateIfMounted(() => _memproses = true);
    // Kode idempoten dibuat SEKALI sebelum kirim -- retry memakai kode sama.
    final kode = 'APT${DateTime.now().millisecondsSinceEpoch}';
    try {
      final hasil = await ApiClient.instance.aksi('apotik_bayar', {
        'kode': kode,
        if (_resepId != null) 'resep_id': _resepId,
        if (_namaPembeli.text.trim().isNotEmpty ||
            _alamatPembeli.text.trim().isNotEmpty)
          'pembeli': {
            'nama': _namaPembeli.text.trim(),
            'alamat': _alamatPembeli.text.trim(),
          },
        if (_namaDokter.text.trim().isNotEmpty)
          'nama_dokter': _namaDokter.text.trim(),
        'items': _keranjang
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty': b.qty,
                  'harga_satuan': b.harga,
                  if (b.batch.isNotEmpty)
                    'batch': b.batch
                        .map((x) => {
                              'kadaluarsa_id': x['kadaluarsa_id'],
                              'qty': x['qty'],
                            })
                        .toList(),
                })
            .toList(),
      });
      if (!mounted) return;
      final total = ((hasil['total'] as num?) ?? 0).toDouble();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Transaksi Berhasil'),
          content: Text(
              'Kode: ${hasil['kode']}\nTotal: ${_rp.format(total)}\n\nStruk/cetak menyusul pada iterasi FASE A berikutnya.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          ],
        ),
      );
      setStateIfMounted(() {
        _keranjang.clear();
        _resepId = null;
        _resepKode = '';
        _namaPembeli.clear();
        _alamatPembeli.clear();
        _namaDokter.clear();
      });
    } catch (e) {
      if (mounted) {
        // Pesan penahan server (kedaluwarsa/terkendali/stok) ditampilkan APA ADANYA.
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Transaksi Ditahan'),
            content: Text('$e'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          ),
        );
      }
    } finally {
      setStateIfMounted(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lebar = MediaQuery.sizeOf(context).width;
    final desktop = lebar >= 900;
    final panelCari = _panelCari(context);
    final panelKeranjang = _panelKeranjang(context);
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(title: const Text('Kasir Apotik')),
      body: desktop
          ? Row(children: [
              Expanded(flex: 3, child: panelCari),
              const VerticalDivider(width: 1),
              Expanded(flex: 2, child: panelKeranjang),
            ])
          : Column(children: [
              Expanded(child: panelCari),
              const Divider(height: 1),
              SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.45,
                  child: panelKeranjang),
            ]),
    );
  }

  Widget _panelCari(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _cari,
              decoration: const InputDecoration(
                  hintText: 'Cari obat: kode / barcode / nama...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: _cariBerubah,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _bukaTebusResep,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Tebus Resep'),
          ),
        ]),
        if (_resepId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppInfoBanner(
                icon: Icons.description_outlined,
                color: AppColors.info,
                text: 'Menebus resep $_resepKode -- baris resep sudah dimuat ke keranjang.'),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _mencari
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _hasilCari.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = _hasilCari[i];
                    final lasa = it['lasa'] == true;
                    final terkendali = it['terkendali'] == true;
                    final stok = ((it['stok'] as num?) ?? 0).toDouble();
                    return ListTile(
                      dense: true,
                      // LASA tampil BERBEDA: badge + nama dgn penekanan huruf besar
                      // (tall-man lettering sederhana) supaya obat mirip tak tertukar.
                      title: Row(children: [
                        Expanded(
                          child: Text('${it['nama']}',
                              style: TextStyle(
                                  fontWeight:
                                      lasa ? FontWeight.w900 : FontWeight.w600,
                                  letterSpacing: lasa ? 1.2 : null,
                                  fontSize: 13.5)),
                        ),
                        if (lasa)
                          const StatusPill(
                              label: 'LASA', warna: Color(0xFFB8860B)),
                        if (terkendali) ...[
                          const SizedBox(width: 4),
                          StatusPill(
                              label: '${it['golonganObat']}',
                              warna: AppColors.danger),
                        ],
                      ]),
                      subtitle: Text(
                          '${it['kode']} • stok $stok ${it['satuan'] ?? ''} • ${_rp.format((it['hargaJual'] as num?) ?? 0)}',
                          style: const TextStyle(fontSize: 11.5)),
                      trailing: IconButton(
                          icon: const Icon(Icons.add_shopping_cart, size: 20),
                          onPressed: stok <= 0 ? null : () => _tambahItem(it)),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _panelKeranjang(BuildContext context) {
    final total = _keranjang.fold<double>(0, (a, b) => a + b.subtotal);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Keranjang (${_keranjang.length})',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _keranjang.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = _keranjang[i];
              return ListTile(
                dense: true,
                title: Text('${b.item['nama']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${b.qty} x ${_rp.format(b.harga)} = ${_rp.format(b.subtotal)}',
                          style: const TextStyle(fontSize: 11.5)),
                      if (b.batch.isNotEmpty)
                        Wrap(
                            spacing: 4,
                            children: b.batch
                                .map((x) => Chip(
                                    visualDensity: VisualDensity.compact,
                                    labelStyle: const TextStyle(fontSize: 10),
                                    label: Text(
                                        'ED ${x['tanggal']} × ${x['qty']}')))
                                .toList()),
                      if (b.terkendali)
                        const Text('OBAT TERKENDALI -- register wajib',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.red,
                                fontWeight: FontWeight.w700)),
                    ]),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    onPressed: () =>
                        setStateIfMounted(() => _keranjang.removeAt(i))),
              );
            },
          ),
        ),
        if (_adaTerkendali) ...[
          const Divider(),
          const Text('Register Obat Terkendali (WAJIB)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(height: 6),
          TextField(
              controller: _namaPembeli,
              decoration: const InputDecoration(
                  labelText: 'Nama pembeli/pasien *',
                  border: OutlineInputBorder(),
                  isDense: true)),
          const SizedBox(height: 6),
          TextField(
              controller: _alamatPembeli,
              decoration: const InputDecoration(
                  labelText: 'Alamat pembeli',
                  border: OutlineInputBorder(),
                  isDense: true)),
          const SizedBox(height: 6),
          TextField(
              controller: _namaDokter,
              decoration: InputDecoration(
                  labelText: _resepId != null
                      ? 'Nama dokter (opsional, resep sudah dipilih)'
                      : 'Nama dokter penulis resep *',
                  border: const OutlineInputBorder(),
                  isDense: true)),
        ],
        const Divider(),
        Row(children: [
          const Expanded(
              child: Text('Total',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          Text(_rp.format(total),
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _keranjang.isEmpty || _memproses ? null : _bayar,
          icon: _memproses
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.payments_outlined),
          label: const Text('Bayar (Tunai)'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ]),
    );
  }
}

/// Sheet pilih batch -- FEFO: urutan dari server sudah terdekat-kedaluwarsa
/// dulu dan prefill otomatis mengikutinya; batch kedaluwarsa DINONAKTIFKAN
/// total (bukan sekadar diperingatkan) -- server tetap lapis penahan akhir.
class _SheetPilihBatch extends StatefulWidget {
  final String namaItem;
  final List<Map<String, dynamic>> batches;
  final double qtyDiminta;
  const _SheetPilihBatch(
      {required this.namaItem, required this.batches, required this.qtyDiminta});

  @override
  State<_SheetPilihBatch> createState() => _SheetPilihBatchState();
}

class _SheetPilihBatchState extends State<_SheetPilihBatch> {
  late final Map<int, TextEditingController> _qty;

  @override
  void initState() {
    super.initState();
    _qty = {};
    // Prefill FEFO: penuhi qty diminta dari batch paling dekat kedaluwarsa dulu.
    var sisaMinta = widget.qtyDiminta;
    for (var i = 0; i < widget.batches.length; i++) {
      final b = widget.batches[i];
      final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
      final expired = b['kedaluwarsa'] == true;
      double ambil = 0;
      if (!expired && sisaMinta > 0 && sisa > 0) {
        ambil = sisaMinta < sisa ? sisaMinta : sisa;
        sisaMinta -= ambil;
      }
      _qty[i] = TextEditingController(
          text: ambil <= 0 ? '' : ambil.toStringAsFixed(0));
    }
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pilih Batch — ${widget.namaItem}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
              'Urutan FEFO (terdekat kedaluwarsa didahulukan). Batch kedaluwarsa terkunci.',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 10),
          ...List.generate(widget.batches.length, (i) {
            final b = widget.batches[i];
            final expired = b['kedaluwarsa'] == true;
            final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: expired
                    ? AppColors.latarLembut(AppColors.danger)
                    : AppColors.cardBgOf(context),
                border: Border.all(
                    color: expired
                        ? AppColors.danger
                        : AppColors.borderOf(context)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ED: ${b['tanggalKadaluarsa']}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: expired ? AppColors.danger : null)),
                        Text('Sisa: $sisa',
                            style: const TextStyle(fontSize: 11.5)),
                        if (expired)
                          const Text('KEDALUWARSA — TIDAK BOLEH DIJUAL',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w800)),
                      ]),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _qty[i],
                    enabled: !expired && sisa > 0,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Qty',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              final pilihan = <Map<String, dynamic>>[];
              for (var i = 0; i < widget.batches.length; i++) {
                final b = widget.batches[i];
                if (b['kedaluwarsa'] == true) continue;
                final q = double.tryParse(_qty[i]!.text.trim()) ?? 0;
                if (q <= 0) continue;
                final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
                if (q > sisa) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Qty batch ED ${b['tanggalKadaluarsa']} melebihi sisa ($sisa).')));
                  return;
                }
                pilihan.add({
                  'kadaluarsa_id': b['kadaluarsaId'],
                  'qty': q,
                  'tanggal': b['tanggalKadaluarsa'],
                });
              }
              if (pilihan.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Pilih minimal satu batch (qty > 0).')));
                return;
              }
              Navigator.pop(context, pilihan);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: const Text('Pakai Batch Ini'),
          ),
        ],
      ),
    );
  }
}

/// Sheet daftar resep menunggu tebus (`apotik_resep_list`, hanya_menunggu).
class _SheetPilihResep extends StatefulWidget {
  const _SheetPilihResep();

  @override
  State<_SheetPilihResep> createState() => _SheetPilihResepState();
}

class _SheetPilihResepState extends State<_SheetPilihResep> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  final _cari = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('apotik_resep_list', {
        if (_cari.text.trim().isNotEmpty) 'keyword': _cari.text.trim(),
        'hanya_menunggu': true,
        'page_size': 30,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Expanded(
                child: Text('Resep Menunggu Tebus',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _cari,
            decoration: const InputDecoration(
                hintText: 'Cari kode resep...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true),
            onSubmitted: (_) => _muat(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _data.isEmpty
                      ? const Center(
                          child: Text('Tidak ada resep menunggu tebus.'))
                      : ListView.separated(
                          controller: sc,
                          itemCount: _data.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _data[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.description_outlined),
                              title: Text('${r['kode']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${r['jumlahBaris']} baris'
                                  '${'${r['keterangan']}'.isEmpty ? '' : ' • ${r['keterangan']}'}',
                                  style: const TextStyle(fontSize: 11.5)),
                              onTap: () => Navigator.pop(context, r),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
