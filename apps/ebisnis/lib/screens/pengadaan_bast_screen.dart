import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'pengadaan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';
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

class _PengadaanBastScreenState extends State<PengadaanBastScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabUtama;
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
    _tabUtama = TabController(length: 2, vsync: this);
    _muat();
  }

  @override
  void dispose() {
    _tabUtama.dispose();
    super.dispose();
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

  /// Buka dialog Back Order untuk sebuah PO, lalu segarkan daftar bila berhasil.
  Future<void> _backOrder(int poId, String poKode) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BackOrderDialog(poId: poId, poKode: poKode),
    );
    if (hasil == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${hasil['description'] ?? 'Back order diproses.'}')));
    await _muat();
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
    if (hasil['_backOrder'] == true) {
      await _backOrder((hasil['po_id'] as num).toInt(), '${hasil['po'] ?? ''}');
      return;
    }
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
      // Local-first: keputusan ditulis ke antrean perangkat DULU, baru dikirim.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_bast_putusan',
        body: {'id': bast['id'], 'keputusan': keputusan},
        kunci: 'pengadaan_bast_putusan:${bast['id']}',
        cacheKey: 'master:pengadaan_bast',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['offline'] == true
              ? 'Keputusan tersimpan di perangkat, akan dikirim otomatis.'
              : 'Keputusan tersimpan: ${r['statusDokumen'] ?? keputusan}')));
      await _muat();
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
      // Local-first juga untuk sinkronisasi stok: perintahnya diantre dulu,
      // sehingga penerimaan di gudang tanpa sinyal tetap tercatat urut.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_bast_sinkron_kulakan',
        body: {'id': bast['id']},
        kunci: 'pengadaan_bast_sinkron:${bast['id']}',
        cacheKey: 'master:pengadaan_bast',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['offline'] == true
              ? 'Perintah sinkron tersimpan di perangkat, akan dikirim otomatis.'
              : 'Stok bertambah lewat faktur ${r['nomorFaktur'] ?? ''} '
                  '(${r['jumlahBaris'] ?? 0} baris).')));
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }


  /// Dua tab pada setiap menu Pengadaan: "Dasbor" (ringkasan angka) dan
  /// "Penerimaan" (daftar + CRUD). Susunannya sengaja disamakan di keenam
  /// menu supaya berpindah tahap tidak menuntut penyesuaian kebiasaan.
  Widget _bungkusTab(Widget isiData) {
    return Column(children: [
      TabBar(
        controller: _tabUtama,
        tabs: const [
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
          Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Penerimaan'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabUtama,
          children: [
            const PengadaanDasborTab(tahap: 'bast'),
            isiData,
          ],
        ),
      ),
    ]);
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
      body: _bungkusTab(Column(children: [
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
      ])),
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
        AppTableColumn('Aksi', width: 230),
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
      // Cetak dokumen: pratinjau lebih dulu, mencetak menyusul. Templatnya sama
      // dengan versi ZKoss sehingga hasil cetaknya identik.
      IconButton(
          tooltip: 'Cetak / pratinjau',
          icon: const Icon(Icons.print_outlined, size: 18),
          onPressed: () => cetakDokumenPengadaan(context,
              tahap: 'bast',
              id: (bast['id'] as num).toInt(),
              kode: '${bast['kode'] ?? ''}')),
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
  final TextEditingController pph;
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
    String pphAwal = '0',
    String kondisiAwal = '',
  })  : diterima = TextEditingController(text: diterimaAwal),
        harga = TextEditingController(text: hargaAwal),
        potongan = TextEditingController(text: potonganAwal),
        ppn = TextEditingController(text: ppnAwal),
        pph = TextEditingController(text: pphAwal),
        kondisi = TextEditingController(text: kondisiAwal);
  void dispose() {
    diterima.dispose();
    harga.dispose();
    potongan.dispose();
    ppn.dispose();
    pph.dispose();
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

    final barisTersimpan =
        (widget.detailAwal?['detail'] as List?) ?? const [];
    if (barisTersimpan.isNotEmpty) {
      // Bentuk potongan (rupiah atau persen) disimpan per baris, tetapi ditampilkan
      // sebagai satu sakelar untuk seluruh dokumen -- ikuti baris pertama.
      _diskonPersen = (Map<String, dynamic>.from(barisTersimpan.first as Map)['diskonPersen'] ??
              false) ==
          true;
    }
    for (final d in barisTersimpan) {
      final m = Map<String, dynamic>.from(d as Map);
      _baris.add(_BarisBast(
        barangId: (m['produk_id'] as num?)?.toInt(),
        masterAssetId: (m['master_asset_id'] as num?)?.toInt(),
        namaBarang: '${m['barang'] ?? '-'}',
        poDetailId: (m['po_detail_id'] as num?)?.toInt(),
        sisaBoleh: (m['sisaBolehDiterima'] as num?)?.toDouble(),
        diterimaAwal: '${m['diterima'] ?? 0}',
        hargaAwal: '${m['hargaBeli'] ?? 0}',
        potonganAwal: '${m['hargaPotongan'] ?? 0}',
        ppnAwal: '${m['persenPpn'] ?? 0}',
        pphAwal: '${m['persenPph'] ?? 0}',
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
            width: 70,
            child: TextField(
                controller: b.pph,
                enabled: !_terkunci,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'PPh %', isDense: true))),
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
        // Barang datang kurang? Simpan dahulu apa yang benar-benar diterima,
        // lalu putuskan sisanya lewat Back Order -- urutan yang dipakai di lapangan.
        if (!_baru && _poId != null)
          OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, <String, dynamic>{
                    '_backOrder': true,
                    'po_id': _poId,
                    'po': _poKode,
                  }),
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('Back Order / Pesan Kembali')),
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
                'persenPph': _angka(b.pph.text),
                'kondisi': b.kondisi.text.trim(),
              })
          .toList(),
    });
  }
}

