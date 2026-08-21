import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/safe_state.dart';
import 'pengajuan_anda_detail_screen.dart';
import 'pengajuan_baru_screen.dart';

/// Layar **"Pengajuan Anda" (Workflow / Proses SOP)** untuk POS Desktop & Android.
///
/// Padanan langsung versi ZKoss `DasboardSop.java` (dasbor + daftar operasional)
/// dan `TampilanAlurSopAction.java` (alur satu pengajuan, ada di layar detail).
/// SELURUH logikanya dijalankan server lewat aksi API `sop_*` yang dilayani
/// `SopService.java` -- port resmi kedua berkas ZKoss itu. Tidak ada iframe,
/// tidak ada webview, dan tidak ada logika bisnis yang disalin ke sisi klien:
/// klien hanya menampilkan apa yang server hitung, persis seperti versi ZKoss
/// menampilkan hasil `getCountXxx`/`criteriaXxx`-nya sendiri.
///
/// Enam kartu dasbor sama persis dengan enam kartu ZKoss (`renderMetricCards`),
/// dan setiap kartu bisa diketuk untuk membuka daftarnya -- padanan popup detail
/// per-kartu di ZKoss, dijadikan satu daftar ter-paginasi lewat `sop_daftar`.
///
/// Hak akses: tombol pembukanya di [AppShell] hanya muncul bila server mengirim
/// `aksesMenu.pengajuan_anda` bernilai true, yang sumbernya `Tbmrole.workflow`
/// -- kolom yang SAMA dipakai versi ZKoss. Gerbang sebenarnya tetap di server
/// (`PosApi.bolehAksesActionKantin`), jadi menyembunyikan tombol hanyalah lapis
/// tampilan, bukan pengamanannya.
class PengajuanAndaScreen extends StatefulWidget {
  /// Kategori yang langsung dibuka (opsional) -- dipakai saat pengguna mengetuk
  /// kartu KPI dari layar lain.
  final String? kategoriAwal;
  const PengajuanAndaScreen({super.key, this.kategoriAwal});

  @override
  State<PengajuanAndaScreen> createState() => _PengajuanAndaScreenState();
}

/// Satu kartu KPI dasbor sekaligus satu kategori daftar.
///
/// Urutan, judul, keterangan, dan warnanya sengaja disamakan dengan
/// `DasboardSop.renderMetricCards` supaya pengguna yang terbiasa dengan versi
/// ZKoss menemukan angka yang sama di tempat yang sama.
class KategoriPengajuan {
  final String kunci;
  final String kunciKpi;
  final String label;
  final String catatan;
  final Color warna;
  final IconData ikon;
  const KategoriPengajuan(
      this.kunci, this.kunciKpi, this.label, this.catatan, this.warna, this.ikon);
}

const kUnguSop = Color(0xFF5B21B6);

const List<KategoriPengajuan> kKategoriPengajuan = [
  KategoriPengajuan('menunggu_saya', 'menungguSaya', 'Menunggu Saya',
      'Butuh disposisi / tindak lanjut', AppColors.danger, Icons.priority_high),
  KategoriPengajuan('sudah_disposisi', 'sudahSayaDisposisi', 'Sudah Disposisi',
      'Riwayat proses oleh Anda', AppColors.success, Icons.check_circle_outline),
  KategoriPengajuan('pengajuan_anda', 'jumlahSopBaru', 'Jumlah Data Pengajuan Anda',
      'Pengajuan SOP yang Anda lakukan', Color(0xFF1E40AF), Icons.add_circle_outline),
  KategoriPengajuan('selesai', 'selesai', 'Selesai', 'Pengajuan selesai',
      AppColors.warning, Icons.star_outline),
  KategoriPengajuan('menunggu_aktor', 'menungguAktor', 'Menunggu Petugas',
      'Proses sedang berjalan', kUnguSop, Icons.arrow_forward),
  KategoriPengajuan('lewat_deadline', 'lewatDeadline', 'Lewat Batas Waktu',
      'Menunggu disposisi Anda yang sudah melewati batas waktu',
      AppColors.danger, Icons.schedule),
];

