import 'dart:async';

import 'package:core_db/core_db.dart';
import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import 'safe_state.dart';

/// Kotak cari produk bergaya "Banbox" (padanan picker `AmbilData...Banbox`
/// versi ZK/JSP: ketik sebagian kata/kode/barcode -> daftar saran tampil di
/// bawah kotak, klik salah satu utk memilih). Dipakai di layar mana pun yang
/// menerima kode/barcode maupun pencarian nama produk.
///
/// Sumber saran:
/// 1. Cache produk lokal (`produkCacheMaster` + `produkCache`) yang otomatis
///    di-refresh setiap kali ada perubahan master lokal (`MasterOffline.revisiBaris`)
///    atau saat kotak mendapatkan fokus, sehingga master produk yang BARU SAJA
///    ditambahkan di tab Produk langsung muncul pilihannya tanpa harus menutup
///    atau memuat ulang halaman (mis. Bulk Entry Faktur Kulakan).
/// 2. Fallback pencarian live ke server (`diskon_grup_produk_cari` & `so_produk_scan`)
///    secara debounced bila kata kunci belum ditemukan di cache lokal (mis.
///    master produk baru ditambahkan dari perangkat/admin lain).
///
/// Enter-langsung (jalur scanner fisik: keystroke kode lalu Enter) SENGAJA
/// tidak lewat mekanisme seleksi bawaan `RawAutocomplete` -- disambungkan
/// LANGSUNG ke [onPilih] apa pun isi teksnya, supaya alur scan yang sudah
/// berfungsi TIDAK berubah sama sekali.
class PencarianProdukBanbox extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool aktif;
  final ValueChanged<String> onPilih;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool tampilkanScanner;
  final TextStyle? textStyle;

  /// Override opsional utk decoration kotak teks -- dipakai layar yang
  /// sudah punya gaya form sendiri (mis. `AppFormStyle.fieldDecoration`)
  /// supaya kotak ini tetap konsisten dgn field lain di layar itu. Kalau
  /// null, dipakai decoration polos bawaan (OutlineInputBorder biasa).
  final InputDecoration Function(BuildContext context)? decorationBuilder;

  const PencarianProdukBanbox({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.onPilih,
    this.onChanged,
    this.aktif = true,
    this.focusNode,
    this.autofocus = false,
    this.tampilkanScanner = true,
    this.textStyle,
    this.decorationBuilder,
  });

  @override
  State<PencarianProdukBanbox> createState() => _PencarianProdukBanboxState();
}

