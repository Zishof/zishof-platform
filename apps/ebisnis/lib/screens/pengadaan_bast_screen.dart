import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';

import 'pengadaan_bulk_entry_screen.dart';

/// Layar "Penerimaan Barang/Jasa (BAST)" -- tahap 3 modul Pengadaan POS.
///
/// Memakai TABEL PENGADAAN BERSAMA dengan JSP dan ZKoss (dibedakan kolom toko);
/// barang menunjuk MasterAsset.
///
/// Dua hal membedakannya dari PR/PO:
/// - Model penerimaan yang sudah ada TIDAK punya kolom penolakan, jadi keputusan yang
///   tersedia hanya Setujui dan Batalkan -- BAST keliru diperbaiki atau dihapus.
/// - Nilai baris dihitung rumus milik entitas (diterima x harga, dikurangi potongan,
///   ditambah PPN), sama persis dengan versi ZKoss; layar hanya menampilkan pratinjau.
class PengadaanBastScreen extends StatefulWidget {
  const PengadaanBastScreen({super.key});

  @override
  State<PengadaanBastScreen> createState() => _PengadaanBastScreenState();
}

class _PengadaanBastScreenState extends State<PengadaanBastScreen> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];
  String _cari = '';
  String _status = '';
  int _halaman = 1;
  int _total = 0;
  static const _pageSize = 15;

  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'pengadaan_bast_daftar',
        {
          if (_cari.isNotEmpty) 'cari': _cari,
          if (_status.isNotEmpty) 'status': _status,
          'page': _halaman,
          'pageSize': _pageSize,
        },
        'master:pengadaan_bast:${_status}_${_cari}_$_halaman',
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat = '${res['description'] ?? 'Gagal memuat Penerimaan Barang.'}';
              _memuat = false;
            });
            return;
          }
          final data = ((res['data'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final dariServer = res['dariServer'] == true;
          setStateIfMounted(() {
            _daftar = data;
            _total = dariServer
                ? (res['total'] as num?)?.toInt() ?? data.length
                : data.length;
            _idBaru = dariServer
                ? Set<String>.from(res['idBaru'] as Set? ?? const <String>{})
                : {};
            _idBerubah = dariServer
                ? Set<String>.from(res['idBerubah'] as Set? ?? const <String>{})
                : {};
            _jumlahHapus = dariServer ? (res['jumlahHapus'] as int? ?? 0) : 0;
            if (dariServer &&
                (_idBaru.isNotEmpty || _idBerubah.isNotEmpty || _jumlahHapus > 0)) {
              _versiPerubahan++;
            }
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _form({Map<String, dynamic>? awal, Map<String, dynamic>? dariPo}) async {
    Map<String, dynamic>? detailAwal;
    if (awal != null && awal['id'] != null) {
      try {
        final r = await ApiClient.instance
            .aksi('pengadaan_bast_detail', {'id': awal['id']});
        detailAwal = Map<String, dynamic>.from(r);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat detail BAST: $e')));
        return;
      }
    }
    if (!mounted) return;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _FormBastDialog(awal: awal, detailAwal: detailAwal, dariPo: dariPo),
    );
    if (hasil == null || !mounted) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_bast_simpan',
        body: hasil,
        kunci: hasil['id'] != null
            ? 'pengadaan_bast:${hasil['id']}'
            : 'pengadaan_bast:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:pengadaan_bast',
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  /// Terima barang dari PO yang sudah disetujui. Server mengembalikan SISA yang
  /// belum diterima per baris, sehingga satu PO dapat diterima bertahap tanpa
  /// penerimaan berlebih.
  Future<void> _dariPo() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PilihPoDialog(),
    );
    if (pilihan == null || !mounted) return;
    try {
      final r = await ApiClient.instance
          .aksi('pengadaan_bast_dari_po', {'po_id': pilihan['id']});
      if (!mounted) return;
      if (r['status'] != '00' && r['status'] != 'success') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['description'] ?? 'Gagal menyiapkan penerimaan.'}'),
            backgroundColor: Theme.of(context).colorScheme.error));
        return;
      }
      final isian = (r['detail'] as List?) ?? const [];
      if (isian.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['catatan'] ?? 'Tidak ada sisa yang perlu diterima '
                'dari PO ini.'}')));
        return;
      }
      await _form(dariPo: Map<String, dynamic>.from(r));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  /// Keputusan atas BAST. Hanya SETUJUI dan BATAL -- model penerimaan yang sudah
  /// ada tidak menyediakan kolom penolakan.
  Future<void> _putusan(Map<String, dynamic> bast, String keputusan) async {
    try {
      final r = await ApiClient.instance.aksi('pengadaan_bast_putusan', {
        'id': bast['id'],
        'keputusan': keputusan,
      });
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sukses
              ? 'Keputusan tersimpan: ${r['statusDokumen'] ?? keputusan}'
              : '${r['description'] ?? 'Gagal menyimpan keputusan.'}'),
          backgroundColor: sukses ? null : Theme.of(context).colorScheme.error));
      if (sukses) await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _hapus(Map<String, dynamic> bast) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Penerimaan Barang'),
        content: Text('Hapus BAST ${bast['kode']}? Hanya dokumen berstatus DRAFT '
            'yang dapat dihapus; yang sudah disetujui menjadi dasar tagihan vendor.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_bast_hapus',
        body: {'id': bast['id']},
        kunci: 'pengadaan_bast:${bast['id']}',
        cacheKey: 'master:pengadaan_bast',
        rowLokal: {'id': bast['id']},
        hapusLokal: true,
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menghapus: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }


  /// Bulk entry mengikuti skema Kulakan: header, tempel/Excel, tabel item, review.
  Future<void> _bulkEntry() async {
    final hasil = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => const PengadaanBulkEntryScreen(
              jenis: JenisPengadaanBulk.bast)),
    );
    if (hasil == true && mounted) await _muat();
  }


  /// Sinkronkan penerimaan yang sudah disetujui ke stok POS lewat Kulakan.
  /// Server menolak sinkronisasi kedua karena akan menggandakan stok, jadi
  /// konfirmasinya menegaskan bahwa langkah ini hanya sekali.
  Future<void> _sinkronKulakan(Map<String, dynamic> bast) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sinkronkan ke Kulakan'),
        content: Text('Tambahkan barang pada ${bast['kode']} ke stok toko '
            'sebagai faktur Kulakan? Langkah ini hanya dapat dilakukan sekali '
            'untuk penerimaan ini.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Sinkronkan')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      final r = await ApiClient.instance
          .aksi('pengadaan_bast_sinkron_kulakan', {'id': bast['id']});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sukses
              ? 'Stok bertambah lewat faktur ${r['nomorFaktur'] ?? ''} '
                  '(${r['jumlahBaris'] ?? 0} baris).'
              : '${r['description'] ?? 'Gagal menyinkronkan.'}'),
          backgroundColor: sukses ? null : Theme.of(context).colorScheme.error));
      if (sukses) await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanBast,
      judul: 'Penerimaan Barang/Jasa (BAST)',
      subjudul: 'Catat barang yang datang dari penyedia',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            onPressed: _bulkEntry,
            tooltip: 'Bulk entry (tempel / Excel)',
            icon: const Icon(Icons.table_view_outlined)),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      floatingActionButton: Row(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.extended(
          heroTag: 'bast_dari_po',
          onPressed: _dariPo,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('Dari PO'),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.extended(
          heroTag: 'bast_langsung',
          onPressed: () => _form(),
          icon: const Icon(Icons.add),
          label: const Text('Terima Langsung'),
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                    labelText: 'Cari kode / keterangan / no. tagihan',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onSubmitted: (v) {
                  setStateIfMounted(() {
                    _cari = v.trim();
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _status,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Status', isDense: true),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Semua status')),
                  DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                  DropdownMenuItem(value: 'DISETUJUI', child: Text('Disetujui')),
                ],
                onChanged: (v) {
                  setStateIfMounted(() {
                    _status = v ?? '';
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BannerPerubahanServer(
            key: ValueKey('perubahan:$_versiPerubahan'),
            baru: _idBaru.length,
            berubah: _idBerubah.length,
            dihapus: _jumlahHapus,
          ),
        ),
        Expanded(child: _isiTabel(totalHalaman)),
      ]),
    );
  }

  Widget _isiTabel(int totalHalaman) {
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
    if (_daftar.isEmpty) {
      return const Center(
        child: Text(
            'Belum ada Penerimaan Barang.\nTekan "Dari PO" untuk menerima pesanan '
            'yang sudah disetujui, atau "Terima Langsung" untuk pembelian tanpa PO.',
            textAlign: TextAlign.center),
      );
    }
    return AppDataTable(
      minWidth: 1050,
      emptyText: 'Tidak ada BAST pada filter ini.',
      columns: const [
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Tanggal', flex: 2),
        AppTableColumn('Penyedia', flex: 3),
        AppTableColumn('Sumber', flex: 2),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('Status', flex: 2),
        AppTableColumn('Aksi', width: 190),
      ],
      rows: _daftar.map(_barisBast).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: 'BAST',
              onSebelumnya: _halaman > 1
                  ? () {
                      setStateIfMounted(() => _halaman--);
                      _muat();
                    }
                  : null,
              onBerikutnya: _halaman < totalHalaman
                  ? () {
                      setStateIfMounted(() => _halaman++);
                      _muat();
                    }
                  : null,
            )
          : null,
    );
  }

  AppTableRowData _barisBast(Map<String, dynamic> bast) {
    final st = '${bast['status'] ?? 'DRAFT'}';
    final disetujui = st == 'DISETUJUI';
    final warna =
        disetujui ? const Color(0xFF2E7D32) : const Color(0xFFB8860B);
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 2,
        child: KilauBaris(
          kunci: '${bast['id'] ?? ''}',
          idBaru: _idBaru,
          idBerubah: _idBerubah,
          child: Text('${bast['kode'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      AppTableCell.text('${bast['tanggal'] ?? '-'}', flex: 2),
      AppTableCell.text('${bast['penyedia'] ?? '-'}', flex: 3),
      AppTableCell.text(
          bast['tanpaPemesanan'] == true ? 'Tanpa PO' : '${bast['po'] ?? '-'}',
          flex: 2),
      AppTableCell.text(_fmtRp.format(bast['nilai'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell(
        flex: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: warna.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(6)),
          child: Text(st,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: warna)),
        ),
      ),
      AppTableCell(width: 190, child: _aksiBast(bast, disetujui)),
    ]);
  }

  Widget _aksiBast(Map<String, dynamic> bast, bool disetujui) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          tooltip: 'Lihat / ubah',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => _form(awal: bast)),
      if (!disetujui)
        IconButton(
            tooltip: 'Setujui',
            icon: const Icon(Icons.check_circle_outline,
                size: 18, color: Color(0xFF2E7D32)),
            onPressed: () => _putusan(bast, 'SETUJUI')),
      if (disetujui)
        IconButton(
            tooltip: 'Batalkan persetujuan',
            icon: const Icon(Icons.undo, size: 18),
            onPressed: () => _putusan(bast, 'BATAL')),
      if (disetujui && bast['sudahSinkron'] != true)
        IconButton(
            tooltip: 'Sinkronkan ke stok Kulakan',
            icon: const Icon(Icons.sync_alt, size: 18, color: Color(0xFF00695C)),
            onPressed: () => _sinkronKulakan(bast)),
      if (bast['sudahSinkron'] == true)
        Tooltip(
          message: 'Sudah masuk stok lewat faktur ${bast['nomorFakturKulakan'] ?? ''}',
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.check_circle, size: 18, color: Color(0xFF00695C)),
          ),
        ),
      if (bast['id'] != null)
        IconButton(
            tooltip: 'Riwayat data (AuditTrails)',
            icon: const Icon(Icons.history, size: 18),
            onPressed: () => tampilkanRiwayatData(context,
                entitas: 'pengadaan_bast',
                id: bast['id'],
                judul: '${bast['kode'] ?? ''}')),
      if (!disetujui)
        IconButton(
            tooltip: 'Hapus',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _hapus(bast)),
    ]);
  }
}

