import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import 'login_screen.dart';
import 'keranjang_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  bool _memuat = true;
  String? _pesanError;

  List<Produk> _semuaProduk = [];
  List<Kategori> _kategori = [];
  int? _kategoriTerpilih; // null = "Semua"
  String _kataKunci = '';

  final List<ItemKeranjang> _keranjang = [];

  @override
  void initState() {
    super.initState();
    _muatAwal();
  }

  Future<void> _muatAwal() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final konfig = await ApiClient.instance.aksi('konfigurasi');
      Sesi.instance
        ..tokoNama = (konfig['tokoNama'] ?? '') as String
        ..tokoId = konfig['tokoId'] as int?
        ..userId = (konfig['userId'] ?? '') as String
        ..pajakPersen = (konfig['pajakPersen'] as num?)?.toDouble() ?? 0
        ..pesanTerimaKasih = (konfig['pesanTerimaKasih'] ?? '') as String
        ..caraBayar = ((konfig['caraBayar'] as List?) ?? [])
            .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
            .toList();

      final katalog = await ApiClient.instance.aksi('katalog');
      final produk = ((katalog['produk'] as List?) ?? [])
          .map((e) => Produk.fromJson(e as Map<String, dynamic>))
          .toList();
      final kategori = ((katalog['kategori'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _semuaProduk = produk;
        _kategori = kategori;
      });
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  List<Produk> get _produkTersaring {
    return _semuaProduk.where((p) {
      final cocokKategori = _kategoriTerpilih == null || p.kategoriId == _kategoriTerpilih;
      final cocokKeyword = _kataKunci.isEmpty ||
          p.nama.toLowerCase().contains(_kataKunci.toLowerCase()) ||
          p.kode.toLowerCase().contains(_kataKunci.toLowerCase()) ||
          p.barcode.toLowerCase().contains(_kataKunci.toLowerCase());
      return cocokKategori && cocokKeyword;
    }).toList();
  }

  void _tambahKeKeranjang(Produk p) {
    setState(() {
      final existing = _keranjang.where((i) => i.produk.id == p.id).toList();
      if (existing.isNotEmpty) {
        existing.first.jumlah++;
      } else {
        _keranjang.add(ItemKeranjang(produk: p));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.nama} ditambahkan'), duration: const Duration(milliseconds: 700)),
    );
  }

  double get _totalKeranjang => _keranjang.fold(0, (s, i) => s + i.subtotal);
  int get _jumlahItemKeranjang => _keranjang.fold(0, (s, i) => s + i.jumlah);

  Future<void> _bukaKeranjang() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KeranjangScreen(keranjang: _keranjang),
    ));
    setState(() {}); // sinkronkan badge jumlah/total setelah checkout/perubahan qty
  }

  Future<void> _logout() async {
    await ApiClient.instance.hapusToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Sesi.instance.tokoNama.isEmpty ? 'eBisnis' : Sesi.instance.tokoNama),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muatAwal, tooltip: 'Muat ulang katalog'),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Keluar'),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _muatAwal, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Cari produk (nama/kode/barcode)...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _kataKunci = v),
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: const Text('Semua'),
                              selected: _kategoriTerpilih == null,
                              onSelected: (_) => setState(() => _kategoriTerpilih = null),
                            ),
                          ),
                          ..._kategori.map((k) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(k.nama),
                                  selected: _kategoriTerpilih == k.id,
                                  onSelected: (_) => setState(() => _kategoriTerpilih = k.id),
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _produkTersaring.length,
                        itemBuilder: (context, i) => _KartuProduk(
                          produk: _produkTersaring[i],
                          onTap: () => _tambahKeKeranjang(_produkTersaring[i]),
                        ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _keranjang.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ElevatedButton(
                  onPressed: _bukaKeranjang,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0563D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Keranjang ($_jumlahItemKeranjang)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_formatRupiah.format(_totalKeranjang), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _KartuProduk extends StatelessWidget {
  final Produk produk;
  final VoidCallback onTap;
  const _KartuProduk({required this.produk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habis = produk.stok <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: habis ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF1E3A5F),
                    child: Text(
                      produk.nama.isNotEmpty ? produk.nama[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              Text(produk.nama, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_formatRupiah.format(produk.hargaJual), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
              Text(habis ? 'Habis' : 'Stok ${produk.stok}', style: TextStyle(fontSize: 11, color: habis ? Colors.red : Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
