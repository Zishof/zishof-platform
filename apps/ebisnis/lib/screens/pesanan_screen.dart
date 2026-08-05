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
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

enum _Filter { semua, online, tertahan }

const _tinggiKartuKpiPesanan = 96.0;
const _pageSizePesanan = 20;

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
  int _halamanPesanan = 1;

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
    setStateIfMounted(() {
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
      if (_kodeController.text.trim().isNotEmpty) {
        payload['kode'] = _kodeController.text.trim();
      }
      if (_pembeliController.text.trim().isNotEmpty) {
        payload['pembeli'] = _pembeliController.text.trim();
      }
      if (Sesi.instance.isAdmin && _pedagangController.text.trim().isNotEmpty) {
        payload['pedagang'] = _pedagangController.text.trim();
      }
      final hasil = await ApiClient.instance.aksi('pesanan_list', payload);
      final data = ((hasil['pesanan'] as List?) ?? [])
          .map((e) => Pesanan.fromJson(e as Map<String, dynamic>))
          .toList();
      setStateIfMounted(() {
        _semua = data;
        _halamanPesanan = 1;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  String _formatTanggalIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = (mulai ? _sejak : _sampai) ?? DateTime.now();
    final hasil = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (hasil == null) return;
    setStateIfMounted(() {
      if (mulai) {
        _sejak = hasil;
      } else {
        _sampai = hasil;
      }
      _halamanPesanan = 1;
    });
  }

  Future<void> _hitungUlang(Pesanan p) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('pesanan_hitung_ulang', {'draft_id': p.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(hasil['description']?.toString() ??
                '${p.kode}: dihitung ulang.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada pesanan online yang perlu dibayar.')));
      return;
    }
    final caraBayar = await showDialog<CaraBayar>(
      context: context,
      builder: (_) => SimpleDialog(
        title:
            Text('Bayar Semua (${belumLunas.length} pesanan) -- Pilih Metode'),
        children: Sesi.instance.caraBayar
            .map((c) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(c),
                child: Text(c.nama)))
            .toList(),
      ),
    );
    if (caraBayar == null) return;

    var berhasil = 0;
    for (final p in belumLunas) {
      try {
        await ApiClient.instance
            .aksi('bayar', _payloadVerifikasi(p, caraBayar));
        berhasil++;
      } catch (_) {
        // Satu pesanan gagal (mis. stok berubah) -- lanjut ke berikutnya, jangan hentikan seluruh proses.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$berhasil dari ${belumLunas.length} pesanan berhasil dibayar.')));
    }
    await _muat();
  }

  Map<String, dynamic> _payloadVerifikasi(Pesanan p, CaraBayar caraBayar) => {
        'kodeUnik': '${p.kode}-VERIF-${DateTime.now().millisecondsSinceEpoch}',
        'clientTrxId':
            '${p.kode}-VERIF-${DateTime.now().millisecondsSinceEpoch}',
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
          width: 820,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ringkasanDetailPesanan(p),
                  const SizedBox(height: 12),
                  _tabelDetailPesanan(p),
                  const SizedBox(height: 12),
                  _totalDetailPesanan(p),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup')),
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
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Batalkan'),
            ),
        ],
      ),
    );
  }

  Widget _ringkasanDetailPesanan(Pesanan p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chipDetail(Icons.person_outline,
            'Pemesan: ${p.pemesan.isEmpty ? "-" : p.pemesan}'),
        if (p.namaMesin != null)
          _chipDetail(Icons.devices_outlined, 'Mesin: ${p.namaMesin}'),
        if (p.kasirLoginNama.isNotEmpty)
          _chipDetail(Icons.badge_outlined, 'Kasir: ${p.kasirLoginNama}'),
        _chipDetail(
          p.dariPembeliOnline ? Icons.public : Icons.pause_circle_outline,
          p.dariPembeliOnline ? 'Pesanan Online' : 'Keranjang Tertahan',
        ),
      ],
    );
  }

  Widget _chipDetail(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelDetailPesanan(Pesanan p) {
    String formatJumlah(double jumlah) =>
        jumlah.toStringAsFixed(jumlah == jumlah.roundToDouble() ? 0 : 2);

    return AppDataTable(
      minWidth: 760,
      emptyText: 'Tidak ada item pesanan.',
      columns: const [
        AppTableColumn('Produk', flex: 4),
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Qty', width: 72, align: TextAlign.center),
        AppTableColumn('Harga', flex: 2, align: TextAlign.right),
        AppTableColumn('Diskon', flex: 2, align: TextAlign.right),
        AppTableColumn('Subtotal', flex: 2, align: TextAlign.right),
      ],
      rows: p.items.map((item) {
        final subtotal = item.harga * item.jumlah - item.diskon;
        return AppTableRowData(cells: [
          AppTableCell.text(
            item.nama,
            flex: 4,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          AppTableCell.text(
            item.kode.isEmpty ? '-' : item.kode,
            flex: 2,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
              fontFamily: 'monospace',
            ),
          ),
          AppTableCell.text(
            formatJumlah(item.jumlah),
            width: 72,
            align: TextAlign.center,
          ),
          AppTableCell.text(
            _formatRupiah.format(item.harga),
            flex: 2,
            align: TextAlign.right,
          ),
          AppTableCell.text(
            item.diskon <= 0 ? '-' : _formatRupiah.format(item.diskon),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              color: item.diskon <= 0
                  ? AppColors.textSecondaryOf(context)
                  : AppColors.warning,
            ),
          ),
          AppTableCell.text(
            _formatRupiah.format(subtotal),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ]);
      }).toList(),
    );
  }

  Widget _totalDetailPesanan(Pesanan p) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AppSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.totalDiskon > 0)
                _barisTotalDetail(
                    'Diskon', '-${_formatRupiah.format(p.totalDiskon)}',
                    warna: AppColors.warning),
              if (p.totalCashback > 0)
                _barisTotalDetail(
                    'Cashback', '+${_formatRupiah.format(p.totalCashback)}',
                    warna: AppColors.success),
              _barisTotalDetail(
                'Total',
                _formatRupiah.format(p.totalBiaya),
                tebal: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barisTotalDetail(
    String label,
    String nilai, {
    bool tebal = false,
    Color? warna,
  }) {
    final gaya = TextStyle(
      fontSize: tebal ? 16 : 12.5,
      fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
      color: warna ?? AppColors.textPrimaryOf(context),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: gaya),
          Text(nilai, style: gaya),
        ],
      ),
    );
  }

  Future<void> _muatKeKeranjang(Pesanan p) async {
    Anggota? member;
    if (p.anggotaId != null) {
      try {
        final hasil =
            await ApiClient.instance.aksi('cari_member', {'id': p.anggotaId});
        final arr = (hasil['member'] as List?) ?? [];
        if (arr.isNotEmpty) {
          member = Anggota.fromJson(arr.first as Map<String, dynamic>);
        }
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
      builder: (_) => KeranjangScreen(
          keranjang: keranjang, draftIdSumber: p.id, memberAwal: member),
    ));
    await _muat();
  }

  Future<void> _verifikasiDanSelesaikan(Pesanan p) async {
    final caraBayar = await showDialog<CaraBayar>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pilih Metode Pembayaran'),
        children: Sesi.instance.caraBayar
            .map((c) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(c),
                child: Text(c.nama)))
            .toList(),
      ),
    );
    if (caraBayar == null) return;

    try {
      await ApiClient.instance.aksi('bayar', _payloadVerifikasi(p, caraBayar));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${p.kode} berhasil diselesaikan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
            Text(
                '${p.kode} akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.'),
            const SizedBox(height: 12),
            TextField(
              controller: alasanController,
              decoration: const InputDecoration(
                  labelText: 'Alasan Pembatalan *',
                  border: OutlineInputBorder()),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final alasan = alasanController.text.trim();
    if (alasan.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      }
      return;
    }
    try {
      await ApiClient.instance
          .aksi('batal_pesanan', {'id': p.id, 'alasan': alasan});
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final semua = _semua;
    final pesananTersaring = _tersaring;
    final totalHalamanPesanan = (pesananTersaring.length / _pageSizePesanan)
        .ceil()
        .clamp(1, 999999)
        .toInt();
    final halamanPesanan =
        _halamanPesanan.clamp(1, totalHalamanPesanan).toInt();
    final awalPesanan = (halamanPesanan - 1) * _pageSizePesanan;
    final pesananHalamanIni =
        pesananTersaring.skip(awalPesanan).take(_pageSizePesanan).toList();
    final jumlahOnline = semua.where((p) => p.dariPembeliOnline).length;
    final jumlahTertahan = semua.length - jumlahOnline;
    final nilaiMenunggu = semua.fold<double>(0, (s, p) => s + p.totalBiaya);
    final tombolAksi = [
      HeaderActionButton(
        icon: _filterTerbuka ? Icons.filter_alt : Icons.filter_alt_outlined,
        label: 'Filter',
        onPressed: () =>
            setStateIfMounted(() => _filterTerbuka = !_filterTerbuka),
      ),
      if (Sesi.instance.bolehKelola)
        HeaderActionButton(
          icon: Icons.playlist_add_check,
          label: 'Bayar Semua',
          onPressed: _bayarSemua,
        ),
      HeaderActionButton(
        icon: Icons.refresh,
        label: 'Muat Ulang',
        onPressed: _muat,
      ),
    ];

    return AppShell(
      menuAktif: MenuEBisnis.pesanan,
      judul: 'Pesanan',
      subjudul: 'Pesanan online & transaksi yang ditahan',
      scrollable: false,
      actionsAppBar: tombolAksi,
      aksiHeader: Wrap(
        alignment: WrapAlignment.end,
        runSpacing: 8,
        children: tombolAksi,
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
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _muat, child: const Text('Coba Lagi')),
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
                        height: _tinggiKartuKpiPesanan,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _kartuKpi(Icons.receipt_long_outlined, 'Total',
                                '${semua.length}', const Color(0xFF1E3A5F)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.public, 'Online', '$jumlahOnline',
                                const Color(0xFF0284C7)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.pause_circle_outline, 'Tertahan',
                                '$jumlahTertahan', const Color(0xFFB8860B)),
                            const SizedBox(width: 8),
                            _kartuKpi(
                                Icons.hourglass_empty,
                                'Nilai Menunggu',
                                _formatRupiah.format(nilaiMenunggu),
                                const Color(0xFFC0563D)),
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
                                      onPressed: () =>
                                          _pilihTanggal(mulai: true),
                                      icon: const Icon(Icons.date_range,
                                          size: 16),
                                      label: Text(
                                          _sejak == null
                                              ? 'Sejak Tanggal'
                                              : _formatTanggalIso(_sejak!),
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _pilihTanggal(mulai: false),
                                      icon: const Icon(Icons.date_range,
                                          size: 16),
                                      label: Text(
                                          _sampai == null
                                              ? 'Sampai Tanggal'
                                              : _formatTanggalIso(_sampai!),
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: TextField(
                                        controller: _kodeController,
                                        decoration: const InputDecoration(
                                            labelText: 'Kode',
                                            isDense: true,
                                            border: OutlineInputBorder())),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: TextField(
                                        controller: _pembeliController,
                                        decoration: const InputDecoration(
                                            labelText: 'Nama Pembeli',
                                            isDense: true,
                                            border: OutlineInputBorder())),
                                  ),
                                  if (Sesi.instance.isAdmin)
                                    SizedBox(
                                      width: 200,
                                      child: TextField(
                                          controller: _pedagangController,
                                          decoration: const InputDecoration(
                                              labelText: 'Toko/Pedagang',
                                              isDense: true,
                                              border: OutlineInputBorder())),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FilterChip(
                                    label: const Text('Hanya Belum Lunas'),
                                    selected: _hanyaBelumLunas,
                                    onSelected: (v) => setStateIfMounted(() {
                                      _hanyaBelumLunas = v;
                                      _halamanPesanan = 1;
                                    }),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      setStateIfMounted(() {
                                        _sejak = null;
                                        _sampai = null;
                                        _hanyaBelumLunas = false;
                                        _halamanPesanan = 1;
                                        _kodeController.clear();
                                        _pembeliController.clear();
                                        _pedagangController.clear();
                                      });
                                      _muat();
                                    },
                                    child: const Text('Reset'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                      onPressed: _muat,
                                      child: const Text('Terapkan')),
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
                            onSelected: (_) => setStateIfMounted(() {
                              _filter = _Filter.semua;
                              _halamanPesanan = 1;
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Online'),
                            selected: _filter == _Filter.online,
                            onSelected: (_) => setStateIfMounted(() {
                              _filter = _Filter.online;
                              _halamanPesanan = 1;
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Tertahan'),
                            selected: _filter == _Filter.tertahan,
                            onSelected: (_) => setStateIfMounted(() {
                              _filter = _Filter.tertahan;
                              _halamanPesanan = 1;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppDataTable(
                        minWidth: 960,
                        emptyText: 'Tidak ada pesanan.',
                        columns: const [
                          AppTableColumn('Kode', flex: 2),
                          AppTableColumn('Pemesan', flex: 3),
                          AppTableColumn('Tipe',
                              flex: 2, align: TextAlign.center),
                          AppTableColumn('Item', flex: 4),
                          AppTableColumn('Total',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Aksi',
                              width: 96, align: TextAlign.center),
                        ],
                        rows: pesananHalamanIni.map((p) {
                          final warnaStatus = p.dariPembeliOnline
                              ? const Color(0xFF0284C7)
                              : const Color(0xFFB8860B);
                          final ringkasanItem = p.items.isEmpty
                              ? '-'
                              : p.items.take(3).map((item) {
                                  final jumlah = item.jumlah.toStringAsFixed(
                                      item.jumlah == item.jumlah.roundToDouble()
                                          ? 0
                                          : 2);
                                  return '${item.nama} x$jumlah';
                                }).join(', ');
                          final sisaItem = p.items.length > 3
                              ? ' +${p.items.length - 3} item'
                              : '';

                          return AppTableRowData(
                            onTap: () => _lihatDetail(p),
                            cells: [
                              AppTableCell.text(
                                p.kode,
                                flex: 2,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              AppTableCell.text(
                                p.pemesan.isEmpty
                                    ? '(Tanpa member)'
                                    : p.pemesan,
                                flex: 3,
                              ),
                              AppTableCell(
                                flex: 2,
                                align: TextAlign.center,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: StatusPill(
                                    label: p.dariPembeliOnline
                                        ? 'Online'
                                        : 'Tertahan',
                                    warna: warnaStatus,
                                  ),
                                ),
                              ),
                              AppTableCell.text(
                                '$ringkasanItem$sisaItem',
                                flex: 4,
                                maxLines: 2,
                              ),
                              AppTableCell.text(
                                _formatRupiah.format(p.totalBiaya),
                                flex: 2,
                                align: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              AppTableCell(
                                width: 96,
                                align: TextAlign.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Detail',
                                      icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 20),
                                      onPressed: () => _lihatDetail(p),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Aksi',
                                      icon: const Icon(Icons.more_horiz,
                                          size: 20),
                                      onPressed: () => _tampilkanAksi(p),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                        pagination: AppTablePagination(
                          halaman: halamanPesanan,
                          totalHalaman: totalHalamanPesanan,
                          totalData: pesananTersaring.length,
                          labelData: 'pesanan',
                          onSebelumnya: halamanPesanan > 1
                              ? () => setStateIfMounted(
                                  () => _halamanPesanan = halamanPesanan - 1)
                              : null,
                          onBerikutnya: halamanPesanan < totalHalamanPesanan
                              ? () => setStateIfMounted(
                                  () => _halamanPesanan = halamanPesanan + 1)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _kartuKpi(IconData icon, String label, String nilai, Color warna) {
    return SizedBox(
        width: 140,
        height: _tinggiKartuKpiPesanan,
        child:
            AppKpiCard(icon: icon, warna: warna, nilai: nilai, label: label));
  }

  Future<void> _tampilkanAksi(Pesanan p) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Detail'),
                onTap: () {
                  Navigator.of(context).pop();
                  _lihatDetail(p);
                }),
            if (p.dariPembeliOnline)
              ListTile(
                leading: const Icon(Icons.check_circle_outline,
                    color: Color(0xFF2E7D32)),
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
