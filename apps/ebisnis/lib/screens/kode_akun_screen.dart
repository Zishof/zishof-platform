import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../widgets/app_components.dart';
import '../services/master_offline.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/pulihkan_terhapus.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

/// Konfigurasi Kode Akun untuk POS Desktop/Android -- padanan layar ZK
/// `pages/master/akunting/akun.zul` yang dijadikan RUJUKAN bentuk datanya.
///
/// Empat tab: Akun (pohon), Daftar Akun (datar), Bank, dan Jenis Transaksi.
/// Tab Akun menyediakan unduh Excel (seluruh kolom + kode induk) dan unggah
/// Excel untuk membuat/memperbarui akun secara massal.
class KodeAkunScreen extends StatefulWidget {
  /// Tab yang dibuka pertama kali: 0 Akun, 1 Daftar Akun, 2 Bank, 3 Jenis Transaksi,
  /// 4 Grup Akun. Dipakai submenu "Akuntansi" agar tiap menu langsung mendarat di
  /// tab yang tepat tanpa menduplikasi layarnya.
  final int tabAwal;
  const KodeAkunScreen({super.key, this.tabAwal = 0});

  @override
  State<KodeAkunScreen> createState() => _KodeAkunScreenState();
}

class _KodeAkunScreenState extends State<KodeAkunScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _memuat = true;
  String? _galat;
  String _cari = '';
  bool _sibuk = false;

  List<Map<String, dynamic>> _akun = [];
  List<Map<String, dynamic>> _bank = [];
  List<Map<String, dynamic>> _grupAkun = [];
  List<Map<String, dynamic>> _jenisTransaksi = [];

  /// Hak tombol per master, dikirim server bersama daftarnya (grid CRUD pada
  /// `TbmroleAction`). Server tetap gerbang yang sebenarnya -- ini hanya
  /// menyembunyikan tombol yang sudah pasti ditolak supaya tidak menyesatkan.
  Map<String, bool> _hakAkun = const {};
  Map<String, bool> _hakBank = const {};
  Map<String, bool> _hakJenisTransaksi = const {};
  Map<String, bool> _hakGrup = const {};

  /// Kode akun anak bawaan = kode induk + nol sebanyak ini (padanan properti
  /// `akun_lenght` yang dipakai tombol "Tambah Data" pada pohon akun layar ZK).
  int _panjangKodeAnak = 2;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 5,
        vsync: this,
        initialIndex:
            widget.tabAwal >= 0 && widget.tabAwal <= 4 ? widget.tabAwal : 0);
    // Label & sasaran tombol unduh/unggah mengikuti tab aktif, jadi tampilan
    // harus dibangun ulang setiap tab berpindah.
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setStateIfMounted(() {});
    });
    _muat();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Kunci cache per daftar. Pencarian ikut dalam kunci supaya hasil tersaring
  /// tidak menimpa cache daftar penuh.
  String _cache(String nama) =>
      'master:kode_akun_$nama${_cari.trim().isEmpty ? '' : ':${_cari.trim()}'}';

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final body =
          _cari.trim().isEmpty ? <String, dynamic>{} : {'cari': _cari.trim()};
      // BACA LOKAL DULU: baris yang masih mengantre kirim tetap terlihat dan daftar
      // tetap terbuka saat perangkat offline; emisi server menyusul memperbarui.
      await MasterOffline.daftarCacheDulu(
          'kode_akun_daftar', body, _cache('akun'), onData: (res) {
        if (!mounted) return;
        setStateIfMounted(() {
          _akun = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          // Hak tombol & panjang kode anak hanya ikut pada emisi SERVER.
          if (res.containsKey('hak')) _hakAkun = _bacaHak(res);
          final n = (res['panjangKodeAnak'] as num?)?.toInt();
          if (n != null && n > 0 && n < 10) _panjangKodeAnak = n;
        });
      });
      await MasterOffline.daftarCacheDulu(
          'kode_akun_bank', body, _cache('bank'), onData: (res) {
        if (!mounted) return;
        setStateIfMounted(() {
          _bank = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (res.containsKey('hak')) _hakBank = _bacaHak(res);
        });
      });
      await MasterOffline.daftarCacheDulu(
          'kode_akun_grup', const {}, _cache('grup'), onData: (res) {
        if (!mounted) return;
        setStateIfMounted(() {
          _grupAkun =
              ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (res.containsKey('hak')) _hakGrup = _bacaHak(res);
        });
      });
      await MasterOffline.daftarCacheDulu(
          'kode_akun_jenis_transaksi', body, _cache('jenis_transaksi'),
          onData: (res) {
        if (!mounted) return;
        setStateIfMounted(() {
          _jenisTransaksi =
              ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (res.containsKey('hak')) _hakJenisTransaksi = _bacaHak(res);
        });
      });
      setStateIfMounted(() => _memuat = false);
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  /// Peta id -> kode akun, dipakai mengisi kolom "Kode Induk" saat mengunduh
  /// supaya berkasnya bisa langsung diunggah kembali tanpa penyuntingan manual.
  Map<String, String> get _kodeById {
    final peta = <String, String>{};
    for (final a in _akun) {
      peta['${a['id']}'] = '${a['kode'] ?? ''}';
    }
    return peta;
  }

  // ---- Definisi unduh/unggah per tab -------------------------------------
  // Urutan kolom di bawah menjadi KONTRAK berkas Excel: hasil unduh dapat
  // langsung disunting lalu diunggah kembali tanpa penyesuaian manual.
  // Tab 0 (Akun) dan 1 (Daftar Akun) memakai definisi sama; datanya sama,
  // hanya tampilannya yang berbeda.

  String get _defJudul =>
      _tab.index == 2 ? 'Bank' : (_tab.index == 3 ? 'Jenis Transaksi' : 'Akun');

  /// Label tombol Tambah: sama dgn judul unduh/unggah, tapi tab Grup Akun juga
  /// punya namanya sendiri (tab itu tidak ikut unduh/unggah Excel).
  String get _defJudulTab => _tab.index == 4 ? 'Grup Akun' : _defJudul;

  String get _defAksiImpor => _tab.index == 2
      ? 'kode_akun_bank_impor'
      : (_tab.index == 3
          ? 'kode_akun_jenis_transaksi_impor'
          : 'kode_akun_impor');

  List<String> get _defKolom {
    if (_tab.index == 2) {
      return const ['Kode', 'Nama Bank', 'Keterangan', 'Kode Akun', 'Aktif'];
    }
    if (_tab.index == 3) {
      return const ['Kode', 'Nama', 'Keterangan', 'Kode Akun', 'Aktif'];
    }
    return const [
      'Kode',
      'Nama',
      'Keterangan',
      'Posisi',
      'Grup Akun',
      'Kode Induk'
    ];
  }

  List<List<String>> _defBaris() {
    if (_tab.index == 2) {
      return _bank
          .map((b) => [
                '${b['kode'] ?? ''}',
                '${b['nama'] ?? ''}',
                '${b['keterangan'] ?? ''}',
                '${b['akunKode'] ?? ''}',
                b['aktif'] == true ? 'Ya' : 'Tidak',
              ])
          .toList();
    }
    if (_tab.index == 3) {
      return _jenisTransaksi
          .map((t) => [
                '${t['kode'] ?? ''}',
                '${t['nama'] ?? ''}',
                '${t['keterangan'] ?? ''}',
                '${t['akunKode'] ?? ''}',
                t['aktif'] == true ? 'Ya' : 'Tidak',
              ])
          .toList();
    }
    final peta = _kodeById;
    return _akun
        .map((a) => [
              '${a['kode'] ?? ''}',
              '${a['nama'] ?? ''}',
              '${a['keterangan'] ?? ''}',
              '${a['posisi'] ?? ''}',
              '${a['grupAkun'] ?? ''}',
              a['parentId'] == null ? '' : (peta['${a['parentId']}'] ?? ''),
            ])
        .toList();
  }

  Map<String, dynamic> _defKeBaris(List<String> r) {
    String k(int i) => r.length > i ? r[i] : '';
    if (_tab.index == 2) {
      return {
        'kode': k(0),
        'nama': k(1),
        'keterangan': k(2),
        'kodeAkun': k(3),
        'aktif': k(4)
      };
    }
    if (_tab.index == 3) {
      return {
        'kode': k(0),
        'nama': k(1),
        'keterangan': k(2),
        'kodeAkun': k(3),
        'aktif': k(4)
      };
    }
    return {
      'kode': k(0),
      'nama': k(1),
      'keterangan': k(2),
      'posisi': k(3),
      'grupAkun': k(4),
      'kodeParent': k(5)
    };
  }

  Future<void> _unduhAkun() async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final bytes = buildSimpleXlsx(
        sheetName: _defJudul,
        headers: _defKolom,
        rows: _defBaris(),
      );
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan $_defJudul',
          fileName:
              '${_defJudul.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          bytes: bytes);
      if (path != null) await File(path).writeAsBytes(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunduh: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _unggahAkun() async {
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berkas Excel tidak dapat dibaca.')));
      }
      return;
    }
    final rows = readSimpleXlsx(Uint8List.fromList(raw));
    final baris = <Map<String, dynamic>>[];
    for (final r in rows.skip(1)) {
      final bersih = r.map((e) => e.trim()).toList();
      if (bersih.every((e) => e.isEmpty)) continue;
      baris.add(_defKeBaris(bersih));
    }
    if (baris.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tidak ada baris berisi di berkas itu.')));
      }
      return;
    }
    if (!mounted) return;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unggah $_defJudul'),
        content: Text(
            '${baris.length} baris akan diproses. Data yang belum ada '
            'akan DIBUAT, yang sudah ada akan DIPERBARUI. Tidak ada data yang dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Proses')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil =
          await ApiClient.instance.aksi(_defAksiImpor, {'baris': baris});
      if (!mounted) return;
      final masalah =
          ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Hasil Unggah $_defJudul'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dibuat: ${hasil['dibuat'] ?? 0}'),
                    Text('Diperbarui: ${hasil['diperbarui'] ?? 0}'),
                    Text('Ditolak: ${hasil['ditolak'] ?? 0}'),
                    if (masalah.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Baris yang ditolak:',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final m in masalah)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('• $m',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
          ],
        ),
      );
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunggah: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Pemetaan akun -> Kelompok Laporan. Akun yang belum dipetakan tidak ikut
  /// terhitung pada Laba Rugi/Neraca berbasis jurnal, jadi tombol ini menutup
  /// celah itu. Server menurunkan kelompoknya dari BAGAN AKUN (induk akun),
  /// bukan menebak dari kata kunci; sifatnya hanya menambah, tidak menghapus.
  Future<void> _petakanAkun() async {
    setStateIfMounted(() => _sibuk = true);
    Map<String, dynamic> usul;
    try {
      usul = await ApiClient.instance
          .aksi('pemetaan_akun_usulan', {'batasContoh': 30});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyiapkan pemetaan: $e')));
      }
      setStateIfMounted(() => _sibuk = false);
      return;
    }
    setStateIfMounted(() => _sibuk = false);
    if (!mounted) return;
    final jumlah = (usul['jumlahBelumDipetakan'] as num?)?.toInt() ?? 0;
    if (jumlah == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Semua akun sudah dipetakan ke Kelompok Laporan.')));
      return;
    }
    final ringkas =
        ((usul['ringkasan'] as List?) ?? []).cast<Map<String, dynamic>>();
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Petakan Akun ke Kelompok Laporan'),
        content: SizedBox(
          width: 620,
          height: 420,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$jumlah akun belum dipetakan dan akan dimasukkan ke '
                '${usul['jumlahKelompok'] ?? 0} kelompok berikut. Kelompok diambil '
                'dari nama akun induk pada bagan akun Anda. Akun yang sudah '
                'dipetakan tidak diubah dan tidak ada data yang dihapus.'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: ringkas.length,
                itemBuilder: (_, i) {
                  final r = ringkas[i];
                  final baru = r['kelompokBaru'] == true;
                  return ListTile(
                    dense: true,
                    title: Text('${r['kelompok'] ?? ''}'),
                    subtitle: Text('${r['jenis'] ?? ''}'
                        '${baru ? ' • kelompok baru' : ' • kelompok yang sudah ada'}'),
                    trailing: Text('${r['jumlahAkun'] ?? 0} akun'),
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Terapkan')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil = await ApiClient.instance.aksi('pemetaan_akun_terapkan', {});
      if (!mounted) return;
      final masalah =
          ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hasil Pemetaan Akun'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Akun dipetakan: ${hasil['dipetakan'] ?? 0}'),
                    Text('Kelompok baru dibuat: ${hasil['kelompokBaru'] ?? 0}'),
                    if (masalah.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Baris yang gagal:',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final m in masalah)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('• $m',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
          ],
        ),
      );
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memetakan akun: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Pohon akun: baris anak diberi indentasi sesuai kedalaman induknya,
  /// meniru tampilan hierarki pada layar ZK.
  List<Map<String, dynamic>> get _akunPohon {
    final anakDari = <String, List<Map<String, dynamic>>>{};
    final akar = <Map<String, dynamic>>[];
    final semuaId = _akun.map((a) => '${a['id']}').toSet();
    for (final a in _akun) {
      final p = a['parentId'];
      if (p == null || !semuaId.contains('$p')) {
        akar.add(a);
      } else {
        anakDari.putIfAbsent('$p', () => []).add(a);
      }
    }
    final hasil = <Map<String, dynamic>>[];
    void telusuri(Map<String, dynamic> node, int level) {
      hasil.add({...node, '_level': level});
      for (final anak in (anakDari['${node['id']}'] ?? const [])) {
        telusuri(anak, level + 1);
      }
    }

    for (final a in akar) {
      telusuri(a, 0);
    }
    return hasil;
  }

  // ==================================================================== CRUD
  // Padanan tombol per node pada pohon akun layar ZK: Tambah Data (anak), Copy
  // Data, Ubah Data, Hapus Data -- ditambah tombol Tambah di toolbar untuk data
  // akar. Validasi lengkap tetap milik server; di sini hanya cek isian kosong.

  Map<String, bool> _bacaHak(Map<String, dynamic> res) {
    final h = res['hak'];
    if (h is! Map)
      return const {'create': true, 'update': true, 'delete': true};
    return {
      'create': h['create'] != false,
      'update': h['update'] != false,
      'delete': h['delete'] != false,
    };
  }

  bool _boleh(Map<String, bool> hak, String aksi) => hak[aksi] != false;

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  /// Aksi TULIS bagan akun: LOKAL DULU, lalu dikirim.
  ///
  /// Baris BARU yang dibuat offline memakai id SEMENTARA bernilai negatif. Setiap
  /// rujukan ke id itu (mis. Bank -> akun kas) ditukar dengan id server saat antrean
  /// dikirim, dan baris yang induknya belum terkirim ditahan lebih dulu -- sehingga
  /// tidak pernah ada data yang menunjuk akun yang belum dikenal server (spec 13.3).
  Future<bool> _kirim(
    String aksi,
    Map<String, dynamic> body, {
    required String kunci,
    required String cacheKey,
    Map<String, dynamic>? rowLokal,
    bool hapusLokal = false,
    String entitas = 'kode_akun',
  }) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      // Tanpa 'id' berarti baris BARU -> siapkan id sementaranya.
      final baru =
          !hapusLokal && (body['id'] == null || '${body['id']}'.isEmpty);
      final idLokal = baru ? MasterOffline.idSementaraBaru() : null;
      final hasil = await prosesSimpanMaster(
        context,
        aksi: aksi,
        body: body,
        kunci: kunci,
        cacheKey: cacheKey,
        rowLokal: {
          ...(rowLokal ?? body),
          if (idLokal != null) 'id': idLokal,
        },
        hapusLokal: hapusLokal,
        idLokal: idLokal,
        entitas: entitas,
      );
      if (hasil['offline'] != true) {
        _pesan('${hasil['message'] ?? 'Perubahan tersimpan.'}');
      }
      await _muat();
      return true;
    } catch (e) {
      _pesan('$e');
      return false;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<bool> _konfirmasi(String judul, String isi) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
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
    return ya == true;
  }

  Widget _isian(String label, TextEditingController c,
          {String? bantuan, bool wajib = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: wajib ? '$label *' : label,
            helperText: bantuan,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  /// Formulir Akun. [akun] null = tambah baru; [induk] terisi = "tambah anak"
  /// (kode & sifat diwarisi dari induknya); [salin] = copy data yang ada.
  Future<void> _formAkun(
      {Map<String, dynamic>? akun,
      Map<String, dynamic>? induk,
      bool salin = false}) async {
    final sumber = akun ?? induk;
    final anakBaru = induk != null;
    final ubah = akun != null && !salin;
    final kodeAwal = anakBaru
        ? '${induk['kode'] ?? ''}${'0' * _panjangKodeAnak}'
        : '${sumber?['kode'] ?? ''}';
    final kode = TextEditingController(text: kodeAwal);
    final nama =
        TextEditingController(text: anakBaru ? '' : '${sumber?['nama'] ?? ''}');
    final keterangan = TextEditingController(
        text: anakBaru ? '' : '${sumber?['keterangan'] ?? ''}');
    final atasNama =
        TextEditingController(text: '${sumber?['atasNama'] ?? ''}');
    final noRek = TextEditingController(text: '${sumber?['noRek'] ?? ''}');
    int? debetCredit = (sumber?['debetCredit'] as num?)?.toInt();
    int? grupAkunId = (sumber?['grupAkunId'] as num?)?.toInt();
    String aktifitas = '${sumber?['aktifitas'] ?? ''}';
    int? parentId = anakBaru
        ? (induk['id'] as num?)?.toInt()
        : (sumber?['parentId'] as num?)?.toInt();
    int? bankId = (sumber?['bankId'] as num?)?.toInt();

    final judul = anakBaru
        ? 'Tambah Akun Anak'
        : salin
            ? 'Salin Akun'
            : (ubah ? 'Ubah Akun' : 'Tambah Akun');
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(judul),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _isian('Kode Akun', kode,
                    wajib: true,
                    bantuan: salin
                        ? 'Kode harus diubah — kode yang sama akan ditolak server.'
                        : anakBaru
                            ? 'Bawaan: kode induk + $_panjangKodeAnak angka nol. Silakan sesuaikan.'
                            : null),
                _isian('Nama Akun', nama, wajib: true),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    value: debetCredit,
                    decoration: const InputDecoration(
                        labelText: 'Nilai Akun (Debet / Credit) *',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Debet')),
                      DropdownMenuItem(value: 2, child: Text('Credit')),
                    ],
                    onChanged: (v) => setDialog(() => debetCredit = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    value: grupAkunId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Grup Akun *',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: _grupAkun
                        .map((g) => DropdownMenuItem(
                              value: (g['id'] as num?)?.toInt(),
                              child: Text('${g['nama'] ?? ''}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDialog(() => grupAkunId = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: aktifitas.isEmpty ? '' : aktifitas,
                    decoration: const InputDecoration(
                        labelText: 'Aktifitas (Arus Kas)',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: '', child: Text('Tanpa Aktifitas')),
                      DropdownMenuItem(
                          value: 'OPERASI', child: Text('OPERASI')),
                      DropdownMenuItem(
                          value: 'INVESTASI', child: Text('INVESTASI')),
                      DropdownMenuItem(
                          value: 'PENDANAAN', child: Text('PENDANAAN')),
                    ],
                    onChanged: (v) => setDialog(() => aktifitas = v ?? ''),
                  ),
                ),
                PemilihAkunField(
                  label: 'Induk',
                  daftar: _akun,
                  nilai: parentId,
                  helperText: 'Kosongkan bila akun ini berdiri sendiri (akar).',
                  onChanged: (v) => setDialog(() => parentId = v),
                ),
                const SizedBox(height: 12),
                _isian('Keterangan', keterangan),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    value: bankId ?? 0,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Bank',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: 0, child: Text('= Bukan Bank =')),
                      ..._bank.map((b) => DropdownMenuItem(
                            value: (b['id'] as num?)?.toInt(),
                            child: Text('${b['nama'] ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) =>
                        setDialog(() => bankId = (v ?? 0) == 0 ? null : v),
                  ),
                ),
                // Sama seperti layar ZK: atas nama & nomor rekening hanya relevan
                // ketika akun ini memang rekening bank.
                if ((bankId ?? 0) > 0) ...[
                  _isian('Atas Nama', atasNama),
                  _isian('No. Rekening', noRek),
                ],
              ]),
            ),
          ),
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
    if (simpan != true) return;
    if (kode.text.trim().isEmpty || nama.text.trim().isEmpty) {
      _pesan('Kode dan Nama Akun wajib diisi.');
      return;
    }
    final payload = <String, dynamic>{
      if (ubah) 'id': akun['id'],
      'kode': kode.text.trim(),
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'debetCredit': debetCredit ?? 0,
      'grupAkunId': grupAkunId ?? 0,
      'aktifitas': aktifitas,
      'parentId': parentId ?? 0,
      'bankId': bankId ?? 0,
      'atasNama': atasNama.text.trim(),
      'noRek': noRek.text.trim(),
    };
    await _kirim(
      'kode_akun_simpan',
      payload,
      kunci: ubah
          ? 'kode_akun:${akun['id']}'
          : 'kode_akun:baru:${DateTime.now().microsecondsSinceEpoch}',
      cacheKey: _cache('akun'),
      // Bentuk baris daftar: kolom tampilan diisi seadanya supaya tabel langsung
      // memperlihatkan perubahan walau server belum menjawab.
      rowLokal: {
        ...payload,
        'posisi': (debetCredit ?? 1) == 1 ? 'Debet' : 'Credit'
      },
    );
  }

  Future<void> _formBank(
      {Map<String, dynamic>? bank, bool salin = false}) async {
    final ubah = bank != null && !salin;
    final kode = TextEditingController(text: '${bank?['kode'] ?? ''}');
    final nama = TextEditingController(text: '${bank?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${bank?['keterangan'] ?? ''}');
    int? akunId = (bank?['akunId'] as num?)?.toInt();
    bool aktif = bank == null ? true : bank['aktif'] != false;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title:
              Text(salin ? 'Salin Bank' : (ubah ? 'Ubah Bank' : 'Tambah Bank')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _isian('Kode Bank', kode,
                    bantuan: 'Dipakai mencocokkan baris saat impor Excel.'),
                _isian('Nama Bank', nama, wajib: true),
                PemilihAkunField(
                  label: 'Akun Kas/Bank',
                  daftar: _akun,
                  nilai: akunId,
                  helperText:
                      'Akun buku besar yang dipakai saat bank ini dijurnal.',
                  onChanged: (v) => setDialog(() => akunId = v),
                ),
                const SizedBox(height: 12),
                _isian('Keterangan', keterangan),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: aktif,
                  onChanged: (v) => setDialog(() => aktif = v),
                ),
              ]),
            ),
          ),
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
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Nama Bank wajib diisi.');
      return;
    }
    final payload = <String, dynamic>{
      if (ubah) 'id': bank['id'],
      'kode': kode.text.trim(),
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'akunId': akunId ?? 0,
      'aktif': aktif,
    };
    await _kirim(
      'kode_akun_bank_simpan',
      payload,
      entitas: 'bank',
      kunci: ubah
          ? 'kode_akun_bank:${bank['id']}'
          : 'kode_akun_bank:baru:${DateTime.now().microsecondsSinceEpoch}',
      cacheKey: _cache('bank'),
    );
  }

  Future<void> _formJenisTransaksi(
      {Map<String, dynamic>? jenis, bool salin = false}) async {
    final ubah = jenis != null && !salin;
    final kode = TextEditingController(text: '${jenis?['kode'] ?? ''}');
    final nama = TextEditingController(text: '${jenis?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${jenis?['keterangan'] ?? ''}');
    int? akunId = (jenis?['akunId'] as num?)?.toInt();
    bool aktif = jenis == null ? true : jenis['aktif'] != false;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(salin
              ? 'Salin Jenis Transaksi'
              : (ubah ? 'Ubah Jenis Transaksi' : 'Tambah Jenis Transaksi')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _isian('Kode', kode),
                _isian('Nama', nama, wajib: true),
                PemilihAkunField(
                  label: 'Akun',
                  daftar: _akun,
                  nilai: akunId,
                  helperText:
                      'Akun bawaan yang dipakai transaksi berjenis ini.',
                  onChanged: (v) => setDialog(() => akunId = v),
                ),
                const SizedBox(height: 12),
                _isian('Keterangan', keterangan),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: aktif,
                  onChanged: (v) => setDialog(() => aktif = v),
                ),
              ]),
            ),
          ),
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
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Nama Jenis Transaksi wajib diisi.');
      return;
    }
    final payload = <String, dynamic>{
      if (ubah) 'id': jenis['id'],
      'kode': kode.text.trim(),
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'akunId': akunId ?? 0,
      'aktif': aktif,
    };
    await _kirim(
      'kode_akun_jenis_transaksi_simpan',
      payload,
      entitas: 'jenis_transaksi',
      kunci: ubah
          ? 'kode_akun_jt:${jenis['id']}'
          : 'kode_akun_jt:baru:${DateTime.now().microsecondsSinceEpoch}',
      cacheKey: _cache('jenis_transaksi'),
    );
  }

  Future<void> _formGrupAkun(
      {Map<String, dynamic>? grup, bool salin = false}) async {
    final ubah = grup != null && !salin;
    final nama = TextEditingController(text: '${grup?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${grup?['keterangan'] ?? ''}');
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(salin
            ? 'Salin Grup Akun'
            : (ubah ? 'Ubah Grup Akun' : 'Tambah Grup Akun')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _isian('Nama Grup', nama,
                  wajib: true,
                  bantuan: salin
                      ? 'Nama harus diubah — nama yang sama akan ditolak.'
                      : null),
              _isian('Keterangan', keterangan),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Nama Grup Akun wajib diisi.');
      return;
    }
    final payload = <String, dynamic>{
      if (ubah) 'id': grup['id'],
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
    };
    await _kirim(
      'kode_akun_grup_simpan',
      payload,
      entitas: 'grup_akun',
      kunci: ubah
          ? 'kode_akun_grup:${grup['id']}'
          : 'kode_akun_grup:baru:${DateTime.now().microsecondsSinceEpoch}',
      cacheKey: _cache('grup'),
    );
  }

  /// Jalan pulang untuk penghapusan yang belum terkirim: penghapusan lokal bersifat
  /// LUNAK, jadi barisnya masih ada di perangkat dan bisa dikembalikan.
  Future<void> _bukaTerhapus() async {
    final nama = _tab.index == 2
        ? 'bank'
        : (_tab.index == 3 ? 'jenis_transaksi' : (_tab.index == 4 ? 'grup' : 'akun'));
    final jumlah = await bukaPulihkanTerhapus(
      context,
      cacheKey: _cache(nama),
      judul: '$_defJudulTab Terhapus',
      labelBaris: (b) => '${b['kode'] ?? ''} ${b['nama'] ?? ''}'.trim(),
      keteranganBaris: (b) => '${b['keterangan'] ?? ''}',
    );
    if (jumlah > 0) await _muat();
  }

  Future<void> _hapus(String aksi, Object? id, String label,
      {required String kunci, required String cacheKey}) async {
    if (id == null) return;
    if (!await _konfirmasi('Hapus data ini?',
        '"$label" akan dihapus permanen. Data yang sudah dipakai transaksi akan ditolak server.')) {
      return;
    }
    await _kirim(aksi, {'id': id},
        kunci: kunci,
        cacheKey: cacheKey,
        rowLokal: {'id': id},
        hapusLokal: true);
  }

  /// Empat tombol aksi pada pohon akun -- urutannya mengikuti layar ZK.
  AppTableCell _aksiAkun(Map<String, dynamic> a) => AppTableCell(
      width: 64,
      child: AksiBarisMenu(aksi: [
        AksiBaris(
            ikon: Icons.playlist_add,
            label: 'Tambah akun anak',
            onTap: _boleh(_hakAkun, 'create')
                ? _sibuk
                    ? null
                    : () => _formAkun(induk: a)
                : null),
        AksiBaris(
            ikon: Icons.copy_outlined,
            label: 'Salin (copy) akun ini',
            onTap: _boleh(_hakAkun, 'create')
                ? _sibuk
                    ? null
                    : () => _formAkun(akun: a, salin: true)
                : null),
        AksiBaris(
            ikon: Icons.edit_outlined,
            label: 'Ubah akun',
            onTap: _boleh(_hakAkun, 'update')
                ? _sibuk
                    ? null
                    : () => _formAkun(akun: a)
                : null),
        AksiBaris(
            ikon: Icons.delete_outline,
            label: 'Hapus akun',
            onTap: _boleh(_hakAkun, 'delete')
                ? _sibuk
                    ? null
                    : () => _hapus('kode_akun_hapus', a['id'],
                        '${a['kode'] ?? ''} - ${a['nama'] ?? ''}',
                        kunci: 'kode_akun:${a['id']}', cacheKey: _cache('akun'))
                : null,
            merusak: true)
      ]));

  /// Tiga tombol aksi untuk master sederhana (Bank, Jenis Transaksi, Grup Akun).
  AppTableCell _aksiBaris(
          {required Map<String, bool> hak,
          required VoidCallback onSalin,
          required VoidCallback onUbah,
          required VoidCallback onHapus}) =>
      AppTableCell(
          width: 64,
          child: AksiBarisMenu(aksi: [
            AksiBaris(
                ikon: Icons.copy_outlined,
                label: 'Salin (copy) data ini',
                onTap: _boleh(hak, 'create')
                    ? _sibuk
                        ? null
                        : onSalin
                    : null),
            AksiBaris(
                ikon: Icons.edit_outlined,
                label: 'Ubah data',
                onTap: _boleh(hak, 'update')
                    ? _sibuk
                        ? null
                        : onUbah
                    : null),
            AksiBaris(
                ikon: Icons.delete_outline,
                label: 'Hapus data',
                onTap: _boleh(hak, 'delete')
                    ? _sibuk
                        ? null
                        : onHapus
                    : null,
                merusak: true)
          ]));

  /// Tombol "Tambah" di toolbar mengikuti tab yang sedang aktif.
  bool get _bolehTambahTabIni {
    if (_tab.index <= 1) return _boleh(_hakAkun, 'create');
    if (_tab.index == 2) return _boleh(_hakBank, 'create');
    if (_tab.index == 3) return _boleh(_hakJenisTransaksi, 'create');
    return _boleh(_hakGrup, 'create');
  }

  Future<void> _tambahTabIni() {
    if (_tab.index <= 1) return _formAkun();
    if (_tab.index == 2) return _formBank();
    if (_tab.index == 3) return _formJenisTransaksi();
    return _formGrupAkun();
  }

  Widget _tabelAkun({required bool pohon}) {
    final data = pohon ? _akunPohon : _akun;
    return AppDataTable(
      minWidth: 900,
      emptyText: 'Tidak ada akun untuk filter ini.',
      columns: const [
        AppTableColumn('Akun', flex: 4),
        AppTableColumn('Debet/Credit', flex: 2),
        AppTableColumn('Keterangan', flex: 3),
        AppTableColumn('Grup Akun', flex: 3),
        AppTableColumn('Dipakai', flex: 1, align: TextAlign.right),
        AppTableColumn('Aksi', width: 64, align: TextAlign.center),
      ],
      rows: data
          .map((a) => AppTableRowData(cells: [
                AppTableCell.text(
                    '${'    ' * ((a['_level'] as int?) ?? 0)}${a['kode'] ?? ''} - ${a['nama'] ?? ''}',
                    flex: 4),
                AppTableCell.text('${a['posisi'] ?? ''}', flex: 2),
                AppTableCell.text('${a['keterangan'] ?? ''}', flex: 3),
                AppTableCell.text('${a['grupAkun'] ?? ''}', flex: 3),
                AppTableCell.text('${a['jumlahDipakai'] ?? 0}',
                    flex: 1, align: TextAlign.right),
                _aksiAkun(a),
              ]))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(
                  labelText: 'Cari kode / nama',
                  prefixIcon: Icon(Icons.search),
                  isDense: true),
              onChanged: (v) => _cari = v,
              onSubmitted: (_) => _muat(),
            ),
          ),
          FilledButton.icon(
              onPressed: _memuat ? null : _muat,
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Terapkan')),
          if (_bolehTambahTabIni)
            FilledButton.icon(
                onPressed: _sibuk ? null : _tambahTabIni,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Tambah $_defJudulTab')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _bukaTerhapus,
              icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
              label: const Text('Data Terhapus')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unduhAkun,
              icon: const Icon(Icons.download, size: 18),
              label: Text('Download $_defJudul')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unggahAkun,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text('Upload $_defJudul')),
          if (_tab.index < 2)
            OutlinedButton.icon(
                onPressed: _sibuk ? null : _petakanAkun,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('Petakan Akun')),
          if (_sibuk)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
      TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Akun'),
            Tab(text: 'Daftar Akun'),
            Tab(text: 'Bank'),
            Tab(text: 'Jenis Transaksi'),
            Tab(text: 'Grup Akun'),
          ]),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ))
                : TabBarView(controller: _tab, children: [
                    _tabelAkun(pohon: true),
                    _tabelAkun(pohon: false),
                    AppDataTable(
                      minWidth: 720,
                      emptyText: 'Belum ada data bank.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Bank', flex: 3),
                        AppTableColumn('Akun Kas', flex: 4),
                        AppTableColumn('Keterangan', flex: 3),
                        AppTableColumn('Aktif', flex: 1),
                        AppTableColumn('Aksi',
                            width: 64, align: TextAlign.center),
                      ],
                      rows: _bank
                          .map((b) => AppTableRowData(cells: [
                                AppTableCell.text('${b['kode'] ?? ''}',
                                    flex: 2),
                                AppTableCell.text('${b['nama'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text(
                                    '${b['akunKode'] ?? ''} ${b['akunNama'] ?? ''}'
                                        .trim(),
                                    flex: 4),
                                AppTableCell.text('${b['keterangan'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text(
                                    b['aktif'] == true ? 'Ya' : 'Tidak',
                                    flex: 1),
                                _aksiBaris(
                                  hak: _hakBank,
                                  onSalin: () =>
                                      _formBank(bank: b, salin: true),
                                  onUbah: () => _formBank(bank: b),
                                  onHapus: () => _hapus('kode_akun_bank_hapus',
                                      b['id'], '${b['nama'] ?? ''}',
                                      kunci: 'kode_akun_bank:${b['id']}',
                                      cacheKey: _cache('bank')),
                                ),
                              ]))
                          .toList(),
                    ),
                    AppDataTable(
                      minWidth: 820,
                      emptyText: 'Belum ada jenis transaksi.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Nama', flex: 3),
                        AppTableColumn('Akun', flex: 4),
                        AppTableColumn('Keterangan', flex: 3),
                        AppTableColumn('Aktif', flex: 1),
                        AppTableColumn('Aksi',
                            width: 64, align: TextAlign.center),
                      ],
                      rows: _jenisTransaksi
                          .map((t) => AppTableRowData(cells: [
                                AppTableCell.text('${t['kode'] ?? ''}',
                                    flex: 2),
                                AppTableCell.text('${t['nama'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text(
                                    '${t['akunKode'] ?? ''} ${t['akunNama'] ?? ''}'
                                        .trim(),
                                    flex: 4),
                                AppTableCell.text('${t['keterangan'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text(
                                    t['aktif'] == true ? 'Ya' : 'Tidak',
                                    flex: 1),
                                _aksiBaris(
                                  hak: _hakJenisTransaksi,
                                  onSalin: () => _formJenisTransaksi(
                                      jenis: t, salin: true),
                                  onUbah: () => _formJenisTransaksi(jenis: t),
                                  onHapus: () => _hapus(
                                      'kode_akun_jenis_transaksi_hapus',
                                      t['id'],
                                      '${t['nama'] ?? ''}',
                                      kunci: 'kode_akun_jt:${t['id']}',
                                      cacheKey: _cache('jenis_transaksi')),
                                ),
                              ]))
                          .toList(),
                    ),
                    // Grup Akun: pengelompokan bebas milik bagan akun (mis. Kas & Bank,
                    // Piutang) -- berbeda dari Kelompok Laporan yang menentukan posisi
                    // akun di Neraca/Laba Rugi.
                    AppDataTable(
                      minWidth: 620,
                      emptyText: 'Belum ada grup akun.',
                      columns: const [
                        AppTableColumn('Nama Grup', flex: 3),
                        AppTableColumn('Keterangan', flex: 5),
                        AppTableColumn('Jumlah Akun',
                            flex: 2, align: TextAlign.right),
                        AppTableColumn('Aksi',
                            width: 64, align: TextAlign.center),
                      ],
                      rows: _grupAkun
                          .map((g) => AppTableRowData(cells: [
                                AppTableCell.text('${g['nama'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text('${g['keterangan'] ?? ''}',
                                    flex: 5),
                                AppTableCell.text(
                                    '${_akun.where((a) => '${a['grupAkun'] ?? ''}' == '${g['nama'] ?? ''}').length}',
                                    flex: 2,
                                    align: TextAlign.right),
                                _aksiBaris(
                                  hak: _hakGrup,
                                  onSalin: () =>
                                      _formGrupAkun(grup: g, salin: true),
                                  onUbah: () => _formGrupAkun(grup: g),
                                  onHapus: () => _hapus('kode_akun_grup_hapus',
                                      g['id'], '${g['nama'] ?? ''}',
                                      kunci: 'kode_akun_grup:${g['id']}',
                                      cacheKey: _cache('grup')),
                                ),
                              ]))
                          .toList(),
                    ),
                  ]),
      ),
    ]);
  }
}
