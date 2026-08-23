import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../sesi.dart';
import '../../widgets/app_components.dart';
import '../../theme/app_colors.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _formatRupiahPd =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

const _opsiStatus = ['PENDING', 'BERHASIL', 'DITOLAK'];

Color _warnaStatus(String? s) {
  switch (s) {
    case 'BERHASIL':
      return AppColors.success;
    case 'DITOLAK':
      return AppColors.danger;
    default:
      return AppColors.warning;
  }
}

/// Tab 2/3 "Pencairan Diskon" (padanan `pencairan_diskon.jsp`) -- riwayat +
/// CRUD pencairan saldo cashback member. Aksi `pencairan_diskon_list/
/// simpan/hapus` (server BARU, gap-closure -- sebelumnya HANYA reachable
/// dari JSP raw-SQL, Electron/Flutter tak punya jalur).
class TabPencairanDiskon extends StatefulWidget {
  const TabPencairanDiskon({super.key});
  @override
  State<TabPencairanDiskon> createState() => _TabPencairanDiskonState();
}

class _TabPencairanDiskonState extends State<TabPencairanDiskon> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  String? _statusFilter;
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
      await MasterOffline.daftarCacheDulu('pencairan_diskon_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        if (_statusFilter != null) 'status': _statusFilter,
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:pencairan_diskon', onData: (hasil) {
        if (!mounted) return;
        final data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _data = data;
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
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cariUlang(String v) async {
    _kataKunci = v;
    _halaman = 1;
    await _muatDaftar();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muatDaftar();
  }

  Future<void> _bukaForm({Map<String, dynamic>? data}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormPencairan(data: data),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> data) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Pencairan?'),
        content: Text(
            'Hapus pencairan "${data['kodePencairan']}"? Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'pencairan_diskon_hapus',
        body: {'id': data['id']},
        kunci: 'pencairan_diskon:${data['id']}',
        cacheKey: 'master:pencairan_diskon',
        rowLokal: {'id': data['id']},
        hapusLokal: true,
      );
      if (mounted) await _muatDaftar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menghapus: $e')));
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Sesi.instance.bolehKelola
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              icon: const Icon(Icons.add),
              label: const Text('Catat Pencairan'))
          : null,
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
                        AppDetailGalatOpsional(detail: detailUntuk(_error)),
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppSearchField(
                              hintText: 'Cari no. referensi / nama member...',
                              onChanged: _cariUlang,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String?>(
                              value: _statusFilter,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null, child: Text('- Semua -')),
                                ..._opsiStatus.map((s) =>
                                    DropdownMenuItem<String?>(
                                        value: s, child: Text(s))),
                              ],
                              onChanged: (v) {
                                _statusFilter = v;
                                _cariUlang(_kataKunci);
                              },
                            ),
                          ),
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
                        emptyText: 'Belum ada data pencairan.',
                        columns: const [
                          AppTableColumn('Waktu & No. Ref', flex: 3),
                          AppTableColumn('Anggota', flex: 3),
                          AppTableColumn('Cara Pencairan', flex: 2),
                          AppTableColumn('Nominal',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Status',
                              flex: 2, align: TextAlign.center),
                          AppTableColumn('', flex: 1, align: TextAlign.center),
                        ],
                        rows: _data.map((p) {
                          return AppTableRowData(
                            onTap: Sesi.instance.bolehKelola
                                ? () => _bukaForm(data: p)
                                : null,
                            cells: [
                              AppTableCell(
                                flex: 3,
                                child: KilauBaris(
                                  kunci: '${p['id'] ?? p['_kunci'] ?? ''}',
                                  idBaru: _idBaru,
                                  idBerubah: _idBerubah,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(children: [
                                        IndikatorBarisSinkron(
                                            kunci: kunciBarisMaster(
                                                'pencairan_diskon', p)),
                                        Flexible(
                                            child: Text('${p['kodePencairan']}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12.5))),
                                        IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip:
                                                'Riwayat data ini (AuditTrails)',
                                            icon: const Icon(Icons.history,
                                                size: 15),
                                            onPressed: () =>
                                                tampilkanRiwayatData(context,
                                                    entitas: 'pencairan_diskon',
                                                    id: p['id'],
                                                    judul:
                                                        '${p['kodePencairan'] ?? ''}')),
                                      ]),
                                      Text('${p['waktuPencairan'] ?? '-'}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondaryOf(
                                                  context))),
                                    ],
                                  ),
                                ),
                              ),
                              AppTableCell.text(
                                  '${p['anggotaNama'] ?? '-'}${(p['anggotaKode'] as String?)?.isNotEmpty == true ? ' (${p['anggotaKode']})' : ''}',
                                  flex: 3,
                                  maxLines: 2),
                              AppTableCell.text(
                                  '${p['caraPembayaranNama'] ?? '-'}',
                                  flex: 2),
                              AppTableCell.text(
                                  _formatRupiahPd.format(p['nominalCair'] ?? 0),
                                  flex: 2,
                                  align: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5)),
                              AppTableCell(
                                flex: 2,
                                align: TextAlign.center,
                                child: StatusPill(
                                    label: '${p['status'] ?? '-'}',
                                    warna:
                                        _warnaStatus(p['status'] as String?)),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: Sesi.instance.bolehKelola
                                    ? IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18, color: Colors.red),
                                        onPressed: () => _hapus(p),
                                        tooltip: 'Hapus',
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
                          labelData: 'pencairan',
                          onSebelumnya:
                              _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                          onBerikutnya: _halaman < _totalHalaman
                              ? () => _pindah(_halaman + 1)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _FormPencairan extends StatefulWidget {
  final Map<String, dynamic>? data;
  const _FormPencairan({required this.data});
  @override
  State<_FormPencairan> createState() => _FormPencairanState();
}

