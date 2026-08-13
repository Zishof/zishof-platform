import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

/// Layar Impor Excel Produk (spec §7.5) -- format "Accurate" ("Daftar Barang
/// dan Jasa"). BEDA dari deskripsi Electron: parsing 100% dilakukan SERVER
/// (`produk_impor_excel_preview` menerima `file_base64` mentah dan
/// mengembalikan baris yg sudah terstruktur) -- Flutter TIDAK perlu meniru
/// logika deteksi kolom Electron sendiri (klien hanya baca berkas jadi bytes
/// lalu unggah), lebih sederhana &amp; dijamin identik hasilnya dgn server.
///
/// Alur: pilih berkas -> preview (baca-saja, tak mengubah apa pun) -> layar
/// Tinjau (wajib, semua baris bisa diedit + dikecualikan) -> Komit per-batch
/// 200 baris (`produk_impor_excel_komit`, per-baris savepoint di server jadi
/// aman lanjut walau ada baris gagal) -> opsional "Nonaktifkan produk yang
/// tak ditemukan di file ini" (`produk_nonaktifkan_tak_diimpor`, union id
/// baris berhasil dari SEMUA batch) -> Laporan hasil.
class ImporExcelProdukScreen extends StatefulWidget {
  const ImporExcelProdukScreen({super.key});
  @override
  State<ImporExcelProdukScreen> createState() => _ImporExcelProdukScreenState();
}

enum _Tahap { pilihBerkas, tinjau, laporan }

class _BarisImpor {
  final int no;
  final bool baru;
  final int? produkId;
  late final TextEditingController kode;
  late final TextEditingController barcode;
  late final TextEditingController nama;
  late final TextEditingController kategoriNama;
  late final TextEditingController pemasokNama;
  late final TextEditingController satuanNama;
  late final TextEditingController stokBaru;
  final double stokLama;
  late final TextEditingController hargaJual;
  late final TextEditingController hargaBeli;
  bool disertakan = true;

  String? statusKomit; // berhasil/gagal/dilewati (diisi setelah commit)
  String? pesanKomit;
  String? teknisKomit;
  String? solusiKomit;

  _BarisImpor(Map<String, dynamic> j)
      : no = (j['no'] as num?)?.toInt() ?? 0,
        baru = j['baru'] == true,
        produkId = (j['produkId'] as num?)?.toInt(),
        stokLama = (j['stokLama'] as num?)?.toDouble() ?? 0 {
    kode = TextEditingController(text: '${j['kode'] ?? ''}');
    barcode = TextEditingController(text: '${j['barcode'] ?? ''}');
    nama = TextEditingController(text: '${j['nama'] ?? ''}');
    kategoriNama = TextEditingController(text: '${j['kategoriNama'] ?? ''}');
    pemasokNama = TextEditingController(text: '${j['pemasokNama'] ?? ''}');
    satuanNama = TextEditingController(text: '${j['satuanNama'] ?? ''}');
    stokBaru = TextEditingController(text: '${(j['stokBaru'] as num?) ?? 0}');
    hargaJual = TextEditingController(text: '${(j['hargaJual'] as num?) ?? 0}');
    hargaBeli = TextEditingController(text: '${(j['hargaBeli'] as num?) ?? 0}');
  }

  void dispose() {
    for (final c in [
      kode,
      barcode,
      nama,
      kategoriNama,
      pemasokNama,
      satuanNama,
      stokBaru,
      hargaJual,
      hargaBeli
    ]) {
      c.dispose();
    }
  }

  Map<String, dynamic> keKomit() => {
        'produkId': produkId,
        'kode': kode.text.trim(),
        'barcode': barcode.text.trim(),
        'nama': nama.text.trim(),
        'kategoriNama': kategoriNama.text.trim(),
        'pemasokNama': pemasokNama.text.trim(),
        'satuanNama': satuanNama.text.trim(),
        'stokBaru': double.tryParse(stokBaru.text.replaceAll(',', '.')) ?? 0,
        'hargaJual': double.tryParse(hargaJual.text.replaceAll(',', '.')) ?? 0,
        'hargaBeli': double.tryParse(hargaBeli.text.replaceAll(',', '.')) ?? 0,
      };
}

class _ImporExcelProdukScreenState extends State<ImporExcelProdukScreen> {
  _Tahap _tahap = _Tahap.pilihBerkas;
  bool _memproses = false;
  AppErrorInfo? _error;

  AppErrorInfo _infoError(Object error, String aktivitas) =>
      error is ApiException
          ? error.info
          : AppErrorInfo.dari(error, aktivitas: aktivitas);

