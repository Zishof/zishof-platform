import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
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

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Master Supplier -- layar legacy 01-03 (Data Supplier / Buka-Tutup Daftar).</h3>
///
/// Paritas fungsional (Matriks 48 layar baris 1-3):
/// - Daftar search-first server-side (`si_supplier_list`: kode/nama/alamat/wilayah),
///   urut Kode/Nama/Wilayah, filter status, paginasi (padanan Pertama/Sebelum/
///   Berikut/Terakhir).
/// - Tap baris = buka DETAIL (padanan Buka Daftar/pilih record -- membuka detail
///   TIDAK menyimpan apa pun); tutup sheet = padanan Tutup Daftar (record aktif
///   dipertahankan di state daftar, tanpa perubahan data).
/// - Tambah/Ubah (`si_supplier_create/update`): identitas + termin + wilayah +
///   rekening bank; kode legacy 3 karakter teks TIDAK bisa diubah setelah tersimpan.
/// - Nonaktifkan (padanan aman Hapus master) dgn alasan wajib; Saldo Hutang
///   baca-saja (ledger AP fase P3 -- tampil "-" sampai tersedia, bukan 0 palsu).
/// - Cetak/ekspor daftar supplier menyusul fase laporan (tombol dinonaktifkan
///   DENGAN alasan terlihat -- diizinkan Panduan v2 selama ada rute kerja).
class MasterSupplierScreen extends StatefulWidget {
  const MasterSupplierScreen({super.key});

  @override
  State<MasterSupplierScreen> createState() => _MasterSupplierScreenState();
}

class _MasterSupplierScreenState extends State<MasterSupplierScreen> {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  String? _filterAktif = 'aktif';
  String _sort = 'kode';
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
      await MasterOffline.daftarCacheDulu('si_supplier_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        if (_filterAktif != null) 'aktif': _filterAktif,
        'sort': _sort,
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:si_supplier', onData: (hasil) {
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
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Future<void> _bukaDetail(Map<String, dynamic> baris) async {
    Map<String, dynamic> detail = baris;
    try {
      final hasil = await ApiClient.instance
          .aksi('si_supplier_detail', {'id': baris['id']});
      detail = (hasil['data'] as Map<String, dynamic>?) ?? baris;
    } catch (_) {
      // Gagal ambil detail (offline?) -- pakai data baris daftar apa adanya.
    }
    if (!mounted) return;
    final aksi = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DetailSupplierSheet(data: detail),
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
      builder: (_) => _FormSupplier(data: data),
    );
    if (tersimpan == true) await _muat();
  }

