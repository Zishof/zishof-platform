import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

const _periodeOpsi = ['harian', 'mingguan', 'bulanan', 'semester', 'tahunan'];

/// Tab 4/9 "Perilaku Pelanggan" -- aksi `dashboard_pelanggan` (param
/// `periode`). Jam sibuk (30 hari, di-bucket ulang jadi 24 jam penuh di sisi
/// klien -- server hanya kirim jam yg ada transaksinya) + 10 pembeli
/// terloyal (30 hari) + rekap pelanggan terloyal per periode terpilih.
class RingkasanTabPelanggan extends StatefulWidget {
  const RingkasanTabPelanggan({super.key});
  @override
  State<RingkasanTabPelanggan> createState() => _RingkasanTabPelangganState();
}

class _RingkasanTabPelangganState extends State<RingkasanTabPelanggan> with JejakGalat {
  static final _formatTanggalServer = DateFormat('yyyy-MM-dd');
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;
  String _periode = 'bulanan';
  DateTime _tanggalAcuan =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  bool get _acuanBukanHariIni {
    final n = DateTime.now();
    return _tanggalAcuan.year != n.year ||
        _tanggalAcuan.month != n.month ||
        _tanggalAcuan.day != n.day;
  }

  String get _sufiksAcuan => _acuanBukanHariIni
      ? ' • s.d. ${DateFormat('dd-MM-yyyy').format(_tanggalAcuan)}'
      : '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _pilihTanggalAcuan() async {
    final v = await showDatePicker(
      context: context,
      initialDate: _tanggalAcuan,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal acuan dashboard',
    );
    if (v == null || !mounted) return;
    setStateIfMounted(() => _tanggalAcuan = DateTime(v.year, v.month, v.day));
    await _muat();
  }

  Future<void> _muat() async {
    if (!mounted) return;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('dashboard_pelanggan', {
        'periode': _periode,
        'tanggalAcuan': _formatTanggalServer.format(_tanggalAcuan),
      });
      if (!mounted) return;
      setStateIfMounted(() => _d = hasil);
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null)
      return statusMuatDasbor(
          memuat: _memuat,
          error: _error,
          detail: detailUntuk(_error),
          onCoba: _muat);
    final d = _d!;
    final jamSibukMentah =
        ((d['jamSibuk'] as List?) ?? []).cast<Map<String, dynamic>>();
    final petaJam = {
      for (final e in jamSibukMentah)
        (e['jam'] as num).toInt(): (e['jumlah'] as num).toDouble()
    };
    final jamSibuk =
        List.generate(24, (jam) => (label: '$jam', nilai: petaJam[jam] ?? 0.0));
    final terloyal = titikDariList(d['pembeliTerloyal'] as List?,
        labelKey: 'nama', nilaiKey: 'total');
    final rekapTerloyal = ((d['rekapPelangganTerloyal'] as List?) ?? [])
        .cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Tanggal Acuan',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                onPressed: _memuat ? null : _pilihTanggalAcuan,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(_formatTanggalServer.format(_tanggalAcuan)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Jam Sibuk (30 hari)$_sufiksAcuan',
              child:
                  BarVertikal(data: jamSibuk, warna: const Color(0xFFB8860B))),
          const SizedBox(height: 12),
          PanelChart(
              judul: '10 Pembeli Terloyal (30 hari)$_sufiksAcuan',
              child: BarHorizontal(
                  data: terloyal, formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Rekap Pelanggan Terloyal$_sufiksAcuan',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      DropdownButton<String>(
                        value: _periode,
                        items: _periodeOpsi
                            .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p,
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setStateIfMounted(() => _periode = v);
                            _muat();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (rekapTerloyal.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Belum ada data.',
                        style: TextStyle(
                            color: AppColors.textSecondaryOf(context)),
                      ),
                    )
                  else
                    ...rekapTerloyal.take(30).map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text('${r['nama']}',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              Text('${r['frekuensi']}x',
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(formatRupiahDasbor.format(r['total'] ?? 0),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
