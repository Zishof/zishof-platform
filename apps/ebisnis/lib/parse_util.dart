/// Parsing angka toleran koma/titik (gap-closure 2026-08-11) -- input desimal di seluruh layar
/// app ini SEBELUMNYA masing-masing menyalin ulang `text.replaceAll(',', '.')` sendiri-sendiri
/// (21+ titik pemakaian, lihat riwayat investigasi Kulakan) -- satu tempat di sini supaya
/// perbaikan/penyesuaian format ke depannya cukup dilakukan sekali.
///
/// SENGAJA cuma menoleransi SATU pemisah desimal (koma ATAU titik, bukan keduanya sekaligus) --
/// TIDAK menoleransi format ribuan spt "1.234,56"/"1,234.56" (akan gagal parse/salah baca),
/// konsisten dgn keterbatasan pola lama yang digantikan.
library;

double? parseDesimal(String? teks) {
  if (teks == null) return null;
  final bersih = teks.trim().replaceAll(',', '.');
  if (bersih.isEmpty) return null;
  return double.tryParse(bersih);
}

/// Sama seperti [parseDesimal] tapi mengembalikan [fallback] (default 0) bila gagal/kosong --
/// dipakai di titik yang tidak boleh null (mis. langsung dipakai dalam perhitungan).
double parseDesimalAtau(String? teks, [double fallback = 0]) {
  return parseDesimal(teks) ?? fallback;
}
