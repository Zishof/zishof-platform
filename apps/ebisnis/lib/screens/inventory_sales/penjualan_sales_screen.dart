import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _fmtRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Penjualan Sales / Sales Order (layar legacy 30-31).</h3>
///
/// Order BUKAN invoice: status "Mode Sales Lapangan" DRAFT -> PESAN ->
/// SIAP_KIRIM -> TERKIRIM -> SIAP_TAGIH (faktur piutang terbit lewat aksi
/// `si_sales_order_invoice`, idempoten per order) -> LUNAS (derivasi
/// pelunasan). Sales keliling hanya melihat order miliknya (scope server).
/// Deep-link SCR-31: dari order SIAP_TAGIH langsung terlihat nomor faktur
/// piutangnya (ledger yang sama, tanpa duplikasi).
class PenjualanSalesScreen extends StatefulWidget {
  const PenjualanSalesScreen({super.key});

  @override
  State<PenjualanSalesScreen> createState() => _PenjualanSalesScreenState();
}

const _semuaStatus = [
  'SEMUA', 'DRAFT', 'PESAN', 'SIAP_KIRIM', 'TERKIRIM', 'SIAP_TAGIH', 'LUNAS', 'BATAL'
];

Color _warnaStatus(String s) {
  switch (s) {
    case 'DRAFT':
      return Colors.blueGrey;
    case 'PESAN':
      return Colors.blue;
    case 'SIAP_KIRIM':
      return Colors.orange;
    case 'TERKIRIM':
      return Colors.deepPurple;
    case 'SIAP_TAGIH':
      return Colors.teal;
    case 'LUNAS':
      return AppColors.success;
    case 'BATAL':
      return AppColors.danger;
  }
  return Colors.grey;
}

class _PenjualanSalesScreenState extends State<PenjualanSalesScreen> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  String _filterStatus = 'SEMUA';
  String _kataKunci = '';
  int _halaman = 1;
  // Diff emisi lokal-dulu: menggerakkan kilau baris + banner perubahan server.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

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
      // Baca LOKAL DULU (lihat MasterOffline.daftarCacheDulu): snapshot cache
      // tampil seketika, hasil server menyusul + diff utk kilau baris.
      await MasterOffline.daftarCacheDulu('si_sales_order_list', {
        if (_filterStatus != 'SEMUA') 'status': _filterStatus,
        if (_kataKunci.isNotEmpty) 'q': _kataKunci,
        'page': _halaman,
        'page_size': 30,
      }, 'master:si_sales_order:$_filterStatus', fieldData: 'rows',
          onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil, fieldData: 'rows');
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaForm({int? orderId}) async {
    final tersimpan = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _FormOrder(orderId: orderId)));
    if (tersimpan == true) _muat();
  }

  Future<void> _bukaDetail(Map<String, dynamic> row) async {
    final berubah = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DetailOrderSheet(orderId: (row['id'] as num).toInt()),
    );
    if (berubah == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final bolehBuat = Sesi.instance.bolehAksiIs('penjualan_sales', 'create');
    return AppShell(
      menuAktif: MenuEBisnis.penjualanSales,
      judul: 'Penjualan Sales (Sales Order)',
      subjudul:
          'Order lapangan: PESAN → SIAP KIRIM → TERKIRIM → SIAP TAGIH (faktur piutang) — layar legacy 30-31',
      scrollable: false,
      floatingActionButton: bolehBuat
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Order Baru', style: TextStyle(color: Colors.white)),
            )
          : null,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(children: [
            Expanded(
              child: AppSearchField(
                hintText: 'Cari nomor order / nama customer...',
                onChanged: (v) {
                  _kataKunci = v.trim();
                  _halaman = 1;
                  _muat();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
                onPressed: _muat,
                tooltip: 'Muat ulang',
                icon: const Icon(Icons.refresh)),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              for (final s in _semuaStatus)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s.replaceAll('_', ' '),
                        style: const TextStyle(fontSize: 12)),
                    selected: _filterStatus == s,
                    onSelected: (_) {
                      setStateIfMounted(() => _filterStatus = s);
                      _halaman = 1;
                      _muat();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: BannerPerubahanServer(
            key: ValueKey('perubahan:${_diff.versi}'),
            baru: _diff.idBaru.length,
            berubah: _diff.idBerubah.length,
            dihapus: _diff.jumlahHapus,
          ),
        ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _PanelError(pesan: _error!, detail: detailUntuk(_error), onCoba: _muat)
                  : _data.isEmpty
                      ? Center(
                          child: Text(
                              'Belum ada sales order.\nBuat order baru dgn tombol di kanan bawah.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.textSecondaryOf(context))))
                      : RefreshIndicator(
                          onRefresh: _muat,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 80),
                            itemCount: _data.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final r = _data[i];
                              final status = '${r['status']}';
                              return KilauBaris(
                                kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                                idBaru: _diff.idBaru,
                                idBerubah: _diff.idBerubah,
                                child: _KartuOrder(
                                onTap: () => _bukaDetail(r),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${r['nomor']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5)),
                                        const SizedBox(height: 2),
                                        Text(
                                            '${r['customerNama']}'
                                            '${'${r['salesNama']}'.isNotEmpty ? ' · Sales: ${r['salesNama']}' : ''}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors
                                                    .textSecondaryOf(context))),
                                        Text('${r['tanggal']}'.split('.').first,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors
                                                    .textSecondaryOf(context))),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_fmtRp.format(r['total'] ?? 0),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: _warnaStatus(status)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(status.replaceAll('_', ' '),
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: _warnaStatus(status))),
                                      ),
                                    ],
                                  ),
                                ]),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

