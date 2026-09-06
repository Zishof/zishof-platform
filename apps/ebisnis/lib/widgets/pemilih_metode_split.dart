import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';

/// Satu alokasi pembayaran pada transaksi yang memakai satu atau beberapa
/// metode. Nominal slot pertama tetap dikirim eksplisit oleh klien; server akan
/// menyimpannya sebagai sisa total setelah slot 2-5 agar kompatibel dengan
/// model transaksi lama.
class SlotBayar {
  final CaraBayar caraBayar;
  double nominal;

  SlotBayar(this.caraBayar, this.nominal);

  SlotBayar salin() => SlotBayar(caraBayar, nominal);
}

/// Validasi bersama untuk checkout dan koreksi transaksi. Toleransi Rp 1
/// mengikuti kontrak server untuk selisih pembulatan angka desimal.
String? validasiAlokasiPembayaran(Iterable<SlotBayar> slot, double total) {
  final daftar = slot.toList();
  if (daftar.isEmpty) return 'Pilih sedikitnya satu metode pembayaran.';
  if (daftar.length > 5) return 'Maksimal 5 metode pembayaran per transaksi.';
  final id = <int>{};
  for (var i = 0; i < daftar.length; i++) {
    final baris = daftar[i];
    if (!id.add(baris.caraBayar.id)) {
      return 'Metode ${baris.caraBayar.nama} dipilih lebih dari satu kali.';
    }
    if (!baris.nominal.isFinite || baris.nominal <= 0) {
      return 'Nominal metode ke-${i + 1} harus lebih dari Rp 0.';
    }
  }
  final dialokasikan =
      daftar.fold<double>(0, (jumlah, baris) => jumlah + baris.nominal);
  if ((dialokasikan - total).abs() >= 1) {
    final rupiah =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return 'Total alokasi ${rupiah.format(dialokasikan)} harus sama dengan '
        'total transaksi ${rupiah.format(total)}.';
  }
  return null;
}

/// Pemilih pembayaran bersama untuk checkout dan koreksi transaksi. Ketuk
/// baris untuk satu metode penuh, atau centang beberapa metode dan isi nominal
/// masing-masing sampai total alokasi seimbang.
class PemilihMetodeSplit extends StatefulWidget {
  final List<CaraBayar> daftarMetode;
  final List<SlotBayar> terpilihAwal;
  final double total;

  /// Muat ulang daftar metode dari server tanpa menutup sheet.
  final Future<List<CaraBayar>?> Function()? muatUlang;

  const PemilihMetodeSplit({
    super.key,
    required this.daftarMetode,
    required this.terpilihAwal,
    required this.total,
    this.muatUlang,
  });

  @override
  State<PemilihMetodeSplit> createState() => _PemilihMetodeSplitState();
}

class _PemilihMetodeSplitState extends State<PemilihMetodeSplit> {
  late List<SlotBayar> _terpilih;
  late List<CaraBayar> _metode;
  bool _menyinkron = false;

  @override
  void initState() {
    super.initState();
    _metode = List<CaraBayar>.of(widget.daftarMetode);
    _terpilih = widget.terpilihAwal.map((s) => s.salin()).toList();
  }

  Future<void> _sinkronkanMetode() async {
    if (_menyinkron || widget.muatUlang == null) return;
    setState(() => _menyinkron = true);
    try {
      final baru = await widget.muatUlang!.call();
      if (!mounted) return;
      if (baru == null || baru.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Metode pembayaran tidak dapat dimuat. Periksa koneksi lalu coba lagi.')));
        return;
      }
      setState(() {
        _metode = List<CaraBayar>.of(baru);
        _terpilih
            .removeWhere((s) => !_metode.any((c) => c.id == s.caraBayar.id));
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Daftar metode pembayaran diperbarui dari server.')));
    } finally {
      if (mounted) setState(() => _menyinkron = false);
    }
  }

  void _toggle(CaraBayar cara) {
    final index = _terpilih.indexWhere((s) => s.caraBayar.id == cara.id);
    if (index >= 0) {
      setState(() => _terpilih.removeAt(index));
      return;
    }
    if (_terpilih.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Maksimal 5 metode pembayaran per transaksi.')));
      return;
    }
    setState(() {
      _terpilih.add(SlotBayar(cara, 0));
      _bagiRataJikaKosong();
    });
  }

  void _bagiRataJikaKosong() {
    if (_terpilih.length < 2 || widget.total <= 0) return;
    if (!_terpilih.every((s) => s.nominal == 0)) return;
    final banyak = _terpilih.length;
    final rata = (widget.total / banyak).floorToDouble();
    for (var i = 0; i < banyak; i++) {
      _terpilih[i].nominal =
          i == banyak - 1 ? widget.total - rata * (banyak - 1) : rata;
    }
  }

  double get _totalDialokasikan =>
      _terpilih.fold(0.0, (jumlah, slot) => jumlah + slot.nominal);
  double get _sisa => widget.total - _totalDialokasikan;
  String? get _galat => validasiAlokasiPembayaran(_terpilih, widget.total);

  @override
  Widget build(BuildContext context) {
    final rupiah =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Ketuk baris untuk bayar penuh dengan 1 metode, atau centang kotak untuk menggabungkan sampai 5 metode.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (widget.muatUlang != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _menyinkron ? null : _sinkronkanMetode,
                      icon: _menyinkron
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync, size: 16),
                      label: const Text('Sinkronkan cara pembayaran'),
                    ),
                  ),
                ),
              ..._metode.map((cara) {
                final aktif = _terpilih.any((s) => s.caraBayar.id == cara.id);
                return ListTile(
                  leading: Checkbox(
                    value: aktif,
                    onChanged: (_) => _toggle(cara),
                  ),
                  title: Text(cara.nama),
                  onTap: () => Navigator.of(context)
                      .pop([SlotBayar(cara, widget.total)]),
                );
              }),
              if (_terpilih.length >= 2) ...[
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Bagi Nominal per Metode',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ..._terpilih.map((slot) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(slot.caraBayar.nama,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 140,
                            child: TextFormField(
                              key: ValueKey(
                                  'nominal-split-${slot.caraBayar.id}'),
                              initialValue: slot.nominal.toStringAsFixed(0),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                prefixText: 'Rp ',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (nilai) => setState(() =>
                                  slot.nominal = double.tryParse(nilai) ?? 0),
                            ),
                          ),
                        ],
                      ),
                    )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sisa belum dialokasikan',
                          style: TextStyle(fontSize: 12)),
                      Text(
                        rupiah.format(_sisa),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _galat == null ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_galat != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(_galat!,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: ElevatedButton(
                    onPressed: _galat == null
                        ? () => Navigator.of(context)
                            .pop(_terpilih.map((s) => s.salin()).toList())
                        : null,
                    child: const Text('Terapkan Split Pembayaran'),
                  ),
                ),
              ] else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
