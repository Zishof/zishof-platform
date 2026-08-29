import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/riwayat_data_dialog.dart';

/// Riwayat lintas-produk dari tabel audit Envers server.
///
/// Daftar ini sengaja online-only: audit tidak disalin ke SQLite agar jejak
/// forensik tidak terpecah menjadi beberapa sumber kebenaran. Ketuk satu revisi
/// untuk melihat field bisnis, jenis datanya, serta nilai lama -> nilai baru.
class ProdukRiwayatPerubahanTab extends StatefulWidget {
  const ProdukRiwayatPerubahanTab({super.key});

  @override
  State<ProdukRiwayatPerubahanTab> createState() =>
      _ProdukRiwayatPerubahanTabState();
}

class _ProdukRiwayatPerubahanTabState extends State<ProdukRiwayatPerubahanTab> {
  static final _formatApi = DateFormat('yyyy-MM-dd');
  static final _formatTanggal = DateFormat('dd/MM/yyyy');
  final _cari = TextEditingController();

  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();
  String _tipe = 'SEMUA';
  List<Map<String, dynamic>> _rows = const [];
  bool _memuat = true;
  bool _adaLagi = false;
  String? _galat;

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

  Future<void> _muat({bool lanjut = false}) async {
    if (mounted) {
      setState(() {
        _memuat = true;
        _galat = null;
        if (!lanjut) _rows = const [];
      });
    }
    try {
      final kata = _cari.text.trim();
      final res = await ApiClient.instance.aksi('revisi_jelajah', {
        'entitas': 'produk',
        'dari': _formatApi.format(_dari),
        'sampai': _formatApi.format(_sampai),
        'tipe': _tipe,
        if (Sesi.instance.tokoFilter != null) 'toko': Sesi.instance.tokoFilter,
        if (kata.isNotEmpty) 'kataKunci': kata,
        'batas': 100,
        'mulai': lanjut ? _rows.length : 0,
      });
      if (!ApiClient.statusResponsSukses(res['status'])) {
        throw Exception(res['description'] ?? 'Riwayat ditolak server.');
      }
      final tambahan = ((res['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _rows = lanjut ? [..._rows, ...tambahan] : tambahan;
        _adaLagi = res['adaLagi'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e'
            .replaceFirst('Exception: ', '')
            .replaceFirst('ApiException: ', '');
      });
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _pilihTanggal(bool awal) async {
    final dipilih = await showDatePicker(
      context: context,
      initialDate: awal ? _dari : _sampai,
      firstDate: DateTime(DateTime.now().year - 8),
      lastDate: DateTime.now(),
      helpText: awal ? 'Riwayat produk sejak' : 'Riwayat produk sampai',
    );
    if (dipilih == null || !mounted) return;
    setState(() {
      if (awal) {
        _dari = dipilih;
        if (_dari.isAfter(_sampai)) _sampai = dipilih;
      } else {
        _sampai = dipilih;
        if (_sampai.isBefore(_dari)) _dari = dipilih;
      }
    });
  }

  Color _warna(String tipe) {
    if (tipe == 'TAMBAH') return AppColors.success;
    if (tipe == 'HAPUS') return AppColors.danger;
    return AppColors.warning;
  }

  IconData _ikon(String tipe) {
    if (tipe == 'TAMBAH') return Icons.add_circle_outline;
    if (tipe == 'HAPUS') return Icons.delete_outline;
    return Icons.edit_outlined;
  }

  Widget _filter() => Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _memuat ? null : () => _pilihTanggal(true),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('Dari ${_formatTanggal.format(_dari)}'),
          ),
          OutlinedButton.icon(
            onPressed: _memuat ? null : () => _pilihTanggal(false),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: Text('Sampai ${_formatTanggal.format(_sampai)}'),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              value: _tipe,
              decoration: const InputDecoration(
                labelText: 'Jenis perubahan',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'SEMUA', child: Text('Semua')),
                DropdownMenuItem(value: 'TAMBAH', child: Text('Ditambah')),
                DropdownMenuItem(value: 'UBAH', child: Text('Diubah')),
                DropdownMenuItem(value: 'HAPUS', child: Text('Dihapus')),
              ],
              onChanged:
                  _memuat ? null : (v) => setState(() => _tipe = v ?? 'SEMUA'),
            ),
          ),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _cari,
              enabled: !_memuat,
              decoration: const InputDecoration(
                labelText: 'Cari kode/nama/barcode/pelaku',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _muat(),
            ),
          ),
          FilledButton.icon(
            onPressed: _memuat ? null : _muat,
            icon: const Icon(Icons.manage_search_outlined),
            label: const Text('Tampilkan'),
          ),
        ],
      );

  Widget _baris(Map<String, dynamic> row) {
    final ringkas = row['ringkas'] is Map
        ? Map<String, dynamic>.from(row['ringkas'] as Map)
        : <String, dynamic>{};
    final id = row['id'];
    final tipe = '${row['tipe'] ?? 'UBAH'}';
    final nama = '${ringkas['nama'] ?? 'Produk #${id ?? '-'}'}';
    final kode = '${ringkas['kode'] ?? '-'}';
    final barcode = '${ringkas['barcode'] ?? ''}'.trim();
    final oleh = '${ringkas['oleh'] ?? ''}'.trim();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        onTap: id == null
            ? null
            : () => tampilkanRiwayatData(
                  context,
                  entitas: 'produk',
                  id: id,
                  judul: nama,
                ),
        leading: CircleAvatar(
          backgroundColor: _warna(tipe).withValues(alpha: .12),
          foregroundColor: _warna(tipe),
          child: Icon(_ikon(tipe), size: 20),
        ),
        title: Text(nama, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '$tipe · ${row['tanggal'] ?? '-'} · revisi ${row['rev'] ?? '-'}\n'
          'Kode $kode${barcode.isEmpty ? '' : ' · Barcode $barcode'}'
          '${oleh.isEmpty ? '' : ' · oleh $oleh'}\n'
          'Klik untuk melihat jenis data serta nilai lama → nilai baru.',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Riwayat ini dibaca langsung dari tabel audit server. Setiap '
              'revisi menjelaskan data apa yang berubah, jenis datanya, nilai '
              'sebelum, nilai sesudah, waktu, dan pelakunya. Data audit tidak '
              'dapat diubah dari halaman ini.',
            ),
          ),
          const SizedBox(height: 12),
          _filter(),
          const SizedBox(height: 12),
          if (_memuat && _rows.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_galat != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 42, color: AppColors.danger),
                    const SizedBox(height: 8),
                    Text(_galat!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _muat,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                  child: Text('Belum ada perubahan produk pada rentang ini.')),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  ..._rows.map(_baris),
                  if (_adaLagi)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _memuat ? null : () => _muat(lanjut: true),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Muat 100 riwayat berikutnya'),
                      ),
                    ),
                  if (_memuat)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
