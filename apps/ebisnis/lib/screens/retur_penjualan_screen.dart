import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../parse_util.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/safe_state.dart';
import 'struk_retur_util.dart';
import '../widgets/jejak_galat.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

const _daftarAlasan = [
  'Rusak',
  'Salah Ukuran/Varian',
  'Tidak Sesuai Pesanan',
  'Berubah Pikiran',
  'Kadaluarsa',
  'Lainnya'
];
const _daftarKondisi = ['Baik - Layak Jual Lagi', 'Rusak - Tidak Layak Jual'];
const _daftarMetodePengembalian = [
  'Tunai',
  'Saldo Member',
  'Tukar Barang',
  'Tanpa Pengembalian'
];

/// Layar Retur Penjualan -- wizard 3 langkah (cari transaksi ->
/// pilih barang -> metode pengembalian) + riwayat/edit/hapus (supervisor).
/// Aksi server: retur_penjualan_list (view, siapa saja) dan
/// retur_penjualan_simpan/_ubah/_hapus (gated supervisor/admin, sama pola
/// gerbang dgn Kulakan). "Cari Transaksi" reuse `laporan_order_list`, "Pilih
/// Barang" reuse `detail_transaksi` -- tidak ada aksi baru utk 2 langkah itu.
class ReturPenjualanScreen extends StatefulWidget {
  const ReturPenjualanScreen({super.key});
  @override
  State<ReturPenjualanScreen> createState() => _ReturPenjualanScreenState();
}

class _ReturPenjualanScreenState extends State<ReturPenjualanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.returPenjualan,
      judul: 'Retur Penjualan',
      subjudul: 'Catat pengembalian barang dari transaksi yang sudah lunas',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabs: const [Tab(text: 'Buat Retur'), Tab(text: 'Riwayat Retur')],
          ),
          Expanded(
              child: TabBarView(
                  controller: _tab,
                  children: const [_TabBuatRetur(), _TabRiwayatRetur()])),
        ],
      ),
    );
  }
}

class _BarisRetur {
  final Map<String, dynamic>
      item; // detail_transaksi, termasuk pembelianId dan sisa qty yang boleh diretur
  bool disertakan = false;
  late final TextEditingController qtyController;
  String alasan = _daftarAlasan.first;
  String kondisi = _daftarKondisi.first;
  bool get kembalikanKeStok => !kondisi.toLowerCase().contains('rusak');
  double get qty =>
      double.tryParse(qtyController.text.replaceAll(',', '.')) ?? 0;
  double get hargaSatuan => (item['harga'] as num?)?.toDouble() ?? 0;
  double get qtyDibeli => (item['qty'] as num?)?.toDouble() ?? 0;
  double get qtySudahDiretur =>
      (item['qtySudahDiretur'] as num?)?.toDouble() ?? 0;
  double get qtyMaksRetur =>
      (item['qtyMaksRetur'] as num?)?.toDouble() ?? qtyDibeli;
  bool get sudahDireturSemua => qtyMaksRetur <= 0;
  double get subtotal => qty * hargaSatuan;

  _BarisRetur(this.item) {
    final qtyAsli = qtyMaksRetur;
    qtyController = TextEditingController(
        text: qtyAsli
            .toStringAsFixed(qtyAsli == qtyAsli.roundToDouble() ? 0 : 2));
  }
}

class _TabBuatRetur extends StatefulWidget {
  const _TabBuatRetur();
  @override
  State<_TabBuatRetur> createState() => _TabBuatReturState();
}

class _TabBuatReturState extends State<_TabBuatRetur> with JejakGalat {
  final _kataKunciController = TextEditingController();
  bool _mencari = false;
  String? _errorPencarian;
  List<Map<String, dynamic>> _hasilPencarian = [];

  Map<String, dynamic>? _transaksiTerpilih;
  bool _memuatDetail = false;
  List<_BarisRetur> _baris = [];
  String _metodePengembalian = _daftarMetodePengembalian.first;
  bool _menyimpan = false;
  String? _errorSimpan;
  String? _idempotencyKey;

  @override
  void dispose() {
    _kataKunciController.dispose();
    for (final b in _baris) {
      b.qtyController.dispose();
    }
    super.dispose();
  }

