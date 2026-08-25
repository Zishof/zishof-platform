import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../services/master_offline.dart';
import '../services/simple_xlsx.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_baris_sinkron.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';

/// Grup Produk (harga terpusat lintas toko) -- padanan layar ZK GrupProdukAction.
///
/// Grup memegang HPP + resep bahan baku + harga jual TERPUSAT; dua sakelar
/// menentukan perilakunya: "HPP selalu mengikuti Grup" (menyalin HPP+resep ke
/// seluruh anggota di semua toko) dan "Harga Jual selalu sama dengan Grup".
/// Keduanya mati = grup murni pengelompokan. Grup juga bisa menautkan satu
/// Aturan Diskon yang otomatis berlaku utk semua produk anggota (dievaluasi
/// dinamis mesin diskon server, tidak disalin per-baris). Keanggotaan produk
/// dikelola langsung di form (cari/unggah/unduh Excel -- pola GrupAturanDiskon).
class GrupProdukScreen extends StatefulWidget {
  const GrupProdukScreen({super.key});

  @override
  State<GrupProdukScreen> createState() => _GrupProdukScreenState();
}

class _GrupProdukScreenState extends State<GrupProdukScreen> {
  final _formatRupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

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
      // Nama aksi mengikuti kontrak server r77580 (GrupProdukApiHelper):
      // grup_produk_daftar dengan parameter hanya_aktif (default true).
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu(
          'grup_produk_daftar', {'hanya_aktif': false}, 'master:grup_produk',
          // Aksi ini mengembalikan SELURUH grup (tanpa paginasi) -- baris
          // lokal yang hilang dari respons memang terhapus di server.
          responsLengkap: true, onData: (res) {
        if (!mounted) return;
        final sukses = res['status'] == '00' || res['status'] == 'success';
        if (!sukses) {
          setStateIfMounted(() {
            _galat = '${res['description'] ?? 'Gagal memuat Grup Produk.'}';
            _memuat = false;
          });
          return;
        }
        final data = (res['data'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final dariServer = res['dariServer'] == true;
        setStateIfMounted(() {
          _daftar = data;
          _idBaru = dariServer
              ? Set<String>.from(res['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(res['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus = dariServer ? (res['jumlahHapus'] as int? ?? 0) : 0;
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
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _simpan(Map<String, dynamic>? awal) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormGrupDialog(
        awal: awal,
        onSubmit: (hasil) async {
          try {
            await prosesSimpanMaster(
              context,
              aksi: 'grup_produk_simpan',
              body: hasil,
              kunci: hasil['id'] != null
                  ? 'grup_produk:${hasil['id']}'
                  : 'grup_produk:baru:${DateTime.now().microsecondsSinceEpoch}',
              cacheKey: 'master:grup_produk',
              rowLokal: hasil,
            );
            await _muat();
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }

  Future<void> _hapus(Map<String, dynamic> g) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Grup Produk'),
        content: Text('Hapus grup "${g['nama']}"? Grup yang masih dipakai '
            'produk akan ditolak server.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster).
      await prosesSimpanMaster(
        context,
        aksi: 'grup_produk_hapus',
        body: {'id': g['id']},
        kunci: 'grup_produk:${g['id']}',
        cacheKey: 'master:grup_produk',
        rowLokal: {'id': g['id']},
        hapusLokal: true,
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menghapus: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  String _harga(dynamic v) =>
      v == null ? '-' : _formatRupiah.format((v as num).toDouble());

  /// Ringkasan kebijakan grup di bawah harga -- memperlihatkan mana yang
  /// benar-benar disalin ke anggota vs sekadar pengelompokan.
  String _ringkasKebijakan(Map<String, dynamic> g) {
    final bagian = <String>[];
    if (g['ikut_hpp'] == true) bagian.add('HPP ikut grup');
    if (g['ikut_harga_jual'] == true) bagian.add('Jual ikut grup');
    if (bagian.isEmpty) bagian.add('Hanya pengelompokan');
    final bahan = (g['bahan_baku'] as List?)?.length ?? 0;
    if (bahan > 0) bagian.add('$bahan bahan baku');
    final diskon = (g['aturan_diskon_nama'] ?? '').toString();
    if (diskon.isNotEmpty) bagian.add('Diskon: $diskon');
    return bagian.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    // Dibungkus AppShell (bukan Scaffold polos) supaya sidebar kiri + topbar
    // TETAP tampil -- sebelumnya layar ini satu-satunya yang tampil "telanjang".
    return AppShell(
      menuAktif: MenuEBisnis.grupProduk,
      judul: 'Grup Produk',
      subjudul: 'HPP, resep, harga jual & diskon terpusat lintas toko',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader:
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _simpan(null),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Grup'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ],
                  ),
                ))
              : _daftar.isEmpty
                  ? const Center(
                      child: Text(
                          'Belum ada grup. Buat grup untuk produk yang bahannya '
                          'sama di banyak outlet,\nlalu kelola produk anggotanya '
                          'langsung di form grup ini.',
                          textAlign: TextAlign.center))
                  : Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: BannerPerubahanServer(
                            key: ValueKey('perubahan:$_versiPerubahan'),
                            baru: _idBaru.length,
                            berubah: _idBerubah.length,
                            dihapus: _jumlahHapus,
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _muat,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _daftar.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (c, i) {
                                final g = _daftar[i];
                                final aktif = g['aktif'] == true;
                                return Card(
                                  child: ListTile(
                                    title: KilauBaris(
                                      kunci: '${g['id'] ?? g['_kunci'] ?? ''}',
                                      idBaru: _idBaru,
                                      idBerubah: _idBerubah,
                                      child: Row(children: [
                                        IndikatorBarisSinkron(
                                            kunci: kunciBarisMaster(
                                                'grup_produk', g)),
                                        Expanded(
                                          child: Text(
                                              '${(g['kode'] ?? '').toString().isEmpty ? '' : '${g['kode']} - '}${g['nama']}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ),
                                      ]),
                                    ),
                                    subtitle: Text(
                                        'HPP ${_harga(g['harga_beli'])}  ·  Jual ${_harga(g['harga_jual'])}  ·  ${g['jumlah_anggota']} produk anggota${aktif ? '' : '  ·  NONAKTIF'}\n'
                                        '${_ringkasKebijakan(g)}'),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (g['id'] != null)
                                          IconButton(
                                              tooltip:
                                                  'Riwayat data ini (AuditTrails)',
                                              onPressed: () =>
                                                  tampilkanRiwayatData(context,
                                                      entitas: 'grup_produk',
                                                      id: g['id'],
                                                      judul:
                                                          '${g['nama'] ?? ''}'),
                                              icon:
                                                  const Icon(Icons.history)),
                                        IconButton(
                                            tooltip: 'Ubah & terapkan',
                                            onPressed: () => _simpan(g),
                                            icon: const Icon(
                                                Icons.edit_outlined)),
                                        IconButton(
                                            tooltip: 'Hapus',
                                            onPressed: () => _hapus(g),
                                            icon: const Icon(
                                                Icons.delete_outline)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// Satu baris resep bahan baku grup -- format payload SAMA dgn form Produk
/// (`bahan_baku: [{produk_id, nama, qty, harga}]`) supaya server & katalog
/// membaca keduanya tanpa pembedaan.
class _BahanGrupBaris {
  int? produkId;
  String nama;
  final TextEditingController qty;
  final TextEditingController harga;
  _BahanGrupBaris(
      {this.produkId,
      required this.nama,
      String qtyAwal = '1',
      String hargaAwal = '0'})
      : qty = TextEditingController(text: qtyAwal),
        harga = TextEditingController(text: hargaAwal);
  void dispose() {
    qty.dispose();
    harga.dispose();
  }
}

class _FormGrupDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final Future<bool> Function(Map<String, dynamic> data) onSubmit;
  const _FormGrupDialog({this.awal, required this.onSubmit});

  @override
  State<_FormGrupDialog> createState() => _FormGrupDialogState();
}

class _FormGrupDialogState extends State<_FormGrupDialog> {
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _hargaBeli;
  late final TextEditingController _hargaJual;
  late bool _aktif;
  late bool _ikutHpp;
  late bool _ikutJual;

  final List<_BahanGrupBaris> _bahan = [];

  // Aturan Diskon tertaut (berlaku utk semua anggota, dievaluasi server).
  int? _aturanDiskonId;
  List<Map<String, dynamic>> _diskonOpsi = [];
  bool _memuatDiskon = true;

  // Produk anggota grup -- HANYA dikirim ke server bila berhasil dimuat
  // (form offline tidak boleh menghapus keanggotaan tanpa sengaja).
  final List<Map<String, dynamic>> _anggota = [];
  bool _anggotaDimuat = false;
  bool _memuatAnggota = false;
  String? _galatAnggota;

  bool get _baru => widget.awal == null;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _kode = TextEditingController(text: (a?['kode'] ?? '').toString());
    _nama = TextEditingController(text: (a?['nama'] ?? '').toString());
    _keterangan =
        TextEditingController(text: (a?['keterangan'] ?? '').toString());
    _hargaBeli = TextEditingController(
        text: a?['harga_beli'] == null ? '' : '${a!['harga_beli']}');
    _hargaJual = TextEditingController(
        text: a?['harga_jual'] == null ? '' : '${a!['harga_jual']}');
    _aktif = a == null || a['aktif'] == true;
    // Grup lama tanpa toggle dilaporkan server sudah ter-derive (ikut bila
    // harganya terisi); grup BARU default mati = murni pengelompokan.
    _ikutHpp = a?['ikut_hpp'] == true;
    _ikutJual = a?['ikut_harga_jual'] == true;
    _aturanDiskonId = (a?['aturan_diskon'] as num?)?.toInt();
    for (final b in (a?['bahan_baku'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(b as Map);
      _bahan.add(_BahanGrupBaris(
        produkId: (m['produk_id'] ?? m['produkId']) is num
            ? ((m['produk_id'] ?? m['produkId']) as num).toInt()
            : null,
        nama: (m['nama'] ?? '-').toString(),
        qtyAwal: '${m['qty'] ?? 1}',
        hargaAwal: '${m['harga'] ?? 0}',
      ));
    }
    _muatDiskonOpsi();
    if (_baru) {
      _anggotaDimuat = true; // grup baru mulai dari keanggotaan kosong
    } else {
      _muatAnggota();
    }
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    _hargaBeli.dispose();
    _hargaJual.dispose();
    for (final b in _bahan) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _muatDiskonOpsi() async {
    try {
      final r = await ApiClient.instance
          .aksi('diskon_list', {'page': 1, 'page_size': 100});
      if (!mounted) return;
      setStateIfMounted(() {
        _diskonOpsi =
            ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _memuatDiskon = false;
      });
    } catch (_) {
      setStateIfMounted(() => _memuatDiskon = false);
    }
  }

  Future<void> _muatAnggota() async {
    setStateIfMounted(() {
      _memuatAnggota = true;
      _galatAnggota = null;
    });
    try {
      final r = await ApiClient.instance
          .aksi('grup_produk_anggota_daftar', {'id': widget.awal!['id']});
      if (!mounted) return;
      setStateIfMounted(() {
        _anggota
          ..clear()
          ..addAll(((r['data'] as List?) ?? []).cast<Map<String, dynamic>>());
        _anggotaDimuat = true;
        _memuatAnggota = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galatAnggota =
            'Daftar anggota tidak dapat dimuat (offline?). Keanggotaan tidak akan diubah saat menyimpan.';
        _memuatAnggota = false;
      });
    }
  }

  double? _angka(String t) =>
      t.trim().isEmpty ? null : double.tryParse(t.replaceAll(',', '.'));

  /// Nilai harga utk ditampilkan sbg label ketika akun tak berhak ubah harga.
  String _rupiah(String t) =>
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
          .format(_angkaNol(t));

  double _angkaNol(String t) =>
      double.tryParse(t.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _totalHppBahan => _bahan.fold(
      0, (s, b) => s + _angkaNol(b.qty.text) * _angkaNol(b.harga.text));

  // ---------- Bahan baku ----------

  Future<void> _tambahBahan() async {
    final dipilih = await _dialogCariProduk(
        judul: 'Pilih Bahan Baku', jenisItem: 'BAHAN');
    if (dipilih == null) return;
    setStateIfMounted(() => _bahan.add(_BahanGrupBaris(
        produkId: (dipilih['id'] as num?)?.toInt(),
        nama: '${dipilih['nama']}')));
  }

  // ---------- Produk anggota ----------

  Future<void> _tambahAnggota() async {
    final dipilih = await _dialogCariProduk(judul: 'Tambah Produk Anggota');
    if (dipilih == null) return;
    setStateIfMounted(() {
      if (!_anggota.any((x) => x['id'] == dipilih['id'])) {
        _anggota.add(dipilih);
      }
    });
  }

  /// Pencarian produk LINTAS toko (aksi grup_produk_produk_cari); [jenisItem]
  /// membatasi hasil (mis. BAHAN utk resep). Mengembalikan satu produk terpilih.
  Future<Map<String, dynamic>?> _dialogCariProduk(
      {required String judul, String? jenisItem}) async {
    final q = TextEditingController();
    List<Map<String, dynamic>> hasilCari = [];
    bool mencari = false;
    final dipilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> cari() async {
          setLocal(() => mencari = true);
          try {
            final r =
                await ApiClient.instance.aksi('grup_produk_produk_cari', {
              'keyword': q.text.trim(),
              if (jenisItem != null) 'jenis_item': jenisItem,
            });
            hasilCari =
                ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          } catch (e) {
            hasilCari = [];
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pencarian gagal: $e')));
            }
          }
          setLocal(() => mencari = false);
        }

        return AlertDialog(
          title: Text(judul),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(children: [
              AppSearchField(
                controller: q,
                hintText: 'Cari kode/barcode/nama (semua toko)',
                autofocus: true,
                onChanged: (_) => cari(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: mencari
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: hasilCari.length,
                        itemBuilder: (_, i) {
                          final p = hasilCari[i];
                          return ListTile(
                            dense: true,
                            title: Text('${p['nama']}'),
                            subtitle: Text(
                                '${p['kode'] ?? ''} ${p['barcode'] ?? ''} · ${p['tokoNama'] ?? ''}'),
                            onTap: () => Navigator.pop(dialogContext, p),
                          );
                        }),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup')),
          ],
        );
      }),
    );
    q.dispose();
    return dipilih;
  }

  Future<void> _unduhAnggota() async {
    final bytes = buildSimpleXlsx(
      sheetName: 'Produk Grup',
      headers: const ['Kode Produk', 'Barcode', 'Nama Produk', 'Toko'],
      rows: _anggota
          .map((p) => [
                '${p['kode'] ?? ''}',
                '${p['barcode'] ?? ''}',
                '${p['nama'] ?? ''}',
                '${p['tokoNama'] ?? ''}'
              ])
          .toList(),
    );
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Produk Anggota Grup',
        fileName:
            'Grup_Produk_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes);
    if (path != null) await File(path).writeAsBytes(bytes);
  }

  Future<void> _unggahAnggota() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final raw =
        f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (raw == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('File Excel tidak dapat dibaca.')));
      }
      return;
    }
    final rows = readSimpleXlsx(Uint8List.fromList(raw));
    final keys = <String>[];
    for (final row in rows.skip(1)) {
      final kode = row.isNotEmpty ? row[0].trim() : '';
      final barcode = row.length > 1 ? row[1].trim() : '';
      if (kode.isNotEmpty || barcode.isNotEmpty) {
        keys.add(kode.isNotEmpty ? kode : barcode);
      }
    }
    try {
      // Satu kode dapat cocok di BANYAK toko -- semua hasilnya ikut jadi
      // anggota (memang itu tujuan grup lintas outlet).
      final r = await ApiClient.instance
          .aksi('grup_produk_produk_resolve', {'kunci': keys});
      final found = ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      final missing =
          ((r['tidakDitemukan'] as List?) ?? []).map((e) => '$e').toList();
      setStateIfMounted(() {
        for (final p in found) {
          if (!_anggota.any((x) => x['id'] == p['id'])) _anggota.add(p);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(missing.isEmpty
                ? '${found.length} produk berhasil dibaca dari Excel.'
                : '${found.length} ditemukan; ${missing.length} tidak ditemukan: ${missing.take(5).join(', ')}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unggah gagal: $e')));
      }
    }
  }

  Widget _judulBagian(String teks, {List<Widget> aksi = const []}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Row(children: [
          Expanded(
              child: Text(teks,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          ...aksi,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_baru ? 'Tambah Grup Produk' : 'Ubah Grup Produk'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: _kode,
                      decoration: const InputDecoration(
                          labelText: 'Kode Grup',
                          hintText: 'Mis. AYAM-MRN (opsional)')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                      controller: _nama,
                      decoration: const InputDecoration(
                          labelText: 'Nama Grup *',
                          hintText: 'Mis. Ayam Marinasi')),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: _keterangan,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Keterangan')),
              if (!Sesi.instance.bolehUbahHarga)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.45)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_outline, size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(Sesi.instance.pesanTidakBolehUbahHarga,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),
              _judulBagian('Harga & Kebijakan Terpusat'),
              Row(children: [
                Expanded(
                  child: Sesi.instance.bolehUbahHarga
                      ? TextField(
                          controller: _hargaBeli,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'HPP / Harga Beli'))
                      : AppHargaTerkunci(
                          label: 'HPP / Harga Beli',
                          nilai: _rupiah(_hargaBeli.text)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Sesi.instance.bolehUbahHarga
                      ? TextField(
                          controller: _hargaJual,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Harga Jual'))
                      : AppHargaTerkunci(
                          label: 'Harga Jual',
                          nilai: _rupiah(_hargaJual.text)),
                ),
              ]),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'HPP selalu mengikuti Grup Produk'),
                  subtitle: const Text(
                      'HPP + resep bahan baku grup disalin ke seluruh produk anggota di semua toko',
                      style: TextStyle(fontSize: 11)),
                  value: _ikutHpp,
                  onChanged: (v) => setState(() => _ikutHpp = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'Harga Jual selalu sama dengan Grup Produk'),
                  subtitle: const Text(
                      'Harga jual grup disalin ke seluruh produk anggota di semua toko',
                      style: TextStyle(fontSize: 11)),
                  value: _ikutJual,
                  onChanged: (v) => setState(() => _ikutJual = v)),
              if (!_ikutHpp && !_ikutJual)
                const Text(
                    'Kedua pilihan mati: grup hanya menjadi pengelompokan, '
                    'harga & resep tiap produk tetap dikelola per toko.',
                    style: TextStyle(fontSize: 12)),
              _judulBagian('Bahan Baku (Resep Grup)', aksi: [
                TextButton.icon(
                    onPressed: _tambahBahan,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Bahan')),
              ]),
              if (_bahan.isEmpty)
                const Text('Belum ada bahan. Resep ikut tersalin ke anggota '
                    'hanya bila "HPP selalu mengikuti Grup" menyala.',
                    style: TextStyle(fontSize: 12)),
              for (final b in _bahan)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text(b.nama,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 70,
                        child: TextField(
                            controller: b.qty,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Qty', isDense: true))),
                    const SizedBox(width: 6),
                    SizedBox(
                        width: 110,
                        child: TextField(
                            controller: b.harga,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Harga', isDense: true))),
                    IconButton(
                        onPressed: () {
                          setState(() => _bahan.remove(b));
                          b.dispose();
                        },
                        icon: const Icon(Icons.close, size: 18)),
                  ]),
                ),
              if (_bahan.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'Total HPP resep: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalHppBahan)}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              _judulBagian('Diskon Grup'),
              _memuatDiskon
                  ? const LinearProgressIndicator(minHeight: 2)
                  : DropdownButtonFormField<int?>(
                      value: _diskonOpsi
                              .any((d) => (d['id'] as num?)?.toInt() == _aturanDiskonId)
                          ? _aturanDiskonId
                          : null,
                      decoration: const InputDecoration(
                          labelText: 'Aturan Diskon utk semua anggota',
                          helperText:
                              'Berlaku otomatis di POS utk seluruh produk anggota grup'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('(tanpa diskon)')),
                        ..._diskonOpsi.map((d) => DropdownMenuItem<int?>(
                            value: (d['id'] as num?)?.toInt(),
                            child: Text('${d['namaAturan'] ?? d['nama_aturan'] ?? d['id']}',
                                maxLines: 1, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() => _aturanDiskonId = v),
                    ),
              _judulBagian('Produk Anggota (${_anggota.length})', aksi: [
                IconButton(
                    tooltip: 'Unduh Excel',
                    onPressed: _anggota.isEmpty ? null : _unduhAnggota,
                    icon: const Icon(Icons.download, size: 20)),
                IconButton(
                    tooltip: 'Unggah Excel (kode/barcode)',
                    onPressed: _anggotaDimuat ? _unggahAnggota : null,
                    icon: const Icon(Icons.upload_file, size: 20)),
                TextButton.icon(
                    onPressed: _anggotaDimuat ? _tambahAnggota : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah')),
              ]),
              if (_memuatAnggota) const LinearProgressIndicator(minHeight: 2),
              if (_galatAnggota != null)
                Text(_galatAnggota!,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error)),
              if (_anggotaDimuat && _anggota.isEmpty)
                const Text(
                    'Belum ada produk anggota. Tambahkan lewat pencarian atau '
                    'unggah Excel berisi kolom Kode Produk/Barcode.',
                    style: TextStyle(fontSize: 12)),
              if (_anggota.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _anggota.length,
                      itemBuilder: (_, i) {
                        final p = _anggota[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${p['nama']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${p['kode'] ?? ''} ${p['barcode'] ?? ''} · ${p['tokoNama'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                              tooltip: 'Keluarkan dari grup',
                              onPressed: () =>
                                  setState(() => _anggota.removeAt(i)),
                              icon: const Icon(Icons.close, size: 18)),
                        );
                      }),
                ),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: _aktif,
                  onChanged: (v) => setState(() => _aktif = v)),
              Text(
                  _ikutHpp || _ikutJual
                      ? 'Menyimpan akan MENYALIN ${_ikutHpp ? 'HPP + resep' : ''}'
                        '${_ikutHpp && _ikutJual ? ' dan ' : ''}'
                        '${_ikutJual ? 'harga jual' : ''} ke seluruh produk '
                        'anggota grup ini di semua toko/outlet.'
                      : 'Menyimpan hanya memperbarui data grup & keanggotaan '
                        '(tanpa menyentuh harga produk).',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        AppCrudDialogActions(
          submitLabel: 'Simpan & Terapkan',
          onSubmit: () async {
            if (_nama.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nama grup wajib diisi.')));
              return false;
            }
            return widget.onSubmit(<String, dynamic>{
              if (!_baru) 'id': widget.awal!['id'],
              'kode': _kode.text.trim(),
              'nama': _nama.text.trim(),
              'keterangan': _keterangan.text.trim(),
              'harga_beli': _angka(_hargaBeli.text),
              'harga_jual': _angka(_hargaJual.text),
              'ikut_hpp': _ikutHpp,
              'ikut_harga_jual': _ikutJual,
              'aturan_diskon': _aturanDiskonId,
              'bahan_baku': _bahan
                  .map((b) => {
                        'produk_id': b.produkId,
                        'nama': b.nama,
                        'qty': _angkaNol(b.qty.text),
                        'harga': _angkaNol(b.harga.text),
                      })
                  .toList(),
              // Keanggotaan dikirim HANYA bila daftarnya berhasil dimuat --
              // menghindari penghapusan keanggotaan saat form dibuka offline.
              if (_anggotaDimuat)
                'produk': _anggota.map((p) => {'id': p['id']}).toList(),
              'aktif': _aktif,
            });
          },
        ),
      ],
    );
  }
}
