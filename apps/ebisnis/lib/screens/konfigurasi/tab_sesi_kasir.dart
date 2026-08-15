import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

/// Riwayat sesi kas seluruh kasir pada toko aktif. Kasir hanya membaca,
/// sedangkan supervisor/admin dapat melakukan koreksi berjejak audit.
class TabSesiKasir extends StatefulWidget {
  const TabSesiKasir({super.key});

  @override
  State<TabSesiKasir> createState() => _TabSesiKasirState();
}

class _TabSesiKasirState extends State<TabSesiKasir> {
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  String _filter = 'SEMUA';

  bool get _bolehKoreksi => Sesi.instance.bolehKelola;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  double _angka(dynamic nilai) => nilai is num
      ? nilai.toDouble()
      : double.tryParse('$nilai'.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_list', {
        if (Sesi.instance.tokoId != null) 'id_toko': Sesi.instance.tokoId,
      });
      setStateIfMounted(() {
        _data = ((hasil['sesi'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _error = e.toString();
        _memuat = false;
      });
    }
  }

  Future<void> _koreksi(Map<String, dynamic> row) async {
    var status = '${row['statusSesi']}' == 'TUTUP' ? 'TUTUP' : 'BUKA';
    final modal = TextEditingController(
        text: _angka(row['modalAwal']).toStringAsFixed(0));
    final tunai = TextEditingController(
        text: _angka(row['penjualanTunai']).toStringAsFixed(0));
    final fisik = TextEditingController(
        text: _angka(row['uangFisik'] ?? row['kasSeharusnya'])
            .toStringAsFixed(0));
    final alasan = TextEditingController();
    try {
      final simpan = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Koreksi Sesi ${row['kasirNama']}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppInfoBanner(
                      icon: Icons.admin_panel_settings_outlined,
                      color: AppColors.warning,
                      text:
                          'Perubahan status dan nominal dicatat sebagai koreksi supervisor. Membuka kembali sesi ditolak bila kasir atau perangkat memiliki sesi aktif lain.',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(
                          labelText: 'Status sesi',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'BUKA', child: Text('BUKA')),
                        DropdownMenuItem(value: 'TUTUP', child: Text('TUTUP')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => status = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Modal awal (Rp)',
                          border: OutlineInputBorder()),
                    ),
                    if (status == 'TUTUP') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tunai,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Penjualan tunai hasil koreksi (Rp)',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: fisik,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Uang fisik (Rp)',
                            border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: alasan,
                      maxLength: 200,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Alasan koreksi supervisor *',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Simpan Koreksi')),
            ],
          ),
        ),
      );
      if (simpan != true) return;
      if (alasan.text.trim().length < 5) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Alasan koreksi wajib minimal 5 karakter.')));
        return;
      }
      final modalNilai = double.tryParse(modal.text.trim());
      final tunaiNilai = double.tryParse(tunai.text.trim());
      final fisikNilai = double.tryParse(fisik.text.trim());
      if (modalNilai == null ||
          modalNilai < 0 ||
          (status == 'TUTUP' &&
              (tunaiNilai == null ||
                  tunaiNilai < 0 ||
                  fisikNilai == null ||
                  fisikNilai < 0))) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Seluruh nominal harus berupa angka nol atau lebih.')));
        return;
      }
      await ApiClient.instance.aksi('sesi_kas_koreksi', {
        'id_sesi': row['id'],
        'status_sesi': status,
        'modal_awal': modalNilai,
        'penjualan_tunai': tunaiNilai ?? 0,
        'uang_fisik': fisikNilai ?? 0,
        'alasan_koreksi': alasan.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koreksi sesi kas berhasil disimpan.')));
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      modal.dispose();
      tunai.dispose();
      fisik.dispose();
      alasan.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tampil = _filter == 'SEMUA'
        ? _data
        : _data.where((e) => '${e['statusSesi']}' == _filter).toList();
    final terbuka = _data.where((e) => '${e['statusSesi']}' == 'BUKA').length;
    final totalTunai = _data.fold<double>(
        0, (jumlah, e) => jumlah + _angka(e['penjualanTunai']));
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppFormSection(
            judul: 'Sesi Kasir',
            deskripsi:
                'Sesi buka dan tutup pada ${Sesi.instance.tokoNama}. Tarik ke bawah atau tekan Muat Ulang untuk menyegarkan nominal.',
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text('$terbuka sesi masih terbuka')),
                  Chip(label: Text('${_data.length} sesi ditampilkan')),
                  Chip(label: Text('Tunai ${_rupiah.format(totalTunai)}')),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'SEMUA', label: Text('Semua')),
                      ButtonSegment(value: 'BUKA', label: Text('Buka')),
                      ButtonSegment(value: 'TUTUP', label: Text('Tutup')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) =>
                        setStateIfMounted(() => _filter = v.first),
                  ),
                  OutlinedButton.icon(
                      onPressed: _memuat ? null : _muat,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Muat Ulang')),
                ],
              ),
              if (!_bolehKoreksi) ...[
                const SizedBox(height: 10),
                const Text(
                    'Mode lihat saja. Hanya supervisor/admin yang dapat mengoreksi status dan nominal sesi.'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _error!)
          else if (tampil.isEmpty)
            const Padding(
                padding: EdgeInsets.all(40),
                child:
                    Center(child: Text('Belum ada sesi kas pada filter ini.')))
          else
            for (final row in tampil)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            '${row['statusSesi']}' == 'BUKA'
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                            color: '${row['statusSesi']}' == 'BUKA'
                                ? AppColors.success
                                : AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                '${row['kasirNama']} (${row['kasirUserId']})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16))),
                        Chip(label: Text('${row['statusSesi']}')),
                        if (_bolehKoreksi)
                          IconButton(
                              onPressed: () => _koreksi(row),
                              tooltip: 'Koreksi supervisor',
                              icon: const Icon(Icons.edit_outlined)),
                      ]),
                      Text(
                          '${row['waktuBuka']} — ${row['waktuTutup'] ?? 'masih berjalan'} · ${row['perangkat']}'),
                      const SizedBox(height: 10),
                      Wrap(spacing: 22, runSpacing: 8, children: [
                        _NilaiSesi(
                            label: 'Modal awal',
                            nilai: _rupiah.format(_angka(row['modalAwal']))),
                        _NilaiSesi(
                            label: 'Penjualan tunai',
                            nilai:
                                _rupiah.format(_angka(row['penjualanTunai']))),
                        _NilaiSesi(
                            label: 'Non-tunai',
                            nilai: _rupiah
                                .format(_angka(row['penjualanNonTunai']))),
                        _NilaiSesi(
                            label: 'Kas seharusnya',
                            nilai:
                                _rupiah.format(_angka(row['kasSeharusnya']))),
                        if ('${row['statusSesi']}' == 'TUTUP')
                          _NilaiSesi(
                              label: 'Uang fisik',
                              nilai: _rupiah.format(_angka(row['uangFisik']))),
                        _NilaiSesi(
                            label: 'Transaksi',
                            nilai: '${row['jumlahTransaksi']} trx'),
                      ]),
                      if ('${row['keterangan'] ?? ''}'.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('${row['keterangan']}',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryOf(context))),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _NilaiSesi extends StatelessWidget {
  final String label;
  final String nilai;
  const _NilaiSesi({required this.label, required this.nilai});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context))),
            Text(nilai, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
