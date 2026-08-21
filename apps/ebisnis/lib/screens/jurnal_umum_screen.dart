import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

/// Layar **Jurnal Umum** — pencatatan jurnal manual dari POS.
///
/// Padanan layar ZK `GrupTransaksiAction` + `TransaksiJurnalUmumHelper`, memakai entitas yang sama
/// (`GrupTransaksi` sebagai kepala, `Transaksi` sebagai baris) sehingga jurnal dari POS dan dari ZK
/// berada di satu buku besar yang sama.
///
/// Alur yang dipakai layar ini sengaja dua tahap:
/// **isi jurnal → simpan sebagai DRAF → periksa → POSTING**. Selama masih draf, jurnal belum
/// terbaca laporan keuangan (semua laporan menyaring jurnal terposting), jadi salah ketik masih
/// bisa diperbaiki. Setelah diposting, jurnal terkunci; untuk mengoreksinya harus dibatalkan
/// posting-nya lebih dulu.
class JurnalUmumScreen extends StatefulWidget {
  const JurnalUmumScreen({super.key});

  @override
  State<JurnalUmumScreen> createState() => _JurnalUmumScreenState();
}

class _JurnalUmumScreenState extends State<JurnalUmumScreen> {
  final _fmtTanggal = DateFormat('yyyy-MM-dd');
  final _fmtAngka = NumberFormat.decimalPattern('id');

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;
  List<Map<String, dynamic>> _jurnal = [];
  List<Map<String, dynamic>> _jenisTransaksi = [];
  List<Map<String, dynamic>> _akun = [];
  String _tanggalClosing = '';

