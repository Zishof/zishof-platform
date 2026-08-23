import 'package:flutter/material.dart';

import 'app_components.dart';
import 'safe_state.dart';

/// Hasil pilihan dari dialog cari akun.
///
/// Dibedakan dari `null` hasil `showDialog` supaya "kosongkan pilihan"
/// (id == null) tidak sama dengan "dialog ditutup tanpa memilih".
class PilihanAkun {
  const PilihanAkun(this.id);
  final int? id;
}

/// Field pemilih akun dengan kotak pencarian (kode & nama).
///
/// Menggantikan `DropdownButtonFormField` untuk daftar akun yang panjang:
/// bagan akun bisa ratusan baris sehingga menggulir dropdown tidak praktis.
/// Sumber datanya tetap `akun_list` (id, kode, nama, label), jadi pemanggil
/// tidak perlu berubah selain mengganti widget-nya.
class PemilihAkunField extends StatelessWidget {
  const PemilihAkunField({
    super.key,
    required this.label,
    required this.daftar,
    required this.nilai,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final List<Map<String, dynamic>> daftar;
  final int? nilai;
  final ValueChanged<int?> onChanged;
  final String? helperText;

  Map<String, dynamic>? get _terpilih {
    for (final a in daftar) {
      if ((a['id'] as num?)?.toInt() == nilai) return a;
    }
    return null;
  }

  static String teksAkun(Map<String, dynamic> a) {
    final label = '${a['label'] ?? ''}'.trim();
    if (label.isNotEmpty) return label;
    return '${a['kode'] ?? ''} ${a['nama'] ?? ''}'.trim();
  }

  Future<void> _buka(BuildContext context) async {
    final hasil = await showDialog<PilihanAkun>(
      context: context,
      builder: (_) =>
          _DialogCariAkun(judul: label, daftar: daftar, terpilih: nilai),
    );
    if (hasil != null) onChanged(hasil.id);
  }

  @override
  Widget build(BuildContext context) {
    final a = _terpilih;
    final adaPilihan = a != null;
    final warnaKosong = Theme.of(context).hintColor;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _buka(context),
      child: InputDecorator(
        decoration: AppFormStyle.fieldDecoration(
          context,
          labelText: label,
          helperText: helperText,
          suffixIcon: adaPilihan
              ? IconButton(
                  tooltip: 'Kosongkan',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.search),
        ),
        child: Text(
          adaPilihan ? teksAkun(a) : '-- Tidak dipilih --',
          overflow: TextOverflow.ellipsis,
          style: adaPilihan ? null : TextStyle(color: warnaKosong),
        ),
      ),
    );
  }
}

class _DialogCariAkun extends StatefulWidget {
  const _DialogCariAkun(
      {required this.judul, required this.daftar, required this.terpilih});

  final String judul;
  final List<Map<String, dynamic>> daftar;
  final int? terpilih;

  @override
  State<_DialogCariAkun> createState() => _DialogCariAkunState();
}

class _DialogCariAkunState extends State<_DialogCariAkun> {
  final TextEditingController _cari = TextEditingController();

  /// id induk -> daftar anaknya, dan daftar akar. Dibangun sekali dari daftar
  /// yang dikirim server (`parentId`).
  late final Map<int, List<Map<String, dynamic>>> _anak;
  late final List<Map<String, dynamic>> _akar;
  late final Map<int, Map<String, dynamic>> _perId;

