import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api_client.dart';
import '../../../widgets/safe_state.dart';
import '../../../services/master_offline.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_lokal_dulu.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tgl = DateFormat('yyyy-MM-dd');

typedef PanggilTerima = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// Satu baris penerimaan; tiap baris membentuk SATU batch (lot) baru.
class BarisPenerimaan {
  Map<String, dynamic> item;
  double qty;
  double hargaBeli;
  DateTime? kedaluwarsa;

  BarisPenerimaan({
    required this.item,
    this.qty = 1,
    this.hargaBeli = 0,
    this.kedaluwarsa,
  });

  String get nama => '${item['nama'] ?? '-'}';

  /// Obat rantai dingin (IR-01). Menentukan apakah bukti suhu diperlukan.
  bool get coldChain => item['coldChain'] == true;
  double get subtotal => qty * hargaBeli;

  /// Sisa hari menuju kedaluwarsa; null bila belum diisi.
  int? sisaHari({DateTime? sekarang}) {
    final k = kedaluwarsa;
    if (k == null) return null;
    final kini = sekarang ?? DateTime.now();
    return DateTime(k.year, k.month, k.day)
        .difference(DateTime(kini.year, kini.month, kini.day))
        .inDays;
  }
}

/// Hasil pemeriksaan sebelum posting penerimaan.
class PagarPenerimaan {
  final bool boleh;
  final List<String> alasan;

  /// Peringatan yang TIDAK menahan posting, tetapi wajib dibaca petugas.
  final List<String> peringatan;
  const PagarPenerimaan(this.boleh, this.alasan, this.peringatan);
}

/// <h3>Penerimaan PBF (Fase 5, mockup 06).</h3>
///
/// Memakai `apotik_terima_barang` apa adanya:
/// `{no_faktur, penyedia, keterangan, items:[{item_id, qty, harga_beli,
/// tanggal_kadaluarsa}]}`. Setiap baris membentuk satu lot baru, sehingga
/// **tanggal kedaluwarsa adalah data keselamatan**, bukan sekadar pelengkap.
///
/// Yang BELUM ada di server dan karena itu tidak dibuat-buat di sini: nomor
/// PO, penerimaan sebagian (partial receiving), dan bukti suhu cold-chain —
/// lihat IR-09. Layar ini tidak berpura-pura mencatatnya.
class ApotikPenerimaanPage extends StatefulWidget {
  final PanggilTerima? panggil;

  /// Pencarian obat dibaca lokal-dulu; POSTING penerimaannya tetap online
  /// (belum ada kunci idempoten — lihat core/apotik_lokal_dulu.dart).
  final MuatDaftarApotik? muatKatalog;

  const ApotikPenerimaanPage({super.key, this.panggil, this.muatKatalog});

  @override
  State<ApotikPenerimaanPage> createState() => _ApotikPenerimaanPageState();

  /// Pemeriksaan pra-posting. Dipisah sebagai fungsi murni agar dapat diuji
  /// tanpa merakit widget.
  /// Rentang rantai dingin baku yang dipakai layar formularium dan server.
  static const double suhuMin = 2;
  static const double suhuMaks = 8;

