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

/// Layar "Pemesanan Pembelian (PO)" -- tahap 2 modul Pengadaan POS.
///
/// Memakai TABEL PENGADAAN BERSAMA dengan JSP dan ZKoss (keputusan produk 2026-08-20),
/// dibedakan lewat kolom toko. Barang menunjuk MasterAsset, bukan produk POS.
///
/// Jadwal termin disimpan pada kolom `formula` PO yang DIPAKAI BERSAMA modul pembayaran
/// vendor; server menggabungkannya sehingga kunci milik modul lain tidak hilang saat PO
/// disunting dari kasir. Seluruh aturan (penomoran, hitung nilai, keseimbangan termin,
/// pagar ubah/hapus) berada di server `PengadaanPosApiHelper` sehingga Desktop, Android,
/// dan JSP berperilaku identik.
class PengadaanPoScreen extends StatefulWidget {
  const PengadaanPoScreen({super.key});

  @override
  State<PengadaanPoScreen> createState() => _PengadaanPoScreenState();
}

class _PengadaanPoScreenState extends State<PengadaanPoScreen> {
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
        'pengadaan_po_daftar',
        {
          if (_cari.isNotEmpty) 'cari': _cari,
          if (_status.isNotEmpty) 'status': _status,
          'page': _halaman,
          'pageSize': _pageSize,
        },
        'master:pengadaan_po:${_status}_${_cari}_$_halaman',
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat = '${res['description'] ?? 'Gagal memuat Pemesanan Pembelian.'}';
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

  Color _warnaStatus(String s) {
    switch (s) {
      case 'DISETUJUI':
        return const Color(0xFF2E7D32);
      case 'LUNAS':
        return const Color(0xFF00695C);
      case 'DITOLAK':
        return Colors.red;
      default:
        return const Color(0xFFB8860B);
    }
  }

