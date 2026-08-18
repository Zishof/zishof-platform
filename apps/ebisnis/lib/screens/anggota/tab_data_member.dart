import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../models.dart';
import '../../services/master_offline.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';

final _formatTanggalKadaluarsa = DateFormat('dd-MM-yyyy');

/// Tab "Data Member Baru" (padanan `anggota_koperasi.jsp`) -- daftar/CRUD
/// member koperasi, sisi paling lengkap dari layar Pelanggan. Sama dgn
/// versi sebelum tab-tab lain ditambahkan, PLUS: hapus member (`anggota_hapus`,
/// baru), field tambahan di form (tipe/kategori sivitas, tanggal kadaluarsa,
/// kode manual saat ubah, userid/pass opsional) utk paritas JSP.
///
/// TIDAK diporting dari JSP: penampil password (dekripsi plaintext ke UI --
/// pola tak aman yg sengaja tak direplikasi) dan tombol kirim-notifikasi
/// per-baris/massal (fitur terpisah, di luar cakupan 6 tab yg diminta).
class AnggotaTabDataMember extends StatefulWidget {
  const AnggotaTabDataMember({super.key});

  @override
  State<AnggotaTabDataMember> createState() => _AnggotaTabDataMemberState();
}

class _AnggotaTabDataMemberState extends State<AnggotaTabDataMember> {
  bool _memuat = true;
  bool _sinkronBerjalan = false;
  bool _memulaiDataSample = false;
  String? _pesanError;
  List<Anggota> _daftar = [];
  List<Kategori> _jenisAnggota = [];
  List<Kategori> _tipeAnggota = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  Map<String, dynamic>? _statistik;

  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      await Future.wait(
          [_muatDaftar(), _muatJenis(), _muatTipe(), _muatStatistik()]);
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatDaftar() async {
    try {
      // Offline-first: fetch sukses menyimpan snapshot ke cache lokal;
      // saat offline snapshot terakhir yang tampil (lihat MasterOffline).
      final hasil = await MasterOffline.daftarDenganCache('anggota_list', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize
      }, 'master:anggota');
      final data = ((hasil['data'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          // Draf create offline belum punya id -- model Anggota mensyaratkan
          // id int, jadi baris draf dilewati sampai tersinkron ke server.
          .where((e) => e['id'] is int)
          .map(Anggota.fromJson)
          .toList();
      if (mounted) {
        setStateIfMounted(() {
          _daftar = data;
          _total = hasil['offline'] == true
              ? data.length
              : (hasil['total'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      if (mounted) setStateIfMounted(() => _pesanError = e.toString());
    }
  }

  Future<void> _muatJenis() async {
    try {
      final hasil = await ApiClient.instance.aksi('jenis_anggota_list');
      final data = ((hasil['data'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setStateIfMounted(() => _jenisAnggota = data);
    } catch (_) {
      // Dropdown jenis gagal muat -- form tetap bisa dipakai tanpa memilih jenis.
    }
  }

  Future<void> _muatTipe() async {
    try {
      final hasil = await ApiClient.instance.aksi('tipe_anggota_list');
      final data = ((hasil['data'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setStateIfMounted(() => _tipeAnggota = data);
    } catch (_) {
      // Dropdown tipe gagal muat -- form tetap bisa dipakai tanpa memilih tipe.
    }
  }

  Future<void> _muatStatistik() async {
    try {
      final hasil = await ApiClient.instance.aksi('anggota_statistik');
      if (mounted) setStateIfMounted(() => _statistik = hasil);
    } catch (_) {
      // dasbor KPI gagal muat bukan blocker.
    }
  }

  Future<void> _cariUlang(String v) async {
    setStateIfMounted(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int halamanBaru) async {
    setStateIfMounted(() => _halaman = halamanBaru);
    await _muatDaftar();
  }

  Future<void> _sinkronkanCacheOffline() async {
    if (_sinkronBerjalan) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      var sejakId = 0;
      var totalTersinkron = 0;
      while (true) {
        final hasil = await ApiClient.instance
            .aksi('anggota_sync_list', {'sejak_id': sejakId, 'page_size': 500});
        final data = (hasil['data'] as List?) ?? [];
        if (data.isNotEmpty) {
          await CoreDb.instance.upsertAnggotaCache(data
              .map((e) => Anggota.keCacheRow(e as Map<String, dynamic>))
              .toList());
          totalTersinkron += data.length;
        }
        sejakId = (hasil['maksId'] as num?)?.toInt() ?? sejakId;
        if (hasil['adaLagi'] != true) break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('$totalTersinkron member tersinkron ke cache offline.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _sinkronBerjalan = false);
    }
  }

  Future<void> _mulaiDataSamplePelanggan() async {
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buat 100.000 pelanggan contoh?'),
        content: const Text(
            'Fitur ini hanya untuk toko demo/UAT. Nama pelanggan memakai nama Indonesia yang umum. Proses berjalan di server secara background dan aman ditekan ulang karena kode pelanggan bersifat idempoten.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Mulai')),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;
    setStateIfMounted(() => _memulaiDataSample = true);
    try {
      final hasil = await ApiClient.instance.aksi('pos_demo_seed_customers', {
        'toko_id': Sesi.instance.tokoId,
        'konfirmasi': 'SEED-DEMO-PELANGGAN-100000',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${hasil['description'] ?? 'Job 100.000 pelanggan contoh dimulai.'}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memulai data pelanggan: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memulaiDataSample = false);
    }
  }

  Future<void> _bukaFormAnggota({Anggota? anggota}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormAnggota(
        anggota: anggota,
        jenisAnggota: _jenisAnggota,
        tipeAnggota: _tipeAnggota,
      ),
    );
    if (tersimpan == true) await _muatSemua();
  }

  Future<void> _hapusAnggota(Anggota a) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Member?'),
        content: Text(
            'Member "${a.nama}" akan dihapus permanen. Kalau member ini punya riwayat transaksi/topup, penghapusan akan ditolak -- nonaktifkan saja sebagai gantinya.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      final hasil = await MasterOffline.simpanAtauAntre(
        'anggota_hapus',
        {'id': a.id},
        kunci: 'anggota:${a.id}',
        cacheKey: 'master:anggota',
        rowLokal: {'id': a.id},
        hapusLokal: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(hasil['offline'] == true
                ? 'Dihapus lokal — akan dikirim otomatis saat online.'
                : '${hasil['description'] ?? 'Member dihapus.'}')));
      }
      await _muatSemua();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

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
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_pesanError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _muatSemua, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muatSemua,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_statistik != null)
            _KartuStatistikAnggota(statistik: _statistik!),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari nama/kode/telepon/email...',
                  debounce: const Duration(milliseconds: 450),
                  onChanged: _cariUlang,
                ),
              ),
              const SizedBox(width: 8),
              if (Sesi.instance.bolehDataSample) ...[
                OutlinedButton.icon(
                  onPressed:
                      _memulaiDataSample ? null : _mulaiDataSamplePelanggan,
                  icon: _memulaiDataSample
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.science_outlined, size: 18),
                  label: Text(_memulaiDataSample
                      ? 'Memulai...'
                      : 'Sample 100K Pelanggan'),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: _sinkronBerjalan ? null : _sinkronkanCacheOffline,
                icon: _sinkronBerjalan
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_sync_outlined, size: 18),
                label: const Text('Sinkron'),
              ),
              if (Sesi.instance.bolehKelola) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _bukaFormAnggota(),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Tambah Member'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _tabelAnggota(),
        ],
      ),
    );
  }

  Widget _tabelAnggota() {
    return AppDataTable(
      minWidth: 1040,
      emptyText: 'Belum ada member.',
      columns: [
        const AppTableColumn('Nama', flex: 3),
        const AppTableColumn('Kode', flex: 2),
        const AppTableColumn('Identitas', flex: 2),
        const AppTableColumn('Jenis / Tipe', flex: 2),
        const AppTableColumn('Kontak', flex: 3),
        const AppTableColumn('Status', flex: 2, align: TextAlign.center),
        AppTableColumn('Aksi',
            width: Sesi.instance.bolehKelola ? 96 : 56,
            align: TextAlign.center),
      ],
      rows: _daftar.map((a) {
        final kontak = [
          if (a.hp.trim().isNotEmpty) a.hp.trim(),
          if (a.telp.trim().isNotEmpty) a.telp.trim(),
          if (a.email.trim().isNotEmpty) a.email.trim(),
        ].join(' / ');
        final warnaStatus =
            a.aktif ? AppColors.success : AppColors.textSecondary;
        final jenisTipe = [
          if (a.jenisNama.isNotEmpty) a.jenisNama,
          if (a.tipeNama.isNotEmpty && a.tipeNama != '-') a.tipeNama,
        ].join(' · ');

        return AppTableRowData(
          onTap: Sesi.instance.bolehKelola
              ? () => _bukaFormAnggota(anggota: a)
              : null,
          cells: [
            AppTableCell(
              flex: 3,
              child: Row(
                children: [
                  IndikatorBarisSinkron(kunci: 'anggota:${a.id}'),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF1E3A5F),
                    child: Text(
                      a.nama.isNotEmpty ? a.nama[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      a.nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppTableCell.text(a.kode.isEmpty ? '-' : a.kode, flex: 2),
            AppTableCell.text(
              a.kodeIdentitas.isEmpty ? '-' : a.kodeIdentitas,
              flex: 2,
            ),
            AppTableCell.text(
              jenisTipe.isEmpty ? 'Tanpa Jenis' : jenisTipe,
              flex: 2,
              maxLines: 2,
            ),
            AppTableCell.text(
              kontak.isEmpty ? '-' : kontak,
              flex: 3,
              maxLines: 2,
            ),
            AppTableCell(
              flex: 2,
              align: TextAlign.center,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusPill(
                    label: a.aktif ? 'Aktif' : 'Nonaktif',
                    warna: warnaStatus,
                  ),
                  if (a.wajibPin)
                    const StatusPill(
                      label: 'Wajib PIN',
                      warna: AppColors.warning,
                    ),
                ],
              ),
            ),
            AppTableCell(
              width: Sesi.instance.bolehKelola ? 96 : 56,
              align: TextAlign.center,
              child: Sesi.instance.bolehKelola
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Ubah member',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _bukaFormAnggota(anggota: a),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Hapus member',
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppColors.danger),
                          onPressed: () => _hapusAnggota(a),
                        ),
                      ],
                    )
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Detail member',
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      onPressed: null,
                    ),
            ),
          ],
        );
      }).toList(),
      pagination: AppTablePagination(
        halaman: _halaman,
        totalHalaman: _totalHalaman,
        totalData: _total,
        labelData: 'member',
        onSebelumnya: _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
        onBerikutnya: _halaman < _totalHalaman
            ? () => _pindahHalaman(_halaman + 1)
            : null,
      ),
    );
  }
}

class _KartuStatistikAnggota extends StatelessWidget {
  final Map<String, dynamic> statistik;
  const _KartuStatistikAnggota({required this.statistik});

