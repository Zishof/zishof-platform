import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

/// Tab "Sinkronisasi Siswa/Mahasiswa" (padanan `sinkron_siswa_mahasiswa.jsp`)
/// -- bulk-buat/perbarui AnggotaKoperasi dari data master Mahasiswa/Siswa yg
/// sudah ada, difilter tahun angkatan/masuk (+ opsional fakultas/jurusan
/// atau yayasan/sekolah). Gerbang `Sesi.instance.bolehKelola` (admin/
/// supervisor) -- SUDAH SAMA PERSIS dgn `LokasiKantinUtil.bolehKelola` versi
/// JSP, tak perlu flag baru.
class AnggotaTabSinkronisasi extends StatefulWidget {
  const AnggotaTabSinkronisasi({super.key});

  @override
  State<AnggotaTabSinkronisasi> createState() =>
      _AnggotaTabSinkronisasiState();
}

class _AnggotaTabSinkronisasiState extends State<AnggotaTabSinkronisasi> {
  bool _modeMahasiswa = true;
  bool _memuatReferensi = true;
  bool _menjalankan = false;
  String? _pesanError;
  Map<String, dynamic>? _hasilTerakhir;

  List<Map<String, dynamic>> _koperasi = [];
  List<Map<String, dynamic>> _fakultas = [];
  List<Map<String, dynamic>> _jurusan = [];
  List<Map<String, dynamic>> _yayasan = [];
  List<Map<String, dynamic>> _sekolah = [];

  int? _koperasiId;
  int? _fakultasId;
  int? _jurusanId;
  int? _yayasanId;
  int? _sekolahId;
  final _tahunController =
      TextEditingController(text: '${DateTime.now().year}');

  @override
  void initState() {
    super.initState();
    _muatReferensiAwal();
  }

