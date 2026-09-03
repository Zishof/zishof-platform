import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/master_offline.dart';
import '../../../widgets/kilau_perubahan.dart';
import '../../../widgets/proses_simpan_master.dart';
import '../../../widgets/riwayat_data_dialog.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_lokal_dulu.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/medication_card.dart';

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
  final MuatDaftarApotik? muatDaftar;
  final SimpanMasterApotik? simpan;

  const ApotikFormulariumPage({super.key, this.muatDaftar, this.simpan});

  @override
  State<ApotikFormulariumPage> createState() => _ApotikFormulariumPageState();
}

class _ApotikFormulariumPageState extends State<ApotikFormulariumPage> {
  late final MuatDaftarApotik _muatDaftar =
      widget.muatDaftar ?? MasterOffline.daftarCacheDulu;
  late final SimpanMasterApotik _simpan = widget.simpan ?? prosesSimpanMaster;

  final _cari = TextEditingController();
  Timer? _debounce;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _item = [];

  /// Diff dari emisi server: menggerakkan animasi kilau baris dan bilah
  /// "pembaruan dari server" — termasuk perubahan yang dibuat petugas lain.
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;

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

  /// Baca LOKAL DULU: snapshot cache tampil seketika, hasil server menyusul
  /// beserta diff baru/berubah/terhapus untuk animasi. Saat server tidak
  /// terjangkau, daftar terakhir tetap terbaca alih-alih layar kosong.
  Future<void> _muat(String keyword) async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await _muatDaftar(
        'apotik_item_cari',
        {
          if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
          'page_size': 50,
        },
        kunciCacheItemApotik,
        onData: (hasil) {
          if (!mounted) return;
          final dariServer = hasil['dariServer'] == true;
          final data = ((hasil['data'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setStateIfMounted(() {
            // Emisi cache disaring ulang: cache menyimpan hasil kueri
            // TERAKHIR, bukan kueri yang sedang diketik.
            _item = dariServer ? data : saringCacheLokal(data, keyword);
            _idBaru = dariServer
                ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
                : {};
            _idBerubah = dariServer
                ? Set<String>.from(
                    hasil['idBerubah'] as Set? ?? const <String>{})
                : {};
            _jumlahHapus = dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        // Daftar dari cache (bila ada) TIDAK dibuang: galat ditampilkan hanya
        // bila memang tidak ada apa pun untuk ditunjukkan.
        if (_item.isEmpty) _galat = '$e';
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
      // Alur "lokal dulu" ber-indikator animasi: antre -> coba kirim -> tutup.
      // Saat offline profil tetap tersimpan di cache lokal dan dikirim ulang
      // otomatis, jadi apoteker tidak kehilangan pekerjaannya.
      final res = await _simpan(
        context,
        aksi: 'apotik_item_profil_simpan',
        body: {'item_id': item['id'], ...hasil},
        kunci: 'apotik_item_profil:${item['id']}',
        cacheKey: kunciCacheItemApotik,
        rowLokal: {...item, ..._rowLokalDariForm(hasil)},
      );
      if (!mounted) return;
      // Saat offline daftar TIDAK dimuat ulang dari server; cache lokal sudah
      // diperbarui oleh prosesSimpanMaster.
      if (res['offline'] != true) _muat(_cari.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan profil: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  /// Terjemahan field form (snake_case, bahasa server) ke bentuk baris cache
  /// (camelCase, bentuk yang dibaca kartu obat).
  Map<String, dynamic> _rowLokalDariForm(Map<String, dynamic> form) => {
        if (form.containsKey('golongan_obat'))
          'golonganObat': form['golongan_obat'],
        if (form.containsKey('lasa')) 'lasa': form['lasa'],
        if (form.containsKey('bentuk_sediaan'))
          'bentukSediaan': form['bentuk_sediaan'],
        if (form.containsKey('kekuatan')) 'kekuatan': form['kekuatan'],
        if (form.containsKey('high_alert')) 'highAlert': form['high_alert'],
        if (form.containsKey('cold_chain')) 'coldChain': form['cold_chain'],
      };

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
          if (_idBaru.isNotEmpty || _idBerubah.isNotEmpty || _jumlahHapus > 0)
            _bilahPerubahan(t),
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

  /// Bilah "pembaruan dari server": memberi tahu bahwa daftar berubah karena
  /// petugas lain, bukan karena tindakan pengguna ini.
  Widget _bilahPerubahan(ApotikDesignTokens t) {
    final bagian = <String>[
      if (_idBaru.isNotEmpty) '${_idBaru.length} baru',
      if (_idBerubah.isNotEmpty) '${_idBerubah.length} berubah',
      if (_jumlahHapus > 0) '$_jumlahHapus dihapus',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(color: t.info.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.cloud_download_outlined, size: 15, color: t.info),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Pembaruan dari server: ${bagian.join(', ')}.',
              style: TextStyle(fontSize: 11.5, color: t.textPrimary)),
        ),
      ]),
    );
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
                child: KilauBaris(
                  kunci: MasterOffline.kunciBaris(item),
                  idBaru: _idBaru,
                  idBerubah: _idBerubah,
                  child: MedicationCard(
                    item: item,
                    onTap: () => _editProfil(item),
                    aksiTambahan: IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Riwayat data ini (AuditTrails)',
                      icon: const Icon(Icons.history, size: 16),
                      onPressed: () => tampilkanRiwayatData(
                        context,
                        entitas: 'apotik_item',
                        id: item['id'],
                        judul: '${item['nama'] ?? ''}',
                      ),
                    ),
                  ),
                ),
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
