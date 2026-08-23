import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../models.dart';
import '../../services/master_offline.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../sesi.dart';
import '../../widgets/app_components.dart';
import '../../theme/app_colors.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Label chip "Hari Aktif" -- kunci ISO weekday (1=Senin..7=Minggu), SAMA
/// persis dgn konvensi CSV `hari_aktif` yg dibaca/dikirim server (lihat
/// JavaDoc AturanDiskon.getHariAktif()).
const _labelHari = {
  1: 'Senin',
  2: 'Selasa',
  3: 'Rabu',
  4: 'Kamis',
  5: 'Jumat',
  6: 'Sabtu',
  7: 'Minggu',
};

/// Tab 1/3 "Aturan Diskon" (padanan diskon.html/diskon-renderer.js Electron)
/// -- CRUD aturan diskon. Siapa saja bisa MELIHAT (aksi `diskon_list` tanpa
/// gate), tapi hanya admin/supervisor toko yang boleh Tambah/Ubah
/// (`diskon_simpan` digerbang server-side, dicerminkan di sini lewat
/// Sesi.instance.bolehKelola).
///
/// CATATAN paritas Electron: `diskon_list` TIDAK mengirim kodeProduk/tokoId/
/// jenisAnggotaId/tipeAnggotaId/maksimalPotongan/keterangan/berlakuSemuaMember/
/// berlakuPerHariDanPerToko -- jadi form "Ubah" sengaja mulai kosong utk
/// field-field itu (harus diisi ulang kalau mau diubah), persis perilaku
/// Electron, BUKAN bug.
class TabAturanDiskon extends StatefulWidget {
  const TabAturanDiskon({super.key});
  @override
  State<TabAturanDiskon> createState() => _TabAturanDiskonState();
}

