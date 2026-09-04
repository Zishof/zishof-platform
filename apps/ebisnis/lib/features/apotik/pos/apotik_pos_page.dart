import 'dart:async';

import 'package:core_hw/core_hw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api_client.dart';
import '../../../services/master_offline.dart';
import '../../../services/pengaturan_laci.dart';
import '../../../services/pengaturan_pembayaran.dart';
import '../../../services/pengaturan_struk.dart';
import '../../../sesi.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../core/apotik_lokal_dulu.dart';
import '../shared/widgets/apotik_context_bar.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/medication_card.dart';
import 'apotik_batch_sheet.dart';
import 'apotik_cart_panel.dart';
import 'apotik_mode_switcher.dart';
import 'apotik_pembayaran_sheet.dart';
import 'apotik_pembayaran_tertunda.dart';
import 'apotik_pos_state.dart';
import 'apotik_struk_teks.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Kontrak pemanggilan server, disuntik pada test agar tanpa jaringan.
typedef PanggilAksi = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// <h3>Ruang kerja kasir apotik (Fase 3, mockup 02).</h3>
///
/// Tiga area pada desktop ≥1280: **konteks+mode | katalog | keranjang**.
/// Di bawah itu keranjang menjadi lembar penuh yang dipanggil dari tombol
/// ringkasan melekat (sticky) — bukan desktop yang sekadar dipersempit.
///
/// Seluruh pagar keselamatan yang sudah terbukti DIPERTAHANKAN dan kini
/// ditegakkan lewat [ApotikPosController]: obat terkendali wajib identitas
/// pembeli + resep/dokter, batch kedaluwarsa & lot ditahan tidak dapat
/// dipilih (IR-02), baris racikan resep dilewati dengan pemberitahuan jujur,
/// dan kode idempoten dipakai ulang saat retry.
class ApotikPosPage extends StatefulWidget {
  final PanggilAksi? panggil;
  final ApotikPosController? controller;

  /// Pemuat katalog "lokal dulu". Hanya KATALOG yang dibaca dari cache;
  /// pembayaran tetap menuntut server (lihat core/apotik_lokal_dulu.dart).
  final MuatDaftarApotik? muatKatalog;

  const ApotikPosPage(
      {super.key, this.panggil, this.controller, this.muatKatalog});

  @override
  State<ApotikPosPage> createState() => _ApotikPosPageState();
}

class _ApotikPosPageState extends State<ApotikPosPage> {
  late final ApotikPosController _pos =
      widget.controller ?? ApotikPosController();
  late final PanggilAksi _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  /// Bila pemanggil menyuntik [panggil] (test atau penyematan), katalog dibaca
  /// lewat panggilan itu — sumber datanya memang sengaja diambil alih.
  /// Produksi tidak pernah menyuntiknya, sehingga jalur normalnya tetap
  /// lokal-dulu lewat `MasterOffline`.
  late final MuatDaftarApotik _muatKatalog = widget.muatKatalog ??
      (widget.panggil == null
          ? MasterOffline.daftarCacheDulu
          : _katalogLewatPanggil);

  Future<void> _katalogLewatPanggil(
    String aksi,
    Map<String, dynamic> body,
    String cacheKey, {
    required void Function(Map<String, dynamic> hasil) onData,
  }) async {
    final r = await _panggil(aksi, body);
    if (!_sukses(r)) {
      throw Exception('${r['description'] ?? 'Gagal memuat katalog obat.'}');
    }
    onData({...r, 'dariServer': true});
  }

  final _cari = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _hasilCari = [];

  /// true bila katalog yang sedang tampil berasal dari cache dan server belum
  /// menjawab. Ditandai di layar: stok dari cache bisa sudah basi.
  bool _katalogDariCache = false;
  List<MetodeBayar> _caraBayar = [];
  int? _caraBayarId;
  bool _memuatCari = false;
  String? _galatCari;

  /// Pembayaran yang nasibnya belum dipastikan (lihat
  /// [ApotikPembayaranTertundaStore]). Kosong pada keadaan normal.
  List<PembayaranTertunda> _tertunda = const [];
  bool _memeriksaTertunda = false;

  /// Struk transaksi terakhir di mesin ini — untuk cetak dan cetak ulang.
  /// Server belum menyimpan riwayat cetak (IR-08), jadi ini murni lokal.
  DataStruk? _strukTerakhir;

