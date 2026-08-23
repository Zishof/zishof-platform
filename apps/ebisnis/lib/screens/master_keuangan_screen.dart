import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';

/// Master data grup "Keuangan" — padanan enam layar ZK yang selama ini menjadi
/// satu-satunya tempat memelihara jenis dan cara pembayaran:
/// `jenis_uang_muka`, `jenis_kas_kecil`, `jenis_kas_besar`, `jenis_reimbursement`,
/// `jenis_pengeluaran`, dan `cara_pembayaran_transfer`.
///
/// **Mengapa layar ini ada.** Delapan modul Keuangan yang sudah dipindahkan ke
/// Desktop/Android bergantung pada pemetaan akun di sini. Bila akunnya belum
/// lengkap, dokumen tetap dapat diajukan dan disetujui tetapi **dilewati begitu
/// saja** oleh mesin posting — tanpa pesan galat di dokumennya. Karena itu daftar
/// di sini menandai baris yang akunnya belum lengkap, dan jumlahnya diberitakan
/// di atas tabel, supaya admin melihat masalahnya sebelum penggunanya menemukannya.
///
/// Bentuk datanya sengaja seragam untuk keenam tipe: yang berbeda hanya LABEL
/// medan akunnya (`medanAkun` dari server), bukan kuncinya. Jadi satu formulir
/// melayani semuanya dan tidak ada cabang per tipe di layar ini.
class MasterKeuanganScreen extends StatefulWidget {
  /// Tab yang dibuka pertama kali, mengikuti urutan `tipe` dari server.
  final int tabAwal;
  const MasterKeuanganScreen({super.key, this.tabAwal = 0});

  @override
  State<MasterKeuanganScreen> createState() => _MasterKeuanganScreenState();
}

