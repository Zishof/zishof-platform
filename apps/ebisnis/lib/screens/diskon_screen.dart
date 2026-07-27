import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Aturan Diskon'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _muatSemua)]),
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
  bool _berlakuSemuaProduk = true;
  bool _berlakuSemuaMember = true;
  bool _potonganLangsung = true;
  bool _berlakuPerHariDanPerToko = false;
  bool _aktif = true;
  int? _jenisAnggotaId;
  int? _tipeAnggotaId;
  bool _menyimpan = false;
  String? _error;

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
    _potonganLangsung = a?['potonganLangsung'] ?? true;
    _aktif = a?['aktif'] ?? true;
    _berlakuSemuaProduk = (a?['produkNama'] as String?)?.isEmpty ?? true;
  }

  @override
  void dispose() {
    _nama.dispose();
    _keterangan.dispose();
    _kodeProduk.dispose();
    _persentase.dispose();
    _nominal.dispose();
    _maksimalPotongan.dispose();
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