  Future<void> _cariTransaksi(String kataKunci) async {
    final v = kataKunci.trim();
    if (v.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _errorPencarian = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
          'laporan_order_list', {'keyword': v, 'page': 1, 'pageSize': 30});
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      setStateIfMounted(() => _hasilPencarian = data);
    } catch (e) {
      setStateIfMounted(() => _errorPencarian = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _pilihTransaksi(Map<String, dynamic> row) async {
    setStateIfMounted(() {
      _transaksiTerpilih = row;
      _idempotencyKey = null;
      _memuatDetail = true;
      _baris = [];
    });
    try {
      final hasil = await ApiClient.instance
          .aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items =
          ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      setStateIfMounted(
          () => _baris = items.map((i) => _BarisRetur(i)).toList());
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
      setStateIfMounted(() => _transaksiTerpilih = null);
    } finally {
      if (mounted) setStateIfMounted(() => _memuatDetail = false);
    }
  }

  void _batalkanPemilihan() {
    setStateIfMounted(() {
      _transaksiTerpilih = null;
      _idempotencyKey = null;
      _baris = [];
    });
  }

  double get _totalNilaiRetur =>
      _baris.where((b) => b.disertakan).fold(0, (s, b) => s + b.subtotal);

  Future<void> _simpanRetur() async {
    final dipilih = _baris.where((b) => b.disertakan).toList();
    if (dipilih.isEmpty) {
      setStateIfMounted(
          () => _errorSimpan = 'Pilih minimal satu barang untuk diretur.');
      return;
    }
    for (final b in dipilih) {
      final qtyAsli = b.qtyMaksRetur;
      if (b.qty <= 0 || b.qty > qtyAsli) {
        setStateIfMounted(() => _errorSimpan =
            'Qty Retur "${b.item['nama']}" harus lebih dari 0 dan maksimal ${qtyAsli.toStringAsFixed(qtyAsli == qtyAsli.roundToDouble() ? 0 : 2)} (sisa yang belum pernah diretur).');
        return;
      }
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _errorSimpan = null;
    });
    try {
      _idempotencyKey ??= 'RETUR-JUAL-${DateTime.now().microsecondsSinceEpoch}';
      await ApiClient.instance.aksi('retur_penjualan_simpan', {
        'idempotency_key': _idempotencyKey,
        'pembelian_anggota_koperasi_id': _transaksiTerpilih!['idTransaksi'],
        'kode_transaksi_asal': _transaksiTerpilih!['nomorNota'],
        'nama_pembeli': _transaksiTerpilih!['pembeli'],
        'metode_pengembalian': _metodePengembalian,
        'items': dipilih
            .map((b) => {
                  'produk_id': b.item['produkId'],
                  'pembelian_id': b.item['pembelianId'],
                  'qty': b.qty,
                  'harga_satuan': b.hargaSatuan,
                  'alasan': b.alasan,
                  'kondisi_barang': b.kondisi,
                  'kembalikan_ke_stok': b.kembalikanKeStok,
                  'keterangan': '',
                })
            .toList(),
      });
      if (mounted) {
        // Data struk diambil SEBELUM form dikosongkan; setelah ini _baris sudah
        // direset sehingga tidak bisa lagi dibaca.
        final itemStruk = dipilih
            .map((b) => itemStrukRetur(
                  nama: '${b.item['nama'] ?? '-'}',
                  qty: b.qty,
                  harga: b.hargaSatuan,
                ))
            .toList();
        final totalStruk =
            dipilih.fold<double>(0, (jumlah, b) => jumlah + b.subtotal);
        final kodeStruk = '${_transaksiTerpilih!['nomorNota'] ?? ''}';
        final pelangganStruk = '${_transaksiTerpilih!['pembeli'] ?? ''}';
        final metodeStruk = _metodePengembalian;
        final waktuStruk =
            DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());

        setStateIfMounted(() {
          _transaksiTerpilih = null;
          _baris = [];
          _hasilPencarian = [];
          _kataKunciController.clear();
          _idempotencyKey = null;
        });

        final cetak = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
            title: const Text('Retur berhasil disimpan'),
            content: Text(
                'Retur atas nota $kodeStruk sebesar '
                '${_formatRupiah.format(totalStruk)} sudah tercatat. '
                'Cetak faktur retur untuk diserahkan kepada pembeli?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Nanti Saja')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(c, true),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Cetak Faktur Retur'),
              ),
            ],
          ),
        );
        if (cetak == true && mounted) {
          await bukaStrukRetur(
            context,
            kode: kodeStruk,
            waktu: waktuStruk,
            item: itemStruk,
            total: totalStruk,
            metode: metodeStruk,
            pelanggan: pelangganStruk,
          );
        }
      }
    } catch (e) {
      setStateIfMounted(() => _errorSimpan = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppInfoBanner(
            icon: Icons.lock_outline,
            color: AppColors.warning,
            text:
                'Hanya admin/supervisor toko yang dapat mencatat retur penjualan.',
          ),
        ),
      );
    }

    if (_transaksiTerpilih == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppFormSection(
            judul: 'Cari Transaksi Asal',
            deskripsi:
                'Masukkan nomor nota, kode transaksi, atau nama pelanggan untuk memilih transaksi yang akan diretur.',
            children: [
              TextField(
                controller: _kataKunciController,
                decoration: AppFormStyle.fieldDecoration(
                  context,
                  labelText: 'Cari nota',
                  hintText: 'Nomor nota / kode transaksi / nama pelanggan',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Cari',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _mencari
                        ? null
                        : () => _cariTransaksi(_kataKunciController.text),
                  ),
                ),
                onSubmitted: _cariTransaksi,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mencari) const Center(child: CircularProgressIndicator()),
          if (_errorPencarian != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _errorPencarian!,
                detail: detailUntuk(_errorPencarian),
              ),
            ),
          if (!_mencari)
            _TabelTransaksiRetur(
              data: _hasilPencarian,
              onPilih: _pilihTransaksi,
              emptyText: _kataKunciController.text.trim().isEmpty
                  ? 'Ketik kata kunci lalu tekan Enter untuk mencari transaksi.'
                  : 'Transaksi tidak ditemukan.',
            ),
        ],
      );
    }

    if (_memuatDetail) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Kembali ke pencarian',
                icon: const Icon(Icons.arrow_back),
                onPressed: _batalkanPemilihan,
              ),
              const SizedBox(width: 4),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.latarLembut(AppColors.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${_transaksiTerpilih!['nomorNota']}",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${_transaksiTerpilih!['pembeli'] ?? 'Umum'}",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatRupiah.format(_transaksiTerpilih!['totalBiaya'] ?? 0),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.assignment_return_outlined,
          text:
              'Langkah 2: pilih barang yang diretur, lalu lengkapi jumlah, alasan, dan kondisi barang.',
        ),
        const SizedBox(height: 12),
        ..._baris.map(
          (b) => _KartuBarangRetur(
            baris: b,
            onChanged: () => setStateIfMounted(() {}),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Langkah 3: Metode Pengembalian',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _daftarMetodePengembalian
              .map((m) => ChoiceChip(
                  label: Text(m),
                  selected: _metodePengembalian == m,
                  onSelected: (_) =>
                      setStateIfMounted(() => _metodePengembalian = m)))
              .toList(),
        ),
        const SizedBox(height: 16),
        if (_errorSimpan != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_errorSimpan!,
                style: TextStyle(color: Colors.red.shade700)),
              AppDetailGalatOpsional(detail: detailUntuk(_errorSimpan)),
            ]),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total Nilai Retur',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(_formatRupiah.format(_totalNilaiRetur),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _menyimpan ? null : _simpanRetur,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _menyimpan
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Simpan Retur'),
          ),
        ),
      ],
    );
  }
}