/// Pemilih PO yang sudah disetujui, sebagai sumber penerimaan.
class _PilihPoDialog extends StatefulWidget {
  const _PilihPoDialog();

  @override
  State<_PilihPoDialog> createState() => _PilihPoDialogState();
}

class _PilihPoDialogState extends State<_PilihPoDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  List<Map<String, dynamic>> _hasil = [];
  bool _memuat = true;
  final _cari = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final r = await ApiClient.instance.aksi('pengadaan_po_daftar', {
        'status': 'DISETUJUI',
        if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
        'page': 1,
        'pageSize': 50,
      });
      _hasil = ((r['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _hasil = [];
    }
    setStateIfMounted(() => _memuat = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Pemesanan Pembelian'),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(children: [
          TextField(
            controller: _cari,
            decoration: InputDecoration(
                labelText: 'Cari kode / keterangan PO',
                suffixIcon:
                    IconButton(onPressed: _muat, icon: const Icon(Icons.search))),
            onSubmitted: (_) => _muat(),
          ),
          const SizedBox(height: 8),
          const Text(
              'Hanya PO berstatus DISETUJUI yang dapat diterima barangnya.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _hasil.isEmpty
                    ? const Center(
                        child: Text('Belum ada PO disetujui yang bisa diterima.'))
                    : ListView.builder(
                        itemCount: _hasil.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          title: Text('${_hasil[i]['kode'] ?? '-'}'),
                          subtitle: Text('${_hasil[i]['penyedia'] ?? ''}'),
                          trailing: Text(_fmtRp.format(_hasil[i]['nilai'] ?? 0)),
                          onTap: () => Navigator.pop(context, _hasil[i]),
                        ),
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
      ],
    );
  }
}

