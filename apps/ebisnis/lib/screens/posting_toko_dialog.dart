import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../widgets/app_components.dart';
import '../widgets/filter_status_posting.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';
import 'posting_akun_perbaikan.dart';

/// Dialog posting jurnal untuk rantai pengadaan &rarr; pembayaran toko:
/// kulakan, pembayaran hutang supplier, penerimaan piutang customer, dan
/// penyesuaian persediaan (retur beli/jual, selisih opname, mutasi antar outlet).
///
/// Pola tampilannya menyusul Posting HPP/Penjualan yang sudah ada: draf jurnal
/// ditampilkan PER DOKUMEN lebih dulu lengkap dengan akun debet/kreditnya, baris
/// yang belum siap tetap terlihat beserta alasannya, dan posting bisa dilakukan
/// per baris atau sekaligus untuk yang sudah siap.
class PostingTokoDialog extends StatefulWidget {
  const PostingTokoDialog({
    super.key,
    required this.jenis,
    required this.judul,
    this.inline = false,
  });

  /// `kulakan` | `bayar_hutang` | `terima_piutang` | `penyesuaian`
  final String jenis;
  final String judul;

  /// true = ditampilkan sebagai panel di dalam tab (tanpa bungkus Dialog dan tanpa
  /// tombol Tutup, karena di dalam tab tombol itu akan menutup seluruh halaman).
  final bool inline;

  @override
  State<PostingTokoDialog> createState() => _PostingTokoDialogState();
}

