import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identitas fisik perangkat (padanan `identitas-mesin.json` Electron) --
/// [idMesin] UUID v4 dibuat SEKALI lalu disimpan permanen (membedakan
/// beberapa mesin/HP kasir di satu toko yang sama walau admin memberi nama
/// yang sama pada dua mesin); [namaMesin] label yang bisa diubah admin,
/// dikirim di setiap transaksi (field `namaMesin`) supaya laporan bisa
/// membedakan "transaksi dari mesin ini vs mesin lain".
class IdentitasMesin {
  IdentitasMesin._();
  static final IdentitasMesin instance = IdentitasMesin._();

  static const _kunciId = 'identitas_mesin_id';
  static const _kunciNama = 'identitas_mesin_nama';

  String? _idMesin;
  String? _namaMesin;
  Future<void>? _pemuatan;

  Future<void> muat() => _pemuatan ??= _muatTersimpan().whenComplete(() {
        _pemuatan = null;
      });

  Future<void> _muatTersimpan() async {
    final sp = await SharedPreferences.getInstance();
    final tersimpan = sp.getString(_kunciId)?.trim();
    final identitas = tersimpan == null || tersimpan.isEmpty
        ? (_idMesin ?? const Uuid().v4())
        : tersimpan;
    if (tersimpan != identitas) {
      if (!await sp.setString(_kunciId, identitas)) {
        throw StateError('Identitas perangkat belum dapat disimpan.');
      }
    }
    _idMesin = identitas;
    _namaMesin = sp.getString(_kunciNama);
  }

  String get idMesin => _idMesin ?? '';
  String get namaMesin => _namaMesin ?? '';

  Future<void> simpanNamaMesin(String nama) async {
    _namaMesin = nama;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciNama, nama);
  }
}