  /// Laci kasir memakai jalur RAW Windows (`core_hw`); di platform lain
  /// opsinya tidak ditawarkan sama sekali.
  bool get _laciTersedia => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _jalankanCari('');
    _muatCaraBayar();
    _muatTertunda();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cari.dispose();
    super.dispose();
  }

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  List<Map<String, dynamic>> _data(Map<String, dynamic> r) =>
      ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  /// IR-07: metode pembayaran diambil dari server; UI TIDAK boleh menawarkan
  /// metode yang tidak dikonfigurasi. Bila daftar kosong/gagal, alur bayar
  /// tetap jalan tanpa metode (kompatibel server lama).
  /// Preferensi lokal bersifat PELENGKAP: kegagalannya -- termasuk tidak
  /// adanya plugin sama sekali -- tidak boleh menggagalkan transaksi. Karena
  /// itu pembacaannya selalu diletakkan SETELAH hal yang wajib tampil, bukan
  /// sebagai syarat di depannya.
  Future<void> _prefsAman(Future<void> Function() kerja) async {
    try {
      await kerja();
    } catch (_) {
      // Abaikan: preferensi bersifat pelengkap, bukan syarat transaksi.
    }
  }

  Future<void> _muatCaraBayar() async {
    List<MetodeBayar> daftar;
    try {
      // Metode pembayaran adalah master yang jarang berubah: dibaca lokal-dulu
      // supaya lembar pembayaran tidak kehilangan pilihannya hanya karena
      // jaringan sedang tersendat.
      List<MetodeBayar>? terbaca;
      await _muatKatalog(
        'apotik_cara_bayar_list',
        const {},
        kunciCacheCaraBayarApotik,
        onData: (hasil) {
          final data = ((hasil['data'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => MetodeBayar.dariJson(Map<String, dynamic>.from(e)))
              .toList();
          if (data.isNotEmpty || hasil['dariServer'] == true) terbaca = data;
        },
      );
      if (terbaca == null) return;
      daftar = terbaca!;
    } catch (_) {
      // Server lama tanpa aksi ini: bukan galat yang perlu mengganggu kasir.
      return;
    }
    setStateIfMounted(() {
      _caraBayar = daftar;
      _caraBayarId = daftar.isEmpty ? null : (_caraBayarId ?? daftar.first.id);
    });
    // Metode bawaan pengguna dibaca SETELAH daftar tampil, supaya pembacaan
    // preferensi tidak pernah menunda munculnya pilihan metode.
    await _prefsAman(() async {
      await PengaturanPembayaran.instance.muat();
      final bawaan = PengaturanPembayaran.instance.caraBayarDefaultId;
      if (bawaan == null || !daftar.any((m) => m.id == bawaan)) return;
      setStateIfMounted(() => _caraBayarId = bawaan);
    });
  }

  Future<void> _muatTertunda() async {
    try {
      final daftar = await ApotikPembayaranTertundaStore.instance.muat();
      setStateIfMounted(() => _tertunda = daftar);
    } catch (_) {
      // Penyimpanan lokal tidak tersedia -- tidak boleh mengunci kasir.
    }
  }

  void _cariDebounce(String v) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _jalankanCari(v));
  }

  Future<void> _jalankanCari(String keyword) async {
    setStateIfMounted(() {
      _memuatCari = true;
      _galatCari = null;
    });
    try {
      // Katalog dibaca LOKAL DULU supaya kasir tetap dapat memeriksa harga dan
      // penanda keselamatan saat jaringan mati. Yang di-cache hanya katalog;
      // pembayaran tetap menuntut server.
      await _muatKatalog(
        'apotik_item_cari',
        {'keyword': keyword, 'page_size': 40},
        kunciCacheItemApotik,
        onData: (hasil) {
          if (!mounted) return;
          final dariServer = hasil['dariServer'] == true;
          final data = ((hasil['data'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setStateIfMounted(() {
            // Emisi cache disaring ulang: cache berisi hasil kueri TERAKHIR.
            _hasilCari = dariServer ? data : saringCacheLokal(data, keyword);
            _katalogDariCache = !dariServer;
            _memuatCari = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        // Katalog dari cache TIDAK dibuang saat server gagal; kasir masih
        // butuh melihat obatnya. Galat hanya bila tak ada apa pun.
        if (_hasilCari.isEmpty) _galatCari = '$e';
        _memuatCari = false;
      });
    }
  }

  void _pesan(String teks, {bool galat = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(teks),
      backgroundColor: galat ? Theme.of(context).colorScheme.error : null,
    ));
  }

  /// Menambah item ke keranjang; bila item ber-batch, kasir memilih batch
  /// lebih dulu (prefill FEFO) — sama seperti alur lama.
  Future<void> _tambahItem(Map<String, dynamic> item, {double qty = 1}) async {
    var batchTerpilih = <Map<String, dynamic>>[];
    try {
      final r = await _panggil('apotik_item_batch', {'item_id': item['id']});
      final batches = _data(r);
      if (batches.isNotEmpty && mounted) {
        final pilih = await showModalBottomSheet<List<Map<String, dynamic>>>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ApotikBatchSheet(
              namaItem: '${item['nama'] ?? '-'}',
              batches: batches,
              qtyDiminta: qty),
        );
        if (pilih == null) return; // kasir membatalkan
        batchTerpilih = pilih;
        qty = batchTerpilih.fold<double>(
            0, (a, b) => a + (((b['qty'] as num?) ?? 0).toDouble()));
      }
    } catch (e) {
      _pesan('Gagal memuat batch: $e', galat: true);
      return;
    }
    setStateIfMounted(() {
      _pos.tambah(ApotikBarisKeranjang(
        item: item,
        qty: qty,
        harga: ((item['hargaJual'] as num?) ?? 0).toDouble(),
        batch: batchTerpilih,
      ));
    });
  }

  Future<void> _ubahBatch(int indeks) async {
    final baris = _pos.keranjang[indeks];
    try {
      final r = await _panggil('apotik_item_batch', {'item_id': baris.itemId});
      final batches = _data(r);
      if (batches.isEmpty || !mounted) return;
      final pilih = await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ApotikBatchSheet(
            namaItem: baris.nama, batches: batches, qtyDiminta: baris.qty),
      );
      if (pilih == null) return;
      setStateIfMounted(() {
        baris.batch = pilih;
        baris.qty = pilih.fold<double>(
            0, (a, b) => a + (((b['qty'] as num?) ?? 0).toDouble()));
      });
    } catch (e) {
      _pesan('Gagal memuat batch: $e', galat: true);
    }
  }

  /// Tebus resep — alur dipertahankan dari layar lama, termasuk pemberitahuan
  /// JUJUR bahwa baris racikan dilewati (belum didukung server, IR-04).
  Future<void> _tebusResep() async {
    List<Map<String, dynamic>> daftar;
    try {
      // Antrean resep dibaca lokal-dulu; PENEBUSANnya tetap lewat server.
      Map<String, dynamic>? emisi;
      await _muatKatalog(
        'apotik_resep_list',
        {'hanya_menunggu': true, 'page_size': 50},
        kunciCacheResepApotik(hanyaMenunggu: true),
        onData: (hasil) => emisi = hasil,
      );
      final r = <String, dynamic>{'status': '00', ...?emisi};
      daftar = _data(r);
    } catch (e) {
      _pesan('Gagal memuat resep: $e', galat: true);
      return;
    }
    if (!mounted) return;
    if (daftar.isEmpty) {
      _pesan('Tidak ada resep yang menunggu ditebus.');
      return;
    }
    final resep = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetResep(daftar: daftar),
    );
    if (resep == null || !mounted) return;
    try {
      final detail =
          await _panggil('apotik_resep_detail', {'resep_id': resep['id']});
      final rows = _data(detail);
      if (detail['adaRacikan'] == true) {
        _pesan('Resep memuat RACIKAN — baris racikan belum bisa diserahkan '
            'lewat kasir ini dan dilewati.');
      }
      setStateIfMounted(() {
        _pos.mode = ApotikModePos.resep;
        _pos.resepId = resep['id'];
        _pos.resepKode = '${resep['kode'] ?? ''}';
      });
      for (final r in rows.where((r) => r['racikan'] != true)) {
        await _tambahItem({
          'id': r['itemId'],
          'kode': r['kode'],
          'nama': r['nama'],
          'satuan': r['satuan'],
          'hargaJual': r['hargaJual'],
          'stok': r['stok'],
          'golonganObat': r['golonganObat'],
          'terkendali': r['terkendali'],
          'lasa': r['lasa'],
          'bentukSediaan': r['bentukSediaan'],
          'kekuatan': r['kekuatan'],
          'highAlert': r['highAlert'],
          'coldChain': r['coldChain'],
        }, qty: ((r['jumlah'] as num?) ?? 1).toDouble());
      }
    } catch (e) {
      _pesan('Gagal muat resep: $e', galat: true);
    }
  }

  /// Membuka lembar pembayaran bila memang ADA yang perlu diputuskan
  /// (server mengirim daftar metode). Bila server tidak mengirim metode apa
  /// pun, tidak ada pilihan untuk ditawarkan dan transaksi dikirim langsung --
  /// perilaku yang sama persis dengan sebelum Fase 6.
  Future<void> _bayar() async {
    if (!_pos.pagarBayar().boleh) {
      setStateIfMounted(() {});
      return;
    }
    if (_caraBayar.isEmpty) {
      await _kirimBayar(null);
      return;
    }
    final hasil = await showModalBottomSheet<HasilPembayaran>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ApotikPembayaranSheet(
        total: _pos.total,
        metode: _caraBayar,
        metodeAwalId: _caraBayarId,
        laciTersedia: _laciTersedia,
      ),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() => _caraBayarId = hasil.caraBayarId);
    await _kirimBayar(hasil);
  }

  Future<void> _kirimBayar(HasilPembayaran? bayar) async {
    // mulaiBayar() menolak panggilan kedua saat proses berjalan dan menolak
    // bila pagar belum lolos -- inti pencegahan double-submit.
    if (!_pos.mulaiBayar()) return;
    setStateIfMounted(() {});
    final payload = _pos.payloadBayar();
    final caraId = bayar?.caraBayarId ?? _caraBayarId;
    if (caraId != null) payload['cara_bayar_id'] = caraId;
    final referensi = bayar?.referensi ?? '';
    if (referensi.isNotEmpty) payload['referensi_bayar'] = referensi;
    // IR-11: rincian pembayaran dikirim SEKALIGUS dengan cara_bayar_id
    // tunggal di atas. Server baru memakai larik ini (termasuk untuk
    // pembayaran terpisah dan pencatatan uang diterima/kembalian); server
    // lama mengabaikannya dan tetap membukukan metode pertama, bukan
    // kehilangan jejak metode sama sekali.
    if (bayar != null && bayar.baris.isNotEmpty) {
      payload['pembayaran'] = bayar.payloadPembayaran();
      if (bayar.baris.length == 1 && bayar.baris.first.metode.adaKembalian) {
        payload['tunai'] = bayar.tunai;
        payload['kembalian'] = bayar.kembalian;
      }
    }
    final kodeKirim = '${payload['kode']}';
    try {
      final r = await _panggil('apotik_bayar', payload);
      if (!_sukses(r)) {
        // Penolakan BISNIS: server sadar menolak, jadi tidak ada transaksi
        // yang terbukukan. Pesannya ditampilkan APA ADANYA.
        setStateIfMounted(() => _pos.tandaiGagal(
            '${r['description'] ?? 'Pembayaran ditolak server.'}'));
        return;
      }
      final total = ((r['total'] as num?) ?? _pos.total).toDouble();
      final struk = _rakitStruk(r, bayar, total);
      _pos.tandaiBerhasil();
      // Bila transaksi ini sempat masuk antrean "belum dipastikan", nasibnya
      // kini jelas -- keluarkan dari antrean. Pembersihan ini tidak boleh
      // menunda struk & dialog di depan kasir.
      unawaited(_lupakanTertunda(kodeKirim));
      if (bayar?.bukaLaci == true) unawaited(_bukaLaci());
      setStateIfMounted(() => _strukTerakhir = struk);
      if (mounted) await _dialogBerhasil(struk, bayar);
      setStateIfMounted(() => _pos.kosongkan());
    } on ApiException catch (e) {
      if (e.offline) {
        // TIDAK DIKETAHUI, bukan "gagal": permintaan mungkin sudah sampai dan
        // terbukukan. Menyebutnya gagal akan mendorong kasir menjual dua kali.
        await _catatTertunda(kodeKirim, payload);
        setStateIfMounted(() => _pos.tandaiBelumTersinkron());
        if (mounted) await _dialogTidakPasti(e.pesan);
        return;
      }
      setStateIfMounted(() => _pos.tandaiGagal(e.pesan));
    } catch (e) {
      // Kode idempoten SENGAJA dipertahankan supaya percobaan ulang dikenali
      // server sebagai kiriman yang sama.
      setStateIfMounted(() => _pos.tandaiGagal('$e'));
    } finally {
      if (_pos.status == ApotikStatusTransaksi.paymentFailed) {
        setStateIfMounted(() => _pos.siapkanUlang());
      }
    }
  }

  DataStruk _rakitStruk(
      Map<String, dynamic> r, HasilPembayaran? bayar, double total) {
    return DataStruk(
      namaApotek: Sesi.instance.tokoNama,
      alamat: Sesi.instance.tokoAlamat,
      telepon: Sesi.instance.tokoTelp,
      kodeTransaksi: '${r['kode'] ?? _pos.kodeIdempoten()}',
      waktu: DateTime.now(),
      kasir: Sesi.instance.userId,
      baris: [
        for (final b in _pos.keranjang)
          BarisStruk(nama: b.nama, qty: b.qty, harga: b.harga),
      ],
      total: total,
      metode: '${r['caraBayar'] ?? bayar?.namaMetode ?? ''}',
      rincianMetode: [
        for (final b in (bayar?.baris ?? const []))
          BarisBayarStruk(nama: b.metode.nama, nominal: b.nominal),
      ],
      tunai: bayar?.tunai ?? 0,
      kembalian: bayar?.kembalian ?? 0,
      referensi: bayar?.referensi ?? '',
      catatanKaki: Sesi.instance.pesanTerimaKasih,
    );
  }

  Future<void> _dialogBerhasil(DataStruk struk, HasilPembayaran? bayar) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Transaksi Berhasil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kode: ${struk.kodeTransaksi}'),
            Text('Total: ${_rp.format(struk.total)}'),
            if (struk.metode.isNotEmpty) Text('Metode: ${struk.metode}'),
            if ((bayar?.kembalian ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Kembalian: ${_rp.format(bayar!.kembalian)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        actions: [
          if (_laciTersedia)
            TextButton(
                onPressed: () => _cetakStruk(struk),
                child: const Text('Cetak Struk')),
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _dialogTidakPasti(String pesan) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Belum Dapat Dipastikan'),
        content: Text(
            'Server tidak terjangkau saat pembayaran dikirim, sehingga BELUM '
            'diketahui apakah transaksi sudah terbukukan.\n\n$pesan\n\n'
            'Jangan mengulang penjualan ini secara manual. Gunakan "Periksa '
            'ke server" pada bilah kuning di atas untuk memastikannya; '
            'kiriman ulang memakai kode yang sama sehingga tidak akan '
            'terbukukan dua kali.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Mengerti')),
        ],
      ),
    );
  }

  Future<void> _catatTertunda(String kode, Map<String, dynamic> payload) async {
    try {
      await ApotikPembayaranTertundaStore.instance.catat(PembayaranTertunda(
        kode: kode,
        payload: payload,
        total: _pos.total,
        waktu: DateTime.now(),
      ));
    } catch (_) {
      // Gagal menulis antrean tidak boleh menelan pesan utama ke kasir.
    }
    await _muatTertunda();
  }

  Future<void> _lupakanTertunda(String kode) async {
    try {
      await ApotikPembayaranTertundaStore.instance.hapus(kode);
    } catch (_) {
      // abaikan
    }
    await _muatTertunda();
  }

  /// Memastikan nasib SELURUH pembayaran yang menggantung dengan mengirim
  /// ulang payload yang sama (server idempoten terhadap `kode`).
  Future<void> _periksaTertunda() async {
    if (_memeriksaTertunda) return;
    setStateIfMounted(() => _memeriksaTertunda = true);
    final laporan = <String>[];
    var adaYangTerbukukan = false;
    try {
      for (final p in List<PembayaranTertunda>.from(_tertunda)) {
        final h = await ApotikPembayaranTertundaStore.instance
            .periksaUlang(p, _panggil);
        laporan.add(h.pesan);
        if (h.status == StatusPeriksaUlang.sudahTerbukukan ||
            h.status == StatusPeriksaUlang.baruTerbukukan) {
          adaYangTerbukukan = true;
          if (p.kode == _pos.kodeIdempoten()) {
            // Transaksi di layar inilah yang ternyata terbukukan -- kosongkan
            // keranjang supaya tidak dijual ulang.
            setStateIfMounted(() => _pos.kosongkan());
          }
        }
      }
    } finally {
      setStateIfMounted(() => _memeriksaTertunda = false);
      await _muatTertunda();
    }
    if (!mounted || laporan.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
            adaYangTerbukukan ? 'Hasil Pemeriksaan' : 'Belum Ada Kepastian'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final l in laporan) Text('\u2022 $l')],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _bukaLaci() async {
    try {
      await _prefsAman(() => PengaturanLaci.instance.muat());
      await bukaLaciKasir(
          pinAlternatif: PengaturanLaci.instance.pinAlternatif,
          namaPrinter: PengaturanLaci.instance.namaPrinter);
    } catch (e) {
      if (!mounted) return;
      _pesan('Gagal membuka laci: $e', galat: true);
    }
  }

  /// Cetak LOKAL lewat jalur RAW ESC/POS. Server tidak menyimpan riwayat
  /// cetak (IR-08), jadi tidak ada klaim apa pun soal itu di layar.
  Future<void> _cetakStruk(DataStruk struk, {bool cetakUlang = false}) async {
    try {
      // Pakai lebar bawaan bila preferensi belum tersedia.
      var lebarMm = 58.0;
      await _prefsAman(() async {
        await PengaturanStruk.instance.muat();
        lebarMm = PengaturanStruk.instance.lebarKertasMm;
      });
      final data = cetakUlang ? _salinCetakUlang(struk) : struk;
      final baris = ApotikStrukTeks.susun(data,
          kolom: ApotikStrukTeks.kolomUntukKertas(lebarMm));
      await cetakRawKasir(ApotikStrukTeks.keEscPos(baris),
          namaPrinter: PengaturanLaci.instance.namaPrinter,
          namaDokumen: 'Struk Apotik ${data.kodeTransaksi}');
      if (!mounted) return;
      _pesan('Struk ${data.kodeTransaksi} dikirim ke printer.');
    } catch (e) {
      if (!mounted) return;
      _pesan('Gagal mencetak struk: $e', galat: true);
    }
  }

  DataStruk _salinCetakUlang(DataStruk s) => DataStruk(
        namaApotek: s.namaApotek,
        alamat: s.alamat,
        telepon: s.telepon,
        kodeTransaksi: s.kodeTransaksi,
        waktu: s.waktu,
        kasir: s.kasir,
        baris: s.baris,
        total: s.total,
        metode: s.metode,
        rincianMetode: s.rincianMetode,
        tunai: s.tunai,
        kembalian: s.kembalian,
        referensi: s.referensi,
        catatanKaki: s.catatanKaki,
        cetakUlang: true,
      );

  /// Bilah peringatan pembayaran yang nasibnya belum diketahui. Sengaja
  /// MELEKAT di atas layar: selama ini belum jelas, kasir tidak boleh
  /// menganggap transaksinya batal.
  Widget _bilahTertunda(ApotikDesignTokens t) {
    return Material(
      color: t.warning.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(children: [
          Icon(Icons.sync_problem, size: 18, color: t.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_tertunda.length} pembayaran belum dipastikan terbukukan. '
              'Jangan jual ulang -- periksa dulu.',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _memeriksaTertunda ? null : _periksaTertunda,
            child:
                Text(_memeriksaTertunda ? 'Memeriksa...' : 'Periksa ke server'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return ApotikResponsive(
      builder: (context, layout) {
        return Scaffold(
          backgroundColor: t.surfaceMuted,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _contextBar(),
              if (_tertunda.isNotEmpty) _bilahTertunda(t),
              Expanded(
                child:
                    layout.bolehTigaArea ? _tigaArea(t) : _satuKolom(t, layout),
              ),
            ],
          ),
          bottomNavigationBar: layout.bolehTigaArea ? null : _aksiMelekat(t),
        );
      },
    );
  }

  Widget _contextBar() {
    final s = Sesi.instance;
    return ApotikContextBar(ruas: [
      ApotikKonteksRuas(
          ikon: Icons.local_pharmacy_outlined,
          label: 'Apotek',
          nilai: s.tokoNama),
      ApotikKonteksRuas(
          ikon: Icons.person_outline, label: 'Kasir', nilai: s.userId),
      if (_pos.resepKode.isNotEmpty)
        ApotikKonteksRuas(
            ikon: Icons.description_outlined,
            label: 'Resep',
            nilai: _pos.resepKode),
    ]);
  }

  /// Desktop ≥1280: konteks+mode | katalog | keranjang.
  Widget _tigaArea(ApotikDesignTokens t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 260, child: _panelKonteks(t)),
        Expanded(child: _panelKatalog(t)),
        SizedBox(width: 380, child: _panelKeranjang()),
      ],
    );
  }

  /// Tablet/desktop sempit/mobile: satu kolom + keranjang lewat lembar penuh.
  Widget _satuKolom(ApotikDesignTokens t, ApotikLayout layout) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(ApotikBreakpoints.paddingHalaman(layout),
              12, ApotikBreakpoints.paddingHalaman(layout), 0),
          child: ApotikModeSwitcher(
            aktif: _pos.mode,
            onPilih: (m) => setStateIfMounted(() => _pos.mode = m),
          ),
        ),
        Expanded(child: _panelKatalog(t)),
      ],
    );
  }

  Widget _panelKonteks(ApotikDesignTokens t) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text('Mode transaksi',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textSecondary)),
          const SizedBox(height: 8),
          ApotikModeSwitcher(
            aktif: _pos.mode,
            onPilih: (m) => setStateIfMounted(() => _pos.mode = m),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _tebusResep,
            icon: const Icon(Icons.description_outlined, size: 17),
            label: const Text('Tebus Resep'),
          ),
          const SizedBox(height: 16),
          if (_caraBayar.isNotEmpty) ...[
            Text('Metode pembayaran',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _caraBayarId,
              isExpanded: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
              items: _caraBayar
                  .map((c) => DropdownMenuItem<int>(
                      value: c.id,
                      child: Text(c.nama.isEmpty ? '-' : c.nama,
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setStateIfMounted(() => _caraBayarId = v),
            ),
            Text(
                'Metode dapat diganti lagi saat membayar, lengkap dengan '
                'uang diterima dan kembalian.',
                style: TextStyle(fontSize: 11, color: t.textSecondary)),
            const SizedBox(height: 16),
          ],
          if (_strukTerakhir != null) ...[
            OutlinedButton.icon(
              onPressed: () => _cetakStruk(_strukTerakhir!, cetakUlang: true),
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: Text('Cetak Ulang ${_strukTerakhir!.kodeTransaksi}'),
            ),
            const SizedBox(height: 16),
          ],
          _identitasPembeli(t),
        ],
      ),
    );
  }

  /// Identitas pembeli — WAJIB untuk obat terkendali (pagar dipertahankan).
  Widget _identitasPembeli(ApotikDesignTokens t) {
    final wajib = _pos.adaTerkendali;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Flexible(
            child: Text('Identitas pembeli',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary)),
          ),
          if (wajib) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 13, color: t.danger),
          ],
        ]),
        if (wajib)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
                'Ada obat terkendali di keranjang — nama pembeli wajib, plus '
                'resep atau nama dokter.',
                style: TextStyle(fontSize: 11, color: t.dangerText)),
          ),
        const SizedBox(height: 6),
        TextField(
          decoration: const InputDecoration(
              labelText: 'Nama pembeli',
              border: OutlineInputBorder(),
              isDense: true),
          onChanged: (v) => setStateIfMounted(() => _pos.namaPembeli = v),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
              labelText: 'Nama dokter',
              border: OutlineInputBorder(),
              isDense: true),
          onChanged: (v) => setStateIfMounted(() => _pos.namaDokter = v),
        ),
      ],
    );
  }

  Widget _panelKatalog(ApotikDesignTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _cari,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Cari nama obat, kode, atau pindai barcode…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _memuatCari
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
            onChanged: _cariDebounce,
            onSubmitted: _jalankanCari,
          ),
        ),
        if (_katalogDariCache) _bilahKatalogCache(t),
        Expanded(
          child: _galatCari != null
              ? ApotikErrorState(
                  pesan: _galatCari!,
                  onCobaLagi: () => _jalankanCari(_cari.text))
              : (_memuatCari && _hasilCari.isEmpty)
                  ? const ApotikLoadingState(pesan: 'Memuat katalog obat…')
                  : _hasilCari.isEmpty
                      ? const ApotikEmptyState(
                          ikon: Icons.medication_outlined,
                          judul: 'Obat tidak ditemukan',
                          petunjuk:
                              'Coba kata kunci lain, atau pindai barcode pada '
                              'kemasan obat.')
                      : _gridObat(t),
        ),
      ],
    );
  }

  /// Penanda katalog dari cache. Kasir HARUS tahu angka stoknya belum tentu
  /// mutakhir — tanpa ini, data lama tampak sama meyakinkannya dengan data
  /// baru, dan itu jenis kesalahan yang tidak terlihat sampai obatnya ternyata
  /// tidak ada.
  Widget _bilahKatalogCache(ApotikDesignTokens t) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.cloud_off_outlined, size: 15, color: t.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Katalog dari data terakhir — stok belum tentu mutakhir. '
            'Pembayaran tetap memerlukan server.',
            style: TextStyle(fontSize: 11.5, color: t.textPrimary),
          ),
        ),
      ]),
    );
  }

  Widget _gridObat(ApotikDesignTokens t) {
    return LayoutBuilder(builder: (context, c) {
      final kolom = (c.maxWidth / 320).floor().clamp(1, 4);
      const jarak = ApotikDesignTokens.gridSpacing;
      final lebar = (c.maxWidth - 28 - jarak * (kolom - 1)) / kolom;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        child: Wrap(
          spacing: jarak,
          runSpacing: jarak,
          children: [
            for (final item in _hasilCari)
              SizedBox(
                width: lebar,
                child: MedicationCard(
                  item: item,
                  onTap: () => _tambahItem(item),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _panelKeranjang() {
    return ApotikCartPanel(
      pos: _pos,
      onUbahQty: (i, q) => setStateIfMounted(() => _pos.ubahQty(i, q)),
      onHapus: (i) => setStateIfMounted(() => _pos.hapus(i)),
      onPilihBatch: _ubahBatch,
      onBayar: _bayar,
      onTahan: () => setStateIfMounted(() => _pos.tahan()),
      onLanjutkan: () => setStateIfMounted(() => _pos.lanjutkan()),
    );
  }

  /// Sticky action bar mobile/tablet: ringkasan + buka keranjang penuh.
  Widget _aksiMelekat(ApotikDesignTokens t) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_pos.keranjang.length} item',
                    style: TextStyle(fontSize: 11, color: t.textSecondary)),
                Text(_rp.format(_pos.total),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary)),
              ],
            ),
          ),
          SizedBox(
            height: ApotikBreakpoints.targetSentuhMinimum,
            child: FilledButton.icon(
              onPressed: _pos.keranjang.isEmpty ? null : _bukaKeranjangPenuh,
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('Keranjang'),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _bukaKeranjangPenuh() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => FractionallySizedBox(
          heightFactor: 0.92,
          child: ApotikCartPanel(
            pos: _pos,
            onUbahQty: (i, q) {
              _pos.ubahQty(i, q);
              setSheet(() {});
              setStateIfMounted(() {});
            },
            onHapus: (i) {
              _pos.hapus(i);
              setSheet(() {});
              setStateIfMounted(() {});
            },
            onPilihBatch: (i) async {
              await _ubahBatch(i);
              setSheet(() {});
            },
            onBayar: () async {
              // Navigator diambil SEBELUM await -- context lembar tidak boleh
              // dipakai lagi setelah gap async (use_build_context_synchronously).
              final navigator = Navigator.of(context);
              await _bayar();
              setSheet(() {});
              // Tutup lembar hanya bila transaksi benar-benar selesai
              // (keranjang dikosongkan); gagal bayar tetap membuka lembar
              // supaya kasir membaca alasannya.
              if (_pos.keranjang.isEmpty) navigator.pop();
            },
            onTahan: () {
              _pos.tahan();
              setSheet(() {});
            },
            onLanjutkan: () {
              _pos.lanjutkan();
              setSheet(() {});
            },
          ),
        ),
      ),
    );
    setStateIfMounted(() {});
  }
}

/// Lembar pilih resep menunggu tebus.
class _SheetResep extends StatelessWidget {
  final List<Map<String, dynamic>> daftar;
  const _SheetResep({required this.daftar});

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, sc) => ListView.separated(
        controller: sc,
        padding: const EdgeInsets.all(16),
        itemCount: daftar.length + 1,
        separatorBuilder: (_, __) => Divider(height: 1, color: t.border),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Resep Menunggu Ditebus',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: t.textPrimary)),
            );
          }
          final r = daftar[i - 1];
          return ListTile(
            dense: true,
            leading: Icon(Icons.description_outlined, color: t.clinicalPurple),
            title: Text('${r['kode'] ?? r['id']}'),
            subtitle: Text([
              if ('${r['diagnosa'] ?? ''}'.trim().isNotEmpty)
                '${r['diagnosa']}',
              if (r['jumlahBaris'] != null) '${r['jumlahBaris']} baris',
            ].join(' • ')),
            onTap: () => Navigator.pop(context, r),
          );
        },
      ),
    );
  }
}
