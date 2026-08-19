import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/app_shell.dart';
import 'pos_help.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Persediaan Apotik -- FASE B (formularium, batch/ED, PBF, opname, retur).</h3>
///
/// Lima tab di atas aksi server FASE B (`apotik_terima_barang`,
/// `apotik_opname_simpan`, `apotik_retur_simpan`, `apotik_batch_monitor`) +
/// formularium (`apotik_item_cari`/`apotik_item_profil_simpan`). Semua mutasi
/// stok terjadi di server lewat ledger SIRS bertanda -- layar ini tidak pernah
/// menghitung stok sendiri.
class PersediaanApotikScreen extends StatefulWidget {
  final int tabAwal;
  const PersediaanApotikScreen({super.key, this.tabAwal = 0});

  @override
  State<PersediaanApotikScreen> createState() => _PersediaanApotikScreenState();
}

class _PersediaanApotikScreenState extends State<PersediaanApotikScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final GlobalKey<_TabFormulariumState> _formulariumKey =
      GlobalKey<_TabFormulariumState>();
  bool _provisionBerjalan = false;
  String _statusProvision = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 5, vsync: this, initialIndex: widget.tabAwal.clamp(0, 4));
    _tab.addListener(_ubahTab);
    unawaited(_pulihkanPemantauanProvision());
  }

  void _ubahTab() {
    if (!_tab.indexIsChanging && mounted) setState(() {});
  }

  Future<void> _isiDataContoh() async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Isi data contoh Apotik?'),
        content: const Text(
            'Server akan menyiapkan 10.000 obat, 5.000 racikan, batch, stok, '
            'tenaga medis, dan akun demo secara idempoten. Data lama tidak '
            'digandakan. Fitur ini hanya dapat berjalan pada toko demo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Mulai di Latar')),
        ],
      ),
    );
    if (setuju != true) return;
    setStateIfMounted(() => _provisionBerjalan = true);
    setStateIfMounted(() => _statusProvision = 'Memulai...');
    try {
      final hasil = await ApiClient.instance.aksi('apotik_provision_demo', {
        'konfirmasi': 'SEED-DEMO-APOTIK',
        'background': true,
      });
      if (!mounted) return;
      setStateIfMounted(() => _statusProvision = 'Sedang diproses...');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('${hasil['description'] ?? 'Data contoh sedang dibuat.'}')));
      await _pantauProvisionSampaiSelesai();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memulai data contoh: $e')));
      setStateIfMounted(() => _provisionBerjalan = false);
      setStateIfMounted(() => _statusProvision = 'Gagal');
    }
  }

  Future<void> _pulihkanPemantauanProvision() async {
    try {
      final hasil = await _statusProvisionServer();
      if (!mounted || hasil['berjalan'] != true) return;
      setStateIfMounted(() {
        _provisionBerjalan = true;
        _statusProvision = _statusTahapProvision(hasil);
      });
      await _pantauProvisionSampaiSelesai();
    } catch (_) {
      // Status latar bukan blocker saat layar pertama kali dibuka.
    }
  }

  Future<Map<String, dynamic>> _statusProvisionServer() {
    return ApiClient.instance.aksi('apotik_provision_demo', {
      'konfirmasi': 'SEED-DEMO-APOTIK',
      'status_only': true,
    });
  }

  String _ringkasProvision(dynamic value) {
    final teks = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (teks.isEmpty) return 'Tanpa rincian dari server.';
    return teks.length > 500 ? '${teks.substring(0, 500)}...' : teks;
  }

  String _statusTahapProvision(Map<String, dynamic> hasil) {
    final tahap = '${hasil['tahap'] ?? ''}'.trim();
    return tahap.isEmpty ? 'Sedang diproses...' : tahap;
  }

  Future<void> _pantauProvisionSampaiSelesai() async {
    var gagalStatusBeruntun = 0;
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Map<String, dynamic> hasil;
      try {
        hasil = await _statusProvisionServer();
        gagalStatusBeruntun = 0;
      } catch (e) {
        gagalStatusBeruntun++;
        if (gagalStatusBeruntun < 5) continue;
        rethrow;
      }
      if (hasil['berjalan'] == true) {
        final tahap = _statusTahapProvision(hasil);
        if (_statusProvision != tahap) {
          setStateIfMounted(() => _statusProvision = tahap);
        }
        continue;
      }

      final berhasil = await _provisionBerhasilKompatibel(hasil);
      setStateIfMounted(() {
        _provisionBerjalan = false;
        _statusProvision = berhasil ? 'Selesai' : 'Gagal';
      });
      if (!mounted) return;
      if (berhasil) {
        _tab.animateTo(0);
        await _formulariumKey.currentState?.muatUlang();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Data contoh selesai dan daftar obat sudah dimuat ulang.'),
          backgroundColor: Colors.green,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Pembuatan data contoh gagal: ${_ringkasProvision(hasil['ringkasan'])}'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 12),
        ));
      }
      return;
    }
  }

  /// Server lama belum mengirim field `selesai` dan `berhasil`. Tetap baca
  /// ringkasan hasil worker dan, sebagai verifikasi terakhir, cek satu item
  /// formularium. Ini mencegah UI melaporkan gagal padahal commit sudah sukses.
  Future<bool> _provisionBerhasilKompatibel(Map<String, dynamic> hasil) async {
    if (hasil.containsKey('selesai') || hasil.containsKey('berhasil')) {
      return hasil['selesai'] == true && hasil['berhasil'] == true;
    }
    final ringkasan = '${hasil['ringkasan'] ?? ''}'.trim();
    if (ringkasan.toUpperCase().startsWith('GAGAL')) return false;
    if (ringkasan.startsWith('{')) {
      try {
        final parsed = jsonDecode(ringkasan);
        if (parsed is Map && '${parsed['status']}' == '00') return true;
      } catch (_) {
        // Ringkasan bukan JSON; lanjutkan ke pemeriksaan data aktual.
      }
    }
    try {
      final daftar = await ApiClient.instance.aksi('apotik_item_cari', {
        'keyword': '',
        'page_size': 1,
      });
      final data = daftar['data'];
      return data is List && data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_ubahTab);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bantuan = const [
      'apotik_formularium',
      'apotik_batch',
      'apotik_pengadaan',
      'apotik_stok_opname',
      'apotik_retur'
    ][_tab.index];
    final bolehDataContoh = Sesi.instance.bolehDataSample;
    return AppShell(
      menuAktif: MenuEBisnis.persediaanApotik,
      judul: 'Obat & Persediaan',
      subjudul: 'Formularium, batch, PBF, stok opname, dan retur obat',
      scrollable: false,
      actionsAppBar: [PosHelp.button(context, bantuan, compact: true)],
      aksiHeader: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (bolehDataContoh)
            OutlinedButton.icon(
              onPressed: _provisionBerjalan ? null : _isiDataContoh,
              icon: _provisionBerjalan
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(_provisionBerjalan
                  ? (_statusProvision.isEmpty
                      ? 'Memproses Data Contoh...'
                      : _statusProvision)
                  : 'Data Contoh'),
            ),
          PosHelp.button(context, bantuan),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(10),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Formularium'),
                Tab(text: 'Batch & Kedaluwarsa'),
                Tab(text: 'Penerimaan PBF'),
                Tab(text: 'Stok Opname'),
                Tab(text: 'Retur Obat'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _TabFormularium(key: _formulariumKey),
                const _TabBatchMonitor(),
                const _TabPenerimaanPbf(),
                const _TabOpname(),
                const _TabRetur(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Picker item bersama -- cari via `apotik_item_cari`, kembalikan Map item.
Future<Map<String, dynamic>?> _pilihItem(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SheetCariItem(),
  );
}

class _SheetCariItem extends StatefulWidget {
  const _SheetCariItem();

  @override
  State<_SheetCariItem> createState() => _SheetCariItemState();
}

class _SheetCariItemState extends State<_SheetCariItem> {
  final _cari = TextEditingController();
  Timer? _debounce;
  bool _memuat = false;
  List<Map<String, dynamic>> _data = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _cari.dispose();
    super.dispose();
  }

  void _berubah(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (v.trim().isEmpty) return;
      setStateIfMounted(() => _memuat = true);
      try {
        final hasil = await ApiClient.instance
            .aksi('apotik_item_cari', {'keyword': v.trim(), 'page_size': 20});
        setStateIfMounted(() => _data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
      } catch (_) {
        // Biarkan daftar lama; kegagalan cari bukan blocker sheet.
      } finally {
        setStateIfMounted(() => _memuat = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _cari,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Cari obat: kode / barcode / nama...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: _berubah,
          ),
        ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  controller: sc,
                  itemCount: _data.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = _data[i];
                    return ListTile(
                      dense: true,
                      title: Text('${it['nama']}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${it['kode']} • stok ${it['stok']} • ${it['golonganObat']}',
                          style: const TextStyle(fontSize: 11.5)),
                      onTap: () => Navigator.pop(context, it),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Tab 1 -- Formularium: daftar obat + set golongan/LASA
// =============================================================================

class _TabFormularium extends StatefulWidget {
  const _TabFormularium({super.key});

  @override
  State<_TabFormularium> createState() => _TabFormulariumState();
}

class _TabFormulariumState extends State<_TabFormularium> {
  final _cari = TextEditingController();
  bool _memuat = false;
  List<Map<String, dynamic>> _data = [];
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan petugas lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('apotik_item_cari', {
        if (_cari.text.trim().isNotEmpty) 'keyword': _cari.text.trim(),
        'page_size': 30,
      }, 'master:apotik_item', onData: (hasil) {
        if (!mounted) return;
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          _idBaru = dariServer
              ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(
                  hasil['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus =
              dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
          if (dariServer &&
              (_idBaru.isNotEmpty ||
                  _idBerubah.isNotEmpty ||
                  _jumlahHapus > 0)) {
            _versiPerubahan++;
          }
          _memuat = false;
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> muatUlang() => _muat();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _ubahProfil(Map<String, dynamic> it) async {
    var golongan = '${it['golonganObat'] ?? 'BEBAS'}';
    var lasa = it['lasa'] == true;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${it['nama']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: golongan,
              decoration: const InputDecoration(
                  labelText: 'Golongan Obat', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'BEBAS', child: Text('Bebas')),
                DropdownMenuItem(
                    value: 'BEBAS_TERBATAS', child: Text('Bebas Terbatas')),
                DropdownMenuItem(value: 'KERAS', child: Text('Keras')),
                DropdownMenuItem(value: 'NARKOTIKA', child: Text('Narkotika')),
                DropdownMenuItem(
                    value: 'PSIKOTROPIKA', child: Text('Psikotropika')),
              ],
              onChanged: (v) => setD(() => golongan = v ?? 'BEBAS'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('LASA (Look-Alike Sound-Alike)'),
              subtitle: const Text('Tampil beda di kasir agar tidak tertukar',
                  style: TextStyle(fontSize: 11)),
              value: lasa,
              onChanged: (v) => setD(() => lasa = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(context, aksi: 'apotik_item_profil_simpan',
          body: {
            'item_id': it['id'],
            'golongan_obat': golongan,
            'lasa': lasa,
          },
          kunci: 'apotik_item:${it['id']}');
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal simpan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        TextField(
          controller: _cari,
          decoration: const InputDecoration(
              hintText: 'Cari obat...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true),
          onSubmitted: (_) => _muat(),
        ),
        const SizedBox(height: 8),
        BannerPerubahanServer(
          key: ValueKey('perubahan:$_versiPerubahan'),
          baru: _idBaru.length,
          berubah: _idBerubah.length,
          dihapus: _jumlahHapus,
        ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _data.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = _data[i];
                    final terkendali = it['terkendali'] == true;
                    return KilauBaris(
                      kunci: '${it['id'] ?? it['_kunci'] ?? ''}',
                      idBaru: _idBaru,
                      idBerubah: _idBerubah,
                      child: ListTile(
                        dense: true,
                        title: Text('${it['nama']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${it['kode']} • stok ${it['stok']} • ${_rp.format((it['hargaJual'] as num?) ?? 0)}',
                            style: const TextStyle(fontSize: 11.5)),
                        trailing: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (it['lasa'] == true)
                                const StatusPill(
                                    label: 'LASA', warna: Color(0xFFB8860B)),
                              StatusPill(
                                  label: '${it['golonganObat']}',
                                  warna: terkendali
                                      ? AppColors.danger
                                      : AppColors.teal),
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Riwayat data ini (AuditTrails)',
                                  icon: const Icon(Icons.history, size: 16),
                                  onPressed: () => tampilkanRiwayatData(context,
                                      entitas: 'apotik_item',
                                      id: it['id'],
                                      judul: '${it['nama'] ?? ''}')),
                            ]),
                        onTap: () => _ubahProfil(it),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Tab 2 -- Batch & Kedaluwarsa (monitor lintas item)
// =============================================================================

class _TabBatchMonitor extends StatefulWidget {
  const _TabBatchMonitor();

  @override
  State<_TabBatchMonitor> createState() => _TabBatchMonitorState();
}

class _TabBatchMonitorState extends State<_TabBatchMonitor> {
  bool _memuat = true;
  int _hari = 90;
  List<Map<String, dynamic>> _data = [];

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi(
          'apotik_batch_monitor', {'hari_ke_depan': _hari, 'page_size': 100});
      setStateIfMounted(() => _data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          const Text('Kedaluwarsa dalam:'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _hari,
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 hari')),
              DropdownMenuItem(value: 90, child: Text('90 hari')),
              DropdownMenuItem(value: 180, child: Text('180 hari')),
              DropdownMenuItem(value: 365, child: Text('1 tahun')),
            ],
            onChanged: (v) {
              _hari = v ?? 90;
              _muat();
            },
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
        ]),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _data.isEmpty
                  ? const Center(
                      child:
                          Text('Tidak ada batch mendekati kedaluwarsa. Bagus.'))
                  : ListView.separated(
                      itemCount: _data.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final b = _data[i];
                        final expired = b['kedaluwarsa'] == true;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              expired
                                  ? Icons.dangerous_outlined
                                  : Icons.schedule,
                              color: expired
                                  ? AppColors.danger
                                  : AppColors.warning),
                          title: Text('${b['nama']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${b['kode']} • sisa ${b['sisa']} • ED ${b['tanggalKadaluarsa']}',
                              style: const TextStyle(fontSize: 11.5)),
                          trailing: StatusPill(
                              label: expired ? 'KEDALUWARSA' : 'SEGERA',
                              warna: expired
                                  ? AppColors.danger
                                  : AppColors.warning),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Baris input bersama utk tab Penerimaan/Opname/Retur
// =============================================================================

class _BarisInput {
  final Map<String, dynamic> item;
  final TextEditingController qty = TextEditingController(text: '1');
  final TextEditingController harga = TextEditingController(text: '0');
  final TextEditingController ed = TextEditingController();
  _BarisInput(this.item);

  void dispose() {
    qty.dispose();
    harga.dispose();
    ed.dispose();
  }
}

// =============================================================================
// Tab 3 -- Penerimaan PBF
// =============================================================================

class _TabPenerimaanPbf extends StatefulWidget {
  const _TabPenerimaanPbf();

  @override
  State<_TabPenerimaanPbf> createState() => _TabPenerimaanPbfState();
}

class _TabPenerimaanPbfState extends State<_TabPenerimaanPbf> {
  final _penyedia = TextEditingController();
  final _noFaktur = TextEditingController();
  final List<_BarisInput> _baris = [];
  bool _proses = false;

  @override
  void dispose() {
    _penyedia.dispose();
    _noFaktur.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _tambah() async {
    final it = await _pilihItem(context);
    if (it != null) setStateIfMounted(() => _baris.add(_BarisInput(it)));
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) return;
    setStateIfMounted(() => _proses = true);
    try {
      final hasil = await ApiClient.instance.aksi('apotik_terima_barang', {
        'penyedia': _penyedia.text.trim(),
        'no_faktur': _noFaktur.text.trim(),
        'items': _baris
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty': double.tryParse(b.qty.text) ?? 0,
                  'harga_beli':
                      double.tryParse(b.harga.text.replaceAll(',', '.')) ?? 0,
                  if (b.ed.text.trim().isNotEmpty)
                    'tanggal_kadaluarsa': b.ed.text.trim(),
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Penerimaan tercatat: ${hasil['jumlahBaris']} baris, ${hasil['jumlahBatch']} batch ED.')));
        setStateIfMounted(() {
          for (final b in _baris) {
            b.dispose();
          }
          _baris.clear();
          _penyedia.clear();
          _noFaktur.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ditolak: $e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(
            child: TextField(
                controller: _penyedia,
                decoration: const InputDecoration(
                    labelText: 'PBF / Pemasok',
                    border: OutlineInputBorder(),
                    isDense: true))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: _noFaktur,
                decoration: const InputDecoration(
                    labelText: 'No. Faktur',
                    border: OutlineInputBorder(),
                    isDense: true))),
      ]),
      const SizedBox(height: 10),
      ..._baris.asMap().entries.map((e) {
        final b = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text('${b.item['nama']}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    onPressed: () => setStateIfMounted(() {
                          _baris.removeAt(e.key).dispose();
                        })),
              ]),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: b.qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Qty',
                            border: OutlineInputBorder(),
                            isDense: true))),
                const SizedBox(width: 6),
                Expanded(
                    child: TextField(
                        controller: b.harga,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Harga Beli',
                            border: OutlineInputBorder(),
                            isDense: true))),
                const SizedBox(width: 6),
                Expanded(
                    child: TextField(
                        controller: b.ed,
                        decoration: const InputDecoration(
                            labelText: 'ED (yyyy-mm-dd)',
                            border: OutlineInputBorder(),
                            isDense: true))),
              ]),
            ]),
          ),
        );
      }),
      OutlinedButton.icon(
          onPressed: _tambah,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Obat')),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: _baris.isEmpty || _proses ? null : _simpan,
        icon: _proses
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.inventory_2_outlined),
        label: const Text('Catat Penerimaan'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
    ]);
  }
}

// =============================================================================
// Tab 4 -- Stok Opname
// =============================================================================

class _TabOpname extends StatefulWidget {
  const _TabOpname();

  @override
  State<_TabOpname> createState() => _TabOpnameState();
}

class _TabOpnameState extends State<_TabOpname> {
  final List<_BarisInput> _baris = [];
  bool _proses = false;
  List<Map<String, dynamic>> _hasilTerakhir = [];

  @override
  void dispose() {
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _tambah() async {
    final it = await _pilihItem(context);
    if (it != null) {
      final b = _BarisInput(it);
      b.qty.text = '${it['stok'] ?? 0}';
      setStateIfMounted(() => _baris.add(b));
    }
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) return;
    setStateIfMounted(() => _proses = true);
    try {
      final hasil = await ApiClient.instance.aksi('apotik_opname_simpan', {
        'items': _baris
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty_fisik': double.tryParse(b.qty.text) ?? 0,
                })
            .toList(),
      });
      setStateIfMounted(() {
        _hasilTerakhir =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        for (final b in _baris) {
          b.dispose();
        }
        _baris.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ditolak: $e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      ..._baris.asMap().entries.map((e) {
        final b = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            title: Text('${b.item['nama']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Stok sistem: ${b.item['stok']}'),
            trailing: SizedBox(
              width: 110,
              child: TextField(
                  controller: b.qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Qty Fisik',
                      border: OutlineInputBorder(),
                      isDense: true)),
            ),
            onLongPress: () => setStateIfMounted(() {
              _baris.removeAt(e.key).dispose();
            }),
          ),
        );
      }),
      OutlinedButton.icon(
          onPressed: _tambah,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Obat Diopname')),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: _baris.isEmpty || _proses ? null : _simpan,
        icon: _proses
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.fact_check_outlined),
        label: const Text('Simpan Opname (koreksi selisih)'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
      if (_hasilTerakhir.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Text('Hasil opname terakhir:',
            style: TextStyle(fontWeight: FontWeight.w800)),
        ..._hasilTerakhir.map((r) => ListTile(
              dense: true,
              title: Text('${r['nama']}'),
              subtitle:
                  Text('sistem ${r['stokSistem']} -> fisik ${r['qtyFisik']}'),
              trailing: Text('${(r['selisih'] as num?) ?? 0}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ((r['selisih'] as num?) ?? 0) == 0
                          ? AppColors.success
                          : AppColors.warning)),
            )),
      ],
    ]);
  }
}

