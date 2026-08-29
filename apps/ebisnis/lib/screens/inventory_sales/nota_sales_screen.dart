import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../services/outbox_is.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Sesi Nota Sales (layar legacy 40-42).</h3>
///
/// Realisasi SPJ: penagihan (collection ber-sesi -> kas COLLECTION_CASH bila
/// tunai), penjualan tunai, biaya berkategori, kulakan dalam sesi, setoran,
/// ledger kas append-only, rekonsiliasi barang, dan penutupan ber-approval
/// Pemilik/Admin dengan DUA rumus terpisah (hasil bersih vs rekonsiliasi kas).
/// Laporan sesi (SCR-41) + cetak PDF (SCR-42).
class NotaSalesScreen extends StatefulWidget {
  const NotaSalesScreen({super.key});

  @override
  State<NotaSalesScreen> createState() => _NotaSalesScreenState();
}

class _NotaSalesScreenState extends State<NotaSalesScreen> with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
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
      await MasterOffline.daftarCacheDulu(
          'si_trip_list', {}, 'master:si_nota_sales', fieldData: 'rows',
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

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.notaSales,
      judul: 'Sesi Nota Sales',
      subjudul:
          'Aktivitas sales lapangan per keberangkatan: tagih, jual tunai, biaya, kulakan, kas, tutup sesi — layar legacy 40-42',
      scrollable: false,
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _PanelErrorNs(
                  pesan: _error!, detail: detailUntuk(_error), onCoba: _muat)
              : _data.isEmpty
                  ? Center(
                      child: Text(
                          'Belum ada sesi. Mulai dari menu SPJ (APPROVED → Mulai Jalan).',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondaryOf(context))))
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                          child: BannerPerubahanServer(
                            key: ValueKey('perubahan:${_diff.versi}'),
                            baru: _diff.idBaru.length,
                            berubah: _diff.idBerubah.length,
                            dihapus: _diff.jumlahHapus,
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
                            itemCount: _data.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final r = _data[i];
                              return KilauBaris(
                                kunci: '${r['id'] ?? r['_kunci'] ?? ''}',
                                idBaru: _diff.idBaru,
                                idBerubah: _diff.idBerubah,
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                          color:
                                              Theme.of(context).dividerColor)),
                                  child: ListTile(
                                    title: Text(
                                        '${r['nomor']} · ${r['salesNama']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5)),
                                    subtitle: Text(
                                        'SPJ ${r['spjNomor']} · mulai ${'${r['waktuMulai']}'.split('.').first}\nSaldo kas: ${_fmtRp.format(r['saldoKas'] ?? 0)}',
                                        style: const TextStyle(fontSize: 11.5)),
                                    isThreeLine: true,
                                    trailing: Text('${r['status']}',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700)),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  DetailSesiNotaSales(
                                                      sessionId:
                                                          (r['id'] as num)
                                                              .toInt())));
                                      _muat();
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ]),
                    ),
    );
  }
}

// =============================================================================
// DETAIL SESI (dipakai juga dari layar SPJ) -- public
// =============================================================================

class DetailSesiNotaSales extends StatefulWidget {
  final int sessionId;
  const DetailSesiNotaSales({super.key, required this.sessionId});

  @override
  State<DetailSesiNotaSales> createState() => _DetailSesiNotaSalesState();
}