/// Kategori tambahan **di luar enam kartu dasbor**: pencarian menyeluruh atas
/// semua pengajuan yang boleh dilihat pengguna (aksi `sop_cari`, port
/// `loadData`/`initCriteria` pada `TampilanAlurSopAction`).
///
/// Sengaja TIDAK dimasukkan ke [kKategoriPengajuan] supaya dasbor tetap
/// menampilkan enam kartu yang sama persis dengan versi ZKoss. Server membatasi
/// hasilnya 100 baris tanpa paginasi, jadi penomoran halaman disembunyikan.
const KategoriPengajuan kCariSemua = KategoriPengajuan(
    'cari_semua',
    '',
    'Pencarian',
    'Cari di seluruh pengajuan yang boleh Anda lihat',
    AppColors.teal,
    Icons.search);

/// Filter global dasbor -- padanan toolbar Mulai/Sampai/Cari pada
/// `DasboardSop.renderDasborSopGlobalFilter`. Satker tidak disertakan karena
/// aksi `sop_dashboard`/`sop_daftar` memang tidak menerimanya.
class FilterPengajuan {
  final DateTime? mulai;
  final DateTime? sampai;
  final String keyword;
  const FilterPengajuan({this.mulai, this.sampai, this.keyword = ''});

  Map<String, dynamic> keBody() => {
        if (mulai != null) 'mulai': _tglServer(mulai!),
        if (sampai != null) 'sampai': _tglServer(sampai!),
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      };

  String get sidik =>
      '${mulai?.millisecondsSinceEpoch ?? 0}_${sampai?.millisecondsSinceEpoch ?? 0}_${keyword.trim()}';

  String get ringkas {
    final p = mulai == null && sampai == null
        ? 'Semua Periode'
        : '${mulai == null ? '...' : _tglTampil(mulai!)} s/d '
            '${sampai == null ? '...' : _tglTampil(sampai!)}';
    final k = keyword.trim().isEmpty ? 'Tanpa keyword' : 'Cari: ${keyword.trim()}';
    return '$p  •  $k';
  }
}

String _dua(int n) => n < 10 ? '0$n' : '$n';
String _tglServer(DateTime d) => '${d.year}-${_dua(d.month)}-${_dua(d.day)}';
String _tglTampil(DateTime d) => '${_dua(d.day)}-${_dua(d.month)}-${d.year}';

