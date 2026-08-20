import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/master_offline.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/safe_state.dart';

/// Layar "Barang Dalam Proses" (CIP -- <i>Construction in Progress</i>).
///
/// Mengikuti arti yang dipakai versi ZKoss pada `BarangDalamProsesDashboard`:
/// sumbernya PENERIMAAN BARANG (BAST), bukan pesanan yang belum datang. Versi
/// pertama layar ini keliru menampilkan kebalikannya, sehingga barang yang sudah
/// dibeli justru hilang begitu BAST-nya dibuat.
///
/// Dua pandangan disediakan dalam satu layar:
///
/// * **Sudah Diterima (BAST)** -- bawaan. Rekap seluruh penerimaan beserta status
///   persetujuan, nilai, dan apakah sudah masuk stok lewat sinkronisasi Kulakan.
/// * **Belum Datang** -- pandangan lama yang tetap berguna untuk memantau kiriman
///   yang tertunda; dilayani server dengan `mode=belum_datang`.
class PengadaanBdpScreen extends StatefulWidget {
  const PengadaanBdpScreen({super.key});

  @override
  State<PengadaanBdpScreen> createState() => _PengadaanBdpScreenState();
}

class _PengadaanBdpScreenState extends State<PengadaanBdpScreen> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  /// true = pandangan BAST (bawaan); false = pandangan "belum datang".
  bool _modeBast = true;

  bool _memuat = true;
  String? _galat;
  String _catatan = '';
  List<Map<String, dynamic>> _daftar = [];
  String _cari = '';
  bool _hanyaTerlambat = false;
  bool _hanyaCip = false;
  bool _hanyaBelumDisetujui = false;
  int _halaman = 1;
  int _total = 0;
  double _totalNilai = 0;
  int _jumlahTerlambat = 0;
  int _jumlahDisetujui = 0;
  double _nilaiDisetujui = 0;
  static const _pageSize = 25;

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
    final param = <String, dynamic>{
      if (_cari.isNotEmpty) 'cari': _cari,
      'page': _halaman,
      'pageSize': _pageSize,
      if (_modeBast) ...{
        if (_hanyaCip) 'hanyaCip': true,
        if (_hanyaBelumDisetujui) 'hanyaBelumDisetujui': true,
      } else ...{
        'mode': 'belum_datang',
        if (_hanyaTerlambat) 'hanyaTerlambat': true,
      },
    };
    final kunci = _modeBast
        ? 'master:pengadaan_bdp:bast:${_hanyaCip}_${_hanyaBelumDisetujui}_${_cari}_$_halaman'
        : 'master:pengadaan_bdp:belum:${_hanyaTerlambat}_${_cari}_$_halaman';
    try {
      await MasterOffline.daftarCacheDulu(
        'pengadaan_bdp_daftar',
        param,
        kunci,
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat = '${res['description'] ?? 'Gagal memuat Barang Dalam Proses.'}';
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
            _totalNilai = (res['totalNilai'] as num?)?.toDouble() ?? 0;
            _jumlahTerlambat = (res['jumlahTerlambat'] as num?)?.toInt() ?? 0;
            _jumlahDisetujui = (res['jumlahDisetujui'] as num?)?.toInt() ?? 0;
            _nilaiDisetujui = (res['nilaiDisetujui'] as num?)?.toDouble() ?? 0;
            _catatan = '${res['catatan'] ?? ''}';
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

  void _gantiMode(bool bast) {
    if (_modeBast == bast) return;
    setStateIfMounted(() {
      _modeBast = bast;
      _halaman = 1;
      _daftar = [];
    });
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanBdp,
      judul: 'Barang Dalam Proses',
      subjudul: _modeBast
          ? 'Rekap penerimaan barang (BAST) beserta nilai dan statusnya'
          : 'Barang yang sudah dipesan tetapi belum diterima',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true,
                    label: Text('Sudah Diterima (BAST)'),
                    icon: Icon(Icons.inventory_2_outlined, size: 16)),
                ButtonSegment(
                    value: false,
                    label: Text('Belum Datang'),
                    icon: Icon(Icons.local_shipping_outlined, size: 16)),
              ],
              selected: {_modeBast},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _gantiMode(s.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: InputDecoration(
                    labelText: _modeBast
                        ? 'Cari kode BAST / vendor / uraian'
                        : 'Cari kode PO / nama barang',
                    prefixIcon: const Icon(Icons.search),
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
            if (_modeBast) ...[
              FilterChip(
                label: const Text('Hanya Pekerjaan Dalam Pelaksanaan (CIP)'),
                selected: _hanyaCip,
                onSelected: (v) {
                  setStateIfMounted(() {
                    _hanyaCip = v;
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
              FilterChip(
                label: const Text('Belum disetujui'),
                selected: _hanyaBelumDisetujui,
                onSelected: (v) {
                  setStateIfMounted(() {
                    _hanyaBelumDisetujui = v;
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
            ] else
              FilterChip(
                label: const Text('Hanya yang terlambat'),
                selected: _hanyaTerlambat,
                onSelected: (v) {
                  setStateIfMounted(() {
                    _hanyaTerlambat = v;
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
          ]),
        ),
        if (!_memuat && _galat == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(spacing: 10, runSpacing: 8, children: _modeBast
                ? [
                    _kotak('Total BAST', '$_total'),
                    _kotak('Total nilai', _fmtRp.format(_totalNilai)),
                    _kotak('Sudah disetujui',
                        '$_jumlahDisetujui · ${_fmtRp.format(_nilaiDisetujui)}'),
                    _kotak('Belum disetujui',
                        '${_total - _jumlahDisetujui} · ${_fmtRp.format(_totalNilai - _nilaiDisetujui)}',
                        merah: _total - _jumlahDisetujui > 0),
                  ]
                : [
                    _kotak('Baris', '$_total'),
                    _kotak('Nilai belum datang', _fmtRp.format(_totalNilai)),
                    _kotak('Lewat batas kirim', '$_jumlahTerlambat',
                        merah: _jumlahTerlambat > 0),
                  ]),
          ),
        Expanded(child: _isiTabel(totalHalaman)),
      ]),
    );
  }

  Widget _kotak(String label, String nilai, {bool merah = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          border: Border.all(
              color: (merah ? Colors.red : Colors.grey).withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(nilai,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: merah ? Colors.red : null)),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              _catatan.isNotEmpty
                  ? _catatan
                  : (_modeBast
                      ? 'Belum ada penerimaan barang (BAST) yang tercatat.'
                      : 'Tidak ada barang yang belum datang.'),
              textAlign: TextAlign.center),
        ),
      );
    }
    return AppDataTable(
      minWidth: _modeBast ? 1240 : 1120,
      emptyText: 'Tidak ada baris pada filter ini.',
      columns: _modeBast
          ? const [
              AppTableColumn('BAST', flex: 3),
              AppTableColumn('Vendor', flex: 3),
              AppTableColumn('Lokasi', flex: 2),
              AppTableColumn('No. PO', flex: 2),
              AppTableColumn('Uraian', flex: 3),
              AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Status', flex: 2),
            ]
          : const [
              AppTableColumn('PO', flex: 2),
              AppTableColumn('Penyedia', flex: 3),
              AppTableColumn('Barang', flex: 3),
              AppTableColumn('Dipesan', flex: 2, align: TextAlign.right),
              AppTableColumn('Diterima', flex: 2, align: TextAlign.right),
              AppTableColumn('Belum datang', flex: 2, align: TextAlign.right),
              AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
              AppTableColumn('Batas kirim', flex: 2),
            ],
      rows: _daftar.map(_modeBast ? _barisBast : _barisBelum).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: _modeBast ? 'penerimaan' : 'baris',
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

  String _angka(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
  }

  AppTableRowData _barisBast(Map<String, dynamic> row) {
    final disetujui = row['disetujui'] == true;
    final masukStok = row['sudahMasukStok'] == true;
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 3,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${row['kode'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(masukStok ? 'sudah masuk stok' : 'belum masuk stok',
                  style: TextStyle(
                      fontSize: 10,
                      color: masukStok ? Colors.teal : Colors.orange)),
            ]),
      ),
      AppTableCell.text('${row['vendor'] ?? '-'}', flex: 3),
      AppTableCell.text(
          '${row['lokasi'] ?? ''}'.isEmpty ? '-' : '${row['lokasi']}',
          flex: 2),
      AppTableCell.text('${row['po'] ?? ''}'.isEmpty ? '-' : '${row['po']}',
          flex: 2),
      AppTableCell.text(
          '${row['uraian'] ?? ''}'.isEmpty ? '-' : '${row['uraian']}',
          flex: 3),
      AppTableCell.text(_fmtRp.format(row['nilai'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell.text('${row['tanggal'] ?? '-'}', flex: 2),
      AppTableCell(
        flex: 2,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: (disetujui ? Colors.green : Colors.orange)
                    .withValues(alpha: .15),
                borderRadius: BorderRadius.circular(20)),
            child: Text('${row['status'] ?? ''}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: disetujui
                        ? Colors.green.shade800
                        : Colors.orange.shade900)),
          ),
        ),
      ),
    ]);
  }

  AppTableRowData _barisBelum(Map<String, dynamic> row) {
    final terlambat = row['terlambat'] == true;
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${row['po'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('umur ${row['umurHari'] ?? 0} hari',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
      ),
      AppTableCell.text('${row['penyedia'] ?? '-'}', flex: 3),
      AppTableCell.text('${row['barang'] ?? '-'}', flex: 3),
      AppTableCell.text(_angka(row['dipesan']), flex: 2, align: TextAlign.right),
      AppTableCell.text(_angka(row['diterima']), flex: 2, align: TextAlign.right),
      AppTableCell(
        flex: 2,
        child: Text(_angka(row['sisa']),
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF00695C))),
      ),
      AppTableCell.text(_fmtRp.format(row['nilaiSisa'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell(
        flex: 2,
        child: Text(
            '${row['kirimPalingLambat'] ?? ''}'.isEmpty
                ? '-'
                : '${row['kirimPalingLambat']}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: terlambat ? FontWeight.w700 : FontWeight.normal,
                color: terlambat ? Colors.red : null)),
      ),
    ]);
  }
}
