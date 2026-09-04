import 'package:flutter/material.dart';

import 'kode_akun_screen.dart';
import 'posting_akun_perbaikan.dart';
import 'posting_toko_dialog.dart';
import 'siklus_akuntansi_screen.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/kilau_perubahan.dart';
import 'laporan_detail_screen.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';

/// Katalog ~150 laporan (32 kategori) -- padanan `laporan.html`/`laporan-renderer.js`
/// Electron & `laporan_laporan.jsp`. Metadata katalog (`laporan_katalog`) SEPENUHNYA
/// data-driven (id/judul/ket/produk?/pelanggan?/perToko?/url?), jadi layar ini
/// generik utk semua laporan -- TIDAK ada kode khusus per-laporan (lihat JavaDoc
/// LaporanKatalogData di server). ~13 item punya `url` (laporan akuntansi resmi
/// ZK/JRXML) -- ini dibuka EKSTERNAL via browser, bukan lewat alur jalankan/PDF
/// generik, karena bukan bagian dari kontrak kolom/baris yang sama.
class LaporanScreen extends StatefulWidget {
  /// Aksi server sumber katalog: `laporan_katalog` (semua) atau
  /// `laporan_keuangan_katalog` (subset keuangan). Membuat layar ini bisa dipakai
  /// ulang untuk menu "Laporan Keuangan" tanpa menduplikasi logika render/run.
  final String aksiKatalog;
  final MenuEBisnis menuAktif;
  final String judul;
  final String subjudul;

  /// Id layar pendukung yang tabnya langsung terbuka saat layar tampil (mis.
  /// 'posting_hpp', 'posting_kulakan'). Dipakai submenu grup "Akuntansi" supaya
  /// tiap menu mendarat di bagiannya tanpa menduplikasi panelnya jadi layar
  /// tersendiri. Id yang tidak ada pada katalog server diabaikan (tab katalog).
  final String? bukaPosting;
  const LaporanScreen({
    super.key,
    this.aksiKatalog = 'laporan_katalog',
    this.menuAktif = MenuEBisnis.laporanLaporan,
    this.judul = 'Laporan-Laporan',
    this.subjudul = 'Katalog laporan siap pakai',
    this.bukaPosting,
  });

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _kategori = [];

  /// Daftar unit usaha + unit bawaan dari respons katalog; diteruskan ke layar
  /// detail supaya laporan berbasis jurnal bisa dipilih per unit atau
  /// dikonsolidasi. Hanya ikut pada respons SERVER (sama seperti 'pendukung').
  List<Map<String, dynamic>> _satuanKerja = [];
  int _satuanKerjaDefault = 0;
  List<Map<String, dynamic>> _pendukung = [];
  final _controllerCari = TextEditingController();
  String _kategoriDipilih = '';
  int _halaman = 1;
  static const int _pageSize = 15;

