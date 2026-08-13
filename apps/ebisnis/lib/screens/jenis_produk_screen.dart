import 'package:flutter/material.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
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
      final hasil = await ApiClient.instance.aksi('jenis_produk_list', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
        'termasuk_nonaktif': true,
      });
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        setStateIfMounted(() {
          _daftar = data;
          _total = (hasil['total'] as num?)?.toInt() ?? 0;
        });
      }
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
    if (konfirmasi != true) return;
    try {
      await ApiClient.instance.aksi('jenis_produk_hapus', {'id': jenis['id']});
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
                              width: Sesi.instance.bolehKelola ? 88 : 56,
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
                              AppTableCell.text('${j['nama'] ?? ''}', flex: 2),
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
                                width: Sesi.instance.bolehKelola ? 88 : 56,
                                align: TextAlign.center,
                                child: Sesi.instance.bolehKelola
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18),
                                            onPressed: () =>
                                                _bukaForm(jenis: j),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.danger),
                                            onPressed: () => _hapus(j),
                                          ),
                                        ],
                                      )
                                    : const Icon(Icons.visibility_outlined,
                                        size: 18),
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
    _muatAkun();
  }

  Future<void> _muatAkun() async {
    try {
      final hasil = await ApiClient.instance.aksi('akun_list', {'limit': 2000});
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

  List<DropdownMenuItem<int?>> _itemsAkun() {
    return [
      const DropdownMenuItem<int?>(
          value: null, child: Text('-- Tidak dipilih --')),
      ..._akun.map((a) => DropdownMenuItem<int?>(
            value: (a['id'] as num).toInt(),
            child: Text('${a['label'] ?? a['nama'] ?? ''}',
                overflow: TextOverflow.ellipsis),
          )),
    ];
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
      await ApiClient.instance.aksi('jenis_produk_simpan', {
        if (widget.jenis != null) 'id': widget.jenis!['id'],
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'maksimalHarian': maks,
        'defaultProduk': _defaultProduk,
        'aktif': _aktif,
        'akunPendapatanId': _akunPendapatanId,
        'akunPpnKeluaranId': _akunPpnKeluaranId,
        'akunHppId': _akunHppId,
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
                    DropdownButtonFormField<int?>(
                      value: _akunPendapatanId,
                      isExpanded: true,
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Akun Pendapatan Penjualan'),
                      items: _itemsAkun(),
                      onChanged: (v) =>
                          setStateIfMounted(() => _akunPendapatanId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _akunPpnKeluaranId,
                      isExpanded: true,
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Akun PPN Keluaran'),
                      items: _itemsAkun(),
                      onChanged: (v) =>
                          setStateIfMounted(() => _akunPpnKeluaranId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _akunHppId,
                      isExpanded: true,
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Akun HPP (Beban Pokok Penjualan)'),
                      items: _itemsAkun(),
                      onChanged: (v) => setStateIfMounted(() => _akunHppId = v),
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
