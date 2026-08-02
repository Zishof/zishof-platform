import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../services/pesanan_poller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'keranjang_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

enum _Filter { semua, online, tertahan }

/// Layar Pesanan (padanan pesanan.html/pesanan-renderer.js Electron) --
/// gabungan 2 jenis draft (lihat JavaDoc [Pesanan]): Pesanan Online (dibuat
/// pembeli sendiri, diselesaikan lewat "Verifikasi & Selesaikan") dan
/// Keranjang Tertahan (ditahan kasir lewat tombol "Tahan" di Keranjang,
/// dilanjutkan lewat "Muat ke Keranjang" -- inilah bagian "resume" yang
/// disebut di task #181).
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

  // Filter tambahan -- padanan filter Mulai/Akhir/Kode/Pembeli/Pedagang di
  // JSP `_draft_pesanan_anggota.jsp`, server (`prosesPesananList` PosApi.java)
  // SUDAH mendukung semuanya sejak lama, hanya UI-nya yang belum dibangun.
  bool _hanyaBelumLunas = false;
  DateTime? _sejak;
  DateTime? _sampai;
  final _kodeController = TextEditingController();
  final _pembeliController = TextEditingController();
  final _pedagangController = TextEditingController();
  bool _filterTerbuka = false;

  @override
  void initState() {
    super.initState();
    _muat();
    PesananPoller.instance.tandaiSudahDilihat();
  }

  @override
  void dispose() {
    _kodeController.dispose();
    _pembeliController.dispose();
    _pedagangController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final payload = <String, dynamic>{'limit': 200};
      // BUG LAMA (fixed): sebelumnya `hanya_belum_lunas` selalu true, jadi
      // pesanan yang SUDAH lunas tak pernah ikut termuat sama sekali --
      // sekarang opsional lewat chip filter, default menampilkan semua.
      if (_hanyaBelumLunas) payload['hanya_belum_lunas'] = true;
      if (_sejak != null) payload['sejak'] = _formatTanggalIso(_sejak!);
      if (_sampai != null) payload['sampai'] = _formatTanggalIso(_sampai!);
      if (_kodeController.text.trim().isNotEmpty) payload['kode'] = _kodeController.text.trim();
      if (_pembeliController.text.trim().isNotEmpty) payload['pembeli'] = _pembeliController.text.trim();
      if (Sesi.instance.isAdmin && _pedagangController.text.trim().isNotEmpty) {
        payload['pedagang'] = _pedagangController.text.trim();
      }
      final hasil = await ApiClient.instance.aksi('pesanan_list', payload);
      final data = ((hasil['pesanan'] as List?) ?? []).map((e) => Pesanan.fromJson(e as Map<String, dynamic>)).toList();
      setState(() => _semua = data);
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  String _formatTanggalIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = (mulai ? _sejak : _sampai) ?? DateTime.now();
    final hasil = await showDatePicker(context: context, initialDate: awal, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (hasil == null) return;
    setState(() => mulai ? _sejak = hasil : _sampai = hasil);
  }

  Future<void> _hitungUlang(Pesanan p) async {
    try {
      final hasil = await ApiClient.instance.aksi('pesanan_hitung_ulang', {'draft_id': p.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hasil['description']?.toString() ?? '${p.kode}: dihitung ulang.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// "Bayar Semua" massal -- TIDAK ADA aksi batch di server, jadi cukup
  /// panggil ulang [_verifikasiDanSelesaikan] (aksi `bayar` yg SUDAH ADA)
  /// satu per satu utk tiap pesanan online yang masih belum lunas, dgn SATU
  /// metode pembayaran yang dipilih di depan -- sama seperti kasir memproses
  /// banyak pesanan manual berturut-turut, hanya diotomatisasi.
  Future<void> _bayarSemua() async {
    final belumLunas = _tersaring.where((p) => p.dariPembeliOnline).toList();
    if (belumLunas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada pesanan online yang perlu dibayar.')));
      return;
    }
    final caraBayar = await showDialog<CaraBayar>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Bayar Semua (${belumLunas.length} pesanan) -- Pilih Metode'),
        children: Sesi.instance.caraBayar
            .map((c) => SimpleDialogOption(onPressed: () => Navigator.of(context).pop(c), child: Text(c.nama)))
            .toList(),
      ),
    );
    if (caraBayar == null) return;

    var berhasil = 0;
    for (final p in belumLunas) {
      try {
        await ApiClient.instance.aksi('bayar', _payloadVerifikasi(p, caraBayar));
        berhasil++;
      } catch (_) {
        // Satu pesanan gagal (mis. stok berubah) -- lanjut ke berikutnya, jangan hentikan seluruh proses.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$berhasil dari ${belumLunas.length} pesanan berhasil dibayar.')));
    }
    await _muat();
  }

  Map<String, dynamic> _payloadVerifikasi(Pesanan p, CaraBayar caraBayar) => {
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
      };

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
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
          // Keranjang Tertahan (draft lokal, BUKAN pesanan online) -- gap-closure:
          // sebelumnya dialog ini murni tampilan, satu-satunya jalan lanjut
          // (Muat ke Keranjang) tersembunyi di menu tekan-tahan yang tak lazim
          // dipakai mouse desktop. Tombol ini langsung ke KeranjangScreen sama
          // seperti _tampilkanAksi, bukan alur baru.
          if (!p.dariPembeliOnline)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _muatKeKeranjang(p);
              },
              icon: const Icon(Icons.shopping_cart_checkout, size: 18),
              label: const Text('Muat ke Keranjang'),
            ),
          if (p.dariPembeliOnline)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _verifikasiDanSelesaikan(p);
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Verifikasi & Selesaikan'),
            ),
          if (Sesi.instance.bolehKelola)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _batalkan(p);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Batalkan'),
            ),
        ],
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
      await ApiClient.instance.aksi('bayar', _payloadVerifikasi(p, caraBayar));
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
    final alasanController = TextEditingController();
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Pesanan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.kode} akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.'),
            const SizedBox(height: 12),
            TextField(
              controller: alasanController,
              decoration: const InputDecoration(labelText: 'Alasan Pembatalan *', border: OutlineInputBorder()),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final alasan = alasanController.text.trim();
    if (alasan.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      return;
    }
    try {
      await ApiClient.instance.aksi('batal_pesanan', {'id': p.id, 'alasan': alasan});
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

    return AppShell(
      menuAktif: MenuEBisnis.pesanan,
      judul: 'Pesanan',
      subjudul: 'Pesanan online & transaksi yang ditahan',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: Icon(_filterTerbuka ? Icons.filter_alt : Icons.filter_alt_outlined), onPressed: () => setState(() => _filterTerbuka = !_filterTerbuka), tooltip: 'Filter'),
        if (Sesi.instance.bolehKelola) IconButton(icon: const Icon(Icons.playlist_add_check), onPressed: _bayarSemua, tooltip: 'Bayar Semua'),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: Icon(_filterTerbuka ? Icons.filter_alt : Icons.filter_alt_outlined), onPressed: () => setState(() => _filterTerbuka = !_filterTerbuka), tooltip: 'Filter'),
        if (Sesi.instance.bolehKelola) IconButton(icon: const Icon(Icons.playlist_add_check), onPressed: _bayarSemua, tooltip: 'Bayar Semua'),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      ]),
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
                            _kartuKpi(Icons.receipt_long_outlined, 'Total', '${semua.length}', const Color(0xFF1E3A5F)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.public, 'Online', '$jumlahOnline', const Color(0xFF0284C7)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.pause_circle_outline, 'Tertahan', '$jumlahTertahan', const Color(0xFFB8860B)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.hourglass_empty, 'Nilai Menunggu', _formatRupiah.format(nilaiMenunggu), const Color(0xFFC0563D)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_filterTerbuka) ...[
                        AppSectionCard(
                          judul: 'Filter Pesanan',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _pilihTanggal(mulai: true),
                                      icon: const Icon(Icons.date_range, size: 16),
                                      label: Text(_sejak == null ? 'Sejak Tanggal' : _formatTanggalIso(_sejak!), style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _pilihTanggal(mulai: false),
                                      icon: const Icon(Icons.date_range, size: 16),
                                      label: Text(_sampai == null ? 'Sampai Tanggal' : _formatTanggalIso(_sampai!), style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: TextField(controller: _kodeController, decoration: const InputDecoration(labelText: 'Kode', isDense: true, border: OutlineInputBorder())),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: TextField(controller: _pembeliController, decoration: const InputDecoration(labelText: 'Nama Pembeli', isDense: true, border: OutlineInputBorder())),
                                  ),
                                  if (Sesi.instance.isAdmin)
                                    SizedBox(
                                      width: 200,
                                      child: TextField(controller: _pedagangController, decoration: const InputDecoration(labelText: 'Toko/Pedagang', isDense: true, border: OutlineInputBorder())),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FilterChip(
                                    label: const Text('Hanya Belum Lunas'),
                                    selected: _hanyaBelumLunas,
                                    onSelected: (v) => setState(() => _hanyaBelumLunas = v),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _sejak = null;
                                        _sampai = null;
                                        _hanyaBelumLunas = false;
                                        _kodeController.clear();
                                        _pembeliController.clear();
                                        _pedagangController.clear();
                                      });
                                      _muat();
                                    },
                                    child: const Text('Reset'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(onPressed: _muat, child: const Text('Terapkan')),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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

  Widget _kartuKpi(IconData icon, String label, String nilai, Color warna) {
    return SizedBox(width: 140, child: AppKpiCard(icon: icon, warna: warna, nilai: nilai, label: label));
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
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Hitung Ulang'),
                onTap: () {
                  Navigator.of(context).pop();
                  _hitungUlang(p);
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
