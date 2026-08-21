import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/master_offline.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/safe_state.dart';

/// Tab "Dasbor" untuk seluruh menu Pengadaan.
///
/// Satu widget melayani enam tahap (PR, PO, BAST, Terima Tagihan, Pembayaran
/// Vendor, Bayar Pajak) karena aksi server `pengadaan_dasbor` mengembalikan
/// bentuk yang SERAGAM: `kpi`, `tren`, `komposisi`, `peringkat`, `daftar`, dan
/// -- khusus PR -- `corong` tahapan PR sampai Bayar.
///
/// Susunannya meniru dasbor yang sudah ada di versi ZKoss:
/// `TraceStatusPengadaanAssetDashboard` (kartu ringkasan tahapan + tabel proses)
/// dan `DasboardPajak` (kartu + tren bulanan + komposisi jenis pajak).
///
/// Sisi baca memakai [MasterOffline.daftarCacheDulu] sehingga dasbor tetap
/// menampilkan angka terakhir yang pernah diterima ketika sinyal buruk.
class PengadaanDasborTab extends StatefulWidget {
  /// pr, po, bast, tagihan, dpc, atau pajak. Untuk grup menu lain yang memakai
  /// bentuk balasan yang sama, ini adalah nilai parameternya (lihat [namaParam]).
  final String tahap;

  /// Aksi server penghasil dasbor. Grup "Keuangan" memakai `keuangan_dasbor`
  /// dengan bentuk balasan yang SAMA (kpi/tren/komposisi/peringkat/daftar),
  /// sehingga widget ini dipakai ulang alih-alih diduplikasi.
  final String aksi;

  /// Nama parameter pembawa [tahap] pada permintaan: `tahap` (Pengadaan) atau
  /// `modul` (Keuangan).
  final String namaParam;

  const PengadaanDasborTab({
    super.key,
    required this.tahap,
    this.aksi = 'pengadaan_dasbor',
    this.namaParam = 'tahap',
  });

  @override
  State<PengadaanDasborTab> createState() => _PengadaanDasborTabState();
}

