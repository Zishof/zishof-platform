import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../widgets/dashboard_charts.dart';

String _formatTanggalJam(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

/// Tab 9/9 "Kepatuhan Operasional" -- aksi `kepatuhan_operasional`. Tidak ada
/// chart di tab ini (padanan persis Electron) -- murni 6 KPI + 6 tabel generik,
/// masing-masing satu aturan kepatuhan.
class RingkasanTabKepatuhan extends StatefulWidget {
  const RingkasanTabKepatuhan({super.key});
  @override
  State<RingkasanTabKepatuhan> createState() => _RingkasanTabKepatuhanState();
}

class _RingkasanTabKepatuhanState extends State<RingkasanTabKepatuhan> {
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('kepatuhan_operasional');
      setState(() => _d = hasil);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Widget _tabel(String judul, List<Map<String, dynamic>> rows, List<(String, String Function(Map<String, dynamic>))> kolom) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('Tidak ada catatan -- baik.', style: TextStyle(color: Colors.black45, fontSize: 12))
            else
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: kolom
                          .map((k) => Text('${k.$1}: ${k.$2(r)}', style: const TextStyle(fontSize: 11)))
                          .toList(),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null) return statusMuatDasbor(memuat: _memuat, error: _error, onCoba: _muat);
    final d = _d!;
    final opnameOverdue = ((d['opnameOverdue'] as List?) ?? []).cast<Map<String, dynamic>>();
    final sesiTerbuka = ((d['sesiTerbuka'] as List?) ?? []).cast<Map<String, dynamic>>();
    final selisihKas = ((d['selisihKas'] as List?) ?? []).cast<Map<String, dynamic>>();
    final diskonManual = ((d['diskonManual'] as List?) ?? []).cast<Map<String, dynamic>>();
    final selisihOpname = ((d['selisihOpname'] as List?) ?? []).cast<Map<String, dynamic>>();
    final pembatalan = ((d['pembatalanTransaksi'] as List?) ?? []).cast<Map<String, dynamic>>();
    final adaTabelPembatalan = d['adaTabelPembatalan'] != false;

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          BarisKpi(kartu: [
            KartuKpi(label: 'Telat Opname', nilai: '${d['jmlTelatOpname'] ?? 0}', warna: Colors.red),
            KartuKpi(label: 'Sesi Lupa Tutup', nilai: '${d['jmlSesiLupaTutup'] ?? 0}', warna: Colors.orange),
            KartuKpi(label: 'Selisih Kas', nilai: formatRupiahDasbor.format(d['totalSelisihKas'] ?? 0), warna: const Color(0xFFC0563D)),
            KartuKpi(label: 'Diskon Manual', nilai: formatRupiahDasbor.format(d['totalDiskonManual'] ?? 0), warna: const Color(0xFFB8860B)),
            KartuKpi(label: 'Selisih Opname', nilai: formatRupiahDasbor.format(d['totalSelisihOpnameRp'] ?? 0), warna: Colors.deepOrange),
            KartuKpi(label: 'Pembatalan', nilai: '${d['jmlPembatalan'] ?? 0}', warna: Colors.red),
          ]),
          const SizedBox(height: 16),
          _tabel('Toko Telat Opname (≥30 hari)', opnameOverdue, [
            ('Toko', (r) => '${r['toko']}'),
            ('Terakhir Opname', (r) => _formatTanggalJam(r['terakhirOpname'])),
            ('Hari', (r) => '${r['hariSejak']}'),
          ]),
          _tabel('Sesi Kas Terbuka ≥24 Jam', sesiTerbuka, [
            ('Toko', (r) => '${r['toko']}'),
            ('Kasir', (r) => '${r['kasir']}'),
            ('Waktu Buka', (r) => _formatTanggalJam(r['waktuBuka'])),
            ('Jam Terbuka', (r) => (r['jamTerbuka'] as num?)?.toStringAsFixed(0) ?? '-'),
          ]),
          _tabel('Selisih Kas Saat Tutup (30 hari)', selisihKas, [
            ('Toko', (r) => '${r['toko']}'),
            ('Kasir', (r) => '${r['kasir']}'),
            ('Waktu Tutup', (r) => _formatTanggalJam(r['waktuTutup'])),
            ('Selisih', (r) => formatRupiahDasbor.format(r['selisih'] ?? 0)),
          ]),
          _tabel('Diskon Manual Tanpa Aturan (30 hari)', diskonManual, [
            ('Toko', (r) => '${r['toko']}'),
            ('Kasir', (r) => '${r['kasir']}'),
            ('Jml Transaksi', (r) => '${r['jumlahTransaksi']}'),
            ('Total Diskon', (r) => formatRupiahDasbor.format(r['totalDiskon'] ?? 0)),
          ]),
          _tabel('Dampak Selisih Opname (30 hari)', selisihOpname, [
            ('Toko', (r) => '${r['toko']}'),
            ('Jml Baris', (r) => '${r['jumlahBaris']}'),
            ('Jml Selisih', (r) => '${r['jumlahSelisih']}'),
            ('Nilai Rupiah', (r) => formatRupiahDasbor.format(r['nilaiRupiah'] ?? 0)),
          ]),
          if (!adaTabelPembatalan)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Text('Fitur pembatalan transaksi baru ditambahkan -- server perlu di-restart agar tabel ini terisi.',
                  style: TextStyle(fontSize: 11, color: Colors.black87)),
            ),
          _tabel('Pembatalan Transaksi (30 hari)', pembatalan, [
            ('Toko', (r) => '${r['toko']}'),
            ('Kasir', (r) => '${r['namaKasir']}'),
            ('Tanggal', (r) => _formatTanggalJam(r['tanggalDibatalkan'])),
            ('Alasan', (r) => '${r['alasan']}'),
            ('Total', (r) => formatRupiahDasbor.format(r['totalBiaya'] ?? 0)),
          ]),
        ],
      ),
    );
  }
}
