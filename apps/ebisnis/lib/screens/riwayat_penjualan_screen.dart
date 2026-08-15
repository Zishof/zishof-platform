import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_shell.dart';
import 'struk_screen.dart';
import 'riwayat_penjualan_analisis_screen.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggalServer = DateFormat('yyyy-MM-dd');

/// Cache-first (spec: "Riwayat Penjualan online-only, tanpa cache lokal") --
/// hanya utk tampilan DEFAULT tanpa filter halaman 1 (yg paling sering
/// dibuka), disimpan lewat `cache_referensi` generik (kunci->JSON) yg SUDAH
/// ADA di core_db, bukan tabel baru -- cukup utk "masih bisa lihat transaksi
/// terakhir walau offline sesaat", bukan pengganti data real-time.
const _kunciCacheRiwayat = 'riwayat_penjualan_default';

List<Map<String, dynamic>> _normalisasiDaftarTransaksi(
    Map<String, dynamic> hasil) {
  dynamic raw = hasil['data'];
  if (raw is Map) {
    raw = raw['rows'] ?? raw['items'] ?? raw['list'] ?? raw['data'];
  }
  raw ??= hasil['rows'] ??
      hasil['items'] ??
      hasil['list'] ??
      hasil['orders'] ??
      hasil['transaksi'] ??
      hasil['riwayat'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => _normalisasiTransaksi(Map<String, dynamic>.from(row)))
      .toList();
}

class _BarisKoreksiTransaksi {
  _BarisKoreksiTransaksi({
    this.pembelianId,
    required this.produkId,
    required this.nama,
    required this.harga,
    required double qty,
  }) : qtyController = TextEditingController(text: _formatQtyKoreksi(qty));

  final dynamic pembelianId;
  final dynamic produkId;
  final String nama;
  final double harga;
  final TextEditingController qtyController;

  void dispose() => qtyController.dispose();
}

