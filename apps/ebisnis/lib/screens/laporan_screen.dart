import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'laporan_detail_screen.dart';

/// Katalog ~150 laporan (32 kategori) -- padanan `laporan.html`/`laporan-renderer.js`
/// Electron & `laporan_laporan.jsp`. Metadata katalog (`laporan_katalog`) SEPENUHNYA
/// data-driven (id/judul/ket/produk?/pelanggan?/perToko?/url?), jadi layar ini
/// generik utk semua laporan -- TIDAK ada kode khusus per-laporan (lihat JavaDoc
/// LaporanKatalogData di server). ~13 item punya `url` (laporan akuntansi resmi
/// ZK/JRXML) -- ini dibuka EKSTERNAL via browser, bukan lewat alur jalankan/PDF
/// generik, karena bukan bagian dari kontrak kolom/baris yang sama.
class LaporanScreen extends StatefulWidget {
  const LaporanScreen({super.key});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _kategori = [];
  final _controllerCari = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _controllerCari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_katalog');
      final arr = (hasil['kategori'] as List?) ?? [];
      setState(() => _kategori = arr.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _bukaItem(Map<String, dynamic> item) async {
    final url = item['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final origin = Uri.parse(ApiClient.baseUrl).origin;
      final uri = Uri.parse('$origin$url');
      final berhasil = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!berhasil && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tidak bisa membuka $uri')));
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LaporanDetailScreen(item: item)));
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> get _terfilter {
    final kw = _controllerCari.text.trim().toLowerCase();
    final hasil = <MapEntry<String, List<Map<String, dynamic>>>>[];
    for (final k in _kategori) {
      final kat = k['kat'] as String? ?? '';
      final items = ((k['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kw.isEmpty) {
        hasil.add(MapEntry(kat, items));
        continue;
      }
      final cocokKategori = kat.toLowerCase().contains(kw);
      final itemCocok = cocokKategori
          ? items
          : items.where((it) {
              final judul = (it['judul'] as String? ?? '').toLowerCase();
              final ket = (it['ket'] as String? ?? '').toLowerCase();
              return judul.contains(kw) || ket.contains(kw);
            }).toList();
      if (itemCocok.isNotEmpty) hasil.add(MapEntry(kat, itemCocok));
    }
    return hasil;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.laporanLaporan,
      judul: 'Laporan-Laporan',
      subjudul: 'Katalog laporan siap pakai',
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat, tooltip: 'Muat ulang'),
      actionsAppBar: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _muat, tooltip: 'Muat ulang')],
      scrollable: false,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(child: Text('Gagal memuat: $_pesanError'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _controllerCari,
                        decoration: const InputDecoration(hintText: 'Cari laporan...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: _terfilter.map((entri) => _panelKategori(entri.key, entri.value)).toList(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _panelKategori(String kategori, List<Map<String, dynamic>> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(kategori, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${items.length} laporan'),
        initiallyExpanded: _controllerCari.text.trim().isNotEmpty,
        children: items.map((item) {
          final adaUrl = (item['url'] as String? ?? '').isNotEmpty;
          return ListTile(
            title: Text(item['judul'] as String? ?? '-'),
            subtitle: (item['ket'] as String? ?? '').isNotEmpty ? Text(item['ket'] as String) : null,
            trailing: Icon(adaUrl ? Icons.open_in_new : Icons.chevron_right, color: adaUrl ? AppColors.info : AppColors.textSecondary, size: 18),
            onTap: () => _bukaItem(item),
          );
        }).toList(),
      ),
    );
  }
}