class _MasterKeuanganScreenState extends State<MasterKeuanganScreen>
    with TickerProviderStateMixin {
  TabController? _tab;
  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  /// Metadata tiap tipe dari `master_keuangan_opsi`: tipe, label, medanAkun,
  /// punyaKode, punyaAnggaran, punyaSatuanKerja.
  List<Map<String, dynamic>> _tipe = const [];
  List<Map<String, dynamic>> _satker = const [];
  List<Map<String, dynamic>> _akun = const [];

  final Map<String, List<Map<String, dynamic>>> _data = {};
  final Map<String, int> _belumLengkap = {};
  final Map<String, List<Map<String, dynamic>>> _terhapus = {};
  Map<String, bool> _hak = const {};

  final TextEditingController _cari = TextEditingController();
  bool _tampilkanTerhapus = false;

  Map<String, dynamic> get _tipeAktif => _tipe[_tab?.index ?? 0];
  String get _kunciAktif => '${_tipeAktif['tipe']}';
  String _cacheKey(String tipe) => 'master_keuangan:$tipe';

  List<Map<String, dynamic>> get _terlihat => _tampilkanTerhapus
      ? (_terhapus[_kunciAktif] ?? const [])
      : (_data[_kunciAktif] ?? const []);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatOpsi());
  }

  @override
  void dispose() {
    _cari.dispose();
    _tab?.dispose();
    super.dispose();
  }

  Future<void> _muatOpsi() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final opsi = await ApiClient.instance.aksi('master_keuangan_opsi', {});
      final res = await ApiClient.instance.aksi('akun_list', {'limit': 2000});
      if (!mounted) return;
      final tipe = ((opsi['tipe'] as List?) ?? []).cast<Map<String, dynamic>>();
      final ct = TabController(
        length: tipe.isEmpty ? 1 : tipe.length,
        vsync: this,
        initialIndex:
            tipe.isEmpty ? 0 : widget.tabAwal.clamp(0, tipe.length - 1),
      );
      ct.addListener(() {
        if (ct.indexIsChanging) return;
        _cari.clear();
        _tampilkanTerhapus = false;
        _muatDaftar();
      });
      setStateIfMounted(() {
        _tipe = tipe;
        _satker = ((opsi['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _akun = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _tab?.dispose();
        _tab = ct;
      });
      await _muatDaftar();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muatDaftar() async {
    if (_tipe.isEmpty) {
      setStateIfMounted(() => _memuat = false);
      return;
    }
    final tipe = _kunciAktif;
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Salinan lokal dulu: daftar master tetap terbuka saat jaringan mati,
      // sama seperti modul Keuangan yang memakainya.
      await MasterOffline.daftarCacheDulu(
        'master_keuangan_daftar',
        {
          'tipe': tipe,
          if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
        },
        _cacheKey(tipe),
        kolomKunci: 'id',
        onData: (hasil) {
          () async {
            final t = await MasterOffline.daftarTerhapusLokal(_cacheKey(tipe));
            if (mounted) setStateIfMounted(() => _terhapus[tipe] = t);
          }();
          if (!mounted) return;
          setStateIfMounted(() {
            _data[tipe] = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            _belumLengkap[tipe] = (hasil['belumLengkap'] as num?)?.toInt() ?? 0;
            final h = hasil['hak'];
            _hak = h is Map
                ? {
                    for (final k in ['create', 'update', 'delete']) k: h[k] != false
                  }
                : const {};
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  bool _boleh(String aksi) => _hak[aksi] != false;

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  Future<bool> _kirimLokalDulu(
    String aksi,
    Map<String, dynamic> body, {
    required String kunci,
    Map<String, dynamic>? rowLokal,
    int? idLokal,
    bool hapusLokal = false,
  }) async {
    final tipe = _kunciAktif;
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil = await prosesSimpanMaster(
        context,
        aksi: aksi,
        body: body,
        kunci: kunci,
        cacheKey: _cacheKey(tipe),
        rowLokal: rowLokal,
        hapusLokal: hapusLokal,
        idLokal: idLokal,
        entitas: 'master_keuangan',
      );
      if (hasil['offline'] == true) {
        _pesan('Tersimpan di perangkat. Akan dikirim otomatis saat jaringan pulih.');
      } else {
        _pesan('${hasil['message'] ?? 'Perubahan tersimpan.'}');
      }
      await _muatDaftar();
      return true;
    } catch (e) {
      _pesan('$e');
      return false;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<bool> _konfirmasi(String judul, String isi, String tombol) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tombol)),
        ],
      ),
    );
    return ya == true;
  }

  String _teksAkun(Object? id) {
    final v = (id as num?)?.toInt();
    if (v == null) return '';
    for (final a in _akun) {
      if ((a['id'] as num?)?.toInt() == v) return PemilihAkunField.teksAkun(a);
    }
    return '#$v';
  }

  /// Ringkasan akun satu baris: satu baris teks per medan akun yang dipakai
  /// tipe ini, memakai LABEL milik tipenya sendiri.
  String _ringkasAkun(Map<String, dynamic> meta, Map<String, dynamic> b) {
    final medan = ((meta['medanAkun'] as List?) ?? []).cast<Map<String, dynamic>>();
    final baris = <String>[];
    for (final m in medan) {
      final teks = _teksAkun(b['${m['kunci']}']);
      baris.add('${m['label']}: ${teks.isEmpty ? '—' : teks}');
    }
    return baris.join('\n');
  }

  // ------------------------------------------------------------- formulir

  /// [salin] membuka formulir berisi salinan [baris] tetapi menyimpannya sebagai
  /// data BARU — dibedakan dari "ubah" supaya id sumbernya tidak ikut terkirim.
  Future<void> _form(Map<String, dynamic> meta,
      [Map<String, dynamic>? baris, bool salin = false]) async {
    final ubah = baris != null && !salin;
    final punyaKode = meta['punyaKode'] == true;
    final punyaAnggaran = meta['punyaAnggaran'] == true;
    final punyaSatker = meta['punyaSatuanKerja'] == true;
    final medan = ((meta['medanAkun'] as List?) ?? []).cast<Map<String, dynamic>>();

    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final kode = TextEditingController(text: '${baris?['kode'] ?? ''}');
    final keterangan = TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    bool aktif = baris == null ? true : baris['aktif'] == true;
    bool menggunakanAnggaran = baris?['menggunakanAnggaran'] == true;
    int? satkerId = (baris?['satuanKerjaId'] as num?)?.toInt();
    final akunTerpilih = <String, int?>{
      for (final m in medan) '${m['kunci']}': (baris?['${m['kunci']}'] as num?)?.toInt()
    };

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text('${ubah ? 'Ubah' : 'Tambah'} ${meta['label']}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (punyaKode)
                  _isian('Kode', kode,
                      helper: 'Boleh dikosongkan; dipakai untuk penomoran dokumen.'),
                _isian('Nama', nama, wajib: true),
                _isian('Keterangan', keterangan, baris: 2),
                if (punyaSatker)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<int?>(
                      value: satkerId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Satuan Kerja',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('(semua satuan kerja)')),
                        ..._satker.map((s) => DropdownMenuItem<int?>(
                            value: (s['id'] as num?)?.toInt(),
                            child: Text('${s['nama'] ?? ''}'))),
                      ],
                      onChanged: (v) => setDialog(() => satkerId = v),
                    ),
                  ),
                if (punyaAnggaran)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Membebani anggaran'),
                    subtitle: const Text(
                        'Bila menyala, pengaju WAJIB memilih anggaran. Bila padam, '
                        'yang wajib justru akun di bawah ini.'),
                    value: menggunakanAnggaran,
                    onChanged: (v) => setDialog(() => menggunakanAnggaran = v),
                  ),
                for (final m in medan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PemilihAkunField(
                      label: '${m['label']}',
                      daftar: _akun,
                      nilai: akunTerpilih['${m['kunci']}'],
                      onChanged: (v) =>
                          setDialog(() => akunTerpilih['${m['kunci']}'] = v),
                      helperText: m['wajibUntukJurnal'] == true
                          ? 'Tanpa akun ini, dokumen yang memakainya tidak akan terjurnal.'
                          : null,
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: const Text(
                      'Yang dinonaktifkan tidak lagi muncul sebagai pilihan pada '
                      'dokumen baru, tetapi dokumen lama tetap utuh.'),
                  value: aktif,
                  onChanged: (v) => setDialog(() => aktif = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Nama ${meta['label']} wajib diisi.');
      return;
    }

    final idBaru = ubah ? null : MasterOffline.idSementaraBaru();
    final body = <String, dynamic>{
      'tipe': '${meta['tipe']}',
      if (ubah) 'id': baris['id'],
      'nama': nama.text.trim(),
      if (punyaKode) 'kode': kode.text.trim(),
      'keterangan': keterangan.text.trim(),
      'aktif': aktif,
      if (punyaSatker && satkerId != null) 'satuanKerjaId': satkerId,
      if (punyaAnggaran) 'menggunakanAnggaran': menggunakanAnggaran,
      for (final m in medan)
        if (akunTerpilih['${m['kunci']}'] != null)
          '${m['kunci']}': akunTerpilih['${m['kunci']}'],
    };
    await _kirimLokalDulu(
      'master_keuangan_simpan',
      body,
      kunci: 'master_keuangan:${meta['tipe']}:${ubah ? baris['id'] : idBaru}',
      idLokal: ubah ? null : idBaru,
      rowLokal: {
        'id': ubah ? baris['id'] : idBaru,
        'nama': nama.text.trim(),
        'kode': punyaKode ? kode.text.trim() : '',
        'keterangan': keterangan.text.trim(),
        'aktif': aktif,
        'menggunakanAnggaran': menggunakanAnggaran,
        'satuanKerjaId': satkerId,
        'dipakai': ubah ? (baris['dipakai'] ?? 0) : 0,
        for (final m in medan) '${m['kunci']}': akunTerpilih['${m['kunci']}'],
        // Dihitung ulang oleh server saat daftar berikutnya; nilai lokal ini
        // hanya menjaga tandanya tidak melompat selama masih luring.
        'akunLengkap': medan
            .where((m) => m['wajibUntukJurnal'] == true)
            .every((m) => akunTerpilih['${m['kunci']}'] != null),
      },
    );
  }

  Widget _isian(String label, TextEditingController c,
          {bool wajib = false, String? helper, int baris = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: baris,
          decoration: InputDecoration(
            labelText: wajib ? '$label *' : label,
            helperText: helper,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Future<void> _hapusBaris(Map<String, dynamic> meta, Map<String, dynamic> b) async {
    final dipakai = (b['dipakai'] as num?)?.toInt() ?? 0;
    if (dipakai > 0) {
      // Ditolak juga oleh server; disebutkan lebih dulu di sini supaya pengguna
      // tidak menunggu bolak-balik hanya untuk mendapat penolakan.
      _pesan('${meta['label']} ini sudah dipakai $dipakai dokumen sehingga tidak '
          'boleh dihapus. Nonaktifkan saja bila tidak dipakai lagi.');
      return;
    }
    if (!await _konfirmasi(
        'Hapus ${meta['label']}?',
        '${b['nama'] ?? ''}\n\nDokumen baru tidak akan bisa memilihnya lagi.',
        'Hapus')) {
      return;
    }
    await _kirimLokalDulu(
      'master_keuangan_hapus',
      {'tipe': '${meta['tipe']}', 'id': b['id']},
      kunci: 'master_keuangan:${meta['tipe']}:${b['id']}',
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  Future<void> _pulihkanBaris(Map<String, dynamic> meta, Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Batalkan penghapusan?',
        '${b['nama'] ?? ''}\n\nBerlaku selama penghapusannya belum terkirim ke server.',
        'Batalkan penghapusan')) {
      return;
    }
    setStateIfMounted(() => _sibuk = true);
    try {
      final berhasil = await MasterOffline.pulihkanLokal(
          _cacheKey('${meta['tipe']}'), b['id'],
          kunci: 'master_keuangan:${meta['tipe']}:${b['id']}');
      _pesan(berhasil
          ? 'Penghapusan dibatalkan.'
          : 'Tidak dapat dibatalkan: penghapusannya sudah terkirim ke server.');
      await _muatDaftar();
    } finally {
      if (mounted) setStateIfMounted(() => _sibuk = false);
    }
  }

  // ------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    final tab = _tab;
    return AppShell(
      menuAktif: MenuEBisnis.masterKeuangan,
      judul: 'Master Data Keuangan',
      subjudul: 'Jenis uang muka, kas, reimbursement, pengeluaran, dan cara pembayaran',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      body: _galat != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_galat!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _muatOpsi, child: const Text('Coba lagi')),
                ]),
              ),
            )
          : tab == null || _tipe.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  TabBar(
                    controller: tab,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [for (final t in _tipe) Tab(text: '${t['label']}')],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(children: [
                      Expanded(
                        child: AppSearchField(
                          controller: _cari,
                          hintText: 'Cari nama atau keterangan…',
                          onChanged: (_) => _muatDaftar(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_boleh('create') && !_tampilkanTerhapus)
                        FilledButton.icon(
                          onPressed: _sibuk ? null : () => _form(_tipeAktif),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Tambah'),
                        ),
                    ]),
                  ),
                  _panelPeringatan(),
                  Expanded(
                    child: _memuat
                        ? const Center(child: CircularProgressIndicator())
                        : TabBarView(
                            controller: tab,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [for (final t in _tipe) _tabel(t)],
                          ),
                  ),
                ]),
    );
  }

  Widget _panelPeringatan() {
    if (_tipe.isEmpty) return const SizedBox.shrink();
    final tipe = _kunciAktif;
    final belum = _belumLengkap[tipe] ?? 0;
    final terhapus = (_terhapus[tipe] ?? const []).length;
    if (belum == 0 && terhapus == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        if (belum > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$belum ${_tipeAktif['label']} belum lengkap akunnya. Dokumen yang '
                  'memakainya tetap bisa diajukan, tetapi TIDAK akan terjurnal.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
        if (terhapus > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setStateIfMounted(() => _tampilkanTerhapus = !_tampilkanTerhapus),
              icon: Icon(_tampilkanTerhapus
                  ? Icons.visibility_off_outlined
                  : Icons.restore_from_trash_outlined),
              label: Text(_tampilkanTerhapus
                  ? 'Kembali ke daftar'
                  : 'Lihat $terhapus yang dihapus di perangkat ini'),
            ),
          ),
      ]),
    );
  }

  Widget _tabel(Map<String, dynamic> meta) {
    final punyaKode = meta['punyaKode'] == true;
    return AppDataTable(
      minWidth: 900,
      emptyText: _tampilkanTerhapus
          ? 'Tidak ada penghapusan yang menunggu dikirim.'
          : 'Belum ada ${meta['label']}.',
      columns: [
        if (punyaKode) const AppTableColumn('Kode', flex: 2),
        const AppTableColumn('Nama', flex: 3),
        const AppTableColumn('Akun', flex: 5),
        const AppTableColumn('Aktif', flex: 1, align: TextAlign.center),
        const AppTableColumn('Dipakai', flex: 1, align: TextAlign.center),
        const AppTableColumn('Aksi', width: 64, align: TextAlign.center),
      ],
      rows: _terlihat.map((b) {
        final lengkap = b['akunLengkap'] != false;
        return AppTableRowData(cells: [
          if (punyaKode) AppTableCell.text('${b['kode'] ?? ''}', flex: 2),
          AppTableCell(
            flex: 3,
            child: Row(children: [
              if (!lengkap)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Akun belum lengkap — dokumennya tidak akan terjurnal.',
                    child: Icon(Icons.warning_amber_outlined,
                        size: 16, color: Colors.orange),
                  ),
                ),
              Expanded(
                child: Text('${b['nama'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
          AppTableCell.text(_ringkasAkun(meta, b), flex: 5, maxLines: 3),
          AppTableCell.text(b['aktif'] == true ? 'Ya' : 'Tidak',
              flex: 1, align: TextAlign.center),
          AppTableCell.text('${(b['dipakai'] as num?)?.toInt() ?? 0}',
              flex: 1, align: TextAlign.center),
          AppTableCell(
            width: 64,
            child: AksiBarisMenu(
              tooltip: 'Aksi data',
              aksi: _tampilkanTerhapus
                  ? [
                      AksiBaris(
                          ikon: Icons.restore,
                          label: 'Batalkan penghapusan',
                          onTap: _sibuk ? null : () => _pulihkanBaris(meta, b)),
                    ]
                  : [
                      AksiBaris(
                          ikon: Icons.edit_outlined,
                          label: 'Ubah data',
                          onTap: _boleh('update') && !_sibuk
                              ? () => _form(meta, b)
                              : null),
                      AksiBaris(
                          ikon: Icons.copy_outlined,
                          label: 'Salin sebagai data baru',
                          onTap: _boleh('create') && !_sibuk
                              ? () => _form(meta, b, true)
                              : null),
                      AksiBaris(
                          ikon: Icons.delete_outline,
                          label: 'Hapus data',
                          merusak: true,
                          onTap: _boleh('delete') && !_sibuk
                              ? () => _hapusBaris(meta, b)
                              : null),
                    ],
            ),
          ),
        ]);
      }).toList(),
    );
  }
}