class _PengadaanDasborTabState extends State<PengadaanDasborTab> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _galat;
  Map<String, dynamic>? _d;
  int _bulan = 12;

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
        widget.aksi,
        {widget.namaParam: widget.tahap, 'bulan': _bulan},
        'master:${widget.aksi}:${widget.tahap}:$_bulan',
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          setStateIfMounted(() {
            if (sukses) {
              _d = Map<String, dynamic>.from(res);
            } else {
              _galat = '${res['description'] ?? 'Gagal memuat dasbor.'}';
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

  List<Map<String, dynamic>> _list(String kunci) =>
      ((_d?[kunci] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<TitikChart> _titik(String kunci) => _list(kunci)
      .map((m) => (
            label: '${m['label'] ?? ''}',
            nilai: (m['nilai'] as num?)?.toDouble() ?? 0
          ))
      .toList();

  Color _warna(String? hex) {
    final v = (hex ?? '').replaceAll('#', '');
    if (v.length != 6) return const Color(0xFF1E3A5F);
    return Color(int.parse('FF$v', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _galat != null) {
      return statusMuatDasbor(memuat: _memuat, error: _galat, onCoba: _muat);
    }
    final d = _d ?? const {};
    final kpi = _list('kpi');
    final tren = _list('tren');
    final corong = _list('corong');
    final komposisi = _titik('komposisi');
    final peringkat = _titik('peringkat');
    final caraBayar = _titik('caraBayar');
    final daftar = _list('daftar');
    final kosong = kpi.isEmpty && tren.isEmpty && daftar.isEmpty;

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          Row(children: [
            Expanded(
              child: Text('Periode $_bulan bulan terakhir',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            DropdownButton<int>(
              value: _bulan,
              underline: const SizedBox.shrink(),
              items: const [3, 6, 12, 24]
                  .map((b) => DropdownMenuItem<int>(
                      value: b, child: Text('$b bulan')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setStateIfMounted(() => _bulan = v);
                _muat();
              },
            ),
          ]),
          const SizedBox(height: 10),
          if (kosong)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: Text(
                      '${d['catatanKosong'] ?? 'Belum ada data pada periode ini.'}',
                      textAlign: TextAlign.center)),
            ),
          if (kpi.isNotEmpty)
            BarisKpi(
              kartu: kpi
                  .map((m) => KartuKpi(
                        label: '${m['label'] ?? ''}',
                        nilai: '${m['nilai'] ?? ''}',
                        warna: _warna('${m['warna'] ?? ''}'),
                      ))
                  .toList(),
            ),
          if (corong.isNotEmpty) ...[
            const SizedBox(height: 12),
            PanelChart(
              judul: 'Ringkasan Tahapan (PR sampai Bayar)',
              child: BarHorizontal(
                data: corong
                    .map((m) => (
                          label: '${m['label'] ?? ''}',
                          nilai: (m['nilai'] as num?)?.toDouble() ?? 0
                        ))
                    .toList(),
                formatNilai: (v) => v.toStringAsFixed(0),
              ),
            ),
          ],
          if (tren.isNotEmpty) ...[
            const SizedBox(height: 12),
            PanelChart(
              judul: '${d['trenJudul'] ?? 'Tren Nilai per Bulan'}',
              child: BarVertikal(
                data: tren
                    .map((m) => (
                          label: '${m['label'] ?? ''}',
                          nilai: (m['nilai'] as num?)?.toDouble() ?? 0
                        ))
                    .toList(),
                formatNilai: _fmtRp.format,
              ),
            ),
            const SizedBox(height: 12),
            PanelChart(
              judul: 'Jumlah Dokumen per Bulan',
              child: GarisTren(
                data: tren
                    .map((m) => (
                          label: '${m['label'] ?? ''}',
                          nilai: (m['jumlah'] as num?)?.toDouble() ?? 0
                        ))
                    .toList(),
              ),
            ),
          ],
          if (komposisi.isNotEmpty) ...[
            const SizedBox(height: 12),
            PanelChart(
              judul: '${d['komposisiJudul'] ?? 'Komposisi Status'}',
              child: StackProporsional(data: komposisi),
            ),
          ],
          if (peringkat.isNotEmpty) ...[
            const SizedBox(height: 12),
            PanelChart(
              judul: '${d['peringkatJudul'] ?? 'Peringkat'}',
              child: BarHorizontal(
                  data: peringkat,
                  tampilkanPeringkat: true,
                  formatNilai: _fmtRp.format),
            ),
          ],
          if (caraBayar.isNotEmpty) ...[
            const SizedBox(height: 12),
            PanelChart(
              judul: 'Komposisi Cara Transfer',
              child: StackProporsional(data: caraBayar),
            ),
          ],
          if (daftar.isNotEmpty) ...[
            const SizedBox(height: 12),
            _panelDaftar(d, daftar),
          ],
        ],
      ),
    );
  }

  /// Tabel pendukung "perlu perhatian" -- padanan Tabel Proses Pengajuan pada
  /// TraceStatusPengadaanAssetDashboard versi ZKoss.
  Widget _panelDaftar(Map d, List<Map<String, dynamic>> daftar) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${d['daftarJudul'] ?? 'Perlu Perhatian'}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ...daftar.map(_barisDaftar),
          ],
        ),
      ),
    );
  }

  Widget _barisDaftar(Map<String, dynamic> m) {
    final umur = (m['umurHari'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${m['kode'] ?? '-'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              if ('${m['keterangan'] ?? ''}'.isNotEmpty)
                Text('${m['keterangan']}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (umur > 0)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text('$umur hari',
                style: const TextStyle(fontSize: 11, color: Colors.orange)),
          ),
        Text(_fmtRp.format(m['nilai'] ?? 0),
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
