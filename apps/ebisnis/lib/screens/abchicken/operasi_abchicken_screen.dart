import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

class _ProsesRantaiPasok {
  final String kode;
  final String label;
  final IconData ikon;
  final bool dapatPosting;
  const _ProsesRantaiPasok(this.kode, this.label, this.ikon, this.dapatPosting);
}

const _prosesRantaiPasok = <_ProsesRantaiPasok>[
  _ProsesRantaiPasok(
      'ringkasan', 'Ringkasan UAT', Icons.fact_check_outlined, false),
  _ProsesRantaiPasok(
      'outlet_order', 'Pesanan Outlet', Icons.storefront_outlined, false),
  _ProsesRantaiPasok('bom', 'Resep / BOM', Icons.account_tree_outlined, false),
  _ProsesRantaiPasok(
      'pos_sale', 'Penjualan POS', Icons.point_of_sale_outlined, true),
  _ProsesRantaiPasok('procurement_pr', 'PR', Icons.assignment_outlined, false),
  _ProsesRantaiPasok(
      'procurement_po', 'PO', Icons.receipt_long_outlined, false),
  _ProsesRantaiPasok(
      'procurement_bast', 'BAST', Icons.inventory_2_outlined, true),
  _ProsesRantaiPasok('procurement_invoice', 'Tagihan Vendor',
      Icons.request_quote_outlined, true),
  _ProsesRantaiPasok('procurement_payment', 'Pembayaran Vendor',
      Icons.payments_outlined, true),
  _ProsesRantaiPasok(
      'production', 'Produksi', Icons.precision_manufacturing_outlined, true),
  _ProsesRantaiPasok(
      'shipment', 'Pengiriman', Icons.local_shipping_outlined, true),
  _ProsesRantaiPasok(
      'claim', 'Backorder / Klaim', Icons.report_problem_outlined, false),
  _ProsesRantaiPasok(
      'account', 'Sumber Akun Posting', Icons.account_balance_outlined, false),
];

/// Pusat operasi rantai pasok untuk varian restoran multi-outlet.
///
/// Daftar selalu dibaca dari cache lokal lebih dahulu lalu disegarkan server
/// per halaman. Perubahan status, approval, dan posting sengaja online-only:
/// aksi tersebut mengubah stok/jurnal dan tidak aman diantrikan tanpa validasi
/// saldo serta periode akuntansi dari server.
class OperasiRantaiPasokScreen extends StatefulWidget {
  final String prosesAwal;
  const OperasiRantaiPasokScreen({super.key, this.prosesAwal = 'ringkasan'});

  @override
  State<OperasiRantaiPasokScreen> createState() =>
      _OperasiRantaiPasokScreenState();
}

class _OperasiRantaiPasokScreenState extends State<OperasiRantaiPasokScreen> {
  final _cari = TextEditingController();
  String _proses = 'ringkasan';
  String _status = 'SEMUA';
  String _posting = 'SEMUA';
  int _halaman = 1;
  int _total = 0;
  int _generasiMuat = 0;
  static const _batas = 50;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _data = const [];
  Map<String, dynamic> _ringkasan = const {};
  List<Map<String, dynamic>> _checks = const [];
  List<Map<String, dynamic>> _pemetaanAkun = const [];
  List<Map<String, dynamic>> _pilihanAkun = const [];

  _ProsesRantaiPasok get _konfigurasi =>
      _prosesRantaiPasok.firstWhere((e) => e.kode == _proses,
          orElse: () => _prosesRantaiPasok.first);

