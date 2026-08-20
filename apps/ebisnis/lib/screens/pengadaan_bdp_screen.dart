import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/master_offline.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/safe_state.dart';

/// Layar "Barang Dalam Proses" -- tahap 6 modul Pengadaan POS.
///
/// Bukan dokumen tersendiri melainkan pandangan yang diturunkan dari selisih PO
/// dan BAST: barang yang sudah dipesan tetapi belum diterima. Angkanya memakai
/// definisi yang sama dengan pagar penerimaan, sehingga apa yang terlihat di sini
/// persis sama dengan sisa yang boleh diterima pada layar BAST.
class PengadaanBdpScreen extends StatefulWidget {
  const PengadaanBdpScreen({super.key});

  @override
  State<PengadaanBdpScreen> createState() => _PengadaanBdpScreenState();
}

class _PengadaanBdpScreenState extends State<PengadaanBdpScreen> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];
  String _cari = '';
  bool _hanyaTerlambat = false;
  int _halaman = 1;
  int _total = 0;
  double _totalNilai = 0;
  int _jumlahTerlambat = 0;
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
    try {
      await MasterOffline.daftarCacheDulu(
        'pengadaan_bdp_daftar',
        {
          if (_cari.isNotEmpty) 'cari': _cari,
          if (_hanyaTerlambat) 'hanyaTerlambat': true,
          'page': _halaman,
          'pageSize': _pageSize,
        },
        'master:pengadaan_bdp:${_hanyaTerlambat}_${_cari}_$_halaman',
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

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanBdp,
      judul: 'Barang Dalam Proses',
      subjudul: 'Barang yang sudah dipesan tetapi belum diterima',
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                    labelText: 'Cari kode PO / nama barang',
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
            child: Row(children: [
              _kotak('Baris', '$_total'),
              const SizedBox(width: 10),
              _kotak('Nilai belum datang', _fmtRp.format(_totalNilai)),
              const SizedBox(width: 10),
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
      return const Center(
        child: Text(
            'Tidak ada barang dalam proses.\nSeluruh pesanan yang disetujui '
            'sudah diterima.',
            textAlign: TextAlign.center),
      );
    }
    return AppDataTable(
      minWidth: 1120,
      emptyText: 'Tidak ada baris pada filter ini.',
      columns: const [
        AppTableColumn('PO', flex: 2),
        AppTableColumn('Penyedia', flex: 3),
        AppTableColumn('Barang', flex: 3),
        AppTableColumn('Dipesan', flex: 2, align: TextAlign.right),
        AppTableColumn('Diterima', flex: 2, align: TextAlign.right),
        AppTableColumn('Belum datang', flex: 2, align: TextAlign.right),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('Batas kirim', flex: 2),
      ],
      rows: _daftar.map(_baris).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: 'baris',
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

  AppTableRowData _baris(Map<String, dynamic> row) {
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
