import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/safe_state.dart';

/// Layar Customer/Anggota (padanan anggota.html/anggota-renderer.js Electron)
/// -- BEDA dari Produk: daftarnya paginasi SERVER-SIDE (aksi `anggota_list`
/// sudah menerima page/page_size sendiri, bukan client-side spt katalog).
///
/// Tombol "Sinkronkan" mengisi `anggota_cache` lokal (aksi `anggota_sync_list`,
/// cursor `sejak_id` diulang sampai `adaLagi=false`) -- inilah yang membuat
/// picker member offline di layar Kasir (lihat KeranjangScreen._DialogPilihMember)
/// akhirnya punya isi; sebelum tombol ini pernah ditekan, cache itu selalu kosong.
class AnggotaScreen extends StatefulWidget {
  const AnggotaScreen({super.key});

  @override
  State<AnggotaScreen> createState() => _AnggotaScreenState();
}

class _AnggotaScreenState extends State<AnggotaScreen> {
  bool _memuat = true;
  bool _sinkronBerjalan = false;
  String? _pesanError;
  List<Anggota> _daftar = [];
  List<Kategori> _jenisAnggota = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  Map<String, dynamic>? _statistik;

  static const _pageSize = 20;

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
      await Future.wait([_muatDaftar(), _muatJenis(), _muatStatistik()]);
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatDaftar() async {
    try {
      final hasil = await ApiClient.instance.aksi('anggota_list', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize
      });
      final data = ((hasil['data'] as List?) ?? [])
          .map((e) => Anggota.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setStateIfMounted(() {
          _daftar = data;
          _total = (hasil['total'] as num?)?.toInt() ?? 0;
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

  Future<void> _bukaFormAnggota({Anggota? anggota}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _FormAnggota(anggota: anggota, jenisAnggota: _jenisAnggota),
    );
    if (tersimpan == true) await _muatSemua();
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  List<Widget> get _tombolAksi => [
        HeaderActionButton(
          icon: Icons.cloud_sync_outlined,
          label: 'Sinkron',
          onPressed: _sinkronBerjalan ? null : _sinkronkanCacheOffline,
          tooltip: 'Sinkronkan ke cache offline (utk picker member Kasir)',
          loading: _sinkronBerjalan
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : null,
        ),
        HeaderActionButton(
          icon: Icons.refresh,
          label: 'Muat Ulang',
          onPressed: _muatSemua,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.anggota,
      judul: 'Pelanggan',
      subjudul: 'Kelola data member/pelanggan toko Anda',
      scrollable: false,
      actionsAppBar: _tombolAksi,
      aksiHeader: Wrap(
        alignment: WrapAlignment.end,
        runSpacing: 8,
        children: _tombolAksi,
      ),
      floatingActionButton: Sesi.instance.bolehKelola
          ? FloatingActionButton.extended(
              onPressed: () => _bukaFormAnggota(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Member'),
            )
          : null,
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
                            onPressed: _muatSemua,
                            child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muatSemua,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      if (_statistik != null)
                        _KartuStatistikAnggota(statistik: _statistik!),
                      const SizedBox(height: 12),
                      AppSearchField(
                        hintText: 'Cari nama/kode/kode identitas...',
                        debounce: const Duration(milliseconds: 450),
                        onChanged: _cariUlang,
                      ),
                      const SizedBox(height: 12),
                      _tabelAnggota(),
                    ],
                  ),
                ),
    );
  }

  Widget _tabelAnggota() {
    return AppDataTable(
      minWidth: 980,
      emptyText: 'Belum ada member.',
      columns: const [
        AppTableColumn('Nama', flex: 3),
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Identitas', flex: 2),
        AppTableColumn('Jenis', flex: 2),
        AppTableColumn('Kontak', flex: 3),
        AppTableColumn('Status', flex: 2, align: TextAlign.center),
        AppTableColumn('Aksi', width: 72, align: TextAlign.center),
      ],
      rows: _daftar.map((a) {
        final kontak = [
          if (a.hp.trim().isNotEmpty) a.hp.trim(),
          if (a.telp.trim().isNotEmpty) a.telp.trim(),
          if (a.email.trim().isNotEmpty) a.email.trim(),
        ].join(' / ');
        final warnaStatus =
            a.aktif ? AppColors.success : AppColors.textSecondary;

        return AppTableRowData(
          onTap: Sesi.instance.bolehKelola
              ? () => _bukaFormAnggota(anggota: a)
              : null,
          cells: [
            AppTableCell(
              flex: 3,
              child: Row(
                children: [
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
              a.jenisNama.isEmpty ? 'Tanpa Jenis' : a.jenisNama,
              flex: 2,
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
              width: 72,
              align: TextAlign.center,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip:
                    Sesi.instance.bolehKelola ? 'Ubah member' : 'Detail member',
                icon: Icon(
                  Sesi.instance.bolehKelola
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: Sesi.instance.bolehKelola
                    ? () => _bukaFormAnggota(anggota: a)
                    : null,
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
  const _FormAnggota({required this.anggota, required this.jenisAnggota});

  @override
  State<_FormAnggota> createState() => _FormAnggotaState();
}

class _FormAnggotaState extends State<_FormAnggota> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _kodeIdentitas;
  late final TextEditingController _hp;
  late final TextEditingController _telp;
  late final TextEditingController _email;
  late final TextEditingController _keterangan;
  int? _jenisId;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final a = widget.anggota;
    _nama = TextEditingController(text: a?.nama ?? '');
    _kodeIdentitas = TextEditingController(text: a?.kodeIdentitas ?? '');
    _hp = TextEditingController(text: a?.hp ?? '');
    _telp = TextEditingController(text: a?.telp ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _keterangan = TextEditingController(text: a?.keterangan ?? '');
    _jenisId = a?.jenisAnggotaKoperasiId;
    _aktif = a?.aktif ?? true;
  }

  @override
  void dispose() {
    _nama.dispose();
    _kodeIdentitas.dispose();
    _hp.dispose();
    _telp.dispose();
    _email.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      await ApiClient.instance.aksi('anggota_simpan', {
        if (widget.anggota != null) 'id': widget.anggota!.id,
        'nama': _nama.text.trim(),
        'kode_identitas': _kodeIdentitas.text.trim(),
        'hp': _hp.text.trim(),
        'telp': _telp.text.trim(),
        'email': _email.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'jenis_anggota_koperasi_id': _jenisId,
        'aktif': _aktif,
      });
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
        initialChildSize: 0.8,
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
            children: [
              AppFormSection(
                judul: 'Identitas',
                deskripsi: 'Data dasar pelanggan/member yang muncul di kasir dan laporan.',
                children: [
                  AppFormTextField(
                    label: 'Nama *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
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
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Kontak & Status',
                children: [
                  AppFormTextField(
                    label: 'No. HP',
                    controller: _hp,
                    keyboardType: TextInputType.phone,
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
                  AppFormSwitchTile(
                    title: 'Aktif',
                    value: _aktif,
                    onChanged: (v) => setStateIfMounted(() => _aktif = v),
                  ),
                ],
              ),
            ],
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
          ),
        ),
      ),
    );
  }
}