class _PostingTokoDialogState extends State<PostingTokoDialog> with JejakGalat {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  late DateTime _mulai;
  DateTime _sampai = DateTime.now();
  bool _sibuk = false;
  String? _galat;
  Map<String, dynamic>? _data;
  FilterStatusPosting _filterStatus = FilterStatusPosting.semua;

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _mulai = DateTime(kini.year, kini.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatDraf());
  }

  List<Map<String, dynamic>> get _rincianDraf =>
      ((_data?['rincian'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> get _rincianSemua => rincianPostingSemua(_data);

  Future<void> _pilihTanggal(bool awal) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: awal ? _mulai : _sampai,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() {
      if (awal) {
        _mulai = hasil;
      } else {
        _sampai = hasil;
      }
      _data = null;
    });
    await _muatDraf();
  }

  Future<void> _muatDraf() async {
    setStateIfMounted(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'posting_${widget.jenis}_draft',
        {
          'mulai': _fmt.format(_mulai),
          'sampai': _fmt.format(_sampai),
          'batasRiwayat': 1000,
        },
      );
      if (!mounted) return;
      final hakBaru = hasil['hak'];
      setStateIfMounted(() {
        // Balasan DRAF membawa hak menerapkannya; tombol Posting baru muncul
        // sesudah draf tampil, jadi haknya selalu sudah diketahui saat
        // tombolnya dirender.
        if (hakBaru is Map) {
          _bolehTerapkan = hakBaru['create'] != false;
        }
        _data = Map<String, dynamic>.from(hasil);
      });
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Hak MENERAPKAN posting, dari balasan draf. Bawaannya true: selama draf belum
  /// dimuat tidak ada tombol Posting yang dirender, jadi tidak ada yang perlu
  /// dipadamkan -- dan peladen tetap gerbang sebenarnya.
  bool _bolehTerapkan = true;

  /// [ids] kosong berarti "semua yang siap".
  Future<void> _posting(List<dynamic> ids) async {
    final satu = ids.length == 1;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(satu ? 'Posting dokumen ini?' : 'Posting semua yang siap?'),
        content: Text(satu
            ? 'Dokumen ini akan dijurnal tersendiri. Dokumen lain yang akunnya '
                'belum lengkap tidak ikut terhalang.'
            : 'Semua dokumen berstatus SIAP pada periode ini akan dijurnal. '
                'Dokumen yang belum siap dilewati.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Posting')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setStateIfMounted(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final body = <String, dynamic>{
        'mulai': _fmt.format(_mulai),
        'sampai': _fmt.format(_sampai),
      };
      if (ids.isNotEmpty) body['posting_ids'] = ids;
      final hasil = await ApiClient.instance
          .aksi('posting_${widget.jenis}_terapkan', body);
      if (!mounted) return;
      final masalah =
          ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${hasil['diposting'] ?? 0} jurnal terbentuk'
              '${masalah.isEmpty ? '.' : ', ${masalah.length} gagal: ${masalah.first}'}')));
      await _muatDraf();
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Widget _diagnostikSetting(List<Map<String, dynamic>> rincian) {
    final alasan = rincian
        .where((r) => r['siap'] != true)
        .map((r) => '${r['referensi'] ?? r['id'] ?? 'Dokumen'} — '
            '${r['alasan'] ?? 'Setting akun belum lengkap.'}')
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (alasan.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.settings_suggest_outlined,
            color: Color(0xFFB45309)),
        title: Text('${alasan.length} dokumen memerlukan perbaikan setting'),
        subtitle: Text(alasan.first),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < alasan.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText('${i + 1}. ${alasan[i]}'),
            ),
          const Text(
            'Lengkapi master/akun yang disebutkan, simpan, lalu klik Muat ulang. '
            'Dokumen lain yang sudah siap tetap dapat diposting.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rincian = _rincianDraf;
    final semua = _rincianSemua;
    final rincianTerfilter = filterRincianPosting(semua, _filterStatus);
    final jumlahSudah = semua.where((r) => r['sudahDiposting'] == true).length;
    final jumlahBelum = semua.length - jumlahSudah;
    final siap = rincian.where((r) => r['siap'] == true).toList();
    final Widget isi = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(widget.judul,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700))),
            if (!widget.inline)
              IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 4),
          Text(
              '${_data?['message'] ?? 'Menyiapkan draf jurnal...'}'
              '  •  Draf hanya menghitung; jurnal baru ditulis saat tombol Posting ditekan.',
              style: Theme.of(context).textTheme.bodySmall),
          PenjelasanSumberAkunPosting(jenis: widget.jenis),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _sibuk ? null : () => _pilihTanggal(true),
                icon: const Icon(Icons.event, size: 18),
                label: Text('Mulai ${_fmt.format(_mulai)}')),
            OutlinedButton.icon(
                onPressed: _sibuk ? null : () => _pilihTanggal(false),
                icon: const Icon(Icons.event_available, size: 18),
                label: Text('Sampai ${_fmt.format(_sampai)}')),
            OutlinedButton.icon(
                onPressed: _sibuk ? null : _muatDraf,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat ulang')),
            TombolSesuaikanAkunPosting(
                jenis: widget.jenis,
                sisi: SisiAkunPosting.debet,
                onSelesai: _muatDraf),
            TombolSesuaikanAkunPosting(
                jenis: widget.jenis,
                sisi: SisiAkunPosting.kredit,
                onSelesai: _muatDraf),
            FilledButton.icon(
                onPressed: _sibuk || siap.isEmpty || !_bolehTerapkan
                    ? null
                    : () => _posting(const []),
                icon: const Icon(Icons.post_add, size: 18),
                label: Text('Posting semua yang siap (${siap.length})')),
            if (_sibuk)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (_galat != null) ...[
            const SizedBox(height: 8),
            Text(_galat!, style: const TextStyle(color: Colors.red)),
            AppDetailGalatOpsional(detail: detailUntuk(_galat)),
          ],
          const SizedBox(height: 12),
          _diagnostikSetting(rincian),
          if (_data != null) ...[
            FilterStatusPostingBar(
              nilai: _filterStatus,
              jumlahSemua: semua.length,
              jumlahSudah: jumlahSudah,
              jumlahBelum: jumlahBelum,
              onChanged: (nilai) =>
                  setStateIfMounted(() => _filterStatus = nilai),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: rincianTerfilter.isEmpty
                ? Center(
                    child: Text(_sibuk
                        ? 'Menghitung...'
                        : 'Tidak ada dokumen untuk filter yang dipilih.'))
                : AppDataTable(
                    minWidth: 1160,
                    emptyText: 'Tidak ada draf.',
                    columns: const [
                      AppTableColumn('Tanggal', flex: 2),
                      AppTableColumn('Referensi', flex: 3),
                      AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                      AppTableColumn('Debet', flex: 4),
                      AppTableColumn('Kredit', flex: 4),
                      AppTableColumn('Status', flex: 4),
                      AppTableColumn('Aksi', flex: 4),
                    ],
                    rows: rincianTerfilter.map((r) {
                      final sudahDiposting = r['sudahDiposting'] == true;
                      final bisa = !sudahDiposting && r['siap'] == true;
                      final status =
                          '${r['statusLabel'] ?? (bisa ? 'Belum Diposting - Siap' : 'Belum Diposting - Tertahan')}';
                      return AppTableRowData(cells: [
                        AppTableCell.text('${r['tanggal'] ?? ''}', flex: 2),
                        AppTableCell.text('${r['referensi'] ?? ''}', flex: 3),
                        AppTableCell.text(
                            _uang.format((r['nilai'] as num?)?.toDouble() ?? 0),
                            flex: 2,
                            align: TextAlign.right),
                        AppTableCell.text('${r['debet'] ?? ''}', flex: 4),
                        AppTableCell.text('${r['kredit'] ?? ''}', flex: 4),
                        AppTableCell.text(
                            sudahDiposting
                                ? '$status${'${r['nomorJurnal'] ?? ''}'.isEmpty ? '' : ' • Jurnal ${r['nomorJurnal']}'}'
                                : bisa
                                    ? status
                                    : '$status${'${r['alasan'] ?? ''}'.isEmpty ? '' : ' — ${r['alasan']}'}',
                            flex: 4),
                        AppTableCell(
                          flex: 4,
                          child: sudahDiposting
                              ? const Text('Tercatat di buku besar',
                                  style: TextStyle(
                                      color: Color(0xFF15803D),
                                      fontWeight: FontWeight.w600))
                              : bisa
                                  ? TextButton(
                                      onPressed: _sibuk || !_bolehTerapkan
                                          ? null
                                          : () => _posting([r['id']]),
                                      child: const Text('Posting'))
                                  : Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        TombolSesuaikanAkunPosting(
                                          jenis: widget.jenis,
                                          sisi: SisiAkunPosting.debet,
                                          alasan: '${r['alasan'] ?? ''}',
                                          ringkas: true,
                                          onSelesai: _muatDraf,
                                        ),
                                        TombolSesuaikanAkunPosting(
                                          jenis: widget.jenis,
                                          sisi: SisiAkunPosting.kredit,
                                          alasan: '${r['alasan'] ?? ''}',
                                          ringkas: true,
                                          onSelesai: _muatDraf,
                                        ),
                                      ],
                                    ),
                        ),
                      ]);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
    if (widget.inline) {
      return isi;
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: isi,
      ),
    );
  }
}
