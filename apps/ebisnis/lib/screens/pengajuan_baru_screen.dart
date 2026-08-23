import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/app_components.dart';
import '../api_client.dart';
import '../services/unggah_lampiran_sop.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

/// Wizard **"Pengajuan Baru"** -- mengajukan satu SOP dari POS Desktop & Android.
///
/// Padanan tombol "Tambah" pada `DisposisiSopAction.java` versi ZKoss, dijalankan
/// seluruhnya lewat API (`sop_jenis`, `sop_mulai_info`, `sop_cari_entitas`,
/// `sop_ajukan`) yang dilayani `SopService.java`. Tanpa iframe, tanpa webview.
///
/// Tiga langkah, mengikuti urutan versi ZKoss:
///
/// 1. **Pilih jenis SOP** -- hanya SOP yang benar-benar boleh DIMULAI oleh
///    pengguna ini; daftarnya dihitung server (`daftarSopBisaDiajukan`), bukan
///    disaring di klien.
/// 2. **Isi pengajuan** -- catatan, tindak lanjut, isian tambahan, dokumen, dan
///    (bila SOP ini punya `formInputan`) form data dinamis milik entitas
///    `FormSop`-nya.
/// 3. **Kirim** -- satu panggilan `sop_ajukan` yang di server berjalan dalam
///    SATU transaksi atomik.
///
/// <h3>Lampiran sebelum dokumen ada</h3>
/// Dokumen dan lampiran diunggah SEBELUM pengajuan tersimpan, memakai
/// `refSementara`: id placeholder negatif yang diterbitkan `sop_mulai_info` dan
/// dipetakan ulang ke id tahap awal yang sebenarnya oleh `sop_ajukan`. Itu pola
/// yang sama dengan `ref = -Common.randLong()` di versi ZKoss -- bukan akal-akalan
/// sisi klien.
///
/// Seperti layar disposisi, wizard ini TIDAK mengantre luring: pengajuan baru
/// bergantung pada hak akses dan definisi alur saat itu juga, dan lampirannya
/// sudah lebih dulu berada di server.
class PengajuanBaruScreen extends StatefulWidget {
  const PengajuanBaruScreen({super.key});

  @override
  State<PengajuanBaruScreen> createState() => _PengajuanBaruScreenState();
}

class _PengajuanBaruScreenState extends State<PengajuanBaruScreen> {
  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;
  List<Map<String, dynamic>> _jenis = const [];
  String _cari = '';

  @override
  void initState() {
    super.initState();
    _muatJenis();
  }

  Future<void> _muatJenis() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await ApiClient.instance.aksi('sop_jenis', const {});
      if (!mounted) return;
      final list = ((r['list'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setStateIfMounted(() {
        _jenis = list;
        if (list.isEmpty) {
          _galat = '${r['message'] ?? 'Tidak ada jenis SOP yang dapat Anda ajukan.'}';
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

  Future<void> _pilihSop(Map<String, dynamic> sop) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final r = await ApiClient.instance
          .aksi('sop_mulai_info', {'sopId': '${sop['id']}'});
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      if (!sukses) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['message'] ?? 'Gagal menyiapkan pengajuan.'}'),
            backgroundColor: Theme.of(context).colorScheme.error));
        return;
      }
      final info = Map<String, dynamic>.from((r['data'] as Map?) ?? const {});
      if (!mounted) return;
      final hasil = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => _FormPengajuanBaru(info: info)),
      );
      if (hasil != null && mounted) Navigator.of(context).pop(hasil);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kata = _cari.trim().toLowerCase();
    final tersaring = kata.isEmpty
        ? _jenis
        : _jenis
            .where((s) =>
                '${s['nama']} ${s['kode']} ${s['jenisSop']} ${s['keterangan']}'
                    .toLowerCase()
                    .contains(kata))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Pengajuan Baru'),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: AppSearchField(
                  hintText: 'Cari jenis SOP',
                  debounce: Duration.zero,
                  onChanged: (v) => setState(() => _cari = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Hanya SOP yang boleh Anda mulai yang ditampilkan di sini.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryOf(context))),
                ),
              ),
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : tersaring.isEmpty
                        ? _kosong()
                        : RefreshIndicator(
                            onRefresh: _muatJenis,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(14),
                              itemCount: tersaring.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _kartuSop(tersaring[i]),
                            ),
                          ),
              ),
            ],
          ),
          if (_sibuk)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _kosong() => ListView(
        children: [
          const SizedBox(height: 60),
          Icon(Icons.inbox_outlined,
              size: 44, color: AppColors.textSecondaryOf(context)),
          const SizedBox(height: 10),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(_galat ?? 'Tidak ada jenis SOP yang cocok.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context))),
            ),
          ),
        ],
      );

  Widget _kartuSop(Map<String, dynamic> s) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _sibuk ? null : () => _pilihSop(s),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardBgOf(context),
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.primary),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.assignment_outlined,
                    size: 19, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s['nama'] ?? '-'}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    if ('${s['jenisSop'] ?? ''}'.isNotEmpty ||
                        '${s['kode'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            [
                              if ('${s['kode'] ?? ''}'.isNotEmpty) '${s['kode']}',
                              if ('${s['jenisSop'] ?? ''}'.isNotEmpty)
                                '${s['jenisSop']}',
                            ].join('  •  '),
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(context))),
                      ),
                    if ('${s['keterangan'] ?? ''}'.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${s['keterangan']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(context))),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textSecondaryOf(context)),
            ],
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// LANGKAH 2 & 3 — ISI PENGAJUAN LALU KIRIM
// ════════════════════════════════════════════════════════════════════════════

