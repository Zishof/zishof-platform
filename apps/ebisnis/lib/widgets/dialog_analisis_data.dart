import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';

/// <h3>Popup "Analisis Data" -- rekap laporan dalam bentuk tab, meniru susunan
/// berkas Excel: satu tab Ringkasan lalu satu tab per kolom pengelompokan.</h3>
///
/// Masukannya bentuk mentah hasil laporan (`kolom` = `{l: label, t: tipe}`,
/// `baris` = daftar nilai per indeks kolom), jadi widget ini berlaku untuk
/// SELURUH ~150 laporan tanpa perlu tahu isi masing-masing.
///
/// <p>Angkanya dihitung ulang dari baris yang SEDANG TAMPIL, bukan diminta lagi
/// ke server. Dengan begitu rekap di popup ini tidak mungkin berbeda dari tabel
/// di belakangnya -- perbedaan sekecil apa pun antara keduanya akan membuat
/// pengguna tidak tahu angka mana yang benar.</p>
Future<void> tampilkanAnalisisData(
  BuildContext context, {
  required String judul,
  String subjudul = '',
  required List<Map<String, dynamic>> kolom,
  required List<List<dynamic>> baris,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogAnalisisData(
      judul: judul,
      subjudul: subjudul,
      kolom: kolom,
      baris: baris,
    ),
  );
}

/// Batas kardinalitas kolom yang layak dijadikan pengelompokan.
///
/// Kolom seperti "Nota" atau "Kode" hampir selalu unik per baris; merekapnya
/// menghasilkan tabel sepanjang datanya sendiri dan tidak menjelaskan apa pun.
/// Kolom yang dilewati tetap DISEBUTKAN di tab Ringkasan berikut alasannya,
/// bukan dihilangkan diam-diam -- pengguna harus tahu apa yang tidak dianalisis.
const int _maksNilaiUnik = 60;
const int _maksBarisTabel = 100;

class _Rekap {
  final String nilai;
  final int jumlah;
  final double total;
  const _Rekap(this.nilai, this.jumlah, this.total);
}

class _DialogAnalisisData extends StatefulWidget {
  final String judul;
  final String subjudul;
  final List<Map<String, dynamic>> kolom;
  final List<List<dynamic>> baris;

  const _DialogAnalisisData({
    required this.judul,
    required this.subjudul,
    required this.kolom,
    required this.baris,
  });

  @override
  State<_DialogAnalisisData> createState() => _DialogAnalisisDataState();
}

class _DialogAnalisisDataState extends State<_DialogAnalisisData> {
  static final _fAngka = NumberFormat.decimalPattern('id');

  late final List<int> _idxAngka;
  late final List<int> _idxGrup;
  late final List<int> _idxDilewati;
  int? _kolomNilai;

  String _label(int i) => '${widget.kolom[i]['l'] ?? 'Kolom ${i + 1}'}';
  bool _angka(int i) => widget.kolom[i]['t'] == 'num';

  @override
  void initState() {
    super.initState();
    _idxAngka = [];
    _idxGrup = [];
    _idxDilewati = [];
    for (var i = 0; i < widget.kolom.length; i++) {
      if (_angka(i)) {
        _idxAngka.add(i);
        continue;
      }
      final unik = <String>{};
      var terlaluBanyak = false;
      for (final b in widget.baris) {
        unik.add(_teks(i < b.length ? b[i] : null));
        if (unik.length > _maksNilaiUnik) {
          terlaluBanyak = true;
          break;
        }
      }
      // Syaratnya BUKAN sekadar "nilai uniknya sedikit", melainkan "nilainya
      // berulang". Kolom yang setiap barisnya berbeda -- nomor nota, kode -- lolos
      // batas kardinalitas apa pun pada data kecil, padahal rekapnya sepanjang
      // datanya sendiri dan tidak menjelaskan apa pun. Perbandingan terhadap
      // JUMLAH BARIS-lah yang menangkap sifat itu di ukuran data mana pun.
      final semuaBerbeda = unik.length == widget.baris.length;
      if (!terlaluBanyak && !semuaBerbeda && unik.length >= 2) {
        _idxGrup.add(i);
      } else {
        _idxDilewati.add(i);
      }
    }
    // Kolom angka TERAKHIR dipakai sbg bawaan: pada laporan di aplikasi ini
    // kolom nilai/saldo hampir selalu berada paling kanan, sedangkan kolom
    // angka di kiri biasanya jumlah/qty.
    _kolomNilai = _idxAngka.isEmpty ? null : _idxAngka.last;
  }