class _TabAturanDiskonState extends State<TabAturanDiskon> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  List<Kategori> _jenisAnggota = [];
  List<Kategori> _tipeAnggota = [];
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      await Future.wait([_muatDaftar(), _muatDropdown()]);
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatDaftar() async {
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('diskon_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:diskon', onData: (hasil) {
        if (!mounted) return;
        final data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _data = data;
          _total = dariServer
              ? (hasil['total'] as num?)?.toInt() ?? data.length
              : data.length;
          _idBaru = dariServer
              ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(
                  hasil['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus =
              dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
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
      setStateIfMounted(() => _error = terapkanGalat(e));
    }
  }

  Future<void> _muatDropdown() async {
    try {
      final hasilJenis = await ApiClient.instance.aksi('jenis_anggota_list');
      final hasilTipe = await ApiClient.instance.aksi('tipe_anggota_list');
      if (mounted) {
        setStateIfMounted(() {
          _jenisAnggota = ((hasilJenis['data'] as List?) ?? [])
              .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
              .toList();
          _tipeAnggota = ((hasilTipe['data'] as List?) ?? [])
              .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
              .toList();
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
      builder: (_) => _FormDiskon(
          aturan: aturan,
          jenisAnggota: _jenisAnggota,
          tipeAnggota: _tipeAnggota),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Sesi.instance.bolehKelola
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Aturan'))
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
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        AppDetailGalatOpsional(detail: detailUntuk(_error)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _muatSemua,
                            child: const Text('Coba Lagi')),
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
                            SizedBox(
                                width: 190,
                                child: AppKpiCard(
                                    icon: Icons.sell_outlined,
                                    warna: AppColors.primary,
                                    nilai: '$_total',
                                    label: 'Total Aturan')),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 190,
                              child: AppKpiCard(
                                icon: Icons.check_circle_outline,
                                warna: AppColors.success,
                                nilai:
                                    '${_data.where((a) => a['aktif'] == true).length}',
                                label: 'Aktif (hal. ini)',
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 190,
                              child: AppKpiCard(
                                icon: Icons.percent_outlined,
                                warna: AppColors.teal,
                                nilai:
                                    '${_data.where((a) => a['potonganLangsung'] == true).length}',
                                label: 'Potong Struk (hal. ini)',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppSearchField(
                        hintText: 'Cari nama aturan...',
                        onChanged: _cariUlang,
                      ),
                      const SizedBox(height: 12),
                      BannerPerubahanServer(
                        key: ValueKey('perubahan:$_versiPerubahan'),
                        baru: _idBaru.length,
                        berubah: _idBerubah.length,
                        dihapus: _jumlahHapus,
                      ),
                      AppDataTable(
                        minWidth: 1128,
                        emptyText: 'Belum ada aturan diskon.',
                        columns: const [
                          AppTableColumn('Aturan', flex: 3),
                          AppTableColumn('Target', flex: 3),
                          AppTableColumn('Jenis', flex: 2),
                          AppTableColumn('Nilai',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Prioritas',
                              flex: 2, align: TextAlign.center),
                          AppTableColumn('Status',
                              flex: 2, align: TextAlign.center),
                          AppTableColumn('Aksi',
                              width: 48, align: TextAlign.center),
                        ],
                        rows: _data.map((a) {
                          final persen = ((a['persentase'] as num?) ?? 0);
                          final nilai = persen > 0
                              ? '$persen%'
                              : _formatRupiah.format(a['nominal'] ?? 0);
                          final produk =
                              (a['produkNama'] as String?)?.isNotEmpty == true
                                  ? a['produkNama']
                                  : 'Semua Produk';
                          final toko =
                              (a['tokoNama'] as String?)?.isNotEmpty == true
                                  ? a['tokoNama']
                                  : 'Semua Toko';
                          final aktif = a['aktif'] == true;
                          final manual = a['aktivasiManual'] == true;
                          return AppTableRowData(
                            onTap: Sesi.instance.bolehKelola
                                ? () => _bukaForm(aturan: a)
                                : null,
                            cells: [
                              AppTableCell(
                                flex: 3,
                                child: KilauBaris(
                                  kunci: '${a['id'] ?? a['_kunci'] ?? ''}',
                                  idBaru: _idBaru,
                                  idBerubah: _idBerubah,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IndikatorBarisSinkron(
                                          kunci:
                                              kunciBarisMaster('diskon', a)),
                                      Flexible(
                                        child: Text('${a['namaAturan']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      if (manual) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.touch_app_outlined,
                                            size: 14, color: AppColors.info),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              AppTableCell.text('$produk - $toko',
                                  flex: 3, maxLines: 2),
                              AppTableCell.text(
                                  a['potonganLangsung'] == true
                                      ? 'Potong Struk'
                                      : 'Cashback',
                                  flex: 2),
                              AppTableCell.text(nilai,
                                  flex: 2,
                                  align: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5)),
                              AppTableCell.text(
                                  '${a['prioritas'] ?? 100}${a['dapatDigabung'] == true ? ' • Gabung' : ' • Tunggal'}',
                                  flex: 2,
                                  align: TextAlign.center),
                              AppTableCell(
                                flex: 2,
                                align: TextAlign.center,
                                child: StatusPill(
                                    label: aktif ? 'Aktif' : 'Nonaktif',
                                    warna: aktif
                                        ? AppColors.success
                                        : AppColors.danger),
                              ),
                              AppTableCell(
                                width: 48,
                                align: TextAlign.center,
                                child: a['id'] != null
                                    ? IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip:
                                            'Riwayat data ini (AuditTrails)',
                                        icon: const Icon(Icons.history,
                                            size: 18),
                                        onPressed: () => tampilkanRiwayatData(
                                            context,
                                            entitas: 'diskon',
                                            id: a['id'],
                                            judul: '${a['namaAturan'] ?? ''}'),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }).toList(),
                        pagination: AppTablePagination(
                          halaman: _halaman,
                          totalHalaman: _totalHalaman,
                          totalData: _total,
                          labelData: 'aturan',
                          onSebelumnya:
                              _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                          onBerikutnya: _halaman < _totalHalaman
                              ? () => _pindah(_halaman + 1)
                              : null,
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
  const _FormDiskon(
      {required this.aturan,
      required this.jenisAnggota,
      required this.tipeAnggota});

  @override
  State<_FormDiskon> createState() => _FormDiskonState();
}

class _FormDiskonState extends State<_FormDiskon> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _kodeProduk;
  late final TextEditingController _persentase;
  late final TextEditingController _nominal;
  late final TextEditingController _maksimalPotongan;
  late final TextEditingController _prioritas;
  late final TextEditingController _grupEksklusif;
  late final TextEditingController _tokoId;
  bool _berlakuSemuaProduk = true;
  bool _berlakuSemuaMember = true;
  bool _potonganLangsung = true;
  bool _berlakuPerHariDanPerToko = false;
  bool _aktif = true;
  bool _aktivasiManual = false;
  bool _dapatDigabung = false;
  String _dasarPerhitungan = 'SETELAH_DISKON';
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

  // "Promo Pilih Hari" -- ISO weekday (1=Senin..7=Minggu), kosong = berlaku
  // SEMUA hari (sama konvensi dgn tanggal_mulai/tanggal_selesai kosong =
  // tanpa batas). Dikirim/dibaca CSV mis. "1,2,3,4,5" (lihat JavaDoc
  // AturanDiskon.getHariAktif() & KantinHelper.diskonSimpan/diskonList).
  final Set<int> _hariAktif = {};

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
    _prioritas = TextEditingController(text: '${a?['prioritas'] ?? 100}');
    _grupEksklusif =
        TextEditingController(text: '${a?['grupEksklusif'] ?? ''}');
    _tokoId = TextEditingController();
    _potonganLangsung = a?['potonganLangsung'] ?? true;
    _aktif = a?['aktif'] ?? true;
    _aktivasiManual = a?['aktivasiManual'] == true;
    _dapatDigabung = a?['dapatDigabung'] == true;
    _dasarPerhitungan = '${a?['dasarPerhitungan'] ?? 'SETELAH_DISKON'}';
    _berlakuSemuaProduk = (a?['produkNama'] as String?)?.isEmpty ?? true;
    _mulai = _uraiTanggalServer(a?['tanggalMulai'] as String?);
    _selesai = _uraiTanggalServer(a?['tanggalSelesai'] as String?);
    _hariAktif.addAll(_uraiHariAktif(a?['hariAktif'] as String?));
  }

  /// Urai CSV hari aktif (mis. "1,2,3,4,5") dari `diskon_list` -- entri yang
  /// tak valid/di luar 1-7 diabaikan diam-diam (defensif thd data lama/kotor).
  Set<int> _uraiHariAktif(String? s) {
    if (s == null || s.trim().isEmpty) return {};
    return s
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .where((h) => h >= 1 && h <= 7)
        .toSet();
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
      return DateTime(int.parse(tgl[2]), int.parse(tgl[1]), int.parse(tgl[0]),
          int.parse(jam[0]), int.parse(jam[1]));
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
    final tanggal = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (tanggal == null) return;
    if (!mounted) return;
    final jam = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(awal));
    final hasil = DateTime(tanggal.year, tanggal.month, tanggal.day,
        jam?.hour ?? 0, jam?.minute ?? 0);
    setStateIfMounted(() => mulai ? _mulai = hasil : _selesai = hasil);
  }

  @override
  void dispose() {
    _nama.dispose();
    _keterangan.dispose();
    _kodeProduk.dispose();
    _persentase.dispose();
    _nominal.dispose();
    _maksimalPotongan.dispose();
    _prioritas.dispose();
    _grupEksklusif.dispose();
    _tokoId.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final body = {
        if (widget.aturan != null) 'id': widget.aturan!['id'],
        'nama_aturan': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'berlaku_semua_produk': _berlakuSemuaProduk,
        if (!_berlakuSemuaProduk) 'kode_produk': _kodeProduk.text.trim(),
        'berlaku_semua_member': _berlakuSemuaMember,
        if (!_berlakuSemuaMember) 'jenis_anggota_id': _jenisAnggotaId,
        if (!_berlakuSemuaMember) 'tipe_anggota_id': _tipeAnggotaId,
        'persentase':
            double.tryParse(_persentase.text.replaceAll(',', '.')) ?? 0,
        'nominal': double.tryParse(_nominal.text.replaceAll(',', '.')) ?? 0,
        'maksimal_potongan':
            double.tryParse(_maksimalPotongan.text.replaceAll(',', '.')) ?? 0,
        'prioritas': int.tryParse(_prioritas.text) ?? 100,
        'dapat_digabung': _dapatDigabung,
        'dasar_perhitungan': _dasarPerhitungan,
        'grup_eksklusif': _grupEksklusif.text.trim(),
        'potongan_langsung': _potonganLangsung,
        'berlaku_per_hari_dan_per_toko': _berlakuPerHariDanPerToko,
        'aktif': _aktif,
        'aktivasi_manual': _aktivasiManual,
        'tanggal_mulai': _mulai == null ? '' : _formatUntukSimpan(_mulai!),
        'tanggal_selesai':
            _selesai == null ? '' : _formatUntukSimpan(_selesai!),
        'hari_aktif':
            _hariAktif.isEmpty ? '' : (_hariAktif.toList()..sort()).join(','),
        if (Sesi.instance.isAdmin)
          'toko_id': _tokoId.text.trim().isEmpty ? null : _tokoId.text.trim(),
      };
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'diskon_simpan',
        body: body,
        kunci: widget.aturan != null
            ? 'diskon:${widget.aturan!['id']}'
            : 'diskon:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:diskon',
        rowLokal: body,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.aturan != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          // AppFormSheet menempatkan actions setelah children secara semantik.
          // ignore: sort_child_properties_last
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Aturan Diskon' : 'Tambah Aturan Diskon',
            subtitle: ubah
                ? 'Target produk/member tidak ditampilkan ulang. Isi lagi bila ingin mengubah cakupannya.'
                : 'Susun aturan potongan yang akan dipakai saat transaksi kasir.',
            icon: ubah ? Icons.edit_calendar_outlined : Icons.discount_outlined,
            errorText: _error,
            errorDetail: detailUntuk(_error),
            // ignore: sort_child_properties_last
            children: [
              AppFormSection(
                judul: 'Informasi Aturan',
                children: [
                  AppFormTextField(
                    label: 'Nama Aturan *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                    maxLines: 2,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Target Diskon',
                children: [
                  AppFormSwitchTile(
                    title: 'Berlaku Semua Produk',
                    value: _berlakuSemuaProduk,
                    onChanged: (v) =>
                        setStateIfMounted(() => _berlakuSemuaProduk = v),
                  ),
                  if (!_berlakuSemuaProduk)
                    AppFormTextField(
                      label: 'Kode Produk Target *',
                      controller: _kodeProduk,
                      validator: (v) => (!_berlakuSemuaProduk &&
                              (v == null || v.trim().isEmpty))
                          ? 'Wajib diisi'
                          : null,
                    ),
                  AppFormSwitchTile(
                    title: 'Berlaku Semua Member',
                    value: _berlakuSemuaMember,
                    onChanged: (v) =>
                        setStateIfMounted(() => _berlakuSemuaMember = v),
                  ),
                  if (!_berlakuSemuaMember) ...[
                    DropdownButtonFormField<int?>(
                      value: _jenisAnggotaId,
                      decoration: AppFormStyle.fieldDecoration(
                        context,
                        labelText: 'Jenis Anggota',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('-- Semua Jenis --')),
                        ...widget.jenisAnggota.map((k) =>
                            DropdownMenuItem<int?>(
                                value: k.id, child: Text(k.nama))),
                      ],
                      onChanged: (v) =>
                          setStateIfMounted(() => _jenisAnggotaId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _tipeAnggotaId,
                      decoration: AppFormStyle.fieldDecoration(
                        context,
                        labelText: 'Tipe Anggota',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('-- Semua Tipe --')),
                        ...widget.tipeAnggota.map((k) => DropdownMenuItem<int?>(
                            value: k.id, child: Text(k.nama))),
                      ],
                      onChanged: (v) =>
                          setStateIfMounted(() => _tipeAnggotaId = v),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Nilai Potongan',
                children: [
                  AppFormSwitchTile(
                    title: 'Potong Langsung di Struk',
                    subtitle: 'Kalau mati, disimpan sebagai cashback/saldo.',
                    value: _potonganLangsung,
                    onChanged: (v) =>
                        setStateIfMounted(() => _potonganLangsung = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AppFormTextField(
                          label: 'Persentase (%)',
                          controller: _persentase,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppFormTextField(
                          label: 'Nominal (Rp)',
                          controller: _nominal,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                    ],
                  ),
                  AppFormTextField(
                    label: 'Maksimal Potongan (Rp, 0=tanpa batas)',
                    controller: _maksimalPotongan,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  AppFormSwitchTile(
                    title: 'Boleh Digabung dengan Promo Lain',
                    subtitle:
                        'Default mati. Jika aktif, promo dihitung menurut prioritas terbesar lebih dahulu.',
                    value: _dapatDigabung,
                    onChanged: (v) =>
                        setStateIfMounted(() => _dapatDigabung = v),
                  ),
                  Row(children: [
                    Expanded(
                      child: AppFormTextField(
                        label: 'Prioritas (lebih besar lebih dahulu)',
                        controller: _prioritas,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _dasarPerhitungan,
                        decoration: AppFormStyle.fieldDecoration(context,
                            labelText: 'Dasar Perhitungan'),
                        items: const [
                          DropdownMenuItem(
                              value: 'SETELAH_DISKON',
                              child: Text('Harga setelah diskon')),
                          DropdownMenuItem(
                              value: 'HARGA_AWAL', child: Text('Harga awal')),
                        ],
                        onChanged: (v) => setStateIfMounted(
                            () => _dasarPerhitungan = v ?? 'SETELAH_DISKON'),
                      ),
                    ),
                  ]),
                  AppFormTextField(
                    label: 'Grup Eksklusif (opsional)',
                    controller: _grupEksklusif,
                    helperText:
                        'Promo dengan kode grup yang sama tidak boleh ditumpuk.',
                  ),
                  AppFormSwitchTile(
                    title: 'Berlaku Per Hari & Per Toko',
                    value: _berlakuPerHariDanPerToko,
                    onChanged: (v) =>
                        setStateIfMounted(() => _berlakuPerHariDanPerToko = v),
                  ),
                  AppFormSwitchTile(
                    title: 'Aktivasi Manual',
                    subtitle:
                        'Kalau aktif, promo TIDAK otomatis diterapkan -- kasir pilih sendiri lewat tombol Promo saat checkout.',
                    value: _aktivasiManual,
                    onChanged: (v) =>
                        setStateIfMounted(() => _aktivasiManual = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Masa Berlaku',
                deskripsi: 'Kosongkan tanggal untuk aturan tanpa batas waktu.',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pilihTanggalJam(mulai: true),
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            _mulai == null
                                ? 'Mulai'
                                : '${_mulai!.day}-${_mulai!.month}-${_mulai!.year} ${_mulai!.hour.toString().padLeft(2, '0')}:${_mulai!.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_mulai != null)
                        IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () =>
                                setStateIfMounted(() => _mulai = null)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pilihTanggalJam(mulai: false),
                          icon: const Icon(Icons.event_busy, size: 16),
                          label: Text(
                            _selesai == null
                                ? 'Selesai'
                                : '${_selesai!.day}-${_selesai!.month}-${_selesai!.year} ${_selesai!.hour.toString().padLeft(2, '0')}:${_selesai!.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_selesai != null)
                        IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () =>
                                setStateIfMounted(() => _selesai = null)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Hari Aktif',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryOf(context))),
                      TextButton(
                        onPressed: _hariAktif.isEmpty
                            ? null
                            : () => setStateIfMounted(() => _hariAktif.clear()),
                        child: const Text('Pilih Semua Hari',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _labelHari.entries.map((e) {
                      final terpilih = _hariAktif.contains(e.key);
                      return FilterChip(
                        label: Text(e.value),
                        selected: terpilih,
                        onSelected: (v) => setStateIfMounted(() {
                          if (v) {
                            _hariAktif.add(e.key);
                          } else {
                            _hariAktif.remove(e.key);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _hariAktif.isEmpty
                          ? 'Kosong = berlaku SEMUA hari.'
                          : 'Hanya berlaku pada hari yang dipilih.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                  if (Sesi.instance.isAdmin) ...[
                    const SizedBox(height: 12),
                    AppFormTextField(
                      label: 'Target Toko (ID, kosongkan = semua toko)',
                      controller: _tokoId,
                      keyboardType: TextInputType.number,
                      helperText:
                          'Akun toko akan tetap otomatis diarahkan ke tokonya sendiri.',
                    ),
                  ],
                  AppFormSwitchTile(
                    title: 'Aktif',
                    value: _aktif,
                    onChanged: (v) => setStateIfMounted(() => _aktif = v),
                  ),
                ],
              ),
            ],
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
          ),
        ),
      ),
    );
  }
}
