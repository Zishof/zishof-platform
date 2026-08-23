import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'pengadaan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';
import 'pengadaan_transitori_tab.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

/// Layar "Pembayaran Vendor" -- tahap 5 modul Pengadaan POS.
///
/// Memakai tabel pembayaran termin yang sama dengan JSP/ZKoss, dibedakan kolom toko.
/// Yang membuat pembayaran DIAKUI adalah PERSETUJUAN: perhitungan kanonik pada
/// PemesananPengadaanMasterAsset.hitungDibayar hanya menjumlahkan dokumen yang sudah
/// disetujui. Karena itu dokumen draf sengaja belum mengubah status PO.
class PengadaanBayarScreen extends StatefulWidget {
  /// Dipasang di dalam layar Proses Transfer sebagai salah satu tab.
  ///
  /// Mode tersemat melepas [AppShell] dan deret tab miliknya sendiri -- kerangka
  /// dan tab itu sudah disediakan tuan rumahnya. Yang tersisa hanyalah penyaring,
  /// tabel, dan tombol "Bayar Vendor", sehingga TIDAK ADA satu pun kemampuan yang
  /// hilang karena penggabungan menu.
  final bool tersemat;

  const PengadaanBayarScreen({super.key, this.tersemat = false});

  @override
  State<PengadaanBayarScreen> createState() => _PengadaanBayarScreenState();
}