  @override
  void dispose() {
    _tahunController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _ambilReferensi(String tipe,
      {int? indukId}) async {
    final hasil = await ApiClient.instance.aksi('sinkron_referensi',
        {'tipe': tipe, if (indukId != null) 'induk_id': indukId});
    return ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> _muatReferensiAwal() async {
    setStateIfMounted(() => _memuatReferensi = true);
    try {
      final hasil = await Future.wait([
        _ambilReferensi('koperasi'),
        _ambilReferensi('fakultas'),
        _ambilReferensi('yayasan'),
      ]);
      if (mounted) {
        setStateIfMounted(() {
          _koperasi = hasil[0];
          _fakultas = hasil[1];
          _yayasan = hasil[2];
        });
      }
    } catch (e) {
      if (mounted) setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuatReferensi = false);
    }
  }

  Future<void> _saatFakultasBerubah(int? id) async {
    setStateIfMounted(() {
      _fakultasId = id;
      _jurusanId = null;
      _jurusan = [];
    });
    if (id == null) return;
    try {
      final data = await _ambilReferensi('jurusan', indukId: id);
      if (mounted) setStateIfMounted(() => _jurusan = data);
    } catch (_) {}
  }

  Future<void> _saatYayasanBerubah(int? id) async {
    setStateIfMounted(() {
      _yayasanId = id;
      _sekolahId = null;
      _sekolah = [];
    });
    if (id == null) return;
    try {
      final data = await _ambilReferensi('sekolah', indukId: id);
      if (mounted) setStateIfMounted(() => _sekolah = data);
    } catch (_) {}
  }

  Future<void> _jalankan() async {
    final tahun = int.tryParse(_tahunController.text.trim());
    if (_koperasiId == null || tahun == null) {
      setStateIfMounted(
          () => _pesanError = 'Koperasi dan Tahun wajib diisi.');
      return;
    }
    setStateIfMounted(() {
      _menjalankan = true;
      _pesanError = null;
      _hasilTerakhir = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        _modeMahasiswa ? 'sinkron_mahasiswa' : 'sinkron_siswa',
        {
          'koperasi_id': _koperasiId,
          'tahun': tahun,
          if (_modeMahasiswa) 'fakultas_id': _fakultasId,
          if (_modeMahasiswa) 'jurusan_id': _jurusanId,
          if (!_modeMahasiswa) 'yayasan_id': _yayasanId,
          if (!_modeMahasiswa) 'sekolah_id': _sekolahId,
        },
      );
      if (mounted) setStateIfMounted(() => _hasilTerakhir = hasil);
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menjalankan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 48, color: AppColors.textSecondaryOf(context)),
              const SizedBox(height: 12),
              const Text(
                  'Hanya admin/manager atau supervisor toko yang dapat menjalankan sinkronisasi.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_memuatReferensi) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppSectionCard(
          judul: 'Sinkronisasi Siswa/Mahasiswa ke Anggota Koperasi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Buat/perbarui data member secara massal dari data master Mahasiswa/Siswa yang sudah ada. Anggota yang sudah ada akan disegarkan (nama/kontak) -- aman dijalankan berulang.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: true,
                      label: Text('Mahasiswa'),
                      icon: Icon(Icons.school_outlined)),
                  ButtonSegment(
                      value: false,
                      label: Text('Siswa'),
                      icon: Icon(Icons.backpack_outlined)),
                ],
                selected: {_modeMahasiswa},
                onSelectionChanged: (v) =>
                    setStateIfMounted(() => _modeMahasiswa = v.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                value: _koperasiId,
                decoration: AppFormStyle.fieldDecoration(context,
                    labelText: 'Koperasi *'),
                items: _koperasi
                    .map((k) => DropdownMenuItem<int?>(
                        value: k['id'] as int, child: Text('${k['nama']}')))
                    .toList(),
                onChanged: (v) => setStateIfMounted(() => _koperasiId = v),
              ),
              const SizedBox(height: 12),
              AppFormTextField(
                label: _modeMahasiswa
                    ? 'Tahun Angkatan *'
                    : 'Tahun Masuk *',
                controller: _tahunController,
                keyboardType: TextInputType.number,
              ),
              if (_modeMahasiswa) ...[
                DropdownButtonFormField<int?>(
                  value: _fakultasId,
                  decoration: AppFormStyle.fieldDecoration(context,
                      labelText: 'Fakultas (opsional, filter kandidat)'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('-- Semua Fakultas --')),
                    ..._fakultas.map((f) => DropdownMenuItem<int?>(
                        value: f['id'] as int, child: Text('${f['nama']}'))),
                  ],
                  onChanged: _saatFakultasBerubah,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _jurusanId,
                  decoration: AppFormStyle.fieldDecoration(context,
                      labelText: 'Jurusan (opsional)'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('-- Semua Jurusan --')),
                    ..._jurusan.map((j) => DropdownMenuItem<int?>(
                        value: j['id'] as int, child: Text('${j['nama']}'))),
                  ],
                  onChanged: (v) => setStateIfMounted(() => _jurusanId = v),
                ),
              ] else ...[
                DropdownButtonFormField<int?>(
                  value: _yayasanId,
                  decoration: AppFormStyle.fieldDecoration(context,
                      labelText: 'Yayasan (opsional, filter kandidat)'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('-- Semua Yayasan --')),
                    ..._yayasan.map((y) => DropdownMenuItem<int?>(
                        value: y['id'] as int, child: Text('${y['nama']}'))),
                  ],
                  onChanged: _saatYayasanBerubah,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _sekolahId,
                  decoration: AppFormStyle.fieldDecoration(context,
                      labelText: 'Sekolah (opsional)'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('-- Semua Sekolah --')),
                    ..._sekolah.map((s) => DropdownMenuItem<int?>(
                        value: s['id'] as int, child: Text('${s['nama']}'))),
                  ],
                  onChanged: (v) => setStateIfMounted(() => _sekolahId = v),
                ),
              ],
              const SizedBox(height: 16),
              if (_pesanError != null) ...[
                Text(_pesanError!,
                    style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _menjalankan ? null : _jalankan,
                  icon: _menjalankan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync),
                  label: Text(
                      _menjalankan ? 'Menjalankan...' : 'Jalankan Sinkronisasi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_hasilTerakhir != null) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            judul: 'Hasil Sinkronisasi Terakhir',
            child: Row(
              children: [
                Expanded(
                  child: AppKpiCard(
                    icon: Icons.groups_outlined,
                    warna: AppColors.primary,
                    nilai: '${_hasilTerakhir!['total'] ?? 0}',
                    label: 'Total Kandidat',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppKpiCard(
                    icon: Icons.check_circle_outline,
                    warna: AppColors.success,
                    nilai: '${_hasilTerakhir!['berhasil'] ?? 0}',
                    label: 'Berhasil',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppKpiCard(
                    icon: Icons.error_outline,
                    warna: AppColors.danger,
                    nilai: '${_hasilTerakhir!['gagal'] ?? 0}',
                    label: 'Gagal',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
