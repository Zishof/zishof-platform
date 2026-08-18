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

class _AnggotaTabTipeMemberState extends State<AnggotaTabTipeMember> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
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
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('tipe_anggota_list_admin', {
        'keyword': _kataKunci.isEmpty ? null : _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:tipe_anggota', onData: (hasil) {
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
      if (mounted) setStateIfMounted(() => _pesanError = e.toString());
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
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormTipeMember(tipe: tipe),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
              const AppTableColumn('Kontak Wajib',
                  flex: 2, align: TextAlign.center),
              const AppTableColumn('Status', flex: 1, align: TextAlign.center),
              AppTableColumn('Aksi',
                  width: Sesi.instance.bolehKelola ? 124 : 92,
                  align: TextAlign.center),
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
                    ].join(' + ').isEmpty
                        ? '-'
                        : [
                            if (wajibHpDariTipe(t)) 'No. HP',
                            if (wajibEmailDariTipe(t)) 'Email',
                          ].join(' + '),
                    flex: 2,
                    align: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: wajibHpDariTipe(t) || wajibEmailDariTipe(t)
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
                    width: Sesi.instance.bolehKelola ? 124 : 92,
                    align: TextAlign.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (t['id'] != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Riwayat data ini (AuditTrails)',
                            icon: const Icon(Icons.history, size: 18),
                            onPressed: () => tampilkanRiwayatData(context,
                                entitas: 'tipe_anggota',
                                id: t['id'],
                                judul: '${t['nama'] ?? ''}'),
                          ),
                        if (Sesi.instance.bolehKelola) ...[
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _bukaForm(tipe: t),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: AppColors.danger),
                            onPressed: () => _hapus(t),
                          ),
                        ] else
                          const Icon(Icons.visibility_outlined, size: 18),
                      ],
                    ),
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
  const _FormTipeMember({required this.tipe});

  @override
  State<_FormTipeMember> createState() => _FormTipeMemberState();
}

class _FormTipeMemberState extends State<_FormTipeMember> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _maksimalBolehUtang;
  bool _aktif = true;
  bool _wajibHp = false;
  bool _wajibEmail = false;
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
    _aktif = t?['aktif'] ?? true;
    // Kebijakan kontak: nilai server bila ada, selain itu default per nama
    // (Pegawai/Dosen/Guru/Umum wajib HP; email tidak wajib semua).
    _wajibHp = wajibHpDariTipe(t);
    _wajibEmail = wajibEmailDariTipe(t);
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    _maksimalBolehUtang.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
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
      setStateIfMounted(() => _pesanError = e.toString());
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
          ),
        ),
      ),
    );
  }
}