  List<String> _kategoriDikenal = [];
  List<String> _pemasokDikenal = [];
  List<String> _satuanDikenal = [];
  List<String> _kolomTidakDitemukan = [];
  List<_BarisImpor> _baris = [];
  bool _nonaktifkanTakDiimpor = false;
  int _halamanTinjau = 0;

  // Seluruh hasil preview tetap berada lokal di memori aplikasi. Yang dirender
  // hanya 25 baris per halaman dan nomor navigasi ditampilkan per kelompok
  // maksimal lima halaman agar desktop maupun Android tetap ringan.
  static const int _barisPerHalaman = 25;
  static const int _maksTombolHalaman = 5;

  static const double _toleransiSelisihStok = 0.000001;

  bool _stokBerbeda(_BarisImpor b) =>
      (_nilaiStok(b) - b.stokLama).abs() > _toleransiSelisihStok;

  List<_BarisImpor> get _barisTerlihat => _baris.where(_stokBerbeda).toList();

  double _nilaiStok(_BarisImpor b) =>
      double.tryParse(b.stokBaru.text.replaceAll(',', '.')) ?? 0;

  // Progres komit per-batch (spec: tampilkan persentase, bukan spinner polos
  // saat 5000+ baris -- satu batch = 200 baris, jadi update tiap batch
  // selesai cukup responsif tanpa perlu progres per-baris dari server).
  int _barisUntukKomit = 0;
  int _barisSelesaiKomit = 0;
  double get _progresKomit =>
      _barisUntukKomit == 0 ? 0 : _barisSelesaiKomit / _barisUntukKomit;

  // Ringkasan hasil komit (tahap laporan)
  int _total = 0,
      _dibuat = 0,
      _diperbarui = 0,
      _dilewati = 0,
      _kategoriBaru = 0,
      _pemasokBaru = 0,
      _satuanBaru = 0,
      _stokDiopname = 0,
      _verifikasiGagal = 0;
  int? _dinonaktifkan;