  @override
  Widget build(BuildContext context) {
    final item = <(IconData, String, String, Color)>[
      (
        Icons.people_outline,
        'Total',
        '${statistik['totalAnggota'] ?? 0}',
        AppColors.primary
      ),
      (
        Icons.check_circle_outline,
        'Aktif',
        '${statistik['totalAktif'] ?? 0}',
        AppColors.success
      ),
      (
        Icons.pause_circle_outline,
        'Nonaktif',
        '${statistik['totalNonaktif'] ?? 0}',
        AppColors.textSecondary
      ),
      (
        Icons.lock_outline,
        'Wajib PIN',
        '${statistik['totalWajibPin'] ?? 0}',
        AppColors.warning
      ),
    ];
    final byJenis =
        titikDariList(statistik['byJenis'] as List?, nilaiKey: 'jumlah');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: item.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (icon, label, nilai, warna) = item[i];
              return SizedBox(
                  width: 190,
                  child: AppKpiCard(
                      icon: icon, warna: warna, nilai: nilai, label: label));
            },
          ),
        ),
        if (byJenis.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionCard(
              judul: 'Anggota per Jenis Keanggotaan',
              child: BarHorizontal(data: byJenis, tampilkanPeringkat: false)),
        ],
      ],
    );
  }
}

