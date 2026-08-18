import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import '../../widgets/indikator_sinkron_master.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/riwayat_audit_dialog.dart';
import '../../widgets/safe_state.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Master Sales -- layar legacy 07 (Data Sales atau Penjual Keliling).</h3>
///
/// CRUD profil sales (`si_sales_*`): kode legacy 2 karakter teks (terkunci
/// setelah tersimpan), No. Perkiraan (mapping COA menunggu UAT -- disimpan apa
/// adanya), wilayah/area, target bulanan, limit penagihan, akun login opsional
/// (satu akun = satu profil sales aktif), jumlah customer binaan, status
/// aktif/nonaktif (sales berhistori dinonaktifkan, bukan dihapus).
class MasterSalesScreen extends StatefulWidget {
  const MasterSalesScreen({super.key});

  @override
  State<MasterSalesScreen> createState() => _MasterSalesScreenState();
}

class _MasterSalesScreenState extends State<MasterSalesScreen> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  String? _filterAktif;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('si_sales_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        if (_filterAktif != null) 'aktif': _filterAktif,
        'page': _halaman,
        'page_size': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Future<void> _bukaForm({Map<String, dynamic>? data}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormSales(data: data),
    );
    if (tersimpan == true) await _muat();
  }

  Future<void> _ubahStatus(Map<String, dynamic> data,
      {required bool aktifkan}) async {
    final alasanCtrl = TextEditingController();
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aktifkan ? 'Aktifkan Sales?' : 'Nonaktifkan Sales?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(aktifkan
              ? 'Sales "${data['nama']}" diaktifkan kembali.'
              : 'Sales berhistori dinonaktifkan, tidak dihapus -- snapshot pada '
                  'faktur/piutang historis tetap utuh.'),
          if (!aktifkan) ...[
            const SizedBox(height: 12),
            TextField(
              controller: alasanCtrl,
              decoration: const InputDecoration(
                  labelText: 'Alasan (wajib, tercatat di audit)',
                  border: OutlineInputBorder()),
            ),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(aktifkan ? 'Aktifkan' : 'Nonaktifkan',
                  style: TextStyle(
                      color: aktifkan ? AppColors.success : Colors.red))),
        ],
      ),
    );
    if (yakin != true) return;
    try {
      await MasterOffline.simpanAtauAntre('si_sales_deactivate', {
        'id': data['id'],
        'aktif': aktifkan,
        if (!aktifkan) 'alasan': alasanCtrl.text.trim(),
      }, kunci: 'si_sales:${data['id']}');
      if (mounted) await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolehTambah = Sesi.instance.bolehAksiIs('master_sales', 'create');
    final bolehUbah = Sesi.instance.bolehAksiIs('master_sales', 'update');
    return AppShell(
      menuAktif: MenuEBisnis.masterSales,
      judul: 'Master Sales',
      subjudul:
          'Penjual keliling: kode, perkiraan, wilayah, target, akun login (layar legacy 07)',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message:
              'Cetak/ekspor daftar sales & mapping perkiraan tersedia di fase laporan (P2-F).',
          child: IconButton(
              icon: const Icon(Icons.print_outlined), onPressed: null),
        ),
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang',
            onPressed: _muat),
      ]),
      floatingActionButton: bolehTambah
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Sales'))
          : null,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _muat, child: const Text('Coba Lagi')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                                hintText: 'Cari kode, nama, area...',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                isDense: true),
                            onSubmitted: (v) {
                              _kataKunci = v.trim();
                              _halaman = 1;
                              _muat();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 130,
                          child: DropdownButtonFormField<String?>(
                            value: _filterAktif,
                            isDense: true,
                            decoration: const InputDecoration(
                                labelText: 'Status',
                                isDense: true,
                                border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(
                                  value: null, child: Text('Semua')),
                              DropdownMenuItem(
                                  value: 'aktif', child: Text('Aktif')),
                              DropdownMenuItem(
                                  value: 'nonaktif', child: Text('Nonaktif')),
                            ],
                            onChanged: (v) {
                              _filterAktif = v;
                              _halaman = 1;
                              _muat();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      AppDataTable(
                        minWidth: 920,
                        emptyText: 'Belum ada sales.',
                        columns: const [
                          AppTableColumn('Kode', flex: 1),
                          AppTableColumn('Nama Sales', flex: 3),
                          AppTableColumn('No. Perkiraan', flex: 2),
                          AppTableColumn('Area', flex: 2),
                          AppTableColumn('Target/Bln',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Customer',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Status',
                              flex: 1, align: TextAlign.center),
                          AppTableColumn('', flex: 1, align: TextAlign.center),
                        ],
                        rows: _data.map((s) {
                          final aktif = s['aktif'] == true;
                          return AppTableRowData(
                            onTap: bolehUbah ? () => _bukaForm(data: s) : null,
                            cells: [
                              AppTableCell(
                                flex: 1,
                                child: SelTeksDenganSinkron(
                                  kunci: 'si_sales:${s['id']}',
                                  teks: '${s['kode']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                      fontSize: 12.5),
                                ),
                              ),
                              AppTableCell(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${s['nama']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    if ('${s['userId'] ?? ''}'.isNotEmpty)
                                      Text('Akun: ${s['userId']}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondaryOf(
                                                  context))),
                                  ],
                                ),
                              ),
                              AppTableCell.text('${s['nomorPerkiraan'] ?? ''}',
                                  flex: 2),
                              AppTableCell.text('${s['area'] ?? ''}', flex: 2),
                              AppTableCell.text(
                                  _fmtRp.format(
                                      (s['targetBulanan'] as num?) ?? 0),
                                  flex: 2,
                                  align: TextAlign.right),
                              AppTableCell.text('${s['jumlahCustomer'] ?? 0}',
                                  flex: 1, align: TextAlign.right),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                    label: aktif ? 'Aktif' : 'Nonaktif',
                                    warna: aktif
                                        ? AppColors.success
                                        : AppColors.danger),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: bolehUbah
                                    ? IconButton(
                                        icon: Icon(
                                            aktif
                                                ? Icons.block
                                                : Icons.check_circle_outline,
                                            size: 18,
                                            color: aktif
                                                ? Colors.red
                                                : AppColors.success),
                                        tooltip:
                                            aktif ? 'Nonaktifkan' : 'Aktifkan',
                                        onPressed: () =>
                                            _ubahStatus(s, aktifkan: !aktif),
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
                          labelData: 'sales',
                          onSebelumnya: _halaman > 1
                              ? () {
                                  _halaman--;
                                  _muat();
                                }
                              : null,
                          onBerikutnya: _halaman < _totalHalaman
                              ? () {
                                  _halaman++;
                                  _muat();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _FormSales extends StatefulWidget {
  final Map<String, dynamic>? data;
  const _FormSales({required this.data});

  @override
  State<_FormSales> createState() => _FormSalesState();
}

class _FormSalesState extends State<_FormSales> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _nomorPerkiraan;
  late final TextEditingController _area;
  late final TextEditingController _telepon;
  late final TextEditingController _alamat;
  late final TextEditingController _target;
  late final TextEditingController _limit;
  late final TextEditingController _akun;
  bool _menyimpan = false;
  bool _adaPerubahan = false;
  String? _error;

  bool get _ubah => widget.data != null;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _kode = TextEditingController(text: d?['kode'] ?? '');
    _nama = TextEditingController(text: d?['nama'] ?? '');
    _nomorPerkiraan = TextEditingController(text: d?['nomorPerkiraan'] ?? '');
    _area = TextEditingController(text: d?['area'] ?? '');
    _telepon = TextEditingController(text: d?['telepon'] ?? '');
    _alamat = TextEditingController(text: d?['alamat'] ?? '');
    _target = TextEditingController(
        text: (d?['targetBulanan'] as num?)?.toStringAsFixed(0) ?? '0');
    _limit = TextEditingController(
        text: (d?['limitPenagihan'] as num?)?.toStringAsFixed(0) ?? '0');
    _akun = TextEditingController(text: d?['userId'] ?? '');
    for (final c in [
      _kode,
      _nama,
      _nomorPerkiraan,
      _area,
      _telepon,
      _alamat,
      _target,
      _limit,
      _akun
    ]) {
      c.addListener(() => _adaPerubahan = true);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _kode,
      _nama,
      _nomorPerkiraan,
      _area,
      _telepon,
      _alamat,
      _target,
      _limit,
      _akun
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final hasil = await MasterOffline.simpanAtauAntre(
          _ubah ? 'si_sales_update' : 'si_sales_create', {
        if (_ubah) 'id': widget.data!['id'],
        if (!_ubah) 'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'nomor_perkiraan': _nomorPerkiraan.text.trim(),
        'area': _area.text.trim(),
        'telepon': _telepon.text.trim(),
        'alamat': _alamat.text.trim(),
        'target_bulanan':
            double.tryParse(_target.text.replaceAll(',', '.')) ?? 0,
        'limit_penagihan':
            double.tryParse(_limit.text.replaceAll(',', '.')) ?? 0,
        'tbmuser_id': _akun.text.trim(),
      },
          kunci: _ubah
              ? 'si_sales:${widget.data!['id']}'
              : 'si_sales:baru:${DateTime.now().microsecondsSinceEpoch}');
      if (hasil['offline'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Tersimpan lokal — akan dikirim otomatis saat online.')));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Future<bool> _konfirmasiTutup() async {
    if (!_adaPerubahan) return true;
    final keluar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perubahan belum disimpan'),
        content: const Text(
            'Ada perubahan yang belum disimpan. Tutup tanpa menyimpan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Kembali')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buang', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return keluar == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _konfirmasiTutup() && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, sc) => Form(
            key: _formKey,
            child: AppFormSheet(
              scrollController: sc,
              title: _ubah ? 'Ubah Sales' : 'Tambah Sales',
              subtitle: _ubah
                  ? 'Kode legacy terkunci; sales pada dokumen historis = snapshot.'
                  : 'Kode legacy 2 karakter dipertahankan sebagai teks apa adanya.',
              icon: _ubah ? Icons.edit_outlined : Icons.badge_outlined,
              errorText: _error,
              children: [
                AppFormSection(judul: 'Identitas Sales', children: [
                  Row(children: [
                    Expanded(
                      child: AppFormTextField(
                        label: _ubah ? 'Kode (terkunci)' : 'Kode Sales *',
                        controller: _kode,
                        readOnly: _ubah,
                        enabled: !_ubah,
                        validator: (v) =>
                            !_ubah && (v == null || v.trim().isEmpty)
                                ? 'Wajib diisi'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppFormTextField(
                        label: 'No. Perkiraan (COA)',
                        controller: _nomorPerkiraan,
                        helperText:
                            'Mapping akun divalidasi saat posting (UAT); nilai legacy disimpan apa adanya.',
                      ),
                    ),
                  ]),
                  AppFormTextField(
                    label: 'Nama Sales *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'Wilayah Utama / Area', controller: _area)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(
                            label: 'Ponsel', controller: _telepon)),
                  ]),
                  AppFormTextField(
                      label: 'Alamat', controller: _alamat, maxLines: 2),
                ]),
                const SizedBox(height: 12),
                AppFormSection(judul: 'Target & Akun', children: [
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'Target Bulanan (Rp)',
                            controller: _target,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(
                            label: 'Limit Penagihan (Rp)',
                            controller: _limit,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true))),
                  ]),
                  AppFormTextField(
                    label: 'Akun Login (userId, opsional)',
                    controller: _akun,
                    helperText:
                        'Satu akun aktif = satu profil sales. Kosongkan untuk melepas tautan.',
                  ),
                ]),
              ],
              actions: [
                // Paritas aksi "Riwayat Audit" legacy: SalesInventory sendiri
                // entity ber-@Audited, jadi id-nya langsung dipakai.
                if (_ubah)
                  OutlinedButton.icon(
                    onPressed: () => tampilkanRiwayatAudit(
                        context,
                        'sales',
                        widget.data!['id'] as Object,
                        '${widget.data!['nama']}'),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Riwayat Audit'),
                  ),
                OutlinedButton.icon(
                  onPressed: _menyimpan
                      ? null
                      : () async {
                          if (await _konfirmasiTutup() && context.mounted) {
                            Navigator.of(context).pop(false);
                          }
                        },
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
