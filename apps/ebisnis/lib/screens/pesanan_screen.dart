import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../services/pesanan_poller.dart';
import '../services/transaksi_outbox_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_shell.dart';
import '../widgets/panduan_stok_kosong.dart';
import 'kasir_screen.dart';
import 'struk_screen.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

enum _Filter { semua, online, tertahan, pending }

const _tinggiKartuKpiPesanan = 96.0;
const _pageSizePesanan = 15;

/// Layar Pesanan (padanan pesanan.html/pesanan-renderer.js Electron) --
/// gabungan 2 jenis draft (lihat JavaDoc [Pesanan]): Pesanan Online (dibuat
/// pembeli sendiri, diselesaikan lewat "Verifikasi & Selesaikan") dan
/// Keranjang Tertahan (ditahan kasir lewat tombol "Tahan" di Keranjang,
/// dilanjutkan lewat "Muat ke Keranjang" -- inilah bagian "resume" yang
/// disebut di task #181).
class PesananScreen extends StatefulWidget {
  const PesananScreen({super.key});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Pesanan> _semua = [];
  _Filter _filter = _Filter.semua;

  // Filter tambahan -- padanan filter Mulai/Akhir/Kode/Pembeli/Pedagang di
  // JSP `_draft_pesanan_anggota.jsp`, server (`prosesPesananList` PosApi.java)
  // SUDAH mendukung semuanya sejak lama, hanya UI-nya yang belum dibangun.
  bool _hanyaBelumLunas = false;
  DateTime? _sejak;
  DateTime? _sampai;
  final _kodeController = TextEditingController();
  final _pembeliController = TextEditingController();
  final _pedagangController = TextEditingController();
  String _kasir = '';
  List<String> _daftarKasir = const [];
  bool _filterTerbuka = false;
  int _halamanPesanan = 1;
  int _totalPesanan = 0;
  Map<String, dynamic> _ringkasan = const {};
  bool _sedangMembayarSemuaTertahan = false;
  bool _sedangSinkronPending = false;
  List<Map<String, dynamic>> _transaksiPending = [];
  int _totalTransaksiPending = 0;
  int _jumlahPendingAktif = 0;
  int _halamanPending = 1;
  String? _statusPending;
  int _intervalRetryMenit = TransaksiOutboxService.intervalRetryMenitDefault;

  @override
  void initState() {
    super.initState();
    _muat();
    _muatRingkasanPending();
    PesananPoller.instance.tandaiSudahDilihat();
  }

  @override
  void dispose() {
    _kodeController.dispose();
    _pembeliController.dispose();
    _pedagangController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      if (_filter == _Filter.pending) {
        await _muatTransaksiPending(aturLoading: false);
        return;
      }
      final payload = _payloadDaftarPesanan(
        page: _halamanPesanan,
        pageSize: _pageSizePesanan,
      );
      final hasil = await ApiClient.instance.aksi('pesanan_list', payload);
      final data = ((hasil['pesanan'] as List?) ?? [])
          .map((e) => Pesanan.fromJson(e as Map<String, dynamic>))
          .toList();
      setStateIfMounted(() {
        _semua = data;
        _totalPesanan = (hasil['total'] as num?)?.toInt() ?? data.length;
        _daftarKasir = ((hasil['daftarKasir'] as List?) ?? const [])
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _ringkasan =
            (hasil['ringkasan'] as Map?)?.cast<String, dynamic>() ?? const {};
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatTransaksiPending({bool aturLoading = true}) async {
    if (aturLoading) setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await CoreDb.instance.listTransaksiPending(
        limit: _pageSizePesanan,
        offset: (_halamanPending - 1) * _pageSizePesanan,
        status: _statusPending,
      );
      final jumlahAktif = await CoreDb.instance.jumlahTransaksiPending();
      final interval =
          await TransaksiOutboxService.instance.muatIntervalRetryMenit();
      setStateIfMounted(() {
        _transaksiPending = hasil.data.cast<Map<String, dynamic>>();
        _totalTransaksiPending = hasil.total;
        _jumlahPendingAktif = jumlahAktif;
        _intervalRetryMenit = interval;
        _pesanError = null;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (aturLoading && mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatRingkasanPending() async {
    final jumlah = await CoreDb.instance.jumlahTransaksiPending();
    final interval =
        await TransaksiOutboxService.instance.muatIntervalRetryMenit();
    setStateIfMounted(() {
      _jumlahPendingAktif = jumlah;
      _intervalRetryMenit = interval;
    });
  }

  Future<void> _sinkronkanPendingSekarang() async {
    if (_sedangSinkronPending) return;
    setStateIfMounted(() => _sedangSinkronPending = true);
    try {
      final hasil = await TransaksiOutboxService.instance.sinkronkan();
      await _muatTransaksiPending(aturLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${hasil.berhasil} dari ${hasil.total} transaksi berhasil dikirim.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e,
            aktivitas: 'sinkron transaksi pending');
      }
    } finally {
      setStateIfMounted(() => _sedangSinkronPending = false);
    }
  }

  Future<void> _aturIntervalRetry() async {
    final controller =
        TextEditingController(text: _intervalRetryMenit.toString());
    final simpan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Interval Retry Transaksi Pending'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Aplikasi akan mencoba mengirim ulang transaksi Pending secara otomatis. Nilai bawaan adalah 10 menit.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Interval (menit)',
                helperText: 'Minimal 1 menit, maksimal 1.440 menit',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (simpan != true) {
      controller.dispose();
      return;
    }
    final menit = int.tryParse(controller.text.trim());
    controller.dispose();
    if (menit == null || menit < 1 || menit > 1440) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Interval harus antara 1 sampai 1.440 menit.')));
      }
      return;
    }
    await TransaksiOutboxService.instance.aturIntervalRetryMenit(menit);
    setStateIfMounted(() => _intervalRetryMenit = menit);
  }

  Map<String, dynamic> _payloadPending(Map<String, dynamic> row) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode('${row['payload_json']}') as Map);
    } catch (_) {
      return const {};
    }
  }

  String _waktuPending(Object? nilai) {
    try {
      return DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse('$nilai'));
    } catch (_) {
      return '$nilai';
    }
  }