  Future<void> _form({Map<String, dynamic>? awal, Map<String, dynamic>? dariPr}) async {
    Map<String, dynamic>? detailAwal;
    if (awal != null && awal['id'] != null) {
      try {
        final r = await ApiClient.instance
            .aksi('pengadaan_po_detail', {'id': awal['id']});
        detailAwal = Map<String, dynamic>.from(r);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat detail PO: $e')));
        return;
      }
    }
    if (!mounted) return;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _FormPoDialog(awal: awal, detailAwal: detailAwal, dariPr: dariPr),
    );
    if (hasil == null || !mounted) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_po_simpan',
        body: hasil,
        kunci: hasil['id'] != null
            ? 'pengadaan_po:${hasil['id']}'
            : 'pengadaan_po:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:pengadaan_po',
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  /// Buat PO dari PR yang sudah disetujui. Server mengembalikan SISA yang belum
  /// dipesan per baris PR, sehingga satu PR dapat dipecah menjadi beberapa PO
  /// tanpa terjadi pemesanan berlebih.
  Future<void> _dariPr() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => const _PilihPrDialog(),
    );
    if (pilihan == null || !mounted) return;
    try {
      final r = await ApiClient.instance
          .aksi('pengadaan_po_dari_pr', {'pr_id': pilihan['id']});
      if (!mounted) return;
      if (r['status'] != '00' && r['status'] != 'success') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['description'] ?? 'Gagal menyiapkan PO dari PR.'}'),
            backgroundColor: Theme.of(context).colorScheme.error));
        return;
      }
      final isian = (r['detail'] as List?) ?? const [];
      if (isian.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['catatan'] ?? 'Tidak ada sisa yang perlu dipesan '
                'dari PR ini.'}')));
        return;
      }
      await _form(dariPr: Map<String, dynamic>.from(r));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  /// Keputusan atas PO. Menolak WAJIB beralasan -- server menolak alasan < 5 karakter,
  /// jadi dialog ini meminta alasannya lebih dulu agar pengguna tidak gagal di server.
  Future<void> _putusan(Map<String, dynamic> po, String keputusan) async {
    String alasan = '';
    if (keputusan == 'TOLAK') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Alasan Penolakan'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Alasan *',
                helperText: 'Minimal 5 karakter, dibaca pembuat PO'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Tolak PO')),
          ],
        ),
      );
      alasan = c.text.trim();
      c.dispose();
      if (ok != true || !mounted) return;
    }
    try {
      final r = await ApiClient.instance.aksi('pengadaan_po_putusan', {
        'id': po['id'],
        'keputusan': keputusan,
        if (alasan.isNotEmpty) 'alasan': alasan,
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

  Future<void> _hapus(Map<String, dynamic> po) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Pemesanan Pembelian'),
        content: Text('Hapus PO ${po['kode']}? Hanya PO berstatus DRAFT dan belum '
            'menerima pembayaran yang dapat dihapus.'),
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
        aksi: 'pengadaan_po_hapus',
        body: {'id': po['id']},
        kunci: 'pengadaan_po:${po['id']}',
        cacheKey: 'master:pengadaan_po',
        rowLokal: {'id': po['id']},
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
              jenis: JenisPengadaanBulk.po)),
    );
    if (hasil == true && mounted) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanPo,
      judul: 'Pemesanan Pembelian (PO)',
      subjudul: 'Pesan barang ke penyedia, termasuk pembayaran bertermin',
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
          heroTag: 'po_dari_pr',
          onPressed: _dariPr,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('Dari PR'),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.extended(
          heroTag: 'po_baru',
          onPressed: () => _form(),
          icon: const Icon(Icons.add),
          label: const Text('Buat PO'),
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
                    labelText: 'Cari kode / keterangan / no. invoice',
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
                  DropdownMenuItem(value: 'DITOLAK', child: Text('Ditolak')),
                  DropdownMenuItem(value: 'LUNAS', child: Text('Lunas')),
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
            'Belum ada Pemesanan Pembelian.\nTekan "Dari PR" untuk memesan dari '
            'permintaan yang sudah disetujui, atau "Buat PO" untuk pesanan langsung.',
            textAlign: TextAlign.center),
      );
    }
    return AppDataTable(
      minWidth: 1100,
      emptyText: 'Tidak ada PO pada filter ini.',
      columns: const [
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Tanggal', flex: 2),
        AppTableColumn('Penyedia', flex: 3),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('Sisa', flex: 2, align: TextAlign.right),
        AppTableColumn('Status', flex: 2),
        AppTableColumn('Aksi', width: 200),
      ],
      rows: _daftar.map(_barisPo).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: 'PO',
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

  AppTableRowData _barisPo(Map<String, dynamic> po) {
    final st = '${po['status'] ?? 'DRAFT'}';
    final bertermin = po['byTermin'] == true;
    final jml = (po['jumlahTermin'] as num?)?.toInt() ?? 0;
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 2,
        child: KilauBaris(
          kunci: '${po['id'] ?? ''}',
          idBaru: _idBaru,
          idBerubah: _idBerubah,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${po['kode'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (bertermin)
                  Text('$jml termin',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF00695C))),
              ]),
        ),
      ),
      AppTableCell.text('${po['tanggal'] ?? '-'}', flex: 2),
      AppTableCell.text('${po['penyedia'] ?? '-'}', flex: 3),
      AppTableCell.text(_fmtRp.format(po['nilai'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell.text(_fmtRp.format(po['sisa'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell(
        flex: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: _warnaStatus(st).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(6)),
          child: Text(st,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _warnaStatus(st))),
        ),
      ),
      AppTableCell(width: 200, child: _aksiPo(po, st)),
    ]);
  }

  Widget _aksiPo(Map<String, dynamic> po, String st) {
    final adaBayar = ((po['dibayar'] as num?)?.toDouble() ?? 0) > 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          tooltip: 'Lihat / ubah',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => _form(awal: po)),
      if (st == 'DRAFT')
        IconButton(
            tooltip: 'Setujui',
            icon: const Icon(Icons.check_circle_outline,
                size: 18, color: Color(0xFF2E7D32)),
            onPressed: () => _putusan(po, 'SETUJUI')),
      if (st == 'DRAFT')
        IconButton(
            tooltip: 'Tolak',
            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
            onPressed: () => _putusan(po, 'TOLAK')),
      if ((st == 'DISETUJUI' || st == 'DITOLAK') && !adaBayar)
        IconButton(
            tooltip: 'Batalkan keputusan',
            icon: const Icon(Icons.undo, size: 18),
            onPressed: () => _putusan(po, 'BATAL')),
      if (po['id'] != null)
        IconButton(
            tooltip: 'Riwayat data (AuditTrails)',
            icon: const Icon(Icons.history, size: 18),
            onPressed: () => tampilkanRiwayatData(context,
                entitas: 'pengadaan_po',
                id: po['id'],
                judul: '${po['kode'] ?? ''}')),
      if (st == 'DRAFT' && !adaBayar)
        IconButton(
            tooltip: 'Hapus',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _hapus(po)),
    ]);
  }
}

