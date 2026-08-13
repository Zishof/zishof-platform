import 'package:flutter/material.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

/// Layar "Supplier (Penyedia)" -- CRUD penuh master data pemasok, dipakai
/// sbg picker di Kulakan per-Faktur (`ais.database.model.library.Penyedia`).
/// Sebelum layar ini, Penyedia HANYA bisa ditambah lewat quick-add nama-saja
/// di dalam picker Kulakan (`penyedia_simpan` insert-only) -- tak ada layar
/// manajemen mandiri utk ubah/hapus/lihat kontak lengkap. `penyedia_simpan`
/// diperluas mendukung `id` (ubah), `penyedia_list_admin` (paginasi+semua
/// kolom) dan `penyedia_hapus` ditambah server-side khusus utk layar ini --
/// jalur quick-add lama di Kulakan TETAP jalan tanpa berubah.
class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});
  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
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
      final hasil = await ApiClient.instance.aksi('penyedia_list_admin', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
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

  Future<void> _bukaForm({Map<String, dynamic>? supplier}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormSupplier(supplier: supplier),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> supplier) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Supplier?'),
        content: Text(
            'Supplier "${supplier['nama']}" akan dihapus. Kalau sudah pernah dipakai di faktur Kulakan, penghapusan akan ditolak.'),
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
      await ApiClient.instance.aksi('penyedia_hapus', {'id': supplier['id']});
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
      menuAktif: MenuEBisnis.penyedia,
      judul: 'Supplier (Penyedia)',
      subjudul: 'Kelola data pemasok/vendor untuk Kulakan',
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
                              hintText: 'Cari kode/nama supplier...',
                              debounce: const Duration(milliseconds: 450),
                              onChanged: _cariUlang,
                            ),
                          ),
                          if (Sesi.instance.bolehKelola) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _bukaForm(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Tambah Supplier'),
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
                        minWidth: 860,
                        emptyText: 'Belum ada supplier.',
                        columns: [
                          const AppTableColumn('Kode', flex: 1),
                          const AppTableColumn('Nama', flex: 2),
                          const AppTableColumn('Kontak', flex: 2),
                          const AppTableColumn('Telp', flex: 1),
                          const AppTableColumn('Email', flex: 2),
                          AppTableColumn('Aksi',
                              width: Sesi.instance.bolehKelola ? 88 : 56,
                              align: TextAlign.center),
                        ],
                        rows: _daftar.map((s) {
                          return AppTableRowData(
                            onTap: Sesi.instance.bolehKelola
                                ? () => _bukaForm(supplier: s)
                                : null,
                            cells: [
                              AppTableCell.text('${s['kode'] ?? '-'}', flex: 1),
                              AppTableCell.text('${s['nama'] ?? ''}', flex: 2),
                              AppTableCell.text('${s['kontak'] ?? '-'}',
                                  flex: 2),
                              AppTableCell.text('${s['telp'] ?? '-'}', flex: 1),
                              AppTableCell.text('${s['email'] ?? '-'}',
                                  flex: 2),
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
                                                _bukaForm(supplier: s),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.danger),
                                            onPressed: () => _hapus(s),
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
                          labelData: 'supplier',
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

class _FormSupplier extends StatefulWidget {
  final Map<String, dynamic>? supplier;
  const _FormSupplier({required this.supplier});

  @override
  State<_FormSupplier> createState() => _FormSupplierState();
}

class _FormSupplierState extends State<_FormSupplier> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _kontak;
  late final TextEditingController _telp;
  late final TextEditingController _fax;
  late final TextEditingController _email;
  late final TextEditingController _alamat;
  late final TextEditingController _kodePos;
  late final TextEditingController _keterangan;
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _kode = TextEditingController(text: '${s?['kode'] ?? ''}');
    _nama = TextEditingController(text: '${s?['nama'] ?? ''}');
    _kontak = TextEditingController(text: '${s?['kontak'] ?? ''}');
    _telp = TextEditingController(text: '${s?['telp'] ?? ''}');
    _fax = TextEditingController(text: '${s?['fax'] ?? ''}');
    _email = TextEditingController(text: '${s?['email'] ?? ''}');
    _alamat = TextEditingController(text: '${s?['alamat'] ?? ''}');
    _kodePos = TextEditingController(text: '${s?['kode_pos'] ?? ''}');
    _keterangan = TextEditingController(text: '${s?['keterangan'] ?? ''}');
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _kontak.dispose();
    _telp.dispose();
    _fax.dispose();
    _email.dispose();
    _alamat.dispose();
    _kodePos.dispose();
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
      await ApiClient.instance.aksi('penyedia_simpan', {
        if (widget.supplier != null) 'id': widget.supplier!['id'],
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'kontak': _kontak.text.trim(),
        'telp': _telp.text.trim(),
        'fax': _fax.text.trim(),
        'email': _email.text.trim(),
        'alamat': _alamat.text.trim(),
        'kode_pos': _kodePos.text.trim(),
        'keterangan': _keterangan.text.trim(),
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
    final ubah = widget.supplier != null;
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
            title: ubah ? 'Ubah Supplier' : 'Tambah Supplier',
            subtitle: 'Data pemasok/vendor untuk faktur Kulakan.',
            icon: Icons.local_shipping_outlined,
            errorText: _pesanError,
            children: [
              AppFormSection(
                judul: 'Identitas',
                children: [
                  AppFormTextField(label: 'Kode', controller: _kode),
                  AppFormTextField(
                    label: 'Nama *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                ],
              ),
              AppFormSection(
                judul: 'Kontak',
                children: [
                  AppFormTextField(label: 'Nama Kontak', controller: _kontak),
                  AppFormTextField(
                    label: 'Telepon',
                    controller: _telp,
                    keyboardType: TextInputType.phone,
                  ),
                  AppFormTextField(label: 'Fax', controller: _fax),
                  AppFormTextField(
                    label: 'Email',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              AppFormSection(
                judul: 'Alamat',
                children: [
                  AppFormTextField(
                      label: 'Alamat', controller: _alamat, maxLines: 2),
                  AppFormTextField(label: 'Kode Pos', controller: _kodePos),
                ],
              ),
              AppFormSection(
                judul: 'Lainnya',
                children: [
                  AppFormTextField(
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 2),
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
