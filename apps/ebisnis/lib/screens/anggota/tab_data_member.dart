import 'dart:io';
import 'dart:typed_data';

import 'package:core_db/core_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../models.dart';
import '../../services/master_offline.dart';
import '../../services/simple_xlsx.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import 'kebijakan_tipe_member.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/progress_sinkron_awal.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/aksi_baris_menu.dart';

final _formatTanggalKadaluarsa = DateFormat('dd-MM-yyyy');

/// Tab "Data Member Baru" (padanan `anggota_koperasi.jsp`) -- daftar/CRUD
/// member koperasi, sisi paling lengkap dari layar Pelanggan. Sama dgn
/// versi sebelum tab-tab lain ditambahkan, PLUS: hapus member (`anggota_hapus`,
/// baru), field tambahan di form (tipe/kategori sivitas, tanggal kadaluarsa,
/// kode manual saat ubah, userid/pass opsional) utk paritas JSP.
///
/// TIDAK diporting dari JSP: penampil password (dekripsi plaintext ke UI --
/// pola tak aman yg sengaja tak direplikasi) dan tombol kirim-notifikasi
/// per-baris/massal (fitur terpisah, di luar cakupan 6 tab yg diminta).
class AnggotaTabDataMember extends StatefulWidget {
  const AnggotaTabDataMember({
    super.key,
    this.refreshVersion = 0,
    this.onBukaSinkronisasi,
  });

  final int refreshVersion;
  final VoidCallback? onBukaSinkronisasi;

  @override
  State<AnggotaTabDataMember> createState() => _AnggotaTabDataMemberState();
}