// =============================================================================
// Tab 5 -- Retur Obat
// =============================================================================

class _TabRetur extends StatefulWidget {
  const _TabRetur();

  @override
  State<_TabRetur> createState() => _TabReturState();
}

class _TabReturState extends State<_TabRetur> {
  String _jenis = 'penjualan';
  final _keterangan = TextEditingController();
  final List<_BarisInput> _baris = [];
  bool _proses = false;

  @override
  void dispose() {
    _keterangan.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _tambah() async {
    final it = await _pilihItem(context);
    if (it != null) setStateIfMounted(() => _baris.add(_BarisInput(it)));
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) return;
    setStateIfMounted(() => _proses = true);
    try {
      await ApiClient.instance.aksi('apotik_retur_simpan', {
        'jenis': _jenis,
        'keterangan': _keterangan.text.trim(),
        'items': _baris
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty': double.tryParse(b.qty.text) ?? 0,
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Retur tercatat.')));
        setStateIfMounted(() {
          for (final b in _baris) {
            b.dispose();
          }
          _baris.clear();
          _keterangan.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ditolak: $e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
              value: 'penjualan',
              label: Text('Dari Pembeli (masuk)'),
              icon: Icon(Icons.assignment_return_outlined)),
          ButtonSegment(
              value: 'pbf',
              label: Text('Ke PBF (keluar)'),
              icon: Icon(Icons.local_shipping_outlined)),
        ],
        selected: {_jenis},
        onSelectionChanged: (s) => setStateIfMounted(() => _jenis = s.first),
      ),
      const SizedBox(height: 10),
      TextField(
          controller: _keterangan,
          decoration: const InputDecoration(
              labelText: 'Keterangan / alasan retur',
              border: OutlineInputBorder(),
              isDense: true)),
      const SizedBox(height: 10),
      ..._baris.asMap().entries.map((e) {
        final b = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            title: Text('${b.item['nama']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Stok: ${b.item['stok']}'),
            trailing: SizedBox(
              width: 100,
              child: TextField(
                  controller: b.qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      isDense: true)),
            ),
            onLongPress: () => setStateIfMounted(() {
              _baris.removeAt(e.key).dispose();
            }),
          ),
        );
      }),
      OutlinedButton.icon(
          onPressed: _tambah,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Obat')),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: _baris.isEmpty || _proses ? null : _simpan,
        icon: _proses
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.assignment_return_outlined),
        label: const Text('Catat Retur'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
    ]);
  }
}