class _PengadaanBayarScreenState extends State<PengadaanBayarScreen>
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
    _tabUtama = TabController(length: 3, vsync: this);
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
              _galat =
                  '${res['description'] ?? 'Gagal memuat pembayaran vendor.'}';
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
                onChanged: (v) => setLocal(() => ajukanTransfer = v ?? false),
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
      // Local-first: keputusan ditulis ke antrean perangkat DULU, baru dikirim.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_bayar_putusan',
        body: {
          'id': row['id'],
          'keputusan': keputusan,
          if (keputusan == 'SETUJUI' && ajukanTransfer) 'ajukanTransfer': true,
        },
        kunci: 'pengadaan_bayar_putusan:${row['id']}',
        cacheKey: 'master:pengadaan_bayar',
      );
      if (!mounted) return;
      final trfDibuat = (r['transferDibuat'] as num?)?.toInt() ?? 0;
      final trfDitarik = (r['transferDitarik'] as num?)?.toInt() ?? 0;
      final catatanTrf = trfDibuat > 0
          ? ' · $trfDibuat pengajuan transfer dibuat'
          : (trfDitarik > 0 ? ' · $trfDitarik pengajuan transfer ditarik' : '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['offline'] == true
              ? 'Keputusan tersimpan di perangkat, akan dikirim otomatis.'
              : 'Keputusan tersimpan: ${r['statusDokumen'] ?? keputusan}$catatanTrf')));
      await _muat();
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
      final r =
          await ApiClient.instance.aksi('pengadaan_bayar_tagihan_terbuka', {
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

  /// Dua tab pada setiap menu Pengadaan: "Dasbor" (ringkasan angka) dan
  /// "Pembayaran" (daftar + CRUD). Susunannya sengaja disamakan di keenam
  /// menu supaya berpindah tahap tidak menuntut penyesuaian kebiasaan.
  Widget _bungkusTab(Widget isiData) {
    return Column(children: [
      TabBar(
        controller: _tabUtama,
        tabs: const [
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
          Tab(
              icon: Icon(Icons.list_alt_outlined, size: 18),
              text: 'Pembayaran'),
          Tab(
              icon: Icon(Icons.pause_circle_outline, size: 18),
              text: 'Transitori'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabUtama,
          children: [
            const PengadaanDasborTab(tahap: 'dpc'),
            isiData,
            const PengadaanTransitoriTab(),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    if (widget.tersemat) {
      // Scaffold transparan dipakai semata-mata agar tombol "Bayar Vendor"
      // tetap mengambang di sudut tab, sama seperti saat layar ini berdiri
      // sendiri. Latarnya transparan supaya warna tuan rumah yang terlihat.
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _bayarBaru(),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Bayar Vendor'),
        ),
        body: _isi(totalHalaman),
      );
    }
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
      body: _bungkusTab(_isi(totalHalaman)),
    );
  }

  /// Isi layar tanpa kerangka: penyaring, banner perubahan server, dan tabel.
  /// Dipakai bersama oleh mode berdiri sendiri dan mode tersemat.
  Widget _isi(int totalHalaman) {
    return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 280,
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
    ]);
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
        AppTableColumn('Aksi', width: 64),
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
    final warna = disetujui ? const Color(0xFF2E7D32) : const Color(0xFFB8860B);
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
        width: 64,
        child: AksiBarisMenu(aksi: [
          // Cetak dokumen: pratinjau lebih dulu, mencetak menyusul. Templatnya sama
          // dengan versi ZKoss sehingga hasil cetaknya identik.
          AksiBaris(
              ikon: Icons.print_outlined,
              label: 'Cetak / pratinjau',
              onTap: () => cetakDokumenPengadaan(context,
                  tahap: 'dpc',
                  id: (row['id'] as num).toInt(),
                  kode: '${row['kode'] ?? ''}')),
          AksiBaris(
              ikon: Icons.edit_outlined,
              label: 'Lihat / ubah',
              onTap: () => _bayarBaru(awal: row)),
          // Setujui dan Batalkan dahulu saling menggantikan di layar; kini keduanya
          // selalu tampil dan yang tidak berlaku hanya diredupkan, supaya letaknya
          // tidak berpindah-pindah mengikuti status.
          AksiBaris(
              ikon: Icons.check_circle_outline,
              label: 'Setujui pembayaran',
              onTap: disetujui ? null : () => _putusan(row, 'SETUJUI')),
          AksiBaris(
              ikon: Icons.undo,
              label: 'Batalkan persetujuan',
              onTap: disetujui ? () => _putusan(row, 'BATAL') : null),
          AksiBaris(
              ikon: Icons.history,
              label: 'Riwayat data',
              onTap: row['id'] == null
                  ? null
                  : () => tampilkanRiwayatData(context,
                      entitas: 'pengadaan_bayar',
                      id: row['id'],
                      judul: '${row['kode'] ?? ''}')),
          AksiBaris(
              ikon: Icons.delete_outline,
              label: 'Hapus',
              merusak: true,
              onTap: disetujui ? null : () => _hapus(row)),
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
          AppSearchField(
            controller: _cari,
            hintText: 'Cari kode / nama penyedia',
            autofocus: true,
            onChanged: (_) => _muat(),
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
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

  /// Transfer (langsung ke rekening penyedia) atau Transitori (ditampung dulu
  /// pada akun transitori, direalisasikan menyusul). Pilihan ini menentukan akun
  /// kredit jurnalnya di server, bukan sekadar penanda di layar.
  bool transitori;
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
    this.transitori = false,
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
  late final TextEditingController _judul;
  late final TextEditingController _tglRealisasi;
  final List<_BarisBayar> _baris = [];

  /// Pilihan Cara Transfer -- mengikuti form Proses Transfer versi ZKoss.
  /// Akun pada cara transfer inilah yang dipakai saat jurnal dibentuk.
  List<Map<String, dynamic>> _caraBayar = [];
  int? _caraBayarId;
  bool _memuatCaraBayar = true;

  bool get _baru => widget.awal == null;
  String get _status => '${widget.detailAwal?['header']?['status'] ?? 'DRAFT'}';
  bool get _terkunci => _status != 'DRAFT';

  @override
  void initState() {
    super.initState();
    _keterangan = TextEditingController(
        text: '${widget.detailAwal?['header']?['keterangan'] ?? ''}');
    _judul = TextEditingController(
        text: '${widget.detailAwal?['header']?['judul'] ?? ''}');
    _tglRealisasi = TextEditingController(
        text: '${widget.detailAwal?['header']?['tanggalRealisasi'] ?? ''}');
    _caraBayarId =
        (widget.detailAwal?['header']?['cara_bayar_id'] as num?)?.toInt();
    _muatCaraBayar();

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
        transitori: m['transitori'] == true,
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

  Future<void> _pilihTanggalRealisasi() async {
    DateTime awal = DateTime.now();
    final bagian = _tglRealisasi.text.trim().split('-');
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
    setState(() => _tglRealisasi.text = DateFormat('dd-MM-yyyy').format(pilih));
  }

  @override
  void dispose() {
    _keterangan.dispose();
    _judul.dispose();
    _tglRealisasi.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _muatCaraBayar() async {
    try {
      final r = await ApiClient.instance.aksi('pengadaan_cara_bayar_opsi', {});
      if (!mounted) return;
      setState(() {
        _caraBayar = ((r['data'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _caraBayarId ??= (r['bawaan_id'] as num?)?.toInt();
        _memuatCaraBayar = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuatCaraBayar = false);
    }
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _total => _baris
      .where((b) => b.pilih)
      .fold(0, (s, b) => s + _angka(b.dibayar.text));

  void _simpan() {
    // Cara transfer TIDAK menghalangi penyimpanan draf -- ia baru dituntut saat
    // pembayaran disetujui, karena di titik itulah jurnal dibentuk. Di sini cukup
    // diingatkan supaya tidak terlupa sampai tahap persetujuan.
    if (_caraBayarId == null && _caraBayar.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cara transfer belum dipilih. Draf tetap tersimpan, '
              'tetapi harus diisi sebelum pembayaran disetujui.')));
    }
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
            content:
                Text('Nilai bayar ${b.poKode} harus lebih besar dari nol.')));
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
      'judul': _judul.text.trim(),
      'keterangan': _keterangan.text.trim(),
      if (_caraBayarId != null) 'cara_bayar_id': _caraBayarId,
      if (_tglRealisasi.text.trim().isNotEmpty)
        'tanggalRealisasi': _tglRealisasi.text.trim(),
      'detail': dipilih
          .map((b) => {
                'po_id': b.poId,
                'termin_key': b.terminKey,
                'dibayar': _angka(b.dibayar.text),
                'transitori': b.transitori,
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
                controller: _judul,
                enabled: !_terkunci,
                decoration: const InputDecoration(
                    labelText: 'Judul transfer',
                    hintText: 'Mis. Pembayaran termin I CV Sumber Rejeki',
                    isDense: true),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: _memuatCaraBayar
                      ? const InputDecorator(
                          decoration: InputDecoration(
                              labelText: 'Cara transfer *', isDense: true),
                          child: Text('memuat...'))
                      : _caraBayar.isEmpty
                          ? InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'Cara transfer', isDense: true),
                              child: Text(
                                  'Belum ada Cara Transfer aktif. Atur dahulu di '
                                  'master Cara Pembayaran Transfer agar pembayaran '
                                  'dapat dijurnal.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange.shade900)))
                          : DropdownButtonFormField<int>(
                              value: _caraBayarId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Cara transfer *',
                                  helperText:
                                      'Akun pada cara transfer dipakai saat jurnal dibentuk',
                                  isDense: true),
                              items: _caraBayar
                                  .map((c) => DropdownMenuItem<int>(
                                        value: (c['id'] as num).toInt(),
                                        child: Text(
                                            '${c['nama'] ?? ''}'
                                            '${'${c['akun'] ?? ''}'.isEmpty ? '' : ' - ${c['akun']}'}',
                                            overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: _terkunci
                                  ? null
                                  : (v) => setState(() => _caraBayarId = v),
                            ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  /* Diketik manual sebelumnya, dan formatnya harus ditebak dari
                   * petunjuk "hh-bb-tttt". Kini lewat pemilih tanggal, sehingga
                   * tidak ada tanggal salah format yang lolos ke server. */
                  child: TextField(
                    controller: _tglRealisasi,
                    enabled: !_terkunci,
                    readOnly: true,
                    onTap: _terkunci ? null : _pilihTanggalRealisasi,
                    decoration: InputDecoration(
                      labelText: 'Tanggal realisasi',
                      hintText: 'Pilih tanggal',
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.event, size: 18),
                        tooltip: 'Pilih tanggal realisasi',
                        onPressed: _terkunci ? null : _pilihTanggalRealisasi,
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _keterangan,
                enabled: !_terkunci,
                decoration: const InputDecoration(
                    labelText: 'Keterangan pembayaran',
                    hintText: 'Mis. transfer BCA 20 Agustus',
                    isDense: true),
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
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
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF00695C)))),
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
        const SizedBox(width: 8),
        /* Pilihan per baris, bukan per dokumen: satu pembayaran boleh memuat
         * sebagian tagihan yang ditransfer langsung dan sebagian lagi yang
         * ditampung dulu sebagai transitori. Begitu pula di versi ZKoss. */
        SizedBox(
          width: 168,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('Transfer', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.north_east, size: 14)),
              ButtonSegment(
                  value: true,
                  label: Text('Transitori', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.pause_circle_outline, size: 14)),
            ],
            selected: {b.transitori},
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onSelectionChanged: (_terkunci || !b.pilih)
                ? null
                : (v) => setState(() => b.transitori = v.first),
          ),
        ),
      ]),
    );
  }
}