// =============================================================================
// DETAIL + transisi status
// =============================================================================

class _DetailOrderSheet extends StatefulWidget {
  final int orderId;
  const _DetailOrderSheet({required this.orderId});

  @override
  State<_DetailOrderSheet> createState() => _DetailOrderSheetState();
}

class _DetailOrderSheetState extends State<_DetailOrderSheet> with JejakGalat {
  Map<String, dynamic>? _d;
  String? _error;
  bool _proses = false;
  bool _adaPerubahan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('si_sales_order_detail', {'order_id': widget.orderId});
      setStateIfMounted(
          () => _d = Map<String, dynamic>.from(hasil['data'] as Map));
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    }
  }

  Future<void> _ubahStatus(String statusBaru, {String? alasan}) async {
    setStateIfMounted(() => _proses = true);
    try {
      await ApiClient.instance.aksi('si_sales_order_status', {
        'order_id': widget.orderId,
        'status': statusBaru,
        if (alasan != null) 'alasan': alasan,
      });
      _adaPerubahan = true;
      await _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  Future<void> _terbitkanFaktur() async {
    setStateIfMounted(() => _proses = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('si_sales_order_invoice', {'order_id': widget.orderId});
      _adaPerubahan = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Faktur piutang terbit: ${hasil['nomor']} '
                '(jatuh tempo ${hasil['jatuhTempo'] ?? '-'}). Tagih lewat menu Piutang.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  Future<void> _konfirmasiBatal() async {
    final ctrl = TextEditingController();
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Batalkan Order?'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'Alasan pembatalan (wajib)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Tidak')),
          TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (ya == true && ctrl.text.trim().isNotEmpty) {
      await _ubahStatus('BATAL', alasan: ctrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scroll) {
          if (_error != null) {
            return _PanelError(pesan: _error!, detail: detailUntuk(_error), onCoba: _muat);
          }
          final d = _d;
          if (d == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final status = '${d['status']}';
          final items = ((d['items'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final bolehUbah = Sesi.instance.bolehAksiIs('penjualan_sales', 'update');
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: Text('${d['nomor']}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: _warnaStatus(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(status.replaceAll('_', ' '),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _warnaStatus(status))),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Customer: ${d['customerNama']}'),
              if ('${d['salesNama']}'.isNotEmpty) Text('Sales: ${d['salesNama']}'),
              Text('Tanggal: ${'${d['tanggal']}'.split('.').first}'),
              if ('${d['keterangan']}'.isNotEmpty)
                Text('Catatan: ${d['keterangan']}'),
              if (status == 'BATAL' && '${d['alasanBatal']}'.isNotEmpty)
                Text('Alasan batal: ${d['alasanBatal']}',
                    style: TextStyle(color: AppColors.danger)),
              if (d['piutangDocId'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AppInfoBanner(
                      icon: Icons.link,
                      color: AppColors.info,
                      text:
                          'Faktur piutang: ${d['piutangDocNomor']} — kelola & terima pembayarannya di menu Piutang Customer (ledger yang sama, tanpa duplikasi).'),
                ),
              const Divider(height: 24),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                        child: Text('${it['namaProduk']}',
                            style: const TextStyle(fontSize: 12.5))),
                    Text(
                        '${it['jumlah']} × ${_fmtRp.format(it['hargaSatuan'] ?? 0)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context))),
                    const SizedBox(width: 10),
                    Text(_fmtRp.format(it['subtotal'] ?? 0),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              const Divider(height: 24),
              Row(children: [
                const Expanded(
                    child: Text('TOTAL',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                Text(_fmtRp.format(d['total'] ?? 0),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 16),
              if (_proses) const LinearProgressIndicator(),
              if (!_proses && bolehUbah)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (status == 'DRAFT' || status == 'PESAN')
                    OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _FormOrder(orderId: widget.orderId)));
                          if (ok == true) {
                            _adaPerubahan = true;
                            _muat();
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Ubah Item')),
                  if (status == 'DRAFT')
                    ElevatedButton(
                        onPressed: () => _ubahStatus('PESAN'),
                        child: const Text('Konfirmasi (PESAN)')),
                  if (status == 'PESAN')
                    ElevatedButton(
                        onPressed: () => _ubahStatus('SIAP_KIRIM'),
                        child: const Text('Siap Kirim')),
                  if (status == 'SIAP_KIRIM')
                    ElevatedButton(
                        onPressed: () => _ubahStatus('TERKIRIM'),
                        child: const Text('Tandai Terkirim')),
                  if (status == 'TERKIRIM')
                    ElevatedButton.icon(
                        onPressed: _terbitkanFaktur,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text('Terbitkan Faktur (SIAP TAGIH)')),
                  if (status == 'DRAFT' ||
                      status == 'PESAN' ||
                      status == 'SIAP_KIRIM')
                    TextButton.icon(
                        onPressed: _konfirmasiBatal,
                        icon: Icon(Icons.cancel_outlined,
                            size: 18, color: AppColors.danger),
                        label: Text('Batalkan',
                            style: TextStyle(color: AppColors.danger))),
                ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_adaPerubahan),
                    child: const Text('Tutup')),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// FORM order (create/update) + picker customer & produk
// =============================================================================

class _ItemOrder {
  int produkId;
  String nama;
  double harga;
  double jumlah;
  _ItemOrder(this.produkId, this.nama, this.harga, this.jumlah);
  double get subtotal => harga * jumlah;
}

class _FormOrder extends StatefulWidget {
  final int? orderId;
  const _FormOrder({this.orderId});

  @override
  State<_FormOrder> createState() => _FormOrderState();
}

class _FormOrderState extends State<_FormOrder> with JejakGalat {
  int? _customerId;
  String _customerNama = '';
  int? _salesId;
  String _salesNama = '';
  final List<_ItemOrder> _items = [];
  final _keterangan = TextEditingController();
  bool _memuat = false;
  bool _menyimpan = false;
  String? _error;

  /// Kunci idempoten create dibuat SEKALI per pembukaan form (retry Simpan
  /// aman, server tidak menggandakan order).
  late final String _kodeUnik =
      'SO-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) _muatOrder();
  }

  Future<void> _muatOrder() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('si_sales_order_detail', {'order_id': widget.orderId});
      final d = Map<String, dynamic>.from(hasil['data'] as Map);
      setStateIfMounted(() {
        _customerId = (d['customerId'] as num?)?.toInt();
        _customerNama = '${d['customerNama']}';
        _salesId = (d['salesId'] as num?)?.toInt();
        _salesNama = '${d['salesNama']}';
        _keterangan.text = '${d['keterangan']}';
        _items.clear();
        for (final e in (d['items'] as List? ?? [])) {
          final m = Map<String, dynamic>.from(e as Map);
          _items.add(_ItemOrder(
              (m['produkId'] as num).toInt(),
              '${m['namaProduk']}',
              (m['hargaSatuan'] as num?)?.toDouble() ?? 0,
              (m['jumlah'] as num?)?.toDouble() ?? 0));
        }
      });
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihCustomer() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => const _DialogCariCustomer());
    if (pilihan != null) {
      setStateIfMounted(() {
        _customerId = (pilihan['anggotaId'] as num).toInt();
        _customerNama = '${pilihan['nama']}';
      });
    }
  }

  Future<void> _pilihSales() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _DialogCariSales());
    if (pilihan != null) {
      setStateIfMounted(() {
        _salesId = (pilihan['id'] as num).toInt();
        _salesNama = '${pilihan['nama']}';
      });
    }
  }

  Future<void> _tambahItem() async {
    final pilihan = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _DialogCariProduk());
    if (pilihan == null) return;
    setStateIfMounted(() {
      _items.add(_ItemOrder(
          (pilihan['id'] as num).toInt(),
          '${pilihan['nama']}',
          (pilihan['hargaJual'] as num?)?.toDouble() ?? 0,
          1));
    });
  }

  double get _total {
    var t = 0.0;
    for (final it in _items) {
      t += it.subtotal;
    }
    return t;
  }

  Future<void> _simpan() async {
    if (_customerId == null) {
      setStateIfMounted(() => _error = 'Customer wajib dipilih.');
      return;
    }
    if (_items.isEmpty) {
      setStateIfMounted(() => _error = 'Order minimal berisi satu item.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      await ApiClient.instance.aksi(
          widget.orderId == null ? 'si_sales_order_create' : 'si_sales_order_update', {
        if (widget.orderId != null) 'order_id': widget.orderId,
        if (widget.orderId == null) 'customer_id': _customerId,
        if (widget.orderId == null && _salesId != null) 'sales_id': _salesId,
        if (widget.orderId == null) 'kode_unik': _kodeUnik,
        'keterangan': _keterangan.text.trim(),
        'items': [
          for (final it in _items)
            {
              'produk_id': it.produkId,
              'jumlah': it.jumlah,
              'harga': it.harga,
            }
        ],
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sales keliling: server memaksa order atas nama dirinya -- picker sales
    // disembunyikan supaya UI tidak menjanjikan hal yang akan ditolak server.
    final tampilkanPilihSales =
        !Sesi.instance.isSalesKeliling && widget.orderId == null;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.orderId == null
              ? 'Sales Order Baru'
              : 'Ubah Sales Order')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppInfoBanner(
                      icon: Icons.error_outline,
                      color: AppColors.danger,
                      text: _error!),
                ),
              AppFormSection(judul: 'Customer & Sales', children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.people_alt_outlined),
                  title: Text(_customerNama.isEmpty
                      ? 'Pilih customer...'
                      : _customerNama),
                  trailing: widget.orderId == null
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: widget.orderId == null ? _pilihCustomer : null,
                ),
                if (tampilkanPilihSales)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(_salesNama.isEmpty
                        ? 'Pilih sales (opsional)...'
                        : _salesNama),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pilihSales,
                  ),
                TextField(
                    controller: _keterangan,
                    decoration:
                        const InputDecoration(labelText: 'Catatan (opsional)')),
              ]),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Item Order',
                aksiJudul: TextButton.icon(
                    onPressed: _tambahItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah')),
                children: [
                  if (_items.isEmpty)
                    Text('Belum ada item — tekan "Tambah".',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context))),
                  for (var i = 0; i < _items.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(
                            flex: 3,
                            child: Text(_items[i].nama,
                                style: const TextStyle(fontSize: 12.5))),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: '${_items[i].harga.round()}',
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Harga'),
                            onChanged: (v) => setStateIfMounted(() =>
                                _items[i].harga = double.tryParse(v) ?? 0),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: TextFormField(
                            initialValue: _items[i].jumlah % 1 == 0
                                ? '${_items[i].jumlah.round()}'
                                : '${_items[i].jumlah}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Qty'),
                            onChanged: (v) => setStateIfMounted(() =>
                                _items[i].jumlah = double.tryParse(v) ?? 0),
                          ),
                        ),
                        IconButton(
                            onPressed: () =>
                                setStateIfMounted(() => _items.removeAt(i)),
                            icon: Icon(Icons.delete_outline,
                                size: 20, color: AppColors.danger)),
                      ]),
                    ),
                  const Divider(),
                  Row(children: [
                    const Expanded(
                        child: Text('TOTAL',
                            style: TextStyle(fontWeight: FontWeight.w800))),
                    Text(_fmtRp.format(_total),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ]),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan Order'),
              ),
            ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Picker dialogs (customer / sales / produk) -- pola search-first sederhana.
// -----------------------------------------------------------------------------

class _KartuOrder extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _KartuOrder({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Theme.of(context).dividerColor)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  final String pesan;
  final VoidCallback onCoba;
  final String? detail;
  const _PanelError(
      {required this.pesan, required this.onCoba, this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(pesan, textAlign: TextAlign.center),
          AppDetailGalatOpsional(detail: detail),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onCoba, child: const Text('Coba Lagi')),
        ]),
      ),
    );
  }
}

