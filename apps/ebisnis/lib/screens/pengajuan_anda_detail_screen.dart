import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../services/unggah_lampiran_sop.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import 'pengadaan_cetak_util.dart';

/// Detail satu pengajuan SOP beserta **alur disposisinya** -- padanan
/// `TampilanAlurSopAction.java` versi ZKoss, dijalankan sepenuhnya lewat API
/// (`sop_detail`, `sop_proses`, `sop_batalkan_pengajuan`, `sop_batalkan_langkah`,
/// `sop_cetak`). Tidak ada webview maupun iframe.
///
/// Yang ditampilkan mengikuti apa yang dikirim server, satu per satu:
/// header pengajuan, spanduk status selesai, tahap yang sedang MENUNGGU (berikut
/// siapa yang berhak dan apakah pengguna saat ini berhak), riwayat langkah yang
/// sudah diambil, data form terkait (hanya-baca), dan peta seluruh tahap desain
/// SOP dengan status masing-masing.
///
/// Tindakan menulis (memproses tahap, membatalkan) sengaja TIDAK diantrekan
/// offline. Berbeda dengan CRUD master, persetujuan alur bergantung pada
/// keadaan tahap dan hak akses SAAT ITU JUGA: bila diputar ulang belakangan,
/// tahapnya bisa sudah diambil orang lain sehingga kiriman gagal diam-diam
/// padahal pengguna merasa sudah menyetujui. Karena itu tindakan di sini hanya
/// berjalan saat daring, dan hasilnya selalu dari server.
class PengajuanAndaDetailScreen extends StatefulWidget {
  final String disposisiSopId;
  const PengajuanAndaDetailScreen({super.key, required this.disposisiSopId});

  @override
  State<PengajuanAndaDetailScreen> createState() =>
      _PengajuanAndaDetailScreenState();
}

