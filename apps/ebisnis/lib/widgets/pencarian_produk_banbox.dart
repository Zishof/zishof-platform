import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'safe_state.dart';

/// Kotak cari produk bergaya "Banbox" (padanan picker `AmbilData...Banbox`
/// versi ZK/JSP: ketik sebagian kata -> daftar saran tampil di bawah kotak,
/// klik salah satu utk memilih). Dipakai di layar mana pun yang tadinya
/// hanya menerima kode/barcode PERSIS (cocok utk hasil scan, tapi kasir yang
/// mengetik manual tanpa tahu kode persis harus buka layar Produk dulu).
/// Saran dicari dari cache produk lokal (offline-first, sumber sama dgn
/// katalog Kasir) supaya responsif tanpa round-trip server tiap ketukan;
/// produk yang BENAR-BENAR dipilih tetap dikirim ke [onPilih] sbg kode --
/// pemanggil tetap memverifikasi ulang ke server, jadi data yang ditampilkan
/// selalu data terkini, bukan cache.
///
/// Enter-langsung (jalur scanner fisik: keystroke kode lalu Enter) SENGAJA
/// tidak lewat mekanisme seleksi bawaan `RawAutocomplete` -- disambungkan
/// LANGSUNG ke [onPilih] apa pun isi teksnya, supaya alur scan yang sudah
/// berfungsi TIDAK berubah sama sekali; dropdown saran murni tambahan utk
/// pencarian manual by nama.
class PencarianProdukBanbox extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool aktif;
  final ValueChanged<String> onPilih;
  final FocusNode? focusNode;
  final bool autofocus;

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
    this.aktif = true,
    this.focusNode,
    this.autofocus = false,
    this.decorationBuilder,
  });

  @override
  State<PencarianProdukBanbox> createState() => _PencarianProdukBanboxState();
}

class _PencarianProdukBanboxState extends State<PencarianProdukBanbox> {
  List<Map<String, Object?>> _semuaProduk = [];
  FocusNode? _focusNodeInternal;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_focusNodeInternal ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _focusNodeInternal = FocusNode();
    _muatCache();
  }

  @override
  void didUpdateWidget(covariant PencarianProdukBanbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _focusNodeInternal?.dispose();
    _focusNodeInternal = widget.focusNode == null ? FocusNode() : null;
  }

  @override
  void dispose() {
    _focusNodeInternal?.dispose();
    super.dispose();
  }

  Future<void> _muatCache() async {
    try {
      final data = await CoreDb.instance.produkCache();
      if (mounted) setStateIfMounted(() => _semuaProduk = data);
    } catch (_) {
      // Pencarian nama sekadar pelengkap -- kalau cache lokal gagal dimuat,
      // kotak tetap berfungsi spt biasa (ketik/scan kode persis + Enter).
    }
  }

  Iterable<Map<String, Object?>> _cariSaran(String kataKunci) {
    final q = kataKunci.trim().toLowerCase();
    if (q.isEmpty) return const Iterable<Map<String, Object?>>.empty();
    return _semuaProduk.where((p) {
      final nama = '${p['nama'] ?? ''}'.toLowerCase();
      final kode = '${p['kode'] ?? ''}'.toLowerCase();
      final barcode = '${p['barcode'] ?? ''}'.toLowerCase();
      return nama.contains(q) || kode.contains(q) || barcode.contains(q);
    }).take(15);
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
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: widget.autofocus,
          enabled: widget.aktif,
          decoration: widget.decorationBuilder?.call(context) ??
              InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
                prefixIcon: Icon(widget.icon),
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