class _PengajuanAndaScreenState extends State<PengajuanAndaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  FilterPengajuan _filter = const FilterPengajuan();

  /// Kategori yang sedang ditampilkan pada tab daftar.
  late String _kategori;

  /// Penyaring tambahan hasil ketukan pada sebaran SOP / beban petugas --
  /// padanan tap-through dari grafik ke popup detail di ZKoss.
  String _sopNama = '';
  String _aktorTahap = '';

  /// Dinaikkan tiap kali filter berubah supaya tab yang tidak aktif ikut
  /// memuat ulang ketika dibuka.
  int _revisi = 0;

  @override
  void initState() {
    super.initState();
    _kategori = widget.kategoriAwal ?? 'menunggu_saya';
    _tab = TabController(
        length: 2, vsync: this, initialIndex: widget.kategoriAwal == null ? 0 : 1);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _bukaKategori(String kunci, {String sopNama = '', String aktorTahap = ''}) {
    setState(() {
      _kategori = kunci;
      _sopNama = sopNama;
      _aktorTahap = aktorTahap;
      _revisi++;
    });
    _tab.animateTo(1);
  }

  /// Membuka wizard "Pengajuan Baru"; bila pengajuan berhasil dibuat, langsung
  /// membuka detailnya supaya pengguna melihat alurnya sudah berjalan, lalu
  /// menyegarkan dasbor dan daftar.
  Future<void> _ajukanBaru() async {
    final hasil = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PengajuanBaruScreen()),
    );
    if (!mounted) return;
    final id = hasil == null ? null : hasil['disposisiSopId'];
    if (id != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PengajuanAndaDetailScreen(disposisiSopId: '$id'),
      ));
    }
    if (!mounted) return;
    setState(() => _revisi++);
  }

  Future<void> _ubahFilter() async {
    final hasil = await showDialog<FilterPengajuan>(
      context: context,
      builder: (_) => _DialogFilter(awal: _filter),
    );
    if (hasil == null || !mounted) return;
    setState(() {
      _filter = hasil;
      _revisi++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Pengajuan Anda'),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Filter periode & pencarian',
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _ubahFilter,
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _revisi++),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.insights_outlined), text: 'Dasbor'),
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Pengajuan'),
          ],
        ),
      ),
      // Padanan tombol "Tambah" pada layar SOP versi ZKoss
      // (DisposisiSopAction). Daftar jenis SOP yang boleh dimulai dihitung
      // server, jadi tombol ini tidak perlu digerbang lagi di sini: bila
      // pengguna tidak berhak memulai SOP apa pun, daftarnya memang kosong.
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Pengajuan Baru'),
        onPressed: _ajukanBaru,
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _TabDasbor(
            key: ValueKey('dasbor-$_revisi-${_filter.sidik}'),
            filter: _filter,
            onPilihKategori: _bukaKategori,
            onUbahFilter: _ubahFilter,
          ),
          _TabDaftar(
            key: ValueKey('daftar-$_revisi-$_kategori-$_sopNama-$_aktorTahap-${_filter.sidik}'),
            kategori: _kategori,
            filter: _filter,
            sopNama: _sopNama,
            aktorTahap: _aktorTahap,
            onGantiKategori: (k) => setState(() {
              _kategori = k;
              _sopNama = '';
              _aktorTahap = '';
              _revisi++;
            }),
            onBersihkanPenyaring: () => setState(() {
              _sopNama = '';
              _aktorTahap = '';
              _revisi++;
            }),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 1 — DASBOR
// ════════════════════════════════════════════════════════════════════════════

class _TabDasbor extends StatefulWidget {
  final FilterPengajuan filter;
  final void Function(String kunci, {String sopNama, String aktorTahap})
      onPilihKategori;
  final VoidCallback onUbahFilter;
  const _TabDasbor(
      {super.key,
      required this.filter,
      required this.onPilihKategori,
      required this.onUbahFilter});

  @override
  State<_TabDasbor> createState() => _TabDasborState();
}

class _TabDasborState extends State<_TabDasbor> {
  bool _memuat = true;
  String? _galat;
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Sengaja TIDAK lewat MasterOffline.daftarCacheDulu: pembantu itu hanya
      // menangani muatan berupa DAFTAR, sedangkan sop_dashboard mengembalikan
      // objek agregat. Angka dasbor pun harus mencerminkan keadaan antrian SAAT
      // INI -- menampilkan cacah lama tanpa penanda bisa membuat pengguna
      // mengira tidak ada yang perlu didisposisi.
      final res =
          await ApiClient.instance.aksi('sop_dashboard', widget.filter.keBody());
      if (!mounted) return;
      final sukses = res['status'] == '00' || res['status'] == 'success';
      setStateIfMounted(() {
        if (sukses) {
          _d = Map<String, dynamic>.from(
              (res['data'] as Map?) ?? const <String, dynamic>{});
        } else {
          _galat =
              '${res['message'] ?? res['description'] ?? 'Gagal memuat dasbor.'}';
        }
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        if (_d == null) _galat = '$e';
        _memuat = false;
      });
    }
  }

  int _n(String kunci) {
    final v = _d?[kunci];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  List<Map<String, dynamic>> _list(String kunci) =>
      ((_d?[kunci] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> _obj(String kunci) =>
      Map<String, dynamic>.from((_d?[kunci] as Map?) ?? const <String, dynamic>{});

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return statusMuatDasbor(
          memuat: _memuat, error: _galat, onCoba: _muat);
    }
    final deadline = _obj('deadline');
    final mutu = _obj('metadataQuality');
    final perSop = _list('perSop');
    final perAktor = _list('perAktor');
    final aktivitas = _list('aktivitasTerbaru');

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _hero(context),
          const SizedBox(height: 14),
          _kartuKpi(context),
          const SizedBox(height: 14),
          PanelChart(
            judul: 'Corong Proses SOP',
            child: BarHorizontal(
              data: [
                for (final k in kKategoriPengajuan)
                  (label: k.label, nilai: _n(k.kunciKpi).toDouble()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PanelChart(
            judul: 'Risiko Batas Waktu',
            child: BarHorizontal(
              data: [
                (label: 'Lewat batas', nilai: _angka(deadline['lewat']).toDouble()),
                (label: 'Jatuh tempo hari ini', nilai: _angka(deadline['hariIni']).toDouble()),
                (label: 'Minggu ini', nilai: _angka(deadline['mingguIni']).toDouble()),
                (label: 'Masih aman', nilai: _angka(deadline['aman']).toDouble()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _panelKetuk(
            context,
            judul: 'Sebaran per SOP',
            catatan: 'Ketuk salah satu baris untuk melihat pengajuannya.',
            data: perSop,
            onKetuk: (label) => widget.onPilihKategori('menunggu_aktor',
                sopNama: label, aktorTahap: ''),
          ),
          const SizedBox(height: 12),
          _panelKetuk(
            context,
            judul: 'Beban Petugas / Tahap',
            catatan: 'Ketuk salah satu baris untuk melihat pengajuannya.',
            data: perAktor,
            onKetuk: (label) => widget.onPilihKategori('menunggu_aktor',
                sopNama: '', aktorTahap: label),
          ),
          const SizedBox(height: 12),
          _panelMutuData(context, mutu),
          const SizedBox(height: 12),
          _panelAktivitas(context, aktivitas),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  int _angka(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.teal],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SOP CONTROL CENTER',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Dasbor Proses SOP',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              'Pantau alur pengajuan, antrian disposisi, penyelesaian, dan '
              'risiko batas waktu dalam satu layar. Ketuk angka untuk melihat '
              'detail datanya.',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 12),
          InkWell(
            onTap: widget.onUbahFilter,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_alt_outlined,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(widget.filter.ringkas,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _angkaHero(
                      'Proses Dipantau', _n('totalDipantau'))),
              Expanded(
                  child: _angkaHero('Total Antrian', _n('totalAntrian'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _angkaHero(String label, int nilai) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$nilai',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );

  Widget _kartuKpi(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final kolom = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
      final lebar = (c.maxWidth - (kolom - 1) * 10) / kolom;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final k in kKategoriPengajuan)
            SizedBox(
              width: lebar,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => widget.onPilihKategori(k.kunci),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardBgOf(context),
                    border: Border.all(color: AppColors.borderOf(context)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.latarLembut(k.warna),
                                borderRadius: BorderRadius.circular(11)),
                            child: Icon(k.ikon, size: 18, color: k.warna),
                          ),
                          Text('${_n(k.kunciKpi)}',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimaryOf(context))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(k.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryOf(context))),
                      const SizedBox(height: 3),
                      Text(k.catatan,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context))),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _panelKetuk(BuildContext context,
      {required String judul,
      required String catatan,
      required List<Map<String, dynamic>> data,
      required void Function(String label) onKetuk}) {
    if (data.isEmpty) {
      return PanelChart(
          judul: judul, child: BarHorizontal(data: const []));
    }
    final maks = data
        .map((e) => _angka(e['jumlah']))
        .fold<int>(1, (a, b) => a > b ? a : b);
    return PanelChart(
      judul: judul,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(catatan,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 8),
          for (final e in data)
            InkWell(
              onTap: () => onKetuk('${e['label'] ?? ''}'),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${e['label'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Text('${_angka(e['jumlah'])}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _angka(e['jumlah']) / maks,
                        minHeight: 6,
                        backgroundColor: AppColors.latarLembut(
                            AppColors.textSecondaryOf(context)),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelMutuData(BuildContext context, Map<String, dynamic> mutu) {
    if (mutu.isEmpty) return const SizedBox.shrink();
    final baris = <({String label, int nilai})>[
      (label: 'Tanpa batas waktu', nilai: _angka(mutu['tanpaDeadline'])),
      (label: 'Tanpa petugas', nilai: _angka(mutu['tanpaAktor'])),
      (label: 'Tanpa nama tahap', nilai: _angka(mutu['tanpaTahap'])),
      (label: 'Tanpa catatan', nilai: _angka(mutu['tanpaCatatan'])),
    ];
    return PanelChart(
      judul: 'Kelengkapan Data Alur',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Dihitung dari contoh alur terbaru. Angka besar berarti banyak '
              'tahap yang datanya belum lengkap sehingga sulit dipantau.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in baris)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: AppColors.latarLembut(b.nilai > 0
                          ? AppColors.warning
                          : AppColors.success),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('${b.label}: ${b.nilai}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: b.nilai > 0
                              ? AppColors.warning
                              : AppColors.success)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelAktivitas(
      BuildContext context, List<Map<String, dynamic>> aktivitas) {
    return PanelChart(
      judul: 'Aktivitas Terbaru',
      child: aktivitas.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('Belum ada aktivitas.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context))),
            )
          : Column(
              children: [
                for (final a in aktivitas)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${a['sop'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${a['aktor'] ?? '-'}  •  ${a['waktu'] ?? '-'}'
                        '${'${a['deadline'] ?? ''}'.isEmpty ? '' : '  •  batas ${a['deadline']}'}',
                        maxLines: 2,
                        style: const TextStyle(fontSize: 11)),
                    trailing: _lencanaStatus(context, '${a['status'] ?? ''}'),
                    onTap: () {
                      final id = a['disposisiSopId'];
                      if (id == null) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            PengajuanAndaDetailScreen(disposisiSopId: '$id'),
                      ));
                    },
                  ),
              ],
            ),
    );
  }
}

Widget _lencanaStatus(BuildContext context, String status) {
  Color w = AppColors.textSecondaryOf(context);
  final s = status.toLowerCase();
  if (s.contains('selesai')) {
    w = AppColors.success;
  } else if (s.contains('menunggu')) {
    w = AppColors.warning;
  } else if (s.contains('tolak')) {
    w = AppColors.danger;
  } else if (s.contains('proses')) {
    w = AppColors.primary;
  }
  if (status.trim().isEmpty) return const SizedBox.shrink();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: AppColors.latarLembut(w),
        borderRadius: BorderRadius.circular(999)),
    child: Text(status,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: w)),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 2 — DAFTAR PENGAJUAN
// ════════════════════════════════════════════════════════════════════════════

class _TabDaftar extends StatefulWidget {
  final String kategori;
  final FilterPengajuan filter;
  final String sopNama;
  final String aktorTahap;
  final void Function(String kunci) onGantiKategori;
  final VoidCallback onBersihkanPenyaring;
  const _TabDaftar(
      {super.key,
      required this.kategori,
      required this.filter,
      required this.sopNama,
      required this.aktorTahap,
      required this.onGantiKategori,
      required this.onBersihkanPenyaring});

  @override
  State<_TabDaftar> createState() => _TabDaftarState();
}

class _TabDaftarState extends State<_TabDaftar> {
  static const int _limit = 10;

  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _baris = const [];
  int _total = 0;
  int _halaman = 1;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    final body = <String, dynamic>{
      'kategori': widget.kategori,
      'page': _halaman,
      'limit': _limit,
      if (widget.sopNama.isNotEmpty) 'sopNama': widget.sopNama,
      if (widget.aktorTahap.isNotEmpty) 'aktorTahap': widget.aktorTahap,
      ...widget.filter.keBody(),
    };
    try {
      // Daftar ini BERHALAMAN dan merupakan antrian kerja: menyimpannya sebagai
      // snapshot lokal justru berbahaya -- baris yang sudah didisposisi orang
      // lain akan tetap terlihat menunggu. Karena itu selalu diambil dari
      // server, dan kegagalan jaringan ditampilkan apa adanya.
      final res = _cariMenyeluruh
          ? await ApiClient.instance
              .aksi('sop_cari', {'keyword': widget.filter.keyword.trim()})
          : await ApiClient.instance.aksi('sop_daftar', body);
      if (!mounted) return;
      final list = ((res['list'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final gagal = res['status'] != '00' &&
          res['status'] != '99' &&
          res['status'] != 'success';
      setStateIfMounted(() {
        _baris = list;
        if (_cariMenyeluruh) {
          // sop_cari tidak berhalaman (dibatasi 100 baris di server).
          _total = list.length;
        } else {
          final t = res['total'];
          _total = t is num ? t.toInt() : int.tryParse('${t ?? 0}') ?? 0;
        }
        if (gagal && list.isEmpty) {
          _galat = '${res['message'] ?? 'Gagal memuat daftar.'}';
        }
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  bool get _cariMenyeluruh => widget.kategori == kCariSemua.kunci;

  static const List<KategoriPengajuan> _semuaKategori = [
    ...kKategoriPengajuan,
    kCariSemua,
  ];

  KategoriPengajuan get _k => _semuaKategori.firstWhere(
      (e) => e.kunci == widget.kategori,
      orElse: () => kKategoriPengajuan.first);

  @override
  Widget build(BuildContext context) {
    final maksHalaman = _total <= 0 ? 1 : ((_total - 1) ~/ _limit) + 1;
    return Column(
      children: [
        _pemilihKategori(context),
        if (widget.sopNama.isNotEmpty || widget.aktorTahap.isNotEmpty)
          _chipPenyaring(context),
        Expanded(
          child: _memuat && _baris.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _galat != null && _baris.isEmpty
                  ? statusMuatDasbor(
                      memuat: false, error: _galat, onCoba: _muat)
                  : _baris.isEmpty
                      ? _kosong(context)
                      : RefreshIndicator(
                          onRefresh: _muat,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                            itemCount: _baris.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => _kartuBaris(context, _baris[i]),
                          ),
                        ),
        ),
        if (!_cariMenyeluruh && _total > _limit)
          _navigasiHalaman(context, maksHalaman),
      ],
    );
  }

  Widget _pemilihKategori(BuildContext context) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final k in _semuaKategori)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(k.label, style: const TextStyle(fontSize: 11)),
                  selected: k.kunci == widget.kategori,
                  selectedColor: AppColors.latarLembut(k.warna),
                  onSelected: (_) => widget.onGantiKategori(k.kunci),
                ),
              ),
          ],
        ),
      );

  Widget _chipPenyaring(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            label: Text(
                widget.sopNama.isNotEmpty
                    ? 'SOP: ${widget.sopNama}'
                    : 'Tahap/Petugas: ${widget.aktorTahap}',
                style: const TextStyle(fontSize: 11)),
            onDeleted: widget.onBersihkanPenyaring,
          ),
        ),
      );

  Widget _kosong(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 70),
          Icon(Icons.inbox_outlined,
              size: 44, color: AppColors.textSecondaryOf(context)),
          const SizedBox(height: 10),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                  _cariMenyeluruh
                      ? (widget.filter.keyword.trim().isEmpty
                          ? 'Isi kata kunci lewat tombol filter di atas untuk '
                              'mencari di seluruh pengajuan Anda.'
                          : 'Tidak ada pengajuan yang cocok dengan '
                              '"${widget.filter.keyword.trim()}".')
                      : 'Belum ada data pada kategori "${_k.label}".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context))),
            ),
          ),
        ],
      );

  Widget _kartuBaris(BuildContext context, Map<String, dynamic> b) {
    final lewat = b['lewatBatasWaktu'] == true;
    final id = b['disposisiSopId'] ?? b['id'];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: id == null
          ? null
          : () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PengajuanAndaDetailScreen(disposisiSopId: '$id'),
              ));
              if (mounted) _muat();
            },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          border: Border.all(
              color: lewat
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : AppColors.borderOf(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${b['kode'] ?? '-'}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                _lencanaStatus(context, '${b['status'] ?? ''}'),
              ],
            ),
            const SizedBox(height: 4),
            Text('${b['sop'] ?? '-'}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                'Pengaju: ${b['pengaju'] ?? '-'}'
                '${'${b['aktorTahap'] ?? ''}'.isEmpty ? '' : '\nTahap: ${b['aktorTahap']}'}',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context))),
            if ('${b['catatan'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Catatan: ${b['catatan']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondaryOf(context))),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 12, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 4),
                Text('${b['waktu'] ?? '-'}',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondaryOf(context))),
                if ('${b['waktuMaksimal'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.event_busy,
                      size: 12,
                      color: lewat
                          ? AppColors.danger
                          : AppColors.textSecondaryOf(context)),
                  const SizedBox(width: 4),
                  Text('${b['waktuMaksimal']}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              lewat ? FontWeight.bold : FontWeight.normal,
                          color: lewat
                              ? AppColors.danger
                              : AppColors.textSecondaryOf(context))),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigasiHalaman(BuildContext context, int maksHalaman) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: AppColors.cardBgOf(context),
            border:
                Border(top: BorderSide(color: AppColors.borderOf(context)))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _halaman <= 1
                  ? null
                  : () {
                      setState(() => _halaman--);
                      _muat();
                    },
            ),
            Text('Halaman $_halaman dari $maksHalaman  ($_total data)',
                style: const TextStyle(fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _halaman >= maksHalaman
                  ? null
                  : () {
                      setState(() => _halaman++);
                      _muat();
                    },
            ),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// DIALOG FILTER GLOBAL
// ════════════════════════════════════════════════════════════════════════════

class _DialogFilter extends StatefulWidget {
  final FilterPengajuan awal;
  const _DialogFilter({required this.awal});

  @override
  State<_DialogFilter> createState() => _DialogFilterState();
}

class _DialogFilterState extends State<_DialogFilter> {
  DateTime? _mulai;
  DateTime? _sampai;
  late final TextEditingController _cari;

  @override
  void initState() {
    super.initState();
    _mulai = widget.awal.mulai;
    _sampai = widget.awal.sampai;
    _cari = TextEditingController(text: widget.awal.keyword);
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _pilih(bool awal) async {
    final kini = DateTime.now();
    final hasil = await showDatePicker(
      context: context,
      initialDate: (awal ? _mulai : _sampai) ?? kini,
      firstDate: DateTime(kini.year - 6),
      lastDate: DateTime(kini.year + 2),
    );
    if (hasil == null || !mounted) return;
    setState(() {
      if (awal) {
        _mulai = hasil;
      } else {
        _sampai = hasil;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter Dasbor SOP'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Kosongkan tanggal untuk menampilkan SELURUH periode -- sama '
                'seperti perilaku bawaan dasbor versi ZKoss.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(
                        _mulai == null ? 'Mulai' : _tglTampil(_mulai!),
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _pilih(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(
                        _sampai == null ? 'Sampai' : _tglTampil(_sampai!),
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _pilih(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cari,
              decoration: const InputDecoration(
                labelText: 'Cari',
                helperText:
                    'Nama SOP, properti, keyword, tahap, petugas, catatan, atau pengaju',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const FilterPengajuan()),
          child: const Text('Bersihkan'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
              context,
              FilterPengajuan(
                  mulai: _mulai, sampai: _sampai, keyword: _cari.text)),
          child: const Text('Tampilkan'),
        ),
      ],
    );
  }
}
