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
  _simpanHakHotel(res);
  return (res['data'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

/// Hak per kunci menu Hotel, dikumpulkan dari balasan daftar mana pun.
///
/// Ditangkap di [muatDaftarHotel] karena SELURUH layar MitraInap memuat datanya
/// lewat sana -- satu tempat, sembilan layar. Menambahkan pembacaan hak di tiap
/// layar pasti meninggalkan layar baru tanpa gerbang.
final Map<String, Map<String, bool>> _hakHotel = {};

void _simpanHakHotel(Map<String, dynamic> res) {
  final kunci = '${res['hakKunci'] ?? ''}'.trim();
  final hak = res['hak'];
  // Kunci menunya datang dari PELADEN, bukan disalin di sini: dua salinan tabel
  // pemetaan aksi-ke-kunci pasti berbeda begitu salah satunya diubah.
  if (kunci.isEmpty || hak is! Map) return;
  _hakHotel[kunci] = hak.map((k, v) => MapEntry('$k', v == true));
}

/// Bolehkah [aksi] pada menu [kunciMenu]?
///
/// Selama haknya belum pernah tiba untuk kunci itu, jawabannya YA: peladen tetap
/// gerbang sebenarnya, dan memadamkan tombol hanya karena haknya belum dimuat
/// justru mengunci pengguna yang sebenarnya berhak.
bool bolehHotel(String kunciMenu, String aksi) {
  final hak = _hakHotel[kunciMenu];
  if (hak == null) return true;
  return hak[aksi] != false;
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
