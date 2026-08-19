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

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _hasil {
    final kata = _cari.text.trim().toLowerCase();
    if (kata.isEmpty) return widget.daftar;
    // Semua kata harus cocok, boleh tersebar di kode maupun nama, sehingga
    // "411 penjualan" tetap ketemu walau urutannya tidak persis.
    final bagian = kata.split(RegExp(r'\s+'));
    return widget.daftar.where((a) {
      final teks = '${a['kode'] ?? ''} ${a['nama'] ?? ''} ${a['label'] ?? ''}'
          .toLowerCase();
      for (final b in bagian) {
        if (!teks.contains(b)) return false;
      }
      return true;
    }).toList();
  }

  void _pilih(int? id) => Navigator.of(context).pop(PilihanAkun(id));

  @override
  Widget build(BuildContext context) {
    final hasil = _hasil;
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
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
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
                // Enter langsung mengambil hasil teratas -- membantu entri cepat
                // di Desktop saat kode akun sudah diketik lengkap.
                onSubmitted: (_) {
                  if (hasil.isNotEmpty) {
                    _pilih((hasil.first['id'] as num?)?.toInt());
                  }
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${hasil.length} akun',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: hasil.isEmpty
                    ? const Center(child: Text('Akun tidak ditemukan.'))
                    : ListView.builder(
                        itemCount: hasil.length + 1,
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
                          final a = hasil[i - 1];
                          final id = (a['id'] as num?)?.toInt();
                          final kode = '${a['kode'] ?? ''}'.trim();
                          return ListTile(
                            dense: true,
                            leading: kode.isEmpty
                                ? null
                                : SizedBox(
                                    width: 84,
                                    child: Text(kode,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                            title: Text(
                                '${a['nama'] ?? PemilihAkunField.teksAkun(a)}',
                                overflow: TextOverflow.ellipsis),
                            selected: id == widget.terpilih,
                            onTap: () => _pilih(id),
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
