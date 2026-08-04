import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../theme/app_colors.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar Diskon / Aturan Diskon (padanan diskon.html/diskon-renderer.js
/// Electron) -- CRUD aturan diskon. Siapa saja bisa MELIHAT (aksi
/// `diskon_list` tanpa gate), tapi hanya admin/supervisor toko yang boleh
/// Tambah/Ubah (`diskon_simpan` digerbang server-side, dicerminkan di sini
/// lewat Sesi.instance.bolehKelola).
///
/// CATATAN paritas Electron: `diskon_list` TIDAK mengirim kodeProduk/tokoId/
/// jenisAnggotaId/tipeAnggotaId/maksimalPotongan/keterangan/berlakuSemuaMember/
/// berlakuPerHariDanPerToko -- jadi form "Ubah" sengaja mulai kosong utk
/// field-field itu (harus diisi ulang kalau mau diubah), persis perilaku
/// Electron, BUKAN bug.
class DiskonScreen extends StatefulWidget {
  const DiskonScreen({super.key});
  @override
  State<DiskonScreen> createState() => _DiskonScreenState();
}

class _DiskonScreenState extends State<DiskonScreen> {
  static const _pageSize = 20;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  List<Kategori> _jenisAnggota = [];
  List<Kategori> _tipeAnggota = [];

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  Future<void> _muatSemua() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      await Future.wait([_muatDaftar(), _muatDropdown()]);
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _muatDaftar() async {
    try {
      final hasil = await ApiClient.instance.aksi('diskon_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      });
      setState(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _muatDropdown() async {
    try {
      final hasilJenis = await ApiClient.instance.aksi('jenis_anggota_list');
      final hasilTipe = await ApiClient.instance.aksi('tipe_anggota_list');
      if (mounted) {
        setState(() {
          _jenisAnggota = ((hasilJenis['data'] as List?) ?? []).map((e) => Kategori.fromJson(e as Map<String, dynamic>)).toList();
          _tipeAnggota = ((hasilTipe['data'] as List?) ?? []).map((e) => Kategori.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {
      // Dropdown gagal muat bukan blocker -- form tetap bisa dipakai tanpa target jenis/tipe anggota.
    }
  }

  Future<void> _cariUlang(String v) async {
    _kataKunci = v;
    _halaman = 1;
    await _muatDaftar();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muatDaftar();
  }

  Future<void> _bukaForm({Map<String, dynamic>? aturan}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormDiskon(aturan: aturan, jenisAnggota: _jenisAnggota, tipeAnggota: _tipeAnggota),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.diskon,
      judul: 'Aturan Diskon',
      subjudul: 'Kelola aturan diskon dan cashback',
      scrollable: false,
      actionsAppBar: [IconButton(icon: const Icon(Icons.refresh), onPressed: _muatSemua)],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muatSemua),
      floatingActionButton: Sesi.instance.bolehKelola
          ? FloatingActionButton.extended(onPressed: () => _bukaForm(), icon: const Icon(Icons.add), label: const Text('Tambah Aturan'))
          : null,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : RefreshIndicator(
                  onRefresh: _muatSemua,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      SizedBox(
                        height: 96,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            SizedBox(width: 190, child: AppKpiCard(icon: Icons.sell_outlined, warna: AppColors.primary, nilai: '$_total', label: 'Total Aturan')),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 190,
                              child: AppKpiCard(
                                icon: Icons.check_circle_outline,
                                warna: AppColors.success,
                                nilai: '${_data.where((a) => a['aktif'] == true).length}',
                                label: 'Aktif (hal. ini)',
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 190,
                              child: AppKpiCard(
                                icon: Icons.percent_outlined,
                                warna: AppColors.teal,
                                nilai: '${_data.where((a) => a['potonganLangsung'] == true).length}',
                                label: 'Potong Struk (hal. ini)',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(hintText: 'Cari nama aturan...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                        onSubmitted: _cariUlang,
                      ),
                      const SizedBox(height: 12),
                      if (_data.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Belum ada aturan diskon.')))
                      else
                        ..._data.map((a) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text('${a['namaAturan']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${(a['produkNama'] as String?)?.isNotEmpty == true ? a['produkNama'] : "Semua Produk"} · ${(a['tokoNama'] as String?)?.isNotEmpty == true ? a['tokoNama'] : "Semua Toko"}\n'
                                  '${a['potonganLangsung'] == true ? "Potong Struk" : "Cashback"}: ${((a['persentase'] as num?) ?? 0) > 0 ? "${a['persentase']}%" : _formatRupiah.format(a['nominal'] ?? 0)}',
                                ),
                                isThreeLine: true,
                                trailing: Text(a['aktif'] == true ? 'Aktif' : 'Nonaktif', style: TextStyle(color: a['aktif'] == true ? const Color(0xFF2E7D32) : Colors.red, fontSize: 12)),
                                onTap: Sesi.instance.bolehKelola ? () => _bukaForm(aturan: a) : null,
                              ),
                            )),
                      if (_total > _pageSize)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _halaman > 1 ? () => _pindah(_halaman - 1) : null),
                              Text('Halaman $_halaman / $_totalHalaman ($_total aturan)'),
                              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _FormDiskon extends StatefulWidget {
  final Map<String, dynamic>? aturan;
  final List<Kategori> jenisAnggota;
  final List<Kategori> tipeAnggota;
  const _FormDiskon({required this.aturan, required this.jenisAnggota, required this.tipeAnggota});

  @override
  State<_FormDiskon> createState() => _FormDiskonState();
}

class _FormDiskonState extends State<_FormDiskon> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _kodeProduk;
  late final TextEditingController _persentase;
  late final TextEditingController _nominal;
  late final TextEditingController _maksimalPotongan;
  late final TextEditingController _tokoId;
  bool _berlakuSemuaProduk = true;
  bool _berlakuSemuaMember = true;
  bool _potonganLangsung = true;
  bool _berlakuPerHariDanPerToko = false;
  bool _aktif = true;
  int? _jenisAnggotaId;
  int? _tipeAnggotaId;
  bool _menyimpan = false;
  String? _error;

  // Masa Berlaku -- `null` = tanpa batas (dikirim kosong ke server, cocok
  // dgn `diskonSimpan` yg menganggap tanggal_mulai/tanggal_selesai kosong
  // sbg tak dibatasi). Toko-scoped user (bukan admin) SELALU dipaksa server
  // ke tokonya sendiri (lihat JavaDoc `diskonSimpan`), jadi field Target Toko
  // hanya relevan/ditampilkan utk admin global.
  DateTime? _mulai;
  DateTime? _selesai;

  @override
  void initState() {
    super.initState();
    final a = widget.aturan;
    _nama = TextEditingController(text: a?['namaAturan'] ?? '');
    _keterangan = TextEditingController();
    _kodeProduk = TextEditingController();
    _persentase = TextEditingController(text: '${a?['persentase'] ?? 0}');
    _nominal = TextEditingController(text: '${a?['nominal'] ?? 0}');
    _maksimalPotongan = TextEditingController();
    _tokoId = TextEditingController();
    _potonganLangsung = a?['potonganLangsung'] ?? true;
    _aktif = a?['aktif'] ?? true;
    _berlakuSemuaProduk = (a?['produkNama'] as String?)?.isEmpty ?? true;
    _mulai = _uraiTanggalServer(a?['tanggalMulai'] as String?);
    _selesai = _uraiTanggalServer(a?['tanggalSelesai'] as String?);
  }

  /// Urai format tampilan server ("dd-MM-yyyy HH:mm" dari `diskon_list`) --
  /// BEDA dari format yg diharapkan `diskon_simpan` ("yyyy-MM-ddTHH:mm"),
  /// lihat [_formatUntukSimpan].
  DateTime? _uraiTanggalServer(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      final bagian = s.trim().split(' ');
      final tgl = bagian[0].split('-');
      final jam = bagian.length > 1 ? bagian[1].split(':') : ['0', '0'];
      return DateTime(int.parse(tgl[2]), int.parse(tgl[1]), int.parse(tgl[0]), int.parse(jam[0]), int.parse(jam[1]));
    } catch (_) {
      return null;
    }
  }

  String _formatUntukSimpan(DateTime d) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${pad(d.month)}-${pad(d.day)}T${pad(d.hour)}:${pad(d.minute)}';
  }

  Future<void> _pilihTanggalJam({required bool mulai}) async {
    final awal = (mulai ? _mulai : _selesai) ?? DateTime.now();
    final tanggal = await showDatePicker(context: context, initialDate: awal, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (tanggal == null) return;
    if (!mounted) return;
    final jam = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(awal));
    final hasil = DateTime(tanggal.year, tanggal.month, tanggal.day, jam?.hour ?? 0, jam?.minute ?? 0);
    setState(() => mulai ? _mulai = hasil : _selesai = hasil);
  }

  @override
  void dispose() {
    _nama.dispose();
    _keterangan.dispose();
    _kodeProduk.dispose();
    _persentase.dispose();
    _nominal.dispose();
    _maksimalPotongan.dispose();
    _tokoId.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      await ApiClient.instance.aksi('diskon_simpan', {
        if (widget.aturan != null) 'id': widget.aturan!['id'],
        'nama_aturan': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'berlaku_semua_produk': _berlakuSemuaProduk,
        if (!_berlakuSemuaProduk) 'kode_produk': _kodeProduk.text.trim(),
        'berlaku_semua_member': _berlakuSemuaMember,
        if (!_berlakuSemuaMember) 'jenis_anggota_id': _jenisAnggotaId,
        if (!_berlakuSemuaMember) 'tipe_anggota_id': _tipeAnggotaId,
        'persentase': double.tryParse(_persentase.text.replaceAll(',', '.')) ?? 0,
        'nominal': double.tryParse(_nominal.text.replaceAll(',', '.')) ?? 0,
        'maksimal_potongan': double.tryParse(_maksimalPotongan.text.replaceAll(',', '.')) ?? 0,
        'potongan_langsung': _potonganLangsung,
        'berlaku_per_hari_dan_per_toko': _berlakuPerHariDanPerToko,
        'aktif': _aktif,
        'tanggal_mulai': _mulai == null ? '' : _formatUntukSimpan(_mulai!),
        'tanggal_selesai': _selesai == null ? '' : _formatUntukSimpan(_selesai!),
        if (Sesi.instance.isAdmin) 'toko_id': _tokoId.text.trim().isEmpty ? null : _tokoId.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.aturan != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(ubah ? 'Ubah Aturan Diskon' : 'Tambah Aturan Diskon', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (ubah)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Target produk/member tidak ditampilkan ulang -- isi lagi kalau ingin diubah.', style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                ),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(labelText: 'Nama Aturan *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _keterangan, decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder()), maxLines: 2),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Berlaku Semua Produk'),
                value: _berlakuSemuaProduk,
                onChanged: (v) => setState(() => _berlakuSemuaProduk = v),
              ),
              if (!_berlakuSemuaProduk)
                TextFormField(
                  controller: _kodeProduk,
                  decoration: const InputDecoration(labelText: 'Kode Produk Target *', border: OutlineInputBorder()),
                  validator: (v) => (!_berlakuSemuaProduk && (v == null || v.trim().isEmpty)) ? 'Wajib diisi' : null,
                ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Berlaku Semua Member'),
                value: _berlakuSemuaMember,
                onChanged: (v) => setState(() => _berlakuSemuaMember = v),
              ),
              if (!_berlakuSemuaMember) ...[
                DropdownButtonFormField<int?>(
                  value: _jenisAnggotaId,
                  decoration: const InputDecoration(labelText: 'Jenis Anggota', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('-- Semua Jenis --')),
                    ...widget.jenisAnggota.map((k) => DropdownMenuItem<int?>(value: k.id, child: Text(k.nama))),
                  ],
                  onChanged: (v) => setState(() => _jenisAnggotaId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _tipeAnggotaId,
                  decoration: const InputDecoration(labelText: 'Tipe Anggota', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('-- Semua Tipe --')),
                    ...widget.tipeAnggota.map((k) => DropdownMenuItem<int?>(value: k.id, child: Text(k.nama))),
                  ],
                  onChanged: (v) => setState(() => _tipeAnggotaId = v),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Potong Langsung di Struk'),
                subtitle: const Text('Kalau mati, disimpan sbg cashback/saldo.', style: TextStyle(fontSize: 11)),
                value: _potonganLangsung,
                onChanged: (v) => setState(() => _potonganLangsung = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _persentase,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Persentase (%)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _nominal,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Nominal (Rp)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maksimalPotongan,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Maksimal Potongan (Rp, 0=tanpa batas)', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Berlaku Per Hari & Per Toko'),
                value: _berlakuPerHariDanPerToko,
                onChanged: (v) => setState(() => _berlakuPerHariDanPerToko = v),
              ),
              const SizedBox(height: 12),
              const Text('Masa Berlaku (kosongkan = tanpa batas)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pilihTanggalJam(mulai: true),
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(_mulai == null ? 'Mulai' : '${_mulai!.day}-${_mulai!.month}-${_mulai!.year} ${_mulai!.hour.toString().padLeft(2, '0')}:${_mulai!.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  if (_mulai != null) IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _mulai = null)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pilihTanggalJam(mulai: false),
                      icon: const Icon(Icons.event_busy, size: 16),
                      label: Text(_selesai == null ? 'Selesai' : '${_selesai!.day}-${_selesai!.month}-${_selesai!.year} ${_selesai!.hour.toString().padLeft(2, '0')}:${_selesai!.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  if (_selesai != null) IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _selesai = null)),
                ],
              ),
              if (Sesi.instance.isAdmin) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tokoId,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Toko (ID, kosongkan = semua toko)',
                    helperText: 'Hanya admin/manager yg bisa memilih toko tertentu -- akun toko selalu otomatis ke tokonya sendiri.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktif'), value: _aktif, onChanged: (v) => setState(() => _aktif = v)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _menyimpan ? null : _simpan,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _menyimpan ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