class _FormPencairanState extends State<_FormPencairan> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kodePencairan;
  late final TextEditingController _nominal;
  late final TextEditingController _keterangan;
  late final TextEditingController _tokoId;
  late final TextEditingController _cariAnggota;
  int? _anggotaId;
  int? _caraPembayaranId;
  String _status = 'PENDING';
  DateTime? _waktu;
  DateTime? _tanggalExpired;
  double? _sisaSaldo;
  bool _mencariSaldo = false;
  bool _menyimpan = false;
  String? _error;
  Timer? _debounce;
  List<Map<String, dynamic>> _hasilCariAnggota = [];

  bool get _ubah => widget.data != null;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _kodePencairan = TextEditingController(text: d?['kodePencairan'] ?? '');
    _nominal = TextEditingController(
        text: d == null
            ? ''
            : '${(d['nominalCair'] as num?)?.toStringAsFixed(0) ?? ''}');
    _keterangan = TextEditingController(text: d?['keterangan'] ?? '');
    _tokoId = TextEditingController(
        text: d?['tokoId'] == null ? '' : '${d!['tokoId']}');
    _cariAnggota = TextEditingController(
        text: d == null
            ? ''
            : '${d['anggotaNama'] ?? ''}${(d['anggotaKode'] as String?)?.isNotEmpty == true ? ' (${d['anggotaKode']})' : ''}');
    _anggotaId = d?['anggotaId'] as int?;
    _caraPembayaranId = d?['caraPembayaranId'] as int?;
    _status = (d?['status'] as String?) ?? 'PENDING';
    _waktu =
        _uraiWaktuRaw(d?['waktuPencairanRaw'] as String?) ?? DateTime.now();
    _tanggalExpired = _uraiTanggal(d?['tanggalExpired'] as String?);
    if (!_ubah) {
      _kodePencairan.text = 'WD-${DateTime.now().millisecondsSinceEpoch}';
    }
    _cariAnggota.addListener(() => _cariAnggotaBerubah(_cariAnggota.text));
    if (_anggotaId != null) _muatSaldo();
  }

  DateTime? _uraiWaktuRaw(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  DateTime? _uraiTanggal(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _muatSaldo() async {
    if (_anggotaId == null) {
      setStateIfMounted(() => _sisaSaldo = null);
      return;
    }
    setStateIfMounted(() => _mencariSaldo = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('pencairan_diskon_saldo_member', {
        'anggota_koperasi_id': _anggotaId,
        if (_ubah) 'except_id': widget.data!['id'],
      });
      setStateIfMounted(
          () => _sisaSaldo = (hasil['sisaSaldo'] as num?)?.toDouble() ?? 0);
    } catch (_) {
      setStateIfMounted(() => _sisaSaldo = null);
    } finally {
      if (mounted) setStateIfMounted(() => _mencariSaldo = false);
    }
  }

  void _cariAnggotaBerubah(String v) {
    if (_mengisiOtomatis) return;
    _anggotaId = null;
    _sisaSaldo = null;
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setStateIfMounted(() => _hasilCariAnggota = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final hasil = await ApiClient.instance
            .aksi('anggota_list', {'keyword': v.trim(), 'page_size': 20});
        setStateIfMounted(() => _hasilCariAnggota =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
      } catch (_) {
        // Pencarian gagal -- biarkan daftar lama, bukan blocker.
      }
    });
  }

  // Cegah listener _cariAnggota mereset _anggotaId & memicu pencarian ulang
  // saat teks diisi PROGRAM (hasil pilih dari daftar), bukan ketikan user.
  bool _mengisiOtomatis = false;

  void _pilihAnggota(Map<String, dynamic> a) {
    final kode = (a['kodeIdentitas'] as String?) ?? '';
    _mengisiOtomatis = true;
    _cariAnggota.text = '${a['nama']}${kode.isNotEmpty ? ' ($kode)' : ''}';
    _mengisiOtomatis = false;
    _anggotaId = a['id'] as int?;
    _hasilCariAnggota = [];
    setStateIfMounted(() {});
    _muatSaldo();
  }

  Future<void> _pilihWaktu() async {
    final tanggal = await showDatePicker(
        context: context,
        initialDate: _waktu ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (tanggal == null) return;
    if (!mounted) return;
    final jam = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_waktu ?? DateTime.now()));
    setStateIfMounted(() => _waktu = DateTime(tanggal.year, tanggal.month,
        tanggal.day, jam?.hour ?? 0, jam?.minute ?? 0));
  }

  Future<void> _pilihTanggalExpired() async {
    final tanggal = await showDatePicker(
        context: context,
        initialDate: _tanggalExpired ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (tanggal == null) return;
    setStateIfMounted(() => _tanggalExpired = tanggal);
  }

  String _fmtWaktu(DateTime d) {
    String p(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}T${p(d.hour)}:${p(d.minute)}';
  }

  String _fmtTanggal(DateTime d) {
    String p(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _kodePencairan.dispose();
    _nominal.dispose();
    _keterangan.dispose();
    _tokoId.dispose();
    _cariAnggota.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_anggotaId == null) {
      setStateIfMounted(
          () => _error = 'Pilih anggota koperasi terlebih dahulu.');
      return;
    }
    if (_caraPembayaranId == null) {
      setStateIfMounted(() => _error = 'Pilih cara pencairan terlebih dahulu.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final body = {
        if (_ubah) 'id': widget.data!['id'],
        'kode_pencairan': _kodePencairan.text.trim(),
        'anggota_koperasi_id': _anggotaId,
        'cara_pembayaran_id': _caraPembayaranId,
        'nominal_cair':
            double.tryParse(_nominal.text.replaceAll(',', '.')) ?? 0,
        'waktu_pencairan': _fmtWaktu(_waktu ?? DateTime.now()),
        'tanggal_expired':
            _tanggalExpired == null ? '' : _fmtTanggal(_tanggalExpired!),
        'status': _status,
        'keterangan': _keterangan.text.trim(),
        if (Sesi.instance.isAdmin)
          'toko_id': _tokoId.text.trim().isEmpty ? null : _tokoId.text.trim(),
      };
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'pencairan_diskon_simpan',
        body: body,
        kunci: _ubah
            ? 'pencairan_diskon:${widget.data!['id']}'
            : 'pencairan_diskon:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:pencairan_diskon',
        rowLokal: body,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            title: _ubah ? 'Ubah Pencairan' : 'Catat Pencairan Baru',
            subtitle: 'Pencairan saldo cashback anggota koperasi.',
            icon: Icons.payments_outlined,
            errorText: _error,
            errorDetail: detailUntuk(_error),
            children: [
              AppFormSection(
                judul: 'Referensi & Waktu',
                children: [
                  AppFormTextField(
                      label: 'No. Referensi', controller: _kodePencairan),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pilihWaktu,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(_waktu == null
                        ? 'Pilih Waktu Pencairan'
                        : '${_waktu!.day}-${_waktu!.month}-${_waktu!.year} ${_waktu!.hour.toString().padLeft(2, '0')}:${_waktu!.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Anggota Koperasi',
                children: [
                  AppFormTextField(
                    label: 'Cari Anggota *',
                    controller: _cariAnggota,
                    validator: (v) =>
                        _anggotaId == null ? 'Pilih anggota dari daftar' : null,
                  ),
                  if (_hasilCariAnggota.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.borderOf(context)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _hasilCariAnggota.length,
                        itemBuilder: (_, i) {
                          final a = _hasilCariAnggota[i];
                          final kode = (a['kodeIdentitas'] as String?) ?? '';
                          return ListTile(
                            dense: true,
                            title: Text('${a['nama']}'),
                            subtitle: kode.isNotEmpty ? Text(kode) : null,
                            onTap: () => _pilihAnggota(a),
                          );
                        },
                      ),
                    ),
                  if (_anggotaId != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined,
                              size: 16),
                          const SizedBox(width: 8),
                          Text('Sisa Saldo Cashback: ',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context))),
                          _mencariSaldo
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : Text(
                                  _sisaSaldo == null
                                      ? '-'
                                      : _formatRupiahPd.format(_sisaSaldo),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: (_sisaSaldo ?? 0) <= 0
                                          ? AppColors.danger
                                          : AppColors.primary),
                                ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Detail Pencairan',
                children: [
                  DropdownButtonFormField<int?>(
                    value: Sesi.instance.caraBayar
                            .any((c) => c.id == _caraPembayaranId)
                        ? _caraPembayaranId
                        : null,
                    decoration: AppFormStyle.fieldDecoration(context,
                        labelText: 'Cara Pencairan *'),
                    items: Sesi.instance.caraBayar
                        .map((c) => DropdownMenuItem<int?>(
                            value: c.id, child: Text(c.nama)))
                        .toList(),
                    onChanged: (v) =>
                        setStateIfMounted(() => _caraPembayaranId = v),
                  ),
                  const SizedBox(height: 12),
                  AppFormTextField(
                    label: 'Nominal Pencairan (Rp) *',
                    controller: _nominal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
                      return n <= 0 ? 'Harus lebih dari 0' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihTanggalExpired,
                          icon: const Icon(Icons.event_busy, size: 16),
                          label: Text(_tanggalExpired == null
                              ? 'Tgl. Kedaluwarsa (opsional)'
                              : '${_tanggalExpired!.day}-${_tanggalExpired!.month}-${_tanggalExpired!.year}'),
                        ),
                      ),
                      if (_tanggalExpired != null)
                        IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setStateIfMounted(
                                () => _tanggalExpired = null)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: AppFormStyle.fieldDecoration(context,
                        labelText: 'Status'),
                    items: _opsiStatus
                        .map((s) =>
                            DropdownMenuItem<String>(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setStateIfMounted(() => _status = v ?? 'PENDING'),
                  ),
                  const SizedBox(height: 12),
                  AppFormTextField(
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 2),
                  if (Sesi.instance.isAdmin) ...[
                    const SizedBox(height: 12),
                    AppFormTextField(
                      label: 'Toko / Kasir Eksekutor (ID, opsional)',
                      controller: _tokoId,
                      keyboardType: TextInputType.number,
                    ),
                  ],
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