  late DateTime _mulai;
  late DateTime _sampai;
  String _cari = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _mulai = DateTime(kini.year, kini.month, 1);
    _sampai = DateTime(kini.year, kini.month + 1, 0);
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('jurnal_umum_list', {
        'mulai': _fmtTanggal.format(_mulai),
        'sampai': _fmtTanggal.format(_sampai),
        'cari': _cari,
        'status': _status,
      });
      final jenis =
          await ApiClient.instance.aksi('jurnal_umum_jenis_transaksi', {});
      // Daftar akun dipakai pemilih akun di editor; sekali muat, dipakai semua baris.
      final akun = await ApiClient.instance.aksi('akun_list', {'limit': 5000});
      if (!mounted) return;
      setStateIfMounted(() {
        _jurnal = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _jenisTransaksi =
            ((jenis['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _akun = ((akun['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _tanggalClosing = '${hasil['tanggalClosing'] ?? ''}';
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _pilihTanggal(bool awal) async {
    final pilih = await showDatePicker(
      context: context,
      initialDate: awal ? _mulai : _sampai,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (pilih == null) return;
    setStateIfMounted(() {
      if (awal) {
        _mulai = pilih;
      } else {
        _sampai = pilih;
      }
    });
    await _muat();
  }

  Future<void> _bukaEditor({Map<String, dynamic>? jurnal}) async {
    if (_akun.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bagan akun belum termuat. Coba muat ulang halaman.')));
      return;
    }
    List<Map<String, dynamic>> barisAwal = [];
    Map<String, dynamic>? kepala;
    if (jurnal != null) {
      setStateIfMounted(() => _sibuk = true);
      try {
        final d = await ApiClient.instance
            .aksi('jurnal_umum_detail', {'id': jurnal['id']});
        kepala = (d['kepala'] as Map?)?.cast<String, dynamic>();
        barisAwal = ((d['baris'] as List?) ?? []).cast<Map<String, dynamic>>();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Gagal memuat jurnal: $e')));
        }
        setStateIfMounted(() => _sibuk = false);
        return;
      }
      setStateIfMounted(() => _sibuk = false);
    }
    if (!mounted) return;
    final tersimpan = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditorJurnal(
        akun: _akun,
        jenisTransaksi: _jenisTransaksi,
        tanggalClosing: _tanggalClosing,
        kepala: kepala,
        barisAwal: barisAwal,
      ),
    );
    if (tersimpan == true) await _muat();
  }

  Future<void> _aksiJurnal(Map<String, dynamic> j, String aksi) async {
    final terposting = j['terposting'] == true;
    String tanya;
    if (aksi == 'jurnal_umum_posting') {
      tanya =
          'Posting jurnal ${j['kode']} ke buku besar? Setelah diposting, jurnal '
          'ikut terbaca laporan keuangan dan tidak dapat diubah lagi.';
    } else if (aksi == 'jurnal_umum_batal_posting') {
      tanya =
          'Batalkan posting jurnal ${j['kode']}? Jurnal kembali menjadi draf dan '
          'ditarik keluar dari laporan keuangan.';
    } else {
      tanya =
          'Hapus jurnal ${j['kode']} beserta seluruh barisnya? Tindakan ini tidak '
          'dapat dibatalkan.';
    }
    if (terposting && aksi == 'jurnal_umum_hapus') return;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text(tanya),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Lanjut')),
        ],
      ),
    );
    if (setuju != true) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil = await ApiClient.instance.aksi(aksi, {'id': j['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Selesai.'}')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _postingSemuaDraf() async {
    final draf = _jurnal.where((j) => j['terposting'] != true).toList();
    if (draf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada jurnal draf pada periode ini.')));
      return;
    }
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Posting Semua Draf'),
        content:
            Text('${draf.length} jurnal draf akan diposting ke buku besar. '
                'Jurnal yang tidak seimbang akan dilewati.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Posting')),
        ],
      ),
    );
    if (setuju != true) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final ids = draf.map((e) => e['id']).toList();
      final hasil = await ApiClient.instance.aksi('jurnal_umum_posting', {'ids': ids});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Selesai.'}')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  String _rp(num? v) => _fmtAngka.format((v ?? 0).round());

  @override
  Widget build(BuildContext context) {
    final draf = _jurnal.where((j) => j['terposting'] != true).length;
    return AppShell(
      menuAktif: MenuEBisnis.jurnalUmum,
      judul: 'Jurnal Umum',
      subjudul: 'Jurnal manual: koreksi, penyesuaian, biaya, dan saldo awal',
      scrollable: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sibuk ? null : () => _bukaEditor(),
        icon: const Icon(Icons.post_add),
        label: const Text('Jurnal Baru'),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pilihTanggal(true),
                icon: const Icon(Icons.event, size: 18),
                label: Text('Mulai ${_fmtTanggal.format(_mulai)}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pilihTanggal(false),
                icon: const Icon(Icons.event_available, size: 18),
                label: Text('Sampai ${_fmtTanggal.format(_sampai)}'),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(
                      labelText: 'Cari kode / keterangan',
                      prefixIcon: Icon(Icons.search),
                      isDense: true),
                  onChanged: (v) => _cari = v,
                  onSubmitted: (_) => _muat(),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _status,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Semua status')),
                    DropdownMenuItem(value: 'draf', child: Text('Draf saja')),
                    DropdownMenuItem(
                        value: 'terposting', child: Text('Terposting saja')),
                  ],
                  onChanged: (v) {
                    setStateIfMounted(() => _status = v ?? '');
                    _muat();
                  },
                ),
              ),
              FilledButton.icon(
                  onPressed: _memuat ? null : _muat,
                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: const Text('Terapkan')),
              if (draf > 0)
                OutlinedButton.icon(
                    onPressed: _sibuk ? null : _postingSemuaDraf,
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: Text('Posting Semua Draf ($draf)')),
              if (_sibuk)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
        const SizedBox(height: 8),
        if (_tanggalClosing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.lock_clock, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Buku sudah ditutup sampai $_tanggalClosing — jurnal bertanggal sebelum '
                    'itu akan ditolak sistem.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _galat != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ]))
                  : AppDataTable(
                      minWidth: 980,
                      emptyText: 'Belum ada jurnal umum pada periode ini. '
                          'Tekan "Jurnal Baru" untuk membuat.',
                      columns: const [
                        AppTableColumn('Kode', flex: 3),
                        AppTableColumn('Tanggal', flex: 2),
                        AppTableColumn('Keterangan', flex: 5),
                        AppTableColumn('Debet',
                            flex: 2, align: TextAlign.right),
                        AppTableColumn('Kredit',
                            flex: 2, align: TextAlign.right),
                        AppTableColumn('Status', flex: 2),
                        AppTableColumn('Aksi', width: 64),
                      ],
                      rows: _jurnal.map((j) {
                        final terposting = j['terposting'] == true;
                        return AppTableRowData(cells: [
                          AppTableCell.text('${j['kode'] ?? ''}', flex: 3),
                          AppTableCell.text('${j['tanggal'] ?? ''}', flex: 2),
                          AppTableCell.text(
                              '${j['keterangan'] ?? ''}'
                              '${(j['jumlahBaris'] ?? 0) > 0 ? '  (${j['jumlahBaris']} baris)' : ''}',
                              flex: 5),
                          AppTableCell.text(_rp(j['totalDebet'] as num?),
                              flex: 2, align: TextAlign.right),
                          AppTableCell.text(_rp(j['totalKredit'] as num?),
                              flex: 2, align: TextAlign.right),
                          AppTableCell(
                            flex: 2,
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(terposting ? 'Terposting' : 'Draf',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                          AppTableCell(
                            width: 64,
                            align: TextAlign.center,
                            child: AksiBarisMenu(aksi: [
                              AksiBaris(
                                  ikon: terposting
                                      ? Icons.visibility_outlined
                                      : Icons.edit_outlined,
                                  label: terposting ? 'Lihat' : 'Ubah',
                                  onTap: _sibuk
                                      ? null
                                      : () => _bukaEditor(jurnal: j)),
                              // Posting dan Batalkan posting dahulu saling
                              // menggantikan; kini keduanya tetap tampil dan yang
                              // tidak berlaku hanya diredupkan.
                              AksiBaris(
                                  ikon: Icons.check_circle_outline,
                                  label: 'Posting ke buku besar',
                                  onTap: _sibuk || terposting
                                      ? null
                                      : () => _aksiJurnal(
                                          j, 'jurnal_umum_posting')),
                              AksiBaris(
                                  ikon: Icons.undo,
                                  label: 'Batalkan posting',
                                  onTap: _sibuk || !terposting
                                      ? null
                                      : () => _aksiJurnal(
                                          j, 'jurnal_umum_batal_posting')),
                              AksiBaris(
                                  ikon: Icons.delete_outline,
                                  label: 'Hapus',
                                  merusak: true,
                                  onTap: _sibuk || terposting
                                      ? null
                                      : () =>
                                          _aksiJurnal(j, 'jurnal_umum_hapus')),
                            ]),
                          ),
                        ]);
                      }).toList(),
                    ),
        ),
      ]),
    );
  }
}

