import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import 'keranjang_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

enum _Filter { semua, online, tertahan }

/// Layar Pesanan (padanan pesanan.html/pesanan-renderer.js Electron) --
/// gabungan 2 jenis draft (lihat JavaDoc [Pesanan]): Pesanan Online (dibuat
/// pembeli sendiri, diselesaikan lewat "Verifikasi & Selesaikan") dan
/// Keranjang Tertahan (ditahan kasir lewat tombol "Tahan" di Keranjang,
/// dilanjutkan lewat "Muat ke Keranjang" -- inilah bagian "resume" yang
/// disebut di task #181).
///
/// Belum ada di iterasi ini (menyusul): filter tanggal/kode/pembeli/pedagang,
/// "Bayar Semua" massal, Cetak Struk dari baris pesanan, Hitung Ulang diskon.
class PesananScreen extends StatefulWidget {
  const PesananScreen({super.key});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Pesanan> _semua = [];
  _Filter _filter = _Filter.semua;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('pesanan_list', {'hanya_belum_lunas': true, 'limit': 200});
      final data = ((hasil['pesanan'] as List?) ?? []).map((e) => Pesanan.fromJson(e as Map<String, dynamic>)).toList();
      setState(() => _semua = data);
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  List<Pesanan> get _tersaring {
    switch (_filter) {
      case _Filter.online:
        return _semua.where((p) => p.dariPembeliOnline).toList();
      case _Filter.tertahan:
        return _semua.where((p) => !p.dariPembeliOnline).toList();
      case _Filter.semua:
        return _semua;
    }
  }

