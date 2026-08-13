import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

/// Tab "Jenis Member" (padanan `jenis_anggota_koperasi.jsp`) -- klasifikasi
/// keanggotaan UTAMA yg mengatur aturan bisnis: label saldo/cashback, saldo
/// minimum, boleh-topup, tampil-saldo/cashback, wajib-belanja-rutin (target
/// frekuensi + maksimal pelanggaran), dan metode pembayaran yg boleh dipilih
/// member jenis ini. BEDA dari Tipe Member (tab sebelah, kategori tipis
/// tanpa aturan) -- lihat `AnggotaTabTipeMember`.
class AnggotaTabJenisMember extends StatefulWidget {
  const AnggotaTabJenisMember({super.key});

  @override
  State<AnggotaTabJenisMember> createState() => _AnggotaTabJenisMemberState();
}

class _AnggotaTabJenisMemberState extends State<AnggotaTabJenisMember> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  List<Map<String, dynamic>> _caraBayar = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
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
      await Future.wait([_muatDaftar(), _muatCaraBayar()]);
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatDaftar() async {
    try {
      final hasil = await ApiClient.instance.aksi('jenis_anggota_list_admin', {
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
      if (mounted) setStateIfMounted(() => _pesanError = e.toString());
    }
  }

  Future<void> _muatCaraBayar() async {
    try {
      final hasil = await ApiClient.instance.aksi('cara_bayar_list_semua');
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setStateIfMounted(() => _caraBayar = data);
    } catch (_) {
      // Daftar cara bayar gagal muat -- form tetap bisa dipakai tanpa checklist ini.
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
      builder: (_) => _FormJenisMember(jenis: jenis, caraBayar: _caraBayar),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> jenis) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Jenis Member?'),
        content: Text(
            'Jenis "${jenis['nama']}" dipakai ${jenis['jumlahAnggota'] ?? 0} member. Kalau masih dipakai, penghapusan akan ditolak -- nonaktifkan saja sebagai gantinya.'),
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
      await ApiClient.instance.aksi('jenis_anggota_hapus', {'id': jenis['id']});
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
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari kode/nama jenis...',
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
            minWidth: 900,
            emptyText: 'Belum ada jenis member.',
            columns: [
              const AppTableColumn('Kode', flex: 1),
              const AppTableColumn('Jenis & Istilah', flex: 3),
              const AppTableColumn('Aturan', flex: 3),
              const AppTableColumn('Status', flex: 1, align: TextAlign.center),
              AppTableColumn('Aksi',
                  width: Sesi.instance.bolehKelola ? 88 : 56,
                  align: TextAlign.center),
            ],
            rows: _daftar.map((j) {
              final aktif = j['aktif'] == true;
              return AppTableRowData(
                onTap: Sesi.instance.bolehKelola
                    ? () => _bukaForm(jenis: j)
                    : null,
                cells: [
                  AppTableCell.text('${j['kode'] ?? '-'}', flex: 1),
                  AppTableCell(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${j['nama'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        Text(
                            'Saldo: ${j['istilahSisaSaldo']} · Cashback: ${j['istilahCashback']}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  AppTableCell(
                    flex: 3,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (j['bolehEntryTopupOlehAdmin'] == true)
                          const StatusPill(
                              label: 'Boleh Topup', warna: AppColors.success),
                        if (j['wajibPin'] == true)
                          const StatusPill(
                              label: 'Wajib PIN', warna: AppColors.warning),
                        if (j['wajibBelanjaRutin'] == true)
                          StatusPill(
                              label:
                                  'Belanja Rutin ${j['targetFrekuensiBelanja'] ?? 0}x',
                              warna: AppColors.primary),
                      ],
                    ),
                  ),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: StatusPill(
                      label: aktif ? 'Aktif' : 'Nonaktif',
                      warna:
                          aktif ? AppColors.success : AppColors.textSecondary,
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
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _bukaForm(jenis: j),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.danger),
                                onPressed: () => _hapus(j),
                              ),
                            ],
                          )
                        : const Icon(Icons.visibility_outlined, size: 18),
                  ),
                ],
              );
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'jenis',
              onSebelumnya:
                  _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
              onBerikutnya: _halaman < _totalHalaman
                  ? () => _pindahHalaman(_halaman + 1)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormJenisMember extends StatefulWidget {
  final Map<String, dynamic>? jenis;
  final List<Map<String, dynamic>> caraBayar;
  const _FormJenisMember({required this.jenis, required this.caraBayar});

  @override
  State<_FormJenisMember> createState() => _FormJenisMemberState();
}

class _FormJenisMemberState extends State<_FormJenisMember> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _istilahSaldo;
  late final TextEditingController _istilahCashback;
  late final TextEditingController _minimalSaldo;
  late final TextEditingController _targetFrekuensi;
  late final TextEditingController _maksimalPelanggaran;
  bool _aktif = true;
  bool _dipilih = true;
  bool _bolehTopup = false;
  bool _tampilSaldo = true;
  bool _tampilCashback = true;
  bool _wajibPin = false;
  bool _wajibBelanjaRutin = false;
  Set<int> _caraBayarDipilih = {};
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final j = widget.jenis;
    _kode = TextEditingController(text: '${j?['kode'] ?? ''}');
    _nama = TextEditingController(text: '${j?['nama'] ?? ''}');
    _keterangan = TextEditingController(text: '${j?['keterangan'] ?? ''}');
    _istilahSaldo =
        TextEditingController(text: '${j?['istilahSisaSaldo'] ?? 'Saldo Kas'}');
    _istilahCashback =
        TextEditingController(text: '${j?['istilahCashback'] ?? 'Cashback'}');
    _minimalSaldo = TextEditingController(text: '${j?['minimalSaldo'] ?? 0}');
    _targetFrekuensi =
        TextEditingController(text: '${j?['targetFrekuensiBelanja'] ?? 0}');
    _maksimalPelanggaran =
        TextEditingController(text: '${j?['maksimalPelanggaran'] ?? 0}');
    _aktif = j?['aktif'] ?? true;
    _dipilih = j?['dipilih'] ?? true;
    _bolehTopup = j?['bolehEntryTopupOlehAdmin'] ?? false;
    _tampilSaldo = j?['tampilkanSisaSaldo'] ?? true;
    _tampilCashback = j?['tampilkanCashback'] ?? true;
    _wajibPin = j?['wajibPin'] ?? false;
    _wajibBelanjaRutin = j?['wajibBelanjaRutin'] ?? false;
    final daftarCsv = '${j?['daftarCaraPembayaranYangBolehDiPilih'] ?? ''}';
    _caraBayarDipilih = daftarCsv
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    _istilahSaldo.dispose();
    _istilahCashback.dispose();
    _minimalSaldo.dispose();
    _targetFrekuensi.dispose();
    _maksimalPelanggaran.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      await ApiClient.instance.aksi('jenis_anggota_simpan', {
        if (widget.jenis != null) 'id': widget.jenis!['id'],
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'istilah_sisa_saldo': _istilahSaldo.text.trim(),
        'istilah_cashback': _istilahCashback.text.trim(),
        'minimal_saldo': double.tryParse(_minimalSaldo.text.trim()) ?? 0,
        'target_frekuensi_belanja':
            int.tryParse(_targetFrekuensi.text.trim()) ?? 0,
        'maksimal_pelanggaran':
            int.tryParse(_maksimalPelanggaran.text.trim()) ?? 0,
        'aktif': _aktif,
        'dipilih': _dipilih,
        'boleh_entry_topup_oleh_admin': _bolehTopup,
        'tampilkan_sisa_saldo': _tampilSaldo,
        'tampilkan_cashback': _tampilCashback,
        'wajib_pin': _wajibPin,
        'wajib_belanja_rutin': _wajibBelanjaRutin,
        'daftar_cara_pembayaran_yang_boleh_di_pilih':
            _caraBayarDipilih.join(','),
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
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Jenis Member' : 'Tambah Jenis Member',
            subtitle:
                'Klasifikasi utama keanggotaan -- mengatur aturan saldo, topup, dan belanja rutin.',
            icon: Icons.category_outlined,
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
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 2),
                  AppFormSwitchTile(
                      title: 'Aktif',
                      value: _aktif,
                      onChanged: (v) => setStateIfMounted(() => _aktif = v)),
                  AppFormSwitchTile(
                      title: 'Bisa dipilih saat pendaftaran',
                      value: _dipilih,
                      onChanged: (v) => setStateIfMounted(() => _dipilih = v)),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Saldo & Cashback',
                children: [
                  AppFormTextField(
                      label: 'Istilah Sisa Saldo', controller: _istilahSaldo),
                  AppFormTextField(
                      label: 'Istilah Cashback', controller: _istilahCashback),
                  AppFormTextField(
                      label: 'Saldo Minimum',
                      controller: _minimalSaldo,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true)),
                  AppFormSwitchTile(
                      title: 'Tampilkan Sisa Saldo',
                      value: _tampilSaldo,
                      onChanged: (v) =>
                          setStateIfMounted(() => _tampilSaldo = v)),
                  AppFormSwitchTile(
                      title: 'Tampilkan Cashback',
                      value: _tampilCashback,
                      onChanged: (v) =>
                          setStateIfMounted(() => _tampilCashback = v)),
                  AppFormSwitchTile(
                      title: 'Boleh Topup oleh Admin/Kasir',
                      value: _bolehTopup,
                      onChanged: (v) =>
                          setStateIfMounted(() => _bolehTopup = v)),
                  AppFormSwitchTile(
                      title: 'Wajib Verifikasi PIN saat Transaksi',
                      value: _wajibPin,
                      onChanged: (v) => setStateIfMounted(() => _wajibPin = v)),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Aturan Wajib Belanja Rutin',
                deskripsi:
                    'Kirim peringatan otomatis bila member tak mencapai target frekuensi belanja.',
                children: [
                  AppFormSwitchTile(
                      title: 'Aktifkan Aturan',
                      value: _wajibBelanjaRutin,
                      onChanged: (v) =>
                          setStateIfMounted(() => _wajibBelanjaRutin = v)),
                  if (_wajibBelanjaRutin) ...[
                    AppFormTextField(
                        label: 'Target Frekuensi Belanja (per minggu)',
                        controller: _targetFrekuensi,
                        keyboardType: TextInputType.number),
                    AppFormTextField(
                        label: 'Maksimal Pelanggaran',
                        controller: _maksimalPelanggaran,
                        keyboardType: TextInputType.number),
                  ],
                ],
              ),
              if (widget.caraBayar.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppFormSection(
                  judul: 'Cara Pembayaran yang Boleh Dipilih',
                  deskripsi:
                      'Kosongkan semua = semua cara bayar boleh dipilih.',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: widget.caraBayar.map((c) {
                        final id = c['id'] as int;
                        final dipilih = _caraBayarDipilih.contains(id);
                        return FilterChip(
                          label: Text('${c['nama']}',
                              style: const TextStyle(fontSize: 12)),
                          selected: dipilih,
                          onSelected: (v) => setStateIfMounted(() {
                            if (v) {
                              _caraBayarDipilih.add(id);
                            } else {
                              _caraBayarDipilih.remove(id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
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
