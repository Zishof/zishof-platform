import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../sesi.dart';

String kunciHistoriPelunasan(Map<String, dynamic> filter) {
  final sesi = Sesi.instance;
  return jsonEncode([
    'histori-pelunasan-v1',
    ApiClient.baseUrl,
    sesi.userId,
    sesi.tenantId,
    sesi.idTokoTerpilih,
    sesi.tokoFilter,
    sesi.isAdmin,
    sesi.supervisorPedagang,
    sesi.bolehEntryPelunasanPiutang,
    filter['dari'],
    filter['sampai'],
    filter['id_anggota'],
  ]);
}

// Server legacy membatasi 3000 MUTASI (bukan 3000 pembayaran). Jangan
// menyatakan histori lengkap atau mengganti cache dengan hasil terpotong.
List<Map<String, dynamic>> _siapkanPembayaran(Map<String, dynamic> hasil) {
  final rows = hasil['data'];
  if (rows is! List) {
    throw const FormatException('Respons histori tidak valid.');
  }
  if (rows.length >= 3000 ||
      (hasil['total'] is num && (hasil['total'] as num) > rows.length)) {
    throw const FormatException(
        'Histori melebihi batas server. Persempit rentang tanggal atau pilih satu pelanggan agar tidak ada pembayaran terlewat.');
  }
  final data = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final raw in rows) {
    if (raw is! Map || raw['barisId'] == null) {
      throw const FormatException('Baris histori tidak valid.');
    }
    final id = '${raw['barisId']}';
    if (!id.startsWith('C')) continue; // H = penambahan piutang, bukan bayar.
    final waktu = DateTime.tryParse('${raw['waktu']}');
    final nominal = raw['berkurang'];
    if (waktu == null ||
        nominal is! num ||
        !nominal.isFinite ||
        nominal < 0 ||
        !ids.add(id)) {
      throw const FormatException(
          'Tanggal/nominal/identitas pembayaran tidak valid.');
    }
    data.add({
      'id': id,
      'waktu': waktu.toIso8601String(),
      'nominal': nominal,
      'isi': jsonEncode(raw),
    });
  }
  return data;
}

/// Cache read-only histori terkonfirmasi. Tidak mengubah saldo atau outbox.
/// Snapshot dipisah per akses + filter, validasi di isolate, penggantian atomik,
/// lalu urut/paginasi/agregasi di SQLite (bukan snapshot penuh di widget).
class HistoriPelunasan {
  static Future<void> _siapkan() async {
    final db = await CoreDb.instance.db;
    await db.execute('''CREATE TABLE IF NOT EXISTS histori_pelunasan_snapshot (
      kunci TEXT PRIMARY KEY, diperbarui TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS histori_pelunasan_baris (
      kunci TEXT NOT NULL, id TEXT NOT NULL, waktu TEXT NOT NULL,
      nominal REAL NOT NULL, isi TEXT NOT NULL, PRIMARY KEY(kunci, id)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_histori_pelunasan_waktu
      ON histori_pelunasan_baris(kunci, waktu, id)''');
  }

  static Future<void> simpan(String key, Map<String, dynamic> hasil) async {
    final rows = await compute(_siapkanPembayaran, hasil);
    await _siapkan();
    final db = await CoreDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete('histori_pelunasan_baris',
          where: 'kunci = ?', whereArgs: [key]);
      await txn.delete('histori_pelunasan_snapshot',
          where: 'kunci = ?', whereArgs: [key]);
      await txn.insert('histori_pelunasan_snapshot', {
        'kunci': key,
        'diperbarui': DateTime.now().toIso8601String(),
      });
      for (var i = 0; i < rows.length; i += 100) {
        final batch = txn.batch();
        for (final row in rows.skip(i).take(100)) {
          batch.insert('histori_pelunasan_baris', {'kunci': key, ...row});
        }
        await batch.commit(noResult: true);
      }
    });
  }

  static Future<Map<String, dynamic>?> baca(String key,
      {int halaman = 1}) async {
    await _siapkan();
    final db = await CoreDb.instance.db;
    return db.transaction((txn) async {
      final meta = await txn.query('histori_pelunasan_snapshot',
          where: 'kunci = ?', whereArgs: [key]);
      if (meta.isEmpty) return null;
      final jumlah = (await txn.rawQuery('''SELECT COUNT(*) AS jumlah,
        COALESCE(SUM(nominal), 0) AS nominal FROM histori_pelunasan_baris
        WHERE kunci = ?''', [key])).single;
      final total = (jumlah['jumlah'] as num).toInt();
      final totalHalaman = ((total + 19) ~/ 20).clamp(1, 999999);
      final page = halaman.clamp(1, totalHalaman);
      final rows = await txn.query('histori_pelunasan_baris',
          columns: ['isi'],
          where: 'kunci = ?',
          whereArgs: [key],
          orderBy: 'waktu DESC, id DESC',
          limit: 20,
          offset: (page - 1) * 20);
      return {
        'data': [
          for (final row in rows)
            jsonDecode(row['isi'] as String) as Map<String, dynamic>
        ],
        'total': total,
        'nominal': jumlah['nominal'],
        'halaman': page,
        'totalHalaman': totalHalaman,
        'diperbarui': meta.single['diperbarui'],
      };
    });
  }

  static Future<void> segarkan(String key, Map<String, dynamic> filter,
      {Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
          pemuat}) async {
    // READ-ONLY; endpoint lama sudah mengembalikan waktu pembayaran yang dipilih.
    final hasil = await (pemuat ??
        (body) => ApiClient.instance.aksi('mutasi_hutang_list', body))(filter);
    await simpan(key, hasil);
  }
}
