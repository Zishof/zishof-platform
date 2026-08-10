import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

final _formatRpTipeMember =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Tab "Tipe Member" (padanan `tipe_anggota_koperasi.jsp`) -- kategori TIPIS
/// (kode/nama/keterangan/aktif SAJA, tanpa aturan bisnis) yg di layar "Data
/// Member Baru" diberi label "Kategori Referensi Sivitas" (mengaitkan member
/// ke data master Mahasiswa/Siswa/Guru/Dosen/Pegawai berdasar nama tipe).
/// BEDA dari Jenis Member (`AnggotaTabJenisMember`, klasifikasi UTAMA dgn
/// aturan saldo/topup/belanja-rutin).
class AnggotaTabTipeMember extends StatefulWidget {
  const AnggotaTabTipeMember({super.key});

  @override
  State<AnggotaTabTipeMember> createState() => _AnggotaTabTipeMemberState();
}

class _AnggotaTabTipeMemberState extends State<AnggotaTabTipeMember> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _muatDaftar();
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('tipe_anggota_list_admin', {
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

  Future<void> _bukaForm({Map<String, dynamic>? tipe}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormTipeMember(tipe: tipe),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> tipe) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Tipe Member?'),
        content: Text(
            'Tipe "${tipe['nama']}" dipakai ${tipe['jumlahAnggota'] ?? 0} member. Kalau masih dipakai, penghapusan akan ditolak -- nonaktifkan saja sebagai gantinya.'),
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
      await ApiClient.instance.aksi('tipe_anggota_hapus', {'id': tipe['id']});
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
                  onPressed: _muatDaftar, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muatDaftar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari kode/nama tipe...',
                  debounce: const Duration(milliseconds: 450),
                  onChanged: _cariUlang,
                ),
              ),
              if (Sesi.instance.bolehKelola) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _bukaForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Tipe'),
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
            minWidth: 720,
            emptyText: 'Belum ada tipe member.',
            columns: [
              const AppTableColumn('Kode', flex: 1),
              const AppTableColumn('Nama Tipe', flex: 2),
              const AppTableColumn('Keterangan', flex: 3),
              const AppTableColumn('Maks. Utang', flex: 2, align: TextAlign.right),
              const AppTableColumn('Status', flex: 1, align: TextAlign.center),
              AppTableColumn('Aksi',
                  width: Sesi.instance.bolehKelola ? 88 : 56,
                  align: TextAlign.center),
            ],
            rows: _daftar.map((t) {
              final aktif = t['aktif'] == true;
              return AppTableRowData(
                onTap: Sesi.instance.bolehKelola
                    ? () => _bukaForm(tipe: t)
                    : null,
                cells: [
                  AppTableCell.text('${t['kode'] ?? '-'}', flex: 1),
                  AppTableCell.text('${t['nama'] ?? ''}', flex: 2),
                  AppTableCell.text('${t['keterangan'] ?? '-'}',
                      flex: 3, maxLines: 2),
                  AppTableCell.text(
                    (((t['maksimalBolehUtang'] as num?) ?? 0) > 0)
                        ? _formatRpTipeMember
                            .format((t['maksimalBolehUtang'] as num?) ?? 0)
                        : 'Tidak boleh',
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: (((t['maksimalBolehUtang'] as num?) ?? 0) > 0)
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                  ),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: StatusPill(
                      label: aktif ? 'Aktif' : 'Nonaktif',
                      warna: aktif ? AppColors.success : AppColors.textSecondary,
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
                                onPressed: () => _bukaForm(tipe: t),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.danger),
                                onPressed: () => _hapus(t),
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
              labelData: 'tipe',
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

class _FormTipeMember extends StatefulWidget {
  final Map<String, dynamic>? tipe;
  const _FormTipeMember({required this.tipe});

  @override
  State<_FormTipeMember> createState() => _FormTipeMemberState();
}

class _FormTipeMemberState extends State<_FormTipeMember> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _maksimalBolehUtang;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final t = widget.tipe;
    _kode = TextEditingController(text: '${t?['kode'] ?? ''}');
    _nama = TextEditingController(text: '${t?['nama'] ?? ''}');
    _keterangan = TextEditingController(text: '${t?['keterangan'] ?? ''}');
    final maksUtang = (t?['maksimalBolehUtang'] as num?) ?? 0;
    _maksimalBolehUtang =
        TextEditingController(text: maksUtang == 0 ? '' : '$maksUtang');
    _aktif = t?['aktif'] ?? true;
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    _maksimalBolehUtang.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      await ApiClient.instance.aksi('tipe_anggota_simpan', {
        if (widget.tipe != null) 'id': widget.tipe!['id'],
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'aktif': _aktif,
        'maksimalBolehUtang': double.tryParse(
                _maksimalBolehUtang.text.trim().replaceAll(',', '.')) ??
            0,
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
    final ubah = widget.tipe != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Tipe Member' : 'Tambah Tipe Member',
            subtitle:
                'Kategori referensi sivitas -- mengaitkan member ke Mahasiswa/Siswa/Guru/Dosen/Pegawai berdasar nama.',
            icon: Icons.label_outline,
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
                  AppFormTextField(
                    label: 'Maksimal Boleh Utang',
                    controller: _maksimalBolehUtang,
                    hintText: '0 = tidak boleh berhutang',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
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
