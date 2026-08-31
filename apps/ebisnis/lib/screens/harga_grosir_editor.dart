import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

/// Editor aturan harga grosir SATU produk (Fase A dok. 48/49) — dipasang di
/// form Produk, di bawah seksi Kemasan.
///
/// Aturan dievaluasi SERVER (`HargaGrosirApiHelper`): ambang terbesar yang
/// terpenuhi menang; aturan ber-toko menang atas global. Editor ini hanya
/// mengelola barisnya lewat `harga_grosir_list/simpan/hapus` — ONLINE-ONLY
/// secara sengaja: aturan komersial harus segera berlaku serentak di semua
/// kasir, dan menyimpannya di antrean lokal membuat dua kasir sempat memakai
/// harga berbeda untuk transaksi yang sama.
///
/// Hapus = NONAKTIF di server (jejak komersial dipertahankan); daftar di sini
/// hanya menampilkan yang aktif.
class HargaGrosirEditor extends StatefulWidget {
  final int produkId;

  /// Nama satuan dasar produk, untuk label ambang ("mulai 50 kg").
  final String satuanNama;

  const HargaGrosirEditor(
      {super.key, required this.produkId, required this.satuanNama});

  @override
  State<HargaGrosirEditor> createState() => _HargaGrosirEditorState();
}

class _HargaGrosirEditorState extends State<HargaGrosirEditor> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _aturan = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await ApiClient.instance
          .aksi('harga_grosir_list', {'produk_id': widget.produkId});
      if (!mounted) return;
      setStateIfMounted(() {
        _aturan = ((r['data'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _tambah() async {
    final minQty = TextEditingController();
    final harga = TextEditingController();
    final hargaPaket = TextEditingController();
    bool kelipatanWajib = false;
    bool tokoIni = false;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Aturan Harga Grosir'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: minQty,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText:
                    'Mulai kuantitas (${widget.satuanNama.isEmpty ? 'satuan dasar' : widget.satuanNama})',
                helperText: 'Ambang dihitung dari TOTAL produk ini se-keranjang.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: harga,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    'Harga per ${widget.satuanNama.isEmpty ? 'satuan dasar' : widget.satuanNama}',
                helperText:
                    'Metode 1 (ambang). Kosongkan bila mengisi harga per paket.',
              ),
            ),
            const SizedBox(height: 10),
            // Metode 2 (dok. 48 §6 no.1): harga TETAP per paket -- server
            // menyimpan turunannya (paket / isi) sebagai harga satuan efektif.
            TextField(
              controller: hargaPaket,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ATAU harga per paket/kemasan (Metode 2)',
                helperText:
                    'Contoh: 4.500.000 per karung isi 50. Total kelipatan paket selalu = harga paket x jumlah paket.',
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: kelipatanWajib,
              onChanged: (v) => setDialog(() => kelipatanWajib = v ?? false),
              contentPadding: EdgeInsets.zero,
              title: const Text('Wajib kelipatan kemasan',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                  'Checkout menolak qty nanggung (mis. 53) dengan saran pembulatan.',
                  style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: tokoIni,
              onChanged: (v) => setDialog(() => tokoIni = v ?? false),
              contentPadding: EdgeInsets.zero,
              title: const Text('Hanya toko aktif ini',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                  'Tidak dicentang = berlaku semua toko. Aturan per-toko menang atas aturan semua-toko.',
                  style: TextStyle(fontSize: 11)),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true || !mounted) return;
    final qty = double.tryParse(minQty.text.replaceAll(',', '.')) ?? 0;
    final hrg = double.tryParse(harga.text.replaceAll(',', '.')) ?? 0;
    final paket = double.tryParse(hargaPaket.text.replaceAll(',', '.')) ?? 0;
    try {
      final r = await ApiClient.instance.aksi('harga_grosir_simpan', {
        'produk_id': widget.produkId,
        'min_qty_dasar': qty,
        'harga': hrg,
        if (paket > 0) 'harga_paket': paket,
        'kelipatan_wajib': kelipatanWajib,
        if (tokoIni) 'toko_id': Sesi.instance.tokoId,
      });
      if (r['status'] != 'success' && r['status'] != '00') {
        throw '${r['description'] ?? 'Server menolak.'}';
      }
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan aturan harga: $e')));
    }
  }

  Future<void> _nonaktifkan(Map<String, dynamic> a) async {
    try {
      final r = await ApiClient.instance
          .aksi('harga_grosir_hapus', {'id': a['id']});
      if (r['status'] != 'success' && r['status'] != '00') {
        throw '${r['description'] ?? 'Server menolak.'}';
      }
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menonaktifkan aturan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      judul: 'Harga Grosir (ambang kuantitas)',
      aksiJudul: TextButton.icon(
        onPressed: _tambah,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Tambah Aturan'),
      ),
      child: _memuat
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : _galat != null
              ? Text('Tidak dapat memuat aturan (perlu daring): $_galat',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.danger))
              : _aturan.isEmpty
                  ? Text(
                      'Opsional. Contoh: mulai 50 ${widget.satuanNama.isEmpty ? 'unit' : widget.satuanNama} '
                      'harga turun ke grosir. Kasir menerapkannya otomatis dari total '
                      'produk ini se-keranjang; diskon dihitung SESUDAH harga grosir.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryOf(context)),
                    )
                  : Column(
                      children: _aturan
                          .map((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(
                                      'Mulai ${a['minQtyDasar']} ${widget.satuanNama} '
                                      '→ ${_fmtRp.format((a['harga'] as num?) ?? 0)}'
                                      '${a['tokoId'] == null ? ' · semua toko' : ' · toko ini'}',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                  IconButton(
                                    iconSize: 18,
                                    color: AppColors.danger,
                                    tooltip:
                                        'Nonaktifkan (jejak harga dipertahankan)',
                                    onPressed: () => _nonaktifkan(a),
                                    icon: const Icon(Icons.block),
                                  ),
                                ]),
                              ))
                          .toList(),
                    ),
    );
  }
}
