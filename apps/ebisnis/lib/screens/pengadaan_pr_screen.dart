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
import '../widgets/aksi_baris_menu.dart';

/// Layar "Permintaan Pembelian (PR)" -- tahap 1 modul Pengadaan POS.
///
/// Memakai TABEL PENGADAAN BERSAMA dengan JSP dan ZKoss (keputusan produk 2026-08-20),
/// dibedakan lewat kolom toko -- sehingga PR yang dibuat kasir terlihat juga pada alur
/// pengadaan yang sudah ada. Barang menunjuk MasterAsset, bukan produk POS.
/// Seluruh aturan bisnis (penomoran, hitung nilai, pagar ubah/hapus, keputusan
/// setujui/tolak) berada di server `PengadaanPosApiHelper` sehingga Desktop, Android,
/// dan JSP berperilaku identik.
class PengadaanPrScreen extends StatefulWidget {
  const PengadaanPrScreen({super.key});

  @override
  State<PengadaanPrScreen> createState() => _PengadaanPrScreenState();
}

class _PengadaanPrScreenState extends State<PengadaanPrScreen>
    with SingleTickerProviderStateMixin {
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
        'pengadaan_pr_daftar',
        {
          if (_cari.isNotEmpty) 'cari': _cari,
          if (_status.isNotEmpty) 'status': _status,
          'page': _halaman,
          'pageSize': _pageSize,
        },
        'master:pengadaan_pr:${_status}_${_cari}_$_halaman',
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat =
                  '${res['description'] ?? 'Gagal memuat Permintaan Pembelian.'}';
              _memuat = false;
            });
            return;
          }
          final data = ((res['data'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final dariServer = res['dariServer'] == true;
          final hakBaru = res['hak'];
          setStateIfMounted(() {
            // Hanya emisi SERVER yang membawa hak; snapshot cache tidak, dan
            // menimpanya dgn peta kosong akan memadamkan tombol tanpa alasan.
            if (hakBaru is Map) {
              _hak = hakBaru.map((k, v) => MapEntry('$k', v == true));
            }
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
                (_idBaru.isNotEmpty ||
                    _idBerubah.isNotEmpty ||
                    _jumlahHapus > 0)) {
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
      case 'DITOLAK':
        return Colors.red;
      case 'TUTUP':
        return Colors.grey;
      default:
        return const Color(0xFFB8860B);
    }
  }

  Future<void> _form({Map<String, dynamic>? awal}) async {
    Map<String, dynamic>? detailAwal;
    if (awal != null && awal['id'] != null) {
      try {
        final r = await ApiClient.instance
            .aksi('pengadaan_pr_detail', {'id': awal['id']});
        detailAwal = Map<String, dynamic>.from(r);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat detail PR: $e')));
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _FormPrDialog(
        awal: awal,
        detailAwal: detailAwal,
        onSubmit: (hasil) async {
          try {
            await prosesSimpanMaster(
              context,
              aksi: 'pengadaan_pr_simpan',
              body: hasil,
              kunci: hasil['id'] != null
                  ? 'pengadaan_pr:${hasil['id']}'
                  : 'pengadaan_pr:baru:${DateTime.now().microsecondsSinceEpoch}',
              cacheKey: 'master:pengadaan_pr',
            );
            await _muat();
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }

  /// Keputusan atas PR. Menolak WAJIB beralasan -- server menolak alasan < 5 karakter,
  /// jadi dialog ini meminta alasannya lebih dulu agar kasir tidak gagal di server.

  /// Hak per aksi yang dikirim peladen bersama daftar (grid CRUD TbmroleAction).
  /// Dipakai MEMADAMKAN tombol; gerbang sebenarnya tetap pemeriksaan di peladen.
  /// Kunci yang tidak dikirim dianggap BOLEH, sama seperti bawaan peladen.
  Map<String, bool> _hak = const {};

  bool _boleh(String aksi) => _hak[aksi] != false;

  Future<void> _putusan(Map<String, dynamic> pr, String keputusan) async {
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
                helperText: 'Minimal 5 karakter, dibaca pembuat PR'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Tolak PR')),
          ],
        ),
      );
      alasan = c.text.trim();
      c.dispose();
      if (ok != true || !mounted) return;
    }
    try {
      // Local-first: keputusan ditulis ke antrean perangkat DULU, baru dikirim.
      // Petugas yang menyetujui di gudang tanpa sinyal tidak perlu menunggu.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_pr_putusan',
        body: {
          'id': pr['id'],
          'keputusan': keputusan,
          if (alasan.isNotEmpty) 'alasan': alasan,
        },
        kunci: 'pengadaan_pr_putusan:${pr['id']}',
        cacheKey: 'master:pengadaan_pr',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['offline'] == true
              ? 'Keputusan tersimpan di perangkat, akan dikirim otomatis.'
              : 'Keputusan tersimpan: ${r['statusPr'] ?? keputusan}')));
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _hapus(Map<String, dynamic> pr) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Permintaan Pembelian'),
        content: Text('Hapus PR ${pr['kode']}? Hanya PR berstatus DRAFT yang '
            'dapat dihapus; dokumen yang sudah diputus disimpan sebagai jejak.'),
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
        aksi: 'pengadaan_pr_hapus',
        body: {'id': pr['id']},
        kunci: 'pengadaan_pr:${pr['id']}',
        cacheKey: 'master:pengadaan_pr',
        rowLokal: {'id': pr['id']},
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
          builder: (_) =>
              const PengadaanBulkEntryScreen(jenis: JenisPengadaanBulk.pr)),
    );
    if (hasil == true && mounted) await _muat();
  }

  /// Dua tab pada setiap menu Pengadaan: "Dasbor" (ringkasan angka) dan
  /// "Permintaan" (daftar + CRUD). Susunannya sengaja disamakan di keenam
  /// menu supaya berpindah tahap tidak menuntut penyesuaian kebiasaan.
  Widget _bungkusTab(Widget isiData) {
    return Column(children: [
      TabBar(
        controller: _tabUtama,
        tabs: const [
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
          Tab(
              icon: Icon(Icons.list_alt_outlined, size: 18),
              text: 'Permintaan'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabUtama,
          children: [
            const PengadaanDasborTab(tahap: 'pr'),
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
      menuAktif: MenuEBisnis.pengadaanPr,
      judul: 'Permintaan Pembelian (PR)',
      subjudul: 'Ajukan kebutuhan barang sebelum dipesan ke supplier',
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
      floatingActionButton: !_boleh('create')
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _form(),
              icon: const Icon(Icons.add),
              label: const Text('Buat PR'),
            ),
      body: _bungkusTab(Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 260,
              child: AppSearchField(
                hintText: 'Cari kode / keterangan',
                onChanged: (v) {
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
                  DropdownMenuItem(
                      value: 'DISETUJUI', child: Text('Disetujui')),
                  DropdownMenuItem(value: 'DITOLAK', child: Text('Ditolak')),
                  DropdownMenuItem(value: 'TUTUP', child: Text('Tutup')),
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
            'Belum ada Permintaan Pembelian.\nTekan "Buat PR" untuk mengajukan kebutuhan barang.',
            textAlign: TextAlign.center),
      );
    }
    return AppDataTable(
      minWidth: 900,
      emptyText: 'Tidak ada PR pada filter ini.',
      columns: const [
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Tanggal', flex: 2),
        AppTableColumn('Keterangan', flex: 3),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('Status', flex: 2),
        AppTableColumn('Aksi', width: 64),
      ],
      rows: _daftar.map(_barisPr).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: 'PR',
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

  AppTableRowData _barisPr(Map<String, dynamic> pr) {
    final st = '${pr['status'] ?? 'DRAFT'}';
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 2,
        child: KilauBaris(
          kunci: '${pr['id'] ?? ''}',
          idBaru: _idBaru,
          idBerubah: _idBerubah,
          child: Text('${pr['kode'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      AppTableCell.text('${pr['tanggal'] ?? '-'}', flex: 2),
      AppTableCell.text('${pr['keterangan'] ?? ''}', flex: 3),
      AppTableCell.text(_fmtRp.format(pr['nilai'] ?? 0),
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
      AppTableCell(width: 64, child: _aksiPr(pr, st)),
    ]);
  }

  /// Aksi baris diringkas menjadi satu tombol "...". Setujui/Tolak/Batalkan
  /// dahulu saling menggantikan mengikuti status; kini ketiganya selalu tampil
  /// dan yang tidak berlaku hanya diredupkan, sehingga letak tiap aksi tetap.
  Widget _aksiPr(Map<String, dynamic> pr, String st) {
    return AksiBarisMenu(aksi: [
      // Cetak dokumen: pratinjau lebih dulu, mencetak menyusul. Templatnya sama
      // dengan versi ZKoss sehingga hasil cetaknya identik.
      AksiBaris(
          ikon: Icons.print_outlined,
          label: 'Cetak / pratinjau',
          onTap: () => cetakDokumenPengadaan(context,
              tahap: 'pr',
              id: (pr['id'] as num).toInt(),
              kode: '${pr['kode'] ?? ''}')),
      AksiBaris(
          ikon: Icons.edit_outlined,
          label: 'Lihat / ubah',
          onTap: () => _form(awal: pr)),
      AksiBaris(
          ikon: Icons.check_circle_outline,
          label: 'Setujui',
          onTap: st == 'DRAFT' && _boleh('approve')
              ? () => _putusan(pr, 'SETUJUI')
              : null),
      AksiBaris(
          ikon: Icons.cancel_outlined,
          label: 'Tolak',
          onTap: st == 'DRAFT' && _boleh('reject')
              ? () => _putusan(pr, 'TOLAK')
              : null),
      AksiBaris(
          ikon: Icons.undo,
          label: 'Batalkan keputusan',
          onTap: (st == 'DISETUJUI' || st == 'DITOLAK') && _boleh('approve')
              ? () => _putusan(pr, 'BATAL')
              : null),
      AksiBaris(
          ikon: Icons.history,
          label: 'Riwayat data',
          onTap: pr['id'] == null
              ? null
              : () => tampilkanRiwayatData(context,
                  entitas: 'pengadaan_pr',
                  id: pr['id'],
                  judul: '${pr['kode'] ?? ''}')),
      AksiBaris(
          ikon: Icons.delete_outline,
          label: 'Hapus',
          merusak: true,
          onTap: st == 'DRAFT' && _boleh('delete') ? () => _hapus(pr) : null),
    ]);
  }
}

/// Satu baris barang pada form PR.
class _BarisPr {
  /// Barang menunjuk MasterAsset (tabel pengadaan BERSAMA dgn JSP/ZKoss),
  /// bukan produk POS -- lihat catatan di PengadaanPosApiHelper.cariBarang.
  int? barangId;

  /// Id MasterAsset asal, dipakai bila baris berasal dari dokumen hulu
  /// yang barangnya belum berpadanan produk POS.
  int? masterAssetId;
  String namaBarang;

  /// Nama satuan PEMBELIAN produk padanan (PDF stok & uom butir 3):
  /// qty & harga PR/PO bersemantik satuan pembelian -- label kolom
  /// menampilkannya; kosong utk barang tanpa padanan/satuan.
  String satuan;
  final TextEditingController jumlah;
  final TextEditingController harga;
  final TextEditingController keterangan;
  _BarisPr({
    this.barangId,
    this.masterAssetId,
    required this.namaBarang,
    this.satuan = '',
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

class _FormPrDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final Map<String, dynamic>? detailAwal;
  final Future<bool> Function(Map<String, dynamic> data) onSubmit;
  const _FormPrDialog({
    this.awal,
    this.detailAwal,
    required this.onSubmit,
  });

  @override
  State<_FormPrDialog> createState() => _FormPrDialogState();
}

class _FormPrDialogState extends State<_FormPrDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  late final TextEditingController _keterangan;
  final List<_BarisPr> _baris = [];

  /// Anggaran yang dibebani permintaan ini. WAJIB kecuali [_tanpaAnggaran]
  /// dicentang -- PR memotong anggaran, jadi sumbernya harus jelas sejak awal.
  int? _anggaranId;
  String _anggaranNama = '';
  bool _tanpaAnggaran = false;
  bool get _baru => widget.awal == null;
  String get _status => '${widget.detailAwal?['header']?['status'] ?? 'DRAFT'}';
  bool get _terkunci => _status != 'DRAFT';

  @override
  void initState() {
    super.initState();
    final h = widget.detailAwal?['header'] as Map?;
    _keterangan = TextEditingController(
        text: '${h?['keterangan'] ?? widget.awal?['keterangan'] ?? ''}');
    _anggaranId = (h?['workspace_id'] as num?)?.toInt();
    _anggaranNama = '${h?['anggaran'] ?? ''}';
    _tanpaAnggaran = h?['tanpaAnggaran'] == true;
    for (final d in ((widget.detailAwal?['detail'] as List?) ?? const [])) {
      final m = Map<String, dynamic>.from(d as Map);
      _baris.add(_BarisPr(
        barangId: (m['produk_id'] as num?)?.toInt(),
        masterAssetId: (m['master_asset_id'] as num?)?.toInt(),
        namaBarang: '${m['barang'] ?? '-'}',
        jumlahAwal: '${m['jumlah'] ?? 1}',
        hargaAwal: '${m['hargaBeli'] ?? 0}',
        keteranganAwal: '${m['keterangan'] ?? ''}',
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

  /// Pemilih Anggaran. Menampilkan pagu, realisasi, dan sisanya supaya kemampuan
  /// anggaran terlihat SEBELUM permintaan diajukan -- bukan setelah ditolak penyetuju.
  Future<void> _pilihAnggaran() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PilihAnggaranDialog(),
    );
    if (pilihan == null || !mounted) return;
    setState(() {
      _anggaranId = (pilihan['id'] as num?)?.toInt();
      _anggaranNama =
          '${pilihan['kode'] ?? ''} ${pilihan['nama'] ?? ''}'.trim();
    });
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _total => _baris.fold(
      0, (s, b) => s + _angka(b.jumlah.text) * _angka(b.harga.text));

  Future<void> _tambahBaris() async {
    final q = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    final dipilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> cari() async {
          try {
            final r = await ApiClient.instance.aksi('pengadaan_barang_cari',
                {'keyword': q.text.trim(), 'limit': 50});
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
              AppSearchField(
                controller: q,
                hintText: 'Cari kode / nama barang',
                scanProduk: true,
                autofocus: true,
                onChanged: (_) => cari(),
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
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Tutup'))
          ],
        );
      }),
    );
    q.dispose();
    if (dipilih == null) return;
    setState(() => _baris.add(_BarisPr(
          barangId: (dipilih['id'] as num?)?.toInt(),
          namaBarang: '${dipilih['nama'] ?? '-'}',
          satuan: '${dipilih['satuanPembelianNama'] ?? ''}',
        )));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_baru
          ? 'Buat Permintaan Pembelian'
          : 'PR ${widget.awal?['kode'] ?? ''}  ·  $_status'),
      content: SizedBox(
        width: 720,
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
                      'PR berstatus $_status tidak dapat diubah. Batalkan keputusannya '
                      'terlebih dahulu bila memang perlu dikoreksi.',
                      style: const TextStyle(fontSize: 12)),
                ),
              TextField(
                controller: _keterangan,
                enabled: !_terkunci,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Keterangan / kebutuhan',
                    hintText: 'Mis. stok minuman menipis untuk akhir pekan'),
              ),
              const SizedBox(height: 10),
              // Saat "Tanpa anggaran" dicentang, pemilih anggarannya DISEMBUNYIKAN --
              // bukan sekadar dimatikan. Kolom mati yang tetap terlihat hanya
              // mengundang pertanyaan apakah masih perlu diisi. Pola yang sama dipakai
              // versi ZKoss lewat centang "Non RKA".
              Row(children: [
                if (!_tanpaAnggaran)
                  Expanded(
                    child: InkWell(
                      onTap: _terkunci ? null : _pilihAnggaran,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Anggaran *',
                          isDense: true,
                          suffixIcon: const Icon(Icons.search, size: 18),
                          errorText:
                              _anggaranId == null ? 'Wajib dipilih' : null,
                        ),
                        child: Text(
                            _anggaranNama.isEmpty
                                ? 'Pilih anggaran'
                                : _anggaranNama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  )
                else
                  const Expanded(
                    child: Text('Permintaan ini tidak membebani anggaran.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                const SizedBox(width: 8),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    value: _tanpaAnggaran,
                    onChanged: _terkunci
                        ? null
                        : (v) => setState(() {
                              _tanpaAnggaran = v ?? false;
                              if (_tanpaAnggaran) {
                                _anggaranId = null;
                                _anggaranNama = '';
                              }
                            }),
                  ),
                  const SizedBox(
                    width: 56,
                    child: Text('Tanpa anggaran',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10)),
                  ),
                ]),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: Row(children: [
                  const Expanded(
                      child: Text('Barang yang Diminta',
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
                        child: Text(b.namaBarang,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 80,
                        child: TextField(
                            controller: b.jumlah,
                            enabled: !_terkunci,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                                labelText: b.satuan.isEmpty
                                    ? 'Jumlah'
                                    : 'Jumlah (${b.satuan})',
                                isDense: true))),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 120,
                        child: TextField(
                            controller: b.harga,
                            enabled: !_terkunci,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                                labelText: b.satuan.isEmpty
                                    ? 'Harga Modal'
                                    : 'Harga Modal /${b.satuan}',
                                isDense: true))),
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
                      child: Text('Total Nilai PR',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(_fmtRp.format(_total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    'Nilai dihitung ulang oleh server dari baris di atas, sehingga total '
                    'dokumen selalu sama dengan rinciannya.',
                    style:
                        TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
        if (!_terkunci)
          AppCrudDialogActions(
            onSubmit: () async {
              if (_baris.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Tambahkan minimal satu baris barang.')));
                return false;
              }
              return widget.onSubmit(<String, dynamic>{
                if (!_baru) 'id': widget.awal!['id'],
                'keterangan': _keterangan.text.trim(),
                'tanpaAnggaran': _tanpaAnggaran,
                if (!_tanpaAnggaran && _anggaranId != null)
                  'workspace_id': _anggaranId,
                'detail': _baris
                    .where((b) => b.barangId != null || b.masterAssetId != null)
                    .map((b) => {
                          if (b.barangId != null)
                            'produk_id': b.barangId
                          else
                            'master_asset_id': b.masterAssetId,
                          'jumlah': _angka(b.jumlah.text),
                          'hargaBeli': _angka(b.harga.text),
                          'keterangan': b.keterangan.text.trim(),
                        })
                    .toList(),
              });
            },
          ),
      ],
    );
  }
}

/// Pemilih Anggaran (Workspace) untuk Permintaan Pembelian.
///
/// Angka pagu/realisasi/sisa berasal dari kolom yang dipelihara modul Anggaran
/// sendiri, bukan dihitung ulang di sini -- supaya tidak muncul definisi kedua
/// yang lambat laun berbeda dengan layar Anggaran.
class _PilihAnggaranDialog extends StatefulWidget {
  const _PilihAnggaranDialog();

  @override
  State<_PilihAnggaranDialog> createState() => _PilihAnggaranDialogState();
}

class _PilihAnggaranDialogState extends State<_PilihAnggaranDialog> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  List<Map<String, dynamic>> _hasil = [];
  bool _memuat = true;
  String _catatan = '';
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
      final r = await ApiClient.instance.aksi('pengadaan_anggaran_cari', {
        if (_cari.text.trim().isNotEmpty) 'keyword': _cari.text.trim(),
        'limit': 50,
      });
      _hasil = ((r['data'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _catatan = '${r['catatan'] ?? ''}';
    } catch (e) {
      _hasil = [];
      _catatan = 'Gagal memuat anggaran: $e';
    }
    setStateIfMounted(() => _memuat = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Anggaran'),
      content: SizedBox(
        width: 600,
        height: 440,
        child: Column(children: [
          AppSearchField(
            controller: _cari,
            hintText: 'Cari kode / nama anggaran',
            onChanged: (_) => _muat(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _hasil.isEmpty
                    ? Center(
                        child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            _catatan.isEmpty
                                ? 'Tidak ada anggaran aktif.'
                                : _catatan,
                            textAlign: TextAlign.center),
                      ))
                    : ListView.builder(
                        itemCount: _hasil.length,
                        itemBuilder: (_, i) {
                          final a = _hasil[i];
                          final sisa = (a['sisa'] as num?)?.toDouble() ?? 0;
                          return ListTile(
                            dense: true,
                            title: Text(
                                '${a['kode'] ?? ''} ${a['nama'] ?? ''}'.trim()),
                            subtitle: Text(
                                'pagu ${_fmtRp.format(a['pagu'] ?? 0)}'
                                ' · realisasi ${_fmtRp.format(a['realisasi'] ?? 0)}'
                                ' · dalam proses ${_fmtRp.format(a['dalamProses'] ?? 0)}',
                                style: const TextStyle(fontSize: 10)),
                            trailing: Text(_fmtRp.format(sisa),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color:
                                        sisa <= 0 ? Colors.red : Colors.teal)),
                            onTap: () => Navigator.pop(context, a),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
      ],
    );
  }
}
