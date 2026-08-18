import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';

/// Utilitas bersama layar-layar MitraInap (aksi hotel_* / HotelApiHelper).
/// Kontrak status API mengikuti PosApi: sukses = '00' atau 'success';
/// hotel_checkout punya status khusus '91' = folio masih bersaldo.

final formatRupiahHotel =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

final formatTanggalHotel = DateFormat('yyyy-MM-dd');

bool apiSukses(Map<String, dynamic> res) =>
    res['status'] == '00' || res['status'] == 'success';

String apiPesan(Map<String, dynamic> res, String cadangan) =>
    (res['description'] ?? cadangan).toString();

int? idInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

double angka(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

/// Panggil satu aksi hotel_* yang mengembalikan `data` list-of-map; lempar
/// Exception berisi description server bila gagal (pola GrupProdukScreen).
Future<List<Map<String, dynamic>>> muatDaftarHotel(
    String aksi, Map<String, dynamic> body) async {
  final res = await ApiClient.instance.aksi(aksi, body);
  if (!apiSukses(res)) {
    throw Exception(apiPesan(res, 'Gagal memuat data ($aksi).'));
  }
  return (res['data'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

/// Dropdown properti -- SEMUA layar MitraInap berscope satu properti
/// (multi-properti per akun, keputusan handover §2.4), jadi pemilihan
/// properti selalu jadi kontrol pertama di tiap layar.
class PilihPropertiHotel extends StatelessWidget {
  final List<Map<String, dynamic>> daftar;
  final int? nilai;
  final ValueChanged<int?> onUbah;

  const PilihPropertiHotel({
    super.key,
    required this.daftar,
    required this.nilai,
    required this.onUbah,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: nilai,
      decoration: const InputDecoration(
        labelText: 'Properti',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: daftar
          .map((p) => DropdownMenuItem<int>(
                value: idInt(p['id']),
                child: Text(
                  '${p['nama'] ?? p['kode'] ?? p['id']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: onUbah,
    );
  }
}
