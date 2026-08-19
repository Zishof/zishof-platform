import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';

final _fmtRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Kas / Bank / Jurnal + Master Akun (layar legacy 43-44).</h3>
///
/// REUSE modul akunting existing: jurnal = akunting.transaksi, COA =
/// akunting.akun (tanpa duplikasi). Master Akun: create/update terbatas
/// Pemilik/Admin, tanpa hapus (akun berhistori). Kas sesi sales lapangan
/// hidup di ledger sesi (menu Sesi Nota Sales).
class KasJurnalScreen extends StatefulWidget {
  const KasJurnalScreen({super.key});

  @override
  State<KasJurnalScreen> createState() => _KasJurnalScreenState();
}

class _KasJurnalScreenState extends State<KasJurnalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.kasJurnal,
      judul: 'Kas & Jurnal',
      subjudul:
          'Jurnal transaksi + Master Akun (COA) — reuse akunting existing, layar legacy 43-44',
      scrollable: false,
      body: Column(children: [
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            tabs: const [
              Tab(text: 'Jurnal'),
              Tab(text: 'Master Akun (COA)'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tab, children: const [
            _TabJurnal(),
            _TabCoa(),
          ]),
        ),
      ]),
    );
  }
}

class _TabJurnal extends StatefulWidget {
  const _TabJurnal();

  @override
  State<_TabJurnal> createState() => _TabJurnalState();
}

class _TabJurnalState extends State<_TabJurnal> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  double _totalDebet = 0, _totalKredit = 0;
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();

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
      final hasil = await ApiClient.instance.aksi('si_cash_journal_list', {
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
      });
      setStateIfMounted(() {
        _data = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totalDebet = (hasil['totalDebet'] as num?)?.toDouble() ?? 0;
        _totalKredit = (hasil['totalKredit'] as num?)?.toDouble() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _PanelErrorKj(pesan: _error!, onCoba: _muat);
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(children: [
            OutlinedButton.icon(
              onPressed: () async {
                final t = await showDatePicker(
                    context: context,
                    initialDate: _dari,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035));
                if (t != null) {
                  setStateIfMounted(() => _dari = t);
                  _muat();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('Dari ${_fmtTgl.format(_dari)}',
                  style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final t = await showDatePicker(
                    context: context,
                    initialDate: _sampai,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035));
                if (t != null) {
                  setStateIfMounted(() => _sampai = t);
                  _muat();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('s/d ${_fmtTgl.format(_sampai)}',
                  style: const TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            Text(
                'D ${_fmtRp.format(_totalDebet)} · K ${_fmtRp.format(_totalKredit)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          AppDataTable(
            minWidth: 1000,
            emptyText: 'Tidak ada jurnal pada periode ini.',
            columns: const [
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Kode', flex: 2),
              AppTableColumn('Akun', flex: 3),
              AppTableColumn('Keterangan', flex: 3),
              AppTableColumn('Debet', flex: 2, align: TextAlign.right),
              AppTableColumn('Kredit', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final r in _data)
                AppTableRowData(cells: [
                  AppTableCell.text('${r['tanggal']}'.split(' ').first, flex: 2),
                  AppTableCell.text('${r['kode']}', flex: 2),
                  AppTableCell.text('${r['akunKode']} ${r['akunNama']}', flex: 3),
                  AppTableCell.text('${r['keterangan']}', flex: 3, maxLines: 2),
                  AppTableCell.text(_fmtRp.format(r['debet'] ?? 0),
                      flex: 2, align: TextAlign.right),
                  AppTableCell.text(_fmtRp.format(r['kredit'] ?? 0),
                      flex: 2, align: TextAlign.right),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabCoa extends StatefulWidget {
  const _TabCoa();

  @override
  State<_TabCoa> createState() => _TabCoaState();
}

class _TabCoaState extends State<_TabCoa> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  String _q = '';
  // Diff emisi lokal-dulu: menggerakkan kilau baris + banner perubahan server.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

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
      // Baca LOKAL DULU (lihat MasterOffline.daftarCacheDulu): snapshot cache
      // tampil seketika, hasil server menyusul + diff utk kilau baris.
      await MasterOffline.daftarCacheDulu(
          'si_coa_list', {if (_q.isNotEmpty) 'q': _q}, 'master:si_coa',
          fieldData: 'rows', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil, fieldData: 'rows');
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _formAkun({Map<String, dynamic>? akun}) async {
    final kode = TextEditingController(text: akun == null ? '' : '${akun['kode']}');
    final nama = TextEditingController(text: akun == null ? '' : '${akun['nama']}');
    final ket =
        TextEditingController(text: akun == null ? '' : '${akun['keterangan']}');
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(akun == null ? 'Perkiraan Baru' : 'Ubah Perkiraan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: kode,
              decoration: const InputDecoration(labelText: 'Kode akun')),
          TextField(
              controller: nama,
              decoration: const InputDecoration(labelText: 'Nama akun')),
          TextField(
              controller: ket,
              decoration: const InputDecoration(labelText: 'Keterangan')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ya == true && kode.text.trim().isNotEmpty && nama.text.trim().isNotEmpty) {
      try {
        await ApiClient.instance.aksi('si_coa_save', {
          if (akun != null) 'akun_id': akun['id'],
          'kode': kode.text.trim(),
          'nama': nama.text.trim(),
          'keterangan': ket.text.trim(),
        });
        _muat();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolehKelola = !Sesi.instance.isSalesKeliling;
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _PanelErrorKj(pesan: _error!, onCoba: _muat);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: bolehKelola
          ? FloatingActionButton.extended(
              onPressed: () => _formAkun(),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Perkiraan Baru',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          children: [
            AppSearchField(
              hintText: 'Cari kode/nama akun...',
              onChanged: (v) {
                _q = v.trim();
                _muat();
              },
            ),
            const SizedBox(height: 10),
            BannerPerubahanServer(
              key: ValueKey('perubahan:${_diff.versi}'),
              baru: _diff.idBaru.length,
              berubah: _diff.idBerubah.length,
              dihapus: _diff.jumlahHapus,
            ),
            AppDataTable(
              minWidth: 860,
              emptyText: 'Tidak ada akun.',
              columns: const [
                AppTableColumn('Kode', flex: 2),
                AppTableColumn('Nama', flex: 4),
                AppTableColumn('Induk', flex: 3),
                AppTableColumn('Keterangan', flex: 3),
                AppTableColumn('Aksi', flex: 1, align: TextAlign.center),
              ],
              rows: [
                for (final r in _data)
                  AppTableRowData(cells: [
                    AppTableCell(
                      flex: 2,
                      child: KilauBaris(
                        kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                        idBaru: _diff.idBaru,
                        idBerubah: _diff.idBerubah,
                        child: Text('${r['kode']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    AppTableCell.text('${r['nama']}', flex: 4),
                    AppTableCell.text(
                        '${r['parentKode']} ${r['parentNama']}'.trim(),
                        flex: 3),
                    AppTableCell.text('${r['keterangan']}', flex: 3),
                    AppTableCell(
                      flex: 1,
                      align: TextAlign.center,
                      child: bolehKelola
                          ? IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _formAkun(akun: r))
                          : const SizedBox.shrink(),
                    ),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelErrorKj extends StatelessWidget {
  final String pesan;
  final VoidCallback onCoba;
  const _PanelErrorKj({required this.pesan, required this.onCoba});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(pesan, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ]),
      ),
    );
  }
}
