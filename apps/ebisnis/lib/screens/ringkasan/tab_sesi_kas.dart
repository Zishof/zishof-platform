import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

/// Riwayat buka/tutup kas (`laporan_sesi_list`) -- sesi yang SUDAH tercatat,
/// bukan angka kas berjalan. Memakai pola "baca lokal dulu"
/// ([MasterOffline.daftarCacheDulu]) sehingga riwayat yang pernah dibuka tetap
/// bisa dilihat saat OFFLINE, lengkap dgn kilau baris utk sesi baru/berubah.
class RingkasanTabSesiKas extends StatefulWidget {
  const RingkasanTabSesiKas({super.key});

  @override
  State<RingkasanTabSesiKas> createState() => _RingkasanTabSesiKasState();
}

class _RingkasanTabSesiKasState extends State<RingkasanTabSesiKas> with JejakGalat {
  static const _ukuran = 15;
  final _cari = TextEditingController();
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _tanggal = DateFormat('yyyy-MM-dd');
  DateTime? _mulai;
  DateTime? _sampai;
  Timer? _debounce;
  bool _memuat = true;
  bool _hanyaSaya = true;
  String? _error;
  int _halaman = 1;
  int _total = 0;
  List<Map<String, dynamic>> _data = [];

  /// Diff emisi "baca lokal dulu" -- menggerakkan kilau baris (sesi yang baru
  /// ditutup / dikoreksi oleh kasir lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot terakhir
      // tampil seketika sehingga riwayat sesi kas yang pernah dibuka tetap bisa
      // dilihat saat OFFLINE; hasil server menyusul + diff utk kilau baris.
      //
      // Kunci cache memuat SELURUH parameter yang mengubah isi laporan
      // (periode, lingkup kasir, kata kunci) -- salah kunci berarti hasil
      // filter A menimpa filter B. Nomor halaman TIDAK ikut: daftarCacheDulu
      // me-MERGE per baris sehingga halaman lain yang pernah diunduh tetap
      // tersimpan pada kunci yang sama.
      await MasterOffline.daftarCacheDulu(
        'laporan_sesi_list',
        {
          'page': _halaman,
          'pageSize': _ukuran,
          'hanyaKasirSaya': _hanyaSaya,
          'cariKasir': _cari.text.trim(),
          if (_mulai != null) 'tglMulai': _tanggal.format(_mulai!),
          if (_sampai != null) 'tglSampai': _tanggal.format(_sampai!),
        },
        'master:ringkasan_sesi_kas:'
        '${_mulai == null ? 'awal' : _tanggal.format(_mulai!)}_'
        '${_sampai == null ? 'kini' : _tanggal.format(_sampai!)}:'
        '${_hanyaSaya ? 'saya' : 'semua'}:'
        '${_cari.text.trim().isEmpty ? 'semua' : _cari.text.trim()}',
        // Server tidak mengirim kolom 'id' -- identitas baris = kode sesi.
        kolomKunci: 'sesiKode',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data = _diff.terapkan(hasil);
            // Total server hanya sahih pada emisi SERVER; emisi lokal jatuh ke
            // jumlah baris yang ada supaya paginasi tidak menampilkan nol.
            _total = _diff.total ?? _data.length;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  String _waktu(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return '-';
    try {
      return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  Future<void> _pilihTanggal(bool mulai) async {
    final awal = mulai ? _mulai : _sampai;
    final d = await showDatePicker(
        context: context,
        initialDate: awal ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return;
    setStateIfMounted(() {
      if (mulai) {
        _mulai = d;
      } else {
        _sampai = d;
      }
      _halaman = 1;
    });
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final halamanTotal = _total == 0 ? 1 : (_total + _ukuran - 1) ~/ _ukuran;
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 300,
                  child: TextField(
                      controller: _cari,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Cari kasir / perangkat'),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce =
                            Timer(const Duration(milliseconds: 400), () {
                          _halaman = 1;
                          _muat();
                        });
                      })),
              OutlinedButton.icon(
                  onPressed: () => _pilihTanggal(true),
                  icon: const Icon(Icons.date_range),
                  label: Text(_mulai == null
                      ? 'Dari Tanggal'
                      : _tanggal.format(_mulai!))),
              OutlinedButton.icon(
                  onPressed: () => _pilihTanggal(false),
                  icon: const Icon(Icons.event),
                  label: Text(_sampai == null
                      ? 'Sampai Tanggal'
                      : _tanggal.format(_sampai!))),
              FilterChip(
                  label: const Text('Hanya sesi saya'),
                  selected: _hanyaSaya,
                  onSelected: (v) {
                    setStateIfMounted(() {
                      _hanyaSaya = v;
                      _halaman = 1;
                    });
                    _muat();
                  }),
              IconButton(
                  onPressed: _muat,
                  tooltip: 'Muat ulang',
                  icon: const Icon(Icons.refresh)),
            ]),
        const SizedBox(height: 12),
        if (_memuat)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(36),
                  child: CircularProgressIndicator()))
        else if (_error != null)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red))))
        else
          AppDataTable(
            minWidth: 1180,
            emptyText: 'Belum ada riwayat buka/tutup kas.',
            columns: const [
              AppTableColumn('Kode', flex: 2),
              AppTableColumn('Kasir', flex: 2),
              AppTableColumn('Perangkat', flex: 2),
              AppTableColumn('Buka', flex: 2),
              AppTableColumn('Tutup', flex: 2),
              AppTableColumn('Modal', flex: 2, align: TextAlign.right),
              AppTableColumn('Tunai', flex: 2, align: TextAlign.right),
              AppTableColumn('Non Tunai', flex: 2, align: TextAlign.right),
              AppTableColumn('Kas Akhir', flex: 2, align: TextAlign.right),
              AppTableColumn('Selisih', flex: 2, align: TextAlign.right),
            ],
            rows: _data
                .map((r) => AppTableRowData(cells: [
                      AppTableCell(
                        flex: 2,
                        child: KilauBaris(
                          kunci: MasterOffline.kunciBaris(r, 'sesiKode'),
                          idBaru: _diff.idBaru,
                          idBerubah: _diff.idBerubah,
                          child: Text('${r['sesiKode'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      AppTableCell.text('${r['kasir'] ?? '-'}', flex: 2),
                      AppTableCell.text(
                          '${r['namaPerangkat']}'.trim().isEmpty
                              ? '-'
                              : '${r['namaPerangkat']}',
                          flex: 2),
                      AppTableCell.text(_waktu(r['waktuBuka']), flex: 2),
                      AppTableCell.text(_waktu(r['waktuTutup']), flex: 2),
                      AppTableCell.text(_rupiah.format(r['modalAwal'] ?? 0),
                          flex: 2, align: TextAlign.right),
                      AppTableCell.text(_rupiah.format(r['totalTunai'] ?? 0),
                          flex: 2, align: TextAlign.right),
                      AppTableCell.text(_rupiah.format(r['totalNonTunai'] ?? 0),
                          flex: 2, align: TextAlign.right),
                      AppTableCell.text(_rupiah.format(r['saldoAkhir'] ?? 0),
                          flex: 2, align: TextAlign.right),
                      AppTableCell.text(_rupiah.format(r['selisih'] ?? 0),
                          flex: 2,
                          align: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ((r['selisih'] as num?) ?? 0) < 0
                                  ? Colors.red
                                  : AppColors.success)),
                    ]))
                .toList(),
            pagination: _total > _ukuran
                ? AppTablePagination(
                    halaman: _halaman,
                    totalHalaman: halamanTotal,
                    totalData: _total,
                    labelData: 'sesi',
                    onSebelumnya: _halaman > 1
                        ? () {
                            setStateIfMounted(() => _halaman--);
                            _muat();
                          }
                        : null,
                    onBerikutnya: _halaman < halamanTotal
                        ? () {
                            setStateIfMounted(() => _halaman++);
                            _muat();
                          }
                        : null)
                : null,
          ),
      ]),
    );
  }
}