/// Editor satu jurnal: kepala + baris debet/kredit, dengan indikator keseimbangan.
class _EditorJurnal extends StatefulWidget {
  const _EditorJurnal({
    required this.akun,
    required this.jenisTransaksi,
    required this.tanggalClosing,
    required this.kepala,
    required this.barisAwal,
  });

  final List<Map<String, dynamic>> akun;
  final List<Map<String, dynamic>> jenisTransaksi;
  final String tanggalClosing;
  final Map<String, dynamic>? kepala;
  final List<Map<String, dynamic>> barisAwal;

  @override
  State<_EditorJurnal> createState() => _EditorJurnalState();
}

class _BarisJurnal {
  int? akunId;
  final TextEditingController debet = TextEditingController();
  final TextEditingController kredit = TextEditingController();
  final TextEditingController keterangan = TextEditingController();

  void buang() {
    debet.dispose();
    kredit.dispose();
    keterangan.dispose();
  }
}

class _EditorJurnalState extends State<_EditorJurnal> {
  final _fmtTanggal = DateFormat('yyyy-MM-dd');
  final _fmtAngka = NumberFormat.decimalPattern('id');
  final _keterangan = TextEditingController();
  final List<_BarisJurnal> _baris = [];
  DateTime _tanggal = DateTime.now();
  int? _jenisId;
  bool _menyimpan = false;
  String? _pesan;

