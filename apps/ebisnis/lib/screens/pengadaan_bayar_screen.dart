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

/// Layar "Pembayaran Vendor" -- tahap 5 modul Pengadaan POS.
///
/// Memakai tabel pembayaran termin yang sama dengan JSP/ZKoss, dibedakan kolom toko.
/// Yang membuat pembayaran DIAKUI adalah PERSETUJUAN: perhitungan kanonik pada
/// PemesananPengadaanMasterAsset.hitungDibayar hanya menjumlahkan dokumen yang sudah
/// disetujui. Karena itu dokumen draf sengaja belum mengubah status PO.
class PengadaanBayarScreen extends StatefulWidget {
  const PengadaanBayarScreen({super.key});

  @override
  State<PengadaanBayarScreen> createState() => _PengadaanBayarScreenState();
}

class _PengadaanBayarScreenState extends State<PengadaanBayarScreen> {
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
        'pengadaan_bayar_daftar',
        {
          if (_cari.isNotEmpty) 'cari': _cari,
          if (_status.isNotEmpty) 'status': _status,
          'page': _halaman,
          'pageSize': _pageSize,
        },
        'master:pengadaan_bayar:${_status}_${_cari}_$_halaman',
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat = '${res['description'] ?? 'Gagal memuat pembayaran vendor.'}';
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

