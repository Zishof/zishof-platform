import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/pengaturan_struk.dart';
import '../services/print_util.dart';
import '../services/laporan_tutup_kas_pdf.dart';

final _rupiahLaporanKas =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

class LaporanTutupKasDialog extends StatelessWidget {
  const LaporanTutupKasDialog({super.key, required this.laporan});

  final Map<String, dynamic> laporan;

  num _angka(String kunci) => laporan[kunci] is num ? laporan[kunci] as num : 0;
  String _teks(String kunci) => laporan[kunci]?.toString() ?? '';
  List<Map<String, dynamic>> get _metode =>
      ((laporan['metodePembayaran'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Widget _baris(String nama, Object nilai, {bool tebal = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(nama,
                  style:
                      TextStyle(fontWeight: tebal ? FontWeight.bold : null))),
          Text(nilai.toString(),
              style: TextStyle(fontWeight: tebal ? FontWeight.bold : null)),
        ]),
      );

  Future<void> _cetak(BuildContext context) async {
    try {
      await PengaturanStruk.instance.muat();
      final (dokumen, format) = await buatPdfLaporanTutupKas(laporan,
          lebarMm: PengaturanStruk.instance.lebarKertasMm);
      await cetakLangsungKePrinterDefault(
          dokumen: dokumen, nama: 'Laporan Tutup Kas', format: format);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Laporan belum dapat dicetak: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Laporan Tutup Kas'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Text(_teks('namaToko'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    const Divider(),
                    Text('Nama Kasir : ${_teks('namaKasir')}'),
                    Text('Buka       : ${_teks('waktuBuka')}'),
                    Text('Tutup      : ${_teks('waktuTutup')}'),
                    const Divider(),
                    _baris('Modal Awal',
                        _rupiahLaporanKas.format(_angka('modalAwal'))),
                    _baris('Penjualan Tunai',
                        _rupiahLaporanKas.format(_angka('penjualanTunai'))),
                    _baris('Kas Seharusnya',
                        _rupiahLaporanKas.format(_angka('kasSeharusnya'))),
                    _baris('Jumlah Kas Tunai',
                        _rupiahLaporanKas.format(_angka('jumlahKasTunai'))),
                    _baris(
                        'Selisih', _rupiahLaporanKas.format(_angka('selisih')),
                        tebal: true),
                    const Divider(),
                    _baris('Retur Penjualan',
                        _rupiahLaporanKas.format(_angka('returPenjualan'))),
                    _baris('Biaya (${_angka('jumlahBiaya')}x)',
                        _rupiahLaporanKas.format(_angka('biaya'))),
                    _baris('Piutang (${_angka('jumlahTransaksiPiutang')}x)',
                        _rupiahLaporanKas.format(_angka('piutang'))),
                    const Divider(),
                    for (final m in _metode) ...[
                      Text(m['nama']?.toString() ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      _baris('${m['jumlahTransaksi'] ?? 0}x Penerimaan',
                          _rupiahLaporanKas.format(m['penerimaan'] ?? 0)),
                      _baris(
                          'Retur', _rupiahLaporanKas.format(m['retur'] ?? 0)),
                      _baris('Total ${m['nama'] ?? ''}',
                          _rupiahLaporanKas.format(m['total'] ?? 0),
                          tebal: true),
                      const SizedBox(height: 6),
                    ],
                    const Divider(),
                    _baris('Jumlah Transaksi', _angka('jumlahTransaksi'),
                        tebal: true),
                    _baris('Total Transaksi',
                        _rupiahLaporanKas.format(_angka('totalTransaksi')),
                        tebal: true),
                  ]),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
              onPressed: () => _cetak(context),
              icon: const Icon(Icons.print),
              label: const Text('Cetak Laporan')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Selesai')),
        ],
      );
}
