import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';

/// Jalankan+tampilkan SATU laporan dari katalog (spec §Laporan-Laporan) --
/// form filter dibangun murni dari metadata katalog (`produk`/`pelanggan`/
/// `perToko` flags), TIDAK ada satu pun kode khusus per-laporan di sini.
/// Kontrak `laporan_jalankan`/`laporan_pdf` (r/tglMulai/tglSampai/qProduk/
/// qPelanggan/perToko -> kolom+baris+grup+grandTotal) generik utk ~150
/// laporan sekaligus -- lihat JavaDoc PosApi.prosesLaporanJalankan di server.
class LaporanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const LaporanDetailScreen({super.key, required this.item});

  @override
  State<LaporanDetailScreen> createState() => _LaporanDetailScreenState();
}

class _LaporanDetailScreenState extends State<LaporanDetailScreen> {
  final _formatTgl = DateFormat('yyyy-MM-dd');
  DateTime? _tglMulai;
  DateTime? _tglSampai;
  final _controllerProduk = TextEditingController();
  final _controllerPelanggan = TextEditingController();
  bool _perToko = false;

  bool _memuat = false;
  bool _memprosesPdf = false;
  String? _pesanError;
  Map<String, dynamic>? _hasil;

  bool get _adaFilterProduk => widget.item['produk'] == true;
  bool get _adaFilterPelanggan => widget.item['pelanggan'] == true;
  bool get _adaFilterPerToko => widget.item['perToko'] == true;

  @override
  void initState() {
    super.initState();
    final sekarang = DateTime.now();
    _tglMulai = DateTime(sekarang.year, sekarang.month, 1);
    _tglSampai = sekarang;
  }

  @override
  void dispose() {
    _controllerProduk.dispose();
    _controllerPelanggan.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buatPayload() {
    return {
      'r': widget.item['id'],
      if (_tglMulai != null) 'tglMulai': _formatTgl.format(_tglMulai!),
      if (_tglSampai != null) 'tglSampai': _formatTgl.format(_tglSampai!),
      if (_adaFilterProduk && _controllerProduk.text.trim().isNotEmpty) 'qProduk': _controllerProduk.text.trim(),
      if (_adaFilterPelanggan && _controllerPelanggan.text.trim().isNotEmpty) 'qPelanggan': _controllerPelanggan.text.trim(),
      if (_adaFilterPerToko && _perToko) 'perToko': 'true',
    };
  }

  Future<void> _tampilkan() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_jalankan', _buatPayload());
      setState(() => _hasil = hasil);
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _cetakPdf() async {
    setState(() => _memprosesPdf = true);
    try {
      final hasil = await ApiClient.instance.aksi('laporan_pdf', _buatPayload());
      final b64 = hasil['pdfBase64'] as String?;
      if (b64 == null || b64.isEmpty) throw Exception('Server tidak mengembalikan berkas PDF.');
      final bytes = base64Decode(b64);
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => Uint8List.fromList(bytes), name: '${widget.item['id']}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setState(() => _memprosesPdf = false);
    }
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = (mulai ? _tglMulai : _tglSampai) ?? DateTime.now();
    final dipilih = await showDatePicker(context: context, initialDate: awal, firstDate: DateTime(2015), lastDate: DateTime(2100));
    if (dipilih != null) {
      setState(() {
        if (mulai) {
          _tglMulai = dipilih;
        } else {
          _tglSampai = dipilih;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(widget.item['judul'] as String? ?? 'Laporan', overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((widget.item['ket'] as String? ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.item['ket'] as String, style: const TextStyle(color: AppColors.textSecondary))),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _kotakTanggal('Tanggal Mulai', _tglMulai, () => _pilihTanggal(mulai: true))),
                      const SizedBox(width: 12),
                      Expanded(child: _kotakTanggal('Tanggal Sampai', _tglSampai, () => _pilihTanggal(mulai: false))),
                    ],
                  ),
                  if (_adaFilterProduk) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _controllerProduk, decoration: const InputDecoration(labelText: 'Cari Produk', border: OutlineInputBorder(), isDense: true)),
                  ],
                  if (_adaFilterPelanggan) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _controllerPelanggan, decoration: const InputDecoration(labelText: 'Cari Pelanggan', border: OutlineInputBorder(), isDense: true)),
                  ],
                  if (_adaFilterPerToko)
                    CheckboxListTile(value: _perToko, onChanged: (v) => setState(() => _perToko = v ?? false), title: const Text('Tampilkan per Toko'), contentPadding: EdgeInsets.zero, dense: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _memuat ? null : _tampilkan,
                          icon: _memuat ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow),
                          label: const Text('Tampilkan'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _hasil == null || _memprosesPdf ? null : _cetakPdf,
                        icon: _memprosesPdf ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_pesanError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.latarLembut(AppColors.danger), borderRadius: BorderRadius.circular(8)),
                child: Text(_pesanError!, style: const TextStyle(color: AppColors.danger)),
              ),
            if (_hasil != null) _TabelLaporan(hasil: _hasil!),
          ],
        ),
      ),
    );
  }

  Widget _kotakTanggal(String label, DateTime? nilai, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        child: Text(nilai == null ? '-' : DateFormat('dd-MM-yyyy').format(nilai)),
      ),
    );
  }
}

