import 'package:flutter/material.dart';

/// Filter status yang dipakai bersama oleh seluruh halaman posting.
enum FilterStatusPosting { semua, sudah, belum }

List<Map<String, dynamic>> rincianPostingSemua(Map<String, dynamic>? data) {
  Map<String, dynamic> map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);
  final belum =
      ((data?['rincian'] as List?) ?? const []).whereType<Map>().map(map);
  final sudah = ((data?['rincianSudahDiposting'] as List?) ?? const [])
      .whereType<Map>()
      .map(map);
  return [...belum, ...sudah];
}

List<Map<String, dynamic>> filterRincianPosting(
  Iterable<Map<String, dynamic>> sumber,
  FilterStatusPosting filter,
) {
  return sumber.where((baris) {
    final sudah = baris['sudahDiposting'] == true;
    return switch (filter) {
      FilterStatusPosting.semua => true,
      FilterStatusPosting.sudah => sudah,
      FilterStatusPosting.belum => !sudah,
    };
  }).toList(growable: false);
}

/// Kontrol tiga keadaan: Semua, Telah Diposting, dan Belum Diposting.
///
/// Jumlah pada label berasal dari data yang benar-benar diterima, sehingga
/// pengguna langsung dapat membedakan histori dari antrean kerja tanpa harus
/// menebak berdasarkan ada/tidaknya tombol Posting.
class FilterStatusPostingBar extends StatelessWidget {
  const FilterStatusPostingBar({
    super.key,
    required this.nilai,
    required this.jumlahSemua,
    required this.jumlahSudah,
    required this.jumlahBelum,
    required this.onChanged,
  });

  final FilterStatusPosting nilai;
  final int jumlahSemua;
  final int jumlahSudah;
  final int jumlahBelum;
  final ValueChanged<FilterStatusPosting> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<FilterStatusPosting>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: FilterStatusPosting.semua,
            icon: const Icon(Icons.view_list_outlined, size: 17),
            label: Text('Semua ($jumlahSemua)'),
          ),
          ButtonSegment(
            value: FilterStatusPosting.sudah,
            icon: const Icon(Icons.task_alt, size: 17),
            label: Text('Telah Diposting ($jumlahSudah)'),
          ),
          ButtonSegment(
            value: FilterStatusPosting.belum,
            icon: const Icon(Icons.pending_actions_outlined, size: 17),
            label: Text('Belum Diposting ($jumlahBelum)'),
          ),
        ],
        selected: {nilai},
        onSelectionChanged: (pilihan) {
          if (pilihan.isNotEmpty) onChanged(pilihan.first);
        },
      ),
    );
  }
}