/// Pemilih PR yang sudah disetujui, sebagai sumber isian PO.
class _PilihPrDialog extends StatefulWidget {
  const _PilihPrDialog();

  @override
  State<_PilihPrDialog> createState() => _PilihPrDialogState();
}

class _PilihPrDialogState extends State<_PilihPrDialog> {
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
      final r = await ApiClient.instance.aksi('pengadaan_pr_daftar', {
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
      title: const Text('Pilih Permintaan Pembelian'),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(children: [
          TextField(
            controller: _cari,
            decoration: InputDecoration(
                labelText: 'Cari kode / keterangan PR',
                suffixIcon:
                    IconButton(onPressed: _muat, icon: const Icon(Icons.search))),
            onSubmitted: (_) => _muat(),
          ),
          const SizedBox(height: 8),
          const Text(
              'Hanya PR berstatus DISETUJUI yang dapat dijadikan pesanan.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _hasil.isEmpty
                    ? const Center(
                        child: Text('Belum ada PR disetujui yang bisa dipesan.'))
                    : ListView.builder(
                        itemCount: _hasil.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          title: Text('${_hasil[i]['kode'] ?? '-'}'),
                          subtitle: Text('${_hasil[i]['keterangan'] ?? ''}'),
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

/// Satu baris barang pada form PO. Barang menunjuk MasterAsset (tabel pengadaan
/// BERSAMA dgn JSP/ZKoss), bukan produk POS.
class _BarisPo {
  int? barangId;

  /// Id MasterAsset asal, dipakai bila baris berasal dari dokumen hulu
  /// yang barangnya belum berpadanan produk POS.
  int? masterAssetId;
  String namaBarang;

  /// Id baris PR asal bila PO ini dibuat dari permintaan -- dikirim balik ke server
  /// supaya sisa yang belum dipesan terhitung benar pada PO berikutnya.
  final int? prDetailId;
  final TextEditingController jumlah;
  final TextEditingController harga;
  final TextEditingController keterangan;
  _BarisPo({
    this.barangId,
    this.masterAssetId,
    required this.namaBarang,
    this.prDetailId,
    String jumlahAwal = '1',
    String hargaAwal = '0',
    String keteranganAwal = '',
  })  : jumlah = TextEditingController(text: jumlahAwal),
        harga = TextEditingController(text: hargaAwal),
        keterangan = TextEditingController(text: keteranganAwal);
  void dispose() {
    jumlah.dispose();
    harga.dispose();
    keterangan.dispose();
  }
}

/// Satu baris termin. `key` dipertahankan apa adanya supaya server dapat
/// menggabungkannya dengan data milik modul pembayaran vendor pada kolom yang sama.
class _BarisTermin {
  final String? key;
  final double dibayar;
  final TextEditingController nama;
  final TextEditingController nilai;
  final TextEditingController tanggal;
  _BarisTermin({
    this.key,
    this.dibayar = 0,
    String namaAwal = '',
    String nilaiAwal = '0',
    String tanggalAwal = '',
  })  : nama = TextEditingController(text: namaAwal),
        nilai = TextEditingController(text: nilaiAwal),
        tanggal = TextEditingController(text: tanggalAwal);
  void dispose() {
    nama.dispose();
    nilai.dispose();
    tanggal.dispose();
  }
}

class _FormPoDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final Map<String, dynamic>? detailAwal;
  final Map<String, dynamic>? dariPr;
  const _FormPoDialog({this.awal, this.detailAwal, this.dariPr});

  @override
  State<_FormPoDialog> createState() => _FormPoDialogState();
}

class _FormPoDialogState extends State<_FormPoDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  late final TextEditingController _keterangan;
  late final TextEditingController _kodeInvoice;
  late final TextEditingController _catatan;
  late final TextEditingController _kirim;
  late final TextEditingController _dp;
  final List<_BarisPo> _baris = [];
  final List<_BarisTermin> _termin = [];
  int? _penyediaId;
  String _penyediaNama = '';
  bool _bertermin = false;

  bool get _baru => widget.awal == null;
  String get _status => '${widget.detailAwal?['header']?['status'] ?? 'DRAFT'}';
  double get _sudahDibayar =>
      ((widget.detailAwal?['header']?['dibayar'] as num?)?.toDouble() ?? 0);

  /// PO terkunci bila sudah diputus ATAU sudah menerima pembayaran -- sama dengan
  /// pagar di server, supaya pengguna tidak menyunting lalu ditolak saat menyimpan.
  bool get _terkunci => _status != 'DRAFT' || _sudahDibayar > 0;

  @override
  void initState() {
    super.initState();
    final h = widget.detailAwal?['header'] as Map?;
    _keterangan = TextEditingController(
        text: '${h?['keterangan'] ?? widget.dariPr?['keterangan'] ?? ''}');
    _kodeInvoice = TextEditingController(text: '${h?['kodeInvoice'] ?? ''}');
    _catatan = TextEditingController(text: '${h?['catatanKesepakatan'] ?? ''}');
    _kirim = TextEditingController(text: '${h?['pengirimanPalingLambat'] ?? ''}');
    _dp = TextEditingController(text: '${(h?['dp'] as num?)?.toDouble() ?? 0}');
    _penyediaId = (h?['penyedia_id'] as num?)?.toInt();
    _penyediaNama = '${h?['penyedia'] ?? ''}';
    _bertermin = h?['byTermin'] == true;

    for (final d in ((widget.detailAwal?['detail'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(d as Map);
      _baris.add(_BarisPo(
        barangId: (m['produk_id'] as num?)?.toInt(),
        masterAssetId: (m['master_asset_id'] as num?)?.toInt(),
        namaBarang: '${m['barang'] ?? '-'}',
        prDetailId: (m['pr_detail_id'] as num?)?.toInt(),
        jumlahAwal: '${m['jumlah'] ?? 1}',
        hargaAwal: '${m['hargaBeli'] ?? 0}',
        keteranganAwal: '${m['keterangan'] ?? ''}',
      ));
    }
    for (final t in ((widget.detailAwal?['termin'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(t as Map);
      _termin.add(_BarisTermin(
        key: '${m['key'] ?? ''}'.isEmpty ? null : '${m['key']}',
        dibayar: (m['dibayar'] as num?)?.toDouble() ?? 0,
        namaAwal: '${m['nama'] ?? ''}',
        nilaiAwal: '${m['penagihan'] ?? 0}',
        tanggalAwal: '${m['tanggalD'] ?? ''}',
      ));
    }
    // Isian dari PR: baris dibawa lengkap dengan jejak baris PR asalnya.
    for (final d in ((widget.dariPr?['detail'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(d as Map);
      _baris.add(_BarisPo(
        barangId: (m['produk_id'] as num?)?.toInt(),
        masterAssetId: (m['master_asset_id'] as num?)?.toInt(),
        namaBarang: '${m['barang'] ?? '-'}',
        prDetailId: (m['pr_detail_id'] as num?)?.toInt(),
        jumlahAwal: '${m['jumlah'] ?? 1}',
        hargaAwal: '${m['hargaBeli'] ?? 0}',
        keteranganAwal: '${m['keterangan'] ?? ''}',
      ));
    }
  }

  @override
  void dispose() {
    _keterangan.dispose();
    _kodeInvoice.dispose();
    _catatan.dispose();
    _kirim.dispose();
    _dp.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    for (final t in _termin) {
      t.dispose();
    }
    super.dispose();
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _total => _baris.fold(
      0, (s, b) => s + _angka(b.jumlah.text) * _angka(b.harga.text));

  double get _totalTermin =>
      _termin.fold(0, (s, t) => s + _angka(t.nilai.text));

  /// Selisih jadwal termin terhadap nilai PO. Server menolak selisih > Rp 1,
  /// jadi angka ini ditampilkan langsung agar pengguna memperbaikinya di sini.
  double get _selisihTermin => _totalTermin - _total;

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
                    subtitle: Text(
                        '${hasil[i]['kode'] ?? ''}  ·  ${hasil[i]['alamat'] ?? ''}'),
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
                        '${hasil[i]['kode'] ?? ''}  ·  ${hasil[i]['merk'] ?? ''} ${hasil[i]['satuan'] ?? ''}'),
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
    setState(() => _baris.add(_BarisPo(
          barangId: (dipilih['id'] as num?)?.toInt(),
          namaBarang: '${dipilih['nama'] ?? '-'}',
        )));
  }

  Future<void> _pilihTanggal(TextEditingController c) async {
    DateTime awal = DateTime.now();
    final bagian = c.text.split('-');
    if (bagian.length == 3) {
      final d = int.tryParse(bagian[0]), m = int.tryParse(bagian[1]), y = int.tryParse(bagian[2]);
      if (d != null && m != null && y != null) awal = DateTime(y, m, d);
    }
    final pilih = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pilih == null) return;
    // Format dd-MM-yyyy adalah format yang dibaca ZKoss pada dokumen yang sama.
    setState(() => c.text = DateFormat('dd-MM-yyyy').format(pilih));
  }

  /// Bagi sisa nilai PO rata ke seluruh termin. Pembulatan sen dibebankan ke
  /// termin terakhir supaya jumlahnya tepat sama dengan nilai PO.
  void _bagiRata() {
    if (_termin.isEmpty) return;
    final n = _termin.length;
    final per = (_total / n).floorToDouble();
    for (var i = 0; i < n; i++) {
      final nilai = i == n - 1 ? _total - per * (n - 1) : per;
      _termin[i].nilai.text = nilai.toStringAsFixed(0);
      if (_termin[i].nama.text.trim().isEmpty) {
        _termin[i].nama.text = 'Termin ${i + 1}';
      }
    }
    setState(() {});
  }

  Widget _panelTermin() {
    final selisih = _selisihTermin;
    final pas = selisih.abs() <= 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _bertermin,
            onChanged: _terkunci
                ? null
                : (v) => setState(() {
                      _bertermin = v;
                      if (v && _termin.isEmpty) {
                        _termin.add(_BarisTermin(namaAwal: 'Termin 1'));
                        _bagiRata();
                      }
                    }),
            title: const Text('Pembayaran bertermin',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Bayar bertahap sesuai jadwal, bukan sekali lunas',
                style: TextStyle(fontSize: 11)),
          ),
        ),
      ]),
      if (_bertermin) ...[
        Row(children: [
          const Expanded(
              child: Text('Jadwal Termin',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          if (!_terkunci)
            TextButton.icon(
                onPressed: _bagiRata,
                icon: const Icon(Icons.horizontal_distribute, size: 18),
                label: const Text('Bagi Rata')),
          if (!_terkunci)
            TextButton.icon(
                onPressed: () => setState(() => _termin.add(_BarisTermin(
                    namaAwal: 'Termin ${_termin.length + 1}'))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah Termin')),
        ]),
        for (final t in _termin)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                  width: 150,
                  child: TextField(
                      controller: t.nama,
                      enabled: !_terkunci,
                      decoration: const InputDecoration(
                          labelText: 'Nama termin', isDense: true))),
              const SizedBox(width: 6),
              SizedBox(
                  width: 130,
                  child: TextField(
                      controller: t.nilai,
                      enabled: !_terkunci,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Nilai tagih', isDense: true))),
              const SizedBox(width: 6),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: t.tanggal,
                  enabled: !_terkunci,
                  readOnly: true,
                  onTap: _terkunci ? null : () => _pilihTanggal(t.tanggal),
                  decoration: const InputDecoration(
                      labelText: 'Jatuh tempo',
                      isDense: true,
                      suffixIcon: Icon(Icons.event, size: 16)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: t.dibayar > 0
                    ? Text('Terbayar ${_fmtRp.format(t.dibayar)}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF00695C)))
                    : const SizedBox.shrink(),
              ),
              if (!_terkunci && t.dibayar <= 0)
                IconButton(
                    onPressed: () {
                      setState(() => _termin.remove(t));
                      t.dispose();
                    },
                    icon: const Icon(Icons.close, size: 18)),
            ]),
          ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: (pas ? const Color(0xFF2E7D32) : Colors.orange)
                  .withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8)),
          child: Text(
              pas
                  ? 'Jadwal termin sudah menutup seluruh nilai PO '
                      '(${_fmtRp.format(_totalTermin)}).'
                  : selisih > 0
                      ? 'Jadwal termin KELEBIHAN ${_fmtRp.format(selisih)} dari nilai PO. '
                          'Kurangi salah satu termin.'
                      : 'Jadwal termin KURANG ${_fmtRp.format(-selisih)} dari nilai PO. '
                          'Tambah termin atau naikkan nilainya.',
              style: const TextStyle(fontSize: 12)),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
              'PO bertermin tidak memakai uang muka terpisah -- tuliskan uang muka '
              'sebagai termin pertama.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_baru
          ? (widget.dariPr != null
              ? 'Buat PO dari ${widget.dariPr?['pr_kode'] ?? 'PR'}'
              : 'Buat Pemesanan Pembelian')
          : 'PO ${widget.awal?['kode'] ?? ''}  ·  $_status'),
      content: SizedBox(
        width: 760,
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
                  child: Text(
                      _sudahDibayar > 0
                          ? 'PO ini sudah menerima pembayaran '
                              '${_fmtRp.format(_sudahDibayar)} sehingga tidak dapat diubah.'
                          : 'PO berstatus $_status tidak dapat diubah. Batalkan '
                              'keputusannya terlebih dahulu bila memang perlu dikoreksi.',
                      style: const TextStyle(fontSize: 12)),
                ),
              InkWell(
                onTap: _terkunci ? null : _pilihPenyedia,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Penyedia / Vendor *',
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
                    controller: _kodeInvoice,
                    enabled: !_terkunci,
                    decoration: const InputDecoration(
                        labelText: 'No. invoice / referensi vendor',
                        isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: _kirim,
                    enabled: !_terkunci,
                    readOnly: true,
                    onTap: _terkunci ? null : () => _pilihTanggal(_kirim),
                    decoration: const InputDecoration(
                        labelText: 'Kirim paling lambat',
                        isDense: true,
                        suffixIcon: Icon(Icons.event, size: 16)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _keterangan,
                enabled: !_terkunci,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Keterangan pesanan',
                    hintText: 'Mis. pesanan rutin minuman bulan September'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _catatan,
                enabled: !_terkunci,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Catatan kesepakatan dengan vendor',
                    hintText: 'Mis. ongkos kirim ditanggung penyedia'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: Row(children: [
                  const Expanded(
                      child: Text('Barang yang Dipesan',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  if (!_terkunci)
                    TextButton.icon(
                        onPressed: _tambahBaris,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tambah Barang')),
                ]),
              ),
              if (_baris.isEmpty)
                const Text('Belum ada barang. Tambahkan minimal satu baris.',
                    style: TextStyle(fontSize: 12)),
              for (final b in _baris)
                Padding(
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
                              if (b.prDetailId != null)
                                const Text('dari PR',
                                    style: TextStyle(
                                        fontSize: 10, color: Color(0xFF00695C))),
                            ])),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 80,
                        child: TextField(
                            controller: b.jumlah,
                            enabled: !_terkunci,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Jumlah', isDense: true))),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 120,
                        child: TextField(
                            controller: b.harga,
                            enabled: !_terkunci,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Harga Beli', isDense: true))),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 110,
                        child: Text(
                            _fmtRp.format(
                                _angka(b.jumlah.text) * _angka(b.harga.text)),
                            textAlign: TextAlign.right,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                    if (!_terkunci)
                      IconButton(
                          onPressed: () {
                            setState(() => _baris.remove(b));
                            b.dispose();
                          },
                          icon: const Icon(Icons.close, size: 18)),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  const Expanded(
                      child: Text('Total Nilai PO',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(_fmtRp.format(_total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ),
              if (!_bertermin)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _dp,
                      enabled: !_terkunci,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Uang muka (DP)', isDense: true),
                    ),
                  ),
                ),
              const Divider(height: 24),
              _panelTermin(),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Nilai dihitung ulang oleh server dari baris di atas, sehingga total '
                    'dokumen selalu sama dengan rinciannya.',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        if (!_terkunci) FilledButton(onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }

  /// Validasi di layar HANYA untuk memberi umpan balik cepat; server tetap
  /// menegakkan aturan yang sama sehingga kanal lain berperilaku identik.
  void _simpan() {
    if (_penyediaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pilih penyedia/vendor terlebih dahulu.')));
      return;
    }
    if (_baris.where((b) => b.barangId != null || b.masterAssetId != null).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tambahkan minimal satu baris barang.')));
      return;
    }
    if (_bertermin) {
      if (_termin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tambahkan minimal satu baris termin.')));
        return;
      }
      if (_termin.any((t) => _angka(t.nilai.text) <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Setiap termin harus bernilai lebih dari nol.')));
        return;
      }
      if (_selisihTermin.abs() > 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Jadwal termin belum menutup nilai PO '
                '(selisih ${_fmtRp.format(_selisihTermin.abs())}). '
                'Tekan "Bagi Rata" atau sesuaikan nilainya.')));
        return;
      }
    }
    Navigator.pop(context, <String, dynamic>{
      if (!_baru) 'id': widget.awal!['id'],
      'penyedia_id': _penyediaId,
      'keterangan': _keterangan.text.trim(),
      'kodeInvoice': _kodeInvoice.text.trim(),
      'catatanKesepakatan': _catatan.text.trim(),
      'pengirimanPalingLambat': _kirim.text.trim(),
      // DP dan termin saling meniadakan -- server menolak DP > 0 pada PO bertermin.
      'dp': _bertermin ? 0 : _angka(_dp.text),
      'byTermin': _bertermin,
      'detail': _baris
          .where((b) => b.barangId != null || b.masterAssetId != null)
          .map((b) => {
                if (b.barangId != null)
                  'produk_id': b.barangId
                else
                  'master_asset_id': b.masterAssetId,
                if (b.prDetailId != null) 'pr_detail_id': b.prDetailId,
                'jumlah': _angka(b.jumlah.text),
                'hargaBeli': _angka(b.harga.text),
                'keterangan': b.keterangan.text.trim(),
              })
          .toList(),
      if (_bertermin)
        'termin': _termin
            .map((t) => {
                  if (t.key != null) 'key': t.key,
                  'nama': t.nama.text.trim(),
                  'penagihan': _angka(t.nilai.text),
                  'tanggalD': t.tanggal.text.trim(),
                })
            .toList(),
    });
  }
}