/// Satu baris kekurangan kiriman pada dialog Back Order.
class _BarisKurang {
  final Map<String, dynamic> data;
  final TextEditingController jumlah;
  bool dipilih = true;
  _BarisKurang(this.data)
      : jumlah = TextEditingController(text: '${data['kurang'] ?? 0}');
  void dispose() => jumlah.dispose();
  double get kurang => ((data['kurang'] ?? 0) as num).toDouble();
  double get harga => ((data['hargaBeli'] ?? 0) as num).toDouble();
}

/// Dialog "Back Order / Pesan Kembali".
///
/// Dipakai ketika barang yang datang tidak memenuhi pesanan. Mengikuti praktik
/// pengadaan di lapangan, keputusannya selalu dua langkah sekaligus: sisa pesanan
/// lama DITUTUP, lalu -- bila barangnya masih dibutuhkan -- diterbitkan pesanan
/// susulan atas kekurangan itu. Menutup sisa lama bukan formalitas: tanpa itu
/// jumlah yang sama terhitung dua kali dan permintaan asalnya tampak dipesan
/// melebihi yang diminta.
class _BackOrderDialog extends StatefulWidget {
  final int poId;
  final String poKode;
  const _BackOrderDialog({required this.poId, required this.poKode});

  @override
  State<_BackOrderDialog> createState() => _BackOrderDialogState();
}