  bool get _terkunci => widget.kepala?['terposting'] == true;

  @override
  void initState() {
    super.initState();
    final k = widget.kepala;
    if (k != null) {
      _keterangan.text = '${k['keterangan'] ?? ''}';
      final t = '${k['tanggal'] ?? ''}';
      if (t.isNotEmpty) {
        _tanggal = DateTime.tryParse(t) ?? DateTime.now();
      }
      final jid = k['jenisTransaksiId'];
      _jenisId = jid is num ? jid.toInt() : null;
    }
    if (widget.barisAwal.isEmpty) {
      _tambahBaris();
      _tambahBaris();
    } else {
      for (final b in widget.barisAwal) {
        final row = _BarisJurnal();
        row.akunId = (b['akunId'] as num?)?.toInt();
        final d = (b['debet'] as num?)?.toDouble() ?? 0;
        final k2 = (b['kredit'] as num?)?.toDouble() ?? 0;
        if (d > 0) row.debet.text = d.toStringAsFixed(0);
        if (k2 > 0) row.kredit.text = k2.toStringAsFixed(0);
        row.keterangan.text = '${b['keterangan'] ?? ''}';
        _baris.add(row);
      }
    }
  }

  @override
  void dispose() {
    _keterangan.dispose();
    for (final b in _baris) {
      b.buang();
    }
    super.dispose();
  }

  void _tambahBaris() => setStateIfMounted(() => _baris.add(_BarisJurnal()));

  void _hapusBaris(int i) {
    if (_baris.length <= 2) return;
    setStateIfMounted(() {
      _baris.removeAt(i).buang();
    });
  }

