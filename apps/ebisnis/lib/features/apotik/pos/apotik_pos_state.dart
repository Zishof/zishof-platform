/// <h3>State machine transaksi POS Apotik (§11.1 dokumen modernisasi).</h3>
///
/// Menggantikan kumpulan boolean (`_memproses`, `_adaTerkendali`, …) yang bisa
/// saling bertentangan. Pure Dart tanpa Flutter supaya dapat diuji langsung.
library;

/// Mode transaksi eksplisit (§ "Mode transaksi eksplisit").
enum ApotikModePos {
  otc,
  resep,
  racikan,
  produksi;

  String get label => switch (this) {
        ApotikModePos.otc => 'OTC / Obat Bebas',
        ApotikModePos.resep => 'Resep Dokter',
        ApotikModePos.racikan => 'Racikan',
        ApotikModePos.produksi => 'Produksi Farmasi',
      };

  /// Mode yang BELUM didukung server (racikan/produksi belum punya aksi tulis).
  /// Dipakai UI untuk menampilkan alasan jujur, bukan tombol yang tidak menulis
  /// apa pun — lihat IR-04 pada docs/apotik-uiux/02-api-action-map.md.
  bool get didukungServer =>
      this == ApotikModePos.otc || this == ApotikModePos.resep;

  String get alasanBelumDidukung => switch (this) {
        ApotikModePos.racikan =>
          'Dispensing racikan belum tersedia dari server (IR-04). '
              'Baris racikan pada resep tetap ditampilkan terkunci.',
        ApotikModePos.produksi =>
          'Produksi farmasi belum tersedia dari server (IR-04).',
        _ => '',
      };
}

enum ApotikStatusTransaksi {
  idle,
  open,
  held,
  approvalRequired,
  readyToPay,
  paymentPending,
  paid,
  paidUnsynced,
  paymentFailed;

  /// Tombol bayar HARUS terkunci selama proses berjalan — pagar utama
  /// anti double-submit.
  bool get bolehBayar => this == ApotikStatusTransaksi.readyToPay;

  /// `paidUnsynced` sengaja TIDAK dianggap sama dengan `paid`: struk boleh
  /// dicetak, tetapi UI tidak boleh mengklaim server sudah membukukan.
  bool get sudahDibukukanServer => this == ApotikStatusTransaksi.paid;

  bool get sedangProses => this == ApotikStatusTransaksi.paymentPending;
}

/// Satu baris keranjang beserta batch terpilih.
class ApotikBarisKeranjang {
  final Map<String, dynamic> item;
  double qty;
  double harga;

  /// Batch terpilih: `[{kadaluarsa_id, qty, tanggal}]` — bentuk yang sama
  /// dengan yang dikirim ke `apotik_bayar` pada implementasi existing.
  List<Map<String, dynamic>> batch;

  ApotikBarisKeranjang({
    required this.item,
    this.qty = 1,
    this.harga = 0,
    List<Map<String, dynamic>>? batch,
  }) : batch = batch ?? <Map<String, dynamic>>[];

  Object? get itemId => item['id'];
  bool get terkendali => item['terkendali'] == true;
  bool get lasa => item['lasa'] == true;
  String get nama => '${item['nama'] ?? '-'}';
  double get subtotal => qty * harga;

  /// Jumlah unit yang sudah dialokasikan ke batch tertentu.
  double get qtyBatchTeralokasi => batch.fold<double>(
      0, (a, b) => a + (((b['qty'] as num?) ?? 0).toDouble()));

  /// Batch wajib menutup seluruh qty. Bila kurang, server akan menolak —
  /// UI menahannya lebih dulu supaya kasir tahu sebabnya.
  bool get batchLengkap =>
      batch.isEmpty || (qtyBatchTeralokasi - qty).abs() < 0.0001;
}

/// Hasil pemeriksaan pagar sebelum boleh membayar.
class ApotikPagarBayar {
  final bool boleh;
  final List<String> alasan;
  const ApotikPagarBayar(this.boleh, this.alasan);
}

/// Kontroler transaksi POS: memegang status, keranjang, identitas pembeli,
/// dan **kunci idempotency**.
///
/// PERBAIKAN PENTING vs implementasi lama: kode idempoten dibuat sekali per
/// SIKLUS transaksi dan DIPAKAI ULANG saat retry. Pada layar lama kode dibuat
/// di dalam `_bayar()` sehingga percobaan kedua setelah gagal mengirim kode
/// BARU — server tidak dapat mengenalinya sebagai kiriman ulang, sehingga ada
/// risiko transaksi ganda.
class ApotikPosController {
  ApotikPosController({DateTime Function()? jam}) : _jam = jam ?? DateTime.now;

  final DateTime Function() _jam;

  ApotikStatusTransaksi status = ApotikStatusTransaksi.idle;
  ApotikModePos mode = ApotikModePos.otc;
  final List<ApotikBarisKeranjang> keranjang = <ApotikBarisKeranjang>[];

  String namaPembeli = '';
  String alamatPembeli = '';
  String namaDokter = '';
  Object? resepId;
  String resepKode = '';

  /// Pesan penahan terakhir dari server, ditampilkan APA ADANYA.
  String? pesanPenahan;

  String? _kodeIdempoten;

  /// Kunci idempotency siklus berjalan; dibuat saat pertama dibutuhkan lalu
  /// dipertahankan sampai transaksi benar-benar sukses/dibatalkan.
  String kodeIdempoten() =>
      _kodeIdempoten ??= 'APT${_jam().millisecondsSinceEpoch}';

  bool get adaTerkendali => keranjang.any((b) => b.terkendali);
  double get total => keranjang.fold<double>(0, (a, b) => a + b.subtotal);

