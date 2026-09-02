import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api_client.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/medication_card.dart';

typedef PanggilFormularium = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// <h3>Formularium / Master Obat (Fase 5).</h3>
///
/// Melengkapi lingkaran IR-01: atribut yang dipakai kartu obat POS
/// (golongan, bentuk sediaan, kekuatan, LASA, high-alert, cold-chain) kini
/// **dapat diisi apoteker** lewat `apotik_item_profil_simpan`. Tanpa layar
/// ini, badge-badge tersebut tidak akan pernah muncul di produksi karena
/// tidak ada yang bisa mengisinya.
///
/// Pencarian tetap **server-side** (`apotik_item_cari` ber-halaman) supaya
/// katalog puluhan ribu obat tidak pernah dimuat seluruhnya ke memori —
/// keputusan performa yang sudah benar di layar lama dan dipertahankan.
class ApotikFormulariumPage extends StatefulWidget {
  final PanggilFormularium? panggil;
  const ApotikFormulariumPage({super.key, this.panggil});

  @override
  State<ApotikFormulariumPage> createState() => _ApotikFormulariumPageState();
}

class _ApotikFormulariumPageState extends State<ApotikFormulariumPage> {
  late final PanggilFormularium _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  final _cari = TextEditingController();
  Timer? _debounce;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _item = [];

  @override
  void initState() {
    super.initState();
    _muat('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cari.dispose();
    super.dispose();
  }

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  Future<void> _muat(String keyword) async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await _panggil(
          'apotik_item_cari', {'keyword': keyword, 'page_size': 50});
      if (!_sukses(r)) {
        setStateIfMounted(() {
          _galat = '${r['description'] ?? 'Gagal memuat formularium.'}';
          _memuat = false;
        });
        return;
      }
      setStateIfMounted(() {
        _item = ((r['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
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

  void _cariDebounce(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _muat(v));
  }

  Future<void> _editProfil(Map<String, dynamic> item) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogProfilObat(item: item),
    );
    if (hasil == null || !mounted) return;
    try {
      final r = await _panggil('apotik_item_profil_simpan', {
        'item_id': item['id'],
        ...hasil,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_sukses(r)
            ? 'Profil ${item['nama']} tersimpan.'
            : 'Gagal: ${r['description'] ?? r['status']}'),
        backgroundColor:
            _sukses(r) ? null : Theme.of(context).colorScheme.error,
      ));
      if (_sukses(r)) _muat(_cari.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan profil: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return ApotikResponsive(builder: (context, layout) {
      final padding = ApotikBreakpoints.paddingHalaman(layout);
      return Scaffold(
        backgroundColor: t.surfaceMuted,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ApotikPageHeader(
            judul: 'Formularium / Master Obat',
            subjudul:
                'Atur golongan, bentuk sediaan, kekuatan, LASA, high-alert, '
                'dan cold-chain',
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: TextField(
              controller: _cari,
              decoration: InputDecoration(
                hintText: 'Cari nama obat, kode, atau barcode…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _memuat
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
              onChanged: _cariDebounce,
              onSubmitted: _muat,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _galat != null
                ? ApotikErrorState(
                    pesan: _galat!, onCobaLagi: () => _muat(_cari.text))
                : (_memuat && _item.isEmpty)
                    ? const ApotikLoadingState(pesan: 'Memuat formularium…')
                    : _item.isEmpty
                        ? const ApotikEmptyState(
                            ikon: Icons.medication_outlined,
                            judul: 'Obat tidak ditemukan',
                            petunjuk:
                                'Coba kata kunci lain. Obat baru ditambahkan '
                                'lewat modul persediaan/penerimaan.')
                        : _grid(padding),
          ),
        ]),
      );
    });
  }

  Widget _grid(double padding) {
    return LayoutBuilder(builder: (context, c) {
      final kolom = (c.maxWidth / 330).floor().clamp(1, 4);
      const jarak = ApotikDesignTokens.gridSpacing;
      final lebar = (c.maxWidth - padding * 2 - jarak * (kolom - 1)) / kolom;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 0, padding, 16),
        child: Wrap(
          spacing: jarak,
          runSpacing: jarak,
          children: [
            for (final item in _item)
              SizedBox(
                width: lebar,
                // Kartu yang SAMA dengan katalog POS -- apoteker melihat
                // persis apa yang nanti dilihat kasir setelah profil diubah.
                child:
                    MedicationCard(item: item, onTap: () => _editProfil(item)),
              ),
          ],
        ),
      );
    });
  }
}

/// Form profil obat (IR-01). Hanya field yang DIUBAH yang dikirim, mengikuti
/// kontrak server "hanya disentuh bila dikirim".
class _DialogProfilObat extends StatefulWidget {
  final Map<String, dynamic> item;
  const _DialogProfilObat({required this.item});

  @override
  State<_DialogProfilObat> createState() => _DialogProfilObatState();
}

class _DialogProfilObatState extends State<_DialogProfilObat> {
  late String _golongan = '${widget.item['golonganObat'] ?? 'BEBAS'}'.isEmpty
      ? 'BEBAS'
      : '${widget.item['golonganObat'] ?? 'BEBAS'}';
  late final _bentuk =
      TextEditingController(text: '${widget.item['bentukSediaan'] ?? ''}');
  late final _kekuatan =
      TextEditingController(text: '${widget.item['kekuatan'] ?? ''}');
  late bool _lasa = widget.item['lasa'] == true;
  late bool _highAlert = widget.item['highAlert'] == true;
  late bool _coldChain = widget.item['coldChain'] == true;

  @override
  void dispose() {
    _bentuk.dispose();
    _kekuatan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return AlertDialog(
      title: Text('Profil — ${widget.item['nama'] ?? ''}',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: _golongan,
              decoration: const InputDecoration(
                  labelText: 'Golongan obat',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(value: 'BEBAS', child: Text('Bebas')),
                DropdownMenuItem(
                    value: 'BEBAS_TERBATAS', child: Text('Bebas terbatas')),
                DropdownMenuItem(value: 'KERAS', child: Text('Keras (Rx)')),
                DropdownMenuItem(value: 'NARKOTIKA', child: Text('Narkotika')),
                DropdownMenuItem(
                    value: 'PSIKOTROPIKA', child: Text('Psikotropika')),
              ],
              onChanged: (v) => setState(() => _golongan = v ?? 'BEBAS'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _kekuatan,
                  decoration: const InputDecoration(
                      labelText: 'Kekuatan',
                      hintText: '500 mg',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _bentuk,
                  decoration: const InputDecoration(
                      labelText: 'Bentuk sediaan',
                      hintText: 'tablet',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('LASA (nama/rupa mirip)'),
              subtitle: Text('Ditebalkan dan diberi badge di katalog kasir',
                  style: TextStyle(fontSize: 11, color: t.textSecondary)),
              value: _lasa,
              onChanged: (v) => setState(() => _lasa = v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('High-alert'),
              subtitle: Text(
                  'Risiko cedera tinggi bila salah — perlu '
                  'pemeriksaan kedua',
                  style: TextStyle(fontSize: 11, color: t.textSecondary)),
              value: _highAlert,
              onChanged: (v) => setState(() => _highAlert = v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Cold-chain (2–8 °C)'),
              value: _coldChain,
              onChanged: (v) => setState(() => _coldChain = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(context, <String, dynamic>{
            'golongan_obat': _golongan,
            'lasa': _lasa,
            'bentuk_sediaan': _bentuk.text.trim(),
            'kekuatan': _kekuatan.text.trim(),
            'high_alert': _highAlert,
            'cold_chain': _coldChain,
          }),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
