import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import 'struk_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar Keranjang + Checkout -- menerima referensi list yang SAMA dengan
/// KasirScreen (bukan salinan), jadi perubahan qty/hapus di sini otomatis
/// tercermin balik ke KasirScreen begitu layar ini ditutup (pola sederhana,
/// cukup untuk pilot -- lihat catatan di KasirScreen._bukaKeranjang).
class KeranjangScreen extends StatefulWidget {
  final List<ItemKeranjang> keranjang;
  const KeranjangScreen({super.key, required this.keranjang});

  @override
  State<KeranjangScreen> createState() => _KeranjangScreenState();
}

class _KeranjangScreenState extends State<KeranjangScreen> {
  CaraBayar? _caraBayarTerpilih;
  bool _memproses = false;

  @override
  void initState() {
    super.initState();
    if (Sesi.instance.caraBayar.isNotEmpty) {
      _caraBayarTerpilih = Sesi.instance.caraBayar.first;
    }
  }

  double get _total => widget.keranjang.fold(0, (s, i) => s + i.subtotal);

  void _ubahJumlah(ItemKeranjang item, int delta) {
    setState(() {
      item.jumlah += delta;
      if (item.jumlah <= 0) widget.keranjang.remove(item);
    });
  }

  String _buatKodeUnik() {
    final rand = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final acak = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'EBISNIS-${DateTime.now().millisecondsSinceEpoch}-$acak';
  }

  String _formatWaktuServer(DateTime d) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${pad(d.day)}-${pad(d.month)}-${d.year} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  Future<void> _bayar() async {
    if (widget.keranjang.isEmpty) return;
    if (_caraBayarTerpilih == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih metode pembayaran terlebih dahulu.')));
      return;
    }
    setState(() => _memproses = true);
    final kodeUnik = _buatKodeUnik();
    final waktu = DateTime.now();
    try {
      await ApiClient.instance.aksi('bayar', {
        'kodeUnik': kodeUnik,
        'clientTrxId': kodeUnik,
        'idToko': Sesi.instance.tokoId,
        'tokoId': Sesi.instance.tokoId,
        'kasir': Sesi.instance.userId,
        'waktu': _formatWaktuServer(waktu),
        'caraBayar': _caraBayarTerpilih!.id,
        'total': _total,
        'id_member': null,
        'draftPembelianAnggotaKoperasi': null,
        'transaksi': widget.keranjang
            .map((i) => {
                  'id': i.produk.id,
                  'kode': i.produk.kode,
                  'nama': i.produk.nama,
                  'harga': i.produk.hargaJual,
                  'jumlah': i.jumlah,
                  'diskon': 0,
                  'aturanDiskon': null,
                  'cashback': 0,
                })
            .toList(),
      });

      if (!mounted) return;
      final itemStruk = widget.keranjang
          .map((i) => {'nama': i.produk.nama, 'qty': i.jumlah, 'harga': i.produk.hargaJual})
          .toList();
      final metodeNama = _caraBayarTerpilih!.nama;
      final totalStruk = _total;
      widget.keranjang.clear();
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => StrukScreen(
          kode: kodeUnik,
          waktu: _formatWaktuServer(waktu),
          item: itemStruk,
          total: totalStruk,
          metode: metodeNama,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: widget.keranjang.isEmpty
          ? const Center(child: Text('Keranjang kosong.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: widget.keranjang.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = widget.keranjang[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.produk.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(_formatRupiah.format(item.produk.hargaJual), style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _ubahJumlah(item, -1)),
                      Text('${item.jumlah}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _ubahJumlah(item, 1)),
                      SizedBox(
                        width: 96,
                        child: Text(_formatRupiah.format(item.subtotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: widget.keranjang.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (Sesi.instance.caraBayar.isNotEmpty)
                      DropdownButtonFormField<CaraBayar>(
                        value: _caraBayarTerpilih,
                        decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder()),
                        items: Sesi.instance.caraBayar
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.nama)))
                            .toList(),
                        onChanged: (v) => setState(() => _caraBayarTerpilih = v),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(_formatRupiah.format(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _memproses ? null : _bayar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _memproses
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Bayar', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