  Future<void> _ubahStatus(Map<String, dynamic> data,
      {required bool aktifkan}) async {
    final alasanCtrl = TextEditingController();
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aktifkan ? 'Aktifkan Supplier?' : 'Nonaktifkan Supplier?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(aktifkan
                ? 'Supplier "${data['nama']}" akan diaktifkan kembali.'
                : 'Master berhistori tidak dihapus fisik -- supplier "${data['nama']}" '
                    'hanya dinonaktifkan dan tetap bisa diaktifkan lagi.'),
            if (!aktifkan) ...[
              const SizedBox(height: 12),
              TextField(
                controller: alasanCtrl,
                decoration: const InputDecoration(
                    labelText: 'Alasan (wajib, tercatat di audit)',
                    border: OutlineInputBorder()),
              ),
            ],
          ],
        ),
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
      await prosesSimpanMaster(context, aksi: 'si_supplier_deactivate', body: {
        'id': data['id'],
        'aktif': aktifkan,
        if (!aktifkan) 'alasan': alasanCtrl.text.trim(),
      }, kunci: 'si_supplier:${data['id']}');
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
    final bolehTambah = Sesi.instance.bolehAksiIs('master_supplier', 'create');
    return AppShell(
      menuAktif: MenuEBisnis.masterSupplier,
      judul: 'Master Supplier',
      subjudul:
          'Identitas pemasok, termin, wilayah, dan rekening (layar legacy 01-03)',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message:
              'Cetak/ekspor daftar supplier tersedia di fase laporan (P2-F) -- belum aktif di rilis ini.',
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
              label: const Text('Tambah Supplier'))
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
                          child: TextField(
                            decoration: const InputDecoration(
                                hintText: 'Cari kode, nama, alamat, wilayah...',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                isDense: true),
                            onSubmitted: (v) {
                              _kataKunci = v.trim();
                              _halaman = 1;
                              _muat();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 130,
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
                          width: 130,
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
                      ]),
                      const SizedBox(height: 12),
                      BannerPerubahanServer(
                        key: ValueKey('perubahan:$_versiPerubahan'),
                        baru: _idBaru.length,
                        berubah: _idBerubah.length,
                        dihapus: _jumlahHapus,
                      ),
                      AppDataTable(
                        minWidth: 860,
                        emptyText: 'Belum ada supplier.',
                        columns: const [
                          AppTableColumn('Kode', flex: 1),
                          AppTableColumn('Nama Supplier', flex: 3),
                          AppTableColumn('Wilayah', flex: 2),
                          AppTableColumn('Termin',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Telepon', flex: 2),
                          AppTableColumn('Status',
                              flex: 1, align: TextAlign.center),
                        ],
                        rows: _data.map((s) {
                          final aktif = s['aktif'] == true;
                          return AppTableRowData(
                            onTap: () => _bukaDetail(s),
                            cells: [
                              AppTableCell(
                                flex: 1,
                                child: KilauBaris(
                                  kunci: '${s['id'] ?? s['_kunci'] ?? ''}',
                                  idBaru: _idBaru,
                                  idBerubah: _idBerubah,
                                  child: SelTeksDenganSinkron(
                                    kunci: 'si_supplier:${s['id']}',
                                    teks: '${s['kode']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'monospace',
                                        fontSize: 12.5),
                                  ),
                                ),
                              ),
                              AppTableCell.text('${s['nama']}',
                                  flex: 3, maxLines: 2),
                              AppTableCell.text('${s['wilayah'] ?? ''}',
                                  flex: 2),
                              AppTableCell.text('${s['terminHari'] ?? 0} hr',
                                  flex: 1, align: TextAlign.right),
                              AppTableCell.text('${s['telp'] ?? ''}', flex: 2),
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
                          labelData: 'supplier',
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

/// Detail supplier (padanan layar 03: menutup sheet TIDAK mengubah record).
class _DetailSupplierSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DetailSupplierSheet({required this.data});

  @override
  Widget build(BuildContext context) {
    final aktif = data['aktif'] == true;
    final bolehUbah = Sesi.instance.bolehAksiIs('master_supplier', 'update');
    final bolehNonaktif =
        Sesi.instance.bolehAksiIs('master_supplier', 'delete') ||
            Sesi.instance.bolehAksiIs('master_supplier', 'update');
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
          AppFormSection(judul: 'Identitas Supplier', children: [
            baris('Kode (legacy, terkunci)', '${data['kode'] ?? ''}'),
            baris('Nama', '${data['nama'] ?? ''}'),
            baris('Alamat', '${data['alamat'] ?? ''}'),
            baris('Wilayah', '${data['wilayah'] ?? ''}'),
            baris('Telepon', '${data['telp'] ?? ''}'),
            baris('Kontak', '${data['kontak'] ?? ''}'),
            baris('Email', '${data['email'] ?? ''}'),
            baris('Keterangan', '${data['keterangan'] ?? ''}'),
          ]),
          const SizedBox(height: 12),
          AppFormSection(judul: 'Relasi & Saldo', children: [
            baris('Termin Pembayaran', '${data['terminHari'] ?? 0} hari'),
            baris('No. Rekening', '${data['noRekening'] ?? ''}'),
            baris('Atas Nama', '${data['atasNama'] ?? ''}'),
            baris('Bank', '${data['bank'] ?? ''}'),
            baris('Alamat Bank', '${data['alamatBank'] ?? ''}'),
            baris(
                'Saldo Hutang',
                data['saldoHutang'] == null
                    ? '- (ledger hutang supplier tersedia di fase P3)'
                    : _fmtRp.format(data['saldoHutang'])),
          ]),
          const SizedBox(height: 12),
          AppFormSection(judul: 'Riwayat Audit', children: [
            baris('Terakhir diubah oleh', '${data['auditOleh'] ?? ''}'),
            baris('Waktu perubahan', '${data['auditWaktu'] ?? ''}'),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Seluruh perubahan tercatat otomatis (Envers) di server; '
                  'riwayat lengkap dapat diminta ke admin.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondaryOf(context))),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                // Paritas aksi "Riwayat Audit" legacy: baca revisi Envers profil.
                // Disabled beralasan bila supplier belum punya profil varian
                // (belum ada revisi untuk dibaca) -- bukan disembunyikan.
                Tooltip(
                  message: data['profilId'] == null
                      ? 'Belum ada profil varian tersimpan — belum ada revisi audit.'
                      : 'Riwayat perubahan (Envers)',
                  child: OutlinedButton.icon(
                      onPressed: data['profilId'] == null
                          ? null
                          : () => tampilkanRiwayatAudit(context, 'supplier',
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

class _FormSupplier extends StatefulWidget {
  final Map<String, dynamic>? data;
  const _FormSupplier({required this.data});

  @override
  State<_FormSupplier> createState() => _FormSupplierState();
}

class _FormSupplierState extends State<_FormSupplier> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _alamat;
  late final TextEditingController _telp;
  late final TextEditingController _kontak;
  late final TextEditingController _email;
  late final TextEditingController _keterangan;
  late final TextEditingController _termin;
  late final TextEditingController _wilayah;
  late final TextEditingController _noRekening;
  late final TextEditingController _atasNama;
  late final TextEditingController _bank;
  late final TextEditingController _alamatBank;
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
    _kontak = TextEditingController(text: d?['kontak'] ?? '');
    _email = TextEditingController(text: d?['email'] ?? '');
    _keterangan = TextEditingController(text: d?['keterangan'] ?? '');
    _termin = TextEditingController(text: '${d?['terminHari'] ?? 0}');
    _wilayah = TextEditingController(text: d?['wilayah'] ?? '');
    _noRekening = TextEditingController(text: d?['noRekening'] ?? '');
    _atasNama = TextEditingController(text: d?['atasNama'] ?? '');
    _bank = TextEditingController(text: d?['bank'] ?? '');
    _alamatBank = TextEditingController(text: d?['alamatBank'] ?? '');
    for (final c in [
      _kode,
      _nama,
      _alamat,
      _telp,
      _kontak,
      _email,
      _keterangan,
      _termin,
      _wilayah,
      _noRekening,
      _atasNama,
      _bank,
      _alamatBank
    ]) {
      c.addListener(() => _adaPerubahan = true);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _kode,
      _nama,
      _alamat,
      _telp,
      _kontak,
      _email,
      _keterangan,
      _termin,
      _wilayah,
      _noRekening,
      _atasNama,
      _bank,
      _alamatBank
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
          aksi: _ubah ? 'si_supplier_update' : 'si_supplier_create',
          body: {
        if (_ubah) 'id': widget.data!['id'],
        if (!_ubah) 'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'alamat': _alamat.text.trim(),
        'telp': _telp.text.trim(),
        'kontak': _kontak.text.trim(),
        'email': _email.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'termin_hari': int.tryParse(_termin.text.trim()) ?? 0,
        'wilayah': _wilayah.text.trim(),
        'no_rekening': _noRekening.text.trim(),
        'atas_nama': _atasNama.text.trim(),
        'bank': _bank.text.trim(),
        'alamat_bank': _alamatBank.text.trim(),
      },
          kunci: _ubah
              ? 'si_supplier:${widget.data!['id']}'
              : 'si_supplier:baru:${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
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
              title: _ubah ? 'Ubah Supplier' : 'Tambah Supplier',
              subtitle: _ubah
                  ? 'Kode legacy terkunci; perubahan rekening/bank tercatat di audit.'
                  : 'Kode dipertahankan sebagai teks (nol di depan tidak hilang).',
              icon: _ubah ? Icons.edit_outlined : Icons.local_shipping_outlined,
              errorText: _error,
              children: [
                AppFormSection(judul: 'Identitas Supplier', children: [
                  AppFormTextField(
                    label: _ubah ? 'Kode (terkunci)' : 'Kode Supplier *',
                    controller: _kode,
                    readOnly: _ubah,
                    enabled: !_ubah,
                    validator: (v) => !_ubah && (v == null || v.trim().isEmpty)
                        ? 'Wajib diisi'
                        : null,
                  ),
                  AppFormTextField(
                    label: 'Nama Supplier *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                      label: 'Alamat', controller: _alamat, maxLines: 2),
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'No. Telepon', controller: _telp)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(
                            label: 'Kontak (PIC)', controller: _kontak)),
                  ]),
                  AppFormTextField(label: 'Email', controller: _email),
                  AppFormTextField(
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 2),
                ]),
                const SizedBox(height: 12),
                AppFormSection(judul: 'Kontrol Relasi & Saldo', children: [
                  Row(children: [
                    Expanded(
                        child: AppFormTextField(
                            label: 'Termin Pembayaran (hari)',
                            controller: _termin,
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppFormTextField(
                            label: 'Wilayah', controller: _wilayah)),
                  ]),
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
                  AppFormTextField(
                      label: 'Alamat Bank', controller: _alamatBank),
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
