import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api_client.dart';
import '../../../sesi.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_context_bar.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/medication_card.dart';
import 'apotik_batch_sheet.dart';
import 'apotik_cart_panel.dart';
import 'apotik_mode_switcher.dart';
import 'apotik_pos_state.dart';

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

  const ApotikPosPage({super.key, this.panggil, this.controller});

  @override
  State<ApotikPosPage> createState() => _ApotikPosPageState();
}

class _ApotikPosPageState extends State<ApotikPosPage> {
  late final ApotikPosController _pos =
      widget.controller ?? ApotikPosController();
  late final PanggilAksi _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  final _cari = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _hasilCari = [];
  List<Map<String, dynamic>> _caraBayar = [];
  int? _caraBayarId;
  bool _memuatCari = false;
  String? _galatCari;

  @override
  void initState() {
    super.initState();
    _jalankanCari('');
    _muatCaraBayar();
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
  Future<void> _muatCaraBayar() async {
    try {
      final r = await _panggil('apotik_cara_bayar_list', const {});
      if (!_sukses(r)) return;
      final daftar = _data(r);
      setStateIfMounted(() {
        _caraBayar = daftar;
        _caraBayarId ??=
            daftar.isEmpty ? null : (daftar.first['id'] as num?)?.toInt();
      });
    } catch (_) {
      // Server lama tanpa aksi ini: bukan galat yang perlu mengganggu kasir.
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
      final r = await _panggil(
          'apotik_item_cari', {'keyword': keyword, 'page_size': 40});
      if (!_sukses(r)) {
        setStateIfMounted(() {
          _galatCari = '${r['description'] ?? 'Gagal memuat katalog obat.'}';
          _memuatCari = false;
        });
        return;
      }
      setStateIfMounted(() {
        _hasilCari = _data(r);
        _memuatCari = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galatCari = '$e';
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
      final r = await _panggil(
          'apotik_resep_list', {'hanya_menunggu': true, 'page_size': 50});
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

  Future<void> _bayar() async {
    // mulaiBayar() menolak panggilan kedua saat proses berjalan dan menolak
    // bila pagar belum lolos -- inti pencegahan double-submit.
    if (!_pos.mulaiBayar()) return;
    setStateIfMounted(() {});
    try {
      final payload = _pos.payloadBayar();
      if (_caraBayarId != null) payload['cara_bayar_id'] = _caraBayarId;
      final r = await _panggil('apotik_bayar', payload);
      if (!_sukses(r)) {
        // Pesan penahan server ditampilkan APA ADANYA.
        setStateIfMounted(() => _pos.tandaiGagal(
            '${r['description'] ?? 'Pembayaran ditolak server.'}'));
        return;
      }
      final total = ((r['total'] as num?) ?? 0).toDouble();
      _pos.tandaiBerhasil();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Transaksi Berhasil'),
            content: Text('Kode: ${r['kode']}\nTotal: ${_rp.format(total)}'
                '${'${r['caraBayar'] ?? ''}'.isEmpty ? '' : '\nMetode: ${r['caraBayar']}'}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
            ],
          ),
        );
      }
      setStateIfMounted(() => _pos.kosongkan());
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
                      value: (c['id'] as num?)?.toInt(),
                      child: Text('${c['nama'] ?? '-'}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setStateIfMounted(() => _caraBayarId = v),
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
          Text('Identitas pembeli',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textSecondary)),
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
                style: TextStyle(fontSize: 11, color: t.danger)),
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