class _DetailSesiNotaSalesState extends State<DetailSesiNotaSales>
    with JejakGalat {
  Map<String, dynamic>? _d;
  String? _error;
  bool _proses = false;

  @override
  void initState() {
    super.initState();
    // P7: kirim ulang antrean offline (tagihan/biaya/kulakan sesi) dulu.
    OutboxIs.flush().whenComplete(_muat);
  }

  Future<void> _muat() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('si_trip_detail', {'session_id': widget.sessionId});
      setStateIfMounted(
          () => _d = Map<String, dynamic>.from(hasil['data'] as Map));
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    }
  }

  Future<void> _aksi(String namaAksi, Map<String, dynamic> body,
      {String? sukses}) async {
    setStateIfMounted(() => _proses = true);
    try {
      /* LOKAL DULU untuk seluruh mutasi layar ini. Sesi sales dikerjakan di
       * lapangan, kerap tanpa sinyal; angka terjual/kembali harus tetap
       * tercatat saat itu juga. Aksi baca tidak melewati pembungkus ini. */
      final r = await MasterOffline.simpanAtauAntre(namaAksi, body,
          kunci: '$namaAksi:${body['trip_id'] ?? body['id'] ?? ''}');
      if (r['offline'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Tersimpan di perangkat, akan dikirim otomatis.')));
        }
        await _muat();
        return;
      }
      if (sukses != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(sukses)));
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

  // -- dialog kecil: kas sederhana (jual tunai / setoran) ------------------

  Future<void> _dialogKas(String judul, String aksi) async {
    final nominal = TextEditingController();
    final ket = TextEditingController();
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nominal,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
          TextField(
              controller: ket,
              decoration: const InputDecoration(labelText: 'Keterangan')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ya == true) {
      final n = double.tryParse(nominal.text) ?? 0;
      if (n <= 0) return;
      await _aksi(
          aksi,
          {
            'session_id': widget.sessionId,
            'nominal': n,
            'keterangan': ket.text.trim(),
          },
          sukses: '$judul tercatat.');
    }
  }

  Future<void> _dialogBiaya() async {
    List<Map<String, dynamic>> kategori = [];
    try {
      final hasil =
          await ApiClient.instance.aksi('si_expense_category_list', {});
      kategori = ((hasil['rows'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    if (!mounted || kategori.isEmpty) return;
    int kategoriId = (kategori.first['id'] as num).toInt();
    final nilai = TextEditingController();
    final uraian = TextEditingController();
    final penerima = TextEditingController();
    String metode = 'TUNAI';
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setD) => AlertDialog(
          title: const Text('Catat Biaya Sesi'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: kategoriId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  for (final k in kategori)
                    DropdownMenuItem(
                        value: (k['id'] as num).toInt(),
                        child: Text('${k['nama']}')),
                ],
                onChanged: (v) => setD(() => kategoriId = v ?? kategoriId),
              ),
              TextField(
                  controller: nilai,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nilai (Rp)')),
              TextField(
                  controller: uraian,
                  decoration: const InputDecoration(labelText: 'Uraian')),
              TextField(
                  controller: penerima,
                  decoration:
                      const InputDecoration(labelText: 'Penerima (opsional)')),
              DropdownButtonFormField<String>(
                value: metode,
                decoration: const InputDecoration(labelText: 'Metode'),
                items: const [
                  DropdownMenuItem(
                      value: 'TUNAI', child: Text('Tunai (kas sesi)')),
                  DropdownMenuItem(value: 'TRANSFER', child: Text('Transfer')),
                ],
                onChanged: (v) => setD(() => metode = v ?? 'TUNAI'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c2).pop(false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.of(c2).pop(true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ya == true) {
      final n = double.tryParse(nilai.text) ?? 0;
      if (n <= 0) return;
      // P7: idempoten kode_unik -> boleh diantre offline.
      try {
        final hasil = await OutboxIs.kirimAtauAntre('si_expense_create', {
          'session_id': widget.sessionId,
          'kategori_id': kategoriId,
          'nilai': n,
          'uraian': uraian.text.trim(),
          'penerima': penerima.text.trim(),
          'metode': metode,
          'kode_unik':
              'BIAYA-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(nilai)}',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(hasil['offline'] == true
                  ? 'Offline — biaya diantre, terkirim otomatis saat online.'
                  : 'Biaya tercatat.')));
        }
        await _muat();
      } catch (e) {
        if (mounted) {
          snackbarGalat(context, e);
        }
      }
    }
  }

  Future<void> _dialogPembelian() async {
    final total = TextEditingController();
    final dibayar = TextEditingController(text: '0');
    final ket = TextEditingController();
    String tujuan = 'MOBIL_SALES';
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setD) => AlertDialog(
          title: const Text('Catat Pembelian dalam Sesi'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: total,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Total faktur (Rp)')),
            TextField(
                controller: dibayar,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Dibayar/DP saat sesi (Rp)')),
            DropdownButtonFormField<String>(
              value: tujuan,
              decoration: const InputDecoration(labelText: 'Tujuan stok'),
              items: const [
                DropdownMenuItem(
                    value: 'MOBIL_SALES', child: Text('Stok Mobil Sales')),
                DropdownMenuItem(value: 'GUDANG', child: Text('Gudang/Toko')),
              ],
              onChanged: (v) => setD(() => tujuan = v ?? 'MOBIL_SALES'),
            ),
            TextField(
                controller: ket,
                decoration: const InputDecoration(
                    labelText: 'Keterangan / nomor faktur supplier')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c2).pop(false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.of(c2).pop(true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ya == true) {
      final t = double.tryParse(total.text) ?? 0;
      if (t <= 0) return;
      try {
        final hasil = await OutboxIs.kirimAtauAntre('si_trip_purchase_link', {
          'session_id': widget.sessionId,
          'total_faktur': t,
          'dibayar_sesi': double.tryParse(dibayar.text) ?? 0,
          'tujuan_stok': tujuan,
          'keterangan': ket.text.trim(),
          'kode_unik':
              'BELI-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(total)}',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(hasil['offline'] == true
                  ? 'Offline — pembelian diantre, terkirim otomatis saat online.'
                  : 'Pembelian tercatat.')));
        }
        await _muat();
      } catch (e) {
        if (mounted) {
          snackbarGalat(context, e);
        }
      }
    }
  }

  Future<void> _dialogHasilNota(Map<String, dynamic> n) async {
    String status = 'UNPAID';
    final hasilK = TextEditingController();
    final alasan = TextEditingController();
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setD) => AlertDialog(
          title: Text('Hasil Kunjungan — ${n['fakturNomor']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: status,
              decoration: const InputDecoration(labelText: 'Hasil'),
              items: const [
                DropdownMenuItem(value: 'UNPAID', child: Text('Belum bayar')),
                DropdownMenuItem(
                    value: 'PROMISE_TO_PAY', child: Text('Janji bayar')),
                DropdownMenuItem(
                    value: 'RETURNED', child: Text('Nota dikembalikan')),
                DropdownMenuItem(value: 'DISPUTED', child: Text('Sengketa')),
                DropdownMenuItem(value: 'LOST', child: Text('Hilang')),
              ],
              onChanged: (v) => setD(() => status = v ?? 'UNPAID'),
            ),
            TextField(
                controller: hasilK,
                decoration:
                    const InputDecoration(labelText: 'Catatan kunjungan')),
            TextField(
                controller: alasan,
                decoration: const InputDecoration(
                    labelText: 'Alasan gagal (bila ada)')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c2).pop(false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.of(c2).pop(true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ya == true) {
      await _aksi(
          'si_trip_nota_result',
          {
            'nota_id': n['id'],
            'status': status,
            'hasil_kunjungan': hasilK.text.trim(),
            'alasan_gagal': alasan.text.trim(),
          },
          sukses: 'Hasil kunjungan tersimpan.');
    }
  }

  /// Tagih nota dalam sesi: collection idempoten ber-trip_session_id (tunai
  /// otomatis masuk kas sesi COLLECTION_CASH di server).
  Future<void> _dialogTagih(Map<String, dynamic> n) async {
    final d = _d;
    if (d == null) return;
    final nominal = TextEditingController(
        text:
            '${(((n['saldoSaatAssign'] as num?) ?? 0).toDouble() - ((n['nilaiTertagih'] as num?) ?? 0).toDouble()).round()}');
    String metode = 'TUNAI';
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c2, setD) => AlertDialog(
          title: Text('Tagih — ${n['fakturNomor']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${n['customerNama']}'),
            TextField(
                controller: nominal,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Nominal diterima (Rp)')),
            DropdownButtonFormField<String>(
              value: metode,
              decoration: const InputDecoration(labelText: 'Metode'),
              items: const [
                DropdownMenuItem(value: 'TUNAI', child: Text('Tunai')),
                DropdownMenuItem(value: 'TRANSFER', child: Text('Transfer')),
              ],
              onChanged: (v) => setD(() => metode = v ?? 'TUNAI'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c2).pop(false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.of(c2).pop(true),
                child: const Text('Terima')),
          ],
        ),
      ),
    );
    if (ya == true) {
      final v = double.tryParse(nominal.text) ?? 0;
      if (v <= 0) return;
      // customer_id dicari dari piutang list milik faktur ini via receivable_list.
      try {
        final rl = await ApiClient.instance.aksi('si_receivable_list', {
          'tampilkan_lunas': true,
          'q': '${n['fakturNomor']}',
          'page': 1,
          'page_size': 5,
        });
        final rows = ((rl['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final baris = rows.firstWhere(
            (r) =>
                (r['id'] as num).toInt() == (n['piutangDocId'] as num).toInt(),
            orElse: () => rows.isEmpty ? {} : rows.first);
        if (baris.isEmpty) throw Exception('Faktur tidak ditemukan.');
        // P7: idempoten -> boleh diantre offline (kunjungan di area tanpa sinyal).
        final hasil = await OutboxIs.kirimAtauAntre('si_collection_create', {
          'customer_id': baris['customerId'],
          'nominal': v,
          'metode': metode,
          'trip_session_id': widget.sessionId,
          'kode_unik':
              'TAGIH-${widget.sessionId}-${n['piutangDocId']}-${DateTime.now().millisecondsSinceEpoch}',
          'alokasi': [
            {'piutang_id': n['piutangDocId'], 'nominal': v}
          ],
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(hasil['offline'] == true
                  ? 'Offline — tagihan diantre, terkirim otomatis saat online.'
                  : 'Penerimaan tercatat.')));
        }
        await _muat();
      } catch (e) {
        if (mounted) {
          snackbarGalat(context, e);
        }
      }
    }
  }

  Future<void> _dialogBarang(Map<String, dynamic> b) async {
    final terjual = TextEditingController(text: '${b['qtyTerjual']}');
    final kembali = TextEditingController(text: '${b['qtyKembali']}');
    final rusak = TextEditingController(text: '${b['qtyRusak']}');
    final hilang = TextEditingController(text: '${b['qtyHilang']}');
    final alasan = TextEditingController(text: '${b['alasanSelisih']}');
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${b['namaProduk']} (dimuat ${b['qtyDimuat']})'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: terjual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Terjual')),
            TextField(
                controller: kembali,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Kembali')),
            TextField(
                controller: rusak,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rusak')),
            TextField(
                controller: hilang,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Hilang')),
            TextField(
                controller: alasan,
                decoration: const InputDecoration(labelText: 'Alasan selisih')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ya == true) {
      await _aksi(
          'si_trip_barang_update',
          {
            'rows': [
              {
                'barang_id': b['id'],
                'qty_terjual': double.tryParse(terjual.text) ?? 0,
                'qty_kembali': double.tryParse(kembali.text) ?? 0,
                'qty_rusak': double.tryParse(rusak.text) ?? 0,
                'qty_hilang': double.tryParse(hilang.text) ?? 0,
                'alasan_selisih': alasan.text.trim(),
              }
            ]
          },
          sukses: 'Kuantitas barang tersimpan.');
    }
  }

  Future<void> _dialogTutup() async {
    final kas = TextEditingController();
    final catatan = TextEditingController();
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tutup Sesi (Approval Pemilik/Admin)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: kas,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Kas fisik aktual dihitung (Rp)')),
          TextField(
              controller: catatan,
              decoration:
                  const InputDecoration(labelText: 'Catatan penutupan')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Tutup Sesi')),
        ],
      ),
    );
    if (ya == true) {
      await _aksi(
          'si_trip_close',
          {
            'session_id': widget.sessionId,
            'kas_fisik_aktual': double.tryParse(kas.text) ?? 0,
            'catatan': catatan.text.trim(),
          },
          sukses: 'Sesi ditutup.');
    }
  }

  /// P10: biaya posted tidak dihapus. Pemilik/Admin menerbitkan dokumen
  /// pembalik; server tetap menjadi penjaga akhir dan menolak sesi CLOSED.
  Future<void> _reversalBiaya(Map<String, dynamic> biaya) async {
    final alasan = TextEditingController();
    final dikonfirmasi = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reversal biaya #${biaya['id']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${biaya['kategori']} — ${biaya['uraian']}',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
              'Biaya tidak dihapus. Sistem menerbitkan dokumen pembalik '
              'negatif dan mengembalikan kas bila metode asal tunai.',
              style: TextStyle(fontSize: 12.5)),
          TextField(
              controller: alasan,
              decoration:
                  const InputDecoration(labelText: 'Alasan reversal (wajib)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              child: const Text('Reversal')),
        ],
      ),
    );
    if (dikonfirmasi != true || alasan.text.trim().isEmpty) return;
    await _aksi(
        'si_expense_reverse',
        {
          'biaya_id': biaya['id'],
          'alasan': alasan.text.trim(),
        },
        sukses: 'Reversal biaya diterbitkan.');
  }

  Future<void> _cetakLaporan() async {
    final d = _d;
    if (d == null) return;
    final rumus = Map<String, dynamic>.from((d['rumus'] as Map?) ?? {});
    final spj = Map<String, dynamic>.from((d['spj'] as Map?) ?? {});
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Text('LAPORAN SESI NOTA SALES',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Sesi: ${d['nomor']}  ·  SPJ: ${spj['nomor']}  ·  Sales: ${spj['salesNama']}'),
        pw.Text('Mulai: ${d['waktuMulai']}  ·  Kembali: ${d['waktuKembali']}'),
        pw.Text('Status: ${d['statusSesi']}'),
        pw.SizedBox(height: 10),
        pw.Text('HASIL BISNIS SESI',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          data: [
            [
              'Total piutang tertagih',
              _fmtRp.format(rumus['totalPiutangTertagih'] ?? 0)
            ],
            ['  - Tunai', _fmtRp.format(rumus['tertagihTunai'] ?? 0)],
            ['  - Non-tunai', _fmtRp.format(rumus['tertagihNonTunai'] ?? 0)],
            ['Total biaya sesi', _fmtRp.format(rumus['totalBiaya'] ?? 0)],
            [
              'Total nilai pembelian',
              _fmtRp.format(rumus['totalNilaiPembelian'] ?? 0)
            ],
            [
              '  - Dibayar/DP saat sesi',
              _fmtRp.format(rumus['pembelianDibayarDp'] ?? 0)
            ],
            [
              '  - Sisa hutang baru',
              _fmtRp.format(rumus['pembelianSisaHutang'] ?? 0)
            ],
            ['HASIL BERSIH SESI', _fmtRp.format(rumus['hasilBersih'] ?? 0)],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('REKONSILIASI KAS FISIK',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          data: [
            ['Uang muka awal', _fmtRp.format(rumus['uangMukaAwal'] ?? 0)],
            [
              '+ Penerimaan piutang tunai',
              _fmtRp.format(rumus['tertagihTunai'] ?? 0)
            ],
            ['+ Penjualan tunai', _fmtRp.format(rumus['penjualanTunai'] ?? 0)],
            ['+ Refund tunai', _fmtRp.format(rumus['refundTunai'] ?? 0)],
            ['- Biaya tunai', _fmtRp.format(rumus['biayaTunai'] ?? 0)],
            [
              '- Pembayaran pembelian tunai',
              _fmtRp.format(rumus['pembayaranPembelianTunai'] ?? 0)
            ],
            [
              '- Setoran ke pemilik',
              _fmtRp.format(rumus['setoranKePemilik'] ?? 0)
            ],
            [
              'KAS FISIK SEHARUSNYA',
              _fmtRp.format(rumus['kasFisikSeharusnya'] ?? 0)
            ],
            if (d['kasFisikAktual'] != null)
              ['Kas fisik aktual', _fmtRp.format(d['kasFisikAktual'] ?? 0)],
            if (d['selisihKas'] != null)
              ['SELISIH KAS', _fmtRp.format(d['selisihKas'] ?? 0)],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('NOTA/INVOICE DIBAWA',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Faktur', 'Customer', 'Saldo Dibawa', 'Tertagih', 'Status'],
          data: [
            for (final n in (spj['nota'] as List? ?? []))
              [
                '${(n as Map)['fakturNomor']}',
                '${n['customerNama']}',
                _fmtRp.format(n['saldoSaatAssign'] ?? 0),
                _fmtRp.format(n['nilaiTertagih'] ?? 0),
                '${n['status']}',
              ]
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('BARANG DIBAWA',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: [
            'Produk',
            'Dimuat',
            'Terjual',
            'Kembali',
            'Rusak',
            'Hilang'
          ],
          data: [
            for (final b in (spj['barang'] as List? ?? []))
              [
                '${(b as Map)['namaProduk']}',
                '${b['qtyDimuat']}',
                '${b['qtyTerjual']}',
                '${b['qtyKembali']}',
                '${b['qtyRusak']}',
                '${b['qtyHilang']}',
              ]
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(children: [
            pw.Text('Sales'),
            pw.SizedBox(height: 36),
            pw.Text('( ${spj['salesNama']} )'),
          ]),
          pw.Column(children: [
            pw.Text('Pemilik/Admin'),
            pw.SizedBox(height: 36),
            pw.Text('( ................ )'),
          ]),
        ]),
      ],
    ));
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(), name: 'laporan-sesi-${d['nomor']}.pdf');
    OutboxIs.kirimAtauAntre('si_print_log_create', {
      'jenis_dokumen': 'laporan_sesi_nota_sales',
      'referensi': '${d['nomor']}',
      'parameter': 'session_id=${widget.sessionId}',
      'perangkat': 'flutter',
      'kode_unik': 'PRN-${DateTime.now().microsecondsSinceEpoch}',
    }).then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final pemilik = !Sesi.instance.isSalesKeliling;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            d == null ? 'Detail Sesi' : '${d['nomor']} (${d['statusSesi']})'),
        actions: [
          IconButton(
              onPressed: d == null ? null : _cetakLaporan,
              tooltip: 'Cetak laporan sesi (PDF)',
              icon: const Icon(Icons.print_outlined)),
        ],
      ),
      body: _error != null
          ? _PanelErrorNs(
              pesan: _error!, detail: detailUntuk(_error), onCoba: _muat)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    _ringkasanRumus(d),
                    const SizedBox(height: 10),
                    if (_proses) const LinearProgressIndicator(),
                    if ('${d['statusSesi']}' == 'ACTIVE')
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: () => _dialogKas(
                                'Penjualan Tunai', 'si_trip_cash_sale'),
                            icon: const Icon(Icons.point_of_sale, size: 18),
                            label: const Text('Jual Tunai')),
                        OutlinedButton.icon(
                            onPressed: _dialogBiaya,
                            icon: const Icon(Icons.receipt_outlined, size: 18),
                            label: const Text('Catat Biaya')),
                        OutlinedButton.icon(
                            onPressed: _dialogPembelian,
                            icon: const Icon(Icons.local_shipping_outlined,
                                size: 18),
                            label: const Text('Kulakan Sesi')),
                        OutlinedButton.icon(
                            onPressed: () => _dialogKas(
                                'Setoran ke Pemilik', 'si_trip_deposit'),
                            icon: const Icon(Icons.savings_outlined, size: 18),
                            label: const Text('Setoran')),
                        ElevatedButton.icon(
                            onPressed: () => _aksi('si_trip_return',
                                {'session_id': widget.sessionId},
                                sukses: 'Sesi ditandai KEMBALI.'),
                            icon: const Icon(Icons.keyboard_return, size: 18),
                            label: const Text('Kembali')),
                      ]),
                    if ('${d['statusSesi']}' == 'RETURNED')
                      ElevatedButton.icon(
                          onPressed: () => _aksi('si_trip_reconcile',
                              {'session_id': widget.sessionId},
                              sukses: 'Masuk tahap rekonsiliasi.'),
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text(
                              'Mulai Rekonsiliasi (barang wajib habis dialokasikan)')),
                    if ('${d['statusSesi']}' == 'RECONCILING' && pemilik)
                      ElevatedButton.icon(
                          onPressed: _dialogTutup,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white),
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text('Tutup Sesi (Approval)')),
                    const SizedBox(height: 12),
                    _bagianNota(d),
                    const SizedBox(height: 12),
                    _bagianBarang(d),
                    const SizedBox(height: 12),
                    _bagianBiayaPembelianKas(d),
                    const SizedBox(height: 30),
                  ]),
                ),
    );
  }

  Widget _ringkasanRumus(Map<String, dynamic> d) {
    final rumus = Map<String, dynamic>.from((d['rumus'] as Map?) ?? {});
    return Wrap(spacing: 10, runSpacing: 10, children: [
      SizedBox(
        width: 220,
        child: AppKpiCard(
            icon: Icons.payments_outlined,
            warna: AppColors.success,
            nilai: _fmtRp.format(rumus['totalPiutangTertagih'] ?? 0),
            label: 'Piutang Tertagih'),
      ),
      SizedBox(
        width: 200,
        child: AppKpiCard(
            icon: Icons.receipt_outlined,
            warna: AppColors.danger,
            nilai: _fmtRp.format(rumus['totalBiaya'] ?? 0),
            label: 'Biaya Sesi'),
      ),
      SizedBox(
        width: 220,
        child: AppKpiCard(
            icon: Icons.trending_up,
            warna: AppColors.info,
            nilai: _fmtRp.format(rumus['hasilBersih'] ?? 0),
            label: 'Hasil Bersih Sesi'),
      ),
      SizedBox(
        width: 220,
        child: AppKpiCard(
            icon: Icons.account_balance_wallet_outlined,
            warna: Colors.teal,
            nilai: _fmtRp.format(rumus['kasFisikSeharusnya'] ?? 0),
            label: 'Kas Fisik Seharusnya'),
      ),
    ]);
  }

  Widget _bagianNota(Map<String, dynamic> d) {
    final spj = Map<String, dynamic>.from((d['spj'] as Map?) ?? {});
    final nota = ((spj['nota'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final aktif = '${d['statusSesi']}' == 'ACTIVE';
    return AppFormSection(
      judul: 'Nota Dibawa (${nota.length})',
      children: [
        for (final n in nota)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${n['fakturNomor']} — ${n['customerNama']}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(
                          'dibawa ${_fmtRp.format(n['saldoSaatAssign'] ?? 0)} · tertagih ${_fmtRp.format(n['nilaiTertagih'] ?? 0)} · ${n['status']}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context))),
                    ]),
              ),
              if (aktif) ...[
                TextButton(
                    onPressed: () => _dialogTagih(n),
                    child: const Text('Tagih')),
                TextButton(
                    onPressed: () => _dialogHasilNota(n),
                    child: const Text('Hasil')),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _bagianBarang(Map<String, dynamic> d) {
    final spj = Map<String, dynamic>.from((d['spj'] as Map?) ?? {});
    final barang = ((spj['barang'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final bolehEdit =
        '${d['statusSesi']}' == 'ACTIVE' || '${d['statusSesi']}' == 'RETURNED';
    return AppFormSection(
      judul: 'Barang Dibawa (${barang.length})',
      children: [
        for (final b in barang)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${b['namaProduk']}',
                style: const TextStyle(fontSize: 12.5)),
            subtitle: Text(
                'dimuat ${b['qtyDimuat']} · terjual ${b['qtyTerjual']} · kembali ${b['qtyKembali']} · rusak ${b['qtyRusak']} · hilang ${b['qtyHilang']} · sisa dibawa ${b['masihDibawa']}',
                style: const TextStyle(fontSize: 11)),
            trailing: bolehEdit
                ? IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _dialogBarang(b))
                : null,
          ),
      ],
    );
  }

  Widget _bagianBiayaPembelianKas(Map<String, dynamic> d) {
    final biaya = ((d['biaya'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final beli = ((d['pembelian'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final kas = ((d['kas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final bolehReversal =
        !Sesi.instance.isSalesKeliling && '${d['statusSesi']}' != 'CLOSED';
    return Column(children: [
      AppFormSection(judul: 'Biaya (${biaya.length})', children: [
        for (final b in biaya)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                  child: Text(
                      '${b['kategori']} — ${b['uraian']}'
                      '${'${b['statusDok']}' == 'DIBATALKAN' ? ' (DIBATALKAN)' : ''}'
                      '${'${b['statusDok']}' == 'REVERSAL' ? ' (REVERSAL)' : ''}',
                      style: const TextStyle(fontSize: 12))),
              Text(_fmtRp.format(b['nilai'] ?? 0),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              if (bolehReversal && '${b['statusDok']}' == 'AKTIF')
                IconButton(
                    icon: const Icon(Icons.undo_outlined, size: 18),
                    color: AppColors.danger,
                    tooltip: 'Reversal biaya',
                    onPressed: () => _reversalBiaya(b)),
            ]),
          ),
      ]),
      const SizedBox(height: 10),
      AppFormSection(judul: 'Pembelian Sesi (${beli.length})', children: [
        for (final b in beli)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                  child: Text(
                      '${b['supplierNama'] ?? ''} ${b['tujuanStok']} — total ${_fmtRp.format(b['totalFaktur'] ?? 0)}',
                      style: const TextStyle(fontSize: 12))),
              Text(
                  'bayar ${_fmtRp.format(b['dibayarSesi'] ?? 0)} · sisa ${_fmtRp.format(b['sisaHutang'] ?? 0)}',
                  style: const TextStyle(fontSize: 11.5)),
            ]),
          ),
      ]),
      const SizedBox(height: 10),
      AppFormSection(judul: 'Ledger Kas (${kas.length})', children: [
        for (final k in kas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                  child: Text('${k['jenis']} ${k['keterangan']}',
                      style: const TextStyle(fontSize: 11.5))),
              Text(_fmtRp.format(k['nominal'] ?? 0),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ((k['nominal'] as num?) ?? 0) < 0
                          ? AppColors.danger
                          : AppColors.success)),
            ]),
          ),
      ]),
    ]);
  }
}

class _PanelErrorNs extends StatelessWidget {
  final String pesan;
  final VoidCallback onCoba;
  final String? detail;
  const _PanelErrorNs({required this.pesan, required this.onCoba, this.detail});

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