  Future<void> _lihatDetail(Pesanan p) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Detail ${p.kode}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pemesan: ${p.pemesan.isEmpty ? "-" : p.pemesan}'),
              if (p.namaMesin != null) Text('Mesin: ${p.namaMesin}'),
              if (p.kasirLoginNama.isNotEmpty) Text('Kasir: ${p.kasirLoginNama}'),
              const Divider(),
              ...p.items.map((i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${i.nama} x${i.jumlah.toStringAsFixed(0)}')),
                        Text(_formatRupiah.format(i.harga * i.jumlah - i.diskon)),
                      ],
                    ),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_formatRupiah.format(p.totalBiaya), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup'))],
      ),
    );
  }

  Future<void> _muatKeKeranjang(Pesanan p) async {
    Anggota? member;
    if (p.anggotaId != null) {
      try {
        final hasil = await ApiClient.instance.aksi('cari_member', {'id': p.anggotaId});
        final arr = (hasil['member'] as List?) ?? [];
        if (arr.isNotEmpty) member = Anggota.fromJson(arr.first as Map<String, dynamic>);
      } catch (_) {
        // Gagal memuat detail member -- tetap lanjut memuat keranjang tanpa member (bukan blocker).
      }
    }
    final keranjang = p.items
        .map((i) => ItemKeranjang(
              produk: Produk(
                id: i.produkId ?? -1,
                kode: i.kode,
                barcode: '',
                nama: i.nama,
                hargaJual: i.harga,
                stok: 999999,
                kategoriId: null,
                kategoriNama: '',
                gambarUrl: null,
              ),
              jumlah: i.jumlah.round(),
              diskon: i.diskon,
              cashback: i.cashback,
              aturanDiskonId: i.aturanDiskonId,
            ))
        .toList();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KeranjangScreen(keranjang: keranjang, draftIdSumber: p.id, memberAwal: member),
    ));
    await _muat();
  }

  Future<void> _verifikasiDanSelesaikan(Pesanan p) async {
    final caraBayar = await showDialog<CaraBayar>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pilih Metode Pembayaran'),
        children: Sesi.instance.caraBayar
            .map((c) => SimpleDialogOption(onPressed: () => Navigator.of(context).pop(c), child: Text(c.nama)))
            .toList(),
      ),
    );
    if (caraBayar == null) return;

    try {
      await ApiClient.instance.aksi('bayar', {
        'kodeUnik': '${p.kode}-VERIF-${DateTime.now().millisecondsSinceEpoch}',
        'clientTrxId': '${p.kode}-VERIF-${DateTime.now().millisecondsSinceEpoch}',
        'idToko': Sesi.instance.tokoId,
        'tokoId': Sesi.instance.tokoId,
        'kasir': Sesi.instance.userId,
        'waktu': _formatWaktuServer(DateTime.now()),
        'caraBayar': caraBayar.id,
        'total': p.totalBiaya,
        'id_member': p.anggotaId,
        'draftPembelianAnggotaKoperasi': p.id,
        'transaksi': p.items
            .map((i) => {
                  'id': i.produkId,
                  'kode': i.kode,
                  'nama': i.nama,
                  'harga': i.harga,
                  'jumlah': i.jumlah,
                  'diskon': i.diskon,
                  'aturanDiskon': i.aturanDiskonId,
                  'cashback': i.cashback,
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${p.kode} berhasil diselesaikan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _formatWaktuServer(DateTime d) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${pad(d.day)}-${pad(d.month)}-${d.year} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  Future<void> _batalkan(Pesanan p) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Pesanan?'),
        content: Text('${p.kode} akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      await ApiClient.instance.aksi('batal_pesanan', {'id': p.id});
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final semua = _semua;
    final jumlahOnline = semua.where((p) => p.dariPembeliOnline).length;
    final jumlahTertahan = semua.length - jumlahOnline;
    final nilaiMenunggu = semua.fold<double>(0, (s, p) => s + p.totalBiaya);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)],
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
                        ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    children: [
                      SizedBox(
                        height: 84,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _kartuKpi('Total', '${semua.length}', const Color(0xFF1E3A5F)),
                            const SizedBox(width: 8),
                            _kartuKpi('Online', '$jumlahOnline', const Color(0xFF0284C7)),
                            const SizedBox(width: 8),
                            _kartuKpi('Tertahan', '$jumlahTertahan', const Color(0xFFB8860B)),
                            const SizedBox(width: 8),
                            _kartuKpi('Nilai Menunggu', _formatRupiah.format(nilaiMenunggu), const Color(0xFFC0563D)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Semua'),
                            selected: _filter == _Filter.semua,
                            onSelected: (_) => setState(() => _filter = _Filter.semua),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Online'),
                            selected: _filter == _Filter.online,
                            onSelected: (_) => setState(() => _filter = _Filter.online),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Tertahan'),
                            selected: _filter == _Filter.tertahan,
                            onSelected: (_) => setState(() => _filter = _Filter.tertahan),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_tersaring.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('Tidak ada pesanan.')),
                        )
                      else
                        ..._tersaring.map((p) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(p.kode, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(p.pemesan.isEmpty ? '(Tanpa member)' : p.pemesan),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_formatRupiah.format(p.totalBiaya), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text(p.dariPembeliOnline ? 'Online' : 'Tertahan',
                                        style: TextStyle(fontSize: 11, color: p.dariPembeliOnline ? const Color(0xFF0284C7) : const Color(0xFFB8860B))),
                                  ],
                                ),
                                onTap: () => _lihatDetail(p),
                                onLongPress: () => _tampilkanAksi(p),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _kartuKpi(String label, String nilai, Color warna) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warna.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(nilai, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: warna)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  Future<void> _tampilkanAksi(Pesanan p) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.info_outline), title: const Text('Detail'), onTap: () {
              Navigator.of(context).pop();
              _lihatDetail(p);
            }),
            if (p.dariPembeliOnline)
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
                title: const Text('Verifikasi & Selesaikan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _verifikasiDanSelesaikan(p);
                },
              ),
            if (!p.dariPembeliOnline)
              ListTile(
                leading: const Icon(Icons.shopping_cart_checkout),
                title: const Text('Muat ke Keranjang'),
                onTap: () {
                  Navigator.of(context).pop();
                  _muatKeKeranjang(p);
                },
              ),
            if (Sesi.instance.bolehKelola)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Batalkan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _batalkan(p);
                },
              ),
          ],
        ),
      ),
    );
  }
}