/// Render generik tabel `kolom`/`baris` + logika grup/subtotal/grand-total
/// (padanan `laporan-renderer.js`/`LaporanKantinPdf.buildTable` -- lihat
/// JavaDoc kelas ini di server utk aturan lengkap): kolom `t=="tgl"` sudah
/// diformat server (`dd-MM-yyyy HH:mm`), `t=="num"` diformat id-ID di sini
/// (integer utk label berawalan Jml/Jumlah, 2 desimal lainnya, negatif
/// dikurung). Kolom `grup>=0` memicu baris header-grup + subtotal per
/// perubahan nilai; `grandTotal` menambah baris total keseluruhan di akhir.
class _TabelLaporan extends StatelessWidget {
  final Map<String, dynamic> hasil;
  const _TabelLaporan({required this.hasil});

  static const _lebarKolom = 150.0;

  bool _isHitungKolom(String label) {
    final l = label.trim().toLowerCase();
    return l.startsWith('jml') || l.startsWith('jumlah');
  }

  String _fmtNum(num? v, bool hitung) {
    if (v == null) return '';
    final neg = v < 0;
    final abs = v.abs();
    final formatter = hitung ? NumberFormat.decimalPattern('id_ID') : NumberFormat('#,##0.00', 'id_ID');
    final s = formatter.format(abs);
    return neg ? '($s)' : s;
  }

  String _fmtSel(dynamic v, String tipe, String label) {
    if (v == null) return '';
    if (tipe == 'num') return _fmtNum(v as num, _isHitungKolom(label));
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final kolom = ((hasil['kolom'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final baris = ((hasil['baris'] as List?) ?? []).map((e) => List<dynamic>.from(e as List)).toList();
    final catatan = hasil['catatan'] as String?;
    final grup = (hasil['grup'] as num?)?.toInt() ?? -1;
    final grandTotal = hasil['grandTotal'] == true;
    final judul = hasil['judul'] as String?;

    if (kolom.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Tidak ada kolom pada laporan ini.')));
    }
    if (baris.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Tidak ada data untuk filter yang dipilih.')));
    }

    final lebarTotal = _lebarKolom * kolom.length;
    final numIdx = <int>[for (var i = 0; i < kolom.length; i++) if (kolom[i]['t'] == 'num') i];

    final List<Widget> baruBaris = [];

    void tambahBarisData(List<dynamic> r) {
      baruBaris.add(Row(
        children: List.generate(kolom.length, (i) {
          final tipe = kolom[i]['t'] as String? ?? 'text';
          final label = kolom[i]['l'] as String? ?? '';
          return SizedBox(width: _lebarKolom, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text(_fmtSel(r[i], tipe, label), style: TextStyle(fontFamily: tipe == 'num' ? 'monospace' : null))));
        }),
      ));
    }

    void tambahBarisPita(String teks, {Color? warna}) {
      baruBaris.add(Container(
        width: lebarTotal,
        color: warna ?? AppColors.latarLembut(AppColors.info),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(teks, style: const TextStyle(fontWeight: FontWeight.bold)),
      ));
    }

    void tambahBarisSubtotal(String key, Map<int, double> sums) {
      baruBaris.add(Row(
        children: List.generate(kolom.length, (i) {
          String teks = '';
          if (i == grup) {
            teks = 'Subtotal $key';
          } else if (sums.containsKey(i)) {
            teks = _fmtNum(sums[i], _isHitungKolom(kolom[i]['l'] as String? ?? ''));
          }
          return SizedBox(
            width: _lebarKolom,
            child: Container(
              color: AppColors.latarLembut(AppColors.textSecondary),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(teks, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
        }),
      ));
    }

    if (grup >= 0 && grup < kolom.length) {
      String? kunciSaatIni;
      final jumlahSaatIni = <int, double>{};
      for (final r in baris) {
        final kunci = r[grup]?.toString() ?? '';
        if (kunciSaatIni == null) {
          tambahBarisPita(kunci);
          kunciSaatIni = kunci;
        } else if (kunci != kunciSaatIni) {
          tambahBarisSubtotal(kunciSaatIni, jumlahSaatIni);
          jumlahSaatIni.clear();
          tambahBarisPita(kunci);
          kunciSaatIni = kunci;
        }
        for (final i in numIdx) {
          jumlahSaatIni[i] = (jumlahSaatIni[i] ?? 0) + ((r[i] as num?)?.toDouble() ?? 0);
        }
        final rSalinan = List<dynamic>.from(r);
        rSalinan[grup] = null;
        tambahBarisData(rSalinan);
      }
      if (kunciSaatIni != null) tambahBarisSubtotal(kunciSaatIni, jumlahSaatIni);
    } else {
      for (final r in baris) {
        tambahBarisData(r);
      }
    }

    if (grandTotal && numIdx.isNotEmpty) {
      final total = <int, double>{};
      for (final r in baris) {
        for (final i in numIdx) {
          total[i] = (total[i] ?? 0) + ((r[i] as num?)?.toDouble() ?? 0);
        }
      }
      baruBaris.add(Row(
        children: List.generate(kolom.length, (i) {
          String teks = '';
          if (i == 0) {
            teks = 'TOTAL';
          } else if (total.containsKey(i)) {
            teks = _fmtNum(total[i], _isHitungKolom(kolom[i]['l'] as String? ?? ''));
          }
          return SizedBox(
            width: _lebarKolom,
            child: Container(
              color: AppColors.latarLembut(AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(teks, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
        }),
      ));
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (judul != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          if (catatan != null && catatan.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(catatan, style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary, fontSize: 12))),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: lebarTotal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    color: AppColors.pageBg,
                    child: Row(
                      children: kolom
                          .map((k) => SizedBox(
                                width: _lebarKolom,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  child: Text(k['l'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const Divider(height: 1),
                  ...baruBaris,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