  /// Saat menyetujui, penyetuju memilih apakah pembayaran ini masuk antrean
  /// transfer bank. Pembayaran tunai tidak perlu masuk antrean pencairan, jadi
  /// pilihannya ditanyakan alih-alih diasumsikan.
  Future<void> _putusan(Map<String, dynamic> row, String keputusan) async {
    bool ajukanTransfer = false;
    if (keputusan == 'SETUJUI') {
      final pilih = await showDialog<bool>(
        context: context,
        builder: (d) => StatefulBuilder(builder: (c, setLocal) {
          return AlertDialog(
            title: Text('Setujui ${row['kode'] ?? ''}'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Nilai ${_fmtRp.format(row['nilai'] ?? 0)} kepada '
                  '${row['penyedia'] ?? '-'}.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: ajukanTransfer,
                onChanged: (v) =>
                    setLocal(() => ajukanTransfer = v ?? false),
                title: const Text('Ajukan transfer bank',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Masukkan ke antrean pencairan keuangan. Kosongkan bila '
                    'dibayar tunai.',
                    style: TextStyle(fontSize: 11)),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('Setujui')),
            ],
          );
        }),
      );
      if (pilih != true || !mounted) return;
    }
    try {
      final r = await ApiClient.instance.aksi('pengadaan_bayar_putusan', {
        'id': row['id'],
        'keputusan': keputusan,
        if (keputusan == 'SETUJUI' && ajukanTransfer) 'ajukanTransfer': true,
      });
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      final trfDibuat = (r['transferDibuat'] as num?)?.toInt() ?? 0;
      final trfDitarik = (r['transferDitarik'] as num?)?.toInt() ?? 0;
      final catatanTrf = trfDibuat > 0
          ? ' · $trfDibuat pengajuan transfer dibuat'
          : (trfDitarik > 0 ? ' · $trfDitarik pengajuan transfer ditarik' : '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sukses
              ? 'Keputusan tersimpan: ${r['statusDokumen'] ?? keputusan}$catatanTrf'
              : '${r['description'] ?? 'Gagal menyimpan keputusan.'}'),
          backgroundColor: sukses ? null : Theme.of(context).colorScheme.error));
      if (sukses) await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _hapus(Map<String, dynamic> row) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Pembayaran'),
        content: Text('Hapus dokumen ${row['kode']}? Hanya dokumen berstatus '
            'DRAFT yang dapat dihapus.'),
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
        aksi: 'pengadaan_bayar_hapus',
        body: {'id': row['id']},
        kunci: 'pengadaan_bayar:${row['id']}',
        cacheKey: 'master:pengadaan_bayar',
        rowLokal: {'id': row['id']},
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

  /// Buat pembayaran: pilih vendor, lalu server mengembalikan tagihan terbukanya
  /// (dirinci per termin) untuk dijadikan isian dokumen.
  Future<void> _bayarBaru({Map<String, dynamic>? awal}) async {
    Map<String, dynamic>? detailAwal;
    int? penyediaId = (awal?['penyedia_id'] as num?)?.toInt();
    String penyediaNama = '${awal?['penyedia'] ?? ''}';

    if (awal != null && awal['id'] != null) {
      try {
        final r = await ApiClient.instance
            .aksi('pengadaan_bayar_detail', {'id': awal['id']});
        detailAwal = Map<String, dynamic>.from(r);
        penyediaId = (detailAwal['header']?['penyedia_id'] as num?)?.toInt();
        penyediaNama = '${detailAwal['header']?['penyedia'] ?? ''}';
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat detail pembayaran: $e')));
        return;
      }
    } else {
      final dipilih = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => const _PilihVendorDialog(),
      );
      if (dipilih == null || !mounted) return;
      penyediaId = (dipilih['id'] as num?)?.toInt();
      penyediaNama = '${dipilih['nama'] ?? ''}';
    }

    List<Map<String, dynamic>> tagihan = [];
    try {
      final r = await ApiClient.instance.aksi('pengadaan_bayar_tagihan_terbuka', {
        'penyedia_id': penyediaId,
        if (awal?['id'] != null) 'kecuali_bayar_id': awal!['id'],
      });
      if (!mounted) return;
      if (r['status'] != '00' && r['status'] != 'success') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['description'] ?? 'Gagal memuat tagihan.'}'),
            backgroundColor: Theme.of(context).colorScheme.error));
        return;
      }
      tagihan = ((r['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (tagihan.isEmpty && detailAwal == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['catatan'] ?? 'Tidak ada tagihan terbuka untuk '
                'penyedia ini.'}')));
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      return;
    }

    if (!mounted) return;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormBayarDialog(
        awal: awal,
        detailAwal: detailAwal,
        tagihan: tagihan,
        penyediaId: penyediaId,
        penyediaNama: penyediaNama,
      ),
    );
    if (hasil == null || !mounted) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_bayar_simpan',
        body: hasil,
        kunci: hasil['id'] != null
            ? 'pengadaan_bayar:${hasil['id']}'
            : 'pengadaan_bayar:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:pengadaan_bayar',
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanDpc,
      judul: 'Pembayaran Vendor',
      subjudul: 'Bayar tagihan penyedia atas pesanan yang sudah disetujui',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bayarBaru(),
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Bayar Vendor'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                    labelText: 'Cari kode / keterangan',
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
            'Belum ada pembayaran vendor.\nTekan "Bayar Vendor" untuk melunasi '
            'tagihan pesanan yang sudah disetujui.',
            textAlign: TextAlign.center),
      );
    }
    return AppDataTable(
      minWidth: 980,
      emptyText: 'Tidak ada pembayaran pada filter ini.',
      columns: const [
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Tanggal', flex: 2),
        AppTableColumn('Penyedia', flex: 3),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('Status', flex: 2),
        AppTableColumn('Aksi', width: 180),
      ],
      rows: _daftar.map(_baris).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: 'pembayaran',
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

  AppTableRowData _baris(Map<String, dynamic> row) {
    final st = '${row['status'] ?? 'DRAFT'}';
    final disetujui = st == 'DISETUJUI';
    final warna =
        disetujui ? const Color(0xFF2E7D32) : const Color(0xFFB8860B);
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 2,
        child: KilauBaris(
          kunci: '${row['id'] ?? ''}',
          idBaru: _idBaru,
          idBerubah: _idBerubah,
          child: Text('${row['kode'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      AppTableCell.text('${row['tanggal'] ?? '-'}', flex: 2),
      AppTableCell.text('${row['penyedia'] ?? '-'}', flex: 3),
      AppTableCell.text(_fmtRp.format(row['nilai'] ?? 0),
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
      AppTableCell(
        width: 180,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Lihat / ubah',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _bayarBaru(awal: row)),
          if (!disetujui)
            IconButton(
                tooltip: 'Setujui pembayaran',
                icon: const Icon(Icons.check_circle_outline,
                    size: 18, color: Color(0xFF2E7D32)),
                onPressed: () => _putusan(row, 'SETUJUI')),
          if (disetujui)
            IconButton(
                tooltip: 'Batalkan persetujuan',
                icon: const Icon(Icons.undo, size: 18),
                onPressed: () => _putusan(row, 'BATAL')),
          if (row['id'] != null)
            IconButton(
                tooltip: 'Riwayat data (AuditTrails)',
                icon: const Icon(Icons.history, size: 18),
                onPressed: () => tampilkanRiwayatData(context,
                    entitas: 'pengadaan_bayar',
                    id: row['id'],
                    judul: '${row['kode'] ?? ''}')),
          if (!disetujui)
            IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _hapus(row)),
        ]),
      ),
    ]);
  }
}

