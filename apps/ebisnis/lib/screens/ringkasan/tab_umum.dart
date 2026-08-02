import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../services/print_util.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/dashboard_charts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final _formatTanggalServer = DateFormat('yyyy-MM-dd');

String _formatWaktu(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

/// Tab 1/9 "Ringkasan Umum" -- aksi `dashboard_umum`: 4 KPI (hari/minggu/bulan/
/// semester), tren omzet (periode dipilih), omzet per kategori, komposisi
/// metode bayar, jam sibuk, dan tabel transaksi (filter tanggal+pembeli,
/// paginasi server-side, tombol Layani/Layani Semua).
class RingkasanTabUmum extends StatefulWidget {
  const RingkasanTabUmum({super.key});
  @override
  State<RingkasanTabUmum> createState() => _RingkasanTabUmumState();
}

class _RingkasanTabUmumState extends State<RingkasanTabUmum> {
  static const _pageSize = 10;
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;
  String _periodeTren = 'harian';
  DateTime? _mulai;
  DateTime? _sampai;
  String _cariPembeli = '';
  int _halaman = 1;

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
      final hasil = await ApiClient.instance.aksi('dashboard_umum', {
        'periodeTren': _periodeTren,
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
        if (_cariPembeli.isNotEmpty) 'cariPembeli': _cariPembeli,
        'page': _halaman,
        'pageSize': _pageSize,
      });
      setState(() => _d = hasil);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _terapkan() async {
    _halaman = 1;
    await _muat();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _layani(dynamic id) async {
    try {
      await ApiClient.instance.aksi('layani_transaksi', {'id': id});
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _layaniSemua() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Layani Semua?'),
        content: const Text('Semua transaksi pada rentang filter ini akan ditandai terlayani.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      final hasil = await ApiClient.instance.aksi('layani_semua_transaksi', {
        if (_mulai != null) 'tglMulai': _formatTanggalServer.format(_mulai!),
        if (_sampai != null) 'tglSampai': _formatTanggalServer.format(_sampai!),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${hasil['jumlahBarisDiperbarui'] ?? 0} transaksi ditandai terlayani.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// Cetak Struk dari baris transaksi Ringkasan Umum -- gap-closure (tab ini
  /// sebelumnya sama sekali tak punya aksi cetak/batal, padahal
  /// `tab_kepatuhan.dart` sudah menampilkan hitungan "Pembatalan Transaksi"
  /// yg mengisyaratkan aksinya ADA di server, hanya tak diekspos di sini).
  /// Bangun PDF 80mm sendiri dari `detail_transaksi` (pola sama persis
  /// `struk_screen.dart._cetakStruk`) -- bukan struk offline-first spt saat
  /// checkout, ini reprint transaksi yg SUDAH final di server.
  Future<void> _cetakStruk(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance.aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items = ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 10 * PdfPageFormat.mm),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('${hasil['kode'] ?? ''}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.Text(_formatWaktu(row['waktu']), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9)),
              pw.Divider(),
              ...items.map((i) => pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('${i['nama']} x${(i['qty'] as num).toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9))),
                      pw.Text(formatRupiahDasbor.format((i['harga'] as num) * (i['qty'] as num) - ((i['diskon'] as num?) ?? 0)), style: pw.TextStyle(fontSize: 9)),
                    ],
                  )),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text(formatRupiahDasbor.format(hasil['totalBiaya'] ?? 0), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      );
      await cetakLangsungKePrinterDefault(dokumen: doc, nama: 'struk-${hasil['kode']}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal cetak: $e')));
    }
  }

  Future<void> _batalkan(Map<String, dynamic> row) async {
    final alasanController = TextEditingController();
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Transaksi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${row['pembeli']} · ${_formatWaktu(row['waktu'])} akan dibatalkan permanen.'),
            const SizedBox(height: 12),
            TextField(controller: alasanController, decoration: const InputDecoration(labelText: 'Alasan Pembatalan *', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    if (alasanController.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      return;
    }
    try {
      await ApiClient.instance.aksi('batalkan_transaksi', {'id': row['idTransaksi'], 'alasan': alasanController.text.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaksi dibatalkan.')));
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _tampilkanAksi(Map<String, dynamic> row) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.info_outline), title: const Text('Detail'), onTap: () {
              Navigator.of(context).pop();
              _lihatDetail(row);
            }),
            ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Cetak Struk'), onTap: () {
              Navigator.of(context).pop();
              _cetakStruk(row);
            }),
            if (Sesi.instance.bolehKelola)
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                title: const Text('Batalkan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _batalkan(row);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _lihatDetail(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance.aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items = ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detail ${hasil['kode'] ?? ''}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...items.map((i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(child: Text('${i['nama']} x${(i['qty'] as num).toStringAsFixed(0)}')),
                            Text(formatRupiahDasbor.format((i['harga'] as num) * (i['qty'] as num) - ((i['diskon'] as num?) ?? 0))),
                          ],
                        ),
                      )),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(formatRupiahDasbor.format(hasil['totalBiaya'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
            // Cetak Struk & Batalkan langsung di sini -- gap-closure: sebelumnya
            // HANYA lewat menu tekan-tahan (_tampilkanAksi), tak lazim dipakai
            // mouse desktop sehingga terkesan "cuma popup tanpa aksi" (bahkan
            // utk supervisor yang harusnya boleh Batalkan).
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _cetakStruk(row);
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Cetak Struk'),
            ),
            if (Sesi.instance.bolehKelola)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _batalkan(row);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Batalkan'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null) return statusMuatDasbor(memuat: _memuat, error: _error, onCoba: _muat);
    final d = _d!;
    final kpi = (d['kpi'] as Map<String, dynamic>?) ?? {};
    final transaksi = (d['transaksi'] as Map<String, dynamic>?) ?? {};
    final data = ((transaksi['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    final total = (transaksi['total'] as num?)?.toInt() ?? 0;
    final totalHalaman = (total / _pageSize).ceil().clamp(1, 999999);

    Map<String, dynamic> k(String key) => (kpi[key] as Map<String, dynamic>?) ?? {};

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (d['semuaToko'] == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Menampilkan data SEMUA toko (akun admin).', style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
            ),
          LayoutBuilder(builder: (context, c) {
            final lebar = c.maxWidth;
            final kolom = lebar >= 1000 ? 5 : (lebar >= 700 ? 3 : 2);
            return GridView.count(
              crossAxisCount: kolom,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                AppKpiCard(icon: Icons.receipt_long, warna: AppColors.primary, nilai: '${k('hariIni')['trx'] ?? 0}', label: 'Transaksi Hari Ini'),
                AppKpiCard(icon: Icons.payments_outlined, warna: AppColors.success, nilai: formatRupiahDasbor.format(k('hariIni')['rp'] ?? 0), label: 'Omzet Hari Ini'),
                AppKpiCard(icon: Icons.calendar_view_week_outlined, warna: AppColors.info, nilai: formatRupiahDasbor.format(k('mingguIni')['rp'] ?? 0), label: 'Omzet Minggu Ini'),
                AppKpiCard(icon: Icons.calendar_month_outlined, warna: AppColors.warning, nilai: formatRupiahDasbor.format(k('bulanIni')['rp'] ?? 0), label: 'Omzet Bulan Ini'),
                AppKpiCard(icon: Icons.stacked_line_chart, warna: AppColors.teal, nilai: formatRupiahDasbor.format(k('semesterIni')['rp'] ?? 0), label: 'Omzet Semester Ini'),
              ],
            );
          }),
          const SizedBox(height: 16),
          AppSectionCard(
            judul: 'Tren Omzet',
            aksiJudul: Wrap(
              spacing: 6,
              children: ['harian', 'mingguan', 'bulanan']
                  .map((p) => ChoiceChip(
                        label: Text(p),
                        selected: _periodeTren == p,
                        onSelected: (_) {
                          setState(() => _periodeTren = p);
                          _muat();
                        },
                      ))
                  .toList(),
            ),
            child: BarVertikal(data: titikDariList(d['tren'] as List?, labelKey: 'label', nilaiKey: 'jumlah')),
          ),
          const SizedBox(height: 16),
          AppSectionCard(judul: 'Omzet per Kategori', child: BarHorizontal(data: titikDariList(d['omzetKategori'] as List?), formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 16),
          AppSectionCard(judul: 'Komposisi Metode Bayar', child: StackProporsional(data: titikDariList(d['metodeBayar'] as List?))),
          const SizedBox(height: 16),
          AppSectionCard(judul: 'Jam Sibuk', child: BarHorizontal(data: titikDariList(d['jamSibuk'] as List?), warna: AppColors.warning, tampilkanPeringkat: false)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await showDatePicker(context: context, initialDate: _mulai ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (v != null) {
                      _mulai = v;
                      await _terapkan();
                    }
                  },
                  child: Text(_mulai == null ? 'Dari Tanggal' : _formatTanggalServer.format(_mulai!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await showDatePicker(context: context, initialDate: _sampai ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (v != null) {
                      _sampai = v;
                      await _terapkan();
                    }
                  },
                  child: Text(_sampai == null ? 'Sampai Tanggal' : _formatTanggalServer.format(_sampai!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Cari pembeli...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                  onSubmitted: (v) {
                    _cariPembeli = v;
                    _terapkan();
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _layaniSemua, child: const Text('Layani Semua')),
            ],
          ),
          const SizedBox(height: 8),
          if (data.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Belum ada transaksi.')))
          else
            ...data.map((row) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    title: Text('${row['pembeli']} · ${row['barang']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text('${_formatWaktu(row['waktu'])} · ${row['metode']}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatRupiahDasbor.format(row['total'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        if (row['terlayani'] != true)
                          TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 24), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            onPressed: () => _layani(row['idTransaksi']),
                            child: const Text('Layani', style: TextStyle(fontSize: 11)),
                          )
                        else
                          const Text('Terlayani', style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32))),
                      ],
                    ),
                    onTap: () => _lihatDetail(row),
                    onLongPress: () => _tampilkanAksi(row),
                  ),
                )),
          if (total > _pageSize)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: _halaman > 1 ? () => _pindah(_halaman - 1) : null),
                  Text('Halaman $_halaman / $totalHalaman'),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: _halaman < totalHalaman ? () => _pindah(_halaman + 1) : null),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