class _AnggotaTabDataMemberState extends State<AnggotaTabDataMember>
    with JejakGalat {
  bool _memuat = true;
  bool _sinkronBerjalan = false;
  bool _memulaiDataSample = false;
  bool _memprosesPin = false;
  String? _pesanError;
  List<Anggota> _daftar = [];
  List<Kategori> _jenisAnggota = [];
  List<Kategori> _tipeAnggota = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  Map<String, dynamic>? _statistik;
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  static const _pageSize = 15;

  bool _sinkronAwalSudahDicoba = false;

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  @override
  void didUpdateWidget(covariant AnggotaTabDataMember oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) {
      _muatSemua();
    }
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      await Future.wait(
          [_muatDaftar(), _muatJenis(), _muatTipe(), _muatStatistik()]);
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
    // SINKRON AWAL otomatis ber-progress-bar (permintaan bisnis): cache
    // offline member masih kosong padahal server punya ribuan baris ->
    // hidrasi penuh sekali dgn progress terlihat. Hanya dicoba sekali per
    // buka layar; saat offline dilewati diam-diam (dicoba lagi lain kali).
    if (!_sinkronAwalSudahDicoba && mounted) {
      _sinkronAwalSudahDicoba = true;
      final kosong = (await CoreDb.instance.jumlahAnggotaCache()) == 0;
      if (kosong && _total > 0 && mounted) {
        await _sinkronkanCacheOffline();
      }
    }
  }

  Future<void> _muatDaftar() async {
    try {
      // LOKAL PENUH dulu: bila cache hasil sinkron member (anggota_cache,
      // ribuan baris) sudah terisi, halaman dibangun dari sana -- BUKAN dari
      // snapshot 15-baris terakhir. Paginasi + pencarian bekerja penuh
      // offline; hasil server tetap menyusul sbg pembaruan terotoritatif.
      final jumlahLokal =
          await CoreDb.instance.jumlahAnggotaCache(kataKunci: _kataKunci);
      final pakaiCachePenuh = jumlahLokal > 0;
      if (pakaiCachePenuh && mounted) {
        final barisLokal = await CoreDb.instance.cariAnggotaCache(_kataKunci,
            limit: _pageSize, offset: (_halaman - 1) * _pageSize);
        setStateIfMounted(() {
          _daftar = barisLokal.map(Anggota.fromCache).toList();
          _total = jumlahLokal;
          _idBaru = {};
          _idBerubah = {};
          _jumlahHapus = 0;
          _memuat = false;
        });
      }
      // Lalu server: emisi snapshot dilewati bila cache penuh sudah tampil
      // (snapshot hanya 1 halaman dan akan menutupi tampilan penuh).
      await MasterOffline.daftarCacheDulu(
          'anggota_list',
          {
            'keyword': _kataKunci.isEmpty ? null : _kataKunci,
            'page': _halaman,
            'page_size': _pageSize
          },
          'master:anggota', onData: (hasil) {
        if (!mounted) return;
        final dariServer = hasil['dariServer'] == true;
        if (!dariServer && pakaiCachePenuh) return;
        final data = ((hasil['data'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            // Draf create offline belum punya id -- model Anggota mensyaratkan
            // id int, jadi baris draf dilewati sampai tersinkron ke server.
            .where((e) => e['id'] is int)
            .map(Anggota.fromJson)
            .toList();
        setStateIfMounted(() {
          _daftar = data;
          _total = dariServer
              ? (hasil['total'] as num?)?.toInt() ?? data.length
              : data.length;
          _idBaru = dariServer
              ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(hasil['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus = dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
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
      if (mounted) setStateIfMounted(() => _pesanError = terapkanGalat(e));
    }
  }

  Future<void> _muatJenis() async {
    try {
      final hasil = await ApiClient.instance.aksi('jenis_anggota_list');
      final data = ((hasil['data'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setStateIfMounted(() => _jenisAnggota = data);
    } catch (_) {
      // Dropdown jenis gagal muat -- form tetap bisa dipakai tanpa memilih jenis.
    }
  }

  Future<void> _muatTipe() async {
    try {
      // Ber-cache dgn kunci SENDIRI (bukan 'master:tipe_anggota' milik tab
      // admin -- bentuk responsnya beda) supaya dropdown + kebijakan wajib
      // HP/email per tipe tetap tersedia saat offline.
      final hasil = await MasterOffline.daftarDenganCache(
          'tipe_anggota_list', {}, 'master:tipe_anggota_pilihan');
      final data = ((hasil['data'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setStateIfMounted(() => _tipeAnggota = data);
    } catch (_) {
      // Dropdown tipe gagal muat -- form tetap bisa dipakai tanpa memilih tipe.
    }
  }

  Future<void> _muatStatistik() async {
    try {
      final hasil = await ApiClient.instance.aksi('anggota_statistik');
      if (mounted) setStateIfMounted(() => _statistik = hasil);
    } catch (_) {
      // dasbor KPI gagal muat bukan blocker.
    }
  }

  Future<void> _cariUlang(String v) async {
    setStateIfMounted(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int halamanBaru) async {
    setStateIfMounted(() => _halaman = halamanBaru);
    await _muatDaftar();
  }

  /// Loop unduh inkremental anggota_sync_list -> anggota_cache. [lapor]
  /// menggerakkan progress bar (total dari anggota_list, mis. 2.697 member).
  Future<int> _loopSinkronAnggota(
      void Function(int tersinkron, int? total) lapor) async {
    var sejakId = 0;
    var totalTersinkron = 0;
    while (true) {
      final hasil = await ApiClient.instance.aksi('anggota_sync_list', {
        'sejak_id': sejakId,
        'page_size': 500,
        'id_toko': Sesi.instance.idTokoTerpilih,
      });
      final data = (hasil['data'] as List?) ?? [];
      if (data.isNotEmpty) {
        await CoreDb.instance.upsertAnggotaCache(data
            .map((e) => Anggota.keCacheRow(e as Map<String, dynamic>))
            .toList());
        totalTersinkron += data.length;
      }
      lapor(totalTersinkron, _total > 0 ? _total : null);
      sejakId = (hasil['maksId'] as num?)?.toInt() ?? sejakId;
      if (hasil['adaLagi'] != true) break;
    }
    return totalTersinkron;
  }

  Future<void> _sinkronkanCacheOffline() async {
    if (_sinkronBerjalan || !mounted) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      // Dialog progress generik (jalankanDenganProgressSinkron) -- sama
      // dgn yang dipakai modul lain utk hidrasi awal cache.
      final total = await jalankanDenganProgressSinkron<int>(
        context,
        judul: 'Unduh member ke cache offline',
        satuan: 'member',
        tugas: _loopSinkronAnggota,
      );
      if (total != null && mounted) {
        final kosong = total == 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: Duration(seconds: kosong ? 8 : 4),
          content: Text(kosong
              ? 'Belum ada member aktif di server. Tombol ini hanya mengunduh cache; buka tab Sinkronisasi Sivitas untuk membuat member dari Siswa, Mahasiswa, Dosen, Guru, atau Pegawai.'
              : '$total member diunduh ke cache offline.'),
        ));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _sinkronBerjalan = false);
    }
  }

  Future<void> _mulaiDataSamplePelanggan() async {
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buat 100.000 pelanggan contoh?'),
        content: const Text(
            'Fitur ini hanya untuk toko demo/UAT. Nama pelanggan memakai nama Indonesia yang umum. Proses berjalan di server secara background dan aman ditekan ulang karena kode pelanggan bersifat idempoten.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Mulai')),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;
    setStateIfMounted(() => _memulaiDataSample = true);
    try {
      final hasil = await ApiClient.instance.aksi('pos_demo_seed_customers', {
        'toko_id': Sesi.instance.tokoId,
        'konfirmasi': 'SEED-DEMO-PELANGGAN-100000',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${hasil['description'] ?? 'Job 100.000 pelanggan contoh dimulai.'}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memulai data pelanggan: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memulaiDataSample = false);
    }
  }

  Future<void> _bukaFormAnggota({Anggota? anggota}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormAnggota(
        anggota: anggota,
        jenisAnggota: _jenisAnggota,
        tipeAnggota: _tipeAnggota,
      ),
    );
    if (tersimpan == true) await _muatSemua();
  }

  void _infoPin(String pesan) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  Future<List<Map<String, dynamic>>> _ambilSemuaMemberUntukPin() async {
    final semua = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final hasil = await ApiClient.instance.aksi('anggota_list', {
        'page': page,
        'page_size': 100,
      });
      final data = ((hasil['data'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      semua.addAll(data);
      final total = (hasil['total'] as num?)?.toInt() ?? semua.length;
      if (data.isEmpty || semua.length >= total) return semua;
      page++;
    }
  }

  /// Mengunduh STATUS + template penggantian PIN, bukan PIN asli. PIN baru
  /// disimpan server sebagai PBKDF2+salt sehingga memang tidak dapat dibalik.
  Future<void> _downloadTemplatePin() async {
    if (_memprosesPin) return;
    setStateIfMounted(() => _memprosesPin = true);
    try {
      final data = await _ambilSemuaMemberUntukPin();
      final bytes = buildSimpleXlsx(
        sheetName: 'PIN Member',
        headers: const [
          'ID_MEMBER',
          'KODE_MEMBER',
          'NAMA_MEMBER',
          'IDENTITAS',
          'PIN_SUDAH_DIATUR',
          'PIN_BARU',
          'KETERANGAN',
        ],
        rows: data
            .map((m) => <Object?>[
                  m['id'] ?? '',
                  m['kode'] ?? '',
                  m['nama'] ?? '',
                  m['kodeIdentitas'] ?? '',
                  m['pinSudahDiatur'] == true ? 'YA' : 'BELUM',
                  '',
                  'Isi PIN_BARU 4-8 angka. Untuk PIN berawalan 0, format sel sebagai Text.',
                ])
            .toList(),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Template PIN Member',
        fileName:
            'Template_PIN_Member_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null) {
        await File(path).writeAsBytes(bytes);
        _infoPin(
            '${data.length} member diekspor. PIN asli/hash tidak disertakan demi keamanan.');
      }
    } catch (e) {
      _infoPin('Template PIN belum berhasil dibuat: $e');
    } finally {
      if (mounted) setStateIfMounted(() => _memprosesPin = false);
    }
  }

  Future<void> _uploadPin() async {
    if (_memprosesPin) return;
    final dipilih = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih Template PIN Member',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (dipilih == null || dipilih.files.isEmpty) return;
    final file = dipilih.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      _infoPin('Berkas Excel tidak dapat dibaca.');
      return;
    }
    setStateIfMounted(() => _memprosesPin = true);
    try {
      final tabel = readSimpleXlsx(Uint8List.fromList(bytes));
      if (tabel.length < 2) {
        throw const FormatException('Excel tidak memiliki baris data.');
      }
      final header = <String, int>{};
      for (var i = 0; i < tabel.first.length; i++) {
        header[tabel.first[i].trim().toUpperCase()] = i;
      }
      final idKolom = header['ID_MEMBER'];
      final kodeKolom = header['KODE_MEMBER'];
      final pinKolom = header['PIN_BARU'];
      if ((idKolom == null && kodeKolom == null) || pinKolom == null) {
        throw const FormatException(
            'Kolom ID_MEMBER atau KODE_MEMBER, serta PIN_BARU wajib tersedia.');
      }
      String nilai(List<String> row, int? kolom) =>
          kolom == null || kolom >= row.length ? '' : row[kolom].trim();

      final baris = <Map<String, dynamic>>[];
      for (var i = 1; i < tabel.length; i++) {
        final row = tabel[i];
        final pin = nilai(row, pinKolom).replaceFirst("'", '');
        if (pin.isEmpty) continue;
        final idText = nilai(row, idKolom).replaceFirst(RegExp(r'\.0$'), '');
        final kode = nilai(row, kodeKolom);
        final id = int.tryParse(idText);
        if (id == null && kode.isEmpty) {
          throw FormatException('Baris ${i + 1}: identitas member kosong.');
        }
        if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
          throw FormatException(
              'Baris ${i + 1}: PIN wajib terdiri dari 4 sampai 8 angka.');
        }
        baris.add({
          if (id != null) 'id': id,
          if (kode.isNotEmpty) 'kode': kode,
          'pin': pin
        });
      }
      if (baris.isEmpty) {
        throw const FormatException('Tidak ada PIN_BARU yang diisi.');
      }
      if (!mounted) return;
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ganti PIN Member Massal?'),
          content: Text(
              '${baris.length} PIN akan diganti. Proses ini tidak menampilkan atau mencadangkan PIN lama dan hanya dapat dijalankan saat online.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Ganti PIN')),
          ],
        ),
      );
      if (lanjut != true) return;
      final hasil = await ApiClient.instance
          .aksi('anggota_pin_simpan_massal', {'data': baris});
      _infoPin('${hasil['description'] ?? '${baris.length} PIN diperbarui.'}');
      await _muatSemua();
    } catch (e) {
      _infoPin('Upload PIN gagal: $e');
    } finally {
      if (mounted) setStateIfMounted(() => _memprosesPin = false);
    }
  }

  Future<void> _aturPinMember(Anggota anggota) async {
    final pin = TextEditingController();
    final ulang = TextEditingController();
    String? galat;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:
              Text('${anggota.pinSudahDiatur ? 'Ganti' : 'Atur'} PIN Member'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${anggota.nama} · ${anggota.kode}'),
                const SizedBox(height: 12),
                TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(
                      labelText: 'PIN baru (4-8 angka)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ulang,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(
                      labelText: 'Ulangi PIN baru',
                      border: OutlineInputBorder()),
                ),
                if (galat != null) ...[
                  const SizedBox(height: 8),
                  Text(galat!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final nilai = pin.text.trim();
                if (!RegExp(r'^[0-9]{4,8}$').hasMatch(nilai)) {
                  setDialogState(
                      () => galat = 'PIN wajib terdiri dari 4 sampai 8 angka.');
                } else if (nilai != ulang.text.trim()) {
                  setDialogState(() => galat = 'Konfirmasi PIN tidak sama.');
                } else {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Simpan PIN'),
            ),
          ],
        ),
      ),
    );
    if (simpan != true || !mounted) {
      pin.dispose();
      ulang.dispose();
      return;
    }
    final nilai = pin.text.trim();
    pin.dispose();
    ulang.dispose();
    try {
      final hasil = await ApiClient.instance.aksi('anggota_pin_simpan_massal', {
        'data': [
          {'id': anggota.id, 'pin': nilai}
        ]
      });
      _infoPin('${hasil['description'] ?? 'PIN member berhasil diperbarui.'}');
      await _muatSemua();
    } catch (e) {
      _infoPin('PIN belum berhasil diperbarui: $e');
    }
  }

  Future<void> _hapusAnggota(Anggota a) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Member?'),
        content: Text(
            'Member "${a.nama}" akan dihapus permanen. Kalau member ini punya riwayat transaksi/topup, penghapusan akan ditolak -- nonaktifkan saja sebagai gantinya.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'anggota_hapus',
        body: {'id': a.id},
        kunci: 'anggota:${a.id}',
        cacheKey: 'master:anggota',
        rowLokal: {'id': a.id},
        hapusLokal: true,
      );
      await _muatSemua();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_pesanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_pesanError!, textAlign: TextAlign.center),
              AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _muatSemua, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muatSemua,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_statistik != null)
            _KartuStatistikAnggota(statistik: _statistik!),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari nama/kode/telepon/email...',
                  debounce: const Duration(milliseconds: 450),
                  onChanged: _cariUlang,
                ),
              ),
              const SizedBox(width: 8),
              if (Sesi.instance.bolehDataSample) ...[
                OutlinedButton.icon(
                  onPressed:
                      _memulaiDataSample ? null : _mulaiDataSamplePelanggan,
                  icon: _memulaiDataSample
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.science_outlined, size: 18),
                  label: Text(_memulaiDataSample
                      ? 'Memulai...'
                      : 'Sample 100K Pelanggan'),
                ),
                const SizedBox(width: 8),
              ],
              if (Sesi.instance.bolehKelola &&
                  widget.onBukaSinkronisasi != null) ...[
                FilledButton.icon(
                  onPressed: widget.onBukaSinkronisasi,
                  icon: const Icon(Icons.sync_alt, size: 18),
                  label: const Text('Buat dari Sivitas'),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: _sinkronBerjalan ? null : _sinkronkanCacheOffline,
                icon: _sinkronBerjalan
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Unduh Offline'),
              ),
              if (Sesi.instance.bolehKelola) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  enabled: !_memprosesPin,
                  tooltip: 'Kelola PIN member',
                  onSelected: (value) {
                    if (value == 'download') _downloadTemplatePin();
                    if (value == 'upload') _uploadPin();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'download',
                        child: Text('Download Template PIN')),
                    PopupMenuItem(
                        value: 'upload', child: Text('Upload PIN Member')),
                  ],
                  child: IgnorePointer(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: _memprosesPin
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.password_outlined, size: 18),
                      label: const Text('Kelola PIN'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _bukaFormAnggota(),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Tambah Member'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          BannerPerubahanServer(
            key: ValueKey('perubahan:$_versiPerubahan'),
            baru: _idBaru.length,
            berubah: _idBerubah.length,
            dihapus: _jumlahHapus,
          ),
          _tabelAnggota(),
        ],
      ),
    );
  }

  Widget _tabelAnggota() {
    return AppDataTable(
      minWidth: 1040,
      emptyText: 'Belum ada member.',
      columns: [
        const AppTableColumn('Nama', flex: 3),
        const AppTableColumn('Kode', flex: 2),
        const AppTableColumn('Identitas', flex: 2),
        const AppTableColumn('Jenis / Tipe', flex: 2),
        const AppTableColumn('Kontak', flex: 3),
        const AppTableColumn('Status', flex: 2, align: TextAlign.center),
        AppTableColumn('Aksi', width: 64, align: TextAlign.center),
      ],
      rows: _daftar.map((a) {
        final kontak = [
          if (a.hp.trim().isNotEmpty) a.hp.trim(),
          if (a.telp.trim().isNotEmpty) a.telp.trim(),
          if (a.email.trim().isNotEmpty) a.email.trim(),
        ].join(' / ');
        final warnaStatus =
            a.aktif ? AppColors.success : AppColors.textSecondary;
        final jenisTipe = [
          if (a.jenisNama.isNotEmpty) a.jenisNama,
          if (a.tipeNama.isNotEmpty && a.tipeNama != '-') a.tipeNama,
        ].join(' · ');

        return AppTableRowData(
          onTap: Sesi.instance.bolehKelola
              ? () => _bukaFormAnggota(anggota: a)
              : null,
          cells: [
            AppTableCell(
              flex: 3,
              child: KilauBaris(
                kunci: '${a.id}',
                idBaru: _idBaru,
                idBerubah: _idBerubah,
                child: Row(
                  children: [
                    IndikatorBarisSinkron(kunci: 'anggota:${a.id}'),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF1E3A5F),
                      child: Text(
                        a.nama.isNotEmpty ? a.nama[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AppTableCell.text(a.kode.isEmpty ? '-' : a.kode, flex: 2),
            AppTableCell.text(
              a.kodeIdentitas.isEmpty ? '-' : a.kodeIdentitas,
              flex: 2,
            ),
            AppTableCell.text(
              jenisTipe.isEmpty ? 'Tanpa Jenis' : jenisTipe,
              flex: 2,
              maxLines: 2,
            ),
            AppTableCell.text(
              kontak.isEmpty ? '-' : kontak,
              flex: 3,
              maxLines: 2,
            ),
            AppTableCell(
              flex: 2,
              align: TextAlign.center,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusPill(
                    label: a.aktif ? 'Aktif' : 'Nonaktif',
                    warna: warnaStatus,
                  ),
                  if (a.wajibPin)
                    const StatusPill(
                      label: 'Wajib PIN',
                      warna: AppColors.warning,
                    ),
                  StatusPill(
                    label:
                        a.pinSudahDiatur ? 'PIN Terpasang' : 'PIN Belum Diatur',
                    warna: a.pinSudahDiatur
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            AppTableCell(
              width: 64,
              align: TextAlign.center,
              child: AksiBarisMenu(aksi: [
                AksiBaris(
                  ikon: Icons.history,
                  label: 'Riwayat data ini',
                  onTap: () => tampilkanRiwayatData(context,
                      entitas: 'anggota', id: a.id, judul: a.nama),
                ),
                AksiBaris(
                  ikon: Icons.password_outlined,
                  label:
                      a.pinSudahDiatur ? 'Ganti PIN member' : 'Atur PIN member',
                  onTap: Sesi.instance.bolehKelola
                      ? () => _aturPinMember(a)
                      : null,
                ),
                AksiBaris(
                  ikon: Icons.edit_outlined,
                  label: 'Ubah member',
                  onTap: Sesi.instance.bolehKelola
                      ? () => _bukaFormAnggota(anggota: a)
                      : null,
                ),
                AksiBaris(
                  ikon: Icons.delete_outline,
                  label: 'Hapus member',
                  merusak: true,
                  onTap:
                      Sesi.instance.bolehKelola ? () => _hapusAnggota(a) : null,
                ),
              ]),
            ),
          ],
        );
      }).toList(),
      pagination: AppTablePagination(
        halaman: _halaman,
        totalHalaman: _totalHalaman,
        totalData: _total,
        labelData: 'member',
        onSebelumnya: _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
        onBerikutnya: _halaman < _totalHalaman
            ? () => _pindahHalaman(_halaman + 1)
            : null,
      ),
    );
  }
}

class _KartuStatistikAnggota extends StatelessWidget {
  final Map<String, dynamic> statistik;
  const _KartuStatistikAnggota({required this.statistik});

  @override
  Widget build(BuildContext context) {
    final item = <(IconData, String, String, Color)>[
      (
        Icons.people_outline,
        'Total',
        '${statistik['totalAnggota'] ?? 0}',
        AppColors.primary
      ),
      (
        Icons.check_circle_outline,
        'Aktif',
        '${statistik['totalAktif'] ?? 0}',
        AppColors.success
      ),
      (
        Icons.pause_circle_outline,
        'Nonaktif',
        '${statistik['totalNonaktif'] ?? 0}',
        AppColors.textSecondary
      ),
      (
        Icons.lock_outline,
        'Wajib PIN',
        '${statistik['totalWajibPin'] ?? 0}',
        AppColors.warning
      ),
    ];
    final byJenis =
        titikDariList(statistik['byJenis'] as List?, nilaiKey: 'jumlah');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: item.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (icon, label, nilai, warna) = item[i];
              return SizedBox(
                  width: 190,
                  child: AppKpiCard(
                      icon: icon, warna: warna, nilai: nilai, label: label));
            },
          ),
        ),
        if (byJenis.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionCard(
              judul: 'Anggota per Jenis Keanggotaan',
              child: BarHorizontal(data: byJenis, tampilkanPeringkat: false)),
        ],
      ],
    );
  }
}

class _FormAnggota extends StatefulWidget {
  final Anggota? anggota;
  final List<Kategori> jenisAnggota;
  final List<Kategori> tipeAnggota;
  const _FormAnggota({
    required this.anggota,
    required this.jenisAnggota,
    required this.tipeAnggota,
  });

  @override
  State<_FormAnggota> createState() => _FormAnggotaState();
}

class _FormAnggotaState extends State<_FormAnggota> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _kode;
  late final TextEditingController _kodeIdentitas;
  late final TextEditingController _hp;
  late final TextEditingController _telp;
  late final TextEditingController _email;
  late final TextEditingController _keterangan;
  late final TextEditingController _userid;
  late final TextEditingController _pass;
  int? _jenisId;
  int? _tipeId;
  bool _aktif = true;
  DateTime? _tanggalKadaluarsa;
  bool _menyimpan = false;
  String? _pesanError;

  Kategori? get _tipeTerpilih {
    for (final k in widget.tipeAnggota) {
      if (k.id == _tipeId) return k;
    }
    return null;
  }

  /// Kebijakan kontak mengikuti tipe terpilih: nilai eksplisit server bila
  /// ada, selain itu default per nama tipe. Tanpa tipe = tidak wajib.
  bool get _wajibHpTipe {
    final t = _tipeTerpilih;
    if (t == null) return false;
    return t.wajibHp ?? defaultWajibHpTipe(t.nama);
  }

  bool get _wajibEmailTipe => _tipeTerpilih?.wajibEmail ?? false;

  @override
  void initState() {
    super.initState();
    final a = widget.anggota;
    _nama = TextEditingController(text: a?.nama ?? '');
    _kode = TextEditingController(text: a?.kode ?? '');
    _kodeIdentitas = TextEditingController(text: a?.kodeIdentitas ?? '');
    _hp = TextEditingController(text: a?.hp ?? '');
    _telp = TextEditingController(text: a?.telp ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _keterangan = TextEditingController(text: a?.keterangan ?? '');
    _userid = TextEditingController(text: a?.userid ?? '');
    _pass = TextEditingController();
    _jenisId = a?.jenisAnggotaKoperasiId;
    _tipeId = a?.tipeAnggotaKoperasiId;
    _aktif = a?.aktif ?? true;
    if (a?.tanggalKadaluarsa != null && a!.tanggalKadaluarsa!.isNotEmpty) {
      try {
        _tanggalKadaluarsa = DateTime.parse(a.tanggalKadaluarsa!);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nama.dispose();
    _kode.dispose();
    _kodeIdentitas.dispose();
    _hp.dispose();
    _telp.dispose();
    _email.dispose();
    _keterangan.dispose();
    _userid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggalKadaluarsa() async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggalKadaluarsa ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (hasil != null) setStateIfMounted(() => _tanggalKadaluarsa = hasil);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final ubah = widget.anggota != null;
      final body = {
        if (ubah) 'id': widget.anggota!.id,
        'nama': _nama.text.trim(),
        if (ubah) 'kode': _kode.text.trim(),
        'kode_identitas': _kodeIdentitas.text.trim(),
        'hp': _hp.text.trim(),
        'telp': _telp.text.trim(),
        'email': _email.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'jenis_anggota_koperasi_id': _jenisId,
        'tipe_anggota_koperasi_id': _tipeId,
        'aktif': _aktif,
        'tanggal_kadaluarsa': _tanggalKadaluarsa == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_tanggalKadaluarsa!),
        if (_userid.text.trim().isNotEmpty) 'userid': _userid.text.trim(),
        if (_pass.text.trim().isNotEmpty) 'pass': _pass.text.trim(),
      };
      await prosesSimpanMaster(
        context,
        aksi: 'anggota_simpan',
        body: body,
        kunci: ubah
            ? 'anggota:${widget.anggota!.id}'
            : 'anggota:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:anggota',
        // Kata sandi cukup tersimpan di outbox utk replay -- jangan ikut
        // ke snapshot tampilan daftar.
        rowLokal: Map<String, dynamic>.from(body)..remove('pass'),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.anggota != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Member' : 'Tambah Member Baru',
            subtitle: ubah
                ? 'Kode member: ${widget.anggota!.kode}'
                : 'Lengkapi identitas pelanggan/member agar transaksi dan laporan lebih mudah dilacak.',
            icon: ubah ? Icons.edit_outlined : Icons.person_add_alt_1_outlined,
            errorText: _pesanError,
            errorDetail: detailUntuk(_pesanError),
            actions: [
              OutlinedButton.icon(
                onPressed:
                    _menyimpan ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
            children: [
              AppFormSection(
                judul: 'Identitas',
                deskripsi:
                    'Data dasar pelanggan/member yang muncul di kasir dan laporan.',
                children: [
                  AppFormTextField(
                    label: 'Nama *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  if (ubah)
                    AppFormTextField(
                      label: 'Kode Member (kosongkan utk biarkan apa adanya)',
                      controller: _kode,
                    ),
                  AppFormTextField(
                    label: 'Kode Identitas (NIS/NIM/dll)',
                    controller: _kodeIdentitas,
                  ),
                  DropdownButtonFormField<int?>(
                    value: _jenisId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Jenis Anggota',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('-- Tanpa Jenis --')),
                      ...widget.jenisAnggota.map((k) => DropdownMenuItem<int?>(
                          value: k.id, child: Text(k.nama))),
                    ],
                    onChanged: (v) => setStateIfMounted(() => _jenisId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _tipeId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Tipe Anggota (Kategori Sivitas)',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('-- Tanpa Tipe --')),
                      ...widget.tipeAnggota.map((k) => DropdownMenuItem<int?>(
                          value: k.id, child: Text(k.nama))),
                    ],
                    onChanged: (v) => setStateIfMounted(() => _tipeId = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Kontak & Status',
                children: [
                  // Wajib/tidaknya No. HP & Email mengikuti kebijakan TIPE
                  // member terpilih (kolom Wajib Memasukkan No. HP/Email di
                  // tab Tipe Member; default per nama: Pegawai/Dosen/Guru/
                  // Umum wajib HP, Mahasiswa/Siswa tidak; email bebas semua).
                  AppFormTextField(
                    label: 'No. HP${_wajibHpTipe ? ' *' : ''}',
                    controller: _hp,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final digit = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                      if (digit.isEmpty) {
                        return _wajibHpTipe
                            ? 'Nomor HP wajib diisi untuk tipe member ini'
                            : null;
                      }
                      if (digit.length < 9 || digit.length > 16) {
                        return 'Nomor HP belum valid';
                      }
                      return null;
                    },
                  ),
                  AppFormTextField(
                    label: 'Telepon',
                    controller: _telp,
                    keyboardType: TextInputType.phone,
                  ),
                  AppFormTextField(
                    label: 'Email${_wajibEmailTipe ? ' *' : ''}',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        _wajibEmailTipe && (v == null || v.trim().isEmpty)
                            ? 'Email wajib diisi untuk tipe member ini'
                            : null,
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                    maxLines: 2,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pilihTanggalKadaluarsa,
                          icon: const Icon(Icons.event_busy, size: 16),
                          label: Text(
                            _tanggalKadaluarsa == null
                                ? 'Tanggal Kadaluarsa (opsional)'
                                : 'Kadaluarsa: ${_formatTanggalKadaluarsa.format(_tanggalKadaluarsa!)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_tanggalKadaluarsa != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setStateIfMounted(
                              () => _tanggalKadaluarsa = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppFormSwitchTile(
                    title: 'Aktif',
                    value: _aktif,
                    onChanged: (v) => setStateIfMounted(() => _aktif = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Kredensial Login (opsional)',
                deskripsi:
                    'Kosongkan bila member ini tidak perlu login sendiri (mis. portal member). Isi hanya bila ingin mengubah.',
                children: [
                  AppFormTextField(label: 'User ID', controller: _userid),
                  AppFormTextField(
                    label: 'Kata Sandi Baru',
                    controller: _pass,
                    obscureText: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