class _BackOrderDialogState extends State<_BackOrderDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  final List<_BarisKurang> _baris = [];
  final _alasan = TextEditingController();
  final _batasKirim = TextEditingController();
  bool _pesanKembali = true;
  bool _memuat = true;
  bool _mengirim = false;
  String _catatan = '';
  String _penyediaNama = '';
  int? _penyediaId;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _alasan.dispose();
    _batasKirim.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  double _angka(String teks) =>
      double.tryParse(teks.replaceAll('.', '').replaceAll(',', '.').trim()) ?? 0;

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final r = await ApiClient.instance
          .aksi('pengadaan_po_kekurangan', {'po_id': widget.poId});
      if (r['status'] != '00' && r['status'] != 'success') {
        _catatan = '${r['description'] ?? 'Gagal memuat kekurangan pesanan.'}';
      } else {
        _penyediaId = (r['penyedia_id'] as num?)?.toInt();
        _penyediaNama = '${r['penyedia'] ?? ''}';
        for (final b in _baris) {
          b.dispose();
        }
        _baris
          ..clear()
          ..addAll(((r['detail'] as List?) ?? const [])
              .map((e) => _BarisKurang(Map<String, dynamic>.from(e as Map)))
              .where((b) => b.kurang > 0));
        if (_baris.isEmpty) {
          _catatan = 'Tidak ada kekurangan pada ${widget.poKode} -- '
              'seluruh barang sudah diterima lengkap.';
        }
      }
    } catch (e) {
      _catatan = 'Gagal memuat kekurangan pesanan: $e';
    }
    setStateIfMounted(() => _memuat = false);
  }

  double get _nilaiDipilih => _baris
      .where((b) => b.dipilih)
      .fold(0.0, (t, b) => t + _angka(b.jumlah.text) * b.harga);

  Future<void> _kirim() async {
    if (_alasan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Alasan wajib diisi -- keputusan menutup sisa pesanan '
              'harus dapat ditelusuri.')));
      return;
    }
    final terpilih = _baris
        .where((b) => b.dipilih && _angka(b.jumlah.text) > 0)
        .toList(growable: false);
    if (_pesanKembali && terpilih.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Centang barang yang ingin dipesan ulang, atau pilih '
              'Tutup sisa saja.')));
      return;
    }
    setStateIfMounted(() => _mengirim = true);
    try {
      // Local-first: keputusan back order ditulis ke antrean perangkat dulu.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_po_back_order',
        kunci: 'pengadaan_po_back_order:${widget.poId}',
        cacheKey: 'master:pengadaan_po',
        body: {
        'po_id': widget.poId,
        'alasan': _alasan.text.trim(),
        'tindakan': _pesanKembali ? 'pesan_kembali' : 'tutup_saja',
        if (_pesanKembali && _penyediaId != null) 'penyedia_id': _penyediaId,
        if (_pesanKembali && _batasKirim.text.trim().isNotEmpty)
          'pengirimanPalingLambat': _batasKirim.text.trim(),
        if (_pesanKembali)
          'detail': terpilih
              .map((b) => {
                    'po_detail_id': b.data['po_detail_id'],
                    'jumlah': _angka(b.jumlah.text),
                  })
              .toList(),
        },
      );
      if (!mounted) return;
      final hasil = Map<String, dynamic>.from(r);
      if (hasil['offline'] == true) {
        hasil['description'] = 'Back order tersimpan di perangkat, akan dikirim otomatis. Nomor pesanan susulan terbit setelah terkirim.';
      }
      Navigator.pop(context, hasil);
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _mengirim = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Widget _barisKurang(_BarisKurang b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 32,
          child: Checkbox(
              value: b.dipilih,
              onChanged: (v) => setState(() => b.dipilih = v ?? false)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${b.data['barang'] ?? '-'}',
                  style: const TextStyle(fontSize: 12)),
              Text(
                  'dipesan ${b.data['dipesan'] ?? 0}'
                  ' · diterima ${b.data['diterima'] ?? 0}'
                  ' · kurang ${b.data['kurang'] ?? 0}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        SizedBox(
          width: 90,
          child: TextField(
            controller: b.jumlah,
            enabled: b.dipilih,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration:
                const InputDecoration(labelText: 'Pesan ulang', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(_fmtRp.format(_angka(b.jumlah.text) * b.harga),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Back Order - ${widget.poKode}'),
      content: SizedBox(
        width: 680,
        child: _memuat
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : _baris.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_catatan, textAlign: TextAlign.center))
                : SingleChildScrollView(child: _isi()),
      ),
      actions: [
        TextButton(
            onPressed: _mengirim ? null : () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton.icon(
            onPressed: (_memuat || _mengirim || _baris.isEmpty) ? null : _kirim,
            icon: _mengirim
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.replay),
            label: Text(_pesanKembali ? 'Tutup & Pesan Kembali' : 'Tutup Sisa')),
      ],
    );
  }

  Widget _isi() {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
                'Sisa pesanan ${widget.poKode} akan DITUTUP. Sesudah ditutup, '
                'pesanan ini tidak menerima barang lagi -- kekurangannya diterima '
                'pada pesanan susulan.',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  label: Text('Pesan kembali'),
                  icon: Icon(Icons.replay, size: 16)),
              ButtonSegment(
                  value: false,
                  label: Text('Tutup sisa saja'),
                  icon: Icon(Icons.block, size: 16)),
            ],
            selected: {_pesanKembali},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _pesanKembali = s.first),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _alasan,
            decoration: const InputDecoration(
                labelText: 'Alasan *',
                hintText: 'mis. stok vendor habis, barang tidak sesuai spesifikasi',
                isDense: true),
          ),
          if (_pesanKembali) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _batasKirim,
                  decoration: const InputDecoration(
                      labelText: 'Batas kirim (hh-bb-tttt)', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InputDecorator(
                  decoration:
                      const InputDecoration(labelText: 'Penyedia', isDense: true),
                  child: Text(_penyediaNama.isEmpty ? '-' : _penyediaNama),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Barang yang dipesan ulang',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(height: 4),
            ..._baris.map(_barisKurang),
            const Divider(),
            Row(children: [
              const Text('Nilai pesanan susulan',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(_fmtRp.format(_nilaiDipilih),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ],
        ]);
  }
}
