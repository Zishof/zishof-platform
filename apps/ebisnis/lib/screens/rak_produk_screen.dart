import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../widgets/rincian_intip_dialog.dart';
import '../widgets/safe_state.dart';
import '../services/simpan_berkas_helper.dart';

/// Layar **Manajemen Rak Produk** (`MenuEBisnis.rakProduk`).
///
/// Memenuhi kebutuhan tata kelola rak, RAK Utama (default penjualan), dan
/// sinkronisasi stok per rak di Toko Ritel:
/// 1. **Master Rak Toko**: Tambah, ubah, dan hapus data rak (Kode Rak, Nama Rak,
///    Lokasi / Lorong, Keterangan) beserta ringkasan jumlah produk dan total stok
///    fisik di dalam setiap rak. Saat system startup, setiap toko secara otomatis
///    dibuatkan default **"RAK Utama"** (`RAK-UTAMA`) dan seluruh produk yang
///    belum memiliki rak dimasukkan ke dalam **RAK Utama**.
/// 2. **Pemetaan Produk ke Rak via Banbox, AmbilDataBanyak (seperti ZKoss), & Excel**:
///    - Memasukkan produk ke dalam rak terpilih menggunakan komponen
///      [PencarianProdukBanbox] (ketik nama/kode/barcode -> pilih dari daftar saran
///      atau scan barcode langsung).
///    - Memilih banyak produk sekaligus melalui dialog **Ambil Data Banyak**
///      (seperti komponen `AmbilDataBanyak` pada ZKoss) dengan pencarian, centang
///      *Pilih Semua*, dan opsi pindahkan dari rak lama.
///    - Memindahkan produk antar-rak (**Pindahkan ke Rak Lain**), di mana apabila
///      produk tidak lagi ditampung oleh rak utamanya yang lama, maka **RAK Utama**
///      produk otomatis ikut berpindah ke rak tujuan sehingga default rak tidak
///      pernah berada di luar daftar rak produk tersebut.
///    - Mengunduh dan mengunggah pemetaan produk per rak melalui file Excel
///      (`rak_download_excel` & `rak_upload_excel`) lengkap dengan indikator
///      progress bar bertahap (persentase & status aktivitas).
/// 3. **Aturan Pengisian Jumlah Barang via Stok Opname**:
///    - Jumlah stok barang di dalam rak wajib dientri melalui menu **Stok Opname**
///      (baik *SO by Scan*, *SO Grand*, *SO Harian*, maupun *Input Opname*) dengan
///      memilih raknya terlebih dahulu.
/// 4. **Sinkronisasi Otomatis Stok Per Rak & Stok Total Produk**:
///    - Menyediakan pemantauan dan tombol **Sinkronkan Stok Rak & Produk** agar
///      jumlah stok di seluruh rak (`SUM(rak_produk_stok.stok)`) selalu sinkron
///      dan bernilai sama persis dengan stok keseluruhan produk (`produk.stok`).
class RakProdukScreen extends StatefulWidget {
  const RakProdukScreen({super.key});

  @override
  State<RakProdukScreen> createState() => _RakProdukScreenState();
}

class _RakProdukScreenState extends State<RakProdukScreen> {
  final _fmtAngka = NumberFormat('#,##0.##', 'id_ID');
  final _fmtRupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _error;

  List<Map<String, dynamic>> _daftarRak = [];
  Map<String, dynamic> _ringkasan = {};

  int? _rakTerpilihId;
  String _rakTerpilihNama = '';
  String _rakTerpilihKode = '';
  bool _memuatProdukRak = false;
  List<Map<String, dynamic>> _produkDiRak = [];
  static const int _pageSizeProdukRak = kBarisPerHalamanTabel;
  int _halamanProdukRak = 1;
  int _totalProdukRak = 0;
  double _totalStokProdukRak = 0;
  double _totalNilaiProdukRak = 0;
  final Set<int> _produkTerpilihIds = <int>{};