  double _angka(TextEditingController c) {
    final t = c.text
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  double get _totalDebet => _baris.fold(0.0, (a, b) => a + _angka(b.debet));
  double get _totalKredit => _baris.fold(0.0, (a, b) => a + _angka(b.kredit));
  double get _selisih => _totalDebet - _totalKredit;
  bool get _seimbang => _selisih.abs() < 0.005 && _totalDebet > 0;

  Future<void> _simpan() async {
    setStateIfMounted(() {
      _menyimpan = true;
      _pesan = null;
    });
    try {
      final baris = <Map<String, dynamic>>[];
      for (final b in _baris) {
        final d = _angka(b.debet);
        final k = _angka(b.kredit);
        if (b.akunId == null && d == 0 && k == 0)
          continue; // baris kosong diabaikan
        baris.add({
          'akunId': b.akunId ?? 0,
          'debet': d,
          'kredit': k,
          'keterangan': b.keterangan.text.trim(),
        });
      }
      // Lokal-dulu untuk PENYIMPANAN draf jurnal. Yang tetap wajib daring adalah
      // POSTING-nya (jurnal_umum_posting) -- itu "journal posting" pada spec 13.3
      // dan dikunci uji master_offline_kontrak_test. Menyimpan draf tidak memakai
      // id balasan server, jadi aman diantre.
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'jurnal_umum_simpan',
        kunci: widget.kepala?['id'] != null
            ? 'jurnal_umum:${widget.kepala!['id']}'
            : 'jurnal_umum:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:jurnal_umum',
        rowLokal: {
          if (widget.kepala?['id'] != null) 'id': widget.kepala!['id'],
          'tanggal': _fmtTanggal.format(_tanggal),
          'keterangan': _keterangan.text.trim(),
        },
        body: {
          if (widget.kepala?['id'] != null) 'id': widget.kepala!['id'],
          'tanggal': _fmtTanggal.format(_tanggal),
          'keterangan': _keterangan.text.trim(),
          'jenisTransaksiId': _jenisId ?? 0,
          'baris': baris,
        },
      );
      if (!mounted) return;
      if ('${hasil['status']}' != '00') {
        setStateIfMounted(
            () => _pesan = '${hasil['message'] ?? 'Gagal menyimpan.'}');
        return;
      }
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Tersimpan.'}')));
    } catch (e) {
      setStateIfMounted(() => _pesan = 'Gagal menyimpan: $e');
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  String _rp(double v) => _fmtAngka.format(v.round());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                    _terkunci
                        ? 'Jurnal ${widget.kepala?['kode'] ?? ''} (terposting — hanya dilihat)'
                        : widget.kepala == null
                            ? 'Jurnal Umum Baru'
                            : 'Ubah Jurnal ${widget.kepala?['kode'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _terkunci
                        ? null
                        : () async {
                            final p = await showDatePicker(
                                context: context,
                                initialDate: _tanggal,
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2100));
                            if (p != null)
                              setStateIfMounted(() => _tanggal = p);
                          },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Tanggal ${_fmtTanggal.format(_tanggal)}'),
                  ),
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int?>(
                      value: _jenisId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Jenis Transaksi (penomoran)',
                          isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('-- Otomatis (JU) --')),
                        ...widget.jenisTransaksi
                            .map((j) => DropdownMenuItem<int?>(
                                  value: (j['id'] as num?)?.toInt(),
                                  child: Text(
                                      '${j['kode'] ?? ''} ${j['nama'] ?? ''}',
                                      overflow: TextOverflow.ellipsis),
                                )),
                      ],
                      onChanged: _terkunci
                          ? null
                          : (v) => setStateIfMounted(() => _jenisId = v),
                    ),
                  ),
                  SizedBox(
                    width: 340,
                    child: TextField(
                      controller: _keterangan,
                      readOnly: _terkunci,
                      decoration: const InputDecoration(
                          labelText: 'Keterangan jurnal *', isDense: true),
                    ),
                  ),
                ]),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _baris.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final b = _baris[i];
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: PemilihAkunField(
                            label: 'Akun baris ${i + 1}',
                            daftar: widget.akun,
                            nilai: b.akunId,
                            onChanged: _terkunci
                                ? (_) {}
                                : (v) => setStateIfMounted(() => b.akunId = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: b.debet,
                            readOnly: _terkunci,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                                labelText: 'Debet', isDense: true),
                            onChanged: (_) => setStateIfMounted(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: b.kredit,
                            readOnly: _terkunci,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                                labelText: 'Kredit', isDense: true),
                            onChanged: (_) => setStateIfMounted(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: b.keterangan,
                            readOnly: _terkunci,
                            decoration: const InputDecoration(
                                labelText: 'Keterangan baris', isDense: true),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus baris',
                          onPressed: _terkunci || _baris.length <= 2
                              ? null
                              : () => _hapusBaris(i),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ]);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              if (!_terkunci)
                OutlinedButton.icon(
                    onPressed: _tambahBaris,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Baris')),
              const Spacer(),
              Text('Debet ${_rp(_totalDebet)}   Kredit ${_rp(_totalKredit)}   ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                    _seimbang ? Icons.check_circle : Icons.error_outline,
                    size: 16),
                label: Text(
                    _seimbang ? 'Seimbang' : 'Selisih ${_rp(_selisih.abs())}'),
              ),
            ]),
            if (_pesan != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_pesan!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_terkunci ? 'Tutup' : 'Batal')),
              const SizedBox(width: 8),
              if (!_terkunci)
                FilledButton.icon(
                  onPressed: _menyimpan || !_seimbang ? null : _simpan,
                  icon: _menyimpan
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan sebagai Draf'),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