/// Satu baris barang pada form BAST.
class _BarisBast {
  int? barangId;

  /// Id MasterAsset asal, dipakai bila baris berasal dari dokumen hulu
  /// yang barangnya belum berpadanan produk POS.
  int? masterAssetId;
  String namaBarang;

  /// Baris PO asal (null bila penerimaan langsung tanpa PO).
  final int? poDetailId;

  /// Sisa yang masih boleh diterima menurut server; null bila tanpa PO.
  final double? sisaBoleh;
  final TextEditingController diterima;
  final TextEditingController harga;
  final TextEditingController potongan;
  final TextEditingController ppn;
  final TextEditingController kondisi;
  _BarisBast({
    this.barangId,
    this.masterAssetId,
    required this.namaBarang,
    this.poDetailId,
    this.sisaBoleh,
    String diterimaAwal = '1',
    String hargaAwal = '0',
    String potonganAwal = '0',
    String ppnAwal = '0',
    String kondisiAwal = '',
  })  : diterima = TextEditingController(text: diterimaAwal),
        harga = TextEditingController(text: hargaAwal),
        potongan = TextEditingController(text: potonganAwal),
        ppn = TextEditingController(text: ppnAwal),
        kondisi = TextEditingController(text: kondisiAwal);
  void dispose() {
    diterima.dispose();
    harga.dispose();
    potongan.dispose();
    ppn.dispose();
    kondisi.dispose();
  }
}

