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
/// Membaca angka rupiah yang diketik apa adanya, termasuk pemisah ribuan
/// Indonesia: "1.200.000" -> 1200000, "1.200.000,5" -> 1200000.5,
/// "Rp 65.000" -> 65000. Teks tanpa angka -> 0, sehingga validator dialog
/// menolaknya dengan pesan jelas alih-alih mengirim ambang 0 yang diam-diam
/// ditolak server (keluhan 31-08: aturan yang dibuat tidak pernah muncul).
@visibleForTesting
double angkaRupiahGrosir(String teks) {
  // Prefiks mata uang dan pemisah ruang dibuang lebih dulu; SISA huruf apa pun
  // berarti isian itu bukan angka (mis. nama produk) -> 0, bukan tebakan.
  var s = teks.trim().replaceAll(RegExp(r'^[Rr][Pp]\.?'), '').replaceAll(' ', '');
  if (RegExp(r'[A-Za-z]').hasMatch(s)) return 0;
  s = s.replaceAll(RegExp(r'[^0-9,.]'), '');
  if (s.isEmpty) return 0;
  final adaKoma = s.contains(',');
  final adaTitik = s.contains('.');
  if (adaKoma && adaTitik) {
    // "1.200.000,50": titik ribuan, koma desimal.
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (adaKoma) {
    final bagian = s.split(',');
    s = (bagian.length > 2 || bagian.last.length == 3)
        ? s.replaceAll(',', '') // "1,200,000"
        : s.replaceAll(',', '.'); // "1200,5"
  } else if (adaTitik) {
    final bagian = s.split('.');
    if (bagian.length > 2 || bagian.last.length == 3) {
      s = s.replaceAll('.', ''); // "1.200.000" / "1.200"
    }
  }
  return double.tryParse(s) ?? 0;
}

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

  /// Dialog tambah/ubah satu aturan. [awal] null = tambah; selain itu baris
  /// yang diedit -- dikirim balik ber-`id` sehingga server MEMPERBARUI baris
  /// yang sama, bukan menumpuk aturan baru (keluhan 31-08: aturan lama tidak
  /// tampil dan tidak bisa disunting).
  Future<void> _editorAturan([Map<String, dynamic>? awal]) async {
    final ubah = awal != null;
    final paketAwal = ubah ? (awal['hargaPaket'] as num?)?.toDouble() : null;
    final minQty = TextEditingController(
        text: ubah ? _angkaTeks(awal['minQtyDasar']) : '');
    final harga = TextEditingController(
        text: ubah && (paketAwal == null || paketAwal <= 0)
            ? _angkaTeks(awal['harga'])
            : '');
    final hargaPaket = TextEditingController(
        text: paketAwal != null && paketAwal > 0 ? _angkaTeks(paketAwal) : '');
    bool kelipatanWajib = ubah && awal['kelipatanWajib'] == true;
    bool tokoIni = ubah ? awal['tokoId'] != null : false;
    final satuan =
        widget.satuanNama.isEmpty ? 'satuan dasar' : widget.satuanNama;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          final qty = angkaRupiahGrosir(minQty.text);
          final hrg = angkaRupiahGrosir(harga.text);
          final paket = angkaRupiahGrosir(hargaPaket.text);
          final galatQty = minQty.text.trim().isEmpty || qty > 0
              ? null
              : 'Isi ANGKA lebih dari 0, mis. 6';
          final galatHarga = (hrg <= 0 &&
                  paket <= 0 &&
                  (harga.text.trim().isNotEmpty ||
                      hargaPaket.text.trim().isNotEmpty))
              ? 'Isi angka lebih dari 0'
              : null;
          final sah = qty > 0 && (hrg > 0 || paket > 0);
          final turunan = paket > 0 && qty > 0 ? paket / qty : null;
          return AlertDialog(
            title:
                Text(ubah ? 'Ubah Aturan Harga Grosir' : 'Aturan Harga Grosir'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: minQty,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (_) => setDialog(() {}),
                  decoration: InputDecoration(
                    labelText: 'Mulai kuantitas ($satuan) *',
                    errorText: galatQty,
                    helperText:
                        'ANGKA saja. Isi paket dalam $satuan -- mis. 6 untuk 1 Dus isi 6. '
                        'Ambang dihitung dari TOTAL produk ini se-keranjang.',
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: harga,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialog(() {}),
                  decoration: InputDecoration(
                    labelText: 'Harga per $satuan',
                    errorText: galatHarga,
                    helperText:
                        'Metode 1 (ambang). Kosongkan bila mengisi harga per paket.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                // Metode 2 (dok. 48 §6 no.1): harga TETAP per paket -- server
                // menyimpan turunannya (paket / isi) sebagai harga satuan.
                TextField(
                  controller: hargaPaket,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialog(() {}),
                  decoration: InputDecoration(
                    labelText: 'ATAU harga per paket/kemasan (Metode 2)',
                    helperText: turunan != null
                        ? '= ${_fmtRp.format(turunan)} / $satuan. Total kelipatan paket selalu = harga paket x jumlah paket.'
                        : 'Contoh: 1.200.000 per Dus isi 6 (ambang 6). Total 1 Dus tepat harga paket.',
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: kelipatanWajib,
                  onChanged: (v) =>
                      setDialog(() => kelipatanWajib = v ?? false),
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
                if (!sah)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Isi ambang kuantitas dan salah satu harga untuk menyimpan.',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondaryOf(c))),
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Batal')),
              FilledButton(
                  // Mati sampai isian sah -- sebelumnya aturan tak pernah
                  // muncul karena ambang berisi teks lalu server menolak.
                  onPressed: sah ? () => Navigator.pop(c, true) : null,
                  child: const Text('Simpan')),
            ],
          );
        },
      ),
    );
    if (simpan != true || !mounted) return;
    final qty = angkaRupiahGrosir(minQty.text);
    final hrg = angkaRupiahGrosir(harga.text);
    final paket = angkaRupiahGrosir(hargaPaket.text);
    try {
      final r = await ApiClient.instance.aksi('harga_grosir_simpan', {
        if (ubah) 'id': awal['id'],
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            ubah ? 'Aturan harga diperbarui.' : 'Aturan harga ditambahkan.'),
        duration: const Duration(milliseconds: 1400),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan aturan harga: $e')));
    }
  }

  /// Angka server -> teks isian tanpa ".0" yang mengganggu saat diedit.
  String _angkaTeks(Object? nilai) {
    final n = (nilai as num?)?.toDouble();
    if (n == null) return '';
    return n == n.roundToDouble() ? '${n.round()}' : '$n';
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
        onPressed: () => _editorAturan(),
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
                      children: _aturan.map((a) {
                        final minQty =
                            (a['minQtyDasar'] as num?)?.toDouble() ?? 0;
                        final paket = (a['hargaPaket'] as num?)?.toDouble();
                        final perSatuan = (a['harga'] as num?)?.toDouble() ?? 0;
                        final satuan = widget.satuanNama.isEmpty
                            ? 'unit'
                            : widget.satuanNama;
                        final qtyTeks = minQty == minQty.roundToDouble()
                            ? '${minQty.round()}'
                            : '$minQty';
                        // Metode 2 ditampilkan sebagai harga PAKET (angka yang
                        // diketik pemilik), turunan per satuan di baris kedua
                        // supaya tidak ada angka yang "hilang" dari layar.
                        final judul = paket != null && paket > 0
                            ? 'Mulai $qtyTeks $satuan -> ${_fmtRp.format(paket)} / paket'
                            : 'Mulai $qtyTeks $satuan -> ${_fmtRp.format(perSatuan)} / $satuan';
                        final rinci = <String>[
                          if (paket != null && paket > 0)
                            '= ${_fmtRp.format(perSatuan)} / $satuan',
                          if (a['kelipatanWajib'] == true) 'wajib kelipatan',
                          a['tokoId'] == null ? 'semua toko' : 'toko ini',
                        ].join(' · ');
                        return InkWell(
                          // Ketuk = UBAH aturan ini (prefill), bukan buat baru.
                          onTap: () => _editorAturan(a),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(judul,
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600)),
                                    Text(rinci,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondaryOf(
                                                context))),
                                  ],
                                ),
                              ),
                              IconButton(
                                iconSize: 18,
                                tooltip: 'Ubah aturan ini',
                                onPressed: () => _editorAturan(a),
                                icon: const Icon(Icons.edit_outlined),
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
                          ),
                        );
                      }).toList(),
                    ),
    );
  }
}
