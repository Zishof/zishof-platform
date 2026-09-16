import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/foundation.dart';

Map<String, dynamic> _kolomSnapshot(String snapshot) {
  final isi = jsonDecode(snapshot) as Map<String, dynamic>;
  final rows = (isi['rows'] as List).cast<Map<String, dynamic>>();
  return {
    'terpotong': isi['terpotong'] == true ? 1 : 0,
    'rows': [
      for (var i = 0; i < rows.length; i++)
        {
          'urutan': i,
          'nota': rows[i]['_nota'],
          'produk': rows[i]['_produk'],
          'kode': rows[i]['_kode'],
          'nama': rows[i]['_nama'],
          'metode': rows[i]['_metode'],
          'satuan': rows[i]['satuan'] ?? '',
          'qty': rows[i]['qty'] ?? 0,
          'total': rows[i]['total'] ?? 0,
          'isi': jsonEncode(rows[i]),
        }
    ],
  };
}

/// Snapshot laporan read-only. Satu penggantian atomik setelah SEMUA halaman
/// server tervalidasi; filter, urut dan paginasi dijalankan oleh SQLite.
class RincianProdukCache {
  static Future<void> _siapkan() async {
    final db = await CoreDb.instance.db;
    // Cache tambahan; tidak mengubah transaksi/saldo/outbox. Kolom biasa
    // menjaga kompatibilitas Android yang tidak menyediakan ekstensi JSON1.
    await db.execute('''CREATE TABLE IF NOT EXISTS laporan_produk_snapshot (
      kunci TEXT PRIMARY KEY, terpotong INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS laporan_produk_baris (
      kunci TEXT NOT NULL, urutan INTEGER NOT NULL, nota TEXT NOT NULL,
      produk TEXT NOT NULL, kode TEXT NOT NULL, nama TEXT NOT NULL,
      metode TEXT NOT NULL, satuan TEXT NOT NULL, qty REAL NOT NULL,
      total REAL NOT NULL, isi TEXT NOT NULL, PRIMARY KEY(kunci, urutan)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_laporan_produk_metode
      ON laporan_produk_baris(kunci, metode, nota)''');
  }

  static Future<void> simpan(String key, String snapshot) async {
    final data = await compute(_kolomSnapshot, snapshot);
    await _siapkan();
    final db = await CoreDb.instance.db;
    await db.transaction((txn) async {
      await txn
          .delete('laporan_produk_baris', where: 'kunci = ?', whereArgs: [key]);
      await txn.delete('laporan_produk_snapshot',
          where: 'kunci = ?', whereArgs: [key]);
      await txn.insert('laporan_produk_snapshot',
          {'kunci': key, 'terpotong': data['terpotong']});
      final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < rows.length; i += 100) {
        final batch = txn.batch();
        for (final row in rows.skip(i).take(100)) {
          batch.insert('laporan_produk_baris', {'kunci': key, ...row});
        }
        await batch.commit(noResult: true);
      }
    });
  }

  static Future<Map<String, dynamic>?> baca(String key, String metode,
      {int halaman = 1, int halamanRekap = 1, bool ekspor = false}) async {
    await _siapkan();
    final db = await CoreDb.instance.db;
    // Semua SELECT berbagi snapshot SQLite yang sama, termasuk saat refresh
    // dari layar lain selesai di tengah pembacaan.
    return db.transaction((txn) async {
      final meta = await txn.rawQuery('''
        SELECT terpotong FROM laporan_produk_snapshot WHERE kunci = ?
      ''', [key]);
      if (meta.isEmpty) return null;
      const sumber = '''
        WITH terpilih AS (
          SELECT * FROM laporan_produk_baris
          WHERE kunci = ? AND (? = '' OR metode = ?)
        )
      ''';
      final args = [key, metode, metode];
      final ringkasan = (await txn.rawQuery('''$sumber
        SELECT COUNT(*) AS jumlah, COALESCE(SUM(nilai), 0) AS nilai FROM (
          SELECT SUM(total) AS nilai
          FROM terpilih GROUP BY produk, metode
        )
      ''', args)).single;
      final jumlahRekap = (ringkasan['jumlah'] as num).toInt();
      final pageRekap = halamanRekap.clamp(
          1, jumlahRekap == 0 ? 1 : (jumlahRekap + 49) ~/ 50);
      final hitung = await txn.rawQuery('''$sumber
        SELECT COUNT(DISTINCT nota) AS total FROM terpilih
      ''', args);
      final total = (hitung.single['total'] as num).toInt();
      final maksimal = total == 0 ? 1 : (total + 9) ~/ 10;
      final page = halaman.clamp(1, maksimal);
      final detail = await txn.rawQuery('''$sumber
        SELECT isi FROM terpilih
        ${ekspor ? '' : '''WHERE nota IN (
          SELECT nota FROM terpilih GROUP BY nota ORDER BY MIN(urutan)
          LIMIT 10 OFFSET ?
        )'''}
        ORDER BY urutan
      ''', [...args, if (!ekspor) (page - 1) * 10]);
      final rekap = await txn.rawQuery('''$sumber
        SELECT kode AS produkKode, nama AS produkNama, satuan, metode,
          SUM(qty) AS qty, SUM(total) AS total,
          COUNT(DISTINCT nota) AS jumlahTransaksi, MIN(urutan) AS pertama
        FROM terpilih GROUP BY produk, metode ORDER BY total DESC, pertama
        ${ekspor ? '' : 'LIMIT 50 OFFSET ?'}
      ''', [...args, if (!ekspor) (pageRekap - 1) * 50]);
      final rows = detail
          .map((r) => Map<String, dynamic>.from(jsonDecode(r['isi'] as String)))
          .toList();
      return {
        'data': rows,
        'rows': rows,
        'rekap': rekap,
        'total': total,
        'halaman': page,
        'halamanRekap': pageRekap,
        'totalRekap': jumlahRekap,
        'nilaiRekap': ringkasan['nilai'],
        'terpotong': meta.single['terpotong'] == 1,
      };
    });
  }
}
