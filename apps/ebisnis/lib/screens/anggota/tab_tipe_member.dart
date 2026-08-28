import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/master_offline.dart';
import 'kebijakan_tipe_member.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/aksi_baris_menu.dart';

final _formatRpTipeMember =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Tab "Tipe Member" (padanan `tipe_anggota_koperasi.jsp`) -- kategori TIPIS
/// (kode/nama/keterangan/aktif SAJA, tanpa aturan bisnis) yg di layar "Data
/// Member Baru" diberi label "Kategori Referensi Sivitas" (mengaitkan member
/// ke data master Mahasiswa/Siswa/Guru/Dosen/Pegawai berdasar nama tipe).
/// BEDA dari Jenis Member (`AnggotaTabJenisMember`, klasifikasi UTAMA dgn
/// aturan saldo/topup/belanja-rutin).
class AnggotaTabTipeMember extends StatefulWidget {
  const AnggotaTabTipeMember({super.key});

  @override
  State<AnggotaTabTipeMember> createState() => _AnggotaTabTipeMemberState();
}

class _AnggotaTabTipeMemberState extends State<AnggotaTabTipeMember>
    with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  List<Map<String, dynamic>> _caraBayar = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;
  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _muatDaftar();
    _muatCaraBayar();
  }

  Future<void> _muatCaraBayar() async {
    try {
      await MasterOffline.daftarCacheDulu(
        'cara_bayar_list_semua',
        const {},
        'master:cara_bayar:pilihan_tipe',
        onData: (hasil) {
          final data =
              ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (mounted) setStateIfMounted(() => _caraBayar = data);
        },
      );
    } catch (_) {
      // Form tetap dapat dibuka; snapshot tipe yang sudah ada tidak diubah.
    }
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu(
          'tipe_anggota_list_admin',
          {
            'keyword': _kataKunci.isEmpty ? null : _kataKunci,
            'page': _halaman,
            'page_size': _pageSize,
          },
          'master:tipe_anggota', onData: (hasil) {
        if (!mounted) return;
        final data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _daftar = data;
          _total = dariServer
              ? (hasil['total'] as num?)?.toInt() ?? data.length
              : data.length;
          _idBaru = dariServer
              ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(hasil['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus = dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
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
      if (mounted) setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cariUlang(String v) async {
    setStateIfMounted(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int h) async {
    setStateIfMounted(() => _halaman = h);
    await _muatDaftar();
  }

  Future<void> _bukaForm({Map<String, dynamic>? tipe}) async {
    final tokoTersedia = Sesi.instance.daftarTokoFilter.isNotEmpty
        ? Sesi.instance.daftarTokoFilter
        : Sesi.instance.daftarToko;
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormTipeMember(
        tipe: tipe,
        caraBayar: _caraBayar,
        toko: tokoTersedia,
      ),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  Future<void> _hapus(Map<String, dynamic> tipe) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Tipe Member?'),
        content: Text(
            'Tipe "${tipe['nama']}" dipakai ${tipe['jumlahAnggota'] ?? 0} member. Kalau masih dipakai, penghapusan akan ditolak -- nonaktifkan saja sebagai gantinya.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'tipe_anggota_hapus',
        body: {'id': tipe['id']},
        kunci: 'tipe_anggota:${tipe['id']}',
        cacheKey: 'master:tipe_anggota',
        rowLokal: {'id': tipe['id']},
        hapusLokal: true,
      );
      await _muatDaftar();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_pesanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_pesanError!, textAlign: TextAlign.center),
              AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _muatDaftar, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _muatDaftar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari kode/nama tipe...',
                  debounce: const Duration(milliseconds: 450),
                  onChanged: _cariUlang,
                ),
              ),
              if (Sesi.instance.bolehKelola) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _bukaForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Tipe'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          BannerPerubahanServer(
            key: ValueKey('perubahan:$_versiPerubahan'),
            baru: _idBaru.length,
            berubah: _idBerubah.length,
            dihapus: _jumlahHapus,
          ),
          AppDataTable(
            minWidth: 720,
            emptyText: 'Belum ada tipe member.',
            columns: [
              const AppTableColumn('Kode', flex: 1),
              const AppTableColumn('Nama Tipe', flex: 2),
              const AppTableColumn('Keterangan', flex: 3),
              const AppTableColumn('Maks. Utang',
                  flex: 2, align: TextAlign.right),
              const AppTableColumn('Aturan Wajib',
                  flex: 2, align: TextAlign.center),
              const AppTableColumn('Status', flex: 1, align: TextAlign.center),
              AppTableColumn('Aksi', width: 64, align: TextAlign.center),
            ],
            rows: _daftar.map((t) {
              final aktif = t['aktif'] == true;
              return AppTableRowData(
                onTap:
                    Sesi.instance.bolehKelola ? () => _bukaForm(tipe: t) : null,
                cells: [
                  AppTableCell(
                    flex: 1,
                    child: KilauBaris(
                      kunci: '${t['id'] ?? t['_kunci'] ?? ''}',
                      idBaru: _idBaru,
                      idBerubah: _idBerubah,
                      child: SelTeksDenganSinkron(
                        kunci: kunciBarisMaster('tipe_anggota', t),
                        teks: '${t['kode'] ?? '-'}',
                      ),
                    ),
                  ),
                  AppTableCell.text('${t['nama'] ?? ''}', flex: 2),
                  AppTableCell.text('${t['keterangan'] ?? '-'}',
                      flex: 3, maxLines: 2),
                  AppTableCell.text(
                    (((t['maksimalBolehUtang'] as num?) ?? 0) > 0)
                        ? _formatRpTipeMember
                            .format((t['maksimalBolehUtang'] as num?) ?? 0)
                        : 'Tidak boleh',
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: (((t['maksimalBolehUtang'] as num?) ?? 0) > 0)
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                  ),
                  AppTableCell.text(
                    [
                      if (wajibHpDariTipe(t)) 'No. HP',
                      if (wajibEmailDariTipe(t)) 'Email',
                      if (t['wajibPin'] == true) 'PIN',
                      if (t['wajibBiometricWajah'] == true) 'Wajah',
                      if (t['wajibBiometricFingerprint'] == true) 'Fingerprint',
                    ].join(' + ').isEmpty
                        ? '-'
                        : [
                            if (wajibHpDariTipe(t)) 'No. HP',
                            if (wajibEmailDariTipe(t)) 'Email',
                            if (t['wajibPin'] == true) 'PIN',
                            if (t['wajibBiometricWajah'] == true) 'Wajah',
                            if (t['wajibBiometricFingerprint'] == true)
                              'Fingerprint',
                          ].join(' + '),
                    flex: 2,
                    align: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: wajibHpDariTipe(t) ||
                              wajibEmailDariTipe(t) ||
                              t['wajibPin'] == true ||
                              t['wajibBiometricWajah'] == true ||
                              t['wajibBiometricFingerprint'] == true
                          ? AppColors.info
                          : AppColors.textSecondary,
                    ),
                  ),
                  AppTableCell(
                    flex: 1,
                    align: TextAlign.center,
                    child: StatusPill(
                      label: aktif ? 'Aktif' : 'Nonaktif',
                      warna:
                          aktif ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                  AppTableCell(
                    width: 64,
                    align: TextAlign.center,
                    child: AksiBarisMenu(aksi: [
                      AksiBaris(
                        ikon: Icons.history,
                        label: 'Riwayat data ini',
                        onTap: t['id'] == null
                            ? null
                            : () => tampilkanRiwayatData(context,
                                entitas: 'tipe_anggota',
                                id: t['id'],
                                judul: '${t['nama'] ?? ''}'),
                      ),
                      AksiBaris(
                        ikon: Icons.edit_outlined,
                        label: 'Ubah',
                        onTap: Sesi.instance.bolehKelola
                            ? () => _bukaForm(tipe: t)
                            : null,
                      ),
                      AksiBaris(
                        ikon: Icons.delete_outline,
                        label: 'Hapus',
                        merusak: true,
                        onTap:
                            Sesi.instance.bolehKelola ? () => _hapus(t) : null,
                      ),
                    ]),
                  ),
                ],
              );
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _total,
              labelData: 'tipe',
              onSebelumnya:
                  _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
              onBerikutnya: _halaman < _totalHalaman
                  ? () => _pindahHalaman(_halaman + 1)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormTipeMember extends StatefulWidget {
  final Map<String, dynamic>? tipe;
  final List<Map<String, dynamic>> caraBayar;
  final List<Map<String, dynamic>> toko;
  const _FormTipeMember({
    required this.tipe,
    required this.caraBayar,
    required this.toko,
  });

  @override
  State<_FormTipeMember> createState() => _FormTipeMemberState();
}

class _FormTipeMemberState extends State<_FormTipeMember> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _maksimalBolehUtang;
  late final TextEditingController _maksimalTransaksiHarian;
  late final TextEditingController _maksimalTransaksiMingguan;
  late final TextEditingController _maksimalTransaksiBulanan;
  Set<int> _caraBayarDipilih = {};
  Set<int> _caraBayarWajibPin = {};
  int? _caraBayarDefaultId;
  bool _tidakBolehCaraBayarLain = false;
  bool _aktif = true;
  bool _wajibHp = false;
  bool _wajibEmail = false;
  bool _wajibPin = false;
  bool _wajibBiometricWajah = false;
  bool _wajibBiometricFingerprint = false;
  bool _berlakuSemuaToko = true;
  Set<int> _tokoDipilih = {};
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final t = widget.tipe;
    _kode = TextEditingController(text: '${t?['kode'] ?? ''}');
    _nama = TextEditingController(text: '${t?['nama'] ?? ''}');
    _keterangan = TextEditingController(text: '${t?['keterangan'] ?? ''}');
    final maksUtang = (t?['maksimalBolehUtang'] as num?) ?? 0;
    _maksimalBolehUtang =
        TextEditingController(text: maksUtang == 0 ? '' : '$maksUtang');
    _maksimalTransaksiHarian = _controllerBatas(t?['maksimalTransaksiHarian']);
    _maksimalTransaksiMingguan =
        _controllerBatas(t?['maksimalTransaksiMingguan']);
    _maksimalTransaksiBulanan =
        _controllerBatas(t?['maksimalTransaksiBulanan']);
    _caraBayarDipilih = '${t?['daftarCaraPembayaranYangBolehDiPilih'] ?? ''}'
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet();
    _caraBayarWajibPin = '${t?['daftarCaraPembayaranWajibPin'] ?? ''}'
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet();
    _caraBayarDefaultId = (t?['caraPembayaranDefaultId'] as num?)?.toInt();
    _tidakBolehCaraBayarLain = t?['tidakBolehCaraPembayaranLain'] == true;
    _aktif = t?['aktif'] ?? true;
    // Kebijakan kontak: nilai server bila ada, selain itu default per nama
    // (Pegawai/Dosen/Guru/Umum wajib HP; email tidak wajib semua).
    _wajibHp = wajibHpDariTipe(t);
    _wajibEmail = wajibEmailDariTipe(t);
    _wajibPin = t?['wajibPin'] == true;
    _wajibBiometricWajah = t?['wajibBiometricWajah'] == true;
    _wajibBiometricFingerprint = t?['wajibBiometricFingerprint'] == true;
    _berlakuSemuaToko = t?['berlakuSemuaToko'] ?? true;
    _tokoDipilih = '${t?['daftarToko'] ?? ''}'
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet();
  }

  TextEditingController _controllerBatas(dynamic nilai) {
    final angka = (nilai as num?)?.toDouble() ?? 0;
    return TextEditingController(
        text: angka <= 0 ? '' : angka.toStringAsFixed(0));
  }

  double _angka(TextEditingController controller) =>
      double.tryParse(
          controller.text.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      0;

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    _maksimalBolehUtang.dispose();
    _maksimalTransaksiHarian.dispose();
    _maksimalTransaksiMingguan.dispose();
    _maksimalTransaksiBulanan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_berlakuSemuaToko && _tokoDipilih.isEmpty) {
      setStateIfMounted(() => _pesanError =
          'Pilih minimal satu toko atau aktifkan Berlaku ke semua toko.');
      return;
    }
    if (_caraBayarDipilih.length == 1) {
      _caraBayarDefaultId = _caraBayarDipilih.first;
    }
    if (_caraBayarDefaultId != null &&
        !_caraBayarDipilih.contains(_caraBayarDefaultId)) {
      setStateIfMounted(() => _pesanError =
          'Cara bayar default harus termasuk cara bayar yang diizinkan.');
      return;
    }
    if (_tidakBolehCaraBayarLain && _caraBayarDefaultId == null) {
      setStateIfMounted(() => _pesanError =
          'Pilih cara bayar default sebelum melarang cara bayar lain.');
      return;
    }
    if (_caraBayarDipilih.isNotEmpty &&
        !_caraBayarDipilih.containsAll(_caraBayarWajibPin)) {
      setStateIfMounted(() => _pesanError =
          'Cara bayar wajib PIN harus termasuk cara bayar yang diizinkan.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final body = {
        if (widget.tipe != null) 'id': widget.tipe!['id'],
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'aktif': _aktif,
        'maksimalBolehUtang': double.tryParse(
                _maksimalBolehUtang.text.trim().replaceAll(',', '.')) ??
            0,
        'wajibHp': _wajibHp,
        'wajibEmail': _wajibEmail,
        'wajibPin': _wajibPin,
        'daftarCaraPembayaranWajibPin': _caraBayarWajibPin.join(','),
        'wajibBiometricWajah': _wajibBiometricWajah,
        'wajibBiometricFingerprint': _wajibBiometricFingerprint,
        'wajib_pin': _wajibPin,
        'wajib_biometric_wajah': _wajibBiometricWajah,
        'wajib_biometric_fingerprint': _wajibBiometricFingerprint,
        'daftarCaraPembayaranYangBolehDiPilih': _caraBayarDipilih.join(','),
        'caraPembayaranDefaultId': _caraBayarDefaultId,
        'tidakBolehCaraPembayaranLain': _tidakBolehCaraBayarLain,
        'maksimalTransaksiHarian': _angka(_maksimalTransaksiHarian),
        'maksimalTransaksiMingguan': _angka(_maksimalTransaksiMingguan),
        'maksimalTransaksiBulanan': _angka(_maksimalTransaksiBulanan),
        'berlakuSemuaToko': _berlakuSemuaToko,
        'daftarToko': _berlakuSemuaToko ? '' : _tokoDipilih.join(','),
      };
      await prosesSimpanMaster(
        context,
        aksi: 'tipe_anggota_simpan',
        body: body,
        kunci: widget.tipe != null
            ? 'tipe_anggota:${widget.tipe!['id']}'
            : 'tipe_anggota:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:tipe_anggota',
        rowLokal: body,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.tipe != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Tipe Member' : 'Tambah Tipe Member',
            subtitle:
                'Kategori referensi sivitas -- mengaitkan member ke Mahasiswa/Siswa/Guru/Dosen/Pegawai berdasar nama.',
            icon: Icons.label_outline,
            errorText: _pesanError,
            errorDetail: detailUntuk(_pesanError),
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
                        child: CircularProgressIndicator(strokeWidth: 2))
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
            children: [
              AppFormSection(
                judul: 'Identitas',
                children: [
                  AppFormTextField(label: 'Kode', controller: _kode),
                  AppFormTextField(
                    label: 'Nama *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 2),
                  AppFormTextField(
                    label: 'Maksimal Boleh Utang',
                    controller: _maksimalBolehUtang,
                    hintText: '0 = tidak boleh berhutang',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  AppFormSwitchTile(
                      title: 'Aktif',
                      value: _aktif,
                      onChanged: (v) => setStateIfMounted(() => _aktif = v)),
                ],
              ),
              AppFormSection(
                judul: 'Kebijakan Kontak Member',
                children: [
                  AppFormSwitchTile(
                      title: 'Wajib Memasukkan No. HP',
                      subtitle:
                          'Form member tipe ini menolak disimpan tanpa No. HP. '
                          'Default: Pegawai/Dosen/Guru/Umum wajib, Mahasiswa/Siswa tidak.',
                      value: _wajibHp,
                      onChanged: (v) => setStateIfMounted(() => _wajibHp = v)),
                  AppFormSwitchTile(
                      title: 'Wajib Memasukkan Email',
                      subtitle: 'Default: tidak wajib untuk semua tipe.',
                      value: _wajibEmail,
                      onChanged: (v) =>
                          setStateIfMounted(() => _wajibEmail = v)),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Verifikasi Transaksi',
                deskripsi:
                    'Default semuanya tidak aktif. Jika Jenis Member atau Tipe Member mewajibkan suatu metode, kasir tetap harus memverifikasinya sebelum saldo dipotong.',
                children: [
                  AppFormSwitchTile(
                    title: 'Wajib pakai PIN',
                    subtitle:
                        'Kasir meminta PIN numerik member sebelum transaksi saldo diproses.',
                    value: _wajibPin,
                    onChanged: (v) => setStateIfMounted(() => _wajibPin = v),
                  ),
                  if (_wajibPin) ...[
                    const Text(
                      'Wajib PIN hanya untuk cara bayar berikut (kosong = semua cara bayar):',
                      style: TextStyle(fontSize: 12),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: widget.caraBayar.map((c) {
                        final id = (c['id'] as num).toInt();
                        return FilterChip(
                          label: Text('${c['nama']}',
                              style: const TextStyle(fontSize: 12)),
                          selected: _caraBayarWajibPin.contains(id),
                          onSelected: (dipilih) => setStateIfMounted(() {
                            if (dipilih) {
                              _caraBayarWajibPin.add(id);
                            } else {
                              _caraBayarWajibPin.remove(id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                  AppFormSwitchTile(
                    title: 'Wajib pakai Face Recognition',
                    subtitle:
                        'Wajah member harus cocok melalui kamera dan pemeriksaan liveness.',
                    value: _wajibBiometricWajah,
                    onChanged: (v) =>
                        setStateIfMounted(() => _wajibBiometricWajah = v),
                  ),
                  AppFormSwitchTile(
                    title: 'Wajib pakai Finger Print',
                    subtitle:
                        'Desktop/Android menggunakan scanner fingerprint eksternal yang didukung SDK vendor.',
                    value: _wajibBiometricFingerprint,
                    onChanged: (v) =>
                        setStateIfMounted(() => _wajibBiometricFingerprint = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Cara Pembayaran',
                deskripsi:
                    'Pilih satu atau beberapa metode. Kosong berarti tidak menambah pembatasan dari Jenis Member.',
                children: [
                  if (widget.caraBayar.isEmpty)
                    const Text('Daftar cara bayar belum dapat dimuat.',
                        style: TextStyle(fontSize: 12, color: Colors.orange))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: widget.caraBayar.map((c) {
                        final id = (c['id'] as num).toInt();
                        return FilterChip(
                          label: Text('${c['nama']}',
                              style: const TextStyle(fontSize: 12)),
                          selected: _caraBayarDipilih.contains(id),
                          onSelected: (dipilih) => setStateIfMounted(() {
                            if (dipilih) {
                              _caraBayarDipilih.add(id);
                            } else {
                              _caraBayarDipilih.remove(id);
                              _caraBayarWajibPin.remove(id);
                              if (_caraBayarDefaultId == id) {
                                _caraBayarDefaultId = null;
                              }
                            }
                            if (_caraBayarDipilih.length == 1) {
                              _caraBayarDefaultId = _caraBayarDipilih.first;
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  DropdownButtonFormField<int>(
                    value: _caraBayarDipilih.contains(_caraBayarDefaultId)
                        ? _caraBayarDefaultId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Cara Bayar Default',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.caraBayar
                        .where((c) => _caraBayarDipilih
                            .contains((c['id'] as num).toInt()))
                        .map((c) => DropdownMenuItem<int>(
                              value: (c['id'] as num).toInt(),
                              child: Text('${c['nama']}'),
                            ))
                        .toList(),
                    onChanged: _caraBayarDipilih.isEmpty
                        ? null
                        : (v) =>
                            setStateIfMounted(() => _caraBayarDefaultId = v),
                  ),
                  AppFormSwitchTile(
                    title: 'Tidak boleh pakai cara bayar lain',
                    subtitle:
                        'Kasir otomatis memakai cara bayar default dan pemilih metode dinonaktifkan. Jika hanya satu metode diizinkan, aturan ini berlaku otomatis.',
                    value: _tidakBolehCaraBayarLain,
                    onChanged: (v) =>
                        setStateIfMounted(() => _tidakBolehCaraBayarLain = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Batas Pembelian',
                deskripsi:
                    'Total transaksi member tidak boleh melewati batas periode. Nilai 0 atau kosong berarti tanpa batas.',
                children: [
                  AppFormTextField(
                    label: 'Maksimal Transaksi Harian',
                    controller: _maksimalTransaksiHarian,
                    hintText: '0 = tanpa batas',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  AppFormTextField(
                    label: 'Maksimal Transaksi Mingguan',
                    controller: _maksimalTransaksiMingguan,
                    hintText: '0 = tanpa batas',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  AppFormTextField(
                    label: 'Maksimal Transaksi Bulanan',
                    controller: _maksimalTransaksiBulanan,
                    hintText: '0 = tanpa batas',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Cakupan Toko',
                deskripsi:
                    'Menentukan toko tempat aturan cara bayar, PIN/biometrik, batas pembelian, dan batas utang tipe ini berlaku.',
                children: [
                  AppFormSwitchTile(
                    title: 'Berlaku ke semua toko',
                    subtitle:
                        'Aktif secara default dan kompatibel dengan seluruh data tipe member lama.',
                    value: _berlakuSemuaToko,
                    onChanged: (v) =>
                        setStateIfMounted(() => _berlakuSemuaToko = v),
                  ),
                  if (!_berlakuSemuaToko) ...[
                    if (widget.toko.isEmpty)
                      const Text(
                        'Daftar toko aktif belum tersedia. Muat ulang konfigurasi saat online.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: widget.toko.map((t) {
                          final id = (t['id'] as num?)?.toInt();
                          if (id == null) return const SizedBox.shrink();
                          return FilterChip(
                            label: Text('${t['nama'] ?? 'Toko $id'}',
                                style: const TextStyle(fontSize: 12)),
                            selected: _tokoDipilih.contains(id),
                            onSelected: (dipilih) => setStateIfMounted(() {
                              if (dipilih) {
                                _tokoDipilih.add(id);
                              } else {
                                _tokoDipilih.remove(id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
