import 'package:flutter/material.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

/// Layar "Cara Pembayaran" (padanan `cara_bayar/index.jsp`) -- CRUD penuh
/// metode pembayaran koperasi, termasuk toggle "Memotong Deposit" dan
/// "Masukkan sebagai Hutang" (piutang toko). BEDA dari `CaraBayar` read-only
/// (dropdown picker checkout, lib/models.dart) -- layar admin ini baru
/// dibangun di sini krn sebelumnya Desktop/Android TIDAK punya CRUD-nya sama
/// sekali (hanya JSP), padahal grid Hak Akses Pedagang sudah lama menyediakan
/// kunci CRUD "pembayaran" tanpa ada layar yang memakainya.
class CaraBayarScreen extends StatefulWidget {
  const CaraBayarScreen({super.key});
  @override
  State<CaraBayarScreen> createState() => _CaraBayarScreenState();
}

class _CaraBayarScreenState extends State<CaraBayarScreen> {
  static const _pageSize = 20;
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
      final hasil = await ApiClient.instance.aksi('cara_bayar_list_admin', {
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

  Future<void> _bukaForm({Map<String, dynamic>? cara}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormCaraBayar(cara: cara),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> cara) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Metode Pembayaran?'),
        content: Text(
            'Metode "${cara['nama']}" akan dihapus. Kalau sudah pernah dipakai transaksi, penghapusan akan ditolak -- nonaktifkan saja sebagai gantinya.'),
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
      await ApiClient.instance.aksi('cara_bayar_hapus', {'id': cara['id']});
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
      menuAktif: MenuEBisnis.caraBayar,
      judul: 'Cara Pembayaran',
      subjudul: 'Kelola metode pembayaran koperasi/kantin',
      scrollable: false,
      actionsAppBar: [IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar)],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
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
                              hintText: 'Cari kode/nama metode...',
                              debounce: const Duration(milliseconds: 450),
                              onChanged: _cariUlang,
                            ),
                          ),
                          if (Sesi.instance.bolehKelola) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _bukaForm(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Tambah Metode'),
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
                        emptyText: 'Belum ada metode pembayaran.',
                        columns: [
                          const AppTableColumn('Kode', flex: 1),
                          const AppTableColumn('Nama', flex: 2),
                          const AppTableColumn('Potong Saldo',
                              flex: 1, align: TextAlign.center),
                          const AppTableColumn('Hutang',
                              flex: 1, align: TextAlign.center),
                          const AppTableColumn('Kembalian',
                              flex: 1, align: TextAlign.center),
                          const AppTableColumn('Status',
                              flex: 1, align: TextAlign.center),
                          AppTableColumn('Aksi',
                              width: Sesi.instance.bolehKelola ? 88 : 56,
                              align: TextAlign.center),
                        ],
                        rows: _daftar.map((c) {
                          final aktif = c['aktif'] == true;
                          final memotong = c['memotongDeposit'] == true;
                          final hutang = c['masukSebagaiHutang'] == true;
                          final kembalian = c['adaKembalian'] == true;
                          return AppTableRowData(
                            onTap: Sesi.instance.bolehKelola
                                ? () => _bukaForm(cara: c)
                                : null,
                            cells: [
                              AppTableCell.text('${c['kode'] ?? '-'}', flex: 1),
                              AppTableCell.text('${c['nama'] ?? ''}', flex: 2),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                  label: memotong ? 'Ya' : 'Tidak',
                                  warna: memotong
                                      ? AppColors.warning
                                      : AppColors.textSecondary,
                                ),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                  label: hutang ? 'Ya' : 'Tidak',
                                  warna: hutang
                                      ? AppColors.danger
                                      : AppColors.textSecondary,
                                ),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                  label: kembalian ? 'Ya' : 'Tidak',
                                  warna: kembalian
                                      ? AppColors.success
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
                                            visualDensity: VisualDensity.compact,
                                            icon: const Icon(Icons.edit_outlined,
                                                size: 18),
                                            onPressed: () => _bukaForm(cara: c),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.danger),
                                            onPressed: () => _hapus(c),
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
                          labelData: 'metode',
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

class _FormCaraBayar extends StatefulWidget {
  final Map<String, dynamic>? cara;
  const _FormCaraBayar({required this.cara});

  @override
  State<_FormCaraBayar> createState() => _FormCaraBayarState();
}

class _FormCaraBayarState extends State<_FormCaraBayar> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  bool _manual = true;
  bool _online = false;
  bool _memotongDeposit = false;
  bool _masukSebagaiHutang = false;
  bool _adaKembalian = false;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _pesanError;

  // Gap-closure "Ada Kembalian" -- selama admin belum menyentuh switch-nya sendiri di form Tambah,
  // ikuti field Nama secara live (ilike "tunai" -> Ya). Sekali disentuh manual (atau form Ubah
  // dibuka dgn data existing), berhenti auto-mengikuti -- pola sama dgn JSP/Electron.
  bool _kembalianDisentuhManual = false;

  @override
  void initState() {
    super.initState();
    final c = widget.cara;
    _kode = TextEditingController(text: '${c?['kode'] ?? ''}');
    _nama = TextEditingController(text: '${c?['nama'] ?? ''}');
    _keterangan = TextEditingController(text: '${c?['keterangan'] ?? ''}');
    _manual = c == null ? true : (c['manual'] != false);
    _online = c?['online'] == true;
    _memotongDeposit = c?['memotongDeposit'] == true;
    _masukSebagaiHutang = c?['masukSebagaiHutang'] == true;
    if (c == null) {
      _adaKembalian = false; // nama masih kosong -- mengikuti field Nama begitu diketik
    } else {
      _adaKembalian = c['adaKembalian'] == true; // nilai final dari server (sudah di-COALESCE)
      _kembalianDisentuhManual = true;
    }
    _aktif = c == null ? true : (c['aktif'] != false);
    _nama.addListener(() {
      if (!_kembalianDisentuhManual) {
        final ikutTunai = _nama.text.trim().toLowerCase().contains('tunai');
        if (ikutTunai != _adaKembalian) {
          setStateIfMounted(() => _adaKembalian = ikutTunai);
        }
      }
    });
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
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
      await ApiClient.instance.aksi('cara_bayar_simpan', {
        if (widget.cara != null) 'id': widget.cara!['id'],
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'manual': _manual,
        'online': _online,
        'memotongDeposit': _memotongDeposit,
        'masukSebagaiHutang': _masukSebagaiHutang,
        'adaKembalian': _adaKembalian,
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
    final ubah = widget.cara != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Metode Pembayaran' : 'Tambah Metode Pembayaran',
            subtitle: 'Atur cara pembayaran koperasi/kantin.',
            icon: Icons.payments_outlined,
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
                  AppFormTextField(
                      label: 'Keterangan', controller: _keterangan, maxLines: 2),
                ],
              ),
              AppFormSection(
                judul: 'Perilaku',
                children: [
                  AppFormSwitchTile(
                      title: 'Verifikasi Manual',
                      subtitle: 'Aktif = butuh verifikasi admin (mis. transfer bank).',
                      value: _manual,
                      onChanged: (v) => setStateIfMounted(() => _manual = v)),
                  AppFormSwitchTile(
                      title: 'Pembayaran Online',
                      value: _online,
                      onChanged: (v) => setStateIfMounted(() => _online = v)),
                  AppFormSwitchTile(
                      title: 'Memotong Deposit',
                      subtitle: 'Transaksi dgn metode ini memotong saldo tabungan anggota.',
                      value: _memotongDeposit,
                      onChanged: (v) =>
                          setStateIfMounted(() => _memotongDeposit = v)),
                ],
              ),
              AppFormSection(
                judul: 'Hutang',
                children: [
                  AppFormSwitchTile(
                    title: 'Masukkan sebagai Hutang',
                    subtitle:
                        'Transaksi dgn metode ini dicatat sebagai HUTANG pelanggan (piutang toko), bukan lunas. Dibatasi oleh field "Maksimal Boleh Utang" pada Tipe Member.',
                    value: _masukSebagaiHutang,
                    onChanged: (v) =>
                        setStateIfMounted(() => _masukSebagaiHutang = v),
                  ),
                ],
              ),
              AppFormSection(
                judul: 'Kembalian',
                children: [
                  AppFormSwitchTile(
                    title: 'Ada Kembalian',
                    subtitle:
                        'Aktif = kasir boleh menerima uang lebih dari total lalu mengembalikan sisanya (spt Tunai). Nonaktif = pembayaran wajib pas, tanpa kembalian (spt QRIS/Transfer/Kasbon).',
                    value: _adaKembalian,
                    onChanged: (v) => setStateIfMounted(() {
                      _adaKembalian = v;
                      _kembalianDisentuhManual = true;
                    }),
                  ),
                ],
              ),
              AppFormSection(
                judul: 'Status',
                children: [
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
