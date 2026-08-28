import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_shell.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/riwayat_data_dialog.dart';
import 'struk_screen.dart';
import 'riwayat_penjualan_analisis_screen.dart';
import 'riwayat_audit_screen.dart';
import '../widgets/safe_state.dart';
import '../services/transaksi_outbox_service.dart';
import '../services/transaksi_rekonsiliasi_service.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/aksi_baris_menu.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggalServer = DateFormat('yyyy-MM-dd');

/// BACA LOKAL-DULU (pola daftarCacheDulu, dihitung manual di layar ini krn
/// jalur bacanya kompleks -- lihat catatan di [_RiwayatPenjualanScreenState._muat])
/// -- hanya utk tampilan DEFAULT tanpa filter halaman 1 (yg paling sering
/// dibuka), disimpan lewat `cache_referensi` generik (kunci->JSON) yg SUDAH
/// ADA di core_db, bukan tabel baru: snapshot terakhir tampil seketika, hasil
/// server menyusul dgn kilau baris + banner perubahan (termasuk transaksi
/// baru dari kasir lain), bukan pengganti data real-time.
const _kunciCacheRiwayat = 'riwayat:penjualan';

/// Kunci diff satu baris transaksi utk kilau/banner -- id header nota bila
/// ada (server), fallback nomor nota (arsip lokal/server lama).
String _kunciDiffTransaksi(Map<String, dynamic> row) =>
    '${row['idTransaksi'] ?? row['nomorNota'] ?? ''}';

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

/// Filter "transaksi tidak valid" adalah audit konsistensi data di server:
/// total master dibandingkan dengan agregat rincian yang tersimpan di DB.
/// Arsip lokal tidak boleh ikut hanya karena tidak mempunyai kolom agregat
/// tersebut. Tanpa penyaringan ini, respons server yang benar-benar kosong
/// akan diisi kembali oleh seluruh transaksi lokal dan transaksi valid tampak
/// seolah-olah tidak valid.
@visibleForTesting
List<Map<String, dynamic>> saringArsipLokalUntukFilterIntegritas(
  List<Map<String, dynamic>> arsipLokal, {
  required bool hanyaTransaksiTidakValid,
}) {
  if (!hanyaTransaksiTidakValid) return arsipLokal;
  return arsipLokal.where((row) {
    // Hanya terima hasil audit eksplisit yang mempunyai kedua operand.
    // Payload kasir biasa tidak mempunyai totalMaster/totalDetail; statusnya
    // belum dapat dinilai sampai transaksi direkonsiliasi oleh server.
    return row['transaksiTidakValid'] == true &&
        row['totalMaster'] is num &&
        row['totalDetail'] is num;
  }).toList();
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
  const _DialogEditTransaksi({
    required this.nomor,
    required this.items,
    required this.waktu,
    required this.kasirUserId,
    required this.kasirNama,
    this.modeBaru = false,
    this.caraBayarId,
    this.caraBayarNama = '',
  });

  final String nomor;
  final List<Map<String, dynamic>> items;
  final DateTime waktu;
  final String kasirUserId;
  final String kasirNama;
  final bool modeBaru;
  final int? caraBayarId;
  final String caraBayarNama;

  @override
  State<_DialogEditTransaksi> createState() => _DialogEditTransaksiState();
}

class _DialogEditTransaksiState extends State<_DialogEditTransaksi> {
  final _alasanController = TextEditingController();
  final _cariController = TextEditingController();
  final _cariKasirController = TextEditingController();
  late final List<_BarisKoreksiTransaksi> _baris;
  List<Map<String, dynamic>> _hasilCari = [];
  bool _mencari = false;
  List<Map<String, dynamic>> _hasilCariKasir = [];
  bool _mencariKasir = false;
  late String _kasirUserId;
  late String _kasirNama;
  String? _pesan;
  late DateTime _waktu;
  int? _caraBayarId;

