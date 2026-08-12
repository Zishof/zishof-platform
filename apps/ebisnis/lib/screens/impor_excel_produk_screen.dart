import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
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
        produkId = j['produkId'] as int?,
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
  String? _error;

  List<String> _kategoriDikenal = [];
  List<String> _pemasokDikenal = [];
  List<String> _satuanDikenal = [];
  List<String> _kolomTidakDitemukan = [];
  List<_BarisImpor> _baris = [];
  bool _nonaktifkanTakDiimpor = false;
  bool _abaikanStokKosong = true;

  List<_BarisImpor> get _barisTerlihat => _abaikanStokKosong
      ? _baris.where((b) => _nilaiStok(b) != 0).toList()
      : _baris;

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
        for (final b in _baris.where((b) => _nilaiStok(b) == 0)) {
          b.disertakan = false;
        }
        _tahap = _Tahap.tinjau;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  Future<void> _komitImpor() async {
    final terpilih = _baris.where((b) => b.disertakan).toList();
    if (terpilih.isEmpty) {
      setStateIfMounted(
          () => _error = 'Tidak ada baris yang disertakan utk diimpor.');
      return;
    }
    setStateIfMounted(() {
      _memproses = true;
      _error = null;
      _barisUntukKomit = terpilih.length;
      _barisSelesaiKomit = 0;
    });
    final idBerhasilSemuaBatch = <int>[];
    _total = _dibuat = _diperbarui = _dilewati = _kategoriBaru =
        _pemasokBaru = _satuanBaru = _stokDiopname = _verifikasiGagal = 0;
    try {
      const ukuranBatch = 200;
      for (var awal = 0; awal < terpilih.length; awal += ukuranBatch) {
        final batch = terpilih.sublist(
            awal, (awal + ukuranBatch).clamp(0, terpilih.length));
        final hasil = await ApiClient.instance.aksi('produk_impor_excel_komit',
            {'baris': batch.map((b) => b.keKomit()).toList()});
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
            {'id_disentuh': idBerhasilSemuaBatch});
        _dinonaktifkan = (hasilNon['dinonaktifkan'] as num?)?.toInt();
      }

      setStateIfMounted(() => _tahap = _Tahap.laporan);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
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
      _abaikanStokKosong = true;
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
                child:
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
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
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade700)),
                ),
              Text(
                  '${_baris.length} baris terbaca, ${_baris.where((b) => b.disertakan).length} akan diimpor.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Jangan tampilkan/upload/proses barang dengan stok = 0',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Aktif secara default.'),
                value: _abaikanStokKosong,
                onChanged: (v) => setStateIfMounted(() {
                  _abaikanStokKosong = v ?? true;
                  for (final b in _baris.where((b) => _nilaiStok(b) == 0)) {
                    b.disertakan = !_abaikanStokKosong;
                  }
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _barisTerlihat.length,
            itemBuilder: (context, i) => _kartuBaris(_barisTerlihat[i]),
          ),
        ),
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
