import 'package:core_db/core_db.dart';
import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

final _formatAngka = NumberFormat.decimalPattern('id_ID');

/// Layar Stok Opname (padanan stokopname.html/stokopname-renderer.js Electron)
/// -- 3 sub-tab: Kartu Mutasi Stok (dasbor), Input Opname (satu produk per
/// simpan), SO by Scan (antrean batch -- scan banyak produk berturut-turut,
/// baru disimpan SEMUA sekaligus lewat tombol "Simpan Semua", padanan mode
/// cepat versi Electron utk opname banyak barang tanpa menunggu round-trip
/// server tiap satu scan). Beda dari Electron: kamera di sini NATIVE
/// (mobile_scanner/MLKit lewat core_hw.BarcodeScannerScreen), bukan
/// Html5Qrcode berbasis web -- pengalaman scan harusnya lebih responsif.
class StokOpnameScreen extends StatefulWidget {
  const StokOpnameScreen({super.key});

  @override
  State<StokOpnameScreen> createState() => _StokOpnameScreenState();
}

class _StokOpnameScreenState extends State<StokOpnameScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.stokOpname,
      judul: 'Stok Opname',
      subjudul: 'Kartu mutasi stok & input hasil hitung fisik',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Kartu Mutasi Stok'),
              Tab(text: 'Input Opname'),
              Tab(text: 'SO by Scan'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              _TabMutasiStok(),
              _TabInputOpname(),
              _TabSoByScan(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TabMutasiStok extends StatefulWidget {
  const _TabMutasiStok();

  @override
  State<_TabMutasiStok> createState() => _TabMutasiStokState();
}

class _TabMutasiStokState extends State<_TabMutasiStok> {
  bool _memuat = true;
  String? _pesanError;
  Map<String, dynamic>? _dasbor;
  Map<String, dynamic>? _ringkasanHariIni;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.aksi('stok_dashboard', {'periode': 'month'}),
        ApiClient.instance.aksi('so_ringkasan'),
      ]);
      setStateIfMounted(() {
        _dasbor = results[0];
        _ringkasanHariIni = results[1];
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_pesanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_pesanError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    final d = _dasbor!;
    final r = _ringkasanHariIni!;
    final top5 = (d['top5Keluar'] as List?) ?? [];
    final maksTop5 = top5.isEmpty
        ? 1.0
        : top5
            .map((e) => (e['qty'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: [
              _kartu('Barang Masuk', _formatAngka.format(d['barangMasuk'] ?? 0),
                  const Color(0xFF2E7D32)),
              _kartu(
                  'Barang Keluar',
                  _formatAngka.format(d['barangKeluar'] ?? 0),
                  const Color(0xFFC0563D)),
              _kartu('Total Stok', _formatAngka.format(d['totalStok'] ?? 0),
                  const Color(0xFF1E3A5F)),
              _kartu(
                  'Stok Kritis (<10)', '${d['stokKritis'] ?? 0}', Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Progres Opname Hari Ini',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                      '${r['jumlahProduk'] ?? 0} produk dicatat (${r['jumlahCatatan'] ?? 0} kali)'),
                  Text(
                      'Selisih bersih: ${_formatAngka.format(r['selisihBersih'] ?? 0)} unit'),
                  Text(
                      'Lebih: +${_formatAngka.format(r['totalLebih'] ?? 0)} · Kurang: -${_formatAngka.format(r['totalKurang'] ?? 0)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (top5.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Top 5 Barang Keluar',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    ...top5.map((e) {
                      final qty = (e['qty'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e['nama']} (${_formatAngka.format(qty)})',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 2),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: qty / maksTop5,
                                minHeight: 8,
                                backgroundColor: AppColors.borderOf(context),
                                color: const Color(0xFF1E3A5F),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kartu(String label, String nilai, Color warna) {
    return Container(
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
          Text(nilai,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: warna)),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ),
    );
  }
}

/// Kotak cari produk bergaya "Banbox" (padanan picker `AmbilData...Banbox`
/// versi ZK/JSP: ketik sebagian kata -> daftar saran tampil di bawah kotak,
/// klik salah satu utk memilih) -- gap-closure: sebelumnya kotak pencarian
/// Stok Opname HANYA menerima kode/barcode PERSIS (cocok utk hasil scan,
/// tapi kasir yang mengetik manual tanpa tahu kode persis harus buka layar
/// Produk dulu). Saran dicari dari cache produk lokal (offline-first, sumber
/// sama dgn katalog Kasir) supaya responsif tanpa round-trip server tiap
/// ketukan; produk yang BENAR-BENAR dipilih tetap dikirim ke [onPilih] sbg
/// kode -- pemanggil (existing `_cariProduk`/`_tambahKeAntrean`) tetap
/// memverifikasi ulang ke server lewat `so_produk_scan`, jadi stok yang
/// ditampilkan selalu data terkini, bukan cache.
///
/// Enter-langsung (jalur scanner fisik: keystroke kode lalu Enter) SENGAJA
/// tidak lewat mekanisme seleksi bawaan `RawAutocomplete` -- disambungkan
/// LANGSUNG ke [onPilih] apa pun isi teksnya, supaya alur scan yang sudah
/// berfungsi TIDAK berubah sama sekali; dropdown saran murni tambahan utk
/// pencarian manual by nama.
class _PencarianProdukBanbox extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool aktif;
  final ValueChanged<String> onPilih;
  const _PencarianProdukBanbox({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onPilih,
    this.aktif = true,
  });

  @override
  State<_PencarianProdukBanbox> createState() =>
      _PencarianProdukBanboxState();
}

class _PencarianProdukBanboxState extends State<_PencarianProdukBanbox> {
  List<Map<String, Object?>> _semuaProduk = [];

  @override
  void initState() {
    super.initState();
    _muatCache();
  }

  Future<void> _muatCache() async {
    try {
      final data = await CoreDb.instance.produkCache();
      if (mounted) setStateIfMounted(() => _semuaProduk = data);
    } catch (_) {
      // Pencarian nama sekadar pelengkap -- kalau cache lokal gagal dimuat,
      // kotak tetap berfungsi spt biasa (ketik/scan kode persis + Enter).
    }
  }

  Iterable<Map<String, Object?>> _cariSaran(String kataKunci) {
    final q = kataKunci.trim().toLowerCase();
    if (q.isEmpty) return const Iterable<Map<String, Object?>>.empty();
    return _semuaProduk.where((p) {
      final nama = '${p['nama'] ?? ''}'.toLowerCase();
      final kode = '${p['kode'] ?? ''}'.toLowerCase();
      final barcode = '${p['barcode'] ?? ''}'.toLowerCase();
      return nama.contains(q) || kode.contains(q) || barcode.contains(q);
    }).take(15);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, Object?>>(
      textEditingController: widget.controller,
      focusNode: FocusNode(),
      optionsBuilder: (value) => _cariSaran(value.text),
      displayStringForOption: (p) => '${p['kode'] ?? p['barcode'] ?? ''}',
      onSelected: (p) {
        final kode = '${p['kode'] ?? p['barcode'] ?? ''}'.trim();
        if (kode.isNotEmpty) widget.onPilih(kode);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.aktif,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(widget.icon),
          ),
          // Enter = cari LANGSUNG apa pun teksnya (jalur scanner), bukan
          // menyeleksi opsi dropdown -- lihat JavaDoc kelas.
          onSubmitted: widget.onPilih,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final p = options.elementAt(i);
                  final barcode = '${p['barcode'] ?? ''}';
                  return ListTile(
                    dense: true,
                    title: Text('${p['nama'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(barcode.isEmpty
                        ? '${p['kode'] ?? ''}'
                        : '${p['kode'] ?? ''} · $barcode'),
                    onTap: () => onSelected(p),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabInputOpname extends StatefulWidget {
  const _TabInputOpname();

  @override
  State<_TabInputOpname> createState() => _TabInputOpnameState();
}

class _TabInputOpnameState extends State<_TabInputOpname> {
  final _barcodeController = TextEditingController();
  final _stokFisikController = TextEditingController();
  final _keteranganController = TextEditingController();
  bool _mencari = false;
  bool _menyimpan = false;
  String? _pesanError;
  Map<String, dynamic>? _produkDitemukan;
  List<Map<String, dynamic>> _riwayatHariIni = [];

  @override
  void initState() {
    super.initState();
    _muatRiwayat();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _stokFisikController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    try {
      final hasil = await ApiClient.instance.aksi('so_riwayat', {'limit': 30});
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setStateIfMounted(() => _riwayatHariIni = data);
    } catch (_) {
      // riwayat gagal dimuat bukan blocker utk input baru.
    }
  }

  Future<void> _cariProduk(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _pesanError = null;
      _produkDitemukan = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      setStateIfMounted(() {
        _produkDitemukan = hasil;
        _stokFisikController.text = '';
        _keteranganController.text = '';
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context,
        judul: 'Scan Barcode Produk');
    if (kode != null) {
      _barcodeController.text = kode;
      await _cariProduk(kode);
    }
  }

  Future<void> _simpanOpname() async {
    final p = _produkDitemukan;
    if (p == null) return;
    final stokFisik = double.tryParse(
        _stokFisikController.text.replaceAll(RegExp('[^0-9.]'), ''));
    if (stokFisik == null) {
      setStateIfMounted(() => _pesanError = 'Stok fisik wajib diisi angka.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('so_simpan', {
        'produk_id': p['produkId'],
        'stok_fisik': stokFisik,
        'keterangan': _keteranganController.text.trim(),
      });
      final selisih = (hasil['selisih'] as num?)?.toDouble() ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Tersimpan. Selisih: ${selisih > 0 ? "+" : ""}${_formatAngka.format(selisih)}'),
        ));
      }
      setStateIfMounted(() {
        _produkDitemukan = null;
        _barcodeController.clear();
        _stokFisikController.clear();
        _keteranganController.clear();
      });
      await _muatRiwayat();
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.warning),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Hanya admin/manager atau supervisor toko yang bisa mencatat hasil Stok Opname.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimaryOf(context)))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Riwayat Hari Ini',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_riwayatHariIni.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('Belum ada catatan hari ini.')))
          else
            ..._riwayatHariIni.map((k) {
              final selisih = (k['selisih'] as num?)?.toDouble() ?? 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text('${k['nama']}'),
                  subtitle: Text(
                      '${k['waktu']} · Sistem ${k['stokSistem']} → Fisik ${k['stokFisik']}'),
                  trailing: Text(
                    '${selisih > 0 ? "+" : ""}${_formatAngka.format(selisih)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selisih == 0
                            ? AppColors.textSecondaryOf(context)
                            : (selisih > 0 ? Colors.green : Colors.red)),
                  ),
                ),
              );
            }),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _PencarianProdukBanbox(
                controller: _barcodeController,
                label: 'Kode / Barcode / Nama Produk',
                icon: Icons.search,
                onPilih: _cariProduk,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _scanKamera,
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan pakai kamera',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_mencari) const Center(child: CircularProgressIndicator()),
        if (_pesanError != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Text(_pesanError!,
                style: TextStyle(color: Colors.red.shade700)),
          ),
        if (_produkDitemukan != null) ...[
          Card(
            color: AppColors.latarLembut(AppColors.warning),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_produkDitemukan!['nama'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Kode: ${_produkDitemukan!['kode'] ?? ''}'),
                  Text(
                      'Stok Sistem: ${_formatAngka.format(_produkDitemukan!['stokSistem'] ?? 0)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stokFisikController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Stok Fisik (hasil hitung) *',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keteranganController,
                    decoration: const InputDecoration(
                        labelText: 'Keterangan (opsional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _menyimpan ? null : _simpanOpname,
                      child: _menyimpan
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Simpan Hasil Opname'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text('Riwayat Hari Ini',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_riwayatHariIni.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Belum ada catatan hari ini.')))
        else
          ..._riwayatHariIni.map((k) {
            final selisih = (k['selisih'] as num?)?.toDouble() ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text('${k['nama']}'),
                subtitle: Text(
                    '${k['waktu']} · Sistem ${k['stokSistem']} → Fisik ${k['stokFisik']}'),
                trailing: Text(
                  '${selisih > 0 ? "+" : ""}${_formatAngka.format(selisih)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selisih == 0
                        ? AppColors.textSecondaryOf(context)
                        : (selisih > 0 ? Colors.green : Colors.red),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// "SO by Scan" -- antrean batch: tiap scan/entry kode HANYA ditambah ke
/// daftar lokal (`_antrean`), stok fisik diisi INLINE per baris, dan baru
/// dikirim ke server (satu panggilan `so_simpan` per baris, berurutan) saat
/// kasir menekan "Simpan Semua" -- padanan mode cepat versi Electron utk
/// menghitung banyak produk berturut-turut tanpa menunggu tiap simpan
/// selesai sebelum scan berikutnya (beda dari _TabInputOpname yg simpan
/// LANGSUNG per satu produk).
class _TabSoByScan extends StatefulWidget {
  const _TabSoByScan();

  @override
  State<_TabSoByScan> createState() => _TabSoByScanState();
}

class _AntreanSo {
  final Map<String, dynamic> produk;
  final TextEditingController stokFisik;
  final TextEditingController keterangan;
  String? statusKirim; // null=belum, 'ok', atau pesan error
  _AntreanSo(this.produk)
      : stokFisik = TextEditingController(),
        keterangan = TextEditingController();
}

class _TabSoByScanState extends State<_TabSoByScan> {
  final _barcodeController = TextEditingController();
  bool _mencari = false;
  bool _mengirim = false;
  String? _pesanError;
  final List<_AntreanSo> _antrean = [];

  @override
  void dispose() {
    _barcodeController.dispose();
    for (final a in _antrean) {
      a.stokFisik.dispose();
      a.keterangan.dispose();
    }
    super.dispose();
  }

  Future<void> _tambahKeAntrean(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _pesanError = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      if (_antrean.any((a) => a.produk['produkId'] == hasil['produkId'])) {
        setStateIfMounted(
            () => _pesanError = '${hasil['nama']} sudah ada di antrean.');
      } else {
        setStateIfMounted(() => _antrean.insert(0, _AntreanSo(hasil)));
      }
      _barcodeController.clear();
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context,
        judul: 'Scan Barcode Produk');
    if (kode != null) await _tambahKeAntrean(kode);
  }

  void _hapusDariAntrean(_AntreanSo a) {
    setStateIfMounted(() => _antrean.remove(a));
    a.stokFisik.dispose();
    a.keterangan.dispose();
  }

  Future<void> _simpanSemua() async {
    final belumDikirim = _antrean.where((a) => a.statusKirim != 'ok').toList();
    if (belumDikirim.isEmpty) return;
    setStateIfMounted(() => _mengirim = true);
    var berhasil = 0;
    for (final a in belumDikirim) {
      final stok =
          double.tryParse(a.stokFisik.text.replaceAll(RegExp('[^0-9.]'), ''));
      if (stok == null) {
        setStateIfMounted(() => a.statusKirim = 'Stok fisik wajib diisi');
        continue;
      }
      try {
        await ApiClient.instance.aksi('so_simpan', {
          'produk_id': a.produk['produkId'],
          'stok_fisik': stok,
          'keterangan': a.keterangan.text.trim(),
        });
        setStateIfMounted(() => a.statusKirim = 'ok');
        berhasil++;
      } catch (e) {
        setStateIfMounted(() => a.statusKirim = e.toString());
      }
    }
    setStateIfMounted(() => _mengirim = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('$berhasil dari ${belumDikirim.length} baris tersimpan.')));
      setStateIfMounted(
          () => _antrean.removeWhere((a) => a.statusKirim == 'ok'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Hanya admin/manager atau supervisor toko yang bisa mencatat hasil Stok Opname.',
          style: TextStyle(
              fontSize: 12, color: AppColors.textSecondaryOf(context)),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _PencarianProdukBanbox(
                  controller: _barcodeController,
                  label: 'Scan / Ketik Kode / Nama Produk',
                  icon: Icons.qr_code,
                  aktif: !_mencari,
                  onPilih: _tambahKeAntrean,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: _mencari ? null : _scanKamera,
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Scan pakai kamera'),
            ],
          ),
        ),
        if (_mencari) const LinearProgressIndicator(),
        if (_pesanError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_pesanError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        Expanded(
          child: _antrean.isEmpty
              ? const Center(
                  child: Text('Antrean kosong -- scan produk utk mulai.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _antrean.length,
                  itemBuilder: (context, i) {
                    final a = _antrean[i];
                    final sukses = a.statusKirim == 'ok';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: sukses ? Colors.green.shade50 : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${a.produk['nama']}  ·  Sistem ${_formatAngka.format(a.produk['stokSistem'] ?? 0)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ),
                                if (!sukses)
                                  IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => _hapusDariAntrean(a)),
                              ],
                            ),
                            if (a.statusKirim != null && !sukses)
                              Text(a.statusKirim!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 11)),
                            if (!sukses)
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: a.stokFisik,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText: 'Stok Fisik',
                                          isDense: true,
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: a.keterangan,
                                      decoration: const InputDecoration(
                                          labelText: 'Keterangan',
                                          isDense: true,
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_antrean.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _mengirim ? null : _simpanSemua,
                child: _mengirim
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Simpan Semua (${_antrean.length})'),
              ),
            ),
          ),
      ],
    );
  }
}
