import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/indikator_baris_sinkron.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/indikator_sinkron_master.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/riwayat_audit_dialog.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Master Customer -- layar legacy 04-06 (Data Customer / Buka-Tutup Daftar).</h3>
///
/// Identitas (kode 5 karakter teks legacy, nama, alamat, telepon) milik
/// AnggotaKoperasi existing; profil sales (termin, diskon default, wilayah,
/// sales pembina, rekening) di CustomerInventoryProfile. Saldo Piutang
/// baca-saja dihitung server dari ledger existing. Nonaktif = profil sales
/// saja (keanggotaan POS tidak disentuh). Kode duplikat DITOLAK (cleansing,
/// bukan gabung otomatis).
class MasterCustomerScreen extends StatefulWidget {
  const MasterCustomerScreen({super.key});

  @override
  State<MasterCustomerScreen> createState() => _MasterCustomerScreenState();
}

class _MasterCustomerScreenState extends State<MasterCustomerScreen> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  String? _filterAktif;
  String _sort = 'kode';
  bool _hanyaProfil = false;
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('si_customer_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        if (_filterAktif != null) 'aktif': _filterAktif,
        'sort': _sort,
        'hanya_profil': _hanyaProfil,
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:si_customer', onData: (hasil) {
        if (!mounted) return;
        final data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final dariServer = hasil['dariServer'] == true;
        setStateIfMounted(() {
          _data = data;
          // Emisi daftarCacheDulu tidak meneruskan 'total' server -- selama
          // halaman penuh, asumsikan masih ada halaman berikutnya supaya
          // kontrol paginasi tetap bisa dipakai.
          _total = dariServer
              ? (hasil['total'] as num?)?.toInt() ??
                  (data.length >= _pageSize
                      ? _halaman * _pageSize + 1
                      : (_halaman - 1) * _pageSize + data.length)
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
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Future<void> _bukaDetail(Map<String, dynamic> baris) async {
    Map<String, dynamic> detail = baris;
    try {
      final hasil = await ApiClient.instance
          .aksi('si_customer_detail', {'anggota_id': baris['anggotaId']});
      detail = (hasil['data'] as Map<String, dynamic>?) ?? baris;
    } catch (_) {
      // Gagal ambil detail -- pakai baris daftar (saldo piutang tidak tampil).
    }
    if (!mounted) return;
    final aksi = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DetailCustomerSheet(data: detail),
    );
    if (!mounted) return;
    if (aksi == 'ubah') {
      await _bukaForm(data: detail);
    } else if (aksi == 'nonaktif' || aksi == 'aktifkan') {
      await _ubahStatus(detail, aktifkan: aksi == 'aktifkan');
    }
  }

  Future<void> _bukaForm({Map<String, dynamic>? data}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormCustomer(data: data),
    );
    if (tersimpan == true) await _muat();
  }

  Future<void> _ubahStatus(Map<String, dynamic> data,
      {required bool aktifkan}) async {
    final alasanCtrl = TextEditingController();
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aktifkan ? 'Aktifkan Customer?' : 'Nonaktifkan Customer?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(aktifkan
              ? 'Profil customer "${data['nama']}" diaktifkan kembali.'
              : 'Hanya profil customer distribusi yang dinonaktifkan; keanggotaan '
                  'POS "${data['nama']}" tidak berubah.'),
          if (!aktifkan) ...[
            const SizedBox(height: 12),
            TextField(
              controller: alasanCtrl,
              decoration: const InputDecoration(
                  labelText: 'Alasan (wajib, tercatat di audit)',
                  border: OutlineInputBorder()),
            ),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(aktifkan ? 'Aktifkan' : 'Nonaktifkan',
                  style: TextStyle(
                      color: aktifkan ? AppColors.success : Colors.red))),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(context, aksi: 'si_customer_deactivate', body: {
        'anggota_id': data['anggotaId'],
        'aktif': aktifkan,
        if (!aktifkan) 'alasan': alasanCtrl.text.trim(),
      }, kunci: 'si_customer:${data['anggotaId']}');
      if (mounted) await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolehTambah = Sesi.instance.bolehAksiIs('master_customer', 'create');
    return AppShell(
      menuAktif: MenuEBisnis.masterCustomer,
      judul: 'Master Customer',
      subjudul:
          'Customer distribusi: termin, diskon, wilayah, sales pembina, piutang (layar legacy 04-06)',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message:
              'Cetak/ekspor daftar customer tersedia di fase laporan (P2-F) -- belum aktif di rilis ini.',
          child: IconButton(
              icon: const Icon(Icons.print_outlined), onPressed: null),
        ),
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang',
            onPressed: _muat),
      ]),
      floatingActionButton: bolehTambah
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Customer'))
          : null,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      AppDetailGalatOpsional(detail: detailUntuk(_error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _muat, child: const Text('Coba Lagi')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      Row(children: [
                        Expanded(
                          child: AppSearchField(
                            hintText: 'Cari kode, nama, telepon, alamat, wilayah...',
                            onChanged: (v) {
                              _kataKunci = v.trim();
                              _halaman = 1;
                              _muat();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 125,
                          child: DropdownButtonFormField<String?>(
                            value: _filterAktif,
                            isDense: true,
                            decoration: const InputDecoration(
                                labelText: 'Status',
                                isDense: true,
                                border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(
                                  value: null, child: Text('Semua')),
                              DropdownMenuItem(
                                  value: 'aktif', child: Text('Aktif')),
                              DropdownMenuItem(
                                  value: 'nonaktif', child: Text('Nonaktif')),
                            ],
                            onChanged: (v) {
                              _filterAktif = v;
                              _halaman = 1;
                              _muat();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 125,
                          child: DropdownButtonFormField<String>(
                            value: _sort,
                            isDense: true,
                            decoration: const InputDecoration(
                                labelText: 'Urut',
                                isDense: true,
                                border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(
                                  value: 'kode', child: Text('Kode')),
                              DropdownMenuItem(
                                  value: 'nama', child: Text('Nama')),
                              DropdownMenuItem(
                                  value: 'wilayah', child: Text('Wilayah')),
                            ],
                            onChanged: (v) {
                              _sort = v ?? 'kode';
                              _muat();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Punya profil'),
                          selected: _hanyaProfil,
                          onSelected: (v) {
                            _hanyaProfil = v;
                            _halaman = 1;
                            _muat();
                          },
                        ),
                      ]),
                      const SizedBox(height: 12),
                      BannerPerubahanServer(
                        key: ValueKey('perubahan:$_versiPerubahan'),
                        baru: _idBaru.length,
                        berubah: _idBerubah.length,
                        dihapus: _jumlahHapus,
                      ),
                      AppDataTable(
                        minWidth: 900,
                        emptyText: 'Belum ada customer.',
                        columns: const [
                          AppTableColumn('Kode', flex: 1),
                          AppTableColumn('Nama Customer', flex: 3),
                          AppTableColumn('Wilayah', flex: 2),
                          AppTableColumn('Termin',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Sales', flex: 2),
                          AppTableColumn('Status',
                              flex: 1, align: TextAlign.center),
                        ],
                        rows: _data.map((c) {
                          final aktif = c['aktif'] == true;
                          return AppTableRowData(
                            onTap: () => _bukaDetail(c),
                            cells: [
                              AppTableCell(
                                flex: 1,
                                child: KilauBaris(
                                  kunci: '${c['id'] ?? c['_kunci'] ?? ''}',
                                  idBaru: _idBaru,
                                  idBerubah: _idBerubah,
                                  child: Row(children: [
                                    IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip:
                                            'Riwayat data ini (AuditTrails)',
                                        icon: const Icon(Icons.history,
                                            size: 16),
                                        onPressed: () => tampilkanRiwayatData(
                                            context,
                                            entitas: 'si_customer',
                                            id: c['anggotaId'],
                                            judul: '${c['nama'] ?? ''}')),
                                    Expanded(
                                      child: SelTeksDenganSinkron(
                                        kunci:
                                            'si_customer:${c['anggotaId']}',
                                        teks: '${c['kode']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'monospace',
                                            fontSize: 12.5),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                              AppTableCell.text('${c['nama']}',
                                  flex: 3, maxLines: 2),
                              AppTableCell.text('${c['wilayah'] ?? ''}',
                                  flex: 2),
                              AppTableCell.text('${c['terminHari'] ?? 0} hr',
                                  flex: 1, align: TextAlign.right),
                              AppTableCell.text('${c['salesOwnerNama'] ?? ''}',
                                  flex: 2),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.center,
                                child: StatusPill(
                                    label: aktif ? 'Aktif' : 'Nonaktif',
                                    warna: aktif
                                        ? AppColors.success
                                        : AppColors.danger),
                              ),
                            ],
                          );
                        }).toList(),
                        pagination: AppTablePagination(
                          halaman: _halaman,
                          totalHalaman: _totalHalaman,
                          totalData: _total,
                          labelData: 'customer',
                          onSebelumnya: _halaman > 1
                              ? () {
                                  _halaman--;
                                  _muat();
                                }
                              : null,
                          onBerikutnya: _halaman < _totalHalaman
                              ? () {
                                  _halaman++;
                                  _muat();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _DetailCustomerSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DetailCustomerSheet({required this.data});

  @override
  Widget build(BuildContext context) {
    final aktif = data['aktif'] == true;
    final bolehUbah = Sesi.instance.bolehAksiIs('master_customer', 'update');
    final bolehNonaktif =
        Sesi.instance.bolehAksiIs('master_customer', 'delete') ||
            Sesi.instance.bolehAksiIs('master_customer', 'update');
    Widget baris(String label, String nilai) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 150,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context)))),
            Expanded(
                child: Text(nilai.isEmpty ? '-' : nilai,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        );
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (context, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Expanded(
              child: Text('${data['kode']} — ${data['nama']}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            StatusPill(
                label: aktif ? 'Aktif' : 'Nonaktif',
                warna: aktif ? AppColors.success : AppColors.danger),
          ]),
          const SizedBox(height: 14),
          AppFormSection(judul: 'Identitas Customer', children: [
            baris('Kode (legacy, terkunci)', '${data['kode'] ?? ''}'),
            baris('Nama', '${data['nama'] ?? ''}'),
            baris('Alamat', '${data['alamat'] ?? ''}'),
            baris('Wilayah', '${data['wilayah'] ?? ''}'),
            baris(
                'Telepon', '${data['telp'] ?? ''} ${data['hp'] ?? ''}'.trim()),
            baris('Email', '${data['email'] ?? ''}'),
          ]),
          const SizedBox(height: 12),
          AppFormSection(judul: 'Relasi & Saldo', children: [
            baris('Termin Pembayaran', '${data['terminHari'] ?? 0} hari'),
            baris('Diskon Default', '${data['diskonDefaultPersen'] ?? 0}%'),
            baris('Limit Kredit',
                _fmtRp.format((data['limitKredit'] as num?) ?? 0)),
            baris('Sales Pembina', '${data['salesOwnerNama'] ?? ''}'),
            baris('No. Rekening', '${data['noRekening'] ?? ''}'),
            baris('Atas Nama', '${data['atasNama'] ?? ''}'),
            baris('Bank', '${data['bank'] ?? ''}'),
            baris(
                'Saldo Piutang',
                data['saldoPiutang'] == null
                    ? '-'
                    : _fmtRp.format(data['saldoPiutang'])),
          ]),
          const SizedBox(height: 12),
          AppFormSection(judul: 'Riwayat Audit', children: [
            baris('Terakhir diubah oleh', '${data['auditOleh'] ?? ''}'),
            baris('Waktu perubahan', '${data['auditWaktu'] ?? ''}'),
          ]),
          const SizedBox(height: 16),
          Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                // Paritas aksi "Riwayat Audit" legacy (revisi Envers profil customer);
                // disabled beralasan bila belum ada profil varian.
                Tooltip(
                  message: data['profilId'] == null
                      ? 'Belum ada profil varian tersimpan — belum ada revisi audit.'
                      : 'Riwayat perubahan (Envers)',
                  child: OutlinedButton.icon(
                      onPressed: data['profilId'] == null
                          ? null
                          : () => tampilkanRiwayatAudit(context, 'customer',
                              data['profilId'] as Object, '${data['nama']}'),
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Riwayat Audit')),
                ),
                OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Tutup')),
                if (bolehNonaktif)
                  OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                          context, aktif ? 'nonaktif' : 'aktifkan'),
                      icon: Icon(
                          aktif ? Icons.block : Icons.check_circle_outline,
                          size: 18,
                          color: aktif ? Colors.red : AppColors.success),
                      label: Text(aktif ? 'Nonaktifkan' : 'Aktifkan',
                          style: TextStyle(
                              color: aktif ? Colors.red : AppColors.success))),
                if (bolehUbah)
                  ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, 'ubah'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Ubah'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0)),
              ]),
        ],
      ),
    );
  }
}

class _FormCustomer extends StatefulWidget {
  final Map<String, dynamic>? data;
  const _FormCustomer({required this.data});

  @override
  State<_FormCustomer> createState() => _FormCustomerState();
}

class _FormCustomerState extends State<_FormCustomer> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _alamat;
  late final TextEditingController _telp;
  late final TextEditingController _hp;
  late final TextEditingController _email;
  late final TextEditingController _termin;
  late final TextEditingController _diskon;
  late final TextEditingController _limitKredit;
  late final TextEditingController _wilayah;
  late final TextEditingController _noRekening;
  late final TextEditingController _atasNama;
  late final TextEditingController _bank;
  List<Map<String, dynamic>> _daftarSales = [];
  int? _salesOwnerId;
  bool _menyimpan = false;
  bool _adaPerubahan = false;
  String? _error;

  bool get _ubah => widget.data != null;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _kode = TextEditingController(text: d?['kode'] ?? '');
    _nama = TextEditingController(text: d?['nama'] ?? '');
    _alamat = TextEditingController(text: d?['alamat'] ?? '');
    _telp = TextEditingController(text: d?['telp'] ?? '');
    _hp = TextEditingController(text: d?['hp'] ?? '');
    _email = TextEditingController(text: d?['email'] ?? '');
    _termin = TextEditingController(text: '${d?['terminHari'] ?? 0}');
    _diskon = TextEditingController(text: '${d?['diskonDefaultPersen'] ?? 0}');
    _limitKredit = TextEditingController(
        text: (d?['limitKredit'] as num?)?.toStringAsFixed(0) ?? '0');
    _wilayah = TextEditingController(text: d?['wilayah'] ?? '');
    _noRekening = TextEditingController(text: d?['noRekening'] ?? '');
    _atasNama = TextEditingController(text: d?['atasNama'] ?? '');
    _bank = TextEditingController(text: d?['bank'] ?? '');
    _salesOwnerId = (d?['salesOwnerId'] as num?)?.toInt();
    for (final c in [
      _kode,
      _nama,
      _alamat,
      _telp,
      _hp,
      _email,
      _termin,
      _diskon,
      _limitKredit,
      _wilayah,
      _noRekening,
      _atasNama,
      _bank
    ]) {
      c.addListener(() => _adaPerubahan = true);
    }
    _muatSales();
  }

  Future<void> _muatSales() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('si_sales_list', {'aktif': 'aktif', 'page_size': 100});
      setStateIfMounted(() => _daftarSales =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // Dropdown sales gagal muat bukan blocker.
    }
  }

  @override
  void dispose() {
    for (final c in [
      _kode,
      _nama,
      _alamat,
      _telp,
      _hp,
      _email,
      _termin,
      _diskon,
      _limitKredit,
      _wilayah,
      _noRekening,
      _atasNama,
      _bank
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      await prosesSimpanMaster(context,
          aksi: _ubah ? 'si_customer_update' : 'si_customer_create',
          body: {
        if (_ubah) 'anggota_id': widget.data!['anggotaId'],
        if (!_ubah) 'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'alamat': _alamat.text.trim(),
        'telp': _telp.text.trim(),
        'hp': _hp.text.trim(),
        'email': _email.text.trim(),
        'termin_hari': int.tryParse(_termin.text.trim()) ?? 0,
        'diskon_default_persen':
            double.tryParse(_diskon.text.replaceAll(',', '.')) ?? 0,
        'limit_kredit':
            double.tryParse(_limitKredit.text.replaceAll(',', '.')) ?? 0,
        'wilayah': _wilayah.text.trim(),
        'no_rekening': _noRekening.text.trim(),
        'atas_nama': _atasNama.text.trim(),
        'bank': _bank.text.trim(),
        'sales_owner_id': _salesOwnerId,
      },
          kunci: _ubah
              ? 'si_customer:${widget.data!['anggotaId']}'
              : 'si_customer:baru:${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Future<bool> _konfirmasiTutup() async {
    if (!_adaPerubahan) return true;
    final keluar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perubahan belum disimpan'),
        content: const Text(
            'Ada perubahan yang belum disimpan. Tutup tanpa menyimpan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Kembali')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buang', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return keluar == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _konfirmasiTutup() && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, sc) => Form(
            key: _formKey,
            child: AppFormSheet(
              scrollController: sc,
              title: _ubah ? 'Ubah Customer' : 'Tambah Customer',
              subtitle: _ubah
                  ? 'Kode legacy terkunci; snapshot pada faktur historis tidak berubah.'
                  : 'Kode teks legacy (nol di depan dipertahankan); duplikat ditolak.',
              icon: _ubah ? Icons.edit_outlined : Icons.people_alt_outlined,
              errorText: _error,
              errorDetail: detailUntuk(_error),
              children: [
                AppFormSection(judul: 'Identitas Customer', children: [
                  AppFormTextField(
                    label: _ubah ? 'Kode (terkunci)' : 'Kode Customer *',
                    controller: _kode,
                    readOnly: _ubah,
                    enabled: !_ubah,
                    validator: (v) => !_ubah && (v == null || v.trim().isEmpty)
                        ? 'Wajib diisi'
                        : null,
                  ),
                  AppFormTextField(
                    label: 'Nama Customer *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                      label: 'Alamat', controller: _alamat, maxLines: 2),
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'Telepon', controller: _telp)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(label: 'HP', controller: _hp)),
                  ]),
                  AppFormTextField(label: 'Email', controller: _email),
                ]),
                const SizedBox(height: 12),
                AppFormSection(judul: 'Profil Distribusi & Saldo', children: [
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'Termin (hari)',
                            controller: _termin,
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(
                            label: 'Diskon Default (%)',
                            controller: _diskon,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true))),
                  ]),
                  AppFormTextField(
                      label: 'Limit Kredit (Rp)',
                      controller: _limitKredit,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true)),
                  AppFormTextField(label: 'Wilayah', controller: _wilayah),
                  DropdownButtonFormField<int?>(
                    value: _daftarSales.any((s) => s['id'] == _salesOwnerId)
                        ? _salesOwnerId
                        : null,
                    decoration: AppFormStyle.fieldDecoration(context,
                        labelText: 'Sales Pembina'),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('- Tanpa sales -')),
                      ..._daftarSales.map((s) => DropdownMenuItem<int?>(
                          value: (s['id'] as num).toInt(),
                          child: Text('${s['kode']} — ${s['nama']}'))),
                    ],
                    onChanged: (v) => setStateIfMounted(() {
                      _salesOwnerId = v;
                      _adaPerubahan = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'No. Rekening', controller: _noRekening)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(
                            label: 'Atas Nama', controller: _atasNama)),
                  ]),
                  AppFormTextField(label: 'Bank', controller: _bank),
                ]),
              ],
              actions: [
                OutlinedButton.icon(
                  onPressed: _menyimpan
                      ? null
                      : () async {
                          if (await _konfirmasiTutup() && context.mounted) {
                            Navigator.of(context).pop(false);
                          }
                        },
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
