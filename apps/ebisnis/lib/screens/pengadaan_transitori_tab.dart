import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';
import '../theme/app_colors.dart';
import '../widgets/aksi_baris_menu.dart';
import 'pengadaan_cetak_util.dart';

/// Tab Transitori pada layar Pembayaran Vendor.
///
/// <b>Apa itu transitori.</b> Pada pembayaran vendor, tiap baris tagihan boleh
/// ditandai TRANSFER atau TRANSITORI. Transfer berarti uangnya langsung menuju
/// rekening penyedia. Transitori berarti uangnya ditampung dahulu pada akun
/// perantara, dan pencairannya menyusul. Pilihan itu bukan penanda tampilan:
/// ia menentukan akun kredit jurnalnya di server.
///
/// <b>Apa itu realisasi.</b> Transitori yang menunggu dikumpulkan ke dalam satu
/// batch, lalu batch itu disetujui. Itulah realisasi, dan itulah yang dikerjakan
/// layar ini, sama seperti ProsesTransitori pada versi ZKoss.
///
/// <b>Realisasi BUKAN posting jurnal.</b> Keduanya memang dua langkah terpisah,
/// juga di ZKoss. Jurnalnya diterbitkan menyusul lewat layar Posting Proses
/// Transitori, yang membaca batch yang sudah disetujui, dan pembatalan posting
/// dikerjakan di sana pula. Layar ini sengaja tidak menerbitkan jurnal sendiri.
class PengadaanTransitoriTab extends StatefulWidget {
  const PengadaanTransitoriTab({super.key});

  @override
  State<PengadaanTransitoriTab> createState() => _PengadaanTransitoriTabState();
}