  @override
  void initState() {
    super.initState();
    _proses = widget.prosesAwal;
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    if (!mounted) return;
    final generasi = ++_generasiMuat;
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      if (_proses == 'ringkasan') {
        await _muatRingkasan(generasi);
      } else if (_proses == 'account') {
        await _muatPemetaanAkun(generasi);
      } else {
        await _muatDaftar(generasi);
      }
    } catch (e) {
      if (mounted && generasi == _generasiMuat) {
        setState(() => _galat = '$e');
      }
    } finally {
      if (mounted && generasi == _generasiMuat) {
        setState(() => _memuat = false);
      }
    }
  }

  Future<void> _muatRingkasan(int generasi) async {
    final ringkasan = await MasterOffline.objekDenganCache(
        'si_restaurant_summary', const {}, 'abchicken:ringkasan');
    final integritas = await MasterOffline.objekDenganCache(
        'si_restaurant_integrity', const {}, 'abchicken:integritas');
    if (!mounted || generasi != _generasiMuat) return;
    setState(() {
      _ringkasan = Map<String, dynamic>.from(ringkasan['data'] as Map? ?? {});
      _checks = (integritas['checks'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  Future<void> _muatDaftar(int generasi) async {
    final proses = _proses;
    final body = <String, dynamic>{
      'halaman': _halaman,
      'batas': _batas,
      if (_status != 'SEMUA') 'status': _status,
      if (_posting != 'SEMUA')
        'posting': _posting == 'TELAH DIPOSTING' ? 'SUDAH' : 'BELUM',
      if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
    };
    await MasterOffline.daftarCacheDulu(
      'si_restaurant_${_proses}_list',
      body,
      'abchicken:$_proses',
      onData: (hasil) {
        // Satu transisi status memicu refresh lama, lalu pengguna dapat segera
        // mengganti filter. Respons lama tidak boleh menimpa hasil filter baru.
        if (!mounted || generasi != _generasiMuat || proses != _proses) {
          return;
        }
        final rows = (hasil['data'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _data = rows;
          _total = (hasil['total'] as num?)?.toInt() ?? rows.length;
          _memuat = false;
        });
      },
    );
  }

  Future<void> _muatPemetaanAkun(int generasi) async {
    final mapping = await MasterOffline.daftarDenganCache(
      'si_restaurant_account_mapping_list',
      const {},
      'abchicken:account-mapping',
    );
    final options = await MasterOffline.daftarDenganCache(
      'si_restaurant_account_options',
      const {},
      'abchicken:account-options',
    );
    if (!mounted || generasi != _generasiMuat) return;
    setState(() {
      _pemetaanAkun = (mapping['data'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _pilihanAkun = (options['data'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  Future<void> _ubahStatus(Map<String, dynamic> row, String status) async {
    try {
      // Online-only: transisi status adalah approval operasional dan wajib
      // divalidasi server agar dua perangkat tidak mengesahkan dokumen sama.
      await ApiClient.instance.aksi('si_restaurant_${_proses}_status', {
        'id': row['id'],
        'status': status,
        'catatan': 'Diperbarui dari pusat operasi AB Chicken',
      });
      await _muat();
      if (mounted) _pesan('Status ${row['nomor']} menjadi $status.');
    } catch (e) {
      if (mounted) _pesan('$e', galat: true);
    }
  }

  Future<void> _postingDokumen(Map<String, dynamic> row) async {
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Posting ke Akuntansi'),
        content: Text(
            'Posting ${row['nomor']} akan membentuk jurnal dan mutasi stok. '
            'Penjualan membaca akun pendapatan dan HPP dari Master Produk serta '
            'akun persediaan bahan dari BOM. BAST dan produksi membaca akun '
            'persediaan dari Master Produk; akun GRNI, hutang, dan kas/bank '
            'berasal dari menu Sumber Akun Posting. Lanjutkan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Posting')),
        ],
      ),
    );
    if (lanjut != true) return;
    try {
      // Online-only: posting wajib memeriksa periode, saldo, idempotensi, dan
      // keseimbangan debit-kredit dalam satu transaksi database server.
      final hasil = await ApiClient.instance
          .aksi('si_restaurant_${_proses}_post', {'id': row['id']});
      await _muat();
      if (mounted) {
        _pesan('Posting berhasil. Jurnal ID ${hasil['jurnalId']}.');
      }
    } catch (e) {
      if (mounted) _pesan('$e', galat: true);
    }
  }

  Future<void> _gantiPemetaan(Map<String, dynamic> mapping) async {
    int? pilihan = (mapping['akunId'] as num?)?.toInt();
    final akunId = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, ubah) {
        return AlertDialog(
          title: Text('Ubah ${mapping['label']}'),
          content: SizedBox(
            width: 520,
            child: DropdownButtonFormField<int>(
              value: pilihan,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Akun debit/kredit'),
              items: [
                for (final akun in _pilihanAkun)
                  DropdownMenuItem<int>(
                    value: (akun['id'] as num).toInt(),
                    child: Text('${akun['kode']} — ${akun['nama']}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => ubah(() => pilihan = v),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton(
              onPressed:
                  pilihan == null ? null : () => Navigator.pop(c, pilihan),
              child: const Text('Simpan'),
            ),
          ],
        );
      }),
    );
    if (akunId == null) return;
    try {
      // Online-only: pemetaan ini memengaruhi jurnal berikutnya dan tidak
      // boleh tersimpan hanya di perangkat atau tertunda dalam outbox.
      await ApiClient.instance.aksi('si_restaurant_account_mapping_save', {
        'peran': mapping['peran'],
        'akunId': akunId,
      });
      await _muat();
      if (mounted) _pesan('Pemetaan akun berhasil diperbarui.');
    } catch (e) {
      if (mounted) _pesan('$e', galat: true);
    }
  }

  void _pesan(String teks, {bool galat = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(teks),
      backgroundColor: galat ? AppColors.danger : AppColors.success,
    ));
  }

  List<String> _statusBerikut(String status) {
    const umum = <String, String>{
      'DRAFT': 'SUBMITTED',
      'SUBMITTED': 'APPROVED',
    };
    if (_proses == 'bom') {
      return status == 'DRAFT'
          ? const ['AKTIF']
          : status == 'AKTIF'
              ? const ['NONAKTIF']
              : const [];
    }
    if (_proses == 'outlet_order') {
      const urut = [
        'DRAFT',
        'SUBMITTED',
        'APPROVED',
        'ALLOCATED',
        'PARTIAL',
        'COMPLETED'
      ];
      final i = urut.indexOf(status);
      return i >= 0 && i < urut.length - 1 ? [urut[i + 1]] : const [];
    }
    if (_proses == 'shipment') {
      const urut = [
        'DRAFT',
        'SUBMITTED',
        'APPROVED',
        'DELIVERY',
        'ARRIVED',
        'COMPLETED'
      ];
      final i = urut.indexOf(status);
      return i >= 0 && i < urut.length - 1 ? [urut[i + 1]] : const [];
    }
    if (_proses == 'claim') {
      const urut = ['DRAFT', 'SUBMITTED', 'APPROVED', 'RESOLVED'];
      final i = urut.indexOf(status);
      return i >= 0 && i < urut.length - 1 ? [urut[i + 1]] : const [];
    }
    return umum[status] == null ? const [] : [umum[status]!];
  }

  bool _siapPosting(Map<String, dynamic> row) {
    if (!_konfigurasi.dapatPosting || row['sudahPosting'] == true) return false;
    final s = '${row['status']}';
    if (_proses == 'pos_sale') return s == 'DRAF' || s == 'TERPOSTING';
    return _proses == 'shipment'
        ? s == 'ARRIVED' || s == 'COMPLETED'
        : s == 'APPROVED';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.abChickenOperations,
      judul: 'Pusat Operasi AB Chicken',
      subjudul:
          'Outlet → gudang pusat → pengadaan → produksi → POS → pengiriman → akuntansi',
      scrollable: false,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _prosesRantaiPasok.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final p = _prosesRantaiPasok[i];
              return ChoiceChip(
                avatar: Icon(p.ikon, size: 17),
                label: Text(p.label),
                selected: p.kode == _proses,
                onSelected: (_) {
                  setState(() {
                    _proses = p.kode;
                    _halaman = 1;
                    _status = 'SEMUA';
                    _posting = 'SEMUA';
                  });
                  _muat();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (_proses != 'ringkasan' && _proses != 'account') _filter(),
        Expanded(child: _isi()),
      ]),
    );
  }

  Widget _filter() {
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _cari,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Nomor, outlet, vendor, atau lokasi',
                suffixIcon: IconButton(
                    onPressed: () {
                      _cari.clear();
                      _halaman = 1;
                      _muat();
                    },
                    icon: const Icon(Icons.clear)),
              ),
              onSubmitted: (_) {
                _halaman = 1;
                _muat();
              },
            ),
          ),
          SizedBox(
            width: 175,
            child: DropdownButtonFormField<String>(
              value: _status,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                'SEMUA',
                'DRAF',
                'DRAFT',
                'SUBMITTED',
                'APPROVED',
                'ALLOCATED',
                'PARTIAL',
                'DELIVERY',
                'ARRIVED',
                'COMPLETED',
                'POSTED',
                'TERPOSTING',
                'RESOLVED',
                'AKTIF',
                'NONAKTIF'
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) {
                setState(() {
                  _status = v ?? 'SEMUA';
                  _halaman = 1;
                });
                _muat();
              },
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              value: _posting,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Status posting'),
              items: const ['SEMUA', 'TELAH DIPOSTING', 'BELUM DIPOSTING']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _posting = v ?? 'SEMUA';
                  _halaman = 1;
                });
                _muat();
              },
            ),
          ),
          OutlinedButton.icon(
              onPressed: _muat,
              icon: const Icon(Icons.refresh),
              label: const Text('Muat ulang')),
          Text('$_total record • 50 per halaman',
              style: Theme.of(context).textTheme.bodySmall),
        ]);
  }

  Widget _isi() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 44),
        const SizedBox(height: 8),
        Text(_galat!, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
      ]));
    }
    if (_proses == 'ringkasan') return _ringkasanWidget();
    if (_proses == 'account') return _akunWidget();
    return _daftarWidget();
  }

  Widget _ringkasanWidget() {
    final lulus =
        _checks.isNotEmpty && _checks.every((e) => e['lulus'] == true);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Card(
        color: lulus ? Colors.green.shade50 : Colors.orange.shade50,
        child: ListTile(
          leading: Icon(lulus ? Icons.verified : Icons.warning_amber,
              color: lulus ? Colors.green : Colors.orange),
          title: Text(lulus
              ? 'Seluruh gerbang data UAT lulus'
              : 'Masih ada gerbang data yang belum lulus'),
          subtitle: const Text(
              'Akuntansi hanya boleh diuji setelah seluruh proses hulu memenuhi syarat.'),
          trailing: OutlinedButton.icon(
              onPressed: _muat,
              icon: const Icon(Icons.refresh),
              label: const Text('Periksa ulang')),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _ringkasan.entries)
          SizedBox(
              width: 210,
              child: Card(
                  child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_labelMetrik(e.key),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text('${e.value}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ]),
              ))),
      ]),
      const SizedBox(height: 12),
      Card(
          child: Column(children: [
        const ListTile(
            title: Text('Gerbang integritas UAT'),
            subtitle: Text(
                'Semua baris harus LULUS sebelum pengujian jurnal dan laporan dimulai.')),
        for (final c in _checks)
          ListTile(
            dense: true,
            leading: Icon(
                c['lulus'] == true ? Icons.check_circle : Icons.cancel,
                color: c['lulus'] == true ? Colors.green : Colors.red),
            title: Text('${c['kode']}'),
            trailing: Text('${c['aktual']}  •  ${c['syarat']}'),
          ),
      ])),
    ]);
  }

  Widget _akunWidget() {
    return ListView(children: [
      Card(
        color: Colors.blue.shade50,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Asal akun posting:\n'
              '• BAST dan produksi membaca akun persediaan dari setiap Master Produk.\n'
              '• Penjualan POS membaca akun pendapatan dan HPP produk, serta akun persediaan bahan dari BOM.\n'
              '• GRNI, Hutang Vendor, dan Kas/Bank Operasional dapat diganti langsung di bawah.\n'
              'Posting ditolak bila akun kosong, nonaktif, atau total debit tidak sama dengan kredit.'),
        ),
      ),
      for (final m in _pemetaanAkun)
        Card(
            child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.account_balance)),
          title: Text('${m['label']}'),
          subtitle:
              Text('${m['kode'] ?? 'Belum dipilih'} — ${m['nama'] ?? ''}'),
          trailing: OutlinedButton.icon(
            onPressed: () => _gantiPemetaan(m),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Ubah akun'),
          ),
        )),
    ]);
  }

  Widget _daftarWidget() {
    if (_data.isEmpty) {
      return const Center(
          child: Text('Tidak ada record yang cocok dengan filter.'));
    }
    final halamanMaks = (_total / _batas).ceil().clamp(1, 999999);
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _muat,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            itemCount: _data.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _baris(_data[i]),
          ),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Halaman $_halaman / $halamanMaks'),
        IconButton(
            onPressed: _halaman > 1
                ? () {
                    setState(() => _halaman--);
                    _muat();
                  }
                : null,
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            onPressed: _halaman < halamanMaks
                ? () {
                    setState(() => _halaman++);
                    _muat();
                  }
                : null,
            icon: const Icon(Icons.chevron_right)),
      ]),
    ]);
  }

  Widget _baris(Map<String, dynamic> row) {
    final sudahPosting = row['sudahPosting'] == true;
    final berikut = _statusBerikut('${row['status']}');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${row['nomor']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${row['referensi']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
          Expanded(
              flex: 2,
              child: Text('${row['mitra']}\n${row['lokasi']}',
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
          Expanded(
              child: Text(_formatRupiah.format((row['nilai'] as num?) ?? 0),
                  textAlign: TextAlign.right)),
          const SizedBox(width: 12),
          Chip(
              label: Text('${row['status']}',
                  style: const TextStyle(fontSize: 11))),
          const SizedBox(width: 6),
          Chip(
            avatar: Icon(sudahPosting ? Icons.check_circle : Icons.schedule,
                size: 16, color: sudahPosting ? Colors.green : Colors.orange),
            label: Text(sudahPosting ? 'Telah diposting' : 'Belum diposting',
                style: const TextStyle(fontSize: 11)),
          ),
          if (berikut.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Ubah status',
              onSelected: (s) => _ubahStatus(row, s),
              itemBuilder: (_) => [
                for (final s in berikut)
                  PopupMenuItem(value: s, child: Text('Ubah ke $s'))
              ],
            ),
          if (_siapPosting(row))
            FilledButton.icon(
                onPressed: () => _postingDokumen(row),
                icon: const Icon(Icons.post_add),
                label: const Text('Posting')),
        ]),
      ),
    );
  }

  String _labelMetrik(String key) {
    const label = {
      'outlet': 'Outlet aktif',
      'gudangPusat': 'Gudang pusat',
      'produkJual': 'Produk jual',
      'bahanBaku': 'Bahan baku',
      'outlet_order': 'Pesanan outlet',
      'bom': 'Resep / BOM',
      'pos_sale': 'Penjualan POS',
      'procurement_pr': 'PR',
      'procurement_po': 'PO',
      'procurement_bast': 'BAST',
      'procurement_invoice': 'Tagihan vendor',
      'procurement_payment': 'Pembayaran vendor',
      'production': 'Perintah produksi',
      'shipment': 'Pengiriman outlet',
      'claim': 'Klaim / backorder',
      'jurnalTerposting': 'Jurnal terposting',
    };
    return label[key] ?? key;
  }
}