String _formatQtyKoreksi(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

class _DialogEditTransaksi extends StatefulWidget {
  const _DialogEditTransaksi({required this.nomor, required this.items});

  final String nomor;
  final List<Map<String, dynamic>> items;

  @override
  State<_DialogEditTransaksi> createState() => _DialogEditTransaksiState();
}

class _DialogEditTransaksiState extends State<_DialogEditTransaksi> {
  final _alasanController = TextEditingController();
  final _cariController = TextEditingController();
  late final List<_BarisKoreksiTransaksi> _baris;
  List<Map<String, dynamic>> _hasilCari = [];
  bool _mencari = false;
  String? _pesan;

  @override
  void initState() {
    super.initState();
    _baris = widget.items
        .map((i) => _BarisKoreksiTransaksi(
              pembelianId: i['pembelianId'],
              produkId: i['produkId'],
              nama: '${i['nama'] ?? 'Produk'}',
              harga: (i['harga'] as num?)?.toDouble() ?? 0,
              qty: (i['qty'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final b in _baris) {
      b.dispose();
    }
    _alasanController.dispose();
    _cariController.dispose();
    super.dispose();
  }

  Future<void> _cariProduk() async {
    final kata = _cariController.text.trim();
    if (kata.length < 2) {
      setState(() =>
          _pesan = 'Ketik sedikitnya 2 karakter kode, barcode, atau nama.');
      return;
    }
    setState(() {
      _mencari = true;
      _pesan = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('katalog', {
        'keyword': kata,
        'page': 1,
        'pageSize': 15,
      });
      if (!mounted) return;
      setState(() => _hasilCari = ((hasil['produk'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList());
    } catch (e) {
      if (mounted) {
        setState(() => _pesan =
            'Produk belum dapat dicari. Periksa koneksi, lalu coba kembali.');
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'mencari produk untuk koreksi transaksi');
      }
    } finally {
      if (mounted) setState(() => _mencari = false);
    }
  }

  void _tambahkan(Map<String, dynamic> produk) {
    final pid = '${produk['id']}';
    for (final b in _baris) {
      if ('${b.produkId}' == pid) {
        final lama = double.tryParse(b.qtyController.text) ?? 0;
        b.qtyController.text = _formatQtyKoreksi(lama + 1);
        setState(() => _hasilCari = []);
        return;
      }
    }
    setState(() {
      _baris.add(_BarisKoreksiTransaksi(
        produkId: produk['id'],
        nama: '${produk['nama'] ?? 'Produk'}',
        harga: (produk['hargaJual'] as num?)?.toDouble() ?? 0,
        qty: 1,
      ));
      _hasilCari = [];
    });
  }

  void _simpan() {
    final alasan = _alasanController.text.trim();
    if (alasan.length < 5) {
      setState(() => _pesan = 'Alasan koreksi minimal 5 karakter.');
      return;
    }
    if (_baris.isEmpty) {
      setState(
          () => _pesan = 'Transaksi harus memiliki sedikitnya satu barang.');
      return;
    }
    final item = <Map<String, dynamic>>[];
    for (var i = 0; i < _baris.length; i++) {
      final qty = double.tryParse(
          _baris[i].qtyController.text.trim().replaceAll(',', '.'));
      if (qty == null || qty <= 0) {
        setState(
            () => _pesan = 'Jumlah pada baris ${i + 1} harus lebih dari nol.');
        return;
      }
      item.add({
        if (_baris[i].pembelianId != null)
          'pembelian_id': _baris[i].pembelianId,
        'produk_id': _baris[i].produkId,
        'qty': qty,
      });
    }
    Navigator.of(context).pop({'alasan': alasan, 'item': item});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Transaksi ${widget.nomor}'),
      content: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Text(
                'Khusus Supervisor. Perubahan akan menghitung ulang total dan stok serta menyimpan rincian sebelum/sesudah pada audit JSON. Transaksi yang sudah diposting atau memiliki retur tidak dapat diedit.',
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cariController,
                  onSubmitted: (_) => _cariProduk(),
                  decoration: const InputDecoration(
                    labelText: 'Tambah produk (kode / barcode / nama)',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _mencari ? null : _cariProduk,
                icon: _mencari
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add),
                label: const Text('Cari'),
              ),
            ]),
            if (_hasilCari.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: ListView(
                  shrinkWrap: true,
                  children: _hasilCari
                      .map((p) => ListTile(
                            dense: true,
                            title:
                                Text('${p['kode'] ?? ''} — ${p['nama'] ?? ''}'),
                            subtitle: Text(
                                '${_formatRupiah.format(p['hargaJual'] ?? 0)} · stok ${p['stok'] ?? 0}'),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () => _tambahkan(p),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 10),
            const Text('Rincian setelah koreksi',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                itemCount: _baris.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final b = _baris[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(b.nama),
                    subtitle: Text(_formatRupiah.format(b.harga)),
                    trailing: SizedBox(
                      width: 220,
                      child: Row(children: [
                        IconButton(
                          tooltip: 'Kurangi',
                          onPressed: () {
                            final n =
                                double.tryParse(b.qtyController.text) ?? 1;
                            if (n > 1) {
                              b.qtyController.text = _formatQtyKoreksi(n - 1);
                            }
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Expanded(
                          child: TextField(
                            controller: b.qtyController,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Jumlah'),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tambah',
                          onPressed: () {
                            final n =
                                double.tryParse(b.qtyController.text) ?? 0;
                            b.qtyController.text = _formatQtyKoreksi(n + 1);
                          },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Hapus barang',
                          color: Colors.red,
                          onPressed: () => setState(() {
                            final dihapus = _baris.removeAt(index);
                            dihapus.dispose();
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            TextField(
              controller: _alasanController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan koreksi *',
                hintText: 'Contoh: tiga barang pada struk belum tersimpan',
              ),
            ),
            if (_pesan != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_pesan!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        FilledButton.icon(
          onPressed: _simpan,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Simpan Koreksi'),
        ),
      ],
    );
  }
}

Map<String, dynamic> _normalisasiTransaksi(Map<String, dynamic> row) {
  dynamic pilih(List<String> kunci) {
    for (final k in kunci) {
      final v = row[k];
      if (v != null && v.toString().trim().isNotEmpty) return v;
    }
    return null;
  }

  return {
    ...row,
    'idTransaksi': pilih([
      'idTransaksi',
      'transaksiId',
      'pembelianAnggotaKoperasiId',
      'pembelianId',
      'orderId',
      'id',
    ]),
    'nomorNota': pilih([
          'nomorNota',
          'nomorTransaksi',
          'noTransaksi',
          'kodeTransaksi',
          'kode',
          'kodeUnik',
          'nomorIdOrder',
          'noNota',
        ]) ??
        '-',
    'waktu': pilih([
      'waktu',
      'tanggal',
      'tanggalTransaksi',
      'tglTransaksi',
      'createdAt',
      'dibuatPada',
    ]),
    'pembeli': pilih([
          'pembeli',
          'namaPembeli',
          'pelanggan',
          'namaPelanggan',
          'memberNama',
          'anggotaNama',
          'customerNama',
        ]) ??
        'Umum',
    'totalBiaya': pilih([
          'totalBiaya',
          'total_biaya',
          'grandTotal',
          'totalBayar',
          'totalPenjualan',
          'total',
          'nilai',
        ]) ??
        0,
    'metode': pilih([
          'metode',
          'metodePembayaran',
          'caraBayar',
          'cara_bayar',
          'jenisPembayaran',
        ]) ??
        '-',
    'kasir': pilih(['kasir', 'namaKasir', 'operator', 'petugas']),
    'namaMesin': pilih(['namaMesin', 'mesin', 'perangkat', 'deviceName']),
    'pajak': pilih(['pajak', 'totalPajak']) ?? 0,
    'totalDiskon': pilih(['totalDiskon', 'diskon', 'nilaiDiskon']) ?? 0,
  };
}

int _normalisasiTotalTransaksi(Map<String, dynamic> hasil, int jumlahData) {
  final kandidat = <dynamic>[
    hasil['total'],
    hasil['totalData'],
    hasil['totalRows'],
    hasil['recordsTotal'],
    hasil['count'],
    hasil['jumlah'],
    hasil['totalTransaksi'],
  ];
  final data = hasil['data'];
  if (data is Map) {
    kandidat.addAll([
      data['total'],
      data['totalData'],
      data['totalRows'],
      data['recordsTotal'],
      data['count'],
      data['jumlah'],
    ]);
  }
  for (final v in kandidat) {
    if (v is num) return v.toInt();
    final parsed = int.tryParse(v?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return jumlahData;
}

String _formatWaktu(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

/// Layar Riwayat Penjualan (spec §11) -- SENGAJA terpisah dari Laporan
/// Transaksi: yang ini alat sempit "cari transaksi lunas lalu cetak ulang
/// strukn ya", bukan dasbor analitik/agregat. Tidak ada aksi server baru --
/// reuse `laporan_order_list` (cari) + `detail_transaksi` (rincian fiskal +
/// bahan cetak ulang), persis pola tab "Report Order" di Laporan Transaksi.
class RiwayatPenjualanScreen extends StatefulWidget {
  const RiwayatPenjualanScreen({super.key});
  @override
  State<RiwayatPenjualanScreen> createState() => _RiwayatPenjualanScreenState();
}

class _RiwayatPenjualanScreenState extends State<RiwayatPenjualanScreen> {
  final Map<String, String> _kunciPembatalan = {};
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  double _omzetTotal = 0;
  DateTime? _mulai;
  DateTime? _sampai;
  String _cariPembeli = '';
  bool _hanyaTransaksiTidakValid = false;

  @override
  void initState() {
    super.initState();
    final hariIni = DateTime.now();
    _mulai = DateTime(hariIni.year, hariIni.month, hariIni.day);
    _sampai = DateTime(hariIni.year, hariIni.month, hariIni.day);
    _muat();
  }

  bool get _defaultTanpaFilter {
    final hariIni = _formatTanggalServer.format(DateTime.now());
    return _mulai != null &&
        _sampai != null &&
        _formatTanggalServer.format(_mulai!) == hariIni &&
        _formatTanggalServer.format(_sampai!) == hariIni &&
        _cariPembeli.isEmpty &&
        !_hanyaTransaksiTidakValid &&
        _halaman == 1;
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final payload = {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        if (_cariPembeli.isNotEmpty) 'keyword': _cariPembeli,
        'includePembayaran': true,
        'includeSplitPembayaran': true,
        'sertakanPembayaran': true,
        'withPayments': true,
        'transaksiTidakValid': _hanyaTransaksiTidakValid,
        'page': _halaman,
        'pageSize': _pageSize,
      };
      var hasil = await ApiClient.instance.aksi('laporan_order_list', payload);
      var data = _normalisasiDaftarTransaksi(hasil);
      if (data.isEmpty && _cariPembeli.isNotEmpty) {
        final fallback = {...payload}..remove('keyword');
        fallback['cariPembeli'] = _cariPembeli;
        hasil = await ApiClient.instance.aksi('laporan_order_list', fallback);
        data = _normalisasiDaftarTransaksi(hasil);
      }
      setStateIfMounted(() {
        _data = data;
        _total = _normalisasiTotalTransaksi(hasil, data.length);
        _omzetTotal = (hasil['totalNilai'] as num?)?.toDouble() ??
            data.fold<double>(
                0, (a, r) => a + ((r['totalBiaya'] as num?)?.toDouble() ?? 0));
      });
      if (_defaultTanpaFilter) {
        unawaited(CoreDb.instance
            .simpanCacheReferensi(_kunciCacheRiwayat, jsonEncode(hasil)));
      }
    } catch (e) {
      // Offline & sedang melihat tampilan default (bukan hasil filter) --
      // pakai snapshot terakhir yg tersimpan drpd layar kosong tak berguna.
      if (_defaultTanpaFilter) {
        final tersimpan =
            await CoreDb.instance.ambilCacheReferensi(_kunciCacheRiwayat);
        if (tersimpan != null) {
          final hasil = jsonDecode(tersimpan) as Map<String, dynamic>;
          final data = _normalisasiDaftarTransaksi(hasil);
          setStateIfMounted(() {
            _data = data;
            _total = _normalisasiTotalTransaksi(hasil, data.length);
            _omzetTotal = (hasil['totalNilai'] as num?)?.toDouble() ??
                data.fold<double>(0,
                    (a, r) => a + ((r['totalBiaya'] as num?)?.toDouble() ?? 0));
            _error = null;
          });
          if (mounted) setStateIfMounted(() => _memuat = false);
          return;
        }
      }
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _terapkan() async {
    _halaman = 1;
    await _muat();
  }

  Widget _chipRingkasan(String label, String nilai, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.latarLembut(warna),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $nilai',
          style: TextStyle(
              color: warna, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Future<void> _lihatDetail(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items =
          ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      final pajakHeader = (row['pajak'] as num?)?.toDouble() ?? 0;
      final diskonHeader = (row['totalDiskon'] as num?)?.toDouble() ?? 0;
      final subtotalPerBaris = items
          .map((i) =>
              (i['harga'] as num).toDouble() * (i['qty'] as num).toDouble() -
              ((i['diskon'] as num?) ?? 0).toDouble())
          .toList();
      final totalSubtotal = subtotalPerBaris.fold<double>(0, (s, v) => s + v);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detail ${hasil['kode'] ?? ''}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chipRingkasan('Diskon', _formatRupiah.format(diskonHeader),
                        AppColors.warning),
                    _chipRingkasan('Pajak', _formatRupiah.format(pajakHeader),
                        AppColors.teal),
                    _chipRingkasan(
                        'Bayar',
                        _formatRupiah.format(hasil['totalBiaya'] ?? 0),
                        AppColors.success),
                  ]),
                  if (row['transaksiTidakValid'] == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.danger),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Transaksi tidak valid: total master ${_formatRupiah.format(row['totalMaster'] ?? 0)}, total rincian ${_formatRupiah.format(row['totalDetail'] ?? 0)}, selisih ${_formatRupiah.format(row['selisihTotal'] ?? 0)}.',
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Divider(),
                  ...List.generate(items.length, (idx) {
                    final i = items[idx];
                    final subtotal = subtotalPerBaris[idx];
                    final pajakBaris = totalSubtotal > 0
                        ? pajakHeader * (subtotal / totalSubtotal)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${i['nama']} x${(i['qty'] as num).toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            'Harga ${_formatRupiah.format(i['harga'])} · Diskon ${_formatRupiah.format(i['diskon'] ?? 0)} · Pajak ${_formatRupiah.format(pajakBaris)} · Subtotal ${_formatRupiah.format(subtotal)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            if (hasil['bolehEditTransaksi'] == true)
              TextButton.icon(
                icon: const Icon(Icons.edit_note_outlined, size: 19),
                label: const Text('Edit Transaksi'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _editTransaksi(row, hasil, items);
                },
              ),
            if (Sesi.instance.bolehAksiPos('riwayatpenjualan', 'delete') ||
                Sesi.instance.bolehAksiPos('riwayatpenjualan', 'reject'))
              TextButton.icon(
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Batalkan Transaksi'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  Navigator.of(context).pop();
                  _batalkanTransaksi(row);
                },
              ),
            TextButton.icon(
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Cetak Struk'),
              onPressed: () {
                Navigator.of(context).pop();
                _cetakUlang(row, hasil, items);
              },
            ),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _batalkanTransaksi(Map<String, dynamic> row) async {
    final alasanController = TextEditingController();
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan Transaksi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Transaksi ${row['nomorNota'] ?? ''} akan dibatalkan. Stok dan saldo terkait akan dikoreksi, serta pembatalan dicatat dalam arsip audit.'),
            const SizedBox(height: 16),
            TextField(
              controller: alasanController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alasan pembatalan *',
                hintText: 'Contoh: transaksi ganda atau salah input kasir',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    final alasan = alasanController.text.trim();
    alasanController.dispose();
    if (setuju != true) return;
    if (alasan.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      }
      return;
    }
    try {
      final id = '${row['idTransaksi']}';
      final key = _kunciPembatalan.putIfAbsent(
          id, () => 'BATAL-$id-${DateTime.now().microsecondsSinceEpoch}');
      final hasil = await ApiClient.instance.aksi('batalkan_transaksi', {
        'id': row['idTransaksi'],
        'alasan': alasan,
        'idempotency_key': key,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hasil['description']?.toString() ??
              'Transaksi berhasil dibatalkan.')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _editTransaksi(Map<String, dynamic> row,
      Map<String, dynamic> detail, List<Map<String, dynamic>> items) async {
    final hasilEdit = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogEditTransaksi(
        nomor: '${detail['kode'] ?? row['nomorNota'] ?? ''}',
        items: items,
      ),
    );
    if (hasilEdit == null || !mounted) return;
    try {
      final hasil = await ApiClient.instance.aksi('edit_transaksi', {
        'id': row['idTransaksi'],
        'alasan': hasilEdit['alasan'],
        'item': hasilEdit['item'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hasil['description']?.toString() ??
              'Transaksi berhasil dikoreksi.')));
      await _muat();
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'edit transaksi');
      }
    }
  }

  Future<void> _cetakUlang(Map<String, dynamic> row,
      Map<String, dynamic> detail, List<Map<String, dynamic>> items) async {
    final itemStruk = items
        .map((i) => {
              'nama': i['nama'],
              'qty': i['qty'],
              'harga': i['harga'],
              'diskon': i['diskon'] ?? 0,
              'cashback': i['cashback'] ?? 0,
            })
        .toList();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StrukScreen(
        kode: '${detail['kode'] ?? row['nomorNota'] ?? ''}',
        waktu: _formatWaktu(row['waktu']),
        item: itemStruk,
        total: (detail['totalBiaya'] as num?)?.toDouble() ??
            (row['totalBiaya'] as num?)?.toDouble() ??
            0,
        metode: '${row['metode'] ?? ''}',
        pembayaran: StrukScreen.pembayaranDariSumber(detail, row),
        pajak: (row['pajak'] as num?)?.toDouble() ?? 0,
        pelanggan: '${detail['pembeli'] ?? row['pembeli'] ?? ''}',
      ),
    ));
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.riwayatPenjualan,
      judul: 'Riwayat Penjualan',
      subjudul: 'Cari transaksi lunas & cetak ulang struk',
      scrollable: false,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: const Text('Analisis Penjualan'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RiwayatPenjualanAnalisisScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  SizedBox(
                      width: 190,
                      child: AppKpiCard(
                          icon: Icons.receipt_long,
                          warna: AppColors.primary,
                          nilai: '$_total',
                          label: 'Total Transaksi')),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 190,
                    child: AppKpiCard(
                      icon: Icons.payments_outlined,
                      warna: AppColors.success,
                      nilai: _formatRupiah.format(_omzetTotal),
                      label: _mulai != null &&
                              _sampai != null &&
                              _formatTanggalServer.format(_mulai!) ==
                                  _formatTanggalServer.format(_sampai!)
                          ? 'Omzet ${_formatTanggalServer.format(_mulai!)}'
                          : 'Omzet seluruh hasil filter',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final v = await showDatePicker(
                                context: context,
                                initialDate: _mulai ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (v != null) {
                              _mulai = v;
                              await _terapkan();
                            }
                          },
                          child: Text(_mulai == null
                              ? 'Dari Tanggal'
                              : _formatTanggalServer.format(_mulai!)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final v = await showDatePicker(
                                context: context,
                                initialDate: _sampai ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now());
                            if (v != null) {
                              _sampai = v;
                              await _terapkan();
                            }
                          },
                          child: Text(_sampai == null
                              ? 'Sampai Tanggal'
                              : _formatTanggalServer.format(_sampai!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final pencarian = AppSearchField(
                        hintText: 'Cari nama pembeli / nomor nota...',
                        debounce: const Duration(milliseconds: 450),
                        onChanged: (v) {
                          _cariPembeli = v;
                          _terapkan();
                        },
                      );
                      final filterTidakValid = SizedBox(
                        width: 250,
                        child: CheckboxListTile(
                          value: _hanyaTransaksiTidakValid,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 0),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Transaksi tidak valid'),
                          subtitle: const Text('Total master ≠ total rincian'),
                          onChanged: (value) {
                            setState(() =>
                                _hanyaTransaksiTidakValid = value ?? false);
                            _terapkan();
                          },
                        ),
                      );
                      if (constraints.maxWidth < 700) {
                        return Column(
                          children: [
                            pencarian,
                            Align(
                                alignment: Alignment.centerLeft,
                                child: filterTidakValid),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: pencarian),
                          const SizedBox(width: 12),
                          filterTidakValid,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_memuat)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(_error!)))
            else
              AppDataTable(
                minWidth: 980,
                emptyText: 'Belum ada transaksi pada rentang ini.',
                columns: const [
                  AppTableColumn('Nota', flex: 4),
                  AppTableColumn('Waktu', flex: 2),
                  AppTableColumn('Pembeli', flex: 2),
                  AppTableColumn('Kasir / Mesin', flex: 2),
                  AppTableColumn('Metode', flex: 2),
                  AppTableColumn('Total', flex: 2, align: TextAlign.right),
                  AppTableColumn('Aksi', width: 74, align: TextAlign.center),
                ],
                rows: _data.map((row) {
                  final kasir = '${row['kasir'] ?? '-'}';
                  final mesin = '${row['namaMesin'] ?? ''}'.trim();
                  final kasirMesin = mesin.isEmpty ? kasir : '$kasir / $mesin';
                  return AppTableRowData(
                    onTap: () => _lihatDetail(row),
                    cells: [
                      AppTableCell.text('${row['nomorNota'] ?? '-'}',
                          flex: 4,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
                      AppTableCell.text('${row['pembeli'] ?? 'Umum'}', flex: 2),
                      AppTableCell.text(kasirMesin, flex: 2),
                      AppTableCell(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusPill(
                              label: StrukScreen.labelPembayaran(row),
                              warna: AppColors.primary),
                        ),
                      ),
                      AppTableCell(
                        flex: 2,
                        align: TextAlign.right,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatRupiah.format(row['totalBiaya'] ?? 0),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: row['transaksiTidakValid'] == true
                                    ? AppColors.danger
                                    : null,
                              ),
                            ),
                            if (row['transaksiTidakValid'] == true)
                              Text(
                                'Selisih ${_formatRupiah.format(row['selisihTotal'] ?? 0)}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      AppTableCell(
                        width: 74,
                        align: TextAlign.center,
                        child: Tooltip(
                          message: 'Detail transaksi',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon:
                                const Icon(Icons.visibility_outlined, size: 18),
                            onPressed: () => _lihatDetail(row),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                pagination: _total > _pageSize
                    ? AppTablePagination(
                        halaman: _halaman,
                        totalHalaman: _totalHalaman,
                        totalData: _total,
                        labelData: 'transaksi',
                        onSebelumnya:
                            _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                        onBerikutnya: _halaman < _totalHalaman
                            ? () => _pindah(_halaman + 1)
                            : null,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