class _DialogCariCustomer extends StatefulWidget {
  const _DialogCariCustomer();
  @override
  State<_DialogCariCustomer> createState() => _DialogCariCustomerState();
}

class _DialogCariCustomerState extends State<_DialogCariCustomer> {
  List<Map<String, dynamic>> _rows = [];
  bool _memuat = false;

  Future<void> _cari(String q) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi('si_customer_list', {
        if (q.isNotEmpty) 'keyword': q,
        'aktif': 'aktif',
        'page': 1,
        'page_size': 20,
      });
      setStateIfMounted(() => _rows = ((hasil['rows'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Customer'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Cari kode/nama/wilayah...',
                  prefixIcon: Icon(Icons.search)),
              onSubmitted: _cari),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  dense: true,
                  title: Text('${r['kode']} — ${r['nama']}'),
                  subtitle: Text('${r['wilayah'] ?? ''}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DialogCariSales extends StatefulWidget {
  const _DialogCariSales();
  @override
  State<_DialogCariSales> createState() => _DialogCariSalesState();
}

class _DialogCariSalesState extends State<_DialogCariSales> {
  List<Map<String, dynamic>> _rows = [];
  bool _memuat = false;

  Future<void> _cari(String q) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi('si_sales_list', {
        if (q.isNotEmpty) 'keyword': q,
        'aktif': 'aktif',
        'page': 1,
        'page_size': 20,
      });
      setStateIfMounted(() => _rows = ((hasil['rows'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Sales'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Cari kode/nama/area...',
                  prefixIcon: Icon(Icons.search)),
              onSubmitted: _cari),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  dense: true,
                  title: Text('${r['kode']} — ${r['nama']}'),
                  subtitle: Text('${r['area'] ?? ''}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DialogCariProduk extends StatefulWidget {
  const _DialogCariProduk();
  @override
  State<_DialogCariProduk> createState() => _DialogCariProdukState();
}

class _DialogCariProdukState extends State<_DialogCariProduk> {
  List<Map<String, dynamic>> _rows = [];
  bool _memuat = false;

  Future<void> _cari(String q) async {
    setStateIfMounted(() => _memuat = true);
    try {
      // Reuse aksi 'katalog' POS existing (id/kode/nama/hargaJual/stok) --
      // tersedia utk semua aktor tanpa gerbang si_ tambahan.
      final hasil = await ApiClient.instance.aksi('katalog', {
        if (q.isNotEmpty) 'keyword': q,
      });
      setStateIfMounted(() => _rows = ((hasil['produk'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(30)
          .toList());
    } catch (_) {
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Produk'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Cari kode/nama produk...',
                  prefixIcon: Icon(Icons.search)),
              onSubmitted: _cari),
          const SizedBox(height: 8),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  dense: true,
                  title: Text('${r['kode']} — ${r['nama']}'),
                  subtitle: Text(
                      '${_fmtRp.format(r['hargaJual'] ?? 0)} · stok ${r['stok'] ?? 0}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