class _PengadaanTransitoriTabState extends State<PengadaanTransitoriTab> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  final _cari = TextEditingController();
  List<Map<String, dynamic>> _daftar = [];
  final Set<int> _terpilih = {};
  String _status = 'MENUNGGU';
  double _nilaiMenunggu = 0;
  bool _memuat = false;
  bool _mengirim = false;
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

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await ApiClient.instance.aksi('pengadaan_transitori_daftar', {
        'status': _status,
        'cari': _cari.text.trim(),
        'pageSize': 100,
      });
      final data = ((r['data'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setStateIfMounted(() {
        _daftar = data;
        _nilaiMenunggu = (r['nilaiMenunggu'] as num?)?.toDouble() ?? 0;
        // Pilihan dibuang setiap kali daftarnya dimuat ulang: baris yang sudah
        // tidak ada lagi tidak boleh ikut terkirim.
        _terpilih.removeWhere((id) => !data.any((d) => d['id'] == id));
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _realisasikan() async {
    if (_terpilih.isEmpty) return;
    final total = _daftar
        .where((d) => _terpilih.contains(d['id']))
        .fold<double>(
            0, (a, d) => a + ((d['nominal'] as num?)?.toDouble() ?? 0));
    final nama = TextEditingController(
        text: 'Realisasi transitori '
            '${DateFormat('dd-MM-yyyy').format(DateTime.now())}');
    final keterangan = TextEditingController();
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Realisasikan transitori?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              '${_terpilih.length} transitori senilai ${_fmtRp.format(total)} '
              'akan dikumpulkan menjadi satu batch dan disetujui.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
              controller: nama,
              decoration: const InputDecoration(
                  labelText: 'Nama batch', isDense: true)),
          const SizedBox(height: 8),
          TextField(
              controller: keterangan,
              decoration: const InputDecoration(
                  labelText: 'Keterangan', isDense: true)),
          const SizedBox(height: 10),
          const Text(
              'Jurnalnya belum terbit di langkah ini. Penerbitan jurnal '
              'dikerjakan lewat Posting Proses Transitori, sama seperti '
              'versi ZKoss.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Realisasikan')),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;
    setStateIfMounted(() => _mengirim = true);
    try {
      // LOKAL DULU: penandaan realisasi ditulis ke antrean sebelum menyentuh
      // jaringan. Jurnalnya sendiri tidak terbit di langkah ini, jadi yang
      // tertunda saat offline hanya penandaan batch-nya.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_transitori_realisasi',
        body: {
          'ids': _terpilih.toList(),
          'nama': nama.text.trim(),
          'keterangan': keterangan.text.trim(),
        },
        kunci: 'pengadaan_transitori:${_terpilih.join('-')}',
      );
      if (!mounted) return;
      final berhasil = r['offline'] == true ||
          r['status'] == '00' ||
          r['status'] == 'success';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['offline'] == true
              ? 'Tersimpan di perangkat, akan dikirim otomatis.'
              : '${r['description'] ?? (berhasil ? 'Transitori direalisasikan.' : 'Gagal merealisasikan.')}'),
          backgroundColor:
              berhasil ? null : Theme.of(context).colorScheme.error));
      if (berhasil) {
        _terpilih.clear();
        await _muat();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      setStateIfMounted(() => _mengirim = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolehPilih = _status == 'MENUNGGU';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _cari,
              onSubmitted: (_) => _muat(),
              decoration: InputDecoration(
                hintText: 'Cari kode pembayaran / uraian...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    onPressed: _muat),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              value: _status,
              isDense: true,
              decoration:
                  const InputDecoration(labelText: 'Status', isDense: true),
              items: const [
                DropdownMenuItem(value: 'MENUNGGU', child: Text('Menunggu')),
                DropdownMenuItem(
                    value: 'DIREALISASIKAN', child: Text('Direalisasikan')),
                DropdownMenuItem(value: '', child: Text('Semua')),
              ],
              onChanged: (v) {
                setStateIfMounted(() {
                  _status = v ?? 'MENUNGGU';
                  _terpilih.clear();
                });
                _muat();
              },
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _muat,
              tooltip: 'Muat ulang'),
        ]),
      ),
      if (_status == 'MENUNGGU' && _nilaiMenunggu > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
                'Menunggu realisasi: ${_fmtRp.format(_nilaiMenunggu)}. '
                'Selama belum direalisasikan, uangnya masih tercatat di akun '
                'perantara dan belum sampai ke penyedia.',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
      if (_terpilih.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Text('${_terpilih.length} dipilih',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
                onPressed: () => setStateIfMounted(_terpilih.clear),
                child: const Text('Bersihkan')),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('Realisasikan'),
              onPressed: _mengirim ? null : _realisasikan,
            ),
          ]),
        ),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(child: Text('Gagal memuat: $_galat'))
                : AppDataTable(
                    minWidth: 1000,
                    emptyText: _status == 'MENUNGGU'
                        ? 'Tidak ada transitori yang menunggu realisasi.'
                        : 'Tidak ada data pada filter ini.',
                    columns: [
                      if (bolehPilih) const AppTableColumn('', width: 44),
                      const AppTableColumn('Pembayaran', flex: 2),
                      const AppTableColumn('PO', flex: 2),
                      const AppTableColumn('Penyedia', flex: 2),
                      const AppTableColumn('Uraian', flex: 3),
                      const AppTableColumn('Nominal',
                          flex: 2, align: TextAlign.right),
                      const AppTableColumn('Status', flex: 2),
                      const AppTableColumn('Aksi', width: 64),
                    ],
                    rows: _daftar.map(_baris).toList(),
                  ),
      ),
    ]);
  }

  AppTableRowData _baris(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    final menunggu = '${row['status'] ?? ''}' == 'MENUNGGU';
    final bolehPilih = _status == 'MENUNGGU';
    // Hanya pembayaran yang SUDAH disetujui boleh direalisasikan; server
    // menolaknya juga, tetapi meredupkannya di sini menghemat satu percobaan.
    final siap = '${row['statusBayar'] ?? ''}' == 'DISETUJUI';
    return AppTableRowData(cells: [
      if (bolehPilih)
        AppTableCell(
          width: 44,
          child: Checkbox(
            value: _terpilih.contains(id),
            onChanged: (!menunggu || !siap)
                ? null
                : (v) => setStateIfMounted(() {
                      if (v == true) {
                        _terpilih.add(id);
                      } else {
                        _terpilih.remove(id);
                      }
                    }),
          ),
        ),
      AppTableCell(
        flex: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${row['bayarKode'] ?? '-'}',
                  style: const TextStyle(fontSize: 12)),
              Text(
                  '${row['tanggalBayar'] ?? ''}'
                  '${'${row['caraBayar'] ?? ''}'.isEmpty ? '' : ' · ${row['caraBayar']}'}',
                  style: const TextStyle(fontSize: 10)),
            ]),
      ),
      AppTableCell.text('${row['po'] ?? '-'}', flex: 2),
      AppTableCell.text('${row['penyedia'] ?? '-'}', flex: 2),
      AppTableCell.text('${row['nama'] ?? '-'}', flex: 3),
      AppTableCell.text(
          _fmtRp.format((row['nominal'] as num?)?.toDouble() ?? 0),
          flex: 2,
          align: TextAlign.right),
      AppTableCell(
        flex: 2,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: (menunggu ? AppColors.warning : AppColors.success)
                        .withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(menunggu ? 'Menunggu' : 'Direalisasikan',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            menunggu ? AppColors.warning : AppColors.success)),
              ),
              if (!menunggu)
                Text(
                    '${row['tanggalRealisasi'] ?? ''}'
                    '${'${row['direalisasikanOleh'] ?? ''}'.isEmpty ? '' : ' · ${row['direalisasikanOleh']}'}',
                    style: const TextStyle(fontSize: 10)),
              if (menunggu && !siap)
                Text('pembayaran belum disetujui',
                    style: TextStyle(fontSize: 10, color: AppColors.danger)),
              if (!menunggu && row['sudahDiposting'] == true)
                const Text('jurnal sudah diposting',
                    style: TextStyle(fontSize: 10)),
            ]),
      ),
      /* Yang dicetak adalah DOKUMEN PEMBAYARAN-nya, bukan transitorinya sendiri.
       * Transitori bukan dokumen berdiri sendiri melainkan satu baris pada
       * pembayaran vendor, dan templat cetaknya sama dengan versi ZKoss. */
      AppTableCell(
        width: 64,
        child: AksiBarisMenu(aksi: [
          AksiBaris(
              ikon: Icons.print_outlined,
              label: 'Cetak / pratinjau pembayaran',
              onTap: row['bayar_id'] == null
                  ? null
                  : () => cetakDokumenPengadaan(context,
                      tahap: 'dpc',
                      id: (row['bayar_id'] as num).toInt(),
                      kode: '${row['bayarKode'] ?? ''}')),
        ]),
      ),
    ]);
  }
}
