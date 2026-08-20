import 'package:flutter/material.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../widgets/indikator_baris_sinkron.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

/// Layar "Jenis Produk" (kategori) — padanan master ZK `JenisProdukAction` &
/// JSP `barang/jenis_produk.jsp`. CRUD penuh + pemilihan 3 akun akuntansi per
/// jenis produk (Pendapatan Penjualan, PPN Keluaran, HPP) yang dipakai fitur
/// Posting Penjualan/HPP Kantin di server. Akun dikirim sebagai id (server
/// me-resolve ke entitas Akun), pola sama seperti versi JSP & Desktop.
class JenisProdukScreen extends StatefulWidget {
  const JenisProdukScreen({super.key});
  @override
  State<JenisProdukScreen> createState() => _JenisProdukScreenState();
}

class _JenisProdukScreenState extends State<JenisProdukScreen> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  @override
  void initState() {
    super.initState();
    _muatDaftar();
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('jenis_produk_list', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
        'termasuk_nonaktif': true,
      }, 'master:jenis_produk', onData: (hasil) {
        if (!mounted) return;
        final data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _daftar = data;
          _total = dariServer
              ? (hasil['total'] as num?)?.toInt() ?? data.length
              : data.length;
          _idBaru = dariServer
              ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(
                  hasil['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus =
              dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
          if (dariServer &&
              (_idBaru.isNotEmpty ||
                  _idBerubah.isNotEmpty ||
                  _jumlahHapus > 0)) {
            _versiPerubahan++;
          }
          _memuat = false;
        });
      });
    } catch (e) {
      if (mounted) setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cariUlang(String v) async {
    setStateIfMounted(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muatDaftar();
  }

  Future<void> _bukaForm({Map<String, dynamic>? jenis}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormJenisProduk(jenis: jenis),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> jenis) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Jenis Produk?'),
        content: Text(
            'Jenis "${jenis['nama']}" akan dihapus. Kalau masih dipakai produk, penghapusan akan ditolak — nonaktifkan saja sebagai gantinya.'),
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
    if (konfirmasi != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'jenis_produk_hapus',
        body: {'id': jenis['id']},
        kunci: 'jenis_produk:${jenis['id']}',
        cacheKey: 'master:jenis_produk',
        rowLokal: {'id': jenis['id']},
        hapusLokal: true,
      );
      await _muatDaftar();
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
    return AppShell(
      menuAktif: MenuEBisnis.jenisProduk,
      judul: 'Jenis Produk',
      subjudul: 'Kelola kategori produk & akun akuntansinya',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar)
      ],
      aksiHeader:
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _muatDaftar,
                            child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muatDaftar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppSearchField(
                              hintText: 'Cari nama jenis produk...',
                              debounce: const Duration(milliseconds: 450),
                              onChanged: _cariUlang,
                            ),
                          ),
                          if (Sesi.instance.bolehKelola) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _bukaForm(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Tambah Jenis'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      BannerPerubahanServer(
                        key: ValueKey('perubahan:$_versiPerubahan'),
                        baru: _idBaru.length,
                        berubah: _idBerubah.length,
                        dihapus: _jumlahHapus,
                      ),
                      AppDataTable(
                        minWidth: 820,
                        emptyText: 'Belum ada jenis produk.',
                        columns: [
                          const AppTableColumn('Nama', flex: 2),
                          const AppTableColumn('Akun Pendapatan', flex: 2),
                          const AppTableColumn('Maks. Harian',
                              flex: 1, align: TextAlign.right),
                          const AppTableColumn('Default',
                              flex: 1, align: TextAlign.center),
                          const AppTableColumn('Status',
                              flex: 1, align: TextAlign.center),
                          AppTableColumn('Aksi',
                              width: Sesi.instance.bolehKelola ? 124 : 56,
                              align: TextAlign.center),
                        ],
                        rows: _daftar.map((j) {
                          final aktif = j['aktif'] == true;
                          final isDefault = j['defaultProduk'] == true;
                          final maks =
                              (j['maksimalHarian'] as num?)?.toDouble() ?? 0;
                          return AppTableRowData(
                            onTap: Sesi.instance.bolehKelola
                                ? () => _bukaForm(jenis: j)
                                : null,
                            cells: [
                              AppTableCell(
                                flex: 2,
                                child: KilauBaris(
                                  kunci: '${j['id'] ?? j['_kunci'] ?? ''}',
                                  idBaru: _idBaru,
                                  idBerubah: _idBerubah,
                                  child: SelTeksDenganSinkron(
                                    kunci: kunciBarisMaster('jenis_produk', j),
                                    teks: '${j['nama'] ?? ''}',
                                  ),
                                ),
                              ),
                              AppTableCell.text(
                                  '${j['akunPendapatanNama'] ?? '-'}',
                                  flex: 2),
                              AppTableCell.text(
                                  maks > 0 ? maks.toStringAsFixed(0) : '-',
                                  flex: 1,
                                  align: TextAlign.right),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                  label: isDefault ? 'Ya' : 'Tidak',
                                  warna: isDefault
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                  label: aktif ? 'Aktif' : 'Nonaktif',
                                  warna: aktif
                                      ? AppColors.success
                                      : AppColors.textSecondary,
                                ),
                              ),
                              AppTableCell(
                                width: Sesi.instance.bolehKelola ? 124 : 56,
                                align: TextAlign.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (j['id'] != null)
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip:
                                            'Riwayat data ini (AuditTrails)',
                                        icon: const Icon(Icons.history,
                                            size: 18),
                                        onPressed: () => tampilkanRiwayatData(
                                            context,
                                            entitas: 'jenis_produk',
                                            id: j['id'],
                                            judul: '${j['nama'] ?? ''}'),
                                      ),
                                    if (Sesi.instance.bolehKelola) ...[
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        onPressed: () => _bukaForm(jenis: j),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18,
                                            color: AppColors.danger),
                                        onPressed: () => _hapus(j),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                        pagination: AppTablePagination(
                          halaman: _halaman,
                          totalHalaman: _totalHalaman,
                          totalData: _total,
                          labelData: 'jenis',
                          onSebelumnya: _halaman > 1
                              ? () => _pindahHalaman(_halaman - 1)
                              : null,
                          onBerikutnya: _halaman < _totalHalaman
                              ? () => _pindahHalaman(_halaman + 1)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _FormJenisProduk extends StatefulWidget {
  final Map<String, dynamic>? jenis;
  const _FormJenisProduk({required this.jenis});

  @override
  State<_FormJenisProduk> createState() => _FormJenisProdukState();
}

class _FormJenisProdukState extends State<_FormJenisProduk> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _maksHarian;
  bool _defaultProduk = false;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _pesanError;

  // Daftar akun untuk 3 pemilih (dimuat sekali dari server).
  bool _memuatAkun = true;
  List<Map<String, dynamic>> _akun = [];
  int? _akunPendapatanId;
  int? _akunPpnKeluaranId;
  int? _akunHppId;
  /// Akun selisih persediaan (susut/temuan) -- lawan jurnal stok opname.
  int? _akunSelisihPersediaanId;
  /// Akun retur penjualan (kontra-pendapatan); kosong = pakai akun pendapatan.
  int? _akunReturPenjualanId;

  @override
  void initState() {
    super.initState();
    final j = widget.jenis;
    _nama = TextEditingController(text: '${j?['nama'] ?? ''}');
    _keterangan = TextEditingController(text: '${j?['keterangan'] ?? ''}');
    final maks = (j?['maksimalHarian'] as num?)?.toDouble() ?? 0;
    _maksHarian =
        TextEditingController(text: maks > 0 ? maks.toStringAsFixed(0) : '');
    _defaultProduk = j?['defaultProduk'] == true;
    _aktif = j == null ? true : (j['aktif'] != false);
    _akunPendapatanId = (j?['akunPendapatanId'] as num?)?.toInt();
    _akunPpnKeluaranId = (j?['akunPpnKeluaranId'] as num?)?.toInt();
    _akunHppId = (j?['akunHppId'] as num?)?.toInt();
    _akunSelisihPersediaanId = (j?['akunSelisihPersediaanId'] as num?)?.toInt();
    _akunReturPenjualanId = (j?['akunReturPenjualanId'] as num?)?.toInt();
    _muatAkun();
  }

  Future<void> _muatAkun() async {
    try {
      final hasil = await MasterOffline.daftarDenganCache(
          'akun_list', {'limit': 2000}, 'master:akun_list');
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setStateIfMounted(() => _akun = data);
    } catch (e) {
      if (mounted) setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuatAkun = false);
    }
  }

  @override
  void dispose() {
    _nama.dispose();
    _keterangan.dispose();
    _maksHarian.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final maks =
          double.tryParse(_maksHarian.text.trim().replaceAll(',', '.'));
      final body = {
        if (widget.jenis != null) 'id': widget.jenis!['id'],
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'maksimalHarian': maks,
        'defaultProduk': _defaultProduk,
        'aktif': _aktif,
        'akunPendapatanId': _akunPendapatanId,
        'akunPpnKeluaranId': _akunPpnKeluaranId,
        'akunHppId': _akunHppId,
        'akunSelisihPersediaanId': _akunSelisihPersediaanId,
        'akunReturPenjualanId': _akunReturPenjualanId,
      };
      await prosesSimpanMaster(
        context,
        aksi: 'jenis_produk_simpan',
        body: body,
        kunci: widget.jenis != null
            ? 'jenis_produk:${widget.jenis!['id']}'
            : 'jenis_produk:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:jenis_produk',
        rowLokal: body,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.jenis != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Jenis Produk' : 'Tambah Jenis Produk',
            subtitle: 'Atur kategori produk & akun akuntansinya.',
            icon: Icons.category_outlined,
            errorText: _pesanError,
            children: [
              AppFormSection(
                judul: 'Identitas',
                children: [
                  AppFormTextField(
                    label: 'Nama *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 2),
                  AppFormTextField(
                      label: 'Maksimal Harian', controller: _maksHarian),
                ],
              ),
              AppFormSection(
                judul: 'Akun Akuntansi (Posting Jurnal Kantin)',
                children: [
                  if (_memuatAkun)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Memuat daftar akun...'),
                      ]),
                    )
                  else ...[
                    // Dropdown diganti pemilih bercari: bagan akun bisa ratusan
                    // baris, jadi pencarian kode/nama jauh lebih cepat.
                    PemilihAkunField(
                      label: 'Akun Pendapatan Penjualan',
                      daftar: _akun,
                      nilai: _akunPendapatanId,
                      helperText: 'Ketik kode atau nama akun untuk mencari.',
                      onChanged: (v) =>
                          setStateIfMounted(() => _akunPendapatanId = v),
                    ),
                    const SizedBox(height: 12),
                    PemilihAkunField(
                      label: 'Akun PPN Keluaran',
                      daftar: _akun,
                      nilai: _akunPpnKeluaranId,
                      onChanged: (v) =>
                          setStateIfMounted(() => _akunPpnKeluaranId = v),
                    ),
                    const SizedBox(height: 12),
                    PemilihAkunField(
                      label: 'Akun HPP (Beban Pokok Penjualan)',
                      daftar: _akun,
                      nilai: _akunHppId,
                      onChanged: (v) => setStateIfMounted(() => _akunHppId = v),
                    ),
                    const SizedBox(height: 12),
                    PemilihAkunField(
                      label: 'Akun Retur Penjualan',
                      daftar: _akun,
                      nilai: _akunReturPenjualanId,
                      helperText: 'Didebet saat retur penjualan dijurnal. '
                          'Kosongkan untuk memakai Akun Pendapatan di atas.',
                      onChanged: (v) =>
                          setStateIfMounted(() => _akunReturPenjualanId = v),
                    ),
                    const SizedBox(height: 12),
                    PemilihAkunField(
                      label: 'Akun Selisih Persediaan',
                      daftar: _akun,
                      nilai: _akunSelisihPersediaanId,
                      helperText: 'Lawan jurnal saat selisih stok opname diposting '
                          '(susut atau temuan barang).',
                      onChanged: (v) =>
                          setStateIfMounted(() => _akunSelisihPersediaanId = v),
                    ),
                  ],
                ],
              ),
              AppFormSection(
                judul: 'Opsi',
                children: [
                  AppFormSwitchTile(
                      title: 'Jadikan Default',
                      value: _defaultProduk,
                      onChanged: (v) =>
                          setStateIfMounted(() => _defaultProduk = v)),
                  AppFormSwitchTile(
                      title: 'Aktif',
                      value: _aktif,
                      onChanged: (v) => setStateIfMounted(() => _aktif = v)),
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
                        child: CircularProgressIndicator(strokeWidth: 2))
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