  @override
  void initState() {
    super.initState();
    _perId = <int, Map<String, dynamic>>{};
    for (final a in widget.daftar) {
      final id = (a['id'] as num?)?.toInt();
      if (id != null) _perId[id] = a;
    }
    _anak = <int, List<Map<String, dynamic>>>{};
    _akar = <Map<String, dynamic>>[];
    for (final a in widget.daftar) {
      final induk = (a['parentId'] as num?)?.toInt();
      // Induk yang tidak ikut terkirim (mis. karena limit) diperlakukan sebagai
      // akar, supaya akunnya tetap terlihat alih-alih hilang dari pohon.
      if (induk == null || !_perId.containsKey(induk)) {
        _akar.add(a);
      } else {
        _anak.putIfAbsent(induk, () => <Map<String, dynamic>>[]).add(a);
      }
    }
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  /// Akun daun = tidak punya anak. Server mengirimnya lewat `leaf`; bila field itu
  /// tidak ada (server lama), disimpulkan dari ada-tidaknya anak.
  bool _daun(Map<String, dynamic> a) {
    if (a['leaf'] is bool) return a['leaf'] as bool;
    final id = (a['id'] as num?)?.toInt();
    return id == null || !(_anak[id]?.isNotEmpty ?? false);
  }

  bool _cocok(Map<String, dynamic> a, List<String> bagian) {
    final teks = '${a['kode'] ?? ''} ${a['nama'] ?? ''} ${a['label'] ?? ''}'.toLowerCase();
    for (final b in bagian) {
      if (!teks.contains(b)) return false;
    }
    return true;
  }

  /// Baris yang dirender: pohon yang diratakan, masing-masing membawa kedalamannya.
  ///
  /// Saat mencari, sebuah simpul ikut ditampilkan bila ia sendiri cocok ATAU salah
  /// satu keturunannya cocok -- sehingga hasil pencarian tetap muncul lengkap dengan
  /// jalur induknya, bukan sebagai potongan tanpa konteks.
  List<_BarisAkun> get _baris {
    final kata = _cari.text.trim().toLowerCase();
    final bagian = kata.isEmpty ? const <String>[] : kata.split(RegExp(r'\s+'));
    final hasil = <_BarisAkun>[];

    bool tambah(Map<String, dynamic> a, int dalam) {
      final id = (a['id'] as num?)?.toInt();
      final anak = id == null ? const <Map<String, dynamic>>[] : (_anak[id] ?? const []);
      final sendiriCocok = bagian.isEmpty || _cocok(a, bagian);
      final posisi = hasil.length;
      hasil.add(_BarisAkun(a, dalam, _daun(a)));
      var adaKeturunanCocok = false;
      for (final c in anak) {
        if (tambah(c, dalam + 1)) adaKeturunanCocok = true;
      }
      if (!sendiriCocok && !adaKeturunanCocok) {
        hasil.removeRange(posisi, hasil.length);
        return false;
      }
      return true;
    }

    for (final a in _akar) {
      tambah(a, 0);
    }
    return hasil;
  }

  void _pilih(int? id) => Navigator.of(context).pop(PilihanAkun(id));

  @override
  Widget build(BuildContext context) {
    final baris = _baris;
    final jumlahDaun = baris.where((b) => b.daun).length;
    final warnaInduk = Theme.of(context).hintColor;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                    child: Text(widget.judul,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _cari,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Cari kode atau nama akun...',
                ),
                onChanged: (_) => setStateIfMounted(() {}),
                // Enter mengambil DAUN teratas -- akun induk tidak pernah menjadi
                // jawaban, jadi tidak boleh terpilih hanya karena kebetulan di atas.
                onSubmitted: (_) {
                  for (final b in baris) {
                    if (b.daun) {
                      _pilih((b.akun['id'] as num?)?.toInt());
                      return;
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '$jumlahDaun akun dapat dipilih · akun induk hanya penunjuk susunan',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: baris.isEmpty
                    ? const Center(child: Text('Akun tidak ditemukan.'))
                    : ListView.builder(
                        itemCount: baris.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.block, size: 18),
                              title: const Text('-- Tidak dipilih --'),
                              selected: widget.terpilih == null,
                              onTap: () => _pilih(null),
                            );
                          }
                          final b = baris[i - 1];
                          final a = b.akun;
                          final id = (a['id'] as num?)?.toInt();
                          final kode = '${a['kode'] ?? ''}'.trim();
                          return ListTile(
                            dense: true,
                            // Indentasi mengikuti kedalamannya; induk dibuat redup dan
                            // TIDAK dapat ditekan (onTap null) supaya jelas ia bukan
                            // pilihan, bukan sekadar pilihan yang kebetulan salah.
                            contentPadding:
                                EdgeInsets.only(left: 8.0 + b.dalam * 16.0, right: 8),
                            leading: kode.isEmpty
                                ? null
                                : SizedBox(
                                    width: 84,
                                    child: Text(kode,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight:
                                                b.daun ? FontWeight.w600 : FontWeight.w400,
                                            color: b.daun ? null : warnaInduk))),
                            title: Text(
                              '${a['nama'] ?? PemilihAkunField.teksAkun(a)}',
                              overflow: TextOverflow.ellipsis,
                              style: b.daun ? null : TextStyle(color: warnaInduk),
                            ),
                            selected: b.daun && id == widget.terpilih,
                            enabled: b.daun,
                            onTap: b.daun ? () => _pilih(id) : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Satu baris pohon akun: akunnya, kedalamannya, dan apakah ia dapat dipilih.
class _BarisAkun {
  const _BarisAkun(this.akun, this.dalam, this.daun);
  final Map<String, dynamic> akun;
  final int dalam;
  final bool daun;
}
