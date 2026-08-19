import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:flutter_test/flutter_test.dart';

ApotikBarisKeranjang _baris({
  int id = 1,
  String nama = 'Paracetamol 500 mg',
  double qty = 1,
  double harga = 3000,
  bool terkendali = false,
  List<Map<String, dynamic>>? batch,
}) {
  return ApotikBarisKeranjang(
    item: <String, dynamic>{
      'id': id,
      'nama': nama,
      'terkendali': terkendali,
    },
    qty: qty,
    harga: harga,
    batch: batch,
  );
}

void main() {
  group('Pagar obat terkendali (dipertahankan dari perilaku existing)', () {
    test('menahan bayar bila nama pembeli kosong', () {
      final c = ApotikPosController()
        ..tambah(_baris(terkendali: true, nama: 'Codein'));
      final pagar = c.pagarBayar();
      expect(pagar.boleh, isFalse);
      expect(pagar.alasan.join(), contains('nama pembeli wajib'));
    });

    test('menahan bayar bila tanpa resep DAN tanpa nama dokter', () {
      final c = ApotikPosController()
        ..tambah(_baris(terkendali: true))
        ..namaPembeli = 'Budi';
      expect(c.pagarBayar().boleh, isFalse);
      expect(c.pagarBayar().alasan.join(), contains('nama dokter'));
    });

    test('lolos bila nama pembeli + nama dokter diisi', () {
      final c = ApotikPosController()
        ..tambah(_baris(terkendali: true))
        ..namaPembeli = 'Budi'
        ..namaDokter = 'dr. Sari';
      expect(c.pagarBayar().boleh, isTrue);
    });

    test('lolos bila nama pembeli + resep dipilih', () {
      final c = ApotikPosController()
        ..tambah(_baris(terkendali: true))
        ..namaPembeli = 'Budi'
        ..resepId = 77;
      expect(c.pagarBayar().boleh, isTrue);
    });

    test('obat non-terkendali tidak menuntut identitas pembeli', () {
      final c = ApotikPosController()..tambah(_baris());
      expect(c.pagarBayar().boleh, isTrue);
    });
  });

  group('Alokasi batch', () {
    test('menahan bayar bila alokasi batch kurang dari qty', () {
      final c = ApotikPosController()
        ..tambah(_baris(qty: 5, batch: [
          {'kadaluarsa_id': 9, 'qty': 3}
        ]));
      final pagar = c.pagarBayar();
      expect(pagar.boleh, isFalse);
      expect(pagar.alasan.join(), contains('belum sama dengan qty'));
    });

    test('lolos bila alokasi batch tepat menutup qty', () {
      final c = ApotikPosController()
        ..tambah(_baris(qty: 5, batch: [
          {'kadaluarsa_id': 9, 'qty': 2},
          {'kadaluarsa_id': 10, 'qty': 3},
        ]));
      expect(c.pagarBayar().boleh, isTrue);
    });

    test('baris tanpa batch dianggap lengkap (server yang memutuskan FEFO)',
        () {
      final c = ApotikPosController()..tambah(_baris(qty: 2));
      expect(c.pagarBayar().boleh, isTrue);
    });
  });

  group('Idempotency - perbaikan celah dobel-bayar', () {
    test('kode idempoten SAMA dipakai ulang saat retry setelah gagal', () {
      var detik = 1000;
      final c = ApotikPosController(
          jam: () => DateTime.fromMillisecondsSinceEpoch(detik++));
      c.tambah(_baris());

      expect(c.mulaiBayar(), isTrue);
      final kodePertama = c.payloadBayar()['kode'];

      c.tandaiGagal('Jaringan terputus.');
      c.siapkanUlang();

      expect(c.mulaiBayar(), isTrue);
      final kodeKedua = c.payloadBayar()['kode'];

      // Inti perbaikan: percobaan kedua HARUS memakai kode yang sama supaya
      // server mengenalinya sebagai kiriman ulang, bukan transaksi baru.
      expect(kodeKedua, kodePertama);
    });

    test('transaksi baru setelah dikosongkan memakai kode berbeda', () {
      var detik = 1000;
      final c = ApotikPosController(
          jam: () => DateTime.fromMillisecondsSinceEpoch(detik += 1000));
      c.tambah(_baris());
      c.mulaiBayar();
      final kodeLama = c.payloadBayar()['kode'];

      c.tandaiBerhasil();
      c.kosongkan();
      c.tambah(_baris());
      final kodeBaru = c.payloadBayar()['kode'];

      expect(kodeBaru, isNot(kodeLama));
    });
  });

  group('Anti double-submit', () {
    test('mulaiBayar ditolak saat status paymentPending', () {
      final c = ApotikPosController()..tambah(_baris());
      expect(c.mulaiBayar(), isTrue);
      expect(c.status, ApotikStatusTransaksi.paymentPending);
      // Ketukan kedua saat proses berjalan TIDAK boleh mengirim ulang.
      expect(c.mulaiBayar(), isFalse);
    });

    test('paymentPending mengunci tombol bayar', () {
      final c = ApotikPosController()..tambah(_baris());
      c.mulaiBayar();
      expect(c.status.bolehBayar, isFalse);
      expect(c.status.sedangProses, isTrue);
    });

    test('mulaiBayar ditolak bila pagar belum lolos', () {
      final c = ApotikPosController()..tambah(_baris(terkendali: true));
      expect(c.mulaiBayar(), isFalse);
      expect(c.status, isNot(ApotikStatusTransaksi.paymentPending));
    });
  });

  group('paidUnsynced tidak sama dengan paid', () {
    test('hanya paid yang dianggap dibukukan server', () {
      final c = ApotikPosController()..tambah(_baris());
      c.mulaiBayar();
      c.tandaiBelumTersinkron();
      expect(c.status, ApotikStatusTransaksi.paidUnsynced);
      expect(c.status.sudahDibukukanServer, isFalse);

      c.tandaiBerhasil();
      expect(c.status.sudahDibukukanServer, isTrue);
    });
  });

  group('Status transaksi mengikuti isi keranjang', () {
    test('idle saat kosong, readyToPay saat pagar lolos', () {
      final c = ApotikPosController();
      expect(c.status, ApotikStatusTransaksi.idle);
      c.tambah(_baris());
      expect(c.status, ApotikStatusTransaksi.readyToPay);
      c.hapus(0);
      expect(c.status, ApotikStatusTransaksi.idle);
    });

    test('open (belum siap bayar) saat pagar belum lolos', () {
      final c = ApotikPosController()..tambah(_baris(terkendali: true));
      expect(c.status, ApotikStatusTransaksi.open);
      expect(c.status.bolehBayar, isFalse);
    });

    test('hold lalu lanjutkan mengembalikan status yang benar', () {
      final c = ApotikPosController()..tambah(_baris());
      c.tahan();
      expect(c.status, ApotikStatusTransaksi.held);
      c.lanjutkan();
      expect(c.status, ApotikStatusTransaksi.readyToPay);
    });

    test('qty 0 menghapus baris', () {
      final c = ApotikPosController()..tambah(_baris());
      c.ubahQty(0, 0);
      expect(c.keranjang, isEmpty);
    });

    test('item sama tanpa batch digabung qty-nya', () {
      final c = ApotikPosController()
        ..tambah(_baris(id: 5, qty: 2))
        ..tambah(_baris(id: 5, qty: 3));
      expect(c.keranjang.length, 1);
      expect(c.keranjang.first.qty, 5);
    });
  });

  group('Mode transaksi', () {
    test('racikan dan produksi menahan bayar dengan alasan jujur', () {
      final c = ApotikPosController()
        ..tambah(_baris())
        ..mode = ApotikModePos.racikan;
      final pagar = c.pagarBayar();
      expect(pagar.boleh, isFalse);
      expect(pagar.alasan.join(), contains('belum tersedia dari server'));
      expect(ApotikModePos.racikan.didukungServer, isFalse);
      expect(ApotikModePos.otc.didukungServer, isTrue);
      expect(ApotikModePos.resep.didukungServer, isTrue);
    });
  });

  group('Payload apotik_bayar tetap sesuai kontrak server existing', () {
    test('menyusun kode, items, batch, pembeli, dan dokter', () {
      final c = ApotikPosController()
        ..tambah(_baris(id: 7, qty: 2, harga: 1500, batch: [
          {'kadaluarsa_id': 3, 'qty': 2, 'tanggal': '2027-01-01'}
        ]))
        ..namaPembeli = ' Budi '
        ..alamatPembeli = 'Jl. Mawar'
        ..namaDokter = ' dr. Sari '
        ..resepId = 12;

      final p = c.payloadBayar();
      expect(p['resep_id'], 12);
      expect((p['pembeli'] as Map)['nama'], 'Budi');
      expect(p['nama_dokter'], 'dr. Sari');

      final items = p['items'] as List;
      expect(items.length, 1);
      final it = items.first as Map;
      expect(it['item_id'], 7);
      expect(it['qty'], 2);
      expect(it['harga_satuan'], 1500);
      // Hanya kadaluarsa_id + qty yang dikirim, sama seperti layar lama.
      expect((it['batch'] as List).first, {'kadaluarsa_id': 3, 'qty': 2});
    });

    test('tidak mengirim pembeli/dokter bila kosong', () {
      final c = ApotikPosController()..tambah(_baris());
      final p = c.payloadBayar();
      expect(p.containsKey('pembeli'), isFalse);
      expect(p.containsKey('nama_dokter'), isFalse);
      expect(p.containsKey('resep_id'), isFalse);
    });
  });

  test('total keranjang dihitung dari qty x harga', () {
    final c = ApotikPosController()
      ..tambah(_baris(id: 1, qty: 2, harga: 1500))
      ..tambah(_baris(id: 2, qty: 3, harga: 1000));
    expect(c.total, 6000);
  });
}