class _FormPengajuanBaru extends StatefulWidget {
  final Map<String, dynamic> info;
  const _FormPengajuanBaru({required this.info});

  @override
  State<_FormPengajuanBaru> createState() => _FormPengajuanBaruState();
}

class _FormPengajuanBaruState extends State<_FormPengajuanBaru> {
  final _keterangan = TextEditingController();
  final Map<String, TextEditingController> _nilaiParam = {};
  final Map<String, TextEditingController> _nilaiForm = {};
  final Map<String, Map<String, dynamic>> _relasiDipilih = {};
  final Map<String, bool> _nilaiBoolean = {};
  final Map<String, DateTime> _nilaiTanggal = {};
  final Set<String> _alurDipilih = {};
  final Map<String, String> _berkasTerunggah = {};

  bool _mengunggah = false;
  bool _mengirim = false;
  String? _galat;

  List<Map<String, dynamic>> _petaList(String kunci) =>
      ((widget.info[kunci] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> get _opsi => _petaList('nextOptions');
  List<Map<String, dynamic>> get _param => _petaList('parameterDefinisi');
  List<Map<String, dynamic>> get _dokumen => _petaList('dokumenDefinisi');
  List<Map<String, dynamic>> get _formFields => _petaList('formFields');

  bool get _tunggal => widget.info['berupaPilihanTunggal'] == true;
  bool get _opsiTidakWajib => widget.info['nextTidakWajib'] == true;
  bool get _catatanWajib => widget.info['catatanWajib'] == true;

  /// SOP boleh dikonfigurasi TANPA kolom catatan pada tahap awalnya (ZKoss
  /// menyembunyikan barisnya). Server lama yang belum mengirim kunci ini
  /// diperlakukan sebagai "boleh" -- sama dengan default entitasnya.
  bool get _bolehCatatan => widget.info['bolehDiisiCatatan'] != false;
  String get _ref => '${widget.info['refSementara']}';

  @override
  void initState() {
    super.initState();
    for (final p in _param) {
      _nilaiParam['${p['key']}'] =
          TextEditingController(text: '${p['nilaiDefault'] ?? ''}');
    }
    for (final f in _formFields) {
      final tipe = '${f['tipe']}';
      if (tipe == 'teks' || tipe == 'angka') {
        _nilaiForm['${f['property']}'] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _keterangan.dispose();
    for (final c in _nilaiParam.values) {
      c.dispose();
    }
    for (final c in _nilaiForm.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Lampiran ────────────────────────────────────────────────────────────

  Future<void> _pilihBerkas(String kunci) async {
    final hasil = await FilePicker.platform.pickFiles(withData: true);
    if (hasil == null || hasil.files.isEmpty) return;
    final berkas = hasil.files.single;
    final isi = berkas.bytes;
    if (isi == null || !mounted) return;
    setState(() => _mengunggah = true);
    final galat = await UnggahLampiranSop.unggah(
      ref: _ref,
      kunci: kunci,
      namaBerkas: berkas.name,
      isi: isi,
    );
    if (!mounted) return;
    setState(() {
      _mengunggah = false;
      if (galat == null) {
        _berkasTerunggah[kunci] = berkas.name;
        _galat = null;
      } else {
        _galat = galat;
      }
    });
  }

  // ── Picker relasi (sop_cari_entitas) ────────────────────────────────────

  Future<void> _pilihRelasi(Map<String, dynamic> f) async {
    final kelas = '${f['relasiClass'] ?? ''}';
    if (kelas.isEmpty) {
      setState(() => _galat =
          'Field "${f['label']}" tidak menyebutkan kelas relasinya, jadi belum bisa dipilih.');
      return;
    }
    final terpilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          DialogCariEntitas(judul: '${f['label']}', clazz: kelas),
    );
    if (terpilih == null || !mounted) return;
    setState(() => _relasiDipilih['${f['property']}'] = terpilih);
  }

  Future<void> _pilihTanggal(String property) async {
    final kini = DateTime.now();
    final hasil = await showDatePicker(
      context: context,
      initialDate: _nilaiTanggal[property] ?? kini,
      firstDate: DateTime(kini.year - 10),
      lastDate: DateTime(kini.year + 10),
    );
    if (hasil == null || !mounted) return;
    setState(() => _nilaiTanggal[property] = hasil);
  }

  // ── Validasi & kirim ────────────────────────────────────────────────────

  String? _periksa() {
    // Kewajiban catatan hanya berlaku bila kolomnya memang ditampilkan.
    if (_bolehCatatan && _catatanWajib && _keterangan.text.trim().isEmpty) {
      return 'Catatan/keterangan harus diisi.';
    }
    if (_alurDipilih.isEmpty && !_opsiTidakWajib && _opsi.isNotEmpty) {
      return 'Pilihan tindak lanjut/langkah berikutnya harus dipilih.';
    }
    for (final p in _param) {
      final kunci = '${p['key']}';
      if (p['wajib'] == true &&
          (_nilaiParam[kunci]?.text ?? '').trim().isEmpty) {
        return 'Isian "${p['label'] ?? p['nama'] ?? kunci}" wajib diisi.';
      }
      if (p['lampiranWajib'] == true && !_berkasTerunggah.containsKey(kunci)) {
        return 'Lampiran untuk "${p['label'] ?? p['nama'] ?? kunci}" wajib diunggah.';
      }
    }
    for (final d in _dokumen) {
      if (d['wajib'] == true && !_berkasTerunggah.containsKey('${d['key']}')) {
        return 'Dokumen "${d['nama'] ?? d['key']}" wajib diunggah.';
      }
    }
    if (widget.info['lampiranCatatanWajib'] == true &&
        !_berkasTerunggah.containsKey(_kunciLampiranCatatan)) {
      return 'Lampiran catatan disposisi wajib diunggah.';
    }
    for (final f in _formFields) {
      if (f['wajib'] != true) continue;
      final property = '${f['property']}';
      final tipe = '${f['tipe']}';
      final kosong = tipe == 'relasi'
          ? !_relasiDipilih.containsKey(property)
          : tipe == 'tanggal'
              ? !_nilaiTanggal.containsKey(property)
              : tipe == 'boolean'
                  ? false // boolean selalu punya nilai (false = tidak)
                  : (_nilaiForm[property]?.text ?? '').trim().isEmpty;
      if (kosong) return 'Isian "${f['label'] ?? property}" wajib diisi.';
    }
    return null;
  }

  static const String _kunciLampiranCatatan = 'Lampiran Catatan Disposisi';

  String _dua(int n) => n < 10 ? '0$n' : '$n';

  /// Server memakai `Common.dateFormat1` = `dd-MM-yyyy`.
  String _tglServer(DateTime d) =>
      '${_dua(d.day)}-${_dua(d.month)}-${d.year}';

  Map<String, dynamic> _bangunFormData() {
    final data = <String, dynamic>{};
    for (final f in _formFields) {
      final property = '${f['property']}';
      switch ('${f['tipe']}') {
        case 'relasi':
          final r = _relasiDipilih[property];
          if (r != null) data[property] = {'id': r['id']};
          break;
        case 'tanggal':
          final t = _nilaiTanggal[property];
          if (t != null) data[property] = _tglServer(t);
          break;
        case 'boolean':
          data[property] = (_nilaiBoolean[property] ?? false) ? 'true' : 'false';
          break;
        default:
          final v = _nilaiForm[property]?.text.trim() ?? '';
          if (v.isNotEmpty) data[property] = v;
      }
    }
    return data;
  }

  Future<void> _kirim() async {
    final galat = _periksa();
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    setState(() {
      _galat = null;
      _mengirim = true;
    });
    final body = <String, dynamic>{
      'sopId': '${widget.info['sopId']}',
      'refSementara': _ref,
      'keterangan': _keterangan.text.trim(),
      // Dikirim sebagai ANGKA: server membacanya dengan JSONArray.getLong.
      if (_alurDipilih.isNotEmpty)
        'alurSopIds': [
          for (final id in _alurDipilih) int.tryParse(id) ?? id,
        ],
      if (_param.isNotEmpty)
        'parameterTambahan': [
          for (final p in _param)
            {
              'kelompokId': p['kelompokId'],
              'parameterId': p['parameterId'],
              'nilai': _nilaiParam['${p['key']}']?.text.trim() ?? '',
              'catatan': '',
            }
        ],
    };
    final formData = _bangunFormData();
    if (formData.isNotEmpty) body['formData'] = formData;

    try {
      final r = await ApiClient.instance.aksi('sop_ajukan', body);
      if (!mounted) return;
      final sukses = r['status'] == '00' || r['status'] == 'success';
      if (!sukses) {
        setState(() {
          _galat = '${r['message'] ?? 'Pengajuan gagal disimpan.'}';
          _mengirim = false;
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${r['message'] ?? 'Pengajuan SOP berhasil disimpan'}')));
      Navigator.of(context).pop(<String, dynamic>{
        'disposisiSopId': r['disposisiSopId'],
        'disposisiAlurSopId': r['disposisiAlurSopId'],
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e';
        _mengirim = false;
      });
    }
  }

  // ── Tampilan ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: Text('${widget.info['sopNama'] ?? 'Pengajuan Baru'}',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _kotakTahap(),
              if (_galat != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.latarLembut(AppColors.danger),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(_galat!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger)),
                ),
              ],
              const SizedBox(height: 12),
              if (_bolehCatatan)
                _kotak(
                  judul: 'Catatan',
                  isi: TextField(
                  controller: _keterangan,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText:
                        'Catatan${_catatanWajib ? ' (wajib)' : ' (opsional)'}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (_formFields.isNotEmpty) ...[
                const SizedBox(height: 12),
                _kotak(
                  judul: '${widget.info['formIstilah'] ?? 'Data'}',
                  isi: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in _formFields) _isianForm(f),
                    ],
                  ),
                ),
              ],
              if (_opsi.isNotEmpty) ...[
                const SizedBox(height: 12),
                _kotak(
                  judul: _tunggal
                      ? 'Tindak Lanjut (pilih satu)'
                      : 'Tindak Lanjut (boleh lebih dari satu)',
                  isi: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        Text('Boleh dikosongkan pada SOP ini.',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondaryOf(context))),
                    ],
                  ),
                ),
              ],
              if (_param.isNotEmpty) ...[
                const SizedBox(height: 12),
                _kotak(
                  judul: 'Isian Tambahan',
                  isi: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in _param) _isianParameter(p),
                    ],
                  ),
                ),
              ],
              if (_dokumen.isNotEmpty ||
                  widget.info['lampiranCatatanWajib'] == true) ...[
                const SizedBox(height: 12),
                _kotak(
                  judul: 'Dokumen',
                  isi: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Berkas diunggah sekarang dan otomatis ditautkan ke '
                          'pengajuan begitu disimpan.',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context))),
                      for (final d in _dokumen)
                        _barisBerkas(
                            kunci: '${d['key']}',
                            label: '${d['nama'] ?? d['key']}',
                            wajib: d['wajib'] == true),
                      if (widget.info['lampiranCatatanWajib'] == true)
                        _barisBerkas(
                            kunci: _kunciLampiranCatatan,
                            label: _kunciLampiranCatatan,
                            wajib: true),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Ajukan'),
                onPressed: _mengirim || _mengunggah ? null : _kirim,
              ),
              const SizedBox(height: 28),
            ],
          ),
          if (_mengirim || _mengunggah)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _kotakTahap() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.teal],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TAHAP AWAL',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${widget.info['tahap'] ?? '-'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${widget.info['sopNama'] ?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      );

  Widget _kotak({required String judul, required Widget isi}) => Container(
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
            Text(judul,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            isi,
          ],
        ),
      );

  Widget _isianForm(Map<String, dynamic> f) {
    final property = '${f['property']}';
    final label =
        '${f['label'] ?? property}${f['wajib'] == true ? ' (wajib)' : ''}';
    switch ('${f['tipe']}') {
      case 'relasi':
        final dipilih = _relasiDipilih[property];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _pilihRelasi(f),
            borderRadius: BorderRadius.circular(6),
            child: InputDecorator(
              decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: const Icon(Icons.search, size: 18)),
              child: Text(
                  dipilih == null
                      ? 'Ketuk untuk memilih'
                      : '${dipilih['nama'] ?? dipilih['kode'] ?? dipilih['id']}',
                  style: TextStyle(
                      fontSize: 12,
                      color: dipilih == null
                          ? AppColors.textSecondaryOf(context)
                          : AppColors.textPrimaryOf(context))),
            ),
          ),
        );
      case 'tanggal':
        final t = _nilaiTanggal[property];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _pilihTanggal(property),
            borderRadius: BorderRadius.circular(6),
            child: InputDecorator(
              decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: const Icon(Icons.date_range, size: 18)),
              child: Text(t == null ? 'Ketuk untuk memilih' : _tglServer(t),
                  style: TextStyle(
                      fontSize: 12,
                      color: t == null
                          ? AppColors.textSecondaryOf(context)
                          : AppColors.textPrimaryOf(context))),
            ),
          ),
        );
      case 'boolean':
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _nilaiBoolean[property] ?? false,
          title: Text(label, style: const TextStyle(fontSize: 12)),
          onChanged: (v) =>
              setState(() => _nilaiBoolean[property] = v ?? false),
        );
      case 'angka':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _nilaiForm[property],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _nilaiForm[property],
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true),
          ),
        );
    }
  }

  Widget _isianParameter(Map<String, dynamic> p) {
    final kunci = '${p['key']}';
    final pilihan = '${p['pilihan'] ?? ''}'
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final label =
        '${p['label'] ?? p['nama'] ?? kunci}${p['wajib'] == true ? ' (wajib)' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                wajib: p['lampiranWajib'] == true),
        ],
      ),
    );
  }

  Widget _barisBerkas(
      {required String kunci, required String label, required bool wajib}) {
    final terunggah = _berkasTerunggah[kunci];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
            onPressed: _mengunggah ? null : () => _pilihBerkas(kunci),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PICKER RELASI — sop_cari_entitas
// ════════════════════════════════════════════════════════════════════════════

/// Pencarian entitas generik. Dipakai untuk field bertipe "relasi" pada form
/// data dinamis, DAN untuk memilih Satuan Kerja pada filter dasbor. Server sengaja menyediakan SATU endpoint untuk semua jenis relasi
/// (divalidasi lewat metadata Hibernate, bukan dengan meng-instantiate kelas
/// sembarangan dari input pengguna), sehingga picker ini pun cukup satu.
class DialogCariEntitas extends StatefulWidget {
  final String judul;
  final String clazz;
  const DialogCariEntitas(
      {super.key, required this.judul, required this.clazz});

  @override
  State<DialogCariEntitas> createState() => DialogCariEntitasState();
}

class DialogCariEntitasState extends State<DialogCariEntitas> {
  final _cari = TextEditingController();
  bool _memuat = false;
  String? _galat;
  List<Map<String, dynamic>> _hasil = const [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await ApiClient.instance.aksi('sop_cari_entitas',
          {'clazz': widget.clazz, 'keyword': _cari.text.trim()});
      if (!mounted) return;
      final list = ((r['list'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setStateIfMounted(() {
        _hasil = list;
        if (list.isEmpty) {
          _galat = '${r['message'] ?? 'Tidak ada data yang cocok.'}';
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

  @override
  Widget build(BuildContext context) {
    final lebar = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text('Pilih ${widget.judul}', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: lebar > 620 ? 520 : lebar * 0.9,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _cari,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Ketik lalu tekan Enter',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    onPressed: _muat),
              ),
              onSubmitted: (_) => _muat(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _hasil.isEmpty
                      ? Center(
                          child: Text(_galat ?? 'Tidak ada data.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      AppColors.textSecondaryOf(context))),
                        )
                      : ListView.builder(
                          itemCount: _hasil.length,
                          itemBuilder: (_, i) {
                            final e = _hasil[i];
                            return ListTile(
                              dense: true,
                              title: Text('${e['nama'] ?? '-'}',
                                  style: const TextStyle(fontSize: 12)),
                              subtitle: '${e['kode'] ?? ''}'.isEmpty
                                  ? null
                                  : Text('${e['kode']}',
                                      style: const TextStyle(fontSize: 11)),
                              onTap: () => Navigator.pop(context, e),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
      ],
    );
  }
}