  final TextEditingController _cariRakCtrl = TextEditingController();
  final TextEditingController _cariProdukRakCtrl = TextEditingController();
  final TextEditingController _banboxProdukCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muatDaftarRak();
  }

  @override
  void dispose() {
    _cariRakCtrl.dispose();
    _cariProdukRakCtrl.dispose();
    _banboxProdukCtrl.dispose();
    super.dispose();
  }

  int? get _tokoIdAktif => Sesi.instance.idTokoTerpilih ?? Sesi.instance.tokoId;

  /// Menampilkan dialog progress bar bertahap dengan indikator persentase & aktivitas.
  Future<T?> _jalankanDenganProgress<T>({
    required String judul,
    required Future<T> Function(
            void Function(double progress, String status) update)
        tugas,
  }) async {
    double nilaiProgress = 0.05;
    String teksStatus = 'Menyiapkan proses...';
    StateSetter? setDialogState;
    bool dialogTerbuka = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          setDialogState = setSt;
          final persen = (nilaiProgress.clamp(0.0, 1.0) * 100).round();
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    judul,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$persen%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: nilaiProgress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    teksStatus,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(ctx),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    void updateProgress(double p, String s) {
      nilaiProgress = p;
      teksStatus = s;
      final setter = setDialogState;
      if (setter != null && mounted && dialogTerbuka) {
        try {
          setter(() {});
        } catch (_) {}
      }
    }

    try {
      final hasil = await tugas(updateProgress);
      updateProgress(1.0, 'Selesai (100%).');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return hasil;
    } finally {
      dialogTerbuka = false;
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _muatDaftarRak({bool tampilkanProgress = false}) async {
    Future<void> kerja(void Function(double, String)? updateProgress) async {
      setStateIfMounted(() {
        _memuat = true;
        _error = null;
      });
      try {
        updateProgress?.call(
            0.25, 'Mengambil daftar master rak & ringkasan...');
        final payload = <String, dynamic>{
          'termasuk_nonaktif': true,
        };
        if (_tokoIdAktif != null && _tokoIdAktif! > 0) {
          payload['toko_id'] = _tokoIdAktif;
        }
        if (_cariRakCtrl.text.trim().isNotEmpty) {
          payload['keyword'] = _cariRakCtrl.text.trim();
        }
        final res = await ApiClient.instance.aksi('rak_list', payload);
        updateProgress?.call(
            0.75, 'Menyusun data rak & status sinkronisasi...');
        final list = ((res['data'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry('$k', v)))
            .toList();
        final ringkasan = (res['ringkasan'] is Map)
            ? (res['ringkasan'] as Map).map((k, v) => MapEntry('$k', v))
            : <String, dynamic>{
                'totalRak': res['totalRak'] ?? list.length,
                'totalProdukTerpetakan':
                    res['totalProdukTerpetakan'] ?? res['totalItemRak'] ?? 0,
                'totalProdukBelumBerRak': res['totalProdukBelumBerRak'] ??
                    res['produkBelumAdaRak'] ??
                    0,
                'totalStokBelumBerRak':
                    res['totalStokBelumBerRak'] ?? res['stokBelumAdaRak'] ?? 0,
                'totalStokSemuaRak':
                    res['totalStokSemuaRak'] ?? res['totalStokTerpetakan'] ?? 0,
                'totalStokProdukToko':
                    res['totalStokProdukToko'] ?? res['totalStokToko'] ?? 0,
                'sinkron': res['sinkron'] ?? true,
              };

        if (!mounted) return;
        setStateIfMounted(() {
          _daftarRak = list;
          _ringkasan = ringkasan;
          _memuat = false;
          if (_rakTerpilihId == null && list.isNotEmpty) {
            final pertama = list.first;
            _rakTerpilihId = (pertama['id'] as num?)?.toInt();
            _rakTerpilihNama = '${pertama['nama'] ?? ''}';
            _rakTerpilihKode = '${pertama['kode'] ?? ''}';
          } else if (_rakTerpilihId != null && _rakTerpilihId! > 0) {
            final cocok =
                list.where((r) => (r['id'] as num?)?.toInt() == _rakTerpilihId);
            if (cocok.isNotEmpty) {
              _rakTerpilihNama = '${cocok.first['nama'] ?? ''}';
              _rakTerpilihKode = '${cocok.first['kode'] ?? ''}';
            }
          }
        });
        if (_rakTerpilihId != null) {
          updateProgress?.call(0.90, 'Memuat daftar produk di rak terpilih...');
          await _muatProdukDiRak(_rakTerpilihId!);
        }
      } catch (e) {
        if (mounted) {
          setStateIfMounted(() {
            _error = '$e';
            _memuat = false;
          });
        }
      }
    }

    if (tampilkanProgress) {
      await _jalankanDenganProgress(
        judul: 'Memuat Ulang Data Rak & Produk',
        tugas: (u) => kerja(u),
      );
    } else {
      await kerja(null);
    }
  }

  /// Meminta satu potongan data rak agar perangkat tidak perlu menerima ribuan
  /// baris hanya untuk menggambar tabel. Jumlah dan nilai seluruh hasil tetap
  /// dihitung di layanan, sehingga ringkasan tidak berubah saat halaman diganti.
  Future<void> _muatProdukDiRak(int rakId,
      {int? halaman, bool hapusPilihan = false}) async {
    final halamanDiminta = halaman ?? _halamanProdukRak;
    setStateIfMounted(() => _memuatProdukRak = true);
    try {
      final payload = <String, dynamic>{
        'rak_id': rakId,
        'page': halamanDiminta,
        'page_size': _pageSizeProdukRak,
      };
      if (_tokoIdAktif != null && _tokoIdAktif! > 0) {
        payload['toko_id'] = _tokoIdAktif;
      }
      if (_cariProdukRakCtrl.text.trim().isNotEmpty) {
        payload['keyword'] = _cariProdukRakCtrl.text.trim();
      }
      final res = await ApiClient.instance.aksi('rak_produk_list', payload);
      final list = ((res['data'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry('$k', v)))
          .toList();
      if (mounted) {
        setStateIfMounted(() {
          _produkDiRak = list;
          _halamanProdukRak = (res['page'] as num?)?.toInt() ?? halamanDiminta;
          _totalProdukRak = (res['total'] as num?)?.toInt() ?? list.length;
          _totalStokProdukRak = (res['totalStokRak'] as num?)?.toDouble() ?? 0;
          _totalNilaiProdukRak =
              (res['totalNilaiRak'] as num?)?.toDouble() ?? 0;
          if (hapusPilihan) _produkTerpilihIds.clear();
          _memuatProdukRak = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setStateIfMounted(() => _memuatProdukRak = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat produk rak: $e')),
        );
      }
    }
  }

  Future<void> _tambahProdukKeRakDariBanbox(String kodeAtauBarcode) async {
    final kode = kodeAtauBarcode.trim();
    if (kode.isEmpty) return;
    if (_rakTerpilihId == null || _rakTerpilihId! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Pilih salah satu Rak (selain "Rak Belum Ditentukan") di panel kiri terlebih dahulu untuk memasukkan produk.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final res = await ApiClient.instance.aksi('rak_produk_tambah', {
        if (_tokoIdAktif != null && _tokoIdAktif! > 0) 'toko_id': _tokoIdAktif,
        'rak_id': _rakTerpilihId,
        'kode': kode,
      });
      _banboxProdukCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${res['description'] ?? 'Produk berhasil dimasukkan ke rak $_rakTerpilihNama.'}'),
          backgroundColor: AppColors.success,
        ),
      );
      await _muatDaftarRak();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menambahkan produk ke rak: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _jadikanRakUtamaProduk(Map<String, dynamic> item) async {
    final rakId = (item['rakId'] as num?)?.toInt() ?? _rakTerpilihId;
    final produkId = (item['produkId'] as num?)?.toInt();
    final namaProduk = '${item['produkNama'] ?? item['nama'] ?? '-'}';
    if (rakId == null || rakId <= 0 || produkId == null) return;

    try {
      final res = await ApiClient.instance.aksi('rak_produk_set_utama', {
        if (_tokoIdAktif != null && _tokoIdAktif! > 0) 'toko_id': _tokoIdAktif,
        'rak_id': rakId,
        'produk_id': produkId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${res['description'] ?? 'Rak $_rakTerpilihNama ditetapkan sebagai RAK Utama untuk "$namaProduk".'}'),
          backgroundColor: AppColors.success,
        ),
      );
      await _muatDaftarRak();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengubah RAK Utama produk: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _bukaDialogPindahkanKeRakLain({
    List<int>? daftarProdukId,
    String? labelProduk,
  }) async {
    final ids = daftarProdukId ?? _produkTerpilihIds.toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Pilih minimal satu produk untuk dipindahkan ke rak lain.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final pilihanRakTujuan = _daftarRak.where((r) {
      final id = (r['id'] as num?)?.toInt() ?? 0;
      return id > 0 && id != _rakTerpilihId && r['aktif'] != false;
    }).toList();

    if (pilihanRakTujuan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Belum ada rak tujuan lain yang aktif. Tambahkan rak baru terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int? rakTujuanId = (pilihanRakTujuan.first['id'] as num?)?.toInt();
    bool pindahkanStok = true;
    bool hapusDariRakAsal = true;

    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Pindahkan Produk ke Rak Lain'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labelProduk != null
                      ? 'Produk: $labelProduk'
                      : 'Memindahkan ${ids.length} produk terpilih dari rak "$_rakTerpilihNama".',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: rakTujuanId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Rak Tujuan *',
                    border: OutlineInputBorder(),
                  ),
                  items: pilihanRakTujuan.map((r) {
                    final id = (r['id'] as num).toInt();
                    final kode = '${r['kode'] ?? ''}'.trim();
                    final nama = '${r['nama'] ?? ''}'.trim();
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(kode.isEmpty ? nama : '$kode — $nama'),
                    );
                  }).toList(),
                  onChanged: (v) => setSt(() => rakTujuanId = v),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pindahkanStok,
                  title: const Text(
                      'Ikut pindahkan saldo stok fisik dari rak asal ke rak tujuan'),
                  subtitle:
                      const Text('Menjaga total stok produk tetap konsisten'),
                  onChanged: (v) => setSt(() => pindahkanStok = v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: hapusDariRakAsal,
                  title:
                      const Text('Keluarkan dari rak asal setelah dipindahkan'),
                  subtitle: const Text(
                      'Jika tidak ada rak lain yang menampung produk ini, RAK Utama produk otomatis ikut berpindah ke rak tujuan.'),
                  onChanged: (v) => setSt(() => hapusDariRakAsal = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed:
                  rakTujuanId == null ? null : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.drive_file_move_outlined, size: 18),
              label: const Text('Pindahkan Sekarang'),
            ),
          ],
        ),
      ),
    );

    if (konfirmasi != true || rakTujuanId == null) return;

    try {
      Map<String, dynamic>? res;
      await _jalankanDenganProgress(
        judul: 'Memindahkan Produk ke Rak Tujuan',
        tugas: (update) async {
          update(0.35,
              'Memindahkan ${ids.length} produk & memperbarui RAK Utama...');
          res = await ApiClient.instance.aksi('rak_produk_pindah', {
            if (_tokoIdAktif != null && _tokoIdAktif! > 0)
              'toko_id': _tokoIdAktif,
            if (_rakTerpilihId != null && _rakTerpilihId! > 0)
              'rak_asal_id': _rakTerpilihId,
            'rak_tujuan_id': rakTujuanId,
            'produk_ids': ids,
            'pindahkan_stok': pindahkanStok,
            'hapus_dari_rak_asal': hapusDariRakAsal,
          });
          update(0.85, 'Memuat ulang data rak & produk...');
          await _muatDaftarRak();
        },
      );
      if (!mounted || res == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${res!['description'] ?? 'Produk berhasil dipindahkan ke rak tujuan.'}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memindahkan produk: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _bukaDialogAmbilDataBanyakProduk() async {
    if (_rakTerpilihId == null || _rakTerpilihId! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Pilih salah satu Rak aktif di sebelah kiri terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final cariCtrl = TextEditingController();
    List<Map<String, dynamic>> daftarHasil = [];
    final Set<int> terpilih = <int>{};
    bool memuatCari = true;
    bool pindahkanDariRakLain = false;
    bool jadikanRakUtama = false;
    StateSetter? setModalState;

    Future<void> muatKatalog(String q) async {
      setModalState?.call(() => memuatCari = true);
      try {
        final res = await ApiClient.instance.aksi('katalog', {
          if (_tokoIdAktif != null && _tokoIdAktif! > 0)
            'toko_id': _tokoIdAktif,
          if (q.trim().isNotEmpty) 'keyword': q.trim(),
          'page': 1,
          'pageSize': 250,
        });
        final list = ((res['produk'] ?? res['data']) as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        daftarHasil = list;
      } catch (_) {}
      setModalState?.call(() => memuatCari = false);
    }

    Future<void>.microtask(() => muatKatalog(''));

    final simpan = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          setModalState = setSt;
          final semuaTerpilih = daftarHasil.isNotEmpty &&
              daftarHasil.every(
                  (p) => terpilih.contains((p['id'] as num?)?.toInt() ?? 0));
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.playlist_add_check_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ambil Data Banyak Produk ke Rak "$_rakTerpilihNama"',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 780,
              height: 540,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cariCtrl,
                          decoration: InputDecoration(
                            hintText:
                                'Ketik nama, kode, atau barcode produk lalu Enter...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onSubmitted: (v) => muatKatalog(v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => muatKatalog(cariCtrl.text),
                        icon: const Icon(Icons.search, size: 17),
                        label: const Text('Cari'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: semuaTerpilih,
                            onChanged: (v) {
                              setSt(() {
                                if (v == true) {
                                  for (final p in daftarHasil) {
                                    final id = (p['id'] as num?)?.toInt();
                                    if (id != null && id > 0) terpilih.add(id);
                                  }
                                } else {
                                  for (final p in daftarHasil) {
                                    final id = (p['id'] as num?)?.toInt();
                                    if (id != null) terpilih.remove(id);
                                  }
                                }
                              });
                            },
                          ),
                          Text(
                            'Pilih Semua di Daftar (${terpilih.length} dipilih)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: pindahkanDariRakLain,
                            onChanged: (v) =>
                                setSt(() => pindahkanDariRakLain = v ?? false),
                          ),
                          const Text(
                            'Pindahkan dari rak lama (update RAK Utama otomatis)',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: jadikanRakUtama,
                            onChanged: (v) =>
                                setSt(() => jadikanRakUtama = v ?? false),
                          ),
                          const Text(
                            'Jadikan Rak Ini sebagai RAK Utama',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Expanded(
                    child: memuatCari
                        ? const Center(child: CircularProgressIndicator())
                        : daftarHasil.isEmpty
                            ? const Center(
                                child: Text('Tidak ada produk yang cocok.'))
                            : ListView.separated(
                                itemCount: daftarHasil.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, idx) {
                                  final p = daftarHasil[idx];
                                  final id = (p['id'] as num?)?.toInt() ?? 0;
                                  final cek = terpilih.contains(id);
                                  final kode = '${p['kode'] ?? '-'}';
                                  final nama = '${p['nama'] ?? '-'}';
                                  final kat = '${p['kategoriNama'] ?? '-'}';
                                  final rakUtama =
                                      '${p['rakUtamaNama'] ?? 'RAK Utama'}';
                                  final stok = p['stok'] ?? 0;
                                  return CheckboxListTile(
                                    dense: true,
                                    value: cek,
                                    onChanged: (v) {
                                      setSt(() {
                                        if (v == true) {
                                          terpilih.add(id);
                                        } else {
                                          terpilih.remove(id);
                                        }
                                      });
                                    },
                                    title: Text(
                                      '$kode — $nama',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      'Kategori: $kat • RAK Utama: $rakUtama • Stok: $stok',
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                onPressed:
                    terpilih.isEmpty ? null : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('Masukkan ${terpilih.length} Produk ke Rak'),
              ),
            ],
          );
        },
      ),
    );

    cariCtrl.dispose();
    if (simpan != true || terpilih.isEmpty) return;

    try {
      Map<String, dynamic>? res;
      await _jalankanDenganProgress(
        judul:
            'Memasukkan ${terpilih.length} Produk ke Rak "$_rakTerpilihNama"',
        tugas: (update) async {
          update(0.35,
              'Menyimpan daftar produk ke rak & menyinkronkan RAK Utama...');
          if (pindahkanDariRakLain) {
            res = await ApiClient.instance.aksi('rak_produk_pindah', {
              if (_tokoIdAktif != null && _tokoIdAktif! > 0)
                'toko_id': _tokoIdAktif,
              'rak_tujuan_id': _rakTerpilihId,
              'produk_ids': terpilih.toList(),
              'pindahkan_stok': true,
              'hapus_dari_rak_asal': true,
              'jadikan_rak_utama': true,
            });
          } else {
            res = await ApiClient.instance.aksi('rak_produk_tambah', {
              if (_tokoIdAktif != null && _tokoIdAktif! > 0)
                'toko_id': _tokoIdAktif,
              'rak_id': _rakTerpilihId,
              'produk_ids': terpilih.toList(),
              if (jadikanRakUtama) 'jadikan_rak_utama': true,
            });
          }
          update(0.85, 'Memuat ulang daftar rak & produk...');
          await _muatDaftarRak();
        },
      );
      if (!mounted || res == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${res!['description'] ?? 'Produk berhasil dimasukkan ke rak.'}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memproses produk ke rak: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _hapusProdukDariRak(Map<String, dynamic> item) async {
    final rakId = (item['rakId'] as num?)?.toInt() ?? _rakTerpilihId;
    final produkId = (item['produkId'] as num?)?.toInt();
    final namaProduk = '${item['produkNama'] ?? item['nama'] ?? '-'}';
    if (rakId == null || rakId <= 0 || produkId == null) return;

    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluarkan Produk dari Rak?'),
        content: Text(
            'Apakah Anda yakin ingin mengeluarkan "$namaProduk" dari rak "$_rakTerpilihNama"?\n\nCatatan: Apabila produk ini tidak lagi berada di rak utamanya, sistem otomatis menyesuaikan RAK Utama ke rak aktif yang tersisa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (yakin != true) return;

    try {
      final res = await ApiClient.instance.aksi('rak_produk_hapus', {
        if (_tokoIdAktif != null && _tokoIdAktif! > 0) 'toko_id': _tokoIdAktif,
        'rak_id': rakId,
        'produk_id': produkId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${res['description'] ?? 'Produk dikeluarkan dari rak.'}'),
        ),
      );
      await _muatDaftarRak();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengeluarkan produk dari rak: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _bukaDialogFormRak({Map<String, dynamic>? awal}) async {
    final kodeCtrl = TextEditingController(text: '${awal?['kode'] ?? ''}');
    final namaCtrl = TextEditingController(text: '${awal?['nama'] ?? ''}');
    final lokasiCtrl = TextEditingController(text: '${awal?['lokasi'] ?? ''}');
    final ketCtrl = TextEditingController(text: '${awal?['keterangan'] ?? ''}');
    bool aktif = awal == null ? true : (awal['aktif'] != false);

    final simpan = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(awal == null ? 'Tambah Rak Baru' : 'Ubah Data Rak'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: kodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kode Rak *',
                    hintText: 'Contoh: RAK-A01, GONDOLA-1, ETALASE-DEPAN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: namaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Rak *',
                    hintText: 'Contoh: Rak Makanan Ringan A1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lokasiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lokasi / Lorong (Opsional)',
                    hintText: 'Contoh: Lorong Tengah Baris 2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ketCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (Opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rak Aktif'),
                  value: aktif,
                  onChanged: (v) => setSt(() => aktif = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton.icon(
              onPressed: () {
                if (kodeCtrl.text.trim().isEmpty &&
                    namaCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Kode Rak atau Nama Rak wajib diisi.')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Simpan Rak'),
            ),
          ],
        ),
      ),
    );

    if (simpan != true) return;

    await _jalankanDenganProgress(
      judul: awal == null ? 'Menyimpan Rak Baru' : 'Memperbarui Data Rak',
      tugas: (update) async {
        update(0.35, 'Mengirim data rak ke server...');
        final res = await ApiClient.instance.aksi('rak_simpan', {
          if (_tokoIdAktif != null && _tokoIdAktif! > 0)
            'toko_id': _tokoIdAktif,
          if (awal?['id'] != null) 'id': awal!['id'],
          'kode': kodeCtrl.text.trim(),
          'nama': namaCtrl.text.trim().isEmpty
              ? kodeCtrl.text.trim()
              : namaCtrl.text.trim(),
          'lokasi': lokasiCtrl.text.trim(),
          'keterangan': ketCtrl.text.trim(),
          'aktif': aktif,
        });
        update(0.80, 'Memuat ulang daftar rak...');
        final idBaru = (res['id'] as num?)?.toInt();
        if (idBaru != null && idBaru > 0) {
          _rakTerpilihId = idBaru;
        }
        await _muatDaftarRak();
      },
    );
  }

  Future<void> _hapusRak(Map<String, dynamic> rak) async {
    final id = (rak['id'] as num?)?.toInt();
    if (id == null || id <= 0) return;
    final nama = '${rak['nama'] ?? rak['kode'] ?? ''}';
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus / Nonaktifkan Rak?'),
        content: Text(
            'Apakah Anda yakin ingin menghapus rak "$nama"?\nJika rak sudah memiliki riwayat produk, rak akan dinonaktifkan secara aman.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yakin != true) return;

    try {
      final res = await ApiClient.instance.aksi('rak_hapus', {
        if (_tokoIdAktif != null && _tokoIdAktif! > 0) 'toko_id': _tokoIdAktif,
        'id': id,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${res['description'] ?? 'Rak dihapus.'}')),
      );
      if (_rakTerpilihId == id) {
        _rakTerpilihId = null;
      }
      await _muatDaftarRak();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal menghapus rak: $e'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _sinkronkanStokRakDanProduk() async {
    try {
      Map<String, dynamic>? hasil;
      await _jalankanDenganProgress(
        judul: 'Sinkronisasi Stok Per Rak & Total Produk',
        tugas: (update) async {
          update(0.25,
              'Menghitung ulang stok seluruh rak dan menyamakan dengan stok produk...');
          hasil = await ApiClient.instance.aksi('rak_sinkronkan_stok', {
            if (_tokoIdAktif != null && _tokoIdAktif! > 0)
              'toko_id': _tokoIdAktif,
          });
          update(0.75, 'Memuat ulang daftar rak & ringkasan persediaan...');
          await _muatDaftarRak();
        },
      );
      if (!mounted || hasil == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${hasil!['description'] ?? 'Sinkronisasi stok per rak dan total produk berhasil.'}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal menyinkronkan stok rak: $e'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _unduhExcelRak({bool hanyaRakTerpilih = false}) async {
    try {
      await _jalankanDenganProgress(
        judul: 'Mengunduh Excel Pemetaan Rak & Produk',
        tugas: (update) async {
          update(0.20, 'Menyiapkan data rak & produk di server...');
          final payload = <String, dynamic>{};
          if (_tokoIdAktif != null && _tokoIdAktif! > 0) {
            payload['toko_id'] = _tokoIdAktif;
          }
          if (hanyaRakTerpilih &&
              _rakTerpilihId != null &&
              _rakTerpilihId! > 0) {
            payload['rak_id'] = _rakTerpilihId;
          }
          final res =
              await ApiClient.instance.aksi('rak_download_excel', payload);
          update(0.65, 'Menerima berkas Excel, membuka dialog simpan...');
          final b64 = '${res['fileBase64'] ?? ''}';
          if (b64.isEmpty) {
            throw Exception(
                '${res['description'] ?? 'Data file Excel kosong.'}');
          }
          final bytes = base64Decode(b64);
          final namaDefault = '${res['namaFile'] ?? 'Master-Rak-Produk.xlsx'}';
          final savePath = await SimpanBerkasHelper.pilihLokasiSimpan(
            dialogTitle: 'Simpan Excel Rak Produk',
            fileName: namaDefault,
            allowedExtensions: ['xlsx'],
          );
          if (savePath != null && savePath.isNotEmpty) {
            update(0.90, 'Menulis berkas ke penyimpanan perangkat...');
            final pathFinal = savePath.toLowerCase().endsWith('.xlsx')
                ? savePath
                : '$savePath.xlsx';
            await File(pathFinal).writeAsBytes(bytes, flush: true);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('File Excel berhasil disimpan ke: $pathFinal'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal mengunduh Excel Rak: $e'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _unggahExcelRak() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih File Excel Pemetaan Rak Produk (.xlsx)',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) return;

    try {
      Map<String, dynamic>? res;
      await _jalankanDenganProgress(
        judul: 'Mengunggah Excel Pemetaan Rak Produk',
        tugas: (update) async {
          update(0.25, 'Mengodekan berkas "${file.name}"...');
          final b64 = base64Encode(bytes);
          update(0.55,
              'Memproses pemetaan rak & produk di server (stok tetap dijaga lewat Stok Opname)...');
          res = await ApiClient.instance.aksi('rak_upload_excel', {
            if (_tokoIdAktif != null && _tokoIdAktif! > 0)
              'toko_id': _tokoIdAktif,
            'file_base64': b64,
          });
          update(0.85, 'Memuat ulang daftar rak & produk...');
          await _muatDaftarRak();
        },
      );
      if (!mounted || res == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${res!['description'] ?? 'Pemetaan produk ke rak berhasil diimpor.'}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal mengunggah Excel Rak: $e'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _muatDataRakStandarToko() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Muat Data Rak & Produk Standar Toko'),
        content: const Text(
          'Apakah Anda ingin memuat master rak beserta pemetaan produk standar toko (RAK DEPAN A03, RAK SAMPING KIRI/KANAN/BELAKANG A03, FLOOR C01, RAK SINGLE B01-B03, RAK COOLER B04, SHOWCASE CASHIER D01)?\n\n'
          'Proses ini aman (idempoten): hanya menambahkan rak/produk yang belum terdaftar dan menjaga RAK Utama setiap produk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: const Text('Muat Sekarang'),
          ),
        ],
      ),
    );
    if (konfirmasi != true) return;

    try {
      Map<String, dynamic>? res;
      await _jalankanDenganProgress(
        judul: 'Memuat Data Rak & Produk Standar Toko',
        tugas: (update) async {
          update(
              0.30, 'Memproses pemetaan 10 rak standar & produk di server...');
          res = await ApiClient.instance.aksi('rak_seed_standar', {
            if (_tokoIdAktif != null && _tokoIdAktif! > 0)
              'toko_id': _tokoIdAktif,
            'paksa_impor': true,
          });
          update(0.85, 'Memuat ulang daftar rak & produk...');
          await _muatDaftarRak();
        },
      );
      if (!mounted || res == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${res!['description'] ?? 'Data rak standar berhasil dimuat.'}',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat data rak standar: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _bukaStokOpname() {
    bukaMenuEBisnis(context, MenuEBisnis.stokOpname);
  }

  @override
  Widget build(BuildContext context) {
    final totalRak = (_ringkasan['totalRak'] as num?)?.toInt() ??
        _daftarRak.where((r) => ((r['id'] as num?)?.toInt() ?? 0) > 0).length;
    final produkTerpetakan = (_ringkasan['totalProdukTerpetakan'] as num?)
            ?.toInt() ??
        (_ringkasan['totalItemRak'] as num?)?.toInt() ??
        _daftarRak
            .where((r) => ((r['id'] as num?)?.toInt() ?? 0) > 0)
            .fold<int>(0,
                (sum, r) => sum + ((r['jumlahProduk'] as num?)?.toInt() ?? 0));
    final produkBelumBerRak =
        (_ringkasan['totalProdukBelumBerRak'] as num?)?.toInt() ??
            (_ringkasan['produkBelumAdaRak'] as num?)?.toInt() ??
            0;
    final stokSemuaRak = (_ringkasan['totalStokSemuaRak'] as num?)
            ?.toDouble() ??
        (_ringkasan['totalStokTerpetakan'] as num?)?.toDouble() ??
        _daftarRak
            .where((r) => ((r['id'] as num?)?.toInt() ?? 0) > 0)
            .fold<double>(0,
                (sum, r) => sum + ((r['totalStok'] as num?)?.toDouble() ?? 0));
    final stokTotalProduk =
        (_ringkasan['totalStokProdukToko'] as num?)?.toDouble() ??
            (_ringkasan['totalStokToko'] as num?)?.toDouble() ??
            stokSemuaRak;
    final sinkron = (stokSemuaRak - stokTotalProduk).abs() < 0.009;

    return AppShell(
      menuAktif: MenuEBisnis.rakProduk,
      judul: 'Manajemen Rak Produk',
      subjudul:
          'Kelola master rak toko, petakan produk ke rak (via Banbox, AmbilDataBanyak, atau Excel), dan sinkronkan stok per rak dengan Stok Opname',
      aksiHeader: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _muatDaftarRak(tampilkanProgress: true),
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Muat Ulang'),
          ),
          OutlinedButton.icon(
            onPressed: _sinkronkanStokRakDanProduk,
            icon: const Icon(Icons.sync, size: 17),
            label: const Text('Sinkronkan Stok Rak & Produk'),
          ),
          OutlinedButton.icon(
            onPressed: () => _unduhExcelRak(hanyaRakTerpilih: false),
            icon: const Icon(Icons.download_outlined, size: 17),
            label: const Text('Download Excel Rak'),
          ),
          OutlinedButton.icon(
            onPressed: _unggahExcelRak,
            icon: const Icon(Icons.upload_file_outlined, size: 17),
            label: const Text('Upload Excel Rak'),
          ),
          OutlinedButton.icon(
            onPressed: _muatDataRakStandarToko,
            icon: const Icon(Icons.playlist_add_check, size: 17),
            label: const Text('Muat Data Rak Standar'),
          ),
          FilledButton.icon(
            onPressed: () => _bukaDialogFormRak(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah Rak Baru'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: Color(0xFF047857), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Aturan Manajemen Rak, RAK Utama (Default Penjualan), & Sinkronisasi Stok Opname Per Rak',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '1. Saat startup, setiap toko memiliki default "RAK Utama" (RAK-UTAMA). Ketika penjualan terjadi di kasir, stok rak yang dikurangi otomatis berasal dari RAK Utama produk tersebut.\n'
                        '2. Di setiap Rak dapat dimasukkan produk via Banbox, Ambil Data Banyak (seperti ZKoss), pindah antar-rak, atau Download & Upload Excel. Ketika produk dipindahkan dan tidak ada rak lain yang menampungnya, RAK Utama produk otomatis ikut berubah.\n'
                        '3. Jumlah stok fisik barang di dalam rak wajib dientri melalui menu Stok Opname (SO Grand, SO by Scan, SO Harian, atau Input Opname) dengan memilih Rak-nya terlebih dahulu.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF064E3B),
                            height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: _bukaStokOpname,
                  icon: const Icon(Icons.fact_check_outlined, size: 17),
                  label: const Text('Buka Stok Opname'),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kartuKpiRak(
                judul: 'Total Master Rak Aktif',
                nilai: '$totalRak Rak',
                sub: 'Klik untuk rincian daftar rak',
                ikon: Icons.shelves,
                warna: AppColors.primary,
                onTap: () => _tampilkanPopupDaftarRak(),
              ),
              _kartuKpiRak(
                judul: 'Produk Sudah Ber-Rak',
                nilai: '${_fmtAngka.format(produkTerpetakan)} Produk',
                sub: 'Sudah ditempatkan di rak toko',
                ikon: Icons.check_circle_outline,
                warna: AppColors.success,
                onTap: () => _tampilkanPopupProdukSaatIni(
                    'Produk di Rak $_rakTerpilihNama'),
              ),
              _kartuKpiRak(
                judul: 'Rak Belum Ditentukan',
                nilai: '${_fmtAngka.format(produkBelumBerRak)} Produk',
                sub: 'Klik untuk melihat & memetakan',
                ikon: Icons.warning_amber_rounded,
                warna: Colors.orange.shade800,
                onTap: () {
                  setStateIfMounted(() {
                    _rakTerpilihId = -1;
                    _rakTerpilihKode = 'UNASSIGNED';
                    _rakTerpilihNama = 'Rak Belum Ditentukan';
                  });
                  _muatProdukDiRak(-1);
                },
              ),
              _kartuKpiRak(
                judul: 'Sinkronisasi Stok Rak vs Total',
                nilai:
                    '${_fmtAngka.format(stokSemuaRak)} / ${_fmtAngka.format(stokTotalProduk)}',
                sub: sinkron
                    ? '100% Sinkron (Stok Rak = Total Produk)'
                    : 'Klik untuk sinkronisasi otomatis',
                ikon: sinkron ? Icons.verified_outlined : Icons.sync_problem,
                warna: sinkron ? const Color(0xFF047857) : AppColors.danger,
                onTap: _sinkronkanStokRakDanProduk,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.danger)),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final lebar = constraints.maxWidth >= 920;
              final panelKiri = _bangunPanelDaftarRak();
              final panelKanan = _bangunPanelProdukRak();
              if (lebar) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 360, child: panelKiri),
                    const SizedBox(width: 16),
                    Expanded(child: panelKanan),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  panelKiri,
                  const SizedBox(height: 16),
                  panelKanan,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _kartuKpiRak({
    required String judul,
    required String nilai,
    required String sub,
    required IconData ikon,
    required Color warna,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 255,
      child: Material(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: warna.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(ikon, color: warna, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        judul,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nilai,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: warna,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new,
                    size: 14, color: warna.withValues(alpha: 0.65)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bangunPanelDaftarRak() {
    final adaVirtual =
        _daftarRak.any((r) => ((r['id'] as num?)?.toInt() ?? 0) == -1);
    final belumBerRakCount =
        (_ringkasan['totalProdukBelumBerRak'] as num?)?.toInt() ?? 0;
    final stokBelumBerRak =
        (_ringkasan['totalStokBelumBerRak'] as num?)?.toDouble() ?? 0;

    final semuaItemRak = <Map<String, dynamic>>[
      ..._daftarRak,
      if (!adaVirtual)
        {
          'id': -1,
          'kode': 'BELUM-DIATUR',
          'nama': 'Rak Belum Ditentukan',
          'lokasi': 'Produk yang belum dipetakan ke rak',
          'jumlahProduk': belumBerRakCount,
          'totalStok': stokBelumBerRak,
          'aktif': true,
        },
    ];

    return AppSectionCard(
      judul: 'Daftar Rak Toko (${_daftarRak.length})',
      aksiJudul: IconButton(
        tooltip: 'Tambah Rak Baru',
        onPressed: () => _bukaDialogFormRak(),
        icon: Icon(Icons.add_circle_outline, color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _cariRakCtrl,
            decoration: InputDecoration(
              hintText: 'Cari kode / nama rak...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              suffixIcon: _cariRakCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _cariRakCtrl.clear();
                        _muatDaftarRak();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: (_) => _muatDaftarRak(),
          ),
          const SizedBox(height: 10),
          if (_memuat)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 540),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: semuaItemRak.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (ctx, idx) {
                  final r = semuaItemRak[idx];
                  final id = (r['id'] as num?)?.toInt() ?? 0;
                  final terpilih = _rakTerpilihId == id;
                  final kode = '${r['kode'] ?? ''}'.trim();
                  final nama = '${r['nama'] ?? ''}'.trim();
                  final lokasi = '${r['lokasi'] ?? ''}'.trim();
                  final jmlProduk = (r['jumlahProduk'] as num?)?.toInt() ?? 0;
                  final totStok = (r['totalStok'] as num?)?.toDouble() ?? 0;
                  final isUnassigned = id == -1;

                  return Material(
                    color: terpilih
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : AppColors.cardBgOf(context),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setStateIfMounted(() {
                          _rakTerpilihId = id;
                          _rakTerpilihNama = nama;
                          _rakTerpilihKode = kode;
                          _halamanProdukRak = 1;
                          _produkTerpilihIds.clear();
                        });
                        _muatProdukDiRak(id, halaman: 1, hapusPilihan: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: terpilih
                                ? AppColors.primary
                                : (isUnassigned
                                    ? Colors.orange.withValues(alpha: 0.5)
                                    : AppColors.borderOf(context)),
                            width: terpilih ? 1.6 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isUnassigned ? Icons.help_outline : Icons.shelves,
                              size: 20,
                              color: isUnassigned
                                  ? Colors.orange.shade800
                                  : (terpilih
                                      ? AppColors.primary
                                      : AppColors.textSecondaryOf(context)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isUnassigned
                                        ? 'Rak Belum Ditentukan'
                                        : (kode.isEmpty
                                            ? nama
                                            : '$kode — $nama'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isUnassigned
                                          ? Colors.orange.shade900
                                          : AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                  if (lokasi.isNotEmpty)
                                    Text(
                                      lokasi,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppColors.textSecondaryOf(context),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      _chipKecil(
                                        '$jmlProduk Produk',
                                        AppColors.primary,
                                      ),
                                      _chipKecil(
                                        'Stok: ${_fmtAngka.format(totStok)}',
                                        const Color(0xFF047857),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!isUnassigned)
                              AksiBarisMenu(
                                aksi: [
                                  AksiBaris(
                                    ikon: Icons.edit_outlined,
                                    label: 'Ubah Rak',
                                    onTap: () => _bukaDialogFormRak(awal: r),
                                  ),
                                  AksiBaris(
                                    ikon: Icons.download_outlined,
                                    label: 'Download Excel Rak Ini',
                                    onTap: () {
                                      setStateIfMounted(() {
                                        _rakTerpilihId = id;
                                        _rakTerpilihNama = nama;
                                        _rakTerpilihKode = kode;
                                      });
                                      _unduhExcelRak(hanyaRakTerpilih: true);
                                    },
                                  ),
                                  AksiBaris(
                                    ikon: Icons.delete_outline,
                                    label: 'Hapus Rak',
                                    merusak: true,
                                    onTap: () => _hapusRak(r),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _bangunPanelProdukRak() {
    final isUnassigned = _rakTerpilihId == -1;
    final judulRak = _rakTerpilihId == null
        ? 'Pilih Rak di Sebelah Kiri'
        : (isUnassigned
            ? 'Produk dengan "Rak Belum Ditentukan"'
            : 'Daftar Produk di Rak: ${_rakTerpilihKode.isEmpty ? _rakTerpilihNama : '$_rakTerpilihKode — $_rakTerpilihNama'}');

    return AppSectionCard(
      judul: judulRak,
      aksiJudul: Wrap(
        spacing: 8,
        children: [
          if (_rakTerpilihId != null && _rakTerpilihId! > 0)
            OutlinedButton.icon(
              onPressed: () => _unduhExcelRak(hanyaRakTerpilih: true),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Excel Rak Ini'),
            ),
          FilledButton.tonalIcon(
            onPressed: _bukaStokOpname,
            icon: const Icon(Icons.fact_check_outlined, size: 16),
            label: const Text('Entri Jumlah Stok via Opname'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rakTerpilihId != null && _rakTerpilihId! > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.add_box_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ambil Data Produk ke Rak "$_rakTerpilihNama" (Banbox Cari Nama / Kode / Barcode)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: PencarianProdukBanbox(
                          controller: _banboxProdukCtrl,
                          label:
                              'Ketik nama / kode / barcode produk lalu pilih dari daftar untuk memasukkan ke rak ini...',
                          icon: Icons.inventory_2_outlined,
                          onPilih: _tambahProdukKeRakDariBanbox,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _tambahProdukKeRakDariBanbox(
                            _banboxProdukCtrl.text),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Masukkan ke Rak'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _bukaDialogAmbilDataBanyakProduk,
                        icon: const Icon(Icons.playlist_add_check_rounded,
                            size: 18),
                        label: const Text('Ambil Data Banyak'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cariProdukRakCtrl,
                  decoration: InputDecoration(
                    hintText: 'Saring produk di dalam rak ini...',
                    prefixIcon: const Icon(Icons.filter_list, size: 18),
                    isDense: true,
                    suffixIcon: _cariProdukRakCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _cariProdukRakCtrl.clear();
                              if (_rakTerpilihId != null) {
                                _halamanProdukRak = 1;
                                _muatProdukDiRak(_rakTerpilihId!,
                                    halaman: 1, hapusPilihan: true);
                              }
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (_rakTerpilihId != null) {
                      _halamanProdukRak = 1;
                      _muatProdukDiRak(_rakTerpilihId!,
                          halaman: 1, hapusPilihan: true);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_produkTerpilihIds.isNotEmpty) ...[
                FilledButton.tonalIcon(
                  onPressed: () => _bukaDialogPindahkanKeRakLain(),
                  icon: const Icon(Icons.drive_file_move_outlined, size: 17),
                  label: Text(
                      'Pindahkan (${_produkTerpilihIds.length}) ke Rak Lain'),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => _tampilkanPopupProdukSaatIni(judulRak),
                icon: const Icon(Icons.table_view_outlined, size: 17),
                label: Text('Rincian Halaman Ini (${_produkDiRak.length})'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_memuatProdukRak)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_produkDiRak.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              child: Text(
                isUnassigned
                    ? 'Seluruh produk aktif sudah memiliki rak yang ditentukan.'
                    : 'Belum ada produk yang dimasukkan ke rak ini. Gunakan kotak Banbox / Ambil Data Banyak di atas atau Upload Excel untuk menambahkan produk.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryOf(context)),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: AppPagedDataTable(
                    headingRowColor: WidgetStatePropertyAll(
                        Colors.grey.withValues(alpha: 0.08)),
                    columns: const [
                      DataColumn(label: Text('KODE / BARCODE')),
                      DataColumn(label: Text('NAMA PRODUK')),
                      DataColumn(label: Text('KATEGORI')),
                      DataColumn(label: Text('RAK & STATUS UTAMA')),
                      DataColumn(numeric: true, label: Text('STOK DI RAK INI')),
                      DataColumn(
                          numeric: true, label: Text('STOK TOTAL PRODUK')),
                      DataColumn(label: Text('AKSI')),
                    ],
                    rows: _produkDiRak.map((p) {
                      final produkId =
                          ((p['produkId'] ?? p['id']) as num?)?.toInt() ?? 0;
                      final isRakUtama = p['utama'] == true ||
                          ((p['rakUtamaId'] as num?)?.toInt() != null &&
                              (p['rakUtamaId'] as num?)?.toInt() ==
                                  _rakTerpilihId);
                      final rakUtamaNama =
                          '${p['rakUtamaNama'] ?? 'RAK Utama'}';
                      final kode = '${p['produkKode'] ?? p['kode'] ?? '-'}';
                      final barcode = '${p['barcode'] ?? ''}';
                      final nama = '${p['produkNama'] ?? p['nama'] ?? '-'}';
                      final kat = '${p['kategori'] ?? '-'}';
                      final rakNama =
                          '${p['rakNama'] ?? (_rakTerpilihNama.isEmpty ? 'Rak Belum Ditentukan' : _rakTerpilihNama)}';
                      final stokRak = (p['stokRak'] ?? p['stok'] ?? 0) is num
                          ? ((p['stokRak'] ?? p['stok'] ?? 0) as num).toDouble()
                          : 0.0;
                      final stokTotal = (p['stokTotalProduk'] ??
                              p['stokTotal'] ??
                              stokRak) is num
                          ? ((p['stokTotalProduk'] ?? p['stokTotal'] ?? stokRak)
                                  as num)
                              .toDouble()
                          : stokRak;
                      return DataRow(
                        selected: produkId > 0 &&
                            _produkTerpilihIds.contains(produkId),
                        onSelectChanged: produkId <= 0
                            ? null
                            : (v) {
                                setStateIfMounted(() {
                                  if (v == true) {
                                    _produkTerpilihIds.add(produkId);
                                  } else {
                                    _produkTerpilihIds.remove(produkId);
                                  }
                                });
                              },
                        cells: [
                          DataCell(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(kode,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                              if (barcode.isNotEmpty && barcode != kode)
                                Text(barcode,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondaryOf(
                                            context))),
                            ],
                          )),
                          DataCell(ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(nama,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          )),
                          DataCell(
                              Text(kat, style: const TextStyle(fontSize: 12))),
                          DataCell(Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _chipKecil(
                                rakNama,
                                rakNama == 'Rak Belum Ditentukan'
                                    ? Colors.orange.shade800
                                    : const Color(0xFF047857),
                              ),
                              if (isRakUtama)
                                _chipKecil('RAK Utama', AppColors.primary)
                              else if (rakUtamaNama.isNotEmpty)
                                _chipKecil(
                                    'Utama: $rakUtamaNama', Colors.blueGrey),
                            ],
                          )),
                          DataCell(
                            InkWell(
                              onTap: _bukaStokOpname,
                              child: Text(
                                _fmtAngka.format(stokRak),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(
                            _fmtAngka.format(stokTotal),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )),
                          DataCell(
                            AksiBarisMenu(
                              aksi: [
                                AksiBaris(
                                  ikon: Icons.fact_check_outlined,
                                  label:
                                      'Ubah jumlah stok di rak melalui Stok Opname',
                                  onTap: _bukaStokOpname,
                                ),
                                if (!isUnassigned && !isRakUtama)
                                  AksiBaris(
                                    ikon: Icons.star_outline_rounded,
                                    label:
                                        'Jadikan Rak Ini sebagai RAK Utama Produk',
                                    onTap: () => _jadikanRakUtamaProduk(p),
                                  ),
                                if (produkId > 0)
                                  AksiBaris(
                                    ikon: Icons.drive_file_move_outlined,
                                    label:
                                        'Pindahkan produk ke rak lain (otomatis sesuaikan RAK Utama)',
                                    onTap: () => _bukaDialogPindahkanKeRakLain(
                                      daftarProdukId: [produkId],
                                      labelProduk: '$kode — $nama',
                                    ),
                                  ),
                                if (!isUnassigned)
                                  AksiBaris(
                                    ikon: Icons.remove_circle_outline,
                                    label: 'Keluarkan produk dari rak ini',
                                    merusak: true,
                                    onTap: () => _hapusProdukDariRak(p),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _totalProdukRak == 0
                              ? '0 produk'
                              : '${((_halamanProdukRak - 1) * _pageSizeProdukRak) + 1}–${((_halamanProdukRak - 1) * _pageSizeProdukRak + _produkDiRak.length)} dari $_totalProdukRak produk • Stok ${_fmtAngka.format(_totalStokProdukRak)} • Nilai ${_fmtRupiah.format(_totalNilaiProdukRak)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Halaman sebelumnya',
                        onPressed: _halamanProdukRak <= 1 || _memuatProdukRak
                            ? null
                            : () => _muatProdukDiRak(_rakTerpilihId!,
                                halaman: _halamanProdukRak - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        'Halaman $_halamanProdukRak / ${((_totalProdukRak / _pageSizeProdukRak).ceil()).clamp(1, 1 << 30)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        tooltip: 'Halaman berikutnya',
                        onPressed: _halamanProdukRak * _pageSizeProdukRak >=
                                    _totalProdukRak ||
                                _memuatProdukRak
                            ? null
                            : () => _muatProdukDiRak(_rakTerpilihId!,
                                halaman: _halamanProdukRak + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chipKecil(String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: warna,
        ),
      ),
    );
  }

  void _tampilkanPopupDaftarRak() {
    tampilkanRincianKlikDialog(
      context,
      judul: 'Rincian Master Rak Toko',
      subjudul: Sesi.instance.tokoNama,
      kolom: const [
        'Kode Rak',
        'Nama Rak',
        'Lokasi / Lorong',
        'Jumlah Produk',
        'Total Stok di Rak',
        'Status',
      ],
      baris: _daftarRak
          .map((r) => [
                '${r['kode'] ?? '-'}',
                '${r['nama'] ?? '-'}',
                '${r['lokasi'] ?? '-'}',
                _fmtAngka.format((r['jumlahProduk'] as num?) ?? 0),
                _fmtAngka.format((r['totalStok'] as num?) ?? 0),
                r['aktif'] == false ? 'Nonaktif' : 'Aktif',
              ])
          .toList(),
    );
  }

  void _tampilkanPopupProdukSaatIni(String judul) {
    tampilkanRincianKlikDialog(
      context,
      judul: judul,
      subjudul:
          '${Sesi.instance.tokoNama} • ${_produkDiRak.length} produk pada halaman $_halamanProdukRak dari $_totalProdukRak',
      kolom: const [
        'Kode Produk',
        'Barcode',
        'Nama Produk',
        'Kategori',
        'Rak',
        'RAK Utama',
        'Stok di Rak',
        'Stok Total Produk',
        'Harga Jual',
      ],
      baris: _produkDiRak
          .map((p) => [
                '${p['produkKode'] ?? p['kode'] ?? '-'}',
                '${p['barcode'] ?? '-'}',
                '${p['produkNama'] ?? p['nama'] ?? '-'}',
                '${p['kategori'] ?? '-'}',
                '${p['rakNama'] ?? (_rakTerpilihNama.isEmpty ? 'Rak Belum Ditentukan' : _rakTerpilihNama)}',
                '${p['rakUtamaNama'] ?? 'RAK Utama'}',
                _fmtAngka.format((p['stokRak'] ?? p['stok'] ?? 0) as num),
                _fmtAngka.format(
                    (p['stokTotalProduk'] ?? p['stokTotal'] ?? 0) as num),
                _fmtRupiah.format((p['hargaJual'] ?? 0) as num),
              ])
          .toList(),
    );
  }
}
