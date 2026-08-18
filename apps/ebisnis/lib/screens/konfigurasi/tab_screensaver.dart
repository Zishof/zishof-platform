import 'dart:convert';
import 'dart:io';

import 'package:core_device/core_device.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/safe_state.dart';

const _opsiMode = [
  ('FULLSCREEN', 'Layar Penuh', Icons.fullscreen),
  ('SETENGAH', 'Setengah Layar', Icons.splitscreen_outlined),
];

const _opsiAnimasi = [
  ('FADE', 'Fade (memudar)', Icons.blur_on),
  ('SLIDE', 'Slide (geser)', Icons.swipe),
  ('ZOOM', 'Zoom (membesar)', Icons.zoom_in),
  ('KEN_BURNS', 'Ken Burns (bergerak lambat)', Icons.camera_outdoor_outlined),
];

/// Tab "Screensaver" di Konfigurasi -- slideshow gambar yg tampil di Layar
/// Pelanggan (jendela kedua) saat idle berkepanjangan (padanan screensaver),
/// gap-closure fitur baru diminta user. Server: `layar_pelanggan_slide_*`
/// (daftar gambar, DB streaming -- lihat JavaDoc entity) + `layar_pelanggan_
/// screensaver_config_*` (pengaturan tampilan, satu baris per toko).
///
/// Lingkup gambar: setiap gambar bisa "berlaku semua mesin toko ini" (default)
/// ATAU "khusus mesin ini" (id_mesin = IdentitasMesin.instance.idMesin) --
/// dipilih SAAT unggah lewat toggle di [_bukaDialogUnggah].
class TabScreensaver extends StatefulWidget {
  const TabScreensaver({super.key});
  @override
  State<TabScreensaver> createState() => _TabScreensaverState();
}

class _TabScreensaverState extends State<TabScreensaver> {
  bool _memuat = true;
  String? _error;
  bool _menyimpanPengaturan = false;

  bool _aktif = false;
  String _mode = 'FULLSCREEN';
  String _animasi = 'FADE';
  final _durasiController = TextEditingController(text: '6');
  final _idleController = TextEditingController(text: '30');

  List<Map<String, dynamic>> _slide = [];

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  @override
  void dispose() {
    _durasiController.dispose();
    _idleController.dispose();
    super.dispose();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      await Future.wait([_muatPengaturan(), _muatSlide()]);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatPengaturan() async {
    final hasil = await ApiClient.instance.aksi('layar_pelanggan_screensaver_config_ambil',
        {'toko_id': Sesi.instance.tokoId});
    final cfg = hasil['data'] as Map?;
    if (cfg == null) return;
    setStateIfMounted(() {
      _aktif = cfg['aktif'] == true;
      _mode = (cfg['modeTampilan'] as String?) ?? 'FULLSCREEN';
      _animasi = (cfg['animasi'] as String?) ?? 'FADE';
      _durasiController.text = '${cfg['durasiDetik'] ?? 6}';
      _idleController.text = '${cfg['idleDetik'] ?? 30}';
    });
  }

  Future<void> _muatSlide() async {
    final hasil = await ApiClient.instance.aksi('layar_pelanggan_slide_list',
        {'toko_id': Sesi.instance.tokoId});
    setStateIfMounted(() {
      _slide = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    });
  }

  Future<void> _simpanPengaturan() async {
    setStateIfMounted(() => _menyimpanPengaturan = true);
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(context,
          aksi: 'layar_pelanggan_screensaver_config_simpan',
          body: {
            'toko_id': Sesi.instance.tokoId,
            'aktif': _aktif,
            'mode_tampilan': _mode,
            'animasi': _animasi,
            'durasi_detik': int.tryParse(_durasiController.text.trim()) ?? 6,
            'idle_detik': int.tryParse(_idleController.text.trim()) ?? 30,
          },
          kunci: 'screensaver:${Sesi.instance.tokoId}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpanPengaturan = false);
    }
  }

  Future<void> _hapusSlide(Map<String, dynamic> s) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Gambar?'),
        content: const Text('Gambar ini akan dihapus dari screensaver.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      await prosesSimpanMaster(context,
          aksi: 'layar_pelanggan_slide_hapus',
          body: {'id': s['id']},
          kunci: 'screensaver_slide:${s['id']}');
      setStateIfMounted(() => _slide.removeWhere((x) => x['id'] == s['id']));
      if (mounted) {
        try {
          await _muatSlide();
        } on ApiException catch (e) {
          if (!e.offline) rethrow; // offline: daftar lokal sudah dimutakhirkan.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menghapus: $e')));
      }
    }
  }