  static PagarPenerimaan periksa({
    required String noFaktur,
    required String penyedia,
    required List<BarisPenerimaan> baris,
    DateTime? sekarang,
    double? suhu,
  }) {
    final alasan = <String>[];
    final peringatan = <String>[];
    if (noFaktur.trim().isEmpty) {
      alasan.add('Nomor faktur wajib diisi.');
    }
    if (penyedia.trim().isEmpty) {
      alasan.add('Nama penyedia/PBF wajib diisi.');
    }
    if (baris.isEmpty) {
      alasan.add('Minimal satu baris penerimaan.');
    }
    for (final b in baris) {
      if (b.qty <= 0) {
        alasan.add('${b.nama}: qty harus lebih dari 0.');
      }
      final sisa = b.sisaHari(sekarang: sekarang);
      if (sisa == null) {
        // Tanpa tanggal kedaluwarsa, lot tidak dapat diurutkan FEFO dan
        // tidak akan pernah muncul di monitor expiry -- ini penahan.
        alasan.add('${b.nama}: tanggal kedaluwarsa wajib diisi '
            '(lot tanpa ED tidak dapat diurutkan FEFO).');
      } else if (sisa < 0) {
        alasan.add('${b.nama}: tanggal kedaluwarsa sudah lewat '
            '(${-sisa} hari) — barang kedaluwarsa tidak boleh diterima.');
      } else if (sisa <= 90) {
        peringatan.add('${b.nama}: hanya $sisa hari menuju kedaluwarsa — '
            'pastikan memang disepakati dengan PBF.');
      }
      if (b.hargaBeli <= 0) {
        peringatan.add('${b.nama}: harga beli 0 — periksa faktur.');
      }
    }
    // Bukti suhu rantai dingin (IR-09 sebagian). Ini PERINGATAN, bukan
    // penahan: server menyimpan tanpa menolak, dan keputusan menerima atau
    // menolak barang rantai dingin adalah wewenang apoteker penanggung jawab
    // menurut SOP apoteknya — bukan aturan yang boleh dikarang layar ini.
    final adaColdChain = baris.any((b) => b.coldChain);
    if (adaColdChain) {
      if (suhu == null) {
        peringatan.add('Faktur ini memuat obat rantai dingin — catat suhu '
            'saat barang diterima sebagai bukti.');
      } else if (suhu < suhuMin || suhu > suhuMaks) {
        peringatan.add('Suhu ${suhu.toStringAsFixed(1)} °C di luar rentang '
            '$suhuMin–$suhuMaks °C. Penerimaan tetap dapat dicatat, tetapi '
            'putuskan bersama apoteker penanggung jawab.');
      }
    }
    return PagarPenerimaan(alasan.isEmpty, alasan, peringatan);
  }
}