class _KartuBarangRetur extends StatelessWidget {
  final _BarisRetur baris;
  final VoidCallback onChanged;

  const _KartuBarangRetur({
    required this.baris,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppSectionCard(
        padding: const EdgeInsets.all(14),
        child: StatefulBuilder(
          builder: (context, setBarisState) {
            final qtyAsli = baris.qtyMaksRetur;
            final qtyLebih = baris.qty > qtyAsli;
            final statusColor =
                baris.kembalikanKeStok ? AppColors.success : AppColors.danger;
            final statusIcon = baris.kembalikanKeStok
                ? Icons.inventory_2_outlined
                : Icons.block_outlined;

            void ubahBaris(VoidCallback perubahan) {
              setBarisState(perubahan);
              onChanged();
            }

            Widget bidangInput(Widget child, double width) {
              return SizedBox(width: width, child: child);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: baris.disertakan,
                      onChanged: baris.sudahDireturSemua
                          ? null
                          : (v) =>
                              ubahBaris(() => baris.disertakan = v ?? true),
                    ),
                    Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.teal),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.teal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${baris.item['nama']}",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Dibeli: ${baris.item['qty']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                              if (baris.qtySudahDiretur > 0)
                                Text(
                                  'Sudah diretur: ${baris.qtySudahDiretur}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.warning,
                                  ),
                                ),
                              Text(
                                'Sisa dapat diretur: ${baris.qtyMaksRetur}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: baris.sudahDireturSemua
                                      ? AppColors.danger
                                      : AppColors.success,
                                ),
                              ),
                              Text(
                                'Harga: ${_formatRupiah.format(baris.hargaSatuan)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatRupiah.format(baris.subtotal),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.latarLembut(baris.disertakan
                                ? AppColors.primary
                                : AppColors.warning),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            baris.sudahDireturSemua
                                ? 'Sudah diretur semua'
                                : (baris.disertakan ? 'Dipilih' : 'Dilewati'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: baris.disertakan
                                  ? AppColors.primary
                                  : AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (baris.disertakan) ...[
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final lebarPenuh = constraints.maxWidth;
                      final lebarField = lebarPenuh >= 780
                          ? (lebarPenuh - 24) / 3
                          : lebarPenuh;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          bidangInput(
                            TextField(
                              controller: baris.qtyController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: AppFormStyle.fieldDecoration(
                                context,
                                labelText: 'Qty Retur',
                                helperText: 'Maks ${baris.qtyMaksRetur}',
                                isDense: true,
                              ).copyWith(
                                errorText: qtyLebih
                                    ? 'Melebihi sisa yang dapat diretur'
                                    : null,
                              ),
                              onChanged: (_) => ubahBaris(() {}),
                            ),
                            lebarField,
                          ),
                          bidangInput(
                            DropdownButtonFormField<String>(
                              value: baris.alasan,
                              isExpanded: true,
                              decoration: AppFormStyle.fieldDecoration(
                                context,
                                labelText: 'Alasan',
                                isDense: true,
                              ),
                              items: _daftarAlasan
                                  .map((a) => DropdownMenuItem(
                                        value: a,
                                        child: Text(
                                          a,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) => ubahBaris(
                                  () => baris.alasan = v ?? baris.alasan),
                            ),
                            lebarField,
                          ),
                          bidangInput(
                            DropdownButtonFormField<String>(
                              value: baris.kondisi,
                              isExpanded: true,
                              decoration: AppFormStyle.fieldDecoration(
                                context,
                                labelText: 'Kondisi Barang',
                                isDense: true,
                              ),
                              items: _daftarKondisi
                                  .map((k) => DropdownMenuItem(
                                        value: k,
                                        child: Text(
                                          k,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) => ubahBaris(
                                  () => baris.kondisi = v ?? baris.kondisi),
                            ),
                            lebarField,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.latarLembut(statusColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            baris.kembalikanKeStok
                                ? 'Stok akan dikembalikan.'
                                : 'Stok tidak dikembalikan karena kondisi rusak.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    'Barang ini tidak disertakan dalam retur.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabRiwayatRetur extends StatefulWidget {
  const _TabRiwayatRetur();
  @override
  State<_TabRiwayatRetur> createState() => _TabRiwayatReturState();
}

class _TabelTransaksiRetur extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final ValueChanged<Map<String, dynamic>> onPilih;
  final String emptyText;

  const _TabelTransaksiRetur({
    required this.data,
    required this.onPilih,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      minWidth: 860,
      emptyText: emptyText,
      columns: const [
        AppTableColumn('Nomor Nota', flex: 4),
        AppTableColumn('Tanggal', flex: 2),
        AppTableColumn('Pelanggan', flex: 2),
        AppTableColumn('Kasir', flex: 2),
        AppTableColumn('Total', flex: 2, align: TextAlign.right),
      ],
      rows: data
          .map((r) => AppTableRowData(
                onTap: () => onPilih(r),
                cells: [
                  AppTableCell.text('${r['nomorNota']}', flex: 4),
                  AppTableCell.text('${r['waktu']}', flex: 2),
                  AppTableCell.text('${r['pembeli'] ?? 'Umum'}', flex: 2),
                  AppTableCell.text('${r['kasir'] ?? '-'}', flex: 2),
                  AppTableCell.text(
                    _formatRupiah.format(r['totalBiaya'] ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ))
          .toList(),
    );
  }
}

class _TabRiwayatReturState extends State<_TabRiwayatRetur> with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (retur yang dicatat kasir lain).
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
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Jalur SIMPAN /
      // UBAH / HAPUS retur TETAP online-only lewat ApiClient (transaksional).
      await MasterOffline.daftarCacheDulu('retur_penjualan_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:retur_penjualan', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil);
          _total = _diff.total ?? _data.length;
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _terapkanFilter(String v) async {
    _kataKunci = v;
    _halaman = 1;
    await _muat();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _hapus(Map<String, dynamic> r) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Retur?'),
        content: Text(
            'Retur "${r['namaProduk']}" akan dihapus permanen. Stok akan dihitung ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      await ApiClient.instance.aksi('retur_penjualan_hapus', {'id': r['id']});
      await _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  /// Cetak faktur retur dari riwayat.
  ///
  /// Satu peristiwa retur biasanya menghasilkan BEBERAPA baris (satu per barang) dengan nomor
  /// nota dan waktu yang sama, sehingga barisnya dikumpulkan dulu supaya yang tercetak adalah
  /// satu faktur utuh — bukan selembar per barang.
  Future<void> _cetak(Map<String, dynamic> r) async {
    final nota = '${r['kodeTransaksiAsal'] ?? ''}';
    final waktu = '${r['waktu'] ?? ''}';
    final serumpun = _data
        .where((e) =>
            '${e['kodeTransaksiAsal'] ?? ''}' == nota &&
            '${e['waktu'] ?? ''}' == waktu)
        .toList();
    final baris = serumpun.isEmpty ? [r] : serumpun;
    final item = baris
        .map((e) => itemStrukRetur(
              nama: '${e['namaProduk'] ?? '-'}',
              qty: (e['qty'] as num?) ?? 0,
              harga: (e['hargaSatuan'] as num?) ?? 0,
            ))
        .toList();
    final total = baris.fold<double>(0, (jumlah, e) {
      final nilai = (e['totalNilai'] as num?) ??
          (((e['qty'] as num?) ?? 0) * ((e['hargaSatuan'] as num?) ?? 0));
      return jumlah + nilai.toDouble();
    });
    if (!mounted) return;
    await bukaStrukRetur(
      context,
      kode: nota,
      waktu: waktu,
      item: item,
      total: total,
      metode: '${r['metodePengembalian'] ?? ''}',
      pelanggan: '${r['namaPembeli'] ?? ''}',
    );
  }

  Future<void> _ubah(Map<String, dynamic> r) async {
    final qtyController = TextEditingController(text: '${r['qty']}');
    final hargaController = TextEditingController(text: '${r['hargaSatuan']}');
    var alasan = _daftarAlasan.contains(r['alasan'])
        ? r['alasan'] as String
        : _daftarAlasan.last;
    var kondisi = _daftarKondisi.contains(r['kondisiBarang'])
        ? r['kondisiBarang'] as String
        : _daftarKondisi.first;
    final disimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ubah Retur -- ${r['namaProduk']}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                  controller: qtyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: AppFormStyle.fieldDecoration(context,
                      labelText: 'Qty', isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: hargaController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: AppFormStyle.fieldDecoration(context,
                      labelText: 'Harga Satuan', isDense: true)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: alasan,
                decoration: AppFormStyle.fieldDecoration(context,
                    labelText: 'Alasan', isDense: true),
                items: _daftarAlasan
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setSheetState(() => alasan = v ?? alasan),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: kondisi,
                decoration: AppFormStyle.fieldDecoration(context,
                    labelText: 'Kondisi Barang', isDense: true),
                items: _daftarKondisi
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setSheetState(() => kondisi = v ?? kondisi),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Simpan Perubahan')),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (disimpan != true) return;
    try {
      await ApiClient.instance.aksi('retur_penjualan_ubah', {
        'id': r['id'],
        'qty': parseDesimal(qtyController.text) ?? r['qty'],
        'harga_satuan': parseDesimal(hargaController.text) ?? r['hargaSatuan'],
        'alasan': alasan,
        'kondisi_barang': kondisi,
        'kembalikan_ke_stok': !kondisi.toLowerCase().contains('rusak'),
      });
      await _muat();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(
                    width: 190,
                    child: AppKpiCard(
                        icon: Icons.assignment_return_outlined,
                        warna: AppColors.primary,
                        nilai: '$_total',
                        label: 'Total Retur')),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.payments_outlined,
                    warna: AppColors.danger,
                    nilai: _formatRupiah.format(_data.fold<num>(
                        0,
                        (a, r) =>
                            a +
                            (((r['qty'] as num?) ?? 0) *
                                ((r['hargaSatuan'] as num?) ?? 0)))),
                    label: 'Nilai (hal. ini)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSearchField(
            hintText: 'Cari produk / nomor nota / pelanggan...',
            onChanged: _terapkanFilter,
          ),
          const SizedBox(height: 12),
          BannerPerubahanServer(
            key: ValueKey('perubahan:${_diff.versi}'),
            baru: _diff.idBaru.length,
            berubah: _diff.idBerubah.length,
            dihapus: _diff.jumlahHapus,
          ),
          if (_memuat)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _error!,
                detail: detailUntuk(_error),
              ),
            )
          else
            _TabelRiwayatRetur(
              data: _data,
              bolehKelola: Sesi.instance.bolehKelola,
              idBaru: _diff.idBaru,
              idBerubah: _diff.idBerubah,
              onUbah: _ubah,
              onHapus: _hapus,
              onCetak: _cetak,
              pagination: _total > _pageSize
                  ? AppTablePagination(
                      halaman: _halaman,
                      totalHalaman: _totalHalaman,
                      totalData: _total,
                      labelData: 'retur',
                      onSebelumnya:
                          _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                      onBerikutnya: _halaman < _totalHalaman
                          ? () => _pindah(_halaman + 1)
                          : null,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _TabelRiwayatRetur extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool bolehKelola;
  final ValueChanged<Map<String, dynamic>> onUbah;
  final ValueChanged<Map<String, dynamic>> onHapus;
  final ValueChanged<Map<String, dynamic>>? onCetak;
  final AppTablePagination? pagination;
  // Penanda diff dari emisi server (baca lokal-dulu) utk kilau baris.
  final Set<String> idBaru;
  final Set<String> idBerubah;

  const _TabelRiwayatRetur({
    required this.data,
    required this.bolehKelola,
    required this.onUbah,
    required this.onHapus,
    this.onCetak,
    this.idBaru = const <String>{},
    this.idBerubah = const <String>{},
    this.pagination,
  });

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      minWidth: bolehKelola ? 1160 : 1080,
      emptyText: 'Belum ada riwayat retur.',
      pagination: pagination,
      columns: [
        const AppTableColumn('Waktu', flex: 2),
        const AppTableColumn('Nomor Nota', flex: 3),
        const AppTableColumn('Produk', flex: 3),
        const AppTableColumn('Pelanggan', flex: 2),
        const AppTableColumn('Qty', flex: 1, align: TextAlign.center),
        const AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        const AppTableColumn('Kondisi', flex: 2),
        const AppTableColumn('Metode', flex: 2),
        AppTableColumn('Aksi',
            width: bolehKelola ? 132 : 52, align: TextAlign.center),
      ],
      rows: data.map((r) {
        final totalNilai = (r['totalNilai'] as num?) ??
            (((r['qty'] as num?) ?? 0) * ((r['hargaSatuan'] as num?) ?? 0));
        return AppTableRowData(
          cells: [
            AppTableCell(
              flex: 2,
              child: KilauBaris(
                kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                idBaru: idBaru,
                idBerubah: idBerubah,
                child: Text('${r['waktu']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            AppTableCell.text('${r['kodeTransaksiAsal']}', flex: 3),
            AppTableCell.text('${r['namaProduk']}', flex: 3),
            AppTableCell.text('${r['namaPembeli'] ?? 'Umum'}', flex: 2),
            AppTableCell.text('${r['qty']}x', flex: 1, align: TextAlign.center),
            AppTableCell.text(
              _formatRupiah.format(totalNilai),
              flex: 2,
              align: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            AppTableCell.text('${r['kondisiBarang']}', flex: 2),
            AppTableCell.text('${r['metodePengembalian']}', flex: 2),
            AppTableCell(
              width: bolehKelola ? 132 : 52,
              align: TextAlign.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Cetak faktur boleh untuk semua yang dapat melihat riwayat:
                  // mencetak ulang bukti tidak mengubah data apa pun.
                  IconButton(
                    tooltip: 'Cetak faktur retur',
                    icon: const Icon(Icons.print_outlined, size: 18),
                    color: AppColors.textSecondaryOf(context),
                    onPressed: onCetak == null ? null : () => onCetak!(r),
                  ),
                  if (bolehKelola)
                    IconButton(
                      tooltip: 'Ubah',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: AppColors.primary,
                      onPressed: () => onUbah(r),
                    ),
                  if (bolehKelola)
                    IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: AppColors.danger,
                      onPressed: () => onHapus(r),
                    ),
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
