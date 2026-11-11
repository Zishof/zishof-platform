import 'package:ebisnis/screens/ringkasan/tab_shortcut.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalisasi menerima nama properti dari layanan Java', () {
    final hasil = normalisasiShortcutDariLayanan({
      'judul': 'Mutasi Barang',
      'deskripsi': 'Kronologi stok',
      'aksesKunci': 'produk',
    });

    expect(hasil['ket'], 'Kronologi stok');
    expect(hasil['kunciMenu'], 'produk');
  });

  test('penyimpanan mengirim items dan nama properti yang diterima layanan',
      () {
    final hasil = siapkanShortcutUntukDisimpan([
      {
        'judul': 'Mutasi Barang',
        'ket': 'Kronologi stok',
        'kunciMenu': 'produk',
        'aktif': true,
      }
    ]).single;

    expect(hasil['deskripsi'], 'Kronologi stok');
    expect(hasil['aksesKunci'], 'produk');
    expect(hasil.containsKey('ket'), isFalse);
    expect(hasil.containsKey('kunciMenu'), isFalse);
  });

  test('pengaturan offline gagal tanpa mengganti cache tersimpan', () async {
    var cacheDiperbarui = false;
    await expectLater(
      jalankanAksiShortcutOnlineOnly(
        aksi: 'shortcut_menu_simpan',
        payload: const {'items': []},
        kirim: (_, __) async => throw Exception('offline'),
        setelahDikonfirmasi: (_) async => cacheDiperbarui = true,
      ),
      throwsException,
    );
    expect(cacheDiperbarui, isFalse);
    expect(kPesanShortcutBelumTersimpan, contains('belum tersimpan'));
  });

  test('cache baru berubah setelah server mengembalikan daftar kanonis',
      () async {
    var cacheDiperbarui = false;
    await jalankanAksiShortcutOnlineOnly(
      aksi: 'shortcut_menu_simpan',
      payload: const {'items': []},
      kirim: (_, __) async => {
        'status': '00',
        'semuaShortcut': [
          {'judul': 'Pintasan', 'deskripsi': 'Keterangan'}
        ],
        'data': <Map<String, dynamic>>[],
      },
      setelahDikonfirmasi: (_) async => cacheDiperbarui = true,
    );
    expect(cacheDiperbarui, isTrue);
  });
}