  void _segarkanStatus() {
    if (status == ApotikStatusTransaksi.paymentPending) return;
    if (keranjang.isEmpty) {
      status = ApotikStatusTransaksi.idle;
      return;
    }
    status = pagarBayar().boleh
        ? ApotikStatusTransaksi.readyToPay
        : ApotikStatusTransaksi.open;
  }

  void tambah(ApotikBarisKeranjang baris) {
    final adaIndeks = keranjang
        .indexWhere((b) => b.itemId != null && b.itemId == baris.itemId);
    if (adaIndeks >= 0 && baris.batch.isEmpty) {
      keranjang[adaIndeks].qty += baris.qty;
    } else {
      keranjang.add(baris);
    }
    _segarkanStatus();
  }

  void ubahQty(int indeks, double qty) {
    if (indeks < 0 || indeks >= keranjang.length) return;
    if (qty <= 0) {
      keranjang.removeAt(indeks);
    } else {
      keranjang[indeks].qty = qty;
    }
    _segarkanStatus();
  }

  void hapus(int indeks) {
    if (indeks < 0 || indeks >= keranjang.length) return;
    keranjang.removeAt(indeks);
    _segarkanStatus();
  }

  void kosongkan() {
    keranjang.clear();
    resepId = null;
    resepKode = '';
    namaPembeli = '';
    alamatPembeli = '';
    namaDokter = '';
    pesanPenahan = null;
    _kodeIdempoten = null;
    status = ApotikStatusTransaksi.idle;
  }

  /// Tahan transaksi (hold) — keranjang dipertahankan, status jelas.
  void tahan() {
    if (keranjang.isEmpty) return;
    status = ApotikStatusTransaksi.held;
  }

  void lanjutkan() {
    if (status != ApotikStatusTransaksi.held) return;
    _segarkanStatus();
  }

  /// Pagar keselamatan sebelum bayar. Mengembalikan SELURUH alasan sekaligus
  /// supaya kasir tidak memperbaiki satu per satu.
  ApotikPagarBayar pagarBayar() {
    final alasan = <String>[];
    if (keranjang.isEmpty) {
      alasan.add('Keranjang masih kosong.');
    }
    // Pagar obat terkendali — dipertahankan PERSIS dari perilaku existing.
    if (adaTerkendali) {
      if (namaPembeli.trim().isEmpty) {
        alasan.add('Obat terkendali: nama pembeli wajib diisi.');
      }
      if (resepId == null && namaDokter.trim().isEmpty) {
        alasan.add(
            'Obat terkendali: pilih resep atau isi nama dokter penulis resep.');
      }
    }
    for (final b in keranjang) {
      if (!b.batchLengkap) {
        alasan.add(
            '${b.nama}: alokasi batch (${b.qtyBatchTeralokasi.toStringAsFixed(0)}) '
            'belum sama dengan qty (${b.qty.toStringAsFixed(0)}).');
      }
    }
    if (!mode.didukungServer) {
      alasan.add(mode.alasanBelumDidukung);
    }
    return ApotikPagarBayar(alasan.isEmpty, alasan);
  }

  /// Menandai mulai mengirim pembayaran. Mengembalikan false bila sedang
  /// diproses atau pagar belum lolos — pemanggil TIDAK boleh mengirim.
  bool mulaiBayar() {
    if (status.sedangProses) return false;
    if (!pagarBayar().boleh) return false;
    status = ApotikStatusTransaksi.paymentPending;
    pesanPenahan = null;
    // Pastikan kode dibuat sebelum kirim pertama; percobaan berikutnya
    // memakai kode yang SAMA karena tidak pernah di-reset di sini.
    kodeIdempoten();
    return true;
  }

  void tandaiBerhasil() {
    status = ApotikStatusTransaksi.paid;
  }

  /// Tersimpan lokal/antre tetapi BELUM dikonfirmasi server.
  void tandaiBelumTersinkron() {
    status = ApotikStatusTransaksi.paidUnsynced;
  }

  /// Gagal — kode idempoten SENGAJA dipertahankan supaya percobaan ulang
  /// dikenali server sebagai kiriman yang sama.
  void tandaiGagal(String pesanServer) {
    status = ApotikStatusTransaksi.paymentFailed;
    pesanPenahan = pesanServer;
  }

  /// Siap mencoba lagi setelah gagal; kode idempoten tetap.
  void siapkanUlang() {
    if (status != ApotikStatusTransaksi.paymentFailed) return;
    _segarkanStatus();
  }

  /// Payload `apotik_bayar` — bentuknya dijaga identik dengan implementasi
  /// existing agar kontrak server tidak berubah diam-diam.
  Map<String, dynamic> payloadBayar() {
    return <String, dynamic>{
      'kode': kodeIdempoten(),
      if (resepId != null) 'resep_id': resepId,
      if (namaPembeli.trim().isNotEmpty || alamatPembeli.trim().isNotEmpty)
        'pembeli': {
          'nama': namaPembeli.trim(),
          'alamat': alamatPembeli.trim(),
        },
      if (namaDokter.trim().isNotEmpty) 'nama_dokter': namaDokter.trim(),
      'items': keranjang
          .map((b) => <String, dynamic>{
                'item_id': b.itemId,
                'qty': b.qty,
                'harga_satuan': b.harga,
                if (b.batch.isNotEmpty)
                  'batch': b.batch
                      .map((x) => {
                            'kadaluarsa_id': x['kadaluarsa_id'],
                            'qty': x['qty'],
                          })
                      .toList(),
              })
          .toList(),
    };
  }
}
