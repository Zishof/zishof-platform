import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../sesi.dart';
import 'kasir_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Struk sederhana (Fase 1 -- tampil di layar saja, cetak ESC/POS via core_hw
/// menyusul begitu paket itu diisi). Item diambil in-memory dari keranjang yang
/// barusan dibayar, sama seperti pola cetakStruk() di POS Desktop existing --
/// tidak perlu round-trip server untuk menampilkan struk.
class StrukScreen extends StatelessWidget {
  final String kode;
  final String waktu;
  final List<Map<String, dynamic>> item;
  final double total;
  final String metode;

  const StrukScreen({
    super.key,
    required this.kode,
    required this.waktu,
    required this.item,
    required this.total,
    required this.metode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi Berhasil'), automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 56),
                    const SizedBox(height: 8),
                    Text(Sesi.instance.tokoNama, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(kode, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    Text(waktu, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    const Divider(height: 24),
                    ...item.map((i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${i['nama']} x${i['qty']}')),
                              Text(_formatRupiah.format((i['harga'] as num) * (i['qty'] as num))),
                            ],
                          ),
                        )),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(_formatRupiah.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Metode', style: TextStyle(color: Colors.black54)),
                        Text(metode),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (Sesi.instance.pesanTerimaKasih.isNotEmpty)
                      Text(Sesi.instance.pesanTerimaKasih, textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const KasirScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Transaksi Baru'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