  String _teks(Object? v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? '(kosong)' : s;
  }

  double _nilai(List<dynamic> b, int i) {
    if (i >= b.length) return 0;
    final v = b[i];
    if (v is num) return v.toDouble();
    final s = v?.toString().replaceAll('.', '').replaceAll(',', '.') ?? '';
    return double.tryParse(s) ?? 0;
  }

  List<_Rekap> _rekap(int idxGrup) {
    final agg = <String, List<double>>{};
    for (final b in widget.baris) {
      final k = _teks(idxGrup < b.length ? b[idxGrup] : null);
      final slot = agg.putIfAbsent(k, () => [0, 0]);
      slot[0] += 1;
      if (_kolomNilai != null) slot[1] += _nilai(b, _kolomNilai!);
    }
    final hasil = agg.entries
        .map((e) => _Rekap(e.key, e.value[0].toInt(), e.value[1]))
        .toList();
    hasil.sort((a, b) {
      final c = b.total.compareTo(a.total);
      return c != 0 ? c : b.jumlah.compareTo(a.jumlah);
    });
    return hasil;
  }

  // ── Tampilan ──────────────────────────────────────────────────────────────

  Widget _penjelasan(String teks) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(teks,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.45)),
      );

  Widget _tabelRekap(int idxGrup) {
    final rekap = _rekap(idxGrup);
    final totalNilai = rekap.fold<double>(0, (s, r) => s + r.total);
    final totalBaris = rekap.fold<int>(0, (s, r) => s + r.jumlah);
    final tampil = rekap.take(_maksBarisTabel).toList();
    final namaNilai = _kolomNilai == null ? '' : _label(_kolomNilai!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _penjelasan(
          'Baris dikelompokkan menurut "${_label(idxGrup)}". Kolom "Jumlah Baris" '
          'menghitung banyaknya baris pada tiap kelompok'
          '${namaNilai.isEmpty ? '' : ', dan "$namaNilai" menjumlahkan nilainya'}. '
          'Urutan dari nilai terbesar, supaya penyumbang terbesar terbaca lebih dulu.',
        ),
        Table(
          border: TableBorder.all(color: AppColors.border),
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.8),
            3: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFEFF3F8)),
              children: [
                _sel(_label(idxGrup), tebal: true),
                _sel('Jumlah Baris', tebal: true, kanan: true),
                _sel(namaNilai.isEmpty ? '-' : namaNilai,
                    tebal: true, kanan: true),
                _sel('%', tebal: true, kanan: true),
              ],
            ),
            ...tampil.map((r) => TableRow(children: [
                  _sel(r.nilai),
                  _sel(_fAngka.format(r.jumlah), kanan: true),
                  _sel(_fAngka.format(r.total), kanan: true),
                  _sel(
                      totalNilai == 0
                          ? '-'
                          : '${(r.total / totalNilai * 100).toStringAsFixed(1)}%',
                      kanan: true),
                ])),
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF7F9FC)),
              children: [
                _sel('TOTAL', tebal: true),
                _sel(_fAngka.format(totalBaris), tebal: true, kanan: true),
                _sel(_fAngka.format(totalNilai), tebal: true, kanan: true),
                _sel(totalNilai == 0 ? '-' : '100,0%',
                    tebal: true, kanan: true),
              ],
            ),
          ],
        ),
        if (rekap.length > tampil.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${rekap.length - tampil.length} kelompok lain tidak ditampilkan '
              '(dibatasi $_maksBarisTabel baris), tetapi TETAP ikut dihitung pada '
              'baris TOTAL di atas.',
              style: const TextStyle(fontSize: 11, color: AppColors.warning),
            ),
          ),
      ],
    );
  }

  Widget _sel(String t, {bool tebal = false, bool kanan = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          t,
          textAlign: kanan ? TextAlign.right : TextAlign.left,
          style: TextStyle(
              fontSize: 12,
              fontWeight: tebal ? FontWeight.w700 : FontWeight.w400),
        ),
      );

  Widget _tabRingkasan() {
    final n = widget.baris.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _penjelasan(
          'Ringkasan dihitung dari $n baris yang sedang tampil di laporan — bukan '
          'permintaan baru ke server. Jadi bila laporan disaring ulang, angka di '
          'sini ikut berubah dan tidak mungkin berbeda dari tabel di belakangnya.',
        ),
        Table(
          border: TableBorder.all(color: AppColors.border),
          columnWidths: const {
            0: FlexColumnWidth(2.4),
            1: FlexColumnWidth(1.4),
            2: FlexColumnWidth(1.4),
            3: FlexColumnWidth(1.4),
            4: FlexColumnWidth(1.2),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFEFF3F8)),
              children: [
                _sel('Kolom Angka', tebal: true),
                _sel('Jumlah', tebal: true, kanan: true),
                _sel('Rata-rata', tebal: true, kanan: true),
                _sel('Terbesar', tebal: true, kanan: true),
                _sel('Bernilai 0', tebal: true, kanan: true),
              ],
            ),
            ..._idxAngka.map((i) {
              final nilai = widget.baris.map((b) => _nilai(b, i)).toList();
              final jml = nilai.fold<double>(0, (s, v) => s + v);
              final nol = nilai.where((v) => v == 0).length;
              final maks = nilai.isEmpty
                  ? 0.0
                  : nilai.reduce((a, b) => a > b ? a : b);
              return TableRow(children: [
                _sel(_label(i)),
                _sel(_fAngka.format(jml), kanan: true),
                _sel(nilai.isEmpty ? '-' : _fAngka.format(jml / nilai.length),
                    kanan: true),
                _sel(_fAngka.format(maks), kanan: true),
                _sel(_fAngka.format(nol), kanan: true),
              ]);
            }),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Catatan pembacaan',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        _penjelasan(
          'Kolom "Bernilai 0" sering paling menjelaskan. Pada laporan bernilai uang, '
          'jumlah nol yang besar biasanya menandakan pencatatan yang tidak lengkap, '
          'bukan transaksi yang benar-benar bernilai nol.',
        ),
        if (_idxDilewati.isNotEmpty)
          _penjelasan(
            'Kolom yang TIDAK dianalisis: '
            '${_idxDilewati.map(_label).join(', ')}. '
            'Alasannya nilainya hampir selalu berbeda di tiap baris (seperti nomor '
            'nota) atau hanya punya satu nilai, sehingga pengelompokannya tidak '
            'menjelaskan apa pun. Disebutkan di sini supaya jelas apa yang tidak '
            'ikut dihitung.',
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lebar = MediaQuery.of(context).size.width.clamp(320.0, 1100.0);
    final tinggi = MediaQuery.of(context).size.height * 0.86;
    final tabs = <Tab>[const Tab(text: 'Ringkasan')];
    final isi = <Widget>[_tabRingkasan()];
    for (final i in _idxGrup) {
      tabs.add(Tab(text: 'Per ${_label(i)}'));
      isi.add(_tabelRekap(i));
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: lebar,
        height: tinggi,
        child: DefaultTabController(
          length: tabs.length,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.insights_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Analisis Data — ${widget.judul}',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (widget.subjudul.trim().isNotEmpty)
                            Text(widget.subjudul,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (_idxAngka.length > 1)
                      SizedBox(
                        width: 210,
                        child: DropdownButtonFormField<int>(
                          value: _kolomNilai,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Nilai yang dijumlahkan',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _idxAngka
                              .map((i) => DropdownMenuItem<int>(
                                    value: i,
                                    child: Text(_label(i),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _kolomNilai = v),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Tutup',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                tabs: tabs,
              ),
              const Divider(height: 1),
              Expanded(
                child: widget.baris.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Laporan belum memuat baris apa pun. Tekan "Tampilkan" '
                            'lebih dulu, lalu buka Analisis Data lagi.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : TabBarView(children: isi),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
