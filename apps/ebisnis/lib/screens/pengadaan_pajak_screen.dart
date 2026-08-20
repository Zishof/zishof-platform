import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/safe_state.dart';

/// Layar "Bayar Pajak" -- tahap penutup rantai Pengadaan POS.
///
/// Mengikuti bentuk layar Pertanggungjawaban Pajak versi ZKoss: satu rekaman
/// setoran mewakili satu jenis pajak, dengan DPP, nilai, NPWP, nama wajib pajak,
/// NTPN, dan tanggal setor sebagai bukti.
///
/// PPh DIPOTONG dari kas yang keluar dan menjadi kewajiban kita kepada negara;
/// PPN dibayarkan kepada vendor sebagai pajak masukan. Keduanya ditampilkan agar
/// petugas melihat gambaran utuh sebelum menyetor.
class PengadaanPajakScreen extends StatefulWidget {
  const PengadaanPajakScreen({super.key});

  @override
  State<PengadaanPajakScreen> createState() => _PengadaanPajakScreenState();
}

class _PengadaanPajakScreenState extends State<PengadaanPajakScreen>
    with SingleTickerProviderStateMixin {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  late final TabController _tab;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _terutang = [];
  List<Map<String, dynamic>> _setoran = [];
  final Set<int> _dipilih = {};
  double _totalPph = 0;
  double _totalPpn = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _muat();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final t = await ApiClient.instance.aksi('pengadaan_pajak_terutang', {});
      final d = await ApiClient.instance.aksi('pengadaan_pajak_daftar', {});
      if (!mounted) return;
      setStateIfMounted(() {
        _terutang = ((t['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _setoran = ((d['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totalPph = (t['totalPph'] as num?)?.toDouble() ?? 0;
        _totalPpn = (t['totalPpn'] as num?)?.toDouble() ?? 0;
        _dipilih.removeWhere((id) =>
            !_terutang.any((r) => (r['detail_id'] as num?)?.toInt() == id));
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  double _totalDipilih(String kunci) => _terutang
      .where((r) => _dipilih.contains((r['detail_id'] as num?)?.toInt()))
      .fold(0, (s, r) => s + ((r[kunci] as num?)?.toDouble() ?? 0));

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(teks),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error));
  }

  /// Setor pajak atas baris terpilih. NTPN dan tanggal setor WAJIB -- keduanya
  /// adalah bukti bahwa uangnya benar-benar masuk kas negara, dan server menolak
  /// bila kosong, jadi dialog meminta keduanya sekaligus.
  Future<void> _setor(String jenis) async {
    if (_dipilih.isEmpty) {
      _pesan('Centang minimal satu baris pajak.', sukses: false);
      return;
    }
    final nilai = _totalDipilih(jenis == 'PPH' ? 'pph' : 'ppn');
    if (nilai <= 0) {
      _pesan('Baris terpilih tidak memiliki $jenis untuk disetor.', sukses: false);
      return;
    }
    final ntpn = TextEditingController();
    final npwp = TextEditingController();
    final namaWp = TextEditingController();
    final keterangan = TextEditingController();
    final tanggal = TextEditingController(
        text: DateFormat('dd-MM-yyyy').format(DateTime.now()));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> pilihTanggal() async {
          final pilih = await showDatePicker(
            context: c,
            initialDate: DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (pilih == null) return;
          setLocal(() =>
              tanggal.text = DateFormat('dd-MM-yyyy').format(pilih));
        }

        return AlertDialog(
          title: Text('Setor $jenis'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${_dipilih.length} baris · nilai ${_fmtRp.format(nilai)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ntpn,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'NTPN *',
                      helperText: 'Nomor Transaksi Penerimaan Negara'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tanggal,
                  readOnly: true,
                  onTap: pilihTanggal,
                  decoration: const InputDecoration(
                      labelText: 'Tanggal setor *',
                      suffixIcon: Icon(Icons.event, size: 18)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: npwp,
                  decoration: const InputDecoration(labelText: 'NPWP'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: namaWp,
                  decoration: const InputDecoration(labelText: 'Nama wajib pajak'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text('Setor $jenis')),
          ],
        );
      }),
    );
    final isi = {
      'ntpn': ntpn.text.trim(),
      'tanggalSetor': tanggal.text.trim(),
      'npwp': npwp.text.trim(),
      'namaWp': namaWp.text.trim(),
      'keterangan': keterangan.text.trim(),
    };
    ntpn.dispose();
    npwp.dispose();
    namaWp.dispose();
    keterangan.dispose();
    tanggal.dispose();
    if (ok != true || !mounted) return;
    if (isi['ntpn']!.isEmpty) {
      _pesan('NTPN wajib diisi sebagai bukti setor.', sukses: false);
      return;
    }
    try {
      final r = await ApiClient.instance.aksi('pengadaan_pajak_setor', {
        'jenis': jenis,
        ...isi,
        'detail': _dipilih.map((id) => {'detail_id': id}).toList(),
      });
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      _pesan(
          sukses
              ? 'Setoran ${r['kode'] ?? ''} tercatat: ${_fmtRp.format(r['nilai'] ?? 0)}'
              : '${r['description'] ?? 'Gagal mencatat setoran.'}',
          sukses: sukses);
      if (sukses) {
        _dipilih.clear();
        await _muat();
      }
    } catch (e) {
      _pesan('Gagal: $e', sukses: false);
    }
  }

  Future<void> _batal(Map<String, dynamic> row) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Batalkan Setoran'),
        content: Text('Batalkan setoran ${row['kode']} (NTPN ${row['ntpn']})? '
            'Pajaknya kembali menjadi terutang dan dapat disetor ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Batalkan')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      final r = await ApiClient.instance
          .aksi('pengadaan_pajak_batal', {'id': row['id']});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      _pesan(
          sukses
              ? 'Setoran dibatalkan; ${r['barisDilepas'] ?? 0} baris kembali terutang.'
              : '${r['description'] ?? 'Gagal membatalkan setoran.'}',
          sukses: sukses);
      if (sukses) await _muat();
    } catch (e) {
      _pesan('Gagal: $e', sukses: false);
    }
  }

  Widget _kotak(String label, String nilai) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(nilai, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanPajak,
      judul: 'Bayar Pajak',
      subjudul: 'Setor PPh yang dipotong dan catat PPN dari pembayaran vendor',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      body: Column(children: [
        TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Terutang'),
            Tab(text: 'Riwayat Setoran'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [_tabTerutang(), _tabSetoran()],
          ),
        ),
      ]),
    );
  }

  Widget _tabTerutang() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_galat!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    if (_terutang.isEmpty) {
      return const Center(
        child: Text(
            'Tidak ada pajak terutang.\nPajak muncul di sini setelah pembayaran '
            'vendor disetujui.',
            textAlign: TextAlign.center),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          _kotak('Baris', '${_terutang.length}'),
          _kotak('PPh terutang', _fmtRp.format(_totalPph)),
          _kotak('PPN tercatat', _fmtRp.format(_totalPpn)),
          _kotak('Dipilih', '${_dipilih.length}'),
        ]),
      ),
      Expanded(child: _daftarTerutang()),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Text(
                'Terpilih: PPh ${_fmtRp.format(_totalDipilih('pph'))} · '
                'PPN ${_fmtRp.format(_totalDipilih('ppn'))}',
                style: const TextStyle(fontSize: 12)),
          ),
          OutlinedButton.icon(
              onPressed: () => _setor('PPN'),
              icon: const Icon(Icons.receipt_outlined, size: 18),
              label: const Text('Setor PPN')),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: () => _setor('PPH'),
              icon: const Icon(Icons.account_balance, size: 18),
              label: const Text('Setor PPh')),
        ]),
      ),
    ]);
  }

  Widget _daftarTerutang() {
    return ListView.builder(
      itemCount: _terutang.length,
      itemBuilder: (_, i) {
        final r = _terutang[i];
        final id = (r['detail_id'] as num?)?.toInt() ?? 0;
        final namaPajak = '${r['namaPajak'] ?? ''}';
        final rincian = '${r['po'] ?? ''} ${r['termin'] ?? ''} · '
            'DPP ${_fmtRp.format(r['dpp'] ?? 0)}\n'
            'PPh ${_fmtRp.format(r['pph'] ?? 0)}'
            '${namaPajak.isEmpty ? '' : ' ($namaPajak)'} · '
            'PPN ${_fmtRp.format(r['ppn'] ?? 0)}';
        return CheckboxListTile(
          dense: true,
          value: _dipilih.contains(id),
          onChanged: (v) => setState(() {
            if (v == true) {
              _dipilih.add(id);
            } else {
              _dipilih.remove(id);
            }
          }),
          title: Text('${r['bayar'] ?? '-'} · ${r['penyedia'] ?? '-'}'),
          subtitle: Text(rincian, style: const TextStyle(fontSize: 11)),
          isThreeLine: true,
        );
      },
    );
  }

  Widget _tabSetoran() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_setoran.isEmpty) {
      return const Center(child: Text('Belum ada setoran pajak tercatat.'));
    }
    return AppDataTable(
      minWidth: 1080,
      emptyText: 'Belum ada setoran.',
      columns: const [
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Jenis', flex: 2),
        AppTableColumn('DPP', flex: 2, align: TextAlign.right),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('NTPN', flex: 3),
        AppTableColumn('Tanggal setor', flex: 2),
        AppTableColumn('Aksi', width: 90),
      ],
      rows: _setoran.map(_barisSetoran).toList(),
    );
  }

  AppTableRowData _barisSetoran(Map<String, dynamic> r) {
    final aktif = r['aktif'] == true;
    final jenisPajak = '${r['jenisPajak'] ?? ''}';
    return AppTableRowData(cells: [
      AppTableCell.text('${r['kode'] ?? '-'}', flex: 2),
      AppTableCell.text(
          '${r['jenis'] ?? ''}${jenisPajak.isEmpty ? '' : ' · $jenisPajak'}',
          flex: 2),
      AppTableCell.text(_fmtRp.format(r['dpp'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell.text(_fmtRp.format(r['nilai'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell.text('${r['ntpn'] ?? '-'}', flex: 3),
      AppTableCell.text('${r['tanggalSetor'] ?? '-'}', flex: 2),
      AppTableCell(
        width: 90,
        child: aktif
            ? IconButton(
                tooltip: 'Batalkan setoran',
                icon: const Icon(Icons.undo, size: 18),
                onPressed: () => _batal(r))
            : const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('dibatalkan',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
      ),
    ]);
  }
}