  @override
  void dispose() {
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _pilihBerkas() async {
    setStateIfMounted(() {
      _error = null;
      _memproses = true;
    });
    try {
      final hasilPilih = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'xls'],
          withData: true);
      if (hasilPilih == null ||
          hasilPilih.files.isEmpty ||
          hasilPilih.files.first.bytes == null) {
        setStateIfMounted(() => _memproses = false);
        return;
      }
      final bytes = hasilPilih.files.first.bytes!;
      final hasil = await ApiClient.instance.aksi('produk_impor_excel_preview',
          {'file_base64': base64Encode(bytes), 'format': 'accurate'});
      final barisJson =
          ((hasil['baris'] as List?) ?? []).cast<Map<String, dynamic>>();
      setStateIfMounted(() {
        _kategoriDikenal = ((hasil['daftarKategori'] as List?) ?? [])
            .map((e) => '${(e as Map)['nama']}')
            .toList();
        _pemasokDikenal = ((hasil['daftarPemasok'] as List?) ?? [])
            .map((e) => '${(e as Map)['nama']}')
            .toList();
        _satuanDikenal = ((hasil['daftarSatuan'] as List?) ?? [])
            .map((e) => '${(e as Map)['nama']}')
            .toList();
        _kolomTidakDitemukan = ((hasil['kolomTidakDitemukan'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
        _baris = barisJson.map((j) => _BarisImpor(j)).toList();
        for (final b in _baris) {
          b.disertakan = _stokBerbeda(b);
        }
        _halamanTinjau = 0;
        _tahap = _Tahap.tinjau;
      });
    } catch (e) {
      setStateIfMounted(
          () => _error = _infoError(e, 'membaca pratinjau Excel produk'));
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  Future<void> _komitImpor() async {
    // Nilai stok dapat diedit di layar tinjau. Hitung kembali tepat sebelum
    // komit agar baris yang menjadi sama tidak ikut terkirim ke server.
    final terpilih =
        _baris.where((b) => b.disertakan && _stokBerbeda(b)).toList();
    if (terpilih.isEmpty) {
      setStateIfMounted(() => _error = AppErrorInfo.dari(
          'Tidak ada baris yang disertakan untuk diimpor.',
          aktivitas: 'komit impor produk'));
      return;
    }
    setStateIfMounted(() {
      _memproses = true;
      _error = null;
      _barisUntukKomit = terpilih.length;
      _barisSelesaiKomit = 0;
      _halamanTinjau = 0;
    });
    // Untuk opsi nonaktifkan, produk dengan stok sama tetap berarti ADA di
    // berkas. Masukkan seluruh id hasil preview agar tidak salah dianggap
    // hilang hanya karena memang tidak perlu diproses.
    final idBerhasilSemuaBatch = <int>{
      ..._baris.map((b) => b.produkId).whereType<int>(),
    };
    _total = _dibuat = _diperbarui = _dilewati = _kategoriBaru =
        _pemasokBaru = _satuanBaru = _stokDiopname = _verifikasiGagal = 0;
    try {
      const ukuranBatch = 200;
      for (var awal = 0; awal < terpilih.length; awal += ukuranBatch) {
        final batch = terpilih.sublist(
            awal, (awal + ukuranBatch).clamp(0, terpilih.length));
        final hasil =
            await ApiClient.instance.aksi('produk_impor_excel_komit', {
          'baris': batch.map((b) => b.keKomit()).toList(),
          'hanya_stok_berbeda': true,
        });
        setStateIfMounted(() => _barisSelesaiKomit += batch.length);
        _total += (hasil['total'] as num?)?.toInt() ?? 0;
        _dibuat += (hasil['dibuat'] as num?)?.toInt() ?? 0;
        _diperbarui += (hasil['diperbarui'] as num?)?.toInt() ?? 0;
        _dilewati += (hasil['dilewati'] as num?)?.toInt() ?? 0;
        _kategoriBaru += (hasil['kategoriBaru'] as num?)?.toInt() ?? 0;
        _pemasokBaru += (hasil['pemasokBaru'] as num?)?.toInt() ?? 0;
        _satuanBaru += (hasil['satuanBaru'] as num?)?.toInt() ?? 0;
        _stokDiopname += (hasil['stokDiopname'] as num?)?.toInt() ?? 0;
        _verifikasiGagal += (hasil['verifikasiGagal'] as num?)?.toInt() ?? 0;
        final barisHasil =
            ((hasil['baris'] as List?) ?? []).cast<Map<String, dynamic>>();
        for (var i = 0; i < barisHasil.length && i < batch.length; i++) {
          final r = barisHasil[i];
          batch[i].statusKomit = '${r['status']}';
          batch[i].pesanKomit = '${r['pesan'] ?? ''}';
          batch[i].teknisKomit = r['teknis'] as String?;
          batch[i].solusiKomit = r['solusi'] as String?;
          if (r['status'] == 'berhasil' && r['id'] != null) {
            idBerhasilSemuaBatch.add((r['id'] as num).toInt());
          }
        }
      }

      if (_nonaktifkanTakDiimpor && idBerhasilSemuaBatch.isNotEmpty) {
        final hasilNon = await ApiClient.instance.aksi(
            'produk_nonaktifkan_tak_diimpor',
            {'id_disentuh': idBerhasilSemuaBatch.toList()});
        _dinonaktifkan = (hasilNon['dinonaktifkan'] as num?)?.toInt();
      }

      setStateIfMounted(() => _tahap = _Tahap.laporan);
    } catch (e) {
      setStateIfMounted(
          () => _error = _infoError(e, 'menyimpan impor Excel produk'));
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  void _mulaiLagi() {
    for (final b in _baris) {
      b.dispose();
    }
    setStateIfMounted(() {
      _baris = [];
      _tahap = _Tahap.pilihBerkas;
      _error = null;
      _nonaktifkanTakDiimpor = false;
      _dinonaktifkan = null;
      _barisUntukKomit = 0;
      _barisSelesaiKomit = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tombolKembali = HeaderActionButton(
      icon: Icons.arrow_back,
      label: 'Kembali',
      tooltip: 'Kembali ke Produk',
      onPressed: () => Navigator.of(context).maybePop(),
    );
    return AppShell(
      menuAktif: MenuEBisnis.produk,
      judul: 'Impor Excel Produk',
      subjudul: 'Format Accurate ("Daftar Barang dan Jasa")',
      scrollable: false,
      aksiHeader: tombolKembali,
      actionsAppBar: [
        IconButton(
          tooltip: 'Kembali ke Produk',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
      body: switch (_tahap) {
        _Tahap.pilihBerkas => _bodyPilihBerkas(),
        _Tahap.tinjau => _bodyTinjau(),
        _Tahap.laporan => _bodyLaporan(),
      },
    );
  }

  Widget _bodyPilihBerkas() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.upload_file_outlined, size: 56, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text('Pilih berkas Excel (.xlsx) format Accurate',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
              'Berkas TIDAK diubah -- server hanya membaca dan menyusun pratinjau, belum menyimpan apa pun.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: AppErrorPanel(info: _error!, ringkas: true),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _memproses ? null : _pilihBerkas,
            icon: _memproses
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_open),
            label: Text(_memproses ? 'Memuat...' : 'Pilih Berkas'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _bodyTinjau() {
    final barisTerlihat = _barisTerlihat;
    final jumlahHalaman = barisTerlihat.isEmpty
        ? 0
        : (barisTerlihat.length / _barisPerHalaman).ceil();
    final halamanAktif =
        jumlahHalaman == 0 ? 0 : _halamanTinjau.clamp(0, jumlahHalaman - 1);
    final awal = halamanAktif * _barisPerHalaman;
    final akhir = (awal + _barisPerHalaman).clamp(0, barisTerlihat.length);
    final barisHalaman = barisTerlihat.sublist(awal, akhir);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_kolomTidakDitemukan.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      'Kolom tidak terdeteksi: ${_kolomTidakDitemukan.join(", ")} -- periksa kembali sebelum komit.',
                      style: const TextStyle(fontSize: 12)),
                ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: AppErrorPanel(info: _error!, ringkas: true),
                ),
              Text(
                  '${_baris.length} baris terbaca, ${barisTerlihat.length} memiliki selisih stok dan akan ditampilkan.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Hanya stok berbeda yang ditampilkan dan diproses. Stok yang sama dilewati otomatis.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _barisTerlihat.isEmpty
              ? const Center(
                  child: Text(
                    'Tidak ada selisih stok. Semua stok Excel sudah sama dengan stok saat ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: barisHalaman.length,
                  itemBuilder: (context, i) => _kartuBaris(barisHalaman[i]),
                ),
        ),
        if (jumlahHalaman > 1)
          _navigasiHalaman(halamanAktif, jumlahHalaman, awal + 1, akhir,
              barisTerlihat.length),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'Nonaktifkan produk yang tidak ditemukan di file ini'),
                  value: _nonaktifkanTakDiimpor,
                  onChanged: (v) => setStateIfMounted(
                      () => _nonaktifkanTakDiimpor = v ?? false),
                ),
                if (_memproses && _barisUntukKomit > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progresKomit,
                      minHeight: 8,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mengimpor $_barisSelesaiKomit dari $_barisUntukKomit baris '
                    '(${(_progresKomit * 100).toStringAsFixed(0)}%)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: _memproses ? null : _mulaiLagi,
                            child: const Text('Batal'))),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _memproses ? null : _komitImpor,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: _memproses
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Komit Impor'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _navigasiHalaman(int halamanAktif, int jumlahHalaman, int barisAwal,
      int barisAkhir, int totalBaris) {
    final awalKelompok =
        (halamanAktif ~/ _maksTombolHalaman) * _maksTombolHalaman;
    final akhirKelompok =
        (awalKelompok + _maksTombolHalaman).clamp(0, jumlahHalaman);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Menampilkan $barisAwal–$barisAkhir dari $totalBaris data · '
              '25 data per halaman',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Halaman sebelumnya',
                    visualDensity: VisualDensity.compact,
                    onPressed: halamanAktif > 0
                        ? () => setStateIfMounted(
                            () => _halamanTinjau = halamanAktif - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  for (var i = awalKelompok; i < akhirKelompok; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: i == halamanAktif
                          ? FilledButton(
                              onPressed: null, child: Text('${i + 1}'))
                          : OutlinedButton(
                              onPressed: () =>
                                  setStateIfMounted(() => _halamanTinjau = i),
                              child: Text('${i + 1}'),
                            ),
                    ),
                  IconButton(
                    tooltip: 'Halaman berikutnya',
                    visualDensity: VisualDensity.compact,
                    onPressed: halamanAktif < jumlahHalaman - 1
                        ? () => setStateIfMounted(
                            () => _halamanTinjau = halamanAktif + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuBaris(_BarisImpor b) {
    return AppSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                  value: b.disertakan,
                  onChanged: (v) =>
                      setStateIfMounted(() => b.disertakan = v ?? true)),
              Expanded(
                  child: Text('Baris ${b.no}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15))),
              StatusPill(
                  label: b.baru ? 'Baru' : 'Perbarui',
                  warna: b.baru ? AppColors.success : AppColors.info),
            ],
          ),
          if (b.disertakan) ...[
            Row(children: [
              Expanded(child: _kolomKecil('Kode', b.kode)),
              const SizedBox(width: 8),
              Expanded(child: _kolomKecil('Barcode', b.barcode)),
            ]),
            const SizedBox(height: 6),
            _kolomKecil('Nama', b.nama),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: _autoComplete(
                      'Kategori', b.kategoriNama, _kategoriDikenal)),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      _autoComplete('Pemasok', b.pemasokNama, _pemasokDikenal)),
              const SizedBox(width: 8),
              Expanded(
                  child: _autoComplete('Satuan', b.satuanNama, _satuanDikenal)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child:
                      _kolomKecil('Stok dari Excel', b.stokBaru, angka: true)),
              const SizedBox(width: 8),
              Expanded(child: _nilaiStokInfo('Stok Saat Ini', b.stokLama)),
              const SizedBox(width: 8),
              Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: b.stokBaru,
                builder: (_, __, ___) => _nilaiStokInfo(
                    'Selisih', _nilaiStok(b) - b.stokLama,
                    warna: _nilaiStok(b) - b.stokLama == 0
                        ? AppColors.textSecondary
                        : (_nilaiStok(b) - b.stokLama > 0
                            ? AppColors.success
                            : AppColors.danger)),
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _kolomKecil('Harga Jual', b.hargaJual, angka: true)),
              const SizedBox(width: 8),
              Expanded(
                  child: _kolomKecil('Harga Beli', b.hargaBeli, angka: true)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _kolomKecil(String label, TextEditingController c,
          {bool angka = false}) =>
      TextField(
        controller: c,
        keyboardType: angka
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 11),
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      );

  Widget _nilaiStokInfo(String label, double nilai, {Color? warna}) =>
      Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (warna ?? AppColors.primary).withValues(alpha: 0.07),
          border: Border.all(
              color: (warna ?? AppColors.primary).withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(NumberFormat('#,##0.##', 'id_ID').format(nilai),
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: warna ?? AppColors.primary)),
        ]),
      );

  Widget _autoComplete(
      String label, TextEditingController c, List<String> opsi) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: c.text),
      optionsBuilder: (v) => v.text.isEmpty
          ? opsi
          : opsi.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: (v) => c.text = v,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        controller.text = c.text;
        controller.addListener(() => c.text = controller.text);
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 11),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        );
      },
    );
  }