  Future<void> _toggleAktifSlide(Map<String, dynamic> s, bool aktif) async {
    setStateIfMounted(() => s['aktif'] = aktif);
    try {
      await prosesSimpanMaster(context,
          aksi: 'layar_pelanggan_slide_ubah',
          body: {'id': s['id'], 'aktif': aktif},
          kunci: 'screensaver_slide:${s['id']}');
    } catch (e) {
      setStateIfMounted(() => s['aktif'] = !aktif);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengubah: $e')));
      }
    }
  }

  Future<void> _bukaDialogUnggah() async {
    final hasilPicker = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: false,
    );
    if (hasilPicker == null || hasilPicker.files.isEmpty) return;
    if (!mounted) return;

    bool khususMesinIni = false;
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text('Unggah ${hasilPicker.files.length} Gambar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gambar akan ditambahkan ke urutan screensaver toko ini.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context))),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Khusus mesin POS ini', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                    khususMesinIni
                        ? 'Hanya tampil di mesin ini.'
                        : 'Tampil di SEMUA mesin POS toko ini.',
                    style: const TextStyle(fontSize: 11)),
                value: khususMesinIni,
                onChanged: (v) => setDlg(() => khususMesinIni = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unggah')),
          ],
        ),
      ),
    );
    if (lanjut != true) return;

    final progress = ValueNotifier<String>('Mengunggah 0/${hasilPicker.files.length}...');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (context, teks, __) => Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 16),
              Expanded(child: Text(teks)),
            ],
          ),
        ),
      ),
    );

    int berhasil = 0, gagal = 0;
    for (var i = 0; i < hasilPicker.files.length; i++) {
      final f = hasilPicker.files[i];
      progress.value = 'Mengunggah ${i + 1}/${hasilPicker.files.length}...';
      try {
        final path = f.path;
        if (path == null) {
          gagal++;
          continue;
        }
        final bytes = await File(path).readAsBytes();
        await ApiClient.instance.aksi('layar_pelanggan_slide_upload', {
          'toko_id': Sesi.instance.tokoId,
          'gambar_base64': base64Encode(bytes),
          'nama_file': f.name,
          'id_mesin': khususMesinIni ? IdentitasMesin.instance.idMesin : '',
        });
        berhasil++;
      } catch (_) {
        gagal++;
      }
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unggah selesai: $berhasil berhasil${gagal > 0 ? ', $gagal gagal' : ''}.')));
      await _muatSlide();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _muatSemua, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muatSemua,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionCard(
            judul: 'Screensaver Layar Pelanggan',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tampilkan slideshow gambar promosi di jendela Layar Pelanggan (jendela kedua) saat kasir tidak sedang bertransaksi -- seperti screensaver.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 14),
                AppFormSwitchTile(
                  title: 'Aktifkan Screensaver',
                  value: _aktif,
                  onChanged: (v) => setStateIfMounted(() => _aktif = v),
                ),
                const SizedBox(height: 4),
                Text('Mode Tampilan',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: _opsiMode
                      .map((o) => ButtonSegment(value: o.$1, label: Text(o.$2), icon: Icon(o.$3, size: 16)))
                      .toList(),
                  selected: {_mode},
                  onSelectionChanged: (v) => setStateIfMounted(() => _mode = v.first),
                ),
                const SizedBox(height: 14),
                Text('Animasi Transisi',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _opsiAnimasi.map((o) {
                    final terpilih = _animasi == o.$1;
                    return ChoiceChip(
                      label: Text(o.$2),
                      avatar: Icon(o.$3, size: 16, color: terpilih ? Colors.white : null),
                      selected: terpilih,
                      onSelected: (_) => setStateIfMounted(() => _animasi = o.$1),
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(color: terpilih ? Colors.white : null, fontSize: 12.5),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppFormTextField(
                        label: 'Durasi per Gambar (detik)',
                        controller: _durasiController,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppFormTextField(
                        label: 'Aktif Setelah Idle (detik)',
                        controller: _idleController,
                        keyboardType: TextInputType.number,
                        helperText: 'Tanpa transaksi selama ini, screensaver menyala.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _menyimpanPengaturan ? null : _simpanPengaturan,
                    icon: _menyimpanPengaturan
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Simpan Pengaturan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            judul: 'Kelola Gambar (${_slide.length})',
            aksiJudul: TextButton.icon(
              onPressed: _bukaDialogUnggah,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Tambah Gambar'),
            ),
            child: _slide.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Belum ada gambar. Klik "Tambah Gambar" untuk mulai.',
                          style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 13)),
                    ),
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _slide.map((s) {
                      final aktif = s['aktif'] == true;
                      final khususMesin = (s['idMesin'] as String?)?.isNotEmpty == true;
                      return Container(
                        width: 168,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.borderOf(context)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 10,
                                  child: s['urlGambar'] != null
                                      ? Image.network('${s['urlGambar']}', fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                              color: AppColors.pageBgOf(context),
                                              child: const Icon(Icons.broken_image_outlined)))
                                      : Container(color: AppColors.pageBgOf(context)),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Material(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(20),
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
                                      onPressed: () => _hapusSlide(s),
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                if (khususMesin)
                                  Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(6)),
                                      child: const Text('Mesin ini',
                                          style: TextStyle(color: Colors.white, fontSize: 10)),
                                    ),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(aktif ? 'Aktif' : 'Nonaktif',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: aktif ? AppColors.success : AppColors.textSecondaryOf(context))),
                                  Transform.scale(
                                    scale: 0.75,
                                    child: Switch(
                                      value: aktif,
                                      onChanged: (v) => _toggleAktifSlide(s, v),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          if (!Sesi.instance.isAdmin) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Gambar & pengaturan berlaku untuk toko Anda saat ini.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(context))),
            ),
          ],
        ],
      ),
    );
  }
}