  /// Diff emisi "baca lokal dulu" -- menggerakkan kilau baris katalog.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    _muat();
    // Submenu Akuntansi > Posting HPP / Posting Penjualan langsung mendarat di
    // tabnya (lihat _katalogBertab), tidak lagi membuka dialog melayang.
  }

  @override
  void dispose() {
    _controllerCari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): katalog yang pernah
      // dibuka tetap bisa dilihat saat OFFLINE -- isinya metadata laporan
      // (judul/keterangan/flag filter), bukan angka yang bisa basi. Kunci cache
      // dipisah per aksi katalog karena `laporan_keuangan_katalog` hanya subset
      // keuangan; identitas baris = nama kategori ('kat'), server tidak
      // mengirim kolom 'id'.
      await MasterOffline.daftarCacheDulu(
        widget.aksiKatalog,
        const {},
        'master:laporan_katalog:${widget.aksiKatalog}',
        fieldData: 'kategori',
        kolomKunci: 'kat',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _kategori = _diff.terapkan(hasil, fieldData: 'kategori');
            // 'pendukung' hanya ikut pada respons SERVER (emisi lokal cuma
            // memuat daftar kategori) -- jangan dikosongkan oleh emisi lokal.
            if (_diff.dariServer) {
              _pendukung = ((hasil['pendukung'] as List?) ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              _satuanKerja = ((hasil['satuanKerja'] as List?) ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              _satuanKerjaDefault =
                  (hasil['satuanKerjaDefault'] as num?)?.toInt() ?? 0;
            }
            if (_kategoriDipilih.isNotEmpty &&
                !_kategori.any(
                    (e) => (e['kat'] as String? ?? '') == _kategoriDipilih)) {
              _kategoriDipilih = '';
            }
            _halaman = 1;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaItem(Map<String, dynamic> item) async {
    final url = item['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final origin = Uri.parse(ApiClient.baseUrl).origin;
      final uri = Uri.parse('$origin$url');
      final berhasil =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!berhasil && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Tidak bisa membuka $uri')));
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LaporanDetailScreen(
              item: item,
              satuanKerja: _satuanKerja,
              satuanKerjaDefault: _satuanKerjaDefault,
            )));
  }

  Future<void> _bukaPendukungInline(Map<String, dynamic> item) async {
    final id = item['id'] as String? ?? '';
    if (id == 'akun_perkiraan') {
      // Konfigurasi Kode Akun kini dibuka NATIF di Desktop/Android (4 tab: Akun,
      // Daftar Akun, Bank, Jenis Transaksi + unduh/unggah Excel), bukan lagi
      // sekadar daftar akun ringkas. Layar ZK tetap jadi rujukan bentuk datanya.
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Konfigurasi Kode Akun')),
          body: const KodeAkunScreen(),
        ),
      ));
      return;
    }
    // Siklus akuntansi (saldo awal, penyesuaian berkala, tutup buku) -- satu layar bertab;
    // ketiganya menentukan benar tidaknya Neraca/Buku Besar/Neraca Saldo.
    const petaSiklus = {
      'saldo_awal_akun': 0,
      'jurnal_penyesuaian': 1,
      'tutup_buku': 2,
    };
    if (petaSiklus.containsKey(id)) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
              title: Text(item['judul'] as String? ?? 'Siklus Akuntansi')),
          body: SiklusAkuntansiScreen(tabAwal: petaSiklus[id]!),
        ),
      ));
      return;
    }
    // Empat posting penutup rantai pengadaan->pembayaran toko. Dialognya terpisah
    // karena kontrak drafnya berbeda (per dokumen, dengan alasan bila belum siap).
    const petaPostingToko = {
      'posting_kulakan': 'kulakan',
      'posting_bayar_hutang': 'bayar_hutang',
      'posting_terima_piutang': 'terima_piutang',
      'posting_penyesuaian': 'penyesuaian',
    };
    if (petaPostingToko.containsKey(id)) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PostingTokoDialog(
          jenis: petaPostingToko[id]!,
          judul: item['judul'] as String? ?? 'Posting',
        ),
      );
      return;
    }
    if (id == 'posting_hpp' || id == 'posting_penjualan') {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PostingKeuanganDialog(
          jenis: id == 'posting_hpp' ? 'hpp' : 'penjualan',
          judul: item['judul'] as String? ?? 'Posting',
        ),
      );
      return;
    }
    await _bukaItem(item);
  }

  static IconData _ikonPendukung(String id) {
    switch (id) {
      case 'akun_perkiraan':
        return Icons.account_tree_outlined;
      case 'posting_hpp':
        return Icons.inventory_2_outlined;
      case 'posting_penjualan':
        return Icons.point_of_sale_outlined;
      case 'posting_kulakan':
        return Icons.local_shipping_outlined;
      case 'posting_bayar_hutang':
        return Icons.payments_outlined;
      case 'posting_terima_piutang':
        return Icons.savings_outlined;
      case 'posting_penyesuaian':
        return Icons.tune_outlined;
      case 'saldo_awal_akun':
        return Icons.play_circle_outline;
      case 'jurnal_penyesuaian':
        return Icons.rule_folder_outlined;
      case 'tutup_buku':
        return Icons.lock_outline;
      default:
        return Icons.post_add_outlined;
    }
  }

  /// Panel isi untuk satu tab pendukung. Semua ditampilkan LANGSUNG di dalam tab
  /// (mode `inline`), bukan lagi dialog melayang, supaya perpindahan antar bagian
  /// terasa sama seperti tab pada layar Kulakan.
  Widget _panelPendukung(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? '';
    final judul = item['judul'] as String? ?? 'Posting';
    if (id == 'akun_perkiraan') {
      return const KodeAkunScreen();
    }
    const petaPostingToko = {
      'posting_kulakan': 'kulakan',
      'posting_bayar_hutang': 'bayar_hutang',
      'posting_terima_piutang': 'terima_piutang',
      'posting_penyesuaian': 'penyesuaian',
    };
    final jenisToko = petaPostingToko[id];
    if (jenisToko != null) {
      return PostingTokoDialog(jenis: jenisToko, judul: judul, inline: true);
    }
    if (id == 'posting_hpp' || id == 'posting_penjualan') {
      return _PostingKeuanganDialog(
          jenis: id == 'posting_hpp' ? 'hpp' : 'penjualan',
          judul: judul,
          inline: true);
    }
    // Item lain (mis. laporan ber-URL) tetap memakai jalur pembuka lama.
    return Center(
      child: FilledButton.icon(
        onPressed: () => _bukaPendukungInline(item),
        icon: Icon(_ikonPendukung(id)),
        label: Text('Buka $judul'),
      ),
    );
  }

  List<_LaporanKatalogBaris> get _terfilter {
    final kw = _controllerCari.text.trim().toLowerCase();
    final hasil = <_LaporanKatalogBaris>[];
    for (final k in _kategori) {
      final kat = k['kat'] as String? ?? '';
      final items = ((k['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (_kategoriDipilih.isNotEmpty && kat != _kategoriDipilih) {
        continue;
      }
      final cocokKategori = kat.toLowerCase().contains(kw);
      for (final item in items) {
        final judul = (item['judul'] as String? ?? '').toLowerCase();
        final ket = (item['ket'] as String? ?? '').toLowerCase();
        if (kw.isEmpty ||
            cocokKategori ||
            judul.contains(kw) ||
            ket.contains(kw)) {
          hasil.add(_LaporanKatalogBaris(kategori: kat, item: item));
        }
      }
    }
    return hasil;
  }

  int _totalHalaman(int total) {
    if (total <= 0) return 1;
    return ((total - 1) ~/ _pageSize) + 1;
  }

  List<_LaporanKatalogBaris> _halamanData(List<_LaporanKatalogBaris> data) {
    final totalHalaman = _totalHalaman(data.length);
    if (_halaman > totalHalaman) _halaman = totalHalaman;
    final mulai = (_halaman - 1) * _pageSize;
    final sampai = (mulai + _pageSize).clamp(0, data.length);
    if (mulai >= data.length) return const [];
    return data.sublist(mulai, sampai);
  }

  Color _warnaBiruGelap(BuildContext context) => AppColors.gelap(context)
      ? AppColors.darkTextPrimary
      : AppColors.sidebarBg;

  List<String> get _opsiKategori {
    final kategori = _kategori
        .map((e) => e['kat'] as String? ?? '')
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return kategori;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: widget.menuAktif,
      judul: widget.judul,
      subjudul: widget.subjudul,
      aksiHeader: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _muat,
          tooltip: 'Muat ulang'),
      actionsAppBar: [
        IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _muat,
            tooltip: 'Muat ulang')
      ],
      // Halaman posting mengurus scroll-nya sendiri; katalog tetap memakai
      // scroll milik shell seperti sebelumnya.
      scrollable: _pendukungTerpilih == null,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Gagal memuat: $_pesanError'),
                  AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
                ]))
              : _pendukungTerpilih == null
                  ? _katalog()
                  : _panelPendukung(_pendukungTerpilih!),
    );
  }

  /// Layar pendukung yang diminta submenu ini (Posting HPP, Akun/Perkiraan, dst),
  /// atau null bila submenu ini memang katalog laporan.
  ///
  /// SATU SUBMENU = SATU HALAMAN. Sebelumnya seluruh layar pendukung dijejer
  /// sebagai tab di atas halaman, padahal daftar yang sama sudah ada di panel
  /// menu: pengguna melihat dua daftar menu sekaligus, dan begitu isinya belasan
  /// deretan tab melebar sampai memotong judul halaman. Perpindahan antarhalaman
  /// kini lewat dropdown grup di kepala halaman (`_DropdownGrupMenu`).
  Map<String, dynamic>? get _pendukungTerpilih {
    final minta = widget.bukaPosting;
    if (minta == null || minta.isEmpty) return null;
    for (final item in _pendukung) {
      if (item['id'] == minta) return item;
    }
    return null;
  }

  Widget _katalog() {
    return Builder(
      builder: (context) {
        final data = _terfilter;
        final totalHalaman = _totalHalaman(data.length);
        final halamanData = _halamanData(data);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sempit = constraints.maxWidth < 720;
                  final kategoriDropdown = DropdownButtonFormField<String>(
                    value: _kategoriDipilih,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kategori',
                      prefixIcon: Icon(Icons.category_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Semua kategori'),
                      ),
                      ..._opsiKategori.map(
                        (kategori) => DropdownMenuItem(
                          value: kategori,
                          child: Text(
                            kategori,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setStateIfMounted(() {
                      _kategoriDipilih = value ?? '';
                      _halaman = 1;
                    }),
                  );
                  final pencarian = AppSearchField(
                    controller: _controllerCari,
                    hintText: 'Cari laporan...',
                    debounce: Duration.zero,
                    onChanged: (_) => setStateIfMounted(() => _halaman = 1),
                  );
                  if (sempit) {
                    return Column(
                      children: [
                        kategoriDropdown,
                        const SizedBox(height: 8),
                        pencarian,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 320, child: kategoriDropdown),
                      const SizedBox(width: 10),
                      Expanded(child: pencarian),
                    ],
                  );
                },
              ),
            ),
            AppDataTable(
              minWidth: 920,
              emptyText: 'Tidak ada laporan yang cocok.',
              columns: const [
                AppTableColumn('Kategori', flex: 2),
                AppTableColumn('Laporan', flex: 3),
                AppTableColumn('Keterangan', flex: 4),
                AppTableColumn('Format', width: 96, align: TextAlign.center),
                AppTableColumn('Aksi', width: 82, align: TextAlign.center),
              ],
              rows: halamanData.map((baris) {
                final item = baris.item;
                final adaUrl = (item['url'] as String? ?? '').isNotEmpty;
                return AppTableRowData(
                  onTap: () => _bukaItem(item),
                  cells: [
                    // Kilau ditempel pada KATEGORI: itulah satuan
                    // ber-identitas stabil pada respons katalog
                    // ('kat'), sedangkan baris tabel di sini hasil
                    // perataan item per kategori.
                    AppTableCell(
                      flex: 2,
                      child: KilauBaris(
                        kunci: MasterOffline.kunciBaris(
                            {'kat': baris.kategori}, 'kat'),
                        idBaru: _diff.idBaru,
                        idBerubah: _diff.idBerubah,
                        child: Text(
                          baris.kategori,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    AppTableCell.text(
                      item['judul'] as String? ?? '-',
                      flex: 3,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _warnaBiruGelap(context),
                      ),
                    ),
                    AppTableCell.text(
                      item['ket'] as String? ?? '-',
                      flex: 4,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    AppTableCell(
                      width: 96,
                      align: TextAlign.center,
                      child: StatusPill(
                        label: adaUrl ? 'Link' : 'Data',
                        warna: adaUrl ? AppColors.info : AppColors.primary,
                      ),
                    ),
                    AppTableCell(
                      width: 82,
                      align: TextAlign.center,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: adaUrl ? 'Buka laporan' : 'Jalankan laporan',
                        icon: Icon(
                          adaUrl ? Icons.open_in_new : Icons.chevron_right,
                          size: 20,
                          color: _warnaBiruGelap(context),
                        ),
                        onPressed: () => _bukaItem(item),
                      ),
                    ),
                  ],
                );
              }).toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: totalHalaman,
                totalData: data.length,
                labelData: 'laporan',
                onSebelumnya: _halaman > 1
                    ? () => setStateIfMounted(() => _halaman--)
                    : null,
                onBerikutnya: _halaman < totalHalaman
                    ? () => setStateIfMounted(() => _halaman++)
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LaporanKatalogBaris {
  final String kategori;
  final Map<String, dynamic> item;

  const _LaporanKatalogBaris({
    required this.kategori,
    required this.item,
  });
}

final _formatRupiahLaporan =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggalLaporan = DateFormat('yyyy-MM-dd');

class _DaftarAkunDialog extends StatefulWidget {
  const _DaftarAkunDialog();

  @override
  State<_DaftarAkunDialog> createState() => _DaftarAkunDialogState();
}

class _DaftarAkunDialogState extends State<_DaftarAkunDialog> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _akun = [];
  final TextEditingController _cari = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      final hasil = await MasterOffline.daftarDenganCache(
          'akun_list', {'limit': 5000}, 'master:akun');
      final sumber = (hasil['data'] as List?) ?? (hasil['akun'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _akun = sumber
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = terapkanGalat(e);
        _memuat = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kata = _cari.text.trim().toLowerCase();
    final akun = _akun.where((e) {
      final teks =
          '${e['kode'] ?? ''} ${e['nama'] ?? e['label'] ?? ''}'.toLowerCase();
      return kata.isEmpty || teks.contains(kata);
    }).toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Expanded(
                    child: Text('Akun / Perkiraan',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700))),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              const Text(
                  'Bagan akun ditampilkan langsung tanpa berpindah halaman.'),
              const SizedBox(height: 12),
              AppSearchField(
                controller: _cari,
                hintText: 'Cari kode atau nama akun...',
                debounce: Duration.zero,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Text('Gagal memuat akun: $_error'),
                                AppDetailGalatOpsional(
                                    detail: detailUntuk(_error)),
                              ]))
                        : ListView.separated(
                            itemCount: akun.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final row = akun[i];
                              return ListTile(
                                leading:
                                    const Icon(Icons.account_tree_outlined),
                                title: Text(row['nama'] as String? ??
                                    row['label'] as String? ??
                                    '-'),
                                subtitle: Text(row['kode']?.toString() ?? '-'),
                              );
                            },
                          ),
              ),
              Text('${akun.length} akun', textAlign: TextAlign.right),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostingKeuanganDialog extends StatefulWidget {
  final String jenis;
  final String judul;

  /// true = tampil sebagai panel di dalam tab (tanpa bungkus Dialog dan tanpa
  /// tombol Tutup, karena di dalam tab tombol itu akan menutup seluruh halaman).
  final bool inline;
  const _PostingKeuanganDialog(
      {required this.jenis, required this.judul, this.inline = false});

  @override
  State<_PostingKeuanganDialog> createState() => _PostingKeuanganDialogState();
}

class _PostingKeuanganDialogState extends State<_PostingKeuanganDialog>
    with JejakGalat {
  late DateTime _mulai;
  DateTime _sampai = DateTime.now();
  bool _memuat = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mulai = DateTime(now.year, now.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _proses(false));
  }

  Future<void> _pilihTanggal(bool awal) async {
    final nilai = awal ? _mulai : _sampai;
    final hasil = await showDatePicker(
      context: context,
      initialDate: nilai,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (hasil == null || !mounted) return;
    setState(() {
      if (awal) {
        _mulai = hasil;
      } else {
        _sampai = hasil;
      }
      _data = null;
    });
  }

  Future<void> _proses(bool posting) async {
    if (_mulai.isAfter(_sampai)) {
      setState(
          () => _error = 'Tanggal mulai tidak boleh melewati tanggal akhir.');
      return;
    }
    if (posting) {
      final setuju = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Posting ${widget.judul}?'),
          content: const Text(
              'Jurnal akan disimpan permanen menggunakan hasil pratinjau periode ini.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Posting')),
          ],
        ),
      );
      if (setuju != true) return;
    }
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'laporan_keuangan_pendukung',
        {
          'jenis': widget.jenis,
          'mulai': _formatTanggalLaporan.format(_mulai),
          'sampai': _formatTanggalLaporan.format(_sampai),
          'posting': posting,
        },
      );
      final data = Map<String, dynamic>.from((hasil['data'] as Map?) ?? hasil);
      if (!mounted) return;
      setState(() => _data = data);
      if (posting) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.judul} berhasil diposting.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  /// Posting SATU transaksi (pola Posting Cicilan Mahasiswa). Server menerima
  /// `posting_ids` dan menulis satu entri jurnal khusus transaksi itu, sehingga
  /// transaksi lain yang pemetaannya belum lengkap tidak ikut terhalang.
  Future<void> _postingSatu(dynamic id) async {
    if (id == null) return;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Posting Transaksi Ini?'),
        content: const Text(
            'Transaksi ini akan dijurnal tersendiri. Tindakan ini tidak dapat '
            'dibatalkan dari halaman ini.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Posting')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'laporan_keuangan_pendukung',
        {
          'jenis': widget.jenis,
          'mulai': _formatTanggalLaporan.format(_mulai),
          'sampai': _formatTanggalLaporan.format(_sampai),
          'posting_ids': [id],
        },
      );
      final data = Map<String, dynamic>.from((hasil['data'] as Map?) ?? hasil);
      if (!mounted) return;
      setState(() => _data = data);
      final ringkas = (data['hasilPosting'] as Map?) ?? const {};
      final diposting = ringkas['diposting'] ?? 0;
      final gagal = ringkas['gagal'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(gagal == 0
              ? '$diposting transaksi diposting.'
              : '$diposting diposting, $gagal gagal. ${ringkas['pesan'] ?? ''}')));
      // Muat ulang draft agar transaksi yang sudah diposting hilang dari daftar.
      await _proses(false);
    } catch (e) {
      if (mounted) setState(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Widget _diagnostikPemetaan(List<dynamic> sumber) {
    final semua = sumber
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final unik = semua.toSet().toList(growable: false);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.settings_suggest_outlined,
            color: Color(0xFFB45309)),
        title:
            Text('${semua.length} transaksi belum siap karena setting akun.'),
        subtitle: Text(unik.isEmpty
            ? 'Buka rincian untuk mengetahui pengaturan yang perlu dilengkapi.'
            : unik.first),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Yang perlu dilakukan:',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (var i = 0; i < unik.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText('${i + 1}. ${unik[i]}'),
            ),
          const Text(
            'Sesudah setting disimpan, klik Pratinjau lagi. Transaksi yang belum siap '
            'tidak boleh dipaksa posting atau diperbaiki langsung pada draf jurnal.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jurnal = ((_data?['jurnal'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final belum = ((_data?['belumDipetakan'] as List?) ?? []);
    // Draft jurnal per transaksi dari server (field 'rincian').
    final rincian = ((_data?['rincian'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final siap = _data?['siap'] == true && _data?['diposting'] != true;
    final Widget isi = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(widget.judul,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700))),
            if (!widget.inline)
              IconButton(
                  onPressed: _memuat ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
          ]),
          const Text(
              'Pratinjau dan posting dilakukan langsung di halaman ini.'),
          PenjelasanSumberAkunPosting(jenis: widget.jenis),
          Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _memuat ? null : () => _pilihTanggal(true),
                icon: const Icon(Icons.date_range),
                label: Text('Mulai ${_formatTanggalLaporan.format(_mulai)}')),
            OutlinedButton.icon(
                onPressed: _memuat ? null : () => _pilihTanggal(false),
                icon: const Icon(Icons.event_available),
                label: Text('Sampai ${_formatTanggalLaporan.format(_sampai)}')),
            FilledButton.icon(
                onPressed: _memuat ? null : () => _proses(false),
                icon: const Icon(Icons.preview_outlined),
                label: const Text('Pratinjau')),
            TombolSesuaikanAkunPosting(
                jenis: widget.jenis,
                sisi: SisiAkunPosting.debet,
                onSelesai: () => _proses(false)),
            TombolSesuaikanAkunPosting(
                jenis: widget.jenis,
                sisi: SisiAkunPosting.kredit,
                onSelesai: () => _proses(false)),
          ]),
          if (_memuat) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_data != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                  label: Text(
                      'Total ${_formatRupiahLaporan.format(_data!['total'] ?? 0)}')),
              if (_data!.containsKey('jumlahTransaksi'))
                Chip(label: Text('${_data!['jumlahTransaksi']} transaksi')),
              Chip(
                  label: Text(_data!['siap'] == true
                      ? 'Siap diposting'
                      : 'Belum siap')),
              if (_data!['terakhir'] != null)
                Chip(label: Text('Posting terakhir ${_data!['terakhir']}')),
            ]),
            if (belum.isNotEmpty) _diagnostikPemetaan(belum),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: rincian.isEmpty
                ? (jurnal.isEmpty
                    ? const Center(
                        child: Text(
                            'Jalankan pratinjau untuk melihat draft jurnal.'))
                    : ListView.separated(
                        itemCount: jurnal.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final row = jurnal[i];
                          return ListTile(
                            dense: true,
                            title: Text(row['akun']?.toString() ?? '-'),
                            subtitle: Text(row['posisi']?.toString() ?? '-'),
                            trailing: Text(_formatRupiahLaporan
                                .format(row['nominal'] ?? 0)),
                          );
                        },
                      ))
                // DRAFT JURNAL PER TRANSAKSI (pola Posting Cicilan Mahasiswa):
                // tiap transaksi tampil beserta baris akun debit/kreditnya sehingga
                // dapat dianalisis dulu, lalu diposting satu per satu.
                : ListView.separated(
                    itemCount: rincian.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = rincian[i];
                      final siapBaris = t['siap'] == true;
                      final barisJurnal = ((t['jurnal'] as List?) ?? [])
                          .cast<Map<String, dynamic>>();
                      return Container(
                        color: siapBaris ? null : const Color(0xFFFFF7ED),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${t['ref'] ?? '-'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      _formatRupiahLaporan
                                          .format(t['nilai'] ?? 0),
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 4),
                                  for (final j in barisJurnal)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 8, top: 1),
                                      child: Text(
                                        '${j['akun'] ?? '-'}   '
                                        '${(j['debit'] ?? 0) > 0 ? 'D ${_formatRupiahLaporan.format(j['debit'])}' : 'K ${_formatRupiahLaporan.format(j['kredit'])}'}',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontFamily: 'monospace'),
                                      ),
                                    ),
                                  if (!siapBaris &&
                                      '${t['alasan'] ?? ''}'.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text('${t['alasan']}',
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFFB45309))),
                                    ),
                                ],
                              ),
                            ),
                            siapBaris
                                ? OutlinedButton.icon(
                                    onPressed: _memuat
                                        ? null
                                        : () => _postingSatu(t['id']),
                                    icon: const Icon(Icons.check_circle_outline,
                                        size: 16),
                                    label: const Text('Posting'))
                                : Wrap(
                                    direction: Axis.vertical,
                                    spacing: 4,
                                    children: [
                                      TombolSesuaikanAkunPosting(
                                        jenis: widget.jenis,
                                        sisi: SisiAkunPosting.debet,
                                        alasan: '${t['alasan'] ?? ''}',
                                        ringkas: true,
                                        onSelesai: () => _proses(false),
                                      ),
                                      TombolSesuaikanAkunPosting(
                                        jenis: widget.jenis,
                                        sisi: SisiAkunPosting.kredit,
                                        alasan: '${t['alasan'] ?? ''}',
                                        ringkas: true,
                                        onSelesai: () => _proses(false),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: _memuat ? null : () => Navigator.pop(context),
                child: const Text('Tutup')),
            const SizedBox(width: 8),
            FilledButton.icon(
                onPressed: siap && !_memuat ? () => _proses(true) : null,
                icon: const Icon(Icons.post_add),
                label: const Text('Posting')),
          ]),
        ],
      ),
    );
    if (widget.inline) {
      return isi;
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
        child: isi,
      ),
    );
  }
}