  Widget _bodyLaporan() {
    final gagal = _baris.where((b) => b.statusKomit == 'gagal').toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const kolom = 2;
            const jarak = 8.0;
            final lebarKolom =
                (constraints.maxWidth - (jarak * (kolom - 1))) / kolom;
            return GridView.count(
              crossAxisCount: kolom,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: jarak,
              crossAxisSpacing: jarak,
              childAspectRatio: lebarKolom / 96,
              children: [
                AppKpiCard(
                    icon: Icons.summarize_outlined,
                    warna: AppColors.primary,
                    nilai: '$_total',
                    label: 'Total Baris'),
                AppKpiCard(
                    icon: Icons.add_circle_outline,
                    warna: AppColors.success,
                    nilai: '$_dibuat',
                    label: 'Dibuat'),
                AppKpiCard(
                    icon: Icons.edit_outlined,
                    warna: AppColors.info,
                    nilai: '$_diperbarui',
                    label: 'Diperbarui'),
                AppKpiCard(
                    icon: Icons.skip_next_outlined,
                    warna: AppColors.textSecondary,
                    nilai: '$_dilewati',
                    label: 'Dilewati'),
                AppKpiCard(
                    icon: Icons.inventory_2_outlined,
                    warna: AppColors.teal,
                    nilai: '$_stokDiopname',
                    label: 'Stok Diopname'),
                AppKpiCard(
                    icon: Icons.error_outline,
                    warna: AppColors.danger,
                    nilai: '${gagal.length}',
                    label: 'Gagal'),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
            'Kategori baru: $_kategoriBaru · Pemasok baru: $_pemasokBaru · Satuan baru: $_satuanBaru',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        if (_verifikasiGagal > 0)
          Text('$_verifikasiGagal baris gagal verifikasi ulang pasca-commit.',
              style: const TextStyle(fontSize: 12, color: AppColors.danger)),
        if (_dinonaktifkan != null)
          Text(
              '$_dinonaktifkan produk lain dinonaktifkan (tak ada di file ini).',
              style: const TextStyle(fontSize: 12, color: AppColors.warning)),
        const SizedBox(height: 16),
        if (gagal.isNotEmpty) ...[
          const Text('Baris Gagal',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...gagal.map((b) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.error_outline, color: AppColors.danger),
                  title: Text('Baris ${b.no}: ${b.nama.text}',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      '${b.pesanKomit ?? ''}${b.solusiKomit != null ? "\nSaran: ${b.solusiKomit}" : ""}'),
                  isThreeLine: b.solusiKomit != null,
                ),
              )),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: _mulaiLagi, child: const Text('Impor Berkas Lain')),
      ],
    );
  }
}