class _FormBastDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final Map<String, dynamic>? detailAwal;
  final Map<String, dynamic>? dariPo;
  const _FormBastDialog({this.awal, this.detailAwal, this.dariPo});

  @override
  State<_FormBastDialog> createState() => _FormBastDialogState();
}

class _FormBastDialogState extends State<_FormBastDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  late final TextEditingController _keterangan;
  late final TextEditingController _kodeTagihan;
  late final TextEditingController _tglTagihan;
  late final TextEditingController _kurir;
  final List<_BarisBast> _baris = [];
  int? _penyediaId;
  String _penyediaNama = '';
  int? _poId;
  String _poKode = '';
  bool _diskonPersen = false;

  bool get _baru => widget.awal == null;
  String get _status => '${widget.detailAwal?['header']?['status'] ?? 'DRAFT'}';
  bool get _terkunci => _status != 'DRAFT';
  bool get _dariPesanan => _poId != null;

  @override
  void initState() {
    super.initState();
    final h = widget.detailAwal?['header'] as Map?;
    _keterangan = TextEditingController(
        text: '${h?['keterangan'] ?? widget.dariPo?['keterangan'] ?? ''}');
    _kodeTagihan = TextEditingController(text: '${h?['kodeTagihan'] ?? ''}');
    _tglTagihan = TextEditingController(text: '${h?['tanggalTagihan'] ?? ''}');
    _kurir = TextEditingController(text: '${h?['kurir'] ?? ''}');
    _penyediaId = (h?['penyedia_id'] as num?)?.toInt() ??
        (widget.dariPo?['penyedia_id'] as num?)?.toInt();
    _penyediaNama =
        '${h?['penyedia'] ?? widget.dariPo?['penyedia'] ?? ''}';
    _poId = (h?['po_id'] as num?)?.toInt() ??
        (widget.dariPo?['po_id'] as num?)?.toInt();
    _poKode = '${h?['po'] ?? widget.dariPo?['po_kode'] ?? ''}';

    for (final d in ((widget.detailAwal?['detail'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(d as Map);
      _baris.add(_BarisBast(
        barangId: (m['produk_id'] as num?)?.toInt(),
        masterAssetId: (m['master_asset_id'] as num?)?.toInt(),
        namaBarang: '${m['barang'] ?? '-'}',
        poDetailId: (m['po_detail_id'] as num?)?.toInt(),
        sisaBoleh: (m['sisaBolehDiterima'] as num?)?.toDouble(),
        diterimaAwal: '${m['diterima'] ?? 0}',
        hargaAwal: '${m['hargaBeli'] ?? 0}',
        kondisiAwal: '${m['kondisi'] ?? ''}',
      ));
    }
    for (final d in ((widget.dariPo?['detail'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(d as Map);
      _baris.add(_BarisBast(
        barangId: (m['produk_id'] as num?)?.toInt(),
        masterAssetId: (m['master_asset_id'] as num?)?.toInt(),
        namaBarang: '${m['barang'] ?? '-'}',
        poDetailId: (m['po_detail_id'] as num?)?.toInt(),
        sisaBoleh: (m['sisaBolehDiterima'] as num?)?.toDouble(),
        diterimaAwal: '${m['diterima'] ?? 0}',
        hargaAwal: '${m['hargaBeli'] ?? 0}',
      ));
    }
  }

  @override
  void dispose() {
    _keterangan.dispose();
    _kodeTagihan.dispose();
    _tglTagihan.dispose();
    _kurir.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  /// Pratinjau nilai baris memakai rumus yang sama dengan entitas server:
  /// (diterima x harga) dikurangi potongan, lalu ditambah PPN.
  double _subtotal(_BarisBast b) {
    final dpp0 = _angka(b.diterima.text) * _angka(b.harga.text);
    final pot = _diskonPersen
        ? (_angka(b.potongan.text) / 100.0) * dpp0
        : _angka(b.potongan.text);
    final dpp = dpp0 - pot;
    return dpp + (_angka(b.ppn.text) / 100.0) * dpp;
  }

  double get _total => _baris.fold(0, (s, b) => s + _subtotal(b));

  Future<void> _pilihPenyedia() async {
    final q = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    final dipilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> cari() async {
          try {
            final r = await ApiClient.instance.aksi(
                'pengadaan_penyedia_cari', {'keyword': q.text.trim(), 'limit': 50});
            hasil = ((r['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } catch (_) {
            hasil = [];
          }
          setLocal(() {});
        }

        if (hasil.isEmpty && q.text.isEmpty) cari();
        return AlertDialog(
          title: const Text('Pilih Penyedia / Vendor'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(children: [
              TextField(
                controller: q,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Cari kode / nama penyedia',
                    suffixIcon: IconButton(
                        onPressed: cari, icon: const Icon(Icons.search))),
                onSubmitted: (_) => cari(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: hasil.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text('${hasil[i]['nama'] ?? '-'}'),
                    subtitle: Text('${hasil[i]['kode'] ?? ''}'),
                    onTap: () => Navigator.pop(dctx, hasil[i]),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx), child: const Text('Tutup'))
          ],
        );
      }),
    );
    q.dispose();
    if (dipilih == null) return;
    setState(() {
      _penyediaId = (dipilih['id'] as num?)?.toInt();
      _penyediaNama = '${dipilih['nama'] ?? ''}';
    });
  }

  Future<void> _tambahBaris() async {
    final q = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    final dipilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> cari() async {
          try {
            final r = await ApiClient.instance.aksi(
                'pengadaan_barang_cari', {'keyword': q.text.trim(), 'limit': 50});
            hasil = ((r['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } catch (_) {
            hasil = [];
          }
          setLocal(() {});
        }

        return AlertDialog(
          title: const Text('Pilih Barang'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(children: [
              TextField(
                controller: q,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Cari kode / nama barang',
                    suffixIcon: IconButton(
                        onPressed: cari, icon: const Icon(Icons.search))),
                onSubmitted: (_) => cari(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: hasil.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text('${hasil[i]['nama'] ?? '-'}'),
                    subtitle: Text(
                        '${hasil[i]['kode'] ?? ''}  ·  ${hasil[i]['satuan'] ?? ''}'),
                    onTap: () => Navigator.pop(dctx, hasil[i]),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx), child: const Text('Tutup'))
          ],
        );
      }),
    );
    q.dispose();
    if (dipilih == null) return;
    setState(() => _baris.add(_BarisBast(
          barangId: (dipilih['id'] as num?)?.toInt(),
          namaBarang: '${dipilih['nama'] ?? '-'}',
        )));
  }

  Future<void> _pilihTanggal(TextEditingController c) async {
    DateTime awal = DateTime.now();
    final bagian = c.text.split('-');
    if (bagian.length == 3) {
      final d = int.tryParse(bagian[0]),
          m = int.tryParse(bagian[1]),
          y = int.tryParse(bagian[2]);
      if (d != null && m != null && y != null) awal = DateTime(y, m, d);
    }
    final pilih = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pilih == null) return;
    // dd-MM-yyyy adalah format yang dibaca ZKoss pada dokumen yang sama.
    setState(() => c.text = DateFormat('dd-MM-yyyy').format(pilih));
  }

  Widget _barisBarang(_BarisBast b) {
    final sisa = b.sisaBoleh;
    final lebih = sisa != null && _angka(b.diterima.text) > sisa + 1e-6;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(b.namaBarang,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sisa != null)
                  Text('sisa boleh diterima: ${sisa.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 10,
                          color: lebih ? Colors.red : const Color(0xFF00695C))),
              ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
            width: 80,
            child: TextField(
                controller: b.diterima,
                enabled: !_terkunci,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: 'Diterima',
                    isDense: true,
                    errorText: lebih ? 'lebih' : null))),
        const SizedBox(width: 6),
        SizedBox(
            width: 110,
            child: TextField(
                controller: b.harga,
                enabled: !_terkunci,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Harga', isDense: true))),
        const SizedBox(width: 6),
        SizedBox(
            width: 90,
            child: TextField(
                controller: b.potongan,
                enabled: !_terkunci,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: _diskonPersen ? 'Potongan %' : 'Potongan',
                    isDense: true))),
        const SizedBox(width: 6),
        SizedBox(
            width: 70,
            child: TextField(
                controller: b.ppn,
                enabled: !_terkunci,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'PPN %', isDense: true))),
        const SizedBox(width: 6),
        SizedBox(
            width: 110,
            child: Text(_fmtRp.format(_subtotal(b)),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        if (!_terkunci)
          IconButton(
              onPressed: () {
                setState(() => _baris.remove(b));
                b.dispose();
              },
              icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_baru
          ? (_dariPesanan
              ? 'Terima Barang dari $_poKode'
              : 'Terima Barang (tanpa PO)')
          : 'BAST ${widget.awal?['kode'] ?? ''}  ·  $_status'),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_terkunci)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                      'BAST yang sudah disetujui tidak dapat diubah. Batalkan '
                      'persetujuannya terlebih dahulu bila memang perlu dikoreksi.',
                      style: TextStyle(fontSize: 12)),
                ),
              if (_dariPesanan)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF00695C).withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      'Penerimaan atas $_poKode dari $_penyediaNama. Jumlah diterima '
                      'tidak boleh melebihi sisa yang dipesan.',
                      style: const TextStyle(fontSize: 12)),
                ),
              if (!_dariPesanan)
                InkWell(
                  onTap: _terkunci ? null : _pilihPenyedia,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Penyedia / Vendor',
                        isDense: true,
                        suffixIcon: Icon(Icons.search, size: 18)),
                    child: Text(
                        _penyediaNama.isEmpty ? 'Belum dipilih' : _penyediaNama),
                  ),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _kodeTagihan,
                    enabled: !_terkunci,
                    decoration: const InputDecoration(
                        labelText: 'No. tagihan / faktur vendor', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _tglTagihan,
                    enabled: !_terkunci,
                    readOnly: true,
                    onTap: _terkunci ? null : () => _pilihTanggal(_tglTagihan),
                    decoration: const InputDecoration(
                        labelText: 'Tanggal tagihan',
                        isDense: true,
                        suffixIcon: Icon(Icons.event, size: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _kurir,
                    enabled: !_terkunci,
                    decoration: const InputDecoration(
                        labelText: 'Kurir / pengirim', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _keterangan,
                enabled: !_terkunci,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Keterangan penerimaan',
                    hintText: 'Mis. barang diterima lengkap, dus tidak penyok'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: Row(children: [
                  const Expanded(
                      child: Text('Barang yang Diterima',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  if (!_terkunci)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Potongan %', style: TextStyle(fontSize: 11)),
                      Switch(
                        value: _diskonPersen,
                        onChanged: (v) => setState(() => _diskonPersen = v),
                      ),
                    ]),
                  if (!_terkunci && !_dariPesanan)
                    TextButton.icon(
                        onPressed: _tambahBaris,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tambah Barang')),
                ]),
              ),
              if (_baris.isEmpty)
                const Text('Belum ada barang. Tambahkan minimal satu baris.',
                    style: TextStyle(fontSize: 12)),
              for (final b in _baris) _barisBarang(b),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  const Expanded(
                      child: Text('Total Nilai Penerimaan',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(_fmtRp.format(_total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    'Total di atas hanya pratinjau; server menghitung ulang memakai '
                    'rumus yang sama dengan versi ZKoss, termasuk potongan dan PPN.',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        if (!_terkunci)
          FilledButton(onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }

  /// Validasi di layar hanya untuk umpan balik cepat; server tetap menegakkan
  /// aturan yang sama sehingga kanal lain berperilaku identik.
  void _simpan() {
    if (_baris.where((b) => b.barangId != null || b.masterAssetId != null).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tambahkan minimal satu baris barang.')));
      return;
    }
    if (!_dariPesanan && _penyediaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pilih penyedia/vendor untuk penerimaan tanpa PO.')));
      return;
    }
    for (final b in _baris) {
      if (_angka(b.diterima.text) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Jumlah diterima untuk ${b.namaBarang} harus lebih '
                'besar dari nol.')));
        return;
      }
      final sisa = b.sisaBoleh;
      if (sisa != null && _angka(b.diterima.text) > sisa + 1e-6) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Jumlah diterima untuk ${b.namaBarang} melebihi sisa '
                'yang dipesan (${sisa.toStringAsFixed(0)}).')));
        return;
      }
    }
    Navigator.pop(context, <String, dynamic>{
      if (!_baru) 'id': widget.awal!['id'],
      if (_poId != null) 'po_id': _poId,
      if (_penyediaId != null) 'penyedia_id': _penyediaId,
      'keterangan': _keterangan.text.trim(),
      'kodeTagihan': _kodeTagihan.text.trim(),
      'tanggalTagihan': _tglTagihan.text.trim(),
      'kurir': _kurir.text.trim(),
      'detail': _baris
          .where((b) => b.barangId != null || b.masterAssetId != null)
          .map((b) => {
                if (b.barangId != null)
                  'produk_id': b.barangId
                else
                  'master_asset_id': b.masterAssetId,
                if (b.poDetailId != null) 'po_detail_id': b.poDetailId,
                'diterima': _angka(b.diterima.text),
                'hargaBeli': _angka(b.harga.text),
                'hargaPotongan': _angka(b.potongan.text),
                'diskonPersen': _diskonPersen,
                'persenPpn': _angka(b.ppn.text),
                'persenPph': 0,
                'kondisi': b.kondisi.text.trim(),
              })
          .toList(),
    });
  }
}