/// Pemilih vendor untuk memulai dokumen pembayaran.
class _PilihVendorDialog extends StatefulWidget {
  const _PilihVendorDialog();

  @override
  State<_PilihVendorDialog> createState() => _PilihVendorDialogState();
}

class _PilihVendorDialogState extends State<_PilihVendorDialog> {
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
      final r = await ApiClient.instance.aksi('pengadaan_penyedia_cari',
          {'keyword': _cari.text.trim(), 'limit': 50});
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
      title: const Text('Pilih Penyedia / Vendor'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _cari,
            autofocus: true,
            decoration: InputDecoration(
                labelText: 'Cari kode / nama penyedia',
                suffixIcon:
                    IconButton(onPressed: _muat, icon: const Icon(Icons.search))),
            onSubmitted: (_) => _muat(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _hasil.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text('${_hasil[i]['nama'] ?? '-'}'),
                      subtitle: Text('${_hasil[i]['kode'] ?? ''}'),
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

/// Satu baris tagihan yang dibayar.
class _BarisBayar {
  final int poId;
  final String poKode;
  final String terminKey;
  final String terminNama;
  final String jatuhTempo;
  final double nilaiTagih;
  final double sudahDibayar;
  final double sisa;
  final TextEditingController dibayar;
  bool pilih;
  _BarisBayar({
    required this.poId,
    required this.poKode,
    required this.terminKey,
    required this.terminNama,
    required this.jatuhTempo,
    required this.nilaiTagih,
    required this.sudahDibayar,
    required this.sisa,
    required String dibayarAwal,
    this.pilih = false,
  }) : dibayar = TextEditingController(text: dibayarAwal);
  void dispose() => dibayar.dispose();
}

class _FormBayarDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final Map<String, dynamic>? detailAwal;
  final List<Map<String, dynamic>> tagihan;
  final int? penyediaId;
  final String penyediaNama;
  const _FormBayarDialog({
    this.awal,
    this.detailAwal,
    required this.tagihan,
    required this.penyediaId,
    required this.penyediaNama,
  });

  @override
  State<_FormBayarDialog> createState() => _FormBayarDialogState();
}

class _FormBayarDialogState extends State<_FormBayarDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  late final TextEditingController _keterangan;
  final List<_BarisBayar> _baris = [];

  bool get _baru => widget.awal == null;
  String get _status => '${widget.detailAwal?['header']?['status'] ?? 'DRAFT'}';
  bool get _terkunci => _status != 'DRAFT';

  @override
  void initState() {
    super.initState();
    _keterangan = TextEditingController(
        text: '${widget.detailAwal?['header']?['keterangan'] ?? ''}');

    // Baris yang sudah ada pada dokumen ini ditandai terpilih; sisanya dari
    // daftar tagihan terbuka ditawarkan dengan nilai bayar 0.
    final sudahAda = <String>{};
    for (final d in ((widget.detailAwal?['detail'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(d as Map);
      final poId = (m['po_id'] as num?)?.toInt() ?? 0;
      final key = '${m['termin_key'] ?? ''}';
      sudahAda.add('$poId|$key');
      final nilai = (m['nilaiTagih'] as num?)?.toDouble() ?? 0;
      final lain = (m['sudahDibayar'] as num?)?.toDouble() ?? 0;
      _baris.add(_BarisBayar(
        poId: poId,
        poKode: '${m['po'] ?? ''}',
        terminKey: key,
        terminNama: '${m['termin'] ?? ''}',
        jatuhTempo: '',
        nilaiTagih: nilai,
        sudahDibayar: lain,
        sisa: (m['sisa'] as num?)?.toDouble() ?? (nilai - lain),
        dibayarAwal: '${(m['dibayar'] as num?)?.toDouble() ?? 0}',
        pilih: true,
      ));
    }
    for (final t in widget.tagihan) {
      final poId = (t['po_id'] as num?)?.toInt() ?? 0;
      final key = '${t['termin_key'] ?? ''}';
      if (sudahAda.contains('$poId|$key')) continue;
      _baris.add(_BarisBayar(
        poId: poId,
        poKode: '${t['po'] ?? ''}',
        terminKey: key,
        terminNama: '${t['termin'] ?? ''}',
        jatuhTempo: '${t['jatuhTempo'] ?? ''}',
        nilaiTagih: (t['nilaiTagih'] as num?)?.toDouble() ?? 0,
        sudahDibayar: (t['sudahDibayar'] as num?)?.toDouble() ?? 0,
        sisa: (t['sisa'] as num?)?.toDouble() ?? 0,
        dibayarAwal: '0',
      ));
    }
  }

  @override
  void dispose() {
    _keterangan.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _total => _baris
      .where((b) => b.pilih)
      .fold(0, (s, b) => s + _angka(b.dibayar.text));

  void _simpan() {
    final dipilih = _baris.where((b) => b.pilih).toList();
    if (dipilih.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Centang minimal satu tagihan untuk dibayar.')));
      return;
    }
    for (final b in dipilih) {
      final n = _angka(b.dibayar.text);
      if (n <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Nilai bayar ${b.poKode} harus lebih besar dari nol.')));
        return;
      }
      if (n > b.sisa + 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Nilai bayar ${b.poKode} melebihi sisa tagihannya '
                '(${_fmtRp.format(b.sisa)}).')));
        return;
      }
    }
    Navigator.pop(context, <String, dynamic>{
      if (!_baru) 'id': widget.awal!['id'],
      'penyedia_id': widget.penyediaId,
      'keterangan': _keterangan.text.trim(),
      'detail': dipilih
          .map((b) => {
                'po_id': b.poId,
                'termin_key': b.terminKey,
                'dibayar': _angka(b.dibayar.text),
              })
          .toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_baru
          ? 'Bayar ${widget.penyediaNama}'
          : 'Pembayaran ${widget.awal?['kode'] ?? ''}  ·  $_status'),
      content: SizedBox(
        width: 820,
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
                      'Pembayaran yang sudah disetujui tidak dapat diubah. '
                      'Batalkan persetujuannya terlebih dahulu bila perlu dikoreksi.',
                      style: TextStyle(fontSize: 12)),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFF00695C).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                    'Dokumen ini baru mengubah status pesanan setelah DISETUJUI; '
                    'draf belum diakui sebagai pembayaran.',
                    style: TextStyle(fontSize: 12)),
              ),
              TextField(
                controller: _keterangan,
                enabled: !_terkunci,
                decoration: const InputDecoration(
                    labelText: 'Keterangan pembayaran',
                    hintText: 'Mis. transfer BCA 20 Agustus'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 4),
                child: Text('Tagihan yang Dibayar',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (_baris.isEmpty)
                const Text('Tidak ada tagihan terbuka untuk penyedia ini.',
                    style: TextStyle(fontSize: 12)),
              for (final b in _baris) _barisTagihan(b),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const Expanded(
                      child: Text('Total Dibayar',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(_fmtRp.format(_total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
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

  Widget _barisTagihan(_BarisBayar b) {
    final keterangan = 'tagih ${_fmtRp.format(b.nilaiTagih)}'
        '${b.sudahDibayar > 0 ? ' · terbayar ${_fmtRp.format(b.sudahDibayar)}' : ''}'
        '${b.jatuhTempo.isEmpty ? '' : ' · jatuh tempo ${b.jatuhTempo}'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: Checkbox(
            value: b.pilih,
            onChanged: _terkunci
                ? null
                : (v) => setState(() {
                      b.pilih = v ?? false;
                      if (b.pilih && _angka(b.dibayar.text) <= 0) {
                        b.dibayar.text = b.sisa.toStringAsFixed(0);
                      }
                    }),
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${b.poKode} · ${b.terminNama}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(keterangan, style: const TextStyle(fontSize: 10)),
              ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
            width: 120,
            child: Text(_fmtRp.format(b.sisa),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF00695C)))),
        const SizedBox(width: 8),
        SizedBox(
            width: 130,
            child: TextField(
                controller: b.dibayar,
                enabled: !_terkunci && b.pilih,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Dibayar', isDense: true))),
      ]),
    );
  }
}