  Future<void> _lihatDetailPending(Map<String, dynamic> row) async {
    final payload = _payloadPending(row);
    final items = (payload['transaksi'] as List?) ?? const [];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Transaksi ${row['kode_unik'] ?? '-'}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Status: ${row['status'] == 'SYNCED' ? 'Sukses' : row['status']}'),
                Text('Dibuat: ${_waktuPending(row['dibuat_pada'])}'),
                Text('Percobaan kirim: ${row['percobaan'] ?? 0}'),
                Text(
                    'Terakhir dicoba: ${row['terakhir_dicoba'] == null ? '-' : _waktuPending(row['terakhir_dicoba'])}'),
                const Divider(height: 24),
                const Text('Rincian barang',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...items.map((item) {
                  final map = item is Map ? item : const {};
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                        '${map['nama'] ?? map['kode'] ?? '-'} × ${map['jumlah'] ?? 0} — ${_formatRupiah.format((map['harga'] as num?)?.toDouble() ?? 0)}'),
                  );
                }),
                const Divider(height: 24),
                Text(
                    'Total: ${_formatRupiah.format((payload['total'] as num?)?.toDouble() ?? 0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if ('${row['pesan_error'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Kendala terakhir',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText('${row['pesan_error']}'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _tabelTransaksiPending() {
    final totalHalaman =
        (_totalTransaksiPending / _pageSizePesanan).ceil().clamp(1, 999999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionCard(
          judul: 'Transaksi Pending Lokal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Transaksi tetap tersimpan di perangkat ini sebagai jurnal audit. Yang masih Pending dicoba ulang setiap $_intervalRetryMenit menit dan tidak dihapus setelah Sukses.'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opsi in <String?, String>{
                    null: 'Semua',
                    'PENDING': 'Pending',
                    'SYNCED': 'Sukses',
                    'GAGAL': 'Gagal',
                  }.entries)
                    ChoiceChip(
                      label: Text(opsi.value),
                      selected: _statusPending == opsi.key,
                      onSelected: (_) {
                        setStateIfMounted(() {
                          _statusPending = opsi.key;
                          _halamanPending = 1;
                        });
                        _muatTransaksiPending();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppDataTable(
          minWidth: 1080,
          emptyText: 'Belum ada transaksi pending pada perangkat ini.',
          columns: const [
            AppTableColumn('Waktu', flex: 2),
            AppTableColumn('Kode Transaksi', flex: 3),
            AppTableColumn('Kasir / Toko', flex: 2),
            AppTableColumn('Total', flex: 2, align: TextAlign.right),
            AppTableColumn('Percobaan', flex: 1, align: TextAlign.center),
            AppTableColumn('Status', flex: 1, align: TextAlign.center),
            AppTableColumn('Kendala Terakhir', flex: 4),
            AppTableColumn('Aksi', width: 64, align: TextAlign.center),
          ],
          rows: _transaksiPending.map((row) {
            final payload = _payloadPending(row);
            final status = '${row['status'] ?? 'PENDING'}';
            final label = status == 'SYNCED'
                ? 'Sukses'
                : status == 'GAGAL'
                    ? 'Gagal'
                    : 'Pending';
            final warna = status == 'SYNCED'
                ? AppColors.success
                : status == 'GAGAL'
                    ? Colors.red
                    : AppColors.warning;
            return AppTableRowData(
              onTap: () => _lihatDetailPending(row),
              cells: [
                AppTableCell.text(_waktuPending(row['dibuat_pada']), flex: 2),
                AppTableCell.text('${row['kode_unik'] ?? '-'}', flex: 3),
                AppTableCell.text(
                    '${row['akun_kunci'] ?? payload['kasir'] ?? '-'} / ${row['toko_id'] ?? payload['tokoId'] ?? '-'}',
                    flex: 2),
                AppTableCell.text(
                    _formatRupiah
                        .format((payload['total'] as num?)?.toDouble() ?? 0),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                AppTableCell.text('${row['percobaan'] ?? 0}',
                    flex: 1, align: TextAlign.center),
                AppTableCell(
                  flex: 1,
                  align: TextAlign.center,
                  child: StatusPill(label: label, warna: warna),
                ),
                AppTableCell.text('${row['pesan_error'] ?? '-'}',
                    flex: 4, maxLines: 2),
                AppTableCell(
                  width: 64,
                  align: TextAlign.center,
                  child: IconButton(
                    tooltip: 'Lihat rincian dan kendala',
                    onPressed: () => _lihatDetailPending(row),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                ),
              ],
            );
          }).toList(),
          pagination: AppTablePagination(
            halaman: _halamanPending,
            totalHalaman: totalHalaman,
            totalData: _totalTransaksiPending,
            labelData: 'transaksi lokal',
            onSebelumnya: _halamanPending > 1
                ? () {
                    setStateIfMounted(() => _halamanPending--);
                    _muatTransaksiPending();
                  }
                : null,
            onBerikutnya: _halamanPending < totalHalaman
                ? () {
                    setStateIfMounted(() => _halamanPending++);
                    _muatTransaksiPending();
                  }
                : null,
          ),
        ),
      ],
    );
  }

  String _formatTanggalIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _payloadDaftarPesanan({
    required int page,
    required int pageSize,
    _Filter? filter,
    bool? hanyaBelumLunas,
    bool gunakanFilterTambahan = true,
  }) {
    final filterEfektif = filter ?? _filter;
    final payload = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (filterEfektif == _Filter.online) payload['asal'] = 'online';
    if (filterEfektif == _Filter.tertahan) payload['asal'] = 'tertahan';
    // BUG LAMA (fixed): sebelumnya `hanya_belum_lunas` selalu true, jadi
    // pesanan yang SUDAH lunas tak pernah ikut termuat sama sekali --
    // sekarang opsional lewat chip filter, default menampilkan semua.
    if (hanyaBelumLunas ?? _hanyaBelumLunas) {
      payload['hanya_belum_lunas'] = true;
    }
    if (gunakanFilterTambahan) {
      if (_sejak != null) payload['sejak'] = _formatTanggalIso(_sejak!);
      if (_sampai != null) payload['sampai'] = _formatTanggalIso(_sampai!);
      if (_kodeController.text.trim().isNotEmpty) {
        payload['kode'] = _kodeController.text.trim();
      }
      if (_pembeliController.text.trim().isNotEmpty) {
        payload['pembeli'] = _pembeliController.text.trim();
      }
      if (Sesi.instance.isAdmin && _pedagangController.text.trim().isNotEmpty) {
        payload['pedagang'] = _pedagangController.text.trim();
      }
      if (_kasir.isNotEmpty) payload['kasir'] = _kasir;
    }
    return payload;
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = (mulai ? _sejak : _sampai) ?? DateTime.now();
    final hasil = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (hasil == null) return;
    setStateIfMounted(() {
      if (mulai) {
        _sejak = hasil;
      } else {
        _sampai = hasil;
      }
      _halamanPesanan = 1;
    });
  }

  Future<void> _hitungUlang(Pesanan p) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('pesanan_hitung_ulang', {'draft_id': p.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(hasil['description']?.toString() ??
                '${p.kode}: dihitung ulang.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'menghitung ulang pesanan');
      }
    }
  }

  /// Mengambil SELURUH keranjang tertahan yang belum lunas, bukan hanya 15
  /// baris pada halaman yang sedang terlihat. Data dibekukan dulu sebelum
  /// pembayaran dimulai agar paging tidak bergeser ketika sebagian draft
  /// berubah menjadi lunas.
  Future<List<Pesanan>> _ambilSemuaTertahanBelumLunas() async {
    final hasilSemua = <Pesanan>[];
    final idSudahAda = <int>{};
    var page = 1;
    while (true) {
      final hasil = await ApiClient.instance.aksi(
        'pesanan_list',
        _payloadDaftarPesanan(
          page: page,
          pageSize: 100,
          filter: _Filter.tertahan,
          hanyaBelumLunas: true,
          gunakanFilterTambahan: false,
        ),
      );
      final data = ((hasil['pesanan'] as List?) ?? [])
          .map((e) => Pesanan.fromJson(e as Map<String, dynamic>))
          .where((p) => !p.dariPembeliOnline && !_sudahTerbayar(p))
          .toList();
      for (final pesanan in data) {
        if (idSudahAda.add(pesanan.id)) hasilSemua.add(pesanan);
      }
      final total = (hasil['total'] as num?)?.toInt() ?? hasilSemua.length;
      if (data.isEmpty || page * 100 >= total) break;
      page++;
    }
    return hasilSemua;
  }

  Future<void> _bayarkanSemuaYangTertahan() async {
    if (_sedangMembayarSemuaTertahan) return;
    setStateIfMounted(() => _sedangMembayarSemuaTertahan = true);
    try {
      final tertahan = await _ambilSemuaTertahanBelumLunas();
      if (!mounted) return;
      if (tertahan.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada transaksi tertahan yang perlu dibayar.'),
        ));
        return;
      }

      final totalNominal = tertahan.fold<double>(
        0,
        (jumlah, pesanan) => jumlah + pesanan.totalBiaya,
      );
      final caraBayar = await showDialog<CaraBayar>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Pilih Metode Pembayaran'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '${tertahan.length} transaksi tertahan dengan total '
                '${_formatRupiah.format(totalNominal)} akan menggunakan '
                'satu metode pembayaran yang sama.',
              ),
            ),
            ...Sesi.instance.caraBayar.map(
              (cara) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(cara),
                child: Text(cara.nama),
              ),
            ),
          ],
        ),
      );
      if (caraBayar == null || !mounted) return;

      final dikonfirmasi = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bayarkan Semua yang Tertahan?'),
          content: Text(
            'Anda akan membayar ${tertahan.length} transaksi tertahan '
            'senilai ${_formatRupiah.format(totalNominal)} menggunakan '
            '${caraBayar.nama}.\n\n'
            'Setiap transaksi akan diperiksa dan disimpan satu per satu. '
            'Transaksi yang gagal tidak akan ditandai terbayar dan akan '
            'tetap berada di daftar Tertahan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Ya, Bayarkan Semua'),
            ),
          ],
        ),
      );
      if (dikonfirmasi != true) return;

      var berhasil = 0;
      var nilaiBerhasil = 0.0;
      final gagal = <String>[];
      String? detailStokKurang;
      Object? errorPertama;
      for (final pesanan in tertahan) {
        try {
          await ApiClient.instance
              .aksi('bayar', _payloadVerifikasi(pesanan, caraBayar));
          berhasil++;
          nilaiBerhasil += pesanan.totalBiaya;
        } catch (e) {
          errorPertama ??= e;
          if (e is ApiException && e.kode == 'STOK_TIDAK_CUKUP') {
            detailStokKurang ??= '${pesanan.kode}: ${e.pesan}';
          }
          final pesanMudah = e is ApiException
              ? e.info.pesan
              : AppErrorInfo.dari(e, aktivitas: 'membayar pesanan').pesan;
          gagal.add('${pesanan.kode}: $pesanMudah');
        }
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pembayaran Massal Selesai'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$berhasil dari ${tertahan.length} transaksi berhasil '
                  'dibayar (${_formatRupiah.format(nilaiBerhasil)}).',
                ),
                if (gagal.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${gagal.length} transaksi tetap tertahan karena belum '
                    'berhasil diproses:',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...gagal.take(10).map((pesan) => Text('• $pesan')),
                  if (gagal.length > 10)
                    Text('• ... dan ${gagal.length - 10} transaksi lainnya.'),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
      if (detailStokKurang != null && mounted) {
        await tampilkanPanduanStokKosong(
          context,
          detail: detailStokKurang,
        );
      }
      if (errorPertama != null && mounted) {
        final e = errorPertama;
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'membayar semua transaksi tertahan');
      }
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'membayar semua transaksi tertahan');
      }
    } finally {
      setStateIfMounted(() => _sedangMembayarSemuaTertahan = false);
      if (mounted) await _muat();
    }
  }

  Map<String, dynamic> _payloadVerifikasi(Pesanan p, CaraBayar caraBayar) {
    final kodeUnik = '${p.kode}-VERIF-${DateTime.now().millisecondsSinceEpoch}';
    return {
      'kodeUnik': kodeUnik,
      'clientTrxId': kodeUnik,
      'idToko': Sesi.instance.tokoId,
      'tokoId': Sesi.instance.tokoId,
      'kasir': Sesi.instance.userId,
      'waktu': _formatWaktuServer(DateTime.now()),
      'caraBayar': caraBayar.id,
      'total': p.totalBiaya,
      'id_member': p.anggotaId,
      'draftPembelianAnggotaKoperasi': p.id,
      'draftPembelianAnggotaKoperasiId': p.id,
      'idDraftPembelianAnggotaKoperasi': p.id,
      'draft_pembelian_anggota_koperasi': p.id,
      'draft_pembelian_anggota_koperasi_id': p.id,
      'id_draft_pembelian_anggota_koperasi': p.id,
      'draftPembelianId': p.id,
      'draft_pembelian_id': p.id,
      'draftId': p.id,
      'draft_id': p.id,
      'idDraft': p.id,
      'kodeDraft': p.kode,
      'draftKode': p.kode,
      'kodeDraftPembelianAnggotaKoperasi': p.kode,
      'kode_draft_pembelian_anggota_koperasi': p.kode,
      'transaksi': p.items
          .map((i) => {
                'id': i.produkId,
                'kode': i.kode,
                'nama': i.nama,
                'harga': i.harga,
                'jumlah': i.jumlah,
                'diskon': i.diskon,
                'aturanDiskon': i.aturanDiskonId,
                'cashback': i.cashback,
              })
          .toList(),
    };
  }

  List<Pesanan> get _tersaring {
    switch (_filter) {
      case _Filter.online:
        return _semua
            .where((p) => p.dariPembeliOnline && !_sudahTerbayar(p))
            .toList();
      case _Filter.tertahan:
        return _semua
            .where((p) => !p.dariPembeliOnline && !_sudahTerbayar(p))
            .toList();
      case _Filter.semua:
        return _semua;
      case _Filter.pending:
        return const [];
    }
  }

  bool _sudahTerbayar(Pesanan p) => p.lunas || p.lunasId != null;

  String _labelStatus(Pesanan p) {
    if (_sudahTerbayar(p)) return 'Terbayar';
    return p.dariPembeliOnline ? 'Online' : 'Tertahan';
  }

  Color _warnaStatus(Pesanan p) {
    if (_sudahTerbayar(p)) return AppColors.success;
    return p.dariPembeliOnline
        ? const Color(0xFF0284C7)
        : const Color(0xFFB8860B);
  }

  Future<void> _lihatDetail(Pesanan p) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Detail ${p.kode}'),
        content: SizedBox(
          width: 820,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ringkasanDetailPesanan(p),
                  const SizedBox(height: 12),
                  _tabelDetailPesanan(p),
                  const SizedBox(height: 12),
                  _totalDetailPesanan(p),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup')),
          if (!p.dariPembeliOnline)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _cetakStrukTertahan(p);
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Cetak Struk'),
            ),
          // Keranjang Tertahan (draft lokal, BUKAN pesanan online) -- gap-closure:
          // sebelumnya dialog ini murni tampilan, satu-satunya jalan lanjut
          // (Muat ke Keranjang) tersembunyi di menu tekan-tahan yang tak lazim
          // dipakai mouse desktop. Tombol ini langsung ke KasirScreen sama
          // seperti _tampilkanAksi, bukan alur baru.
          if (!p.dariPembeliOnline && !_sudahTerbayar(p))
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _muatKeKeranjang(p);
              },
              icon: const Icon(Icons.shopping_cart_checkout, size: 18),
              label: const Text('Muat ke Keranjang'),
            ),
          if (p.dariPembeliOnline && !_sudahTerbayar(p))
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _verifikasiDanSelesaikan(p);
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Verifikasi & Selesaikan'),
            ),
          if (Sesi.instance.bolehHapusPesanan)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _batalkan(p);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: Text(_sudahTerbayar(p)
                  ? 'Batalkan Pembelian'
                  : 'Batalkan Pesanan'),
            ),
        ],
      ),
    );
  }

  void _cetakStrukTertahan(Pesanan p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StrukScreen(
          kode: p.kode,
          waktu: p.tanggalPembayaran.isEmpty ? '-' : p.tanggalPembayaran,
          // Baris ekstra (indukId != null) diberi indentasi visual "   + " --
          // sama spt flatten struk sukses di KeranjangScreen._bayar, urutan
          // asal dari server umumnya sudah induk-lalu-anak jadi cukup prefiks
          // tanpa perlu pengelompokan ulang di sini.
          item: p.items
              .map((i) => {
                    'nama': i.indukId != null ? '   + ${i.nama}' : i.nama,
                    'qty': i.jumlah,
                    'harga': i.harga,
                    'diskon': i.diskon,
                    'cashback': i.cashback,
                  })
              .toList(),
          total: p.totalBiaya,
          metode: _sudahTerbayar(p) ? 'Terbayar' : 'Tertahan',
          pajak: 0,
          tersinkron: true,
          statusLabel: _sudahTerbayar(p) ? 'Terbayar' : 'Tertahan (On Hold)',
          pelanggan: p.pemesan,
        ),
      ),
    );
  }

  Widget _ringkasanDetailPesanan(Pesanan p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chipDetail(Icons.person_outline,
            'Pemesan: ${p.pemesan.isEmpty ? "-" : p.pemesan}'),
        if (p.namaMesin != null)
          _chipDetail(Icons.devices_outlined, 'Mesin: ${p.namaMesin}'),
        if (p.kasirLoginNama.isNotEmpty)
          _chipDetail(Icons.badge_outlined, 'Kasir: ${p.kasirLoginNama}'),
        _chipDetail(
          p.dariPembeliOnline ? Icons.public : Icons.pause_circle_outline,
          p.dariPembeliOnline ? 'Pesanan Online' : 'Keranjang Tertahan',
        ),
        _chipDetail(
          _sudahTerbayar(p)
              ? Icons.check_circle_outline
              : Icons.hourglass_empty,
          'Status: ${_labelStatus(p)}',
        ),
      ],
    );
  }

  Widget _chipDetail(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelDetailPesanan(Pesanan p) {
    String formatJumlah(double jumlah) =>
        jumlah.toStringAsFixed(jumlah == jumlah.roundToDouble() ? 0 : 2);

    return AppDataTable(
      minWidth: 760,
      emptyText: 'Tidak ada item pesanan.',
      columns: const [
        AppTableColumn('Produk', flex: 4),
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Qty', width: 72, align: TextAlign.center),
        AppTableColumn('Harga', flex: 2, align: TextAlign.right),
        AppTableColumn('Diskon', flex: 2, align: TextAlign.right),
        AppTableColumn('Subtotal', flex: 2, align: TextAlign.right),
      ],
      rows: p.items.map((item) {
        final subtotal = item.harga * item.jumlah - item.diskon;
        // Baris ekstra (indukId != null) diindentasi visual -- lihat JavaDoc
        // _cetakStrukTertahan utk alasan yg sama.
        return AppTableRowData(cells: [
          AppTableCell.text(
            item.indukId != null ? '   + ${item.nama}' : item.nama,
            flex: 4,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight:
                  item.indukId != null ? FontWeight.w500 : FontWeight.w700,
              color: item.indukId != null
                  ? AppColors.textSecondaryOf(context)
                  : AppColors.textPrimaryOf(context),
            ),
          ),
          AppTableCell.text(
            item.kode.isEmpty ? '-' : item.kode,
            flex: 2,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
              fontFamily: 'monospace',
            ),
          ),
          AppTableCell.text(
            formatJumlah(item.jumlah),
            width: 72,
            align: TextAlign.center,
          ),
          AppTableCell.text(
            _formatRupiah.format(item.harga),
            flex: 2,
            align: TextAlign.right,
          ),
          AppTableCell.text(
            item.diskon <= 0 ? '-' : _formatRupiah.format(item.diskon),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              color: item.diskon <= 0
                  ? AppColors.textSecondaryOf(context)
                  : AppColors.warning,
            ),
          ),
          AppTableCell.text(
            _formatRupiah.format(subtotal),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ]);
      }).toList(),
    );
  }

  Widget _totalDetailPesanan(Pesanan p) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AppSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.totalDiskon > 0)
                _barisTotalDetail(
                    'Diskon', '-${_formatRupiah.format(p.totalDiskon)}',
                    warna: AppColors.warning),
              if (p.totalCashback > 0)
                _barisTotalDetail(
                    'Cashback', '+${_formatRupiah.format(p.totalCashback)}',
                    warna: AppColors.success),
              _barisTotalDetail(
                'Total',
                _formatRupiah.format(p.totalBiaya),
                tebal: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barisTotalDetail(
    String label,
    String nilai, {
    bool tebal = false,
    Color? warna,
  }) {
    final gaya = TextStyle(
      fontSize: tebal ? 16 : 12.5,
      fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
      color: warna ?? AppColors.textPrimaryOf(context),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: gaya),
          Text(nilai, style: gaya),
        ],
      ),
    );
  }

  Future<void> _muatKeKeranjang(Pesanan p) async {
    Anggota? member;
    if (p.anggotaId != null) {
      try {
        final hasil =
            await ApiClient.instance.aksi('cari_member', {'id': p.anggotaId});
        final arr = (hasil['member'] as List?) ?? [];
        if (arr.isNotEmpty) {
          member = Anggota.fromJson(arr.first as Map<String, dynamic>);
        }
      } catch (_) {
        // Gagal memuat detail member -- tetap lanjut memuat keranjang tanpa member (bukan blocker).
      }
    }
    final produkCache = await CoreDb.instance.produkCache();
    int? idProduk(ItemPesanan item) {
      if (item.produkId != null && item.produkId! > 0) return item.produkId;
      final kode = item.kode.trim();
      if (kode.isEmpty) return null;
      for (final row in produkCache) {
        if ('${row['kode'] ?? ''}'.trim() == kode) {
          final id = row['id'];
          if (id is int) return id;
          if (id is num) return id.toInt();
          return int.tryParse('${id ?? ''}');
        }
      }
      return null;
    }

    // Gap-closure "Produk Ekstra": server mengembalikan baris ekstra FLAT
    // (sejajar dgn baris dasar), dibedakan lewat [ItemPesanan.indukId] yg
    // menunjuk ke [ItemPesanan.draftItemId] baris induknya (lihat JavaDoc
    // model). Kelompokkan dulu di sini SEBELUM membangun [ItemKeranjang]
    // supaya "Muat ke Keranjang" merestorasi struktur bersarang yg sama
    // spt saat pertama ditahan -- tanpa ini tiap ekstra akan jadi baris
    // keranjang top-level sendiri-sendiri (kehilangan keterkaitan ke induk).
    // Draft LAMA (server belum kirim field ini / bukan produk ekstra sama
    // sekali) -- semua `indukId` null, `ekstraByInduk` selalu kosong,
    // perilaku identik sblm gap-closure ini.
    final baseItems = <ItemPesanan>[];
    final ekstraByInduk = <int, List<ItemPesanan>>{};
    for (final i in p.items) {
      final indukId = i.indukId;
      if (indukId != null) {
        ekstraByInduk.putIfAbsent(indukId, () => []).add(i);
      } else {
        baseItems.add(i);
      }
    }

    final itemTanpaId = <ItemPesanan>[];
    final keranjang = <ItemKeranjang>[];
    final indukTerpakai = <int>{};
    for (final i in baseItems) {
      final produkId = idProduk(i);
      if (produkId == null || produkId <= 0) {
        itemTanpaId.add(i);
        continue;
      }
      final anak = i.draftItemId == null
          ? const <ItemPesanan>[]
          : (ekstraByInduk[i.draftItemId] ?? const <ItemPesanan>[]);
      if (i.draftItemId != null) indukTerpakai.add(i.draftItemId!);
      final ekstra = <ItemEkstra>[];
      var ekstraGagal = false;
      for (final e in anak) {
        final idEkstra = idProduk(e);
        if (idEkstra == null || idEkstra <= 0) {
          itemTanpaId.add(e);
          ekstraGagal = true;
          continue;
        }
        ekstra.add(ItemEkstra(
            id: idEkstra, kode: e.kode, nama: e.nama, harga: e.harga));
      }
      if (ekstraGagal) {
        // Batalkan seluruh muat (lihat gerbang di bawah).
        continue;
      }
      keranjang.add(
        ItemKeranjang(
          produk: Produk(
            id: produkId,
            kode: i.kode,
            barcode: '',
            nama: i.nama,
            hargaJual: i.harga,
            stok: 999999,
            kategoriId: null,
            kategoriNama: '',
            gambarUrl: null,
          ),
          jumlah: i.jumlah.round(),
          diskon: i.diskon,
          cashback: i.cashback,
          aturanDiskonId: i.aturanDiskonId,
          ekstra: ekstra,
        ),
      );
    }
    // Baris ekstra "yatim" (indukId menunjuk ke draftItemId yg tak pernah
    // ditemukan di antara baris dasar, mis. anomali data) -- jangan dibuang
    // diam-diam (bisa berarti kehilangan tagihan), perlakukan sbg kegagalan
    // spt baris tanpa ID produk supaya muncul di pesan error di bawah.
    for (final entry in ekstraByInduk.entries) {
      if (!indukTerpakai.contains(entry.key)) itemTanpaId.addAll(entry.value);
    }
    if (itemTanpaId.isNotEmpty) {
      if (mounted) {
        final daftar =
            itemTanpaId.map((i) => i.kode.isEmpty ? i.nama : i.kode).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Tidak bisa memuat ke keranjang. ID produk tidak ditemukan untuk: $daftar')));
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KasirScreen(
        keranjangAwal: keranjang,
        draftIdSumber: p.id,
        draftKodeSumber: p.kode,
        memberAwal: member,
      ),
    ));
    await _muat();
  }

  Future<void> _verifikasiDanSelesaikan(Pesanan p) async {
    final caraBayar = await showDialog<CaraBayar>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pilih Metode Pembayaran'),
        children: Sesi.instance.caraBayar
            .map((c) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(c),
                child: Text(c.nama)))
            .toList(),
      ),
    );
    if (caraBayar == null) return;

    try {
      await ApiClient.instance.aksi('bayar', _payloadVerifikasi(p, caraBayar));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${p.kode} berhasil diselesaikan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        if (e is ApiException && e.kode == 'STOK_TIDAK_CUKUP') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.pesan),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 8),
          ));
          await tampilkanPanduanStokKosong(context, detail: e.pesan);
        } else {
          await tampilkanKesalahan(context, e is ApiException ? e.info : e,
              aktivitas: 'menyelesaikan pembayaran pesanan');
        }
      }
    }
  }

  String _formatWaktuServer(DateTime d) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${pad(d.day)}-${pad(d.month)}-${d.year} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  Future<void> _batalkan(Pesanan p) async {
    final alasanController = TextEditingController();
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
            _sudahTerbayar(p) ? 'Batalkan Pembelian?' : 'Batalkan Pesanan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_sudahTerbayar(p)
                ? '${p.kode} sudah terbayar. Pembatalan akan mengoreksi stok, saldo, dan transaksi terkait serta menyimpan jejak audit. Tindakan ini tidak dapat dipulihkan otomatis.'
                : '${p.kode} akan dibatalkan dan dihapus dari daftar pesanan aktif. Tindakan ini tidak bisa dibatalkan.'),
            const SizedBox(height: 12),
            TextField(
              controller: alasanController,
              decoration: const InputDecoration(
                  labelText: 'Alasan Pembatalan *',
                  border: OutlineInputBorder()),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    final alasan = alasanController.text.trim();
    if (alasan.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      }
      return;
    }
    try {
      final hasil = await ApiClient.instance
          .aksi('batal_pesanan', {'id': p.id, 'alasan': alasan});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(hasil['description']?.toString() ??
                (_sudahTerbayar(p)
                    ? 'Pembelian berhasil dibatalkan.'
                    : 'Pesanan berhasil dibatalkan.'))));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'membatalkan pesanan');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final semua = _semua;
    final pesananTersaring = _tersaring;
    final totalHalamanPesanan =
        (_totalPesanan / _pageSizePesanan).ceil().clamp(1, 999999).toInt();
    final halamanPesanan =
        _halamanPesanan.clamp(1, totalHalamanPesanan).toInt();
    final pesananHalamanIni = pesananTersaring;
    final belumTerbayar = semua.where((p) => !_sudahTerbayar(p)).toList();
    final jumlahOnline = (_ringkasan['online'] as num?)?.toInt() ??
        belumTerbayar.where((p) => p.dariPembeliOnline).length;
    final jumlahTertahan = (_ringkasan['tertahan'] as num?)?.toInt() ??
        belumTerbayar.where((p) => !p.dariPembeliOnline).length;
    final jumlahTerbayar = (_ringkasan['terbayar'] as num?)?.toInt() ??
        semua.where(_sudahTerbayar).length;
    final nilaiMenunggu = (_ringkasan['nilaiMenunggu'] as num?)?.toDouble() ??
        belumTerbayar.fold<double>(0, (s, p) => s + p.totalBiaya);
    final sedangDiPending = _filter == _Filter.pending;
    final tombolAksi = [
      if (!sedangDiPending)
        HeaderActionButton(
          icon: _filterTerbuka ? Icons.filter_alt : Icons.filter_alt_outlined,
          label: 'Filter',
          onPressed: () =>
              setStateIfMounted(() => _filterTerbuka = !_filterTerbuka),
        ),
      if (!sedangDiPending && Sesi.instance.bolehKelola)
        HeaderActionButton(
          icon: Icons.playlist_add_check,
          label: _sedangMembayarSemuaTertahan
              ? 'Memproses...'
              : 'Bayarkan Semua yang Tertahan',
          tooltip: 'Bayarkan seluruh transaksi berstatus Tertahan',
          loading: _sedangMembayarSemuaTertahan
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onPressed: _sedangMembayarSemuaTertahan || jumlahTertahan == 0
              ? null
              : _bayarkanSemuaYangTertahan,
        ),
      if (sedangDiPending) ...[
        HeaderActionButton(
          icon: Icons.settings_outlined,
          label: 'Retry $_intervalRetryMenit menit',
          tooltip: 'Atur interval pengiriman ulang otomatis',
          onPressed: _aturIntervalRetry,
        ),
        HeaderActionButton(
          icon: Icons.sync,
          label: _sedangSinkronPending ? 'Mengirim...' : 'Retry Sekarang',
          onPressed: _sedangSinkronPending ? null : _sinkronkanPendingSekarang,
        ),
      ],
      HeaderActionButton(
          icon: Icons.refresh, label: 'Muat Ulang', onPressed: _muat),
    ];

    return AppShell(
      menuAktif: MenuEBisnis.pesanan,
      judul: 'Pesanan',
      subjudul: 'Pesanan online & transaksi yang ditahan',
      scrollable: false,
      actionsAppBar: tombolAksi,
      aksiHeader: Wrap(
        alignment: WrapAlignment.end,
        runSpacing: 8,
        children: tombolAksi,
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _muat, child: const Text('Coba Lagi')),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setStateIfMounted(() {
                              _filter = _Filter.pending;
                              _halamanPending = 1;
                            });
                            _muat();
                          },
                          icon: const Icon(Icons.pending_actions),
                          label: const Text('Buka Transaksi Pending'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    children: [
                      SizedBox(
                        height: _tinggiKartuKpiPesanan,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _kartuKpi(
                                Icons.receipt_long_outlined,
                                'Total',
                                '${(_ringkasan['total'] as num?)?.toInt() ?? _totalPesanan}',
                                const Color(0xFF1E3A5F)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.public, 'Online', '$jumlahOnline',
                                const Color(0xFF0284C7)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.pause_circle_outline, 'Tertahan',
                                '$jumlahTertahan', const Color(0xFFB8860B)),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.pending_actions, 'Pending Lokal',
                                '$_jumlahPendingAktif', AppColors.warning),
                            const SizedBox(width: 8),
                            _kartuKpi(Icons.check_circle_outline, 'Terbayar',
                                '$jumlahTerbayar', AppColors.success),
                            const SizedBox(width: 8),
                            _kartuKpi(
                                Icons.hourglass_empty,
                                'Nilai Menunggu',
                                _formatRupiah.format(nilaiMenunggu),
                                const Color(0xFFC0563D)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_filterTerbuka) ...[
                        AppSectionCard(
                          judul: 'Filter Pesanan',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _pilihTanggal(mulai: true),
                                      icon: const Icon(Icons.date_range,
                                          size: 16),
                                      label: Text(
                                          _sejak == null
                                              ? 'Sejak Tanggal'
                                              : _formatTanggalIso(_sejak!),
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _pilihTanggal(mulai: false),
                                      icon: const Icon(Icons.date_range,
                                          size: 16),
                                      label: Text(
                                          _sampai == null
                                              ? 'Sampai Tanggal'
                                              : _formatTanggalIso(_sampai!),
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: TextField(
                                        controller: _kodeController,
                                        decoration: const InputDecoration(
                                            labelText: 'Kode',
                                            isDense: true,
                                            border: OutlineInputBorder())),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: TextField(
                                        controller: _pembeliController,
                                        decoration: const InputDecoration(
                                            labelText: 'Nama Pembeli',
                                            isDense: true,
                                            border: OutlineInputBorder())),
                                  ),
                                  if (Sesi.instance.isAdmin)
                                    SizedBox(
                                      width: 200,
                                      child: TextField(
                                          controller: _pedagangController,
                                          decoration: const InputDecoration(
                                              labelText: 'Toko/Pedagang',
                                              isDense: true,
                                              border: OutlineInputBorder())),
                                    ),
                                  SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<String>(
                                      value: _kasir.isEmpty ? null : _kasir,
                                      decoration: const InputDecoration(
                                        labelText: 'Nama Kasir',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      hint: const Text('Semua kasir'),
                                      items: [
                                        const DropdownMenuItem(
                                            value: '',
                                            child: Text('Semua kasir')),
                                        ..._daftarKasir.map((nama) =>
                                            DropdownMenuItem(
                                                value: nama,
                                                child: Text(nama,
                                                    overflow: TextOverflow
                                                        .ellipsis))),
                                      ],
                                      onChanged: (v) => setStateIfMounted(() {
                                        _kasir = v ?? '';
                                        _halamanPesanan = 1;
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FilterChip(
                                    label: const Text('Hanya Belum Lunas'),
                                    selected: _hanyaBelumLunas,
                                    onSelected: (v) => setStateIfMounted(() {
                                      _hanyaBelumLunas = v;
                                      _halamanPesanan = 1;
                                    }),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      setStateIfMounted(() {
                                        _sejak = null;
                                        _sampai = null;
                                        _hanyaBelumLunas = false;
                                        _halamanPesanan = 1;
                                        _kodeController.clear();
                                        _pembeliController.clear();
                                        _pedagangController.clear();
                                        _kasir = '';
                                      });
                                      _muat();
                                    },
                                    child: const Text('Reset'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                      onPressed: _muat,
                                      child: const Text('Terapkan')),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Semua'),
                            selected: _filter == _Filter.semua,
                            onSelected: (_) {
                              setStateIfMounted(() {
                                _filter = _Filter.semua;
                                _halamanPesanan = 1;
                              });
                              _muat();
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Online'),
                            selected: _filter == _Filter.online,
                            onSelected: (_) {
                              setStateIfMounted(() {
                                _filter = _Filter.online;
                                _halamanPesanan = 1;
                              });
                              _muat();
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Tertahan'),
                            selected: _filter == _Filter.tertahan,
                            onSelected: (_) {
                              setStateIfMounted(() {
                                _filter = _Filter.tertahan;
                                _halamanPesanan = 1;
                              });
                              _muat();
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Transaksi Pending'),
                            selected: _filter == _Filter.pending,
                            onSelected: (_) {
                              setStateIfMounted(() {
                                _filter = _Filter.pending;
                                _halamanPending = 1;
                              });
                              _muat();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_filter == _Filter.pending)
                        _tabelTransaksiPending()
                      else
                        AppDataTable(
                          minWidth: 1240,
                          emptyText: 'Tidak ada pesanan.',
                          columns: const [
                            AppTableColumn('Kode', flex: 2),
                            AppTableColumn('Pemesan', flex: 3),
                            AppTableColumn('Alasan Ditahan', flex: 3),
                            AppTableColumn('Kasir', flex: 2),
                            AppTableColumn('Status',
                                flex: 2, align: TextAlign.center),
                            AppTableColumn('Item', flex: 4),
                            AppTableColumn('Total',
                                flex: 2, align: TextAlign.right),
                            AppTableColumn('Aksi',
                                width: 96, align: TextAlign.center),
                          ],
                          rows: pesananHalamanIni.map((p) {
                            final warnaStatus = _warnaStatus(p);
                            final ringkasanItem = p.items.isEmpty
                                ? '-'
                                : p.items.take(3).map((item) {
                                    final jumlah = item.jumlah.toStringAsFixed(
                                        item.jumlah ==
                                                item.jumlah.roundToDouble()
                                            ? 0
                                            : 2);
                                    return '${item.nama} x$jumlah';
                                  }).join(', ');
                            final sisaItem = p.items.length > 3
                                ? ' +${p.items.length - 3} item'
                                : '';

                            return AppTableRowData(
                              onTap: () => _lihatDetail(p),
                              cells: [
                                AppTableCell.text(
                                  p.kode,
                                  flex: 2,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                AppTableCell.text(
                                  p.pemesan.isEmpty
                                      ? '(Tanpa member)'
                                      : p.pemesan,
                                  flex: 3,
                                ),
                                AppTableCell.text(
                                  p.dariPembeliOnline || p.keterangan.isEmpty
                                      ? '-'
                                      : p.keterangan,
                                  flex: 3,
                                  maxLines: 2,
                                ),
                                AppTableCell.text(
                                  p.kasirLoginNama.isEmpty
                                      ? '-'
                                      : p.kasirLoginNama,
                                  flex: 2,
                                  maxLines: 2,
                                ),
                                AppTableCell(
                                  flex: 2,
                                  align: TextAlign.center,
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: StatusPill(
                                      label: _labelStatus(p),
                                      warna: warnaStatus,
                                    ),
                                  ),
                                ),
                                AppTableCell.text(
                                  '$ringkasanItem$sisaItem',
                                  flex: 4,
                                  maxLines: 2,
                                ),
                                AppTableCell.text(
                                  _formatRupiah.format(p.totalBiaya),
                                  flex: 2,
                                  align: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                AppTableCell(
                                  width: 96,
                                  align: TextAlign.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Detail',
                                        icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 20),
                                        onPressed: () => _lihatDetail(p),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Aksi',
                                        icon: const Icon(Icons.more_horiz,
                                            size: 20),
                                        onPressed: () => _tampilkanAksi(p),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                          pagination: AppTablePagination(
                            halaman: halamanPesanan,
                            totalHalaman: totalHalamanPesanan,
                            totalData: pesananTersaring.length,
                            labelData: 'pesanan',
                            onSebelumnya: halamanPesanan > 1
                                ? () {
                                    setStateIfMounted(() =>
                                        _halamanPesanan = halamanPesanan - 1);
                                    _muat();
                                  }
                                : null,
                            onBerikutnya: halamanPesanan < totalHalamanPesanan
                                ? () {
                                    setStateIfMounted(() =>
                                        _halamanPesanan = halamanPesanan + 1);
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

  Widget _kartuKpi(IconData icon, String label, String nilai, Color warna) {
    return SizedBox(
        width: 140,
        height: _tinggiKartuKpiPesanan,
        child:
            AppKpiCard(icon: icon, warna: warna, nilai: nilai, label: label));
  }

  Future<void> _tampilkanAksi(Pesanan p) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Detail'),
                onTap: () {
                  Navigator.of(context).pop();
                  _lihatDetail(p);
                }),
            if (p.dariPembeliOnline && !_sudahTerbayar(p))
              ListTile(
                leading: const Icon(Icons.check_circle_outline,
                    color: Color(0xFF2E7D32)),
                title: const Text('Verifikasi & Selesaikan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _verifikasiDanSelesaikan(p);
                },
              ),
            if (!p.dariPembeliOnline && !_sudahTerbayar(p))
              ListTile(
                leading: const Icon(Icons.shopping_cart_checkout),
                title: const Text('Muat ke Keranjang'),
                onTap: () {
                  Navigator.of(context).pop();
                  _muatKeKeranjang(p);
                },
              ),
            if (Sesi.instance.bolehKelola && !_sudahTerbayar(p))
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Hitung Ulang'),
                onTap: () {
                  Navigator.of(context).pop();
                  _hitungUlang(p);
                },
              ),
            if (Sesi.instance.bolehHapusPesanan)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(_sudahTerbayar(p)
                    ? 'Batalkan Pembelian'
                    : 'Batalkan Pesanan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _batalkan(p);
                },
              ),
          ],
        ),
      ),
    );
  }
}