class _ApotikPenerimaanPageState extends State<ApotikPenerimaanPage> {
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
    if (_sukses(r)) onData({...r, 'dariServer': true});
  }

  late final PanggilTerima _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  final _noFaktur = TextEditingController();
  final _penyedia = TextEditingController();
  final _keterangan = TextEditingController();
  final _cari = TextEditingController();
  final _suhu = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _hasilCari = [];
  final List<BarisPenerimaan> _baris = [];
  bool _mencari = false;
  bool _memposting = false;
  String? _pesanServer;

  @override
  void dispose() {
    _debounce?.cancel();
    _noFaktur.dispose();
    _penyedia.dispose();
    _keterangan.dispose();
    _suhu.dispose();
    _cari.dispose();
    super.dispose();
  }

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  void _cariDebounce(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _cariItem(v));
  }

  Future<void> _cariItem(String keyword) async {
    if (keyword.trim().isEmpty) {
      setStateIfMounted(() => _hasilCari = []);
      return;
    }
    setStateIfMounted(() => _mencari = true);
    try {
      await _muatKatalog(
        'apotik_item_cari',
        {'keyword': keyword, 'page_size': 15},
        kunciCacheItemApotik,
        onData: (hasil) {
          if (!mounted) return;
          final dariServer = hasil['dariServer'] == true;
          final data = ((hasil['data'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setStateIfMounted(() {
            _hasilCari = dariServer ? data : saringCacheLokal(data, keyword);
            _mencari = false;
          });
        },
      );
    } catch (_) {
      // Hasil dari cache (bila ada) dipertahankan: petugas masih bisa
      // menyusun baris penerimaan; postingnya yang butuh server.
      setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _posting() async {
    final pagar = ApotikPenerimaanPage.periksa(
      noFaktur: _noFaktur.text,
      penyedia: _penyedia.text,
      baris: _baris,
      suhu: _nilaiSuhu,
    );
    if (!pagar.boleh) return;
    setStateIfMounted(() {
      _memposting = true;
      _pesanServer = null;
    });
    try {
      final r = await _panggil('apotik_terima_barang', {
        'no_faktur': _noFaktur.text.trim(),
        'penyedia': _penyedia.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'items': [
          for (final b in _baris)
            {
              'item_id': b.item['id'],
              'qty': b.qty,
              'harga_beli': b.hargaBeli,
              'tanggal_kadaluarsa': _tgl.format(b.kedaluwarsa!),
            }
        ],
        if (_nilaiSuhu != null) 'suhu_terima': _nilaiSuhu,
      });
      if (!mounted) return;
      if (!_sukses(r)) {
        // Pesan penahan server apa adanya.
        setStateIfMounted(() {
          _pesanServer = '${r['description'] ?? 'Penerimaan ditolak server.'}';
          _memposting = false;
        });
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Penerimaan Tercatat'),
          content: Text('${r['jumlahBaris'] ?? _baris.length} baris, '
              '${r['jumlahBatch'] ?? _baris.length} batch baru masuk stok.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
          ],
        ),
      );
      setStateIfMounted(() {
        _baris.clear();
        _noFaktur.clear();
        _keterangan.clear();
        _suhu.clear();
        _memposting = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _pesanServer = '$e';
        _memposting = false;
      });
    }
  }

  Future<void> _pilihTanggal(BarisPenerimaan b) async {
    final kini = DateTime.now();
    final hasil = await showDatePicker(
      context: context,
      initialDate:
          b.kedaluwarsa ?? DateTime(kini.year + 1, kini.month, kini.day),
      firstDate: DateTime(kini.year - 1),
      lastDate: DateTime(kini.year + 15),
    );
    if (hasil != null) setStateIfMounted(() => b.kedaluwarsa = hasil);
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final pagar = ApotikPenerimaanPage.periksa(
      noFaktur: _noFaktur.text,
      penyedia: _penyedia.text,
      baris: _baris,
      suhu: _nilaiSuhu,
    );
    return ApotikResponsive(builder: (context, layout) {
      final padding = ApotikBreakpoints.paddingHalaman(layout);
      return Scaffold(
        backgroundColor: t.surfaceMuted,
        body: ListView(
          padding: EdgeInsets.fromLTRB(padding, 0, padding, 24),
          children: [
            const ApotikPageHeader(
              judul: 'Penerimaan PBF',
              subjudul: 'Setiap baris membentuk satu batch baru — tanggal '
                  'kedaluwarsa wajib',
            ),
            _kotakFaktur(t),
            const SizedBox(height: 12),
            _kotakTambahItem(t),
            const SizedBox(height: 12),
            _kotakBaris(t),
            const SizedBox(height: 12),
            _kotakPagar(t, pagar),
            const SizedBox(height: 12),
            SizedBox(
              height: ApotikBreakpoints.targetSentuhMinimum,
              child: FilledButton.icon(
                onPressed: (pagar.boleh && !_memposting) ? _posting : null,
                icon: _memposting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text(_memposting ? 'Memposting…' : 'Posting Penerimaan'),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _kotak(ApotikDesignTokens t, String judul, IconData ikon, Widget isi) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ikon, size: 17, color: t.primary),
          const SizedBox(width: 8),
          Text(judul,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ]),
        const SizedBox(height: 10),
        isi,
      ]),
    );
  }

  Widget _kotakFaktur(ApotikDesignTokens t) {
    return _kotak(
      t,
      'Faktur & penyedia',
      Icons.receipt_long_outlined,
      Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _noFaktur,
              decoration: const InputDecoration(
                  labelText: 'Nomor faktur *',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (_) => setStateIfMounted(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _penyedia,
              decoration: const InputDecoration(
                  labelText: 'Penyedia / PBF *',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (_) => setStateIfMounted(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _keterangan,
          decoration: const InputDecoration(
              labelText: 'Keterangan',
              border: OutlineInputBorder(),
              isDense: true),
        ),
        // Kolom suhu HANYA muncul bila faktur ini memang memuat obat rantai
        // dingin -- meminta suhu untuk kiriman tablet biasa hanya melatih
        // petugas mengabaikan kolom.
        if (_baris.any((b) => b.coldChain)) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _suhu,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            onChanged: (_) => setStateIfMounted(() {}),
            decoration: const InputDecoration(
              labelText: 'Suhu saat diterima (°C)',
              helperText: 'Rantai dingin: 2–8 °C. Dicatat sebagai bukti; '
                  'keputusan menerima tetap pada apoteker.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ]),
    );
  }

  /// Suhu terbaca; null bila belum diisi (bukan 0 — 0 °C adalah nilai sah).
  double? get _nilaiSuhu {
    final teks = _suhu.text.trim().replaceAll(',', '.');
    if (teks.isEmpty) return null;
    return double.tryParse(teks);
  }

  Widget _kotakTambahItem(ApotikDesignTokens t) {
    return _kotak(
      t,
      'Tambah obat',
      Icons.search,
      Column(children: [
        TextField(
          controller: _cari,
          decoration: InputDecoration(
            hintText: 'Cari nama obat atau kode…',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _mencari
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
          onChanged: _cariDebounce,
        ),
        for (final it in _hasilCari)
          ListTile(
            dense: true,
            title: Text('${it['nama'] ?? '-'}',
                style: TextStyle(fontSize: 13, color: t.textPrimary)),
            subtitle: Text('${it['kode'] ?? ''} • stok ${it['stok'] ?? 0}',
                style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
            trailing: const Icon(Icons.add_circle_outline, size: 18),
            onTap: () {
              setStateIfMounted(() {
                _baris.add(BarisPenerimaan(
                    item: it,
                    hargaBeli:
                        ((it['hargaJual'] as num?) ?? 0).toDouble() * 0));
                _hasilCari = [];
                _cari.clear();
              });
            },
          ),
      ]),
    );
  }

  Widget _kotakBaris(ApotikDesignTokens t) {
    return _kotak(
      t,
      'Baris penerimaan (${_baris.length})',
      Icons.list_alt_outlined,
      _baris.isEmpty
          ? const ApotikEmptyState(
              ikon: Icons.inventory_2_outlined,
              judul: 'Belum ada baris',
              petunjuk: 'Cari obat di atas lalu tambahkan ke daftar '
                  'penerimaan.')
          : Column(children: [
              for (var i = 0; i < _baris.length; i++) _barisEditor(t, i),
            ]),
    );
  }

  Widget _barisEditor(ApotikDesignTokens t, int i) {
    final b = _baris[i];
    final sisa = b.sisaHari();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border:
            Border.all(color: (sisa != null && sisa < 0) ? t.danger : t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(b.nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Hapus baris ${b.nama}',
            icon: Icon(Icons.close, size: 16, color: t.textSecondary),
            onPressed: () => setStateIfMounted(() => _baris.removeAt(i)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
            width: 92,
            child: TextFormField(
              initialValue: b.qty.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (v) => setStateIfMounted(
                  () => b.qty = double.tryParse(v.trim()) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: TextFormField(
              initialValue:
                  b.hargaBeli == 0 ? '' : b.hargaBeli.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Harga beli',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (v) => setStateIfMounted(
                  () => b.hargaBeli = double.tryParse(v.trim()) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pilihTanggal(b),
              icon: const Icon(Icons.event_outlined, size: 16),
              label: Text(b.kedaluwarsa == null
                  ? 'Tanggal ED *'
                  : 'ED ${_tgl.format(b.kedaluwarsa!)}'),
            ),
          ),
        ]),
        if (sisa != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            if (sisa < 0)
              ApotikStatusPill.kedaluwarsa()
            else if (sisa <= 90)
              ApotikStatusPill.nearExpiry(sisa)
            else
              ApotikStatusPill.layak(penjelasan: 'ED masih jauh'),
            const Spacer(),
            Text(_rp.format(b.subtotal),
                style: TextStyle(fontSize: 12.5, color: t.textPrimary)),
          ]),
        ],
      ]),
    );
  }

  Widget _kotakPagar(ApotikDesignTokens t, PagarPenerimaan pagar) {
    if (pagar.alasan.isEmpty &&
        pagar.peringatan.isEmpty &&
        _pesanServer == null) {
      return const SizedBox.shrink();
    }
    return Column(children: [
      if (_pesanServer != null)
        _kotakPesan(t, t.danger, Icons.error_outline,
            'Penerimaan ditahan server', [_pesanServer!]),
      if (pagar.alasan.isNotEmpty)
        _kotakPesan(t, t.warning, Icons.gpp_maybe_outlined,
            'Belum dapat diposting', pagar.alasan),
      if (pagar.peringatan.isNotEmpty)
        _kotakPesan(t, t.info, Icons.info_outline, 'Perlu diperhatikan',
            pagar.peringatan),
    ]);
  }

  Widget _kotakPesan(ApotikDesignTokens t, Color warna, IconData ikon,
      String judul, List<String> isi) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(color: warna.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ikon, size: 15, color: warna),
          const SizedBox(width: 6),
          Text(judul,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: warna)),
        ]),
        const SizedBox(height: 4),
        for (final s in isi)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $s',
                style: TextStyle(fontSize: 11.5, color: t.textPrimary)),
          ),
      ]),
    );
  }
}