class _FormAnggota extends StatefulWidget {
  final Anggota? anggota;
  final List<Kategori> jenisAnggota;
  final List<Kategori> tipeAnggota;
  const _FormAnggota({
    required this.anggota,
    required this.jenisAnggota,
    required this.tipeAnggota,
  });

  @override
  State<_FormAnggota> createState() => _FormAnggotaState();
}

class _FormAnggotaState extends State<_FormAnggota> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _kode;
  late final TextEditingController _kodeIdentitas;
  late final TextEditingController _hp;
  late final TextEditingController _telp;
  late final TextEditingController _email;
  late final TextEditingController _keterangan;
  late final TextEditingController _userid;
  late final TextEditingController _pass;
  int? _jenisId;
  int? _tipeId;
  bool _aktif = true;
  DateTime? _tanggalKadaluarsa;
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final a = widget.anggota;
    _nama = TextEditingController(text: a?.nama ?? '');
    _kode = TextEditingController(text: a?.kode ?? '');
    _kodeIdentitas = TextEditingController(text: a?.kodeIdentitas ?? '');
    _hp = TextEditingController(text: a?.hp ?? '');
    _telp = TextEditingController(text: a?.telp ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _keterangan = TextEditingController(text: a?.keterangan ?? '');
    _userid = TextEditingController(text: a?.userid ?? '');
    _pass = TextEditingController();
    _jenisId = a?.jenisAnggotaKoperasiId;
    _tipeId = a?.tipeAnggotaKoperasiId;
    _aktif = a?.aktif ?? true;
    if (a?.tanggalKadaluarsa != null && a!.tanggalKadaluarsa!.isNotEmpty) {
      try {
        _tanggalKadaluarsa = DateTime.parse(a.tanggalKadaluarsa!);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nama.dispose();
    _kode.dispose();
    _kodeIdentitas.dispose();
    _hp.dispose();
    _telp.dispose();
    _email.dispose();
    _keterangan.dispose();
    _userid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggalKadaluarsa() async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggalKadaluarsa ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (hasil != null) setStateIfMounted(() => _tanggalKadaluarsa = hasil);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final ubah = widget.anggota != null;
      final body = {
        if (ubah) 'id': widget.anggota!.id,
        'nama': _nama.text.trim(),
        if (ubah) 'kode': _kode.text.trim(),
        'kode_identitas': _kodeIdentitas.text.trim(),
        'hp': _hp.text.trim(),
        'telp': _telp.text.trim(),
        'email': _email.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'jenis_anggota_koperasi_id': _jenisId,
        'tipe_anggota_koperasi_id': _tipeId,
        'aktif': _aktif,
        'tanggal_kadaluarsa': _tanggalKadaluarsa == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_tanggalKadaluarsa!),
        if (_userid.text.trim().isNotEmpty) 'userid': _userid.text.trim(),
        if (_pass.text.trim().isNotEmpty) 'pass': _pass.text.trim(),
      };
      final hasil = await MasterOffline.simpanAtauAntre(
        'anggota_simpan',
        body,
        kunci: ubah
            ? 'anggota:${widget.anggota!.id}'
            : 'anggota:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:anggota',
        // Kata sandi cukup tersimpan di outbox utk replay -- jangan ikut
        // ke snapshot tampilan daftar.
        rowLokal: Map<String, dynamic>.from(body)..remove('pass'),
      );
      if (hasil['offline'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Tersimpan lokal — akan dikirim otomatis saat online.')));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.anggota != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Member' : 'Tambah Member Baru',
            subtitle: ubah
                ? 'Kode member: ${widget.anggota!.kode}'
                : 'Lengkapi identitas pelanggan/member agar transaksi dan laporan lebih mudah dilacak.',
            icon: ubah ? Icons.edit_outlined : Icons.person_add_alt_1_outlined,
            errorText: _pesanError,
            actions: [
              OutlinedButton.icon(
                onPressed:
                    _menyimpan ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
            children: [
              AppFormSection(
                judul: 'Identitas',
                deskripsi:
                    'Data dasar pelanggan/member yang muncul di kasir dan laporan.',
                children: [
                  AppFormTextField(
                    label: 'Nama *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  if (ubah)
                    AppFormTextField(
                      label: 'Kode Member (kosongkan utk biarkan apa adanya)',
                      controller: _kode,
                    ),
                  AppFormTextField(
                    label: 'Kode Identitas (NIS/NIM/dll)',
                    controller: _kodeIdentitas,
                  ),
                  DropdownButtonFormField<int?>(
                    value: _jenisId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Jenis Anggota',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('-- Tanpa Jenis --')),
                      ...widget.jenisAnggota.map((k) => DropdownMenuItem<int?>(
                          value: k.id, child: Text(k.nama))),
                    ],
                    onChanged: (v) => setStateIfMounted(() => _jenisId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _tipeId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Tipe Anggota (Kategori Sivitas)',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('-- Tanpa Tipe --')),
                      ...widget.tipeAnggota.map((k) => DropdownMenuItem<int?>(
                          value: k.id, child: Text(k.nama))),
                    ],
                    onChanged: (v) => setStateIfMounted(() => _tipeId = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Kontak & Status',
                children: [
                  AppFormTextField(
                    label: 'No. HP *',
                    controller: _hp,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final digit = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                      if (digit.isEmpty) return 'Nomor HP wajib diisi';
                      if (digit.length < 9 || digit.length > 16) {
                        return 'Nomor HP belum valid';
                      }
                      return null;
                    },
                  ),
                  AppFormTextField(
                    label: 'Telepon',
                    controller: _telp,
                    keyboardType: TextInputType.phone,
                  ),
                  AppFormTextField(
                    label: 'Email',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                    maxLines: 2,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihTanggalKadaluarsa,
                          icon: const Icon(Icons.event_busy, size: 16),
                          label: Text(
                            _tanggalKadaluarsa == null
                                ? 'Tanggal Kadaluarsa (opsional)'
                                : 'Kadaluarsa: ${_formatTanggalKadaluarsa.format(_tanggalKadaluarsa!)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_tanggalKadaluarsa != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setStateIfMounted(
                              () => _tanggalKadaluarsa = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppFormSwitchTile(
                    title: 'Aktif',
                    value: _aktif,
                    onChanged: (v) => setStateIfMounted(() => _aktif = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Kredensial Login (opsional)',
                deskripsi:
                    'Kosongkan bila member ini tidak perlu login sendiri (mis. portal member). Isi hanya bila ingin mengubah.',
                children: [
                  AppFormTextField(label: 'User ID', controller: _userid),
                  AppFormTextField(
                    label: 'Kata Sandi Baru',
                    controller: _pass,
                    obscureText: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