class _PencarianProdukBanboxState extends State<PencarianProdukBanbox> {
  List<Map<String, Object?>> _semuaProduk = [];
  final Map<String, List<Map<String, Object?>>> _saranServerPerKata = {};
  Timer? _debounceServer;
  String _kataServerTerakhir = '';
  FocusNode? _focusNodeInternal;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_focusNodeInternal ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _focusNodeInternal = FocusNode();
    _focusNode.addListener(_saatFokusBerubah);
    MasterOffline.revisiBaris.addListener(_saatMasterBerubah);
    _muatCache();
  }

  @override
  void didUpdateWidget(covariant PencarianProdukBanbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    (oldWidget.focusNode ?? _focusNodeInternal)
        ?.removeListener(_saatFokusBerubah);
    _focusNodeInternal?.dispose();
    _focusNodeInternal = widget.focusNode == null ? FocusNode() : null;
    _focusNode.addListener(_saatFokusBerubah);
  }

  @override
  void dispose() {
    _debounceServer?.cancel();
    _focusNode.removeListener(_saatFokusBerubah);
    MasterOffline.revisiBaris.removeListener(_saatMasterBerubah);
    _focusNodeInternal?.dispose();
    super.dispose();
  }

  void _saatFokusBerubah() {
    if (_focusNode.hasFocus) {
      _muatCache();
      final q = widget.controller.text.trim();
      if (q.length >= 2) {
        _jadwalkanCariServer(q);
      }
    }
  }

  void _saatMasterBerubah() {
    _saranServerPerKata.clear();
    _muatCache();
  }

  void _paksaPerbaruiOpsi() {
    if (!mounted) return;
    // Memicu ValueListenableBuilder internal RawAutocomplete agar daftar
    // opsi segar kembali saat hasil cache/server masuk.
    final nilai = widget.controller.value;
    widget.controller.value = nilai.copyWith(
      text: nilai.text,
      selection: nilai.selection,
      composing: TextRange.empty,
    );
    setStateIfMounted(() {});
  }

  Future<void> _muatCache() async {
    try {
      final master = await CoreDb.instance.produkCacheMaster(
        limit: 10000,
        jenisItem: 'SEMUA',
      );
      final jual = await CoreDb.instance.produkCache(limit: 10000);
      final gabung = <String, Map<String, Object?>>{};
      for (final p in [...master, ...jual]) {
        final key = '${p['id'] ?? ''}|${p['kode'] ?? ''}|${p['barcode'] ?? ''}';
        gabung[key] = p;
      }
      if (mounted) {
        setStateIfMounted(() => _semuaProduk = gabung.values.toList());
      }
    } catch (_) {
      try {
        final data = await CoreDb.instance.produkCache();
        if (mounted) setStateIfMounted(() => _semuaProduk = data);
      } catch (_) {}
    }
  }

  void _jadwalkanCariServer(String kataKunci) {
    final q = kataKunci.trim();
    if (q.length < 2) return;
    final key = q.toLowerCase();
    if (_saranServerPerKata.containsKey(key) || _kataServerTerakhir == key) {
      return;
    }
    _debounceServer?.cancel();
    _debounceServer = Timer(const Duration(milliseconds: 220), () async {
      _kataServerTerakhir = key;
      final hasilGabung = <Map<String, Object?>>[];
      try {
        final res = await ApiClient.instance.aksi('diskon_grup_produk_cari', {
          'q': q,
          if (Sesi.instance.idTokoTerpilih != null)
            'toko_id': Sesi.instance.idTokoTerpilih,
        });
        final list = (res['data'] as List?) ?? const [];
        for (final item in list.whereType<Map>()) {
          hasilGabung.add({
            'id': item['id'],
            'kode': '${item['kode'] ?? ''}',
            'barcode': '${item['barcode'] ?? item['kode'] ?? ''}',
            'nama': '${item['nama'] ?? ''}',
            'harga_jual': item['hargaJual'] ?? item['harga_jual'] ?? 0,
          });
        }
      } catch (_) {}
      if (hasilGabung.isEmpty && q.length >= 3) {
        try {
          final scan = await ApiClient.instance.aksi('so_produk_scan', {
            'barcode': q,
          });
          if (scan['produkId'] != null || '${scan['nama'] ?? ''}'.isNotEmpty) {
            hasilGabung.add({
              'id': scan['produkId'] ?? scan['id'],
              'kode': '${scan['kode'] ?? q}',
              'barcode': '${scan['barcode'] ?? q}',
              'nama': '${scan['nama'] ?? ''}',
              'harga_jual': scan['hargaJual'] ?? 0,
            });
          }
        } catch (_) {}
      }
      if (!mounted) return;
      _saranServerPerKata[key] = hasilGabung;
      if (hasilGabung.isNotEmpty) {
        final mapAda = <String, Map<String, Object?>>{
          for (final p in _semuaProduk)
            '${p['id'] ?? ''}|${p['kode'] ?? ''}|${p['barcode'] ?? ''}': p,
        };
        for (final p in hasilGabung) {
          final k = '${p['id'] ?? ''}|${p['kode'] ?? ''}|${p['barcode'] ?? ''}';
          mapAda[k] = p;
        }
        _semuaProduk = mapAda.values.toList();
        _paksaPerbaruiOpsi();
      }
    });
  }

  Iterable<Map<String, Object?>> _cariSaran(String kataKunci) {
    final q = kataKunci.trim().toLowerCase();
    if (q.isEmpty) return const Iterable<Map<String, Object?>>.empty();
    final cocokLokal = _semuaProduk.where((p) {
      final nama = '${p['nama'] ?? ''}'.toLowerCase();
      final kode = '${p['kode'] ?? ''}'.toLowerCase();
      final barcode = '${p['barcode'] ?? ''}'.toLowerCase();
      return nama.contains(q) || kode.contains(q) || barcode.contains(q);
    }).take(15).toList();
    if (cocokLokal.length < 5 && q.length >= 2) {
      _jadwalkanCariServer(kataKunci);
    }
    return cocokLokal;
  }

  Future<void> _scanProduk() async {
    final kode = await BarcodeScannerScreen.pindai(
      context,
      judul: 'Scan Barcode / QR Produk',
    );
    if (!mounted || kode == null || kode.trim().isEmpty) return;
    final nilai = kode.trim();
    widget.controller
      ..text = nilai
      ..selection = TextSelection.collapsed(offset: nilai.length);
    widget.onPilih(nilai);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, Object?>>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) => _cariSaran(value.text),
      displayStringForOption: (p) => '${p['kode'] ?? p['barcode'] ?? ''}',
      onSelected: (p) {
        final kode = '${p['kode'] ?? p['barcode'] ?? ''}'.trim();
        if (kode.isNotEmpty) widget.onPilih(kode);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final dasar = widget.decorationBuilder?.call(context) ??
            InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(widget.icon),
            );
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: widget.autofocus,
          enabled: widget.aktif,
          style: widget.textStyle,
          onChanged: widget.onChanged,
          decoration: dasar.copyWith(
            suffixIcon: widget.tampilkanScanner
                ? IconButton(
                    tooltip: 'Scan barcode/QR dengan kamera',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: widget.aktif ? _scanProduk : null,
                  )
                : dasar.suffixIcon,
          ),
          // Enter = cari LANGSUNG apa pun teksnya (jalur scanner), bukan
          // menyeleksi opsi dropdown -- lihat JavaDoc kelas.
          onSubmitted: widget.onPilih,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final p = options.elementAt(i);
                  final barcode = '${p['barcode'] ?? ''}';
                  return ListTile(
                    dense: true,
                    title: Text('${p['nama'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(barcode.isEmpty
                        ? '${p['kode'] ?? ''}'
                        : '${p['kode'] ?? ''} · $barcode'),
                    onTap: () => onSelected(p),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
