import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTanggal = DateFormat('dd-MM-yyyy');

/// Tab "Topup" (padanan `_manajemen_topup.jsp`) -- riwayat pengisian saldo
/// member + entry baru. Gerbang tulis (tambah/ubah/hapus) memakai
/// `Sesi.instance.bolehEntryTopup` (padanan `Tbmrole.bolehEntryTopup`),
/// BEDA dari gerbang CRUD tab lain yg pakai `bolehKelola` -- melihat riwayat
/// tetap terbuka utk siapa saja yg bisa membuka layar Pelanggan (mode
/// "Hanya Baca" spt JSP saat `!canEdit`).
class AnggotaTabTopup extends StatefulWidget {
  const AnggotaTabTopup({super.key});

  @override
  State<AnggotaTabTopup> createState() => _AnggotaTabTopupState();
}

class _AnggotaTabTopupState extends State<AnggotaTabTopup> {
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
      final hasil = await ApiClient.instance.aksi('deposit_list', {
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

  Future<void> _bukaForm({Map<String, dynamic>? deposit}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormTopup(deposit: deposit),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> d) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Entri Topup?'),
        content: Text(
            'Topup ${_formatRupiah.format((d['nominal'] as num?) ?? 0)} untuk "${d['namaMember']}" akan dihapus permanen dan MENGURANGI saldo member secara langsung.'),
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
      await ApiClient.instance.aksi('deposit_hapus', {'id': d['id']});
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
    final bolehEdit = Sesi.instance.bolehEntryTopup;
    return RefreshIndicator(
      onRefresh: _muatDaftar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (!bolehEdit)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.latarLembut(AppColors.warning),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mode Hanya Baca -- Anda tidak memiliki hak akses "Boleh Entry Topup". Hubungi admin untuk mengaktifkannya.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari nama member...',
                  debounce: const Duration(milliseconds: 450),
                  onChanged: _cariUlang,
                ),
              ),
              if (bolehEdit) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _bukaForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Topup'),
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
            emptyText: 'Belum ada riwayat topup.',
            columns: [
              const AppTableColumn('Waktu', flex: 2),
              const AppTableColumn('Member', flex: 3),
              const AppTableColumn('Nominal', flex: 2, align: TextAlign.right),
              const AppTableColumn('Metode / Ket.', flex: 3),
              AppTableColumn('Aksi',
                  width: bolehEdit ? 88 : 24, align: TextAlign.center),
            ],
            rows: _daftar.map((d) {
              final expired = d['tanggalExpired'] != null;
              return AppTableRowData(
                cells: [
                  AppTableCell.text('${d['waktu'] ?? '-'}', flex: 2),
                  AppTableCell(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d['namaMember'] ?? '-'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        if (expired)
                          Text('Kadaluarsa: ${d['tanggalExpired']}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.warning)),
                      ],
                    ),
                  ),
                  AppTableCell.text(
                    _formatRupiah.format((d['nominal'] as num?) ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success),
                  ),
                  AppTableCell.text(
                    [
                      if ('${d['jenisPembayaranNama'] ?? ''}'.isNotEmpty)
                        d['jenisPembayaranNama'],
                      if ('${d['keterangan'] ?? ''}'.isNotEmpty)
                        d['keterangan'],
                    ].join(' · '),
                    flex: 3,
                    maxLines: 2,
                  ),
                  AppTableCell(
                    width: bolehEdit ? 88 : 24,
                    align: TextAlign.center,
                    child: bolehEdit
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _bukaForm(deposit: d),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.danger),
                                onPressed: () => _hapus(d),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'topup',
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

class _FormTopup extends StatefulWidget {
  final Map<String, dynamic>? deposit;
  const _FormTopup({required this.deposit});

  @override
  State<_FormTopup> createState() => _FormTopupState();
}

class _FormTopupState extends State<_FormTopup> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nominal;
  late final TextEditingController _keterangan;
  late final TextEditingController _cariMember;
  int? _idMember;
  String? _namaMemberDipilih;
  List<Map<String, dynamic>> _hasilCariMember = [];
  bool _mencariMember = false;
  DateTime _waktu = DateTime.now();
  DateTime? _tanggalExpired;
  bool _menyimpan = false;
  String? _pesanError;
  Timer? _debounceCariMember;

  @override
  void initState() {
    super.initState();
    final d = widget.deposit;
    _nominal = TextEditingController(text: '${d?['nominal'] ?? ''}');
    _keterangan = TextEditingController(text: '${d?['keterangan'] ?? ''}');
    _cariMember = TextEditingController()..addListener(_saatCariMemberBerubah);
    if (d != null) {
      _idMember = d['idMember'] as int?;
      _namaMemberDipilih = '${d['namaMember'] ?? ''}';
      if (d['waktu'] != null) {
        try {
          _waktu = DateTime.parse((d['waktu'] as String).replaceFirst(' ', 'T'));
        } catch (_) {}
      }
      if (d['tanggalExpired'] != null) {
        try {
          _tanggalExpired = DateTime.parse('${d['tanggalExpired']}');
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _debounceCariMember?.cancel();
    _nominal.dispose();
    _keterangan.dispose();
    _cariMember.dispose();
    super.dispose();
  }

  void _saatCariMemberBerubah() {
    _debounceCariMember?.cancel();
    _debounceCariMember = Timer(
        const Duration(milliseconds: 400), () => _cariAnggota(_cariMember.text));
  }

  Future<void> _cariAnggota(String kata) async {
    if (kata.trim().length < 2) {
      setStateIfMounted(() => _hasilCariMember = []);
      return;
    }
    setStateIfMounted(() => _mencariMember = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('anggota_list', {'keyword': kata.trim(), 'page_size': 10});
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setStateIfMounted(() => _hasilCariMember = data);
    } catch (_) {
      // Pencarian gagal -- diamkan, user bisa coba lagi.
    } finally {
      if (mounted) setStateIfMounted(() => _mencariMember = false);
    }
  }

  Future<void> _pilihWaktu() async {
    final tanggal = await showDatePicker(
        context: context,
        initialDate: _waktu,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (tanggal == null || !mounted) return;
    final jam = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_waktu));
    setStateIfMounted(() => _waktu = DateTime(
        tanggal.year, tanggal.month, tanggal.day, jam?.hour ?? 0, jam?.minute ?? 0));
  }

  Future<void> _pilihTanggalExpired() async {
    final hasil = await showDatePicker(
        context: context,
        initialDate: _tanggalExpired ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (hasil != null) setStateIfMounted(() => _tanggalExpired = hasil);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.deposit == null && _idMember == null) {
      setStateIfMounted(() => _pesanError = 'Member wajib dipilih.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final ubah = widget.deposit != null;
      await ApiClient.instance.aksi(ubah ? 'deposit_ubah' : 'topup_saldo', {
        if (ubah) 'id': widget.deposit!['id'],
        if (!ubah) 'id_member': _idMember,
        'nominal': double.tryParse(_nominal.text.trim()) ?? 0,
        'keterangan': _keterangan.text.trim(),
        'waktu': DateFormat('yyyy-MM-dd HH:mm:ss').format(_waktu),
        'tanggal_expired': _tanggalExpired == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_tanggalExpired!),
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
    final ubah = widget.deposit != null;
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
            title: ubah ? 'Ubah Entri Topup' : 'Tambah Topup',
            subtitle: ubah
                ? 'Member: ${_namaMemberDipilih ?? '-'}'
                : 'Isi saldo member secara manual.',
            icon: Icons.add_card_outlined,
            errorText: _pesanError,
            children: [
              AppFormSection(
                judul: 'Member',
                children: [
                  if (ubah)
                    AppReadonlyField(
                        label: 'Member', value: _namaMemberDipilih ?? '-')
                  else ...[
                    AppFormTextField(
                      label: 'Cari Member *',
                      controller: _cariMember,
                      hintText: 'Ketik nama/kode member...',
                    ),
                    if (_mencariMember)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_idMember != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Chip(
                          avatar: const Icon(Icons.check_circle,
                              size: 16, color: Colors.white),
                          backgroundColor: AppColors.success,
                          label: Text(_namaMemberDipilih ?? '',
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    if (_hasilCariMember.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.borderOf(context)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _hasilCariMember.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = _hasilCariMember[i];
                            return ListTile(
                              dense: true,
                              title: Text('${m['nama']}'),
                              subtitle: Text('${m['kode'] ?? ''}'),
                              onTap: () => setStateIfMounted(() {
                                _idMember = m['id'] as int;
                                _namaMemberDipilih = '${m['nama']}';
                                _hasilCariMember = [];
                                _cariMember.text = '${m['nama']}';
                              }),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Detail Topup',
                children: [
                  AppFormTextField(
                    label: 'Nominal *',
                    controller: _nominal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) return 'Nominal harus > 0';
                      return null;
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihWaktu,
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            'Waktu: ${_formatTanggal.format(_waktu)} ${_waktu.hour.toString().padLeft(2, '0')}:${_waktu.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihTanggalExpired,
                          icon: const Icon(Icons.event_busy, size: 16),
                          label: Text(
                            _tanggalExpired == null
                                ? 'Tanggal Kadaluarsa (opsional)'
                                : 'Kadaluarsa: ${_formatTanggal.format(_tanggalExpired!)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_tanggalExpired != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () =>
                              setStateIfMounted(() => _tanggalExpired = null),
                        ),
                    ],
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                    maxLines: 2,
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