class _PengajuanAndaDetailScreenState extends State<PengajuanAndaDetailScreen> {
  bool _memuat = true;
  String? _galat;
  Map<String, dynamic> _d = const {};
  bool _sibuk = false;

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
          .aksi('sop_detail', {'disposisiSopId': widget.disposisiSopId});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      setStateIfMounted(() {
        if (sukses) {
          _d = Map<String, dynamic>.from((r['data'] as Map?) ?? const {});
        } else {
          _galat = '${r['message'] ?? r['description'] ?? 'Gagal memuat detail.'}';
        }
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String kunci) =>
      ((_d[kunci] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  void _pesan(String teks, {bool galat = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(teks),
      backgroundColor: galat ? Theme.of(context).colorScheme.error : null,
    ));
  }

  // ── Tindakan ────────────────────────────────────────────────────────────

  Future<void> _prosesTahap(Map<String, dynamic> tahap) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogProsesTahap(tahap: tahap),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final r = await ApiClient.instance.aksi('sop_proses', hasil);
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      _pesan(sukses
          ? '${r['message'] ?? 'Tahap berhasil diproses.'}'
          : '${r['message'] ?? r['description'] ?? 'Gagal memproses tahap.'}',
          galat: !sukses);
      if (sukses) await _muat();
    } catch (e) {
      _pesan('$e', galat: true);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Mengubah langkah yang SUDAH diambil -- padanan tombol "Ubah" pada
  /// TampilanAlurSopAction. Izinnya ditentukan server (`bisaUbah` per baris
  /// riwayat) dan DITEGAKKAN ULANG saat menyimpan, jadi tombol ini hanya
  /// tampilan.
  Future<void> _ubahLangkah(Map<String, dynamic> r) async {
    setStateIfMounted(() => _sibuk = true);
    Map<String, dynamic> info;
    try {
      final t = await ApiClient.instance
          .aksi('sop_ubah_info', {'disposisiAlurSopId': '${r['id']}'});
      if (!mounted) return;
      if (t['status'] != '00' && t['status'] != 'success') {
        _pesan('${t['message'] ?? 'Langkah ini tidak dapat diubah.'}',
            galat: true);
        return;
      }
      info = Map<String, dynamic>.from((t['data'] as Map?) ?? const {});
    } catch (e) {
      if (mounted) _pesan('$e', galat: true);
      return;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }

    if (!mounted) return;
    if (info['langkahOrangLain'] == true) {
      final lanjut = await _konfirmasi(
          'Ubah langkah milik orang lain?',
          'Langkah ini diambil oleh ${info['olehNama'] ?? 'pengguna lain'}. '
              'Nama pengambil aslinya tetap dipertahankan pada catatan; '
              'yang berubah hanya isian disposisinya.');
      if (lanjut != true || !mounted) return;
    }

    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogProsesTahap(tahap: info, modeUbah: true),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final t = await ApiClient.instance.aksi('sop_ubah', hasil);
      if (!mounted) return;
      final sukses = t['status'] == '00' || t['status'] == 'success';
      _pesan(
          '${t['message'] ?? (sukses ? 'Perubahan tersimpan.' : 'Gagal menyimpan perubahan.')}',
          galat: !sukses);
      if (sukses) await _muat();
    } catch (e) {
      _pesan('$e', galat: true);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _batalkanLangkah(Map<String, dynamic> tahap) async {
    final ya = await _konfirmasi(
        'Batalkan tahap ini?',
        'Tahap "${tahap['tahap'] ?? ''}" yang masih menunggu akan dibatalkan. '
            'Tindakan ini mengikuti aturan yang sama dengan versi ZKoss.');
    if (ya != true || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final r = await ApiClient.instance.aksi('sop_batalkan_langkah',
          {'disposisiAlurSopId': '${tahap['disposisiAlurSopId']}'});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      _pesan(
          sukses
              ? '${r['message'] ?? 'Tahap dibatalkan.'}'
              : '${r['message'] ?? 'Gagal membatalkan tahap.'}',
          galat: !sukses);
      if (sukses) await _muat();
    } catch (e) {
      _pesan('$e', galat: true);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _batalkanPengajuan() async {
    final ya = await _konfirmasi('Batalkan pengajuan ini?',
        'Pengajuan akan ditarik kembali. Hanya bisa dilakukan selama belum ada '
            'tahap lain yang memprosesnya.');
    if (ya != true || !mounted) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final r = await ApiClient.instance.aksi(
          'sop_batalkan_pengajuan', {'disposisiSopId': widget.disposisiSopId});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      _pesan(
          sukses
              ? '${r['message'] ?? 'Pengajuan dibatalkan.'}'
              : '${r['message'] ?? 'Gagal membatalkan pengajuan.'}',
          galat: !sukses);
      if (sukses && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _pesan('$e', galat: true);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _cetak() async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final r = await ApiClient.instance
          .aksi('sop_cetak', {'disposisiSopId': widget.disposisiSopId});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      final url = '${r['url'] ?? ''}';
      if (!sukses || url.isEmpty) {
        _pesan('${r['message'] ?? 'Dokumen gagal dicetak.'}', galat: true);
        return;
      }
      // sop_cetak hanya mengembalikan URL, jadi isinya diunduh dulu supaya
      // tetap tampil sebagai PRATINJAU dalam aplikasi -- bukan langsung
      // melempar pengguna ke dialog printer sistem.
      final unduhan =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (!mounted) return;
      if (unduhan.statusCode >= 200 && unduhan.statusCode < 300) {
        await tampilkanPratinjauPdf(context,
            judul: '${_d['kode'] ?? 'Disposisi'}',
            isi: Uint8List.fromList(unduhan.bodyBytes));
      } else {
        _pesan('Dokumen tercetak tetapi tidak dapat diunduh '
            '(HTTP ${unduhan.statusCode}).', galat: true);
      }
    } catch (e) {
      _pesan('$e', galat: true);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<bool?> _konfirmasi(String judul, String isi) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(judul),
          content: Text(isi),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Lanjutkan')),
          ],
        ),
      );

  // ── Tampilan ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Detail Pengajuan'),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Cetak disposisi',
            icon: const Icon(Icons.print_outlined),
            onPressed: _sibuk || _d.isEmpty ? null : _cetak,
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _sibuk ? null : _muat,
          ),
        ],
      ),
      body: _memuat && _d.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _galat != null && _d.isEmpty
              ? _tampilanGalat()
              : Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: _muat,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          _kartuHeader(),
                          if (_d['selesai'] == true) ...[
                            const SizedBox(height: 12),
                            _spandukSelesai(),
                          ],
                          const SizedBox(height: 12),
                          _bagianTahapPending(),
                          const SizedBox(height: 12),
                          _bagianRiwayat(),
                          const SizedBox(height: 12),
                          _bagianForm(),
                          const SizedBox(height: 12),
                          _bagianAlur(),
                          if (_d['bisaBatalkanPengajuan'] == true) ...[
                            const SizedBox(height: 18),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.undo, size: 18),
                              label: const Text('Batalkan Pengajuan'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger),
                              onPressed: _sibuk ? null : _batalkanPengajuan,
                            ),
                          ],
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                    if (_sibuk)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                            child: CircularProgressIndicator()),
                      ),
                  ],
                ),
    );
  }

  Widget _tampilanGalat() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: AppColors.danger),
              const SizedBox(height: 10),
              Text(_galat ?? 'Gagal memuat.', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );

  Widget _kotak({required String judul, required Widget isi, IconData? ikon}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          border: Border.all(color: AppColors.borderOf(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (ikon != null) ...[
                Icon(ikon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
              ],
              Text(judul,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            isi,
          ],
        ),
      );

  Widget _baris(String label, String nilai) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondaryOf(context))),
            ),
            Expanded(
                child: Text(nilai.isEmpty ? '-' : nilai,
                    style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Widget _kartuHeader() => _kotak(
        judul: '${_d['kode'] ?? '-'}',
        ikon: Icons.description_outlined,
        isi: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _baris('SOP', '${_d['sop'] ?? ''}'),
            _baris('Pengaju', '${_d['pengaju'] ?? ''}'),
            _baris('Waktu pengajuan', '${_d['waktuPengajuan'] ?? ''}'),
            _baris('Keterangan', '${_d['keterangan'] ?? ''}'),
          ],
        ),
      );

  Widget _spandukSelesai() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.latarLembut(AppColors.success),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified, color: AppColors.success, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pengajuan sudah SELESAI',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success)),
                  if ('${_d['catatanSelesai'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${_d['catatanSelesai']}',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _bagianTahapPending() {
    final pending = _list('tahapPending');
    if (pending.isEmpty) {
      return _kotak(
        judul: 'Tahap Menunggu',
        ikon: Icons.hourglass_empty,
        isi: Text('Tidak ada tahap yang sedang menunggu.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondaryOf(context))),
      );
    }
    return Column(
      children: [
        for (final t in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _kotak(
              judul: 'Menunggu: ${t['tahap'] ?? '-'}',
              ikon: Icons.hourglass_top,
              isi: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t['ditolak'] == true &&
                      '${t['infoDitolak'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppColors.latarLembut(AppColors.danger),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('${t['infoDitolak']}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger)),
                      ),
                    ),
                  _baris('Petugas', '${t['aktorLabel'] ?? ''}'),
                  _baris('Hak akses', '${t['hakAkses'] ?? ''}'),
                  if ('${t['waktuMaksimal'] ?? ''}'.isNotEmpty)
                    _baris('Batas waktu', '${t['waktuMaksimal']}'),
                  _daftarAktorBerhak(t),
                  const SizedBox(height: 8),
                  if (t['bisaProses'] == true)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Proses Tahap Ini'),
                          onPressed: _sibuk ? null : () => _prosesTahap(t),
                        ),
                        if (t['bisaBatalkanLangkah'] == true)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Batalkan Tahap'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger),
                            onPressed:
                                _sibuk ? null : () => _batalkanLangkah(t),
                          ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: AppColors.latarLembut(
                              AppColors.textSecondaryOf(context)),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          'Anda tidak berhak memproses tahap ini. Tahap ini '
                          'menunggu petugas yang tercantum di atas.',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context))),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _daftarAktorBerhak(Map<String, dynamic> t) {
    final aktor = ((t['aktorBerhak'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (aktor.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text('Yang berhak',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context))),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in aktor)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.primary),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(
                        '${a['nama'] ?? a['userId'] ?? ''}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bagianRiwayat() {
    final riwayat = _list('riwayat');
    return _kotak(
      judul: 'Riwayat Langkah',
      ikon: Icons.history,
      isi: riwayat.isEmpty
          ? Text('Belum ada langkah yang diambil.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondaryOf(context)))
          : Column(
              children: [
                for (int i = 0; i < riwayat.length; i++)
                  _langkahRiwayat(riwayat[i], i == riwayat.length - 1),
              ],
            ),
    );
  }

  Widget _langkahRiwayat(Map<String, dynamic> r, bool terakhir) {
    final selesai = r['selesai'] == true;
    final kembali = r['kembali'] == true;
    final warna = kembali
        ? AppColors.warning
        : (selesai ? AppColors.success : AppColors.primary);
    final param = ((r['parameterTambahan'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final dokumen = ((r['dokumen'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration:
                    BoxDecoration(color: warna, shape: BoxShape.circle),
              ),
              if (!terakhir)
                Expanded(
                  child: Container(
                      width: 2,
                      color: AppColors.borderOf(context),
                      margin: const EdgeInsets.symmetric(vertical: 2)),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: terakhir ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['tahap'] ?? '-'}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                      '${r['aktor'] ?? ''}'
                      '${'${r['olehNama'] ?? ''}'.isEmpty ? '' : ' — ${r['olehNama']}'}',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryOf(context))),
                  const SizedBox(height: 2),
                  Text(
                      '${r['waktu'] ?? ''}'
                      '${'${r['waktuMaksimal'] ?? ''}'.isEmpty ? '' : '  •  batas ${r['waktuMaksimal']}'}',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondaryOf(context))),
                  if ('${r['opsi'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Pilihan: ${r['opsi']}',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  if ('${r['catatan'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Catatan: ${r['catatan']}',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  for (final p in param)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                          '• ${p['label'] ?? p['nama'] ?? ''}: ${p['nilai'] ?? '-'}',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  for (final dk in dokumen)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        Icon(Icons.attach_file,
                            size: 12,
                            color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('${dk['nama'] ?? dk['key'] ?? 'Lampiran'}',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ]),
                    ),
                  if (r['bisaUbah'] == true)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('Ubah',
                            style: TextStyle(fontSize: 11)),
                        onPressed: _sibuk ? null : () => _ubahLangkah(r),
                      ),
                    ),
                  if (kembali)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Dikembalikan ke tahap sebelumnya',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bagianForm() {
    final form = Map<String, dynamic>.from(
        (_d['form'] as Map?) ?? const <String, dynamic>{});
    final fields = ((form['fields'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (form.isEmpty || (fields.isEmpty && '${form['nama'] ?? ''}'.isEmpty)) {
      return const SizedBox.shrink();
    }
    return _kotak(
      judul: '${form['istilah'] ?? 'Data Terkait'}',
      ikon: Icons.assignment_outlined,
      isi: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ('${form['nama'] ?? ''}'.isNotEmpty)
            _baris('Nama', '${form['nama']}'),
          if ('${form['kode'] ?? ''}'.isNotEmpty)
            _baris('Kode', '${form['kode']}'),
          for (final f in fields)
            _baris('${f['label'] ?? f['nama'] ?? ''}', '${f['nilai'] ?? ''}'),
          const SizedBox(height: 4),
          Text('Data ini hanya-baca di sini, sama seperti versi ZKoss.',
              style: TextStyle(
                  fontSize: 10, color: AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }

  Widget _bagianAlur() {
    final alur = Map<String, dynamic>.from(
        (_d['alur'] as Map?) ?? const <String, dynamic>{});
    final nodes = ((alur['nodes'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (nodes.isEmpty) return const SizedBox.shrink();
    return _kotak(
      judul: 'Peta Alur SOP',
      ikon: Icons.account_tree_outlined,
      isi: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ('${alur['ringkasan'] ?? ''}'.trim().isNotEmpty) ...[
            Text('${alur['ringkasan']}',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 10),
          ],
          for (final n in nodes) _simpulAlur(n),
        ],
      ),
    );
  }

  Widget _simpulAlur(Map<String, dynamic> n) {
    final selesai = n['selesai'] == true;
    final menunggu = n['menunggu'] == true;
    final belum = n['belumDilewati'] == true;
    final lewat = n['lewatBatasWaktu'] == true;
    Color warna = AppColors.textSecondaryOf(context);
    IconData ikon = Icons.radio_button_unchecked;
    if (selesai) {
      warna = AppColors.success;
      ikon = Icons.check_circle;
    } else if (menunggu) {
      warna = lewat ? AppColors.danger : AppColors.warning;
      ikon = Icons.hourglass_top;
    } else if (belum) {
      warna = AppColors.textSecondaryOf(context);
      ikon = Icons.radio_button_unchecked;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 16, color: warna),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${n['nama'] ?? '-'}'
                          '${n['start'] == true ? '  (mulai)' : ''}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: warna)),
                    ),
                    if ('${n['status'] ?? ''}'.isNotEmpty)
                      Text('${n['status']}',
                          style: TextStyle(fontSize: 10, color: warna)),
                  ],
                ),
                if ('${n['aktor'] ?? ''}'.isNotEmpty)
                  Text('${n['aktor']}',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondaryOf(context))),
                if ('${n['waktuMaksimal'] ?? ''}'.isNotEmpty)
                  Text('Batas: ${n['waktuMaksimal']}',
                      style: TextStyle(
                          fontSize: 10,
                          color: lewat
                              ? AppColors.danger
                              : AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DIALOG PROSES TAHAP — padanan form disposisi DisposisiAlurSopAction.onSave
// ════════════════════════════════════════════════════════════════════════════

class _DialogProsesTahap extends StatefulWidget {
  final Map<String, dynamic> tahap;

  /// true = mengubah langkah yang SUDAH diambil (aksi `sop_ubah`), bukan
  /// memproses tahap yang menunggu (`sop_proses`). Bentuk muatan `sop_ubah_info`
  /// sengaja dibuat kompatibel dgn `tahapPending`, sehingga satu form melayani
  /// keduanya dan tidak ada dua tempat yang harus dijaga tetap sama.
  final bool modeUbah;
  const _DialogProsesTahap({required this.tahap, this.modeUbah = false});

  @override
  State<_DialogProsesTahap> createState() => _DialogProsesTahapState();
}

class _DialogProsesTahapState extends State<_DialogProsesTahap> {
  final _keterangan = TextEditingController();
  final Map<String, TextEditingController> _nilaiParam = {};
  final Set<String> _alurDipilih = {};
  final Map<String, String> _berkasTerunggah = {};

  bool _kembali = false;
  bool _selesai = false;
  bool _mengunggah = false;
  String? _galat;

  List<Map<String, dynamic>> _petaList(String kunci) =>
      ((widget.tahap[kunci] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> get _opsi => _petaList('nextOptions');
  List<Map<String, dynamic>> get _param => _petaList('parameterDefinisi');
  List<Map<String, dynamic>> get _dokumen => _petaList('dokumenDefinisi');

  bool get _tunggal => widget.tahap['berupaPilihanTunggal'] == true;
  bool get _opsiTidakWajib => widget.tahap['nextTidakWajib'] == true;
  bool get _catatanWajib => widget.tahap['catatanWajib'] == true;

  /// Tahap boleh dikonfigurasi TANPA kolom catatan sama sekali (ZKoss
  /// menyembunyikan barisnya). Server lama yang belum mengirim kunci ini
  /// diperlakukan sebagai "boleh" -- sama dengan default entitasnya.
  bool get _bolehCatatan => widget.tahap['bolehDiisiCatatan'] != false;

  /// Hanya tahap dengan `tanggalDisposisiBolehDiubah` yang boleh mengubah waktu
  /// disposisi; selain itu memakai waktu server.
  bool get _tanggalBolehDiubah => widget.tahap['tanggalBolehDiubah'] == true;

  /// Tahap yang membekukan dokumen tidak menerima unggahan baru.
  bool get _bekukanDokumen => widget.tahap['bekukanDokumen'] == true;

  DateTime? _waktuDisposisi;

  String _dua(int n) => n < 10 ? '0$n' : '$n';

  /// Format yang dibaca server: `Common.dateFormat3` = dd-MM-yyyy HH:mm:ss.
  String _waktuServer(DateTime d) =>
      '${_dua(d.day)}-${_dua(d.month)}-${d.year} '
      '${_dua(d.hour)}:${_dua(d.minute)}:${_dua(d.second)}';

  Future<void> _pilihWaktuDisposisi() async {
    final kini = _waktuDisposisi ?? DateTime.now();
    final tgl = await showDatePicker(
      context: context,
      initialDate: kini,
      firstDate: DateTime(kini.year - 5),
      lastDate: DateTime(kini.year + 5),
    );
    if (tgl == null || !mounted) return;
    final jam = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(kini),
    );
    if (!mounted) return;
    setState(() => _waktuDisposisi = DateTime(tgl.year, tgl.month, tgl.day,
        jam?.hour ?? kini.hour, jam?.minute ?? kini.minute));
  }

  @override
  void initState() {
    super.initState();
    for (final p in _param) {
      _nilaiParam['${p['key']}'] =
          TextEditingController(text: '${p['nilaiDefault'] ?? ''}');
    }
    if (widget.modeUbah) {
      _keterangan.text = '${widget.tahap['keterangan'] ?? ''}';
      _selesai = widget.tahap['selesai'] == true;
      _kembali = widget.tahap['kembali'] == true;
    }
  }

  /// Rute hanya boleh diubah selama langkah ini belum melahirkan penerus --
  /// aturan `editPilihan` pada ZKoss. Di luar mode ubah, selalu boleh.
  bool get _bolehUbahPilihan =>
      !widget.modeUbah || widget.tahap['bisaUbahPilihan'] == true;

  @override
  void dispose() {
    _keterangan.dispose();
    for (final c in _nilaiParam.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pilihBerkas(Map<String, dynamic> d) async {
    final hasil = await FilePicker.platform.pickFiles(withData: true);
    if (hasil == null || hasil.files.isEmpty) return;
    final berkas = hasil.files.single;
    final isi = berkas.bytes;
    if (isi == null || !mounted) return;
    setState(() => _mengunggah = true);
    final galat = await UnggahLampiranSop.unggah(
      ref: '${widget.tahap['disposisiAlurSopId']}',
      kunci: '${d['key']}',
      namaBerkas: berkas.name,
      isi: isi,
    );
    if (!mounted) return;
    setState(() {
      _mengunggah = false;
      if (galat == null) {
        _berkasTerunggah['${d['key']}'] = berkas.name;
        _galat = null;
      } else {
        _galat = galat;
      }
    });
  }

  String? _periksa() {
    // Kewajiban catatan hanya berlaku bila kolomnya memang ditampilkan; tahap
    // yang dikonfigurasi tanpa kolom catatan tidak boleh menuntut isiannya.
    if (_bolehCatatan && _catatanWajib && _keterangan.text.trim().isEmpty) {
      return 'Catatan wajib diisi pada tahap ini.';
    }
    if (_bolehUbahPilihan &&
        !_kembali &&
        !_selesai &&
        _alurDipilih.isEmpty &&
        !_opsiTidakWajib &&
        _opsi.isNotEmpty) {
      return 'Pilih tahap lanjutan, atau pilih "Setujui dan Selesai" / '
          '"Kembalikan ke tahap sebelumnya".';
    }
    for (final p in _param) {
      if (p['wajib'] == true &&
          (_nilaiParam['${p['key']}']?.text ?? '').trim().isEmpty) {
        return 'Isian "${p['label'] ?? p['nama'] ?? p['key']}" wajib diisi.';
      }
      if (p['lampiranWajib'] == true &&
          !_berkasTerunggah.containsKey('${p['key']}')) {
        return 'Lampiran untuk "${p['label'] ?? p['nama'] ?? p['key']}" wajib diunggah.';
      }
    }
    if (!_bekukanDokumen) {
      for (final d in _dokumen) {
        if (d['wajib'] == true && !_berkasTerunggah.containsKey('${d['key']}')) {
          return 'Dokumen "${d['nama'] ?? d['key']}" wajib diunggah.';
        }
      }
    }
    return null;
  }

  void _kirim() {
    final galat = _periksa();
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    final body = <String, dynamic>{
      'disposisiAlurSopId': '${widget.tahap['disposisiAlurSopId']}',
      'keterangan': _keterangan.text.trim(),
      // Hanya dikirim bila tahap memang mengizinkan; server pun memeriksanya
      // ulang, jadi klien tidak bisa memaksakan tanggal pada tahap yang tidak
      // dikonfigurasi begitu.
      if (_tanggalBolehDiubah && _waktuDisposisi != null)
        'waktu': _waktuServer(_waktuDisposisi!),
    };
    if (widget.modeUbah) {
      body['kembali'] = _kembali;
      body['selesai'] = _selesai;
    } else if (_kembali) {
      body['kembali'] = true;
    } else if (_selesai) {
      body['selesai'] = true;
    }
    if (_alurDipilih.isNotEmpty) {
      // Dikirim sebagai ANGKA: server membacanya dengan JSONArray.getLong.
      body['alurSopIds'] = [
        for (final id in _alurDipilih) int.tryParse(id) ?? id,
      ];
    }
    if (_param.isNotEmpty) {
      body['parameterTambahan'] = [
        for (final p in _param)
          {
            'kelompokId': p['kelompokId'],
            'parameterId': p['parameterId'],
            'nilai': _nilaiParam['${p['key']}']?.text.trim() ?? '',
            'catatan': '',
          }
      ];
    }
    Navigator.pop(context, body);
  }

  @override
  Widget build(BuildContext context) {
    final lebar = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text(
          '${widget.modeUbah ? 'Ubah' : 'Proses'}: ${widget.tahap['tahap'] ?? ''}',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: lebar > 620 ? 560 : lebar * 0.9,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_galat != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: AppColors.latarLembut(AppColors.danger),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_galat!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger)),
                ),
              if (_bolehCatatan)
                TextField(
                  controller: _keterangan,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText:
                        'Catatan${_catatanWajib ? ' (wajib)' : ' (opsional)'}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              if (_tanggalBolehDiubah) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pilihWaktuDisposisi,
                  borderRadius: BorderRadius.circular(6),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal dan Waktu Disposisi',
                      helperText: 'Tahap ini memperbolehkan waktunya diubah',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Icon(Icons.event, size: 18),
                    ),
                    child: Text(
                        _waktuDisposisi == null
                            ? 'Sekarang (waktu server)'
                            : _waktuServer(_waktuDisposisi!),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
              if (widget.tahap['bisaKembali'] == true)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _kembali,
                  title: const Text('Kembalikan ke tahap sebelumnya',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() {
                    _kembali = v ?? false;
                    if (_kembali) {
                      _selesai = false;
                      _alurDipilih.clear();
                    }
                  }),
                ),
              if (widget.tahap['bisaSelesai'] == true)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selesai,
                  title: const Text('Setujui dan Selesai',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() {
                    _selesai = v ?? false;
                    if (_selesai) {
                      _kembali = false;
                      _alurDipilih.clear();
                    }
                  }),
                ),
              if (_opsi.isNotEmpty && !_kembali && !_selesai && _bolehUbahPilihan) ...[
                const SizedBox(height: 8),
                Text(
                    _tunggal
                        ? 'Pilih SATU tahap lanjutan'
                        : 'Pilih tahap lanjutan (boleh lebih dari satu)',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                for (final o in _opsi)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _alurDipilih.contains('${o['alurSopId']}'),
                    title: Text(
                        '${o['nama'] ?? ''}'
                        '${'${o['opsi'] ?? ''}'.isEmpty ? '' : ' — ${o['opsi']}'}',
                        style: const TextStyle(fontSize: 12)),
                    // Pratinjau penerima -- padanan SopUtil.renderAktorTunggal /
                    // tampilAktor di ZKoss. Tanpa ini pengguna memilih rute tanpa
                    // tahu dokumennya pergi ke siapa.
                    subtitle: o['kembaliKePengaju'] == true
                        ? Text('Kembali ke pengaju',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning))
                        : ('${o['aktorLabel'] ?? ''}'.isEmpty
                            ? null
                            : Text('Ke: ${o['aktorLabel']}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        AppColors.textSecondaryOf(context)))),
                    onChanged: (v) => setState(() {
                      final id = '${o['alurSopId']}';
                      if (v == true) {
                        if (_tunggal) _alurDipilih.clear();
                        _alurDipilih.add(id);
                      } else {
                        _alurDipilih.remove(id);
                      }
                    }),
                  ),
                if (_opsiTidakWajib)
                  Text('Tahap lanjutan boleh dikosongkan pada tahap ini.',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondaryOf(context))),
              ],
              if (_param.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Isian Tambahan',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                for (final p in _param) _isianParameter(p),
              ],
              if (_dokumen.isNotEmpty && _bekukanDokumen)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                      'Dokumen dikunci pada tahap ini, jadi tidak dapat diunggah '
                      'maupun diganti.',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondaryOf(context))),
                ),
              if (_dokumen.isNotEmpty && !_bekukanDokumen) ...[
                const SizedBox(height: 12),
                const Text('Dokumen',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                for (final d in _dokumen)
                  _barisBerkas(
                      kunci: '${d['key']}',
                      label: '${d['nama'] ?? d['key']}',
                      wajib: d['wajib'] == true,
                      onPilih: () => _pilihBerkas(d)),
              ],
              if (widget.tahap['lampiranCatatanWajib'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _barisBerkas(
                      kunci: 'Lampiran Catatan Disposisi',
                      label: 'Lampiran Catatan Disposisi',
                      wajib: true,
                      onPilih: () => _pilihBerkas(
                          {'key': 'Lampiran Catatan Disposisi'})),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed:
                _mengunggah ? null : () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
            onPressed: _mengunggah ? null : _kirim,
            child: const Text('Simpan')),
      ],
    );
  }

  Widget _isianParameter(Map<String, dynamic> p) {
    final pilihan = '${p['pilihan'] ?? ''}'
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final label =
        '${p['label'] ?? p['nama'] ?? p['key']}${p['wajib'] == true ? ' (wajib)' : ''}';
    final kunci = '${p['key']}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pilihan.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _nilaiParam[kunci]!.text.isEmpty
                  ? null
                  : _nilaiParam[kunci]!.text,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true),
              items: [
                for (final v in pilihan)
                  DropdownMenuItem(
                      value: v,
                      child: Text(v, style: const TextStyle(fontSize: 12))),
              ],
              onChanged: (v) =>
                  setState(() => _nilaiParam[kunci]!.text = v ?? ''),
            )
          else
            TextField(
              controller: _nilaiParam[kunci],
              decoration: InputDecoration(
                  labelText: label,
                  helperText: '${p['keterangan'] ?? ''}'.isEmpty
                      ? null
                      : '${p['keterangan']}',
                  border: const OutlineInputBorder(),
                  isDense: true),
            ),
          if (p['harusMenyertakanLampiran'] == true ||
              p['lampiranWajib'] == true)
            _barisBerkas(
                kunci: kunci,
                label: 'Lampiran untuk ${p['label'] ?? p['nama'] ?? kunci}',
                wajib: p['lampiranWajib'] == true,
                onPilih: () => _pilihBerkas(p)),
        ],
      ),
    );
  }

  Widget _barisBerkas(
      {required String kunci,
      required String label,
      required bool wajib,
      required VoidCallback onPilih}) {
    final terunggah = _berkasTerunggah[kunci];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
                '$label${wajib ? ' (wajib)' : ''}'
                '${terunggah == null ? '' : '\n$terunggah'}',
                style: TextStyle(
                    fontSize: 11,
                    color: terunggah == null
                        ? AppColors.textSecondaryOf(context)
                        : AppColors.success)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: Icon(
                terunggah == null ? Icons.upload_file : Icons.check, size: 15),
            label: Text(terunggah == null ? 'Unggah' : 'Ganti',
                style: const TextStyle(fontSize: 11)),
            onPressed: _mengunggah ? null : onPilih,
          ),
        ],
      ),
    );
  }
}