  @override
  void initState() {
    super.initState();
    _waktu = widget.waktu;
    _kasirUserId = widget.kasirUserId;
    _kasirNama = widget.kasirNama;
    _caraBayarId =
        widget.caraBayarId ?? _idCaraBayarDariNama(widget.caraBayarNama);
    _caraBayarId ??= Sesi.instance.caraBayar.isEmpty
        ? null
        : Sesi.instance.caraBayar.first.id;
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

  int? _idCaraBayarDariNama(String nama) {
    final teks = nama.trim().toLowerCase();
    if (teks.isEmpty) return null;
    for (final cara in Sesi.instance.caraBayar) {
      if (cara.nama.trim().toLowerCase() == teks) return cara.id;
    }
    return null;
  }

  @override
  void dispose() {
    for (final b in _baris) {
      b.dispose();
    }
    _alasanController.dispose();
    _cariController.dispose();
    _cariKasirController.dispose();
    super.dispose();
  }

  Future<void> _cariKasir() async {
    final kata = _cariKasirController.text.trim();
    if (kata.length < 2) {
      setState(
          () => _pesan = 'Ketik sedikitnya 2 karakter ID atau nama kasir.');
      return;
    }
    setState(() {
      _mencariKasir = true;
      _pesan = null;
    });
    try {
      final hasil = await ApiClient.instance
          .aksi('edit_transaksi_kasir_cari', {'keyword': kata});
      if (!mounted) return;
      setState(() => _hasilCariKasir = ((hasil['data'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList());
    } catch (e) {
      if (mounted) {
        setState(() => _pesan =
            'Akun kasir belum dapat dicari. Periksa koneksi, lalu coba kembali.');
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'mencari akun kasir');
      }
    } finally {
      if (mounted) setState(() => _mencariKasir = false);
    }
  }

  void _pilihKasir(Map<String, dynamic> akun) {
    setState(() {
      _kasirUserId = '${akun['userId'] ?? ''}'.trim();
      _kasirNama = '${akun['nama'] ?? akun['userId'] ?? ''}'.trim();
      _hasilCariKasir = [];
      _cariKasirController.clear();
    });
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
      // Offline: jatuh ke cache produk lokal hasil sinkron katalog --
      // koreksi transaksi justru sering dibutuhkan saat jaringan bermasalah.
      if (e is ApiException && e.offline) {
        final cache =
            await CoreDb.instance.produkCache(keyword: kata, limit: 15);
        if (!mounted) return;
        setState(() {
          _hasilCari = cache.map(Produk.cacheRowKeJson).toList();
          if (_hasilCari.isEmpty) {
            _pesan = 'Server tak terjangkau dan "$kata" tidak ditemukan di '
                'cache produk lokal.';
          }
        });
      } else if (mounted) {
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
    if (_caraBayarId == null) {
      setState(() => _pesan = 'Metode pembayaran wajib dipilih.');
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
        'id': _baris[i].produkId,
        'nama': _baris[i].nama,
        'harga': _baris[i].harga,
        'jumlah': qty,
        'diskon': 0,
        'cashback': 0,
      });
    }
    Navigator.of(context).pop({
      'alasan': alasan,
      'item': item,
      'waktu': _waktu.toIso8601String(),
      'cara_bayar': _caraBayarId,
      if (_kasirUserId.isNotEmpty) 'kasir_user_id': _kasirUserId,
    });
  }

  Future<void> _pilihWaktu() async {
    final sekarang = DateTime.now();
    final tanggalAwal = _waktu.isAfter(sekarang) ? sekarang : _waktu;
    final tanggal = await showDatePicker(
      context: context,
      initialDate: tanggalAwal,
      firstDate: DateTime(2000),
      lastDate: sekarang,
    );
    if (tanggal == null || !mounted) return;
    final jam = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_waktu),
    );
    if (jam == null || !mounted) return;
    final pilihan = DateTime(
        tanggal.year, tanggal.month, tanggal.day, jam.hour, jam.minute);
    if (pilihan.isAfter(DateTime.now())) {
      setState(() => _pesan =
          'Tanggal dan jam transaksi tidak boleh berada di masa depan.');
      return;
    }
    setState(() {
      _waktu = pilihan;
      _pesan = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.modeBaru
          ? 'Tambah Transaksi Baru'
          : 'Edit Transaksi ${widget.nomor}'),
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
              child: Text(
                widget.modeBaru
                    ? 'Khusus Supervisor. Transaksi pemulihan tetap melalui validasi harga, stok, diskon, audit, dan idempotensi server.'
                    : 'Khusus Supervisor. Perubahan akan menghitung ulang total dan stok serta menyimpan rincian sebelum/sesudah pada audit JSON. Transaksi yang sudah diposting atau memiliki retur tidak dapat diedit.',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Tanggal dan jam transaksi'),
              subtitle: Text(DateFormat('dd-MM-yyyy HH:mm').format(_waktu)),
              trailing: OutlinedButton.icon(
                onPressed: _pilihWaktu,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Ubah'),
              ),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cariKasirController,
                  onSubmitted: (_) => _cariKasir(),
                  decoration: InputDecoration(
                    labelText: 'Kasir transaksi',
                    hintText: 'Cari ID atau nama pada tbmuser',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    helperText: _kasirNama.isEmpty
                        ? 'Kasir saat ini belum tercatat'
                        : 'Terpilih: $_kasirNama${_kasirUserId.isEmpty ? '' : ' ($_kasirUserId)'}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _mencariKasir ? null : _cariKasir,
                icon: _mencariKasir
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: const Text('Cari Kasir'),
              ),
            ]),
            if (_hasilCariKasir.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: ListView(
                  shrinkWrap: true,
                  children: _hasilCariKasir
                      .map((akun) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title:
                                Text('${akun['nama'] ?? akun['userId'] ?? ''}'),
                            subtitle: Text('${akun['userId'] ?? ''}'),
                            trailing: const Icon(Icons.check_circle_outline),
                            onTap: () => _pilihKasir(akun),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _caraBayarId,
              decoration: const InputDecoration(
                  labelText: 'Metode pembayaran *',
                  prefixIcon: Icon(Icons.payments_outlined)),
              items: Sesi.instance.caraBayar
                  .map((cara) => DropdownMenuItem<int>(
                      value: cara.id, child: Text(cara.nama)))
                  .toList(),
              onChanged: (value) => setState(() => _caraBayarId = value),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: AppSearchField(
                  controller: _cariController,
                  onSubmitted: (_) => _cariProduk(),
                  labelText: 'Tambah produk (kode / barcode / nama)',
                  scanProduk: true,
                  onScanned: (_) => _cariProduk(),
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
            Text(
                widget.modeBaru
                    ? 'Rincian transaksi'
                    : 'Rincian setelah koreksi',
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
              decoration: InputDecoration(
                labelText: widget.modeBaru
                    ? 'Alasan input/pemulihan *'
                    : 'Alasan koreksi *',
                hintText: 'Contoh: transaksi pada struk belum tersimpan',
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
          label: Text(widget.modeBaru ? 'Simpan Transaksi' : 'Simpan Koreksi'),
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

DateTime _parseWaktuKoreksi(dynamic raw) {
  final nilai = raw?.toString().trim() ?? '';
  final iso = DateTime.tryParse(nilai);
  if (iso != null) return iso;
  for (final pola in ['dd-MM-yyyy HH:mm:ss', 'dd-MM-yyyy HH:mm']) {
    try {
      return DateFormat(pola).parseStrict(nilai);
    } catch (_) {
      // Coba pola berikutnya.
    }
  }
  return DateTime.now();
}

String _kodeTransaksiStabil(Map<String, dynamic> row) {
  for (final kunci in const [
    'kodeUnik',
    'clientTrxId',
    'kodeTransaksi',
    'nomorTransaksi',
    'nomorNota',
    'kode'
  ]) {
    final nilai = '${row[kunci] ?? ''}'.trim();
    if (nilai.isNotEmpty && nilai != '-') {
      // Server lama hanya menyisipkan kode asli di akhir label nomor nota:
      // "Order 001 - 0001 - 001 (AB...)". Ekstraksi ini membuat klien baru
      // tetap dapat direkonsiliasi dengan server yang belum dideploy ulang.
      if (kunci == 'nomorNota') {
        final cocok = RegExp(r'\(([^()]+)\)\s*$').firstMatch(nilai);
        final kodeLama = cocok?.group(1)?.trim() ?? '';
        if (kodeLama.isNotEmpty) return kodeLama.toLowerCase();
      }
      return nilai.toLowerCase();
    }
  }
  return '';
}

/// Menggabungkan arsip lokal-first dengan hasil server berdasarkan kode
/// idempotensi transaksi, bukan label nota presentasi.
///
/// Server baru menampilkan nomor seperti `Order 001 - 0001 - 001 (EB...)`,
/// sedangkan arsip lokal menyimpan `EB...` secara mentah. Membandingkan
/// `nomorNota` membuat keduanya dianggap transaksi berbeda; baris lokal yang
/// sudah SYNCED lalu tetap tidak mempunyai `idTransaksi` dan sebelumnya dapat
/// memanggil `detail_transaksi` dengan `id: null`.
@visibleForTesting
List<Map<String, dynamic>> gabungkanTransaksiServerDanLokal(
  List<Map<String, dynamic>> server,
  List<Map<String, dynamic>> lokal, {
  required int batas,
}) {
  final serverMenurutKode = <String, Map<String, dynamic>>{};
  for (final row in server) {
    final kode = _kodeTransaksiStabil(row);
    if (kode.isNotEmpty) serverMenurutKode[kode] = row;
  }

  final kodeServerTerpakai = <String>{};
  final hasilLokal = lokal.map((rowLokal) {
    final kode = _kodeTransaksiStabil(rowLokal);
    final rowServer = kode.isEmpty ? null : serverMenurutKode[kode];
    if (rowServer == null) return rowLokal;
    kodeServerTerpakai.add(kode);
    // Field otoritatif server (terutama idTransaksi dan label nota) menang;
    // metadata/cadangan lokal tetap dibawa untuk fallback ketika offline.
    return <String, dynamic>{...rowLokal, ...rowServer};
  }).toList();

  final serverBelumTerpakai = server.where((row) {
    final kode = _kodeTransaksiStabil(row);
    return kode.isEmpty || !kodeServerTerpakai.contains(kode);
  });
  return <Map<String, dynamic>>[...hasilLokal, ...serverBelumTerpakai]
      .take(batas)
      .toList();
}

String _formatWaktuBayar(DateTime waktu) =>
    DateFormat('dd-MM-yyyy HH:mm:ss').format(waktu);

bool _transaksiSudahAdaDiServer(Object error) {
  if (error is ApiException &&
      (error.kode ?? '').trim() == 'DUPLIKAT_KODE_TRANSAKSI') {
    return true;
  }
  final pesan = error.toString().toLowerCase();
  return pesan.contains('sudah tercatat') ||
      pesan.contains('kode transaksi yang sama sudah ada') ||
      pesan.contains('duplicate key');
}

class _DialogPerbandinganTransaksi extends StatefulWidget {
  const _DialogPerbandinganTransaksi({
    required this.hasil,
    required this.onHapusHanyaLokal,
  });

  final HasilPerbandinganTransaksi hasil;
  final Future<int> Function(List<String> kode) onHapusHanyaLokal;

  @override
  State<_DialogPerbandinganTransaksi> createState() =>
      _DialogPerbandinganTransaksiState();
}

class _DialogPerbandinganTransaksiState
    extends State<_DialogPerbandinganTransaksi> {
  bool _hanyaSelisih = true;
  bool _menghapus = false;

  Future<void> _hapusHanyaLokal() async {
    final hanyaLokal = widget.hasil.baris
        .where((item) => item.status == StatusPerbandinganTransaksi.hanyaLokal)
        .toList();
    if (hanyaLokal.isEmpty || _menghapus) return;
    final total =
        hanyaLokal.fold<double>(0, (jumlah, item) => jumlah + item.totalLokal);
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transaksi yang hanya ada di lokal?'),
        content: Text(
          '${hanyaLokal.length} transaksi dengan total '
          '${_formatRupiah.format(total)} akan dihapus dari arsip, antrean, '
          'dan cadangan lokal perangkat ini.\n\n'
          'Tindakan ini tidak mengubah data server dan tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: Text('Hapus ${hanyaLokal.length} transaksi'),
          ),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setState(() => _menghapus = true);
    try {
      final jumlah = await widget
          .onHapusHanyaLokal(hanyaLokal.map((item) => item.kode).toList());
      if (mounted) Navigator.of(context).pop(jumlah);
    } catch (error) {
      if (mounted) {
        await tampilkanKesalahan(context, error,
            aktivitas: 'menghapus transaksi yang hanya ada di lokal');
      }
    } finally {
      if (mounted) setState(() => _menghapus = false);
    }
  }

  String _labelStatus(StatusPerbandinganTransaksi status) {
    switch (status) {
      case StatusPerbandinganTransaksi.sama:
        return 'Sama';
      case StatusPerbandinganTransaksi.hanyaLokal:
        return 'Hanya lokal';
      case StatusPerbandinganTransaksi.hanyaServer:
        return 'Hanya server';
      case StatusPerbandinganTransaksi.berbeda:
        return 'Nominal berbeda';
      case StatusPerbandinganTransaksi.duplikat:
        return 'Duplikat';
    }
  }

  Color _warnaStatus(StatusPerbandinganTransaksi status) {
    switch (status) {
      case StatusPerbandinganTransaksi.sama:
        return AppColors.success;
      case StatusPerbandinganTransaksi.hanyaLokal:
      case StatusPerbandinganTransaksi.hanyaServer:
        return Colors.orange.shade800;
      case StatusPerbandinganTransaksi.berbeda:
      case StatusPerbandinganTransaksi.duplikat:
        return Colors.red.shade700;
    }
  }

  Widget _ringkasan(String label, int nilai, Color warna) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.09),
          border: Border.all(color: warna.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$nilai  $label',
            style: TextStyle(color: warna, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final baris = widget.hasil.baris
        .where((item) =>
            !_hanyaSelisih || item.status != StatusPerbandinganTransaksi.sama)
        .toList();
    return AlertDialog(
      title: const Text('Perbandingan Transaksi Lokal ↔ Server'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(640, 1180).toDouble(),
        height: MediaQuery.sizeOf(context).height.clamp(420, 720).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Perbandingan memuat seluruh arsip server untuk toko aktif. '
              'Sinkronkan bila transaksi lokal masih perlu dikirim; hapus hanya '
              'jika transaksi memang tidak boleh ada di server.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ringkasan(
                    'Sama',
                    widget.hasil.jumlah(StatusPerbandinganTransaksi.sama),
                    AppColors.success),
                _ringkasan(
                    'Hanya lokal',
                    widget.hasil.jumlah(StatusPerbandinganTransaksi.hanyaLokal),
                    Colors.orange.shade800),
                _ringkasan(
                    'Hanya server',
                    widget.hasil
                        .jumlah(StatusPerbandinganTransaksi.hanyaServer),
                    Colors.orange.shade800),
                _ringkasan(
                    'Nominal berbeda',
                    widget.hasil.jumlah(StatusPerbandinganTransaksi.berbeda),
                    Colors.red.shade700),
                _ringkasan(
                    'Duplikat',
                    widget.hasil.jumlah(StatusPerbandinganTransaksi.duplikat),
                    Colors.red.shade700),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tampilkan hanya data yang berbeda'),
              value: _hanyaSelisih,
              onChanged: (nilai) => setState(() => _hanyaSelisih = nilai),
            ),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: baris.isEmpty
                    ? const Center(child: Text('Tidak ada selisih transaksi.'))
                    : Scrollbar(
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Kode transaksi')),
                                DataColumn(label: Text('Status')),
                                DataColumn(
                                    label: Text('Baris lokal'), numeric: true),
                                DataColumn(
                                    label: Text('Baris server'), numeric: true),
                                DataColumn(
                                    label: Text('Total lokal'), numeric: true),
                                DataColumn(
                                    label: Text('Total server'), numeric: true),
                                DataColumn(
                                    label: Text('Asal lokal (user / mesin)')),
                                DataColumn(
                                    label: Text('Asal server (user / mesin)')),
                              ],
                              rows: baris.take(5000).map((item) {
                                final warna = _warnaStatus(item.status);
                                return DataRow(cells: [
                                  DataCell(SelectableText(item.kode)),
                                  DataCell(Text(_labelStatus(item.status),
                                      style: TextStyle(
                                          color: warna,
                                          fontWeight: FontWeight.w700))),
                                  DataCell(Text('${item.jumlahLokal}')),
                                  DataCell(Text('${item.jumlahServer}')),
                                  DataCell(Text(
                                      _formatRupiah.format(item.totalLokal))),
                                  DataCell(Text(
                                      _formatRupiah.format(item.totalServer))),
                                  DataCell(SelectableText(item.asalLokal)),
                                  DataCell(SelectableText(item.asalServer)),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (baris.length > 5000)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Menampilkan 5.000 dari ${baris.length} baris agar layar tetap responsif.'),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.hasil.jumlah(StatusPerbandinganTransaksi.hanyaLokal) > 0)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
            onPressed: _menghapus ? null : _hapusHanyaLokal,
            icon: _menghapus
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: Text(
              'Hapus hanya lokal '
              '(${widget.hasil.jumlah(StatusPerbandinganTransaksi.hanyaLokal)})',
            ),
          ),
        FilledButton(
          onPressed: _menghapus ? null : () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      ],
    );
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

class _RiwayatPenjualanScreenState extends State<RiwayatPenjualanScreen>
    with JejakGalat {
  final Map<String, String> _kunciPembatalan = {};
  static const _pageSize = 15;
  bool _memuat = true;
  bool _menyinkronkanDuaArah = false;
  bool _membandingkanDuaArah = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  double _omzetTotal = 0;
  DateTime? _mulai;
  DateTime? _sampai;
  String _cariPembeli = '';
  bool _hanyaTransaksiTidakValid = false;
  // Diff hasil server vs snapshot cache yang barusan tampil -- menggerakkan
  // kilau baris + banner "pembaruan dari server" (transaksi kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;
  final _kasirFilter = TextEditingController();
  final _mesinFilter = TextEditingController();
  final _produkFilter = TextEditingController();
  final _pelangganFilter = TextEditingController();
  final _notaFilter = TextEditingController();
  final _metodeFilter = TextEditingController();
  final _waktuMulaiFilter = TextEditingController();
  final _waktuSampaiFilter = TextEditingController();
  final _totalMinimalFilter = TextEditingController();
  final _totalMaksimalFilter = TextEditingController();
  final _qtyMinimalFilter = TextEditingController();
  final _qtyMaksimalFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    final hariIni = DateTime.now();
    _mulai = DateTime(hariIni.year, hariIni.month, hariIni.day);
    _sampai = DateTime(hariIni.year, hariIni.month, hariIni.day);
    _muat();
  }

  int? _idCaraBayarDariNama(String nama) {
    final teks = nama.trim().toLowerCase();
    if (teks.isEmpty) return null;
    for (final cara in Sesi.instance.caraBayar) {
      if (cara.nama.trim().toLowerCase() == teks) return cara.id;
    }
    return null;
  }

  @override
  void dispose() {
    for (final controller in [
      _kasirFilter,
      _mesinFilter,
      _produkFilter,
      _pelangganFilter,
      _notaFilter,
      _metodeFilter,
      _waktuMulaiFilter,
      _waktuSampaiFilter,
      _totalMinimalFilter,
      _totalMaksimalFilter,
      _qtyMinimalFilter,
      _qtyMaksimalFilter,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _adaFilterLanjutan => [
        _kasirFilter,
        _mesinFilter,
        _produkFilter,
        _pelangganFilter,
        _notaFilter,
        _metodeFilter,
        _waktuMulaiFilter,
        _waktuSampaiFilter,
        _totalMinimalFilter,
        _totalMaksimalFilter,
        _qtyMinimalFilter,
        _qtyMaksimalFilter,
      ].any((c) => c.text.trim().isNotEmpty);

  bool get _defaultTanpaFilter {
    final hariIni = _formatTanggalServer.format(DateTime.now());
    return _mulai != null &&
        _sampai != null &&
        _formatTanggalServer.format(_mulai!) == hariIni &&
        _formatTanggalServer.format(_sampai!) == hariIni &&
        _cariPembeli.isEmpty &&
        !_adaFilterLanjutan &&
        !_hanyaTransaksiTidakValid &&
        _halaman == 1;
  }

  DateTime? _waktuPayloadLokal(dynamic raw) {
    final teks = '${raw ?? ''}'.trim();
    if (teks.isEmpty) return null;
    final iso = DateTime.tryParse(teks);
    if (iso != null) return iso;
    for (final pola in const [
      'dd-MM-yyyy HH:mm:ss',
      'dd-MM-yyyy HH:mm',
      'yyyy-MM-dd HH:mm:ss',
    ]) {
      try {
        return DateFormat(pola).parseStrict(teks);
      } catch (_) {}
    }
    return null;
  }

  String _namaCaraBayarLokal(Map<String, dynamic> payload) {
    final tersimpan = '${payload['caraBayarNama'] ?? ''}'.trim();
    if (tersimpan.isNotEmpty) return tersimpan;
    final id = payload['caraBayar'];
    for (final cara in Sesi.instance.caraBayar) {
      if ('${cara.id}' == '$id') return cara.nama;
    }
    return id == null ? '-' : '$id';
  }

  Future<List<Map<String, dynamic>>> _arsipLokalSesuaiFilter() async {
    final rows = await CoreDb.instance.transaksiArsipLokal(
      akunKunci: Sesi.instance.userId,
      tokoId: Sesi.instance.tokoId,
    );
    final hasil = <Map<String, dynamic>>[];
    for (final source in rows) {
      if ('${source['status']}' == 'GAGAL') continue;
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
            jsonDecode('${source['payload_json']}') as Map);
      } catch (_) {
        continue;
      }
      final waktu = _waktuPayloadLokal(payload['waktu']) ??
          DateTime.tryParse('${source['dibuat_pada']}');
      if (waktu == null) continue;
      final hari = DateTime(waktu.year, waktu.month, waktu.day);
      if (_mulai != null &&
          hari.isBefore(DateTime(_mulai!.year, _mulai!.month, _mulai!.day))) {
        continue;
      }
      if (_sampai != null &&
          hari.isAfter(DateTime(_sampai!.year, _sampai!.month, _sampai!.day))) {
        continue;
      }
      final transaksi = ((payload['transaksi'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final kode = '${payload['kodeUnik'] ?? source['kode_unik']}';
      final pembeli = '${payload['nama_member'] ?? 'Umum'}';
      final kasir = '${payload['kasir'] ?? '-'}';
      final mesin = '${payload['nama_mesin'] ?? ''}';
      final metode = _namaCaraBayarLokal(payload);
      final total = (payload['total'] as num?)?.toDouble() ?? 0;
      final teksProduk = transaksi
          .map((e) => '${e['kode'] ?? ''} ${e['nama'] ?? ''}')
          .join(' ')
          .toLowerCase();
      final qty = transaksi.fold<double>(
          0, (sum, e) => sum + ((e['jumlah'] as num?)?.toDouble() ?? 0));
      bool cocok(String nilai, String filter) =>
          filter.trim().isEmpty ||
          nilai.toLowerCase().contains(filter.trim().toLowerCase());
      if (!cocok('$kode $pembeli', _cariPembeli) ||
          !cocok(kasir, _kasirFilter.text) ||
          !cocok(mesin, _mesinFilter.text) ||
          !cocok(teksProduk, _produkFilter.text) ||
          !cocok(pembeli, _pelangganFilter.text) ||
          !cocok(kode, _notaFilter.text) ||
          !cocok(metode, _metodeFilter.text)) {
        continue;
      }
      final minTotal = _angkaFilter(_totalMinimalFilter);
      final maxTotal = _angkaFilter(_totalMaksimalFilter);
      final minQty = _angkaFilter(_qtyMinimalFilter);
      final maxQty = _angkaFilter(_qtyMaksimalFilter);
      if ((minTotal > 0 && total < minTotal) ||
          (maxTotal > 0 && total > maxTotal) ||
          (minQty > 0 && qty < minQty) ||
          (maxQty > 0 && qty > maxQty)) {
        continue;
      }
      hasil.add(_normalisasiTransaksi(<String, dynamic>{
        'nomorNota': kode,
        'waktu': waktu.toIso8601String(),
        'pembeli': pembeli,
        'totalBiaya': total,
        'metode': metode,
        'kasir': kasir,
        'namaMesin': mesin,
        'pajak': payload['pajak'] ?? 0,
        'totalDiskon': payload['diskon_faktur_nilai'] ?? 0,
        'statusSinkronLokal': source['status'],
        'payloadLokal': payload,
        'itemLokal': transaksi,
      }));
    }
    return hasil;
  }

  List<Map<String, dynamic>> _gabungkanDenganArsipLokal(
      List<Map<String, dynamic>> server, List<Map<String, dynamic>> lokal) {
    lokal.sort((a, b) {
      final aPending = a['statusSinkronLokal'] == 'PENDING' ? 0 : 1;
      final bPending = b['statusSinkronLokal'] == 'PENDING' ? 0 : 1;
      if (aPending != bPending) return aPending.compareTo(bPending);
      return '${b['waktu'] ?? ''}'.compareTo('${a['waktu'] ?? ''}');
    });
    // Arsip lokal diprioritaskan agar transaksi baru/pending langsung tampak,
    // tetapi jumlah baris tetap mengikuti paging 15 data. Tanpa batas ini,
    // perangkat lama dengan ribuan arsip akan membuat halaman pertama sangat
    // panjang dan lambat walaupun query server sudah memakai paging.
    return gabungkanTransaksiServerDanLokal(server, lokal, batas: _pageSize);
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    final lokal = saringArsipLokalUntukFilterIntegritas(
      await _arsipLokalSesuaiFilter(),
      hanyaTransaksiTidakValid: _hanyaTransaksiTidakValid,
    );
    // BACA LOKAL-DULU (pola daftarCacheDulu, dihitung manual krn jalur baca
    // layar ini kompleks: gabungan arsip lokal + bentuk respons bervariasi +
    // fallback keyword): utk tampilan DEFAULT, snapshot terakhir langsung
    // tampil tanpa menunggu jaringan; hasil server menyusul dan diff-nya
    // menggerakkan kilau baris + banner (transaksi baru dari kasir lain).
    // Tampilan berfilter/halaman >1 tetap online-first spt semula.
    List<Map<String, dynamic>>? dataCache;
    if (_defaultTanpaFilter) {
      try {
        final tersimpan =
            await CoreDb.instance.ambilCacheReferensi(_kunciCacheRiwayat);
        if (tersimpan != null) {
          final hasilCache = jsonDecode(tersimpan) as Map<String, dynamic>;
          final data = _normalisasiDaftarTransaksi(hasilCache);
          dataCache = data;
          final gabungan = _gabungkanDenganArsipLokal(data, lokal);
          setStateIfMounted(() {
            _data = gabungan;
            _total = _normalisasiTotalTransaksi(hasilCache, data.length);
            _omzetTotal = (hasilCache['totalNilai'] as num?)?.toDouble() ??
                gabungan.fold<double>(0,
                    (a, r) => a + ((r['totalBiaya'] as num?)?.toDouble() ?? 0));
            _idBaru = {};
            _idBerubah = {};
            _jumlahHapus = 0;
            _memuat = false;
          });
        }
      } catch (_) {
        dataCache = null; // cache rusak -- lanjut jalur server biasa.
      }
    }
    try {
      final payload = {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        if (_cariPembeli.isNotEmpty) 'keyword': _cariPembeli,
        if (_kasirFilter.text.trim().isNotEmpty)
          'kasir': _kasirFilter.text.trim(),
        if (_mesinFilter.text.trim().isNotEmpty)
          'mesin': _mesinFilter.text.trim(),
        if (_produkFilter.text.trim().isNotEmpty)
          'produk': _produkFilter.text.trim(),
        if (_pelangganFilter.text.trim().isNotEmpty)
          'cariPembeli': _pelangganFilter.text.trim(),
        if (_notaFilter.text.trim().isNotEmpty)
          'nomorNota': _notaFilter.text.trim(),
        if (_metodeFilter.text.trim().isNotEmpty)
          'metodeExact': _metodeFilter.text.trim(),
        if (_waktuMulaiFilter.text.trim().isNotEmpty)
          'waktuMulai': _waktuMulaiFilter.text.trim(),
        if (_waktuSampaiFilter.text.trim().isNotEmpty)
          'waktuSampai': _waktuSampaiFilter.text.trim(),
        if ((_angkaFilter(_totalMinimalFilter)) > 0)
          'totalMinimal': _angkaFilter(_totalMinimalFilter),
        if ((_angkaFilter(_totalMaksimalFilter)) > 0)
          'totalMaksimal': _angkaFilter(_totalMaksimalFilter),
        if ((_angkaFilter(_qtyMinimalFilter)) > 0)
          'qtyMinimal': _angkaFilter(_qtyMinimalFilter),
        if ((_angkaFilter(_qtyMaksimalFilter)) > 0)
          'qtyMaksimal': _angkaFilter(_qtyMaksimalFilter),
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
      final gabungan =
          _halaman == 1 ? _gabungkanDenganArsipLokal(data, lokal) : data;
      final kodeServer = data
          .map((e) => '${e['nomorNota'] ?? ''}'.trim().toLowerCase())
          .toSet();
      final tambahanLokal = lokal
          .where((e) =>
              e['statusSinkronLokal'] != 'SYNCED' &&
              !kodeServer
                  .contains('${e['nomorNota'] ?? ''}'.trim().toLowerCase()))
          .length;
      // Diff vs snapshot cache yang barusan tampil (kunci id header nota) --
      // baris server yang baru muncul/berubah isi dikilaukan + banner.
      final idBaru = <String>{};
      final idBerubah = <String>{};
      var jumlahHapus = 0;
      if (dataCache != null) {
        final petaLama = <String, String>{
          for (final r in dataCache)
            if (_kunciDiffTransaksi(r).isNotEmpty)
              _kunciDiffTransaksi(r): jsonEncode(r),
        };
        final kunciBaruSemua = <String>{};
        for (final r in data) {
          final k = _kunciDiffTransaksi(r);
          if (k.isEmpty) continue;
          kunciBaruSemua.add(k);
          final lama = petaLama[k];
          if (lama == null) {
            idBaru.add(k);
          } else if (lama != jsonEncode(r)) {
            idBerubah.add(k);
          }
        }
        // Baris lama yg hilang hanya dihitung "dihapus" bila halaman server
        // TIDAK penuh -- kalau penuh, baris lama mungkin sekadar tergeser ke
        // halaman 2 oleh transaksi yang lebih baru (bukan dibatalkan).
        if (data.length < _pageSize) {
          jumlahHapus =
              petaLama.keys.where((k) => !kunciBaruSemua.contains(k)).length;
        }
      }
      setStateIfMounted(() {
        _data = gabungan;
        _total = _normalisasiTotalTransaksi(hasil, data.length) + tambahanLokal;
        _omzetTotal = (hasil['totalNilai'] as num?)?.toDouble() ??
            gabungan.fold<double>(
                0, (a, r) => a + ((r['totalBiaya'] as num?)?.toDouble() ?? 0));
        _idBaru = idBaru;
        _idBerubah = idBerubah;
        _jumlahHapus = jumlahHapus;
        if (idBaru.isNotEmpty || idBerubah.isNotEmpty || jumlahHapus > 0) {
          _versiPerubahan++;
        }
      });
      if (_defaultTanpaFilter) {
        unawaited(CoreDb.instance
            .simpanCacheReferensi(_kunciCacheRiwayat, jsonEncode(hasil)));
      }
    } catch (e) {
      // Snapshot cache sudah tampil (baca lokal-dulu) -- saat OFFLINE cukup
      // diam (indikator offline global sudah menceritakan kondisinya);
      // penolakan bisnis server tetap diperlihatkan lewat jalur di bawah.
      if (dataCache != null && e is ApiException && e.offline) return;
      if (lokal.isNotEmpty) {
        setStateIfMounted(() {
          _data = lokal;
          _total = lokal.length;
          _omzetTotal = lokal.fold<double>(
              0, (a, r) => a + ((r['totalBiaya'] as num?)?.toDouble() ?? 0));
          _error = null;
        });
        return;
      }
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
      setStateIfMounted(() => _error = terapkanGalat(e));
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

  double _angkaFilter(TextEditingController controller) =>
      double.tryParse(
          controller.text.replaceAll('.', '').replaceAll(',', '.').trim()) ??
      0;

  Future<void> _resetFilterLanjutan() async {
    for (final controller in [
      _kasirFilter,
      _mesinFilter,
      _produkFilter,
      _pelangganFilter,
      _notaFilter,
      _metodeFilter,
      _waktuMulaiFilter,
      _waktuSampaiFilter,
      _totalMinimalFilter,
      _totalMaksimalFilter,
      _qtyMinimalFilter,
      _qtyMaksimalFilter,
    ]) {
      controller.clear();
    }
    _hanyaTransaksiTidakValid = false;
    await _terapkan();
  }

  Widget _fieldFilter(String label, TextEditingController controller,
      {String? hint, TextInputType? keyboardType}) {
    return SizedBox(
      width: 230,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onSubmitted: (_) => _terapkan(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
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
      final payloadLokal = row['payloadLokal'];
      late Map<String, dynamic> hasil;
      late List<Map<String, dynamic>> items;

      void pakaiSnapshotLokal(Map payloadSumber) {
        final payload = Map<String, dynamic>.from(payloadSumber);
        hasil = <String, dynamic>{
          'kode': row['nomorNota'],
          'waktu': row['waktu'],
          'totalBiaya': row['totalBiaya'],
          'kasirNama': row['kasir'],
          'bolehEditTransaksi': false,
        };
        items = ((payload['transaksi'] as List?) ?? const [])
            .whereType<Map>()
            .map((raw) {
          final i = Map<String, dynamic>.from(raw);
          return <String, dynamic>{
            ...i,
            'qty': i['qty'] ?? i['jumlah'] ?? 0,
            'harga': i['harga'] ?? 0,
            'diskon': i['diskon'] ?? 0,
          };
        }).toList();
      }

      // Baris hasil sinkron tetap membawa payload lokal sebagai cadangan. Dahulu
      // keberadaan payload itu selalu menang dan memaksa bolehEditTransaksi=false,
      // sehingga tombol Edit hilang meskipun server mengizinkan. Transaksi yang
      // sudah SYNCED wajib meminta detail + otorisasi terkini dari server; snapshot
      // lokal hanya dipakai bila koneksi benar-benar gagal.
      final sudahTersinkron = row['statusSinkronLokal'] == 'SYNCED';
      if (payloadLokal is Map && !sudahTersinkron) {
        pakaiSnapshotLokal(payloadLokal);
      } else {
        final idTransaksi = row['idTransaksi'];
        if (idTransaksi == null) {
          // Jangan pernah mengirim `id:null`. Snapshot lokal masih merupakan
          // detail yang benar untuk dibaca; sesudah refresh dari server, merge
          // berdasarkan kode stabil di atas akan melengkapinya dengan ID.
          if (payloadLokal is Map) {
            pakaiSnapshotLokal(payloadLokal);
          } else {
            throw const FormatException(
                'Detail transaksi belum memiliki ID server. Muat ulang data lalu coba kembali.');
          }
        } else {
          try {
            hasil = await ApiClient.instance
                .aksi('detail_transaksi', {'id': idTransaksi});
            items =
                ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
          } on ApiException catch (error) {
            if (!error.offline || payloadLokal is! Map) rethrow;
            pakaiSnapshotLokal(payloadLokal);
          }
        }
      }
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
                    if (row['statusSinkronLokal'] != null)
                      _chipRingkasan(
                          'Sinkron',
                          row['statusSinkronLokal'] == 'SYNCED'
                              ? 'Tersinkron'
                              : 'Menunggu',
                          row['statusSinkronLokal'] == 'SYNCED'
                              ? AppColors.success
                              : AppColors.warning),
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
                  if (hasil['bolehEditTransaksi'] != true &&
                      '${hasil['alasanEditTransaksi'] ?? ''}'
                          .trim()
                          .isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.warning),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${hasil['alasanEditTransaksi']}',
                        style: const TextStyle(
                          color: AppColors.warning,
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
            if (row['idTransaksi'] != null &&
                (Sesi.instance.bolehAksiPos('riwayatpenjualan', 'delete') ||
                    Sesi.instance.bolehAksiPos('riwayatpenjualan', 'reject')))
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
        snackbarGalat(context, e);
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
        snackbarGalat(context, e);
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
        waktu: _parseWaktuKoreksi(detail['waktu'] ?? row['waktu']),
        kasirUserId: '${detail['kasirUserId'] ?? ''}',
        kasirNama: '${detail['kasirNama'] ?? row['kasir'] ?? ''}',
        caraBayarId: (detail['caraBayarId'] as num?)?.toInt() ??
            _idCaraBayarDariNama(
                '${detail['caraBayarNama'] ?? row['metode'] ?? ''}'),
        caraBayarNama: '${detail['caraBayarNama'] ?? row['metode'] ?? ''}',
      ),
    );
    if (hasilEdit == null || !mounted) return;
    try {
      final hasil = await ApiClient.instance.aksi('edit_transaksi', {
        'id': row['idTransaksi'],
        'alasan': hasilEdit['alasan'],
        'item': hasilEdit['item'],
        'waktu': hasilEdit['waktu'],
        'cara_bayar': hasilEdit['cara_bayar'],
        if (hasilEdit['kasir_user_id'] != null)
          'kasir_user_id': hasilEdit['kasir_user_id'],
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

  Future<void> _tambahTransaksiSupervisor() async {
    if (!Sesi.instance.bolehKelola) return;
    final isian = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogEditTransaksi(
        nomor: '',
        items: const [],
        waktu: DateTime.now(),
        kasirUserId: Sesi.instance.userId,
        kasirNama: Sesi.instance.userId,
        modeBaru: true,
      ),
    );
    if (isian == null || !mounted) return;
    final waktu = DateTime.parse('${isian['waktu']}');
    final caraBayarId = isian['cara_bayar'] as int;
    final caraBayar =
        Sesi.instance.caraBayar.where((cara) => cara.id == caraBayarId).first;
    final item = (isian['item'] as List).cast<Map<String, dynamic>>();
    final total = item.fold<double>(
        0,
        (jumlah, baris) =>
            jumlah +
            ((baris['harga'] as num?)?.toDouble() ?? 0) *
                ((baris['jumlah'] as num?)?.toDouble() ?? 0));
    final kode =
        'SUP-${Sesi.instance.tokoId ?? 0}-${DateTime.now().microsecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'kodeUnik': kode,
      'clientTrxId': kode,
      'idToko': Sesi.instance.tokoId,
      'tokoId': Sesi.instance.tokoId,
      'kasir': '${isian['kasir_user_id'] ?? Sesi.instance.userId}',
      'kasir_user_id': '${isian['kasir_user_id'] ?? Sesi.instance.userId}',
      'waktu': _formatWaktuBayar(waktu),
      'caraBayar': caraBayarId,
      'caraBayarNama': caraBayar.nama,
      'total': total,
      'pajak': 0,
      'nama_mesin': IdentitasMesin.instance.namaMesin,
      'id_perangkat': IdentitasMesin.instance.idMesin,
      'input_supervisor': true,
      'alasan_supervisor': isian['alasan'],
      'keterangan': 'INPUT SUPERVISOR: ${isian['alasan']}',
      'transaksi': item,
    };
    await CoreDb.instance.simpanTransaksiPending(kode, jsonEncode(payload),
        akunKunci: Sesi.instance.userId,
        tokoId: Sesi.instance.tokoId,
        idPerangkat: IdentitasMesin.instance.idMesin);
    TransaksiOutboxService.instance.kirimDiBackground();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Transaksi supervisor aman di lokal dan sedang dikirim ke server di background.')));
    await _muat();
  }

  Future<List<Map<String, dynamic>>> _semuaTransaksiServer() async {
    final semua = <Map<String, dynamic>>[];
    var halaman = 1;
    while (halaman <= 1000) {
      final hasil =
          await ApiClient.instance.aksi('transaksi_backup_toko_list', {
        'toko_id': Sesi.instance.tokoId,
        'tglMulai': '2000-01-01',
        'tglSampai': _formatTanggalServer.format(DateTime.now()),
        'page': halaman,
        'pageSize': 200,
      });
      final baris = _normalisasiDaftarTransaksi(hasil);
      semua.addAll(baris);
      final total = _normalisasiTotalTransaksi(hasil, baris.length);
      if (baris.isEmpty || semua.length >= total || baris.length < 200) break;
      halaman++;
    }
    return semua;
  }

  Map<String, dynamic> _payloadDariServer(Map<String, dynamic> row,
      Map<String, dynamic> detail, List<Map<String, dynamic>> items) {
    final kode =
        '${row['kodeUnik'] ?? detail['kodeUnik'] ?? detail['clientTrxId'] ?? detail['kode'] ?? row['nomorNota']}'
            .trim();
    return <String, dynamic>{
      'kodeUnik': kode,
      'clientTrxId': kode,
      'idToko': Sesi.instance.tokoId,
      'tokoId': Sesi.instance.tokoId,
      'kasir':
          '${detail['kasirUserId'] ?? row['kasirUserId'] ?? row['kasir'] ?? ''}',
      'kasir_user_id':
          '${detail['kasirUserId'] ?? row['kasirUserId'] ?? row['kasir'] ?? ''}',
      'waktu': '${detail['waktu'] ?? row['waktu'] ?? ''}',
      'caraBayarNama': '${row['metode'] ?? ''}',
      'total': detail['totalBiaya'] ?? row['totalBiaya'] ?? 0,
      'pajak': row['pajak'] ?? 0,
      'nama_member': detail['pembeli'] ?? row['pembeli'],
      'nama_mesin': row['namaMesin'],
      'id_perangkat': detail['idPerangkat'] ?? row['idPerangkat'],
      'sumber_username':
          '${detail['kasirUserId'] ?? row['kasirUserId'] ?? row['kasir'] ?? ''}',
      'sumber_mesin':
          '${row['namaMesin'] ?? detail['idPerangkat'] ?? row['idPerangkat'] ?? ''}',
      'asal_backup': 'SERVER_TOKO_SAMA',
      'transaksi': items
          .map((item) => <String, dynamic>{
                'id': item['produkId'] ?? item['id'],
                'kode': item['kode'],
                'nama': item['nama'],
                'harga': item['harga'] ?? 0,
                'jumlah': item['qty'] ?? item['jumlah'] ?? 0,
                'diskon': item['diskon'] ?? 0,
                'cashback': item['cashback'] ?? 0,
              })
          .toList(),
    };
  }

  Future<void> _sinkronkanTransaksiDuaArah() async {
    if (!Sesi.instance.bolehKelola || _menyinkronkanDuaArah) return;
    setState(() => _menyinkronkanDuaArah = true);
    var dariServer = 0;
    var keServer = 0;
    var sudahSama = 0;
    var arsipServerDilewati = 0;
    var payloadTidakLengkap = 0;
    try {
      final server = await _semuaTransaksiServer();
      final serverByKode = <String, Map<String, dynamic>>{};
      for (final row in server) {
        final kode = _kodeTransaksiStabil(row);
        if (kode.isNotEmpty) serverByKode[kode] = row;
      }
      final lokal = await CoreDb.instance
          .transaksiArsipLokal(tokoId: Sesi.instance.tokoId, limit: 1000000);
      final lokalByKode = <String, Map<String, Object?>>{};
      for (final row in lokal) {
        final kode = '${row['kode_unik'] ?? ''}'.trim().toLowerCase();
        if (kode.isNotEmpty) lokalByKode[kode] = row;
      }

      for (final entry in serverByKode.entries) {
        final lokalAda = lokalByKode[entry.key];
        if (lokalAda != null) {
          if ('${lokalAda['status']}' != 'SYNCED') {
            await CoreDb.instance
                .tandaiTransaksiSinkron('${lokalAda['kode_unik']}');
          }
          sudahSama++;
          continue;
        }
        final row = entry.value;
        final id = row['idTransaksi'];
        if (id == null) continue;
        final detail =
            await ApiClient.instance.aksi('detail_transaksi', {'id': id});
        final items = ((detail['item'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final payload = _payloadDariServer(row, detail, items);
        final kodeAsli = '${payload['kodeUnik']}'.trim();
        if (kodeAsli.isEmpty) continue;
        if (await CoreDb.instance.simpanTransaksiDariServer(
            kodeAsli, jsonEncode(payload),
            akunKunci:
                '${payload['sumber_username'] ?? payload['kasir'] ?? ''}',
            tokoId: Sesi.instance.tokoId,
            idPerangkat:
                '${payload['id_perangkat'] ?? payload['sumber_mesin'] ?? ''}')) {
          dariServer++;
        }
      }

      for (final entry in lokalByKode.entries) {
        if (serverByKode.containsKey(entry.key)) continue;
        Map<String, dynamic> payload;
        try {
          payload = Map<String, dynamic>.from(
              jsonDecode('${entry.value['payload_json']}') as Map);
        } catch (_) {
          payloadTidakLengkap++;
          continue;
        }
        final kelayakan = periksaKelayakanPayloadSinkronisasi(payload);
        if (kelayakan.status == StatusKelayakanSinkronisasi.arsipDariServer) {
          arsipServerDilewati++;
          continue;
        }
        if (!kelayakan.siapDikirim) {
          payloadTidakLengkap++;
          continue;
        }
        payload['input_supervisor'] = true;
        payload['alasan_supervisor'] = 'Rekonsiliasi backup lokal ke server';
        payload['kasir_user_id'] = payload['kasir'];
        try {
          await ApiClient.instance.aksi('bayar', payload);
          await CoreDb.instance
              .tandaiTransaksiSinkron('${entry.value['kode_unik']}');
          keServer++;
        } catch (e) {
          if (_transaksiSudahAdaDiServer(e)) {
            await CoreDb.instance
                .tandaiTransaksiSinkron('${entry.value['kode_unik']}');
            sudahSama++;
          } else {
            rethrow;
          }
        }
      }
      await _muat();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Sinkronisasi selesai: $dariServer dari server, $keServer ke server, '
              '$sudahSama sudah sama, $arsipServerDilewati arsip server tidak dikirim ulang, '
              '$payloadTidakLengkap payload lokal perlu diperiksa.')));
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'sinkronisasi transaksi lokal dan server');
      }
    } finally {
      if (mounted) setState(() => _menyinkronkanDuaArah = false);
    }
  }

  Future<void> _bandingkanTransaksiDuaArah() async {
    if (!Sesi.instance.bolehKelola || _membandingkanDuaArah) return;
    setState(() => _membandingkanDuaArah = true);
    try {
      final hasil = bandingkanTransaksiLokalDanServer(
        await CoreDb.instance
            .transaksiArsipLokal(tokoId: Sesi.instance.tokoId, limit: 1000000),
        await _semuaTransaksiServer(),
      );
      if (!mounted) return;
      final jumlahDihapus = await showDialog<int>(
        context: context,
        builder: (dialogContext) => _DialogPerbandinganTransaksi(
          hasil: hasil,
          onHapusHanyaLokal:
              CoreDb.instance.hapusTransaksiLokalTidakAdaDiServer,
        ),
      );
      if (jumlahDihapus != null && mounted) {
        await _muat();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$jumlahDihapus transaksi lokal yang tidak ada di server telah dihapus.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'membandingkan transaksi lokal dan server');
      }
    } finally {
      if (mounted) setState(() => _membandingkanDuaArah = false);
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

  Future<void> _mulaiDataSampleTransaksi() async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Masukkan 200.000 Transaksi Demo?'),
        content: const Text(
            'Fitur ini hanya untuk toko demo/UAT. Pembuatan transaksi berjalan di server secara background dan memakai kode idempoten agar tidak ganda.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mulai')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    try {
      final hasil =
          await ApiClient.instance.aksi('pos_demo_seed_transactions', {
        'toko_id': Sesi.instance.tokoId,
        'konfirmasi': 'SEED-DEMO-TRANSAKSI-200000',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${hasil['description'] ?? 'Job transaksi demo dimulai.'}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal memulai data demo: $e')));
    }
  }

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
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  // Tombol jam di tiap baris hanya menjangkau nota yang MASIH ada.
                  // Untuk nota yang sudah lenyap dari daftar, satu-satunya jalan
                  // adalah menyapu tabel audit menurut rentang tanggal.
                  if (Sesi.instance.isAdmin)
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RiwayatAuditScreen(
                          entitasAwal: 'transaksi',
                          tipeAwal: 'HAPUS',
                          menuAktif: MenuEBisnis.riwayatPenjualan,
                          labelKembali: 'Riwayat Penjualan',
                        ),
                      )),
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('History'),
                    ),
                  if (Sesi.instance.bolehDataSample)
                    OutlinedButton.icon(
                      onPressed: _mulaiDataSampleTransaksi,
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Data Sample 200K'),
                    ),
                  if (Sesi.instance.bolehKelola)
                    OutlinedButton.icon(
                      onPressed: _membandingkanDuaArah
                          ? null
                          : _bandingkanTransaksiDuaArah,
                      icon: _membandingkanDuaArah
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.compare_arrows_outlined, size: 18),
                      label: Text(_membandingkanDuaArah
                          ? 'Membandingkan...'
                          : 'Bandingkan Lokal ↔ Server'),
                    ),
                  if (Sesi.instance.bolehKelola)
                    OutlinedButton.icon(
                      onPressed: _menyinkronkanDuaArah
                          ? null
                          : _sinkronkanTransaksiDuaArah,
                      icon: _menyinkronkanDuaArah
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync_alt_outlined, size: 18),
                      label: Text(_menyinkronkanDuaArah
                          ? 'Menyinkronkan...'
                          : 'Sinkronkan Lokal ↔ Server'),
                    ),
                  if (Sesi.instance.bolehKelola)
                    FilledButton.icon(
                      onPressed: _tambahTransaksiSupervisor,
                      icon: const Icon(Icons.add_shopping_cart_outlined,
                          size: 18),
                      label: const Text('Tambah Transaksi Baru'),
                    ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.insights_outlined, size: 18),
                    label: const Text('Analisis Penjualan'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RiwayatPenjualanAnalisisScreen(),
                      ),
                    ),
                  ),
                ],
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
                        hintText: 'Pencarian cepat pelanggan / nomor nota...',
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
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ExpansionTile(
                      initiallyExpanded: _adaFilterLanjutan,
                      leading: const Icon(Icons.filter_alt_outlined),
                      title: const Text('Filter Lengkap'),
                      subtitle: Text(_adaFilterLanjutan
                          ? 'Filter tambahan sedang diterapkan'
                          : 'Kasir, waktu, produk, pelanggan, nota, metode, nilai, dan jumlah barang'),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _fieldFilter('Nama kasir', _kasirFilter,
                                  hint: 'Contoh: Rizal'),
                              _fieldFilter('Mesin / perangkat', _mesinFilter,
                                  hint: 'Kasir 1 / ID mesin'),
                              _fieldFilter(
                                  'Nama / kode / barcode barang', _produkFilter,
                                  hint: 'Nama, kode, atau barcode'),
                              _fieldFilter('Nama pelanggan', _pelangganFilter,
                                  hint: 'Member atau pelanggan umum'),
                              _fieldFilter(
                                  'Nomor nota / kode transaksi', _notaFilter,
                                  hint: 'AB... / nomor nota'),
                              _fieldFilter('Metode pembayaran', _metodeFilter,
                                  hint: 'Tunai, QRIS, transfer, voucher'),
                              _fieldFilter('Jam mulai', _waktuMulaiFilter,
                                  hint: 'HH:mm'),
                              _fieldFilter('Jam sampai', _waktuSampaiFilter,
                                  hint: 'HH:mm'),
                              _fieldFilter(
                                  'Total minimal (Rp)', _totalMinimalFilter,
                                  keyboardType: TextInputType.number),
                              _fieldFilter(
                                  'Total maksimal (Rp)', _totalMaksimalFilter,
                                  keyboardType: TextInputType.number),
                              _fieldFilter(
                                  'Jumlah barang minimal', _qtyMinimalFilter,
                                  keyboardType: TextInputType.number),
                              _fieldFilter(
                                  'Jumlah barang maksimal', _qtyMaksimalFilter,
                                  keyboardType: TextInputType.number),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _resetFilterLanjutan,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset Filter'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _terapkan,
                              icon: const Icon(Icons.check),
                              label: const Text('Terapkan Filter'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            BannerPerubahanServer(
              key: ValueKey('perubahan:$_versiPerubahan'),
              baru: _idBaru.length,
              berubah: _idBerubah.length,
              dihapus: _jumlahHapus,
            ),
            if (_memuat)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        AppDetailGalatOpsional(detail: detailUntuk(_error)),
                      ])))
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
                  AppTableColumn('Aksi', width: 64, align: TextAlign.center),
                ],
                rows: _data.map((row) {
                  final kasir = '${row['kasir'] ?? '-'}';
                  final mesin = '${row['namaMesin'] ?? ''}'.trim();
                  final kasirMesin = mesin.isEmpty ? kasir : '$kasir / $mesin';
                  return AppTableRowData(
                    onTap: () => _lihatDetail(row),
                    cells: [
                      AppTableCell(
                        flex: 4,
                        child: KilauBaris(
                          kunci: _kunciDiffTransaksi(row),
                          idBaru: _idBaru,
                          idBerubah: _idBerubah,
                          child: Text('${row['nomorNota'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      AppTableCell.text(_formatWaktu(row['waktu']), flex: 2),
                      AppTableCell.text('${row['pembeli'] ?? 'Umum'}', flex: 2),
                      AppTableCell.text(kasirMesin, flex: 2),
                      AppTableCell(
                        flex: 2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StatusPill(
                                label: StrukScreen.labelPembayaran(row),
                                warna: AppColors.primary),
                            if (row['statusSinkronLokal'] != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                row['statusSinkronLokal'] == 'SYNCED'
                                    ? 'Cadangan lokal · tersinkron'
                                    : 'Cadangan lokal · menunggu sinkron',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: row['statusSinkronLokal'] == 'SYNCED'
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ],
                          ],
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
                        width: 64,
                        align: TextAlign.center,
                        child: AksiBarisMenu(aksi: [
                          AksiBaris(
                              ikon: Icons.visibility_outlined,
                              label: 'Detail transaksi',
                              onTap: () => _lihatDetail(row)),
                          // Riwayat revisi header nota (AuditTrails/Envers)
                          // -- hanya baris server yg punya id transaksi.
                          AksiBaris(
                              ikon: Icons.history,
                              label: 'Riwayat data ini',
                              onTap: row['idTransaksi'] == null
                                  ? null
                                  : () => tampilkanRiwayatData(context,
                                      entitas: 'transaksi',
                                      id: row['idTransaksi'] as Object,
                                      judul: '${row['nomorNota'] ?? ''}')),
                        ]),
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
