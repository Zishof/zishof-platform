import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'pengadaan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';
import '../services/kompresi_gambar.dart';

/// Layar "Terima Tagihan Vendor" -- tahap 4 modul Pengadaan POS.
///
/// Pada model pengadaan yang sudah ada, menerima tagihan BUKAN dokumen tersendiri
/// melainkan tahap di atas BAST: nomor dan tanggal faktur vendor dicapkan pada
/// penerimaan yang sudah disetujui, lalu menjadi dasar pembayaran vendor.
/// Karena itu layar ini hanya menampilkan BAST yang sudah disetujui -- barang yang
/// belum diakui diterima tidak boleh menimbulkan kewajiban bayar.
class PengadaanTagihanScreen extends StatefulWidget {
  const PengadaanTagihanScreen({super.key});

  @override
  State<PengadaanTagihanScreen> createState() => _PengadaanTagihanScreenState();
}

class _PengadaanTagihanScreenState extends State<PengadaanTagihanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabUtama;
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];
  String _cari = '';
  String _status = '';
  int _halaman = 1;
  int _total = 0;
  static const _pageSize = 15;

  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _versiPerubahan = 0;

  /// Lampiran yang sedang diunduh; dipakai menandai keripiknya saja,
  /// sehingga baris lain tetap dapat diklik selama unduhan berjalan.
  int? _unduhLampiranId;

  @override
  void initState() {
    super.initState();
    _tabUtama = TabController(length: 2, vsync: this);
    _muat();
  }

  @override
  void dispose() {
    _tabUtama.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'pengadaan_tagihan_daftar',
        {
          if (_cari.isNotEmpty) 'cari': _cari,
          if (_status.isNotEmpty) 'status': _status,
          'page': _halaman,
          'pageSize': _pageSize,
        },
        'master:pengadaan_tagihan:${_status}_${_cari}_$_halaman',
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat =
                  '${res['description'] ?? 'Gagal memuat daftar tagihan.'}';
              _memuat = false;
            });
            return;
          }
          final data = ((res['data'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final dariServer = res['dariServer'] == true;
          setStateIfMounted(() {
            _daftar = data;
            _total = dariServer
                ? (res['total'] as num?)?.toInt() ?? data.length
                : data.length;
            _idBaru = dariServer
                ? Set<String>.from(res['idBaru'] as Set? ?? const <String>{})
                : {};
            _idBerubah = dariServer
                ? Set<String>.from(res['idBerubah'] as Set? ?? const <String>{})
                : {};
            if (dariServer && (_idBaru.isNotEmpty || _idBerubah.isNotEmpty)) {
              _versiPerubahan++;
            }
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  /// Kirim perubahan tagihan secara LOCAL-FIRST: ditulis ke antrean perangkat
  /// lebih dulu, baru diupayakan sampai ke server. Petugas yang menerima faktur
  /// di lapangan tanpa sinyal tidak perlu menunggu.
  Future<void> _kirim(String aksi, Map<String, dynamic> body) async {
    try {
      final r = await prosesSimpanMaster(
        context,
        aksi: aksi,
        body: body,
        kunci: '$aksi:${body['id']}',
        cacheKey: 'master:pengadaan_tagihan',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['offline'] == true
              ? 'Tersimpan di perangkat, akan dikirim otomatis.'
              : 'Tersimpan.')));
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  /// Nomor DAN tanggal faktur wajib -- server menolak bila salah satunya kosong,
  /// jadi dialog ini meminta keduanya sekaligus.
  Future<void> _terimaTagihan(Map<String, dynamic> row) async {
    final nomor = TextEditingController(text: '${row['kodeTagihan'] ?? ''}');
    final tanggal =
        TextEditingController(text: '${row['tanggalTagihan'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> pilihTanggal() async {
          DateTime awal = DateTime.now();
          final bagian = tanggal.text.split('-');
          if (bagian.length == 3) {
            final dd = int.tryParse(bagian[0]);
            final mm = int.tryParse(bagian[1]);
            final yy = int.tryParse(bagian[2]);
            if (dd != null && mm != null && yy != null) {
              awal = DateTime(yy, mm, dd);
            }
          }
          final pilih = await showDatePicker(
            context: c,
            initialDate: awal,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (pilih == null) return;
          // dd-MM-yyyy adalah pola yang dibaca server dan layar ZKoss.
          setLocal(() => tanggal.text = DateFormat('dd-MM-yyyy').format(pilih));
        }

        return AlertDialog(
          title: Text('Terima Tagihan · ${row['kode'] ?? ''}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '${row['penyedia'] ?? '-'}  ·  ${_fmtRp.format(row['nilai'] ?? 0)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nomor,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Nomor tagihan / faktur vendor *',
                    helperText: 'Sesuai dokumen tagihan yang diterima'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tanggal,
                readOnly: true,
                onTap: pilihTanggal,
                decoration: const InputDecoration(
                    labelText: 'Tanggal tagihan *',
                    suffixIcon: Icon(Icons.event, size: 18)),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _PapanLampiran(bastId: (row['id'] as num).toInt()),
            ])),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Terima Tagihan')),
          ],
        );
      }),
    );
    final kode = nomor.text.trim();
    final tgl = tanggal.text.trim();
    nomor.dispose();
    tanggal.dispose();
    if (ok != true || !mounted) return;
    if (kode.isEmpty || tgl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nomor dan tanggal tagihan wajib diisi.')));
      return;
    }
    await _kirim('pengadaan_tagihan_terima',
        {'id': row['id'], 'kodeTagihan': kode, 'tanggalTagihan': tgl});
  }

  Future<void> _batalTagihan(Map<String, dynamic> row) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Batalkan Tagihan'),
        content: Text('Batalkan tagihan ${row['kodeTagihan']} pada '
            '${row['kode']}? Nomor dan tanggal fakturnya akan dikosongkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Batalkan')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    await _kirim('pengadaan_tagihan_batal', {'id': row['id']});
  }

  /// Dua tab pada setiap menu Pengadaan: "Dasbor" (ringkasan angka) dan
  /// "Tagihan" (daftar + CRUD). Susunannya sengaja disamakan di keenam
  /// menu supaya berpindah tahap tidak menuntut penyesuaian kebiasaan.
  Widget _bungkusTab(Widget isiData) {
    return Column(children: [
      TabBar(
        controller: _tabUtama,
        tabs: const [
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
          Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Tagihan'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabUtama,
          children: [
            const PengadaanDasborTab(tahap: 'tagihan'),
            isiData,
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 9999);
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanTagihan,
      judul: 'Terima Tagihan Vendor',
      subjudul: 'Catat faktur vendor atas barang yang sudah diterima',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      body: _bungkusTab(Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                    labelText: 'Cari kode BAST / keterangan / no. faktur',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onSubmitted: (v) {
                  setStateIfMounted(() {
                    _cari = v.trim();
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                value: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Status tagihan', isDense: true),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Semua')),
                  DropdownMenuItem(
                      value: 'BELUM', child: Text('Belum ditagih')),
                  DropdownMenuItem(
                      value: 'SUDAH', child: Text('Sudah ditagih')),
                ],
                onChanged: (v) {
                  setStateIfMounted(() {
                    _status = v ?? '';
                    _halaman = 1;
                  });
                  _muat();
                },
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BannerPerubahanServer(
            key: ValueKey('perubahan:$_versiPerubahan'),
            baru: _idBaru.length,
            berubah: _idBerubah.length,
            dihapus: 0,
          ),
        ),
        Expanded(child: _isiTabel(totalHalaman)),
      ])),
    );
  }

  Widget _isiTabel(int totalHalaman) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_galat!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    if (_daftar.isEmpty) {
      return const Center(
        child: Text(
            'Belum ada penerimaan barang yang siap ditagihkan.\n'
            'Setujui dulu BAST-nya di menu Penerimaan Barang.',
            textAlign: TextAlign.center),
      );
    }
    return AppDataTable(
      minWidth: 1080,
      emptyText: 'Tidak ada tagihan pada filter ini.',
      columns: const [
        AppTableColumn('BAST', flex: 2),
        AppTableColumn('Tanggal', flex: 2),
        AppTableColumn('Penyedia', flex: 3),
        AppTableColumn('PO', flex: 2),
        AppTableColumn('Termin ke', flex: 2),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('Faktur', flex: 3),
        AppTableColumn('Barang', flex: 2, align: TextAlign.center),
        AppTableColumn('Lampiran', flex: 3),
        AppTableColumn('Aksi', width: 64),
      ],
      rows: _daftar.map(_baris).toList(),
      pagination: _total > _pageSize
          ? AppTablePagination(
              halaman: _halaman,
              totalHalaman: totalHalaman,
              totalData: _total,
              labelData: 'tagihan',
              onSebelumnya: _halaman > 1
                  ? () {
                      setStateIfMounted(() => _halaman--);
                      _muat();
                    }
                  : null,
              onBerikutnya: _halaman < totalHalaman
                  ? () {
                      setStateIfMounted(() => _halaman++);
                      _muat();
                    }
                  : null,
            )
          : null,
    );
  }

  /// Satu berkas lampiran sebagai keripik yang dapat diklik untuk mengunduh.
  Widget _keripikLampiran(Map<String, dynamic> item) {
    final id = (item['lampiran_id'] as num?)?.toInt();
    final nama = '${item['nama'] ?? 'Berkas'}';
    final namaFile = '${item['namaFile'] ?? ''}'.trim();
    final sedang = id != null && _unduhLampiranId == id;
    // Hanya satu unduhan pada satu waktu: dialog simpan bawaan sistem bersifat
    // modal, jadi dua unduhan serentak akan saling menutupi dialognya.
    final aktif = id != null && _unduhLampiranId == null;
    return Tooltip(
      message: namaFile.isEmpty ? 'Unduh $nama' : 'Unduh $namaFile',
      child: InkWell(
        onTap: aktif ? () => _unduhLampiran(item) : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            sedang
                ? const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.6))
                : Icon(Icons.download_outlined,
                    size: 12, color: AppColors.primary),
            const SizedBox(width: 3),
            Text(nama,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
        ),
      ),
    );
  }

  /// Mengunduh satu lampiran langsung dari barisnya, tanpa membuka dialog ubah.
  Future<void> _unduhLampiran(Map<String, dynamic> item) async {
    final id = (item['lampiran_id'] as num?)?.toInt();
    if (id == null) return;
    setStateIfMounted(() => _unduhLampiranId = id);
    await _simpanLampiran(context, item);
    setStateIfMounted(() => _unduhLampiranId = null);
  }

  AppTableRowData _baris(Map<String, dynamic> row) {
    final sudah = '${row['status'] ?? 'BELUM'}' == 'SUDAH';
    final warna = sudah ? const Color(0xFF2E7D32) : const Color(0xFFB8860B);
    return AppTableRowData(cells: [
      AppTableCell(
        flex: 2,
        child: KilauBaris(
          kunci: '${row['id'] ?? ''}',
          idBaru: _idBaru,
          idBerubah: _idBerubah,
          child: Text('${row['kode'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      AppTableCell.text('${row['tanggal'] ?? '-'}', flex: 2),
      AppTableCell.text('${row['penyedia'] ?? '-'}', flex: 3),
      AppTableCell.text('${row['po'] ?? '-'}', flex: 2),
      /* Pesanan bertermin ditagih per termin, jadi beberapa baris dapat berasal
       * dari pesanan yang sama dan hanya kolom inilah yang membedakannya. */
      AppTableCell.text(
          '${row['termin'] ?? ''}'.isEmpty ? '-' : '${row['termin']}',
          flex: 2),
      AppTableCell.text(_fmtRp.format(row['nilai'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell(
        flex: 3,
        child: sudah
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text('${row['kodeTagihan']}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: warna)),
                    Text('${row['tanggalTagihan']}',
                        style: const TextStyle(fontSize: 10)),
                  ])
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: warna.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('BELUM DITAGIH',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: warna)),
              ),
      ),
      /* Status BARANG, bukan status faktur. Kolom Faktur di sebelah kiri sudah
       * menyatakan apakah tagihannya sudah masuk; yang belum pernah terlihat di
       * layar ini adalah apakah barangnya sudah benar-benar diterima. Keduanya
       * bisa berbeda: faktur kerap datang sebelum penerimaan disetujui. */
      AppTableCell(
        flex: 2,
        align: TextAlign.center,
        child: Builder(builder: (_) {
          final diterima = '${row['statusBarang'] ?? ''}' == 'DISETUJUI';
          final w = diterima ? AppColors.success : AppColors.warning;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: w.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(6)),
            child: Text(diterima ? 'Diterima' : 'Belum diterima',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: w)),
          );
        }),
      ),
      /* Berkas yang SUDAH diunggah, disebut namanya. Sebelumnya isi papan
       * lampiran hanya terlihat setelah dialognya dibuka satu per satu,
       * sehingga tidak ada cara menyapu daftar untuk mencari yang kurang.
       * Kosong bila penyimpanan berkas sedang tidak terbaca -- server memang
       * membiarkan kolom ini kosong daripada mematikan seluruh daftar. */
      AppTableCell(
        flex: 3,
        child: Builder(builder: (_) {
          final daftar =
              (row['lampiran'] as List?)?.cast<Object?>() ?? const [];
          final rinci = (row['lampiranRinci'] as List?)
                  ?.whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList() ??
              const <Map<String, dynamic>>[];
          if (daftar.isEmpty && rinci.isEmpty) {
            return Text('Belum ada',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context)));
          }
          final wajibKurang = row['lampiranWajibLengkap'] == false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tiap berkas dapat diunduh di tempat. Server versi lama yang belum
              // mengirim lampiranRinci tetap menampilkan daftar namanya saja.
              if (rinci.isEmpty)
                Text(daftar.join(', '),
                    style: const TextStyle(fontSize: 11), maxLines: 2)
              else
                Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: rinci.map(_keripikLampiran).toList()),
              Text(
                  '${row['lampiranTerisi'] ?? daftar.length}'
                  '/${row['lampiranTotal'] ?? 5} berkas'
                  '${wajibKurang ? ' · Invoice belum ada' : ''}',
                  style: TextStyle(
                      fontSize: 10,
                      color: wajibKurang
                          ? AppColors.danger
                          : AppColors.textSecondaryOf(context))),
            ],
          );
        }),
      ),
      AppTableCell(
        width: 64,
        child: AksiBarisMenu(aksi: [
          // Cetak dokumen: pratinjau lebih dulu, mencetak menyusul. Templatnya sama
          // dengan versi ZKoss sehingga hasil cetaknya identik.
          AksiBaris(
              ikon: Icons.print_outlined,
              label: 'Cetak / pratinjau',
              onTap: () => cetakDokumenPengadaan(context,
                  tahap: 'tagihan',
                  id: (row['id'] as num).toInt(),
                  kode: '${row['kode'] ?? ''}')),
          AksiBaris(
              ikon: sudah ? Icons.edit_note : Icons.receipt_long,
              label: sudah ? 'Ubah data faktur' : 'Terima tagihan',
              onTap: () => _terimaTagihan(row)),
          AksiBaris(
              ikon: Icons.undo,
              label: 'Batalkan tagihan',
              onTap: sudah ? () => _batalTagihan(row) : null),
        ]),
      ),
    ]);
  }
}

/// Papan lampiran dokumen tagihan pada satu BAST.
///
/// Berkasnya disimpan di tabel `LampiranLain` yang SAMA dengan versi ZKoss, dengan
/// `ref` = id BAST dan `jenis` = nama slot. Karena itu berkas yang diunggah dari POS
/// langsung terbaca di ZKoss, dan sebaliknya.
///
/// Slot yang ditandai wajib -- Invoice -- harus terisi sebelum tagihan dapat
/// diterima. Pagarnya ada di server, jadi Desktop, Android, dan JSP berlaku sama;
/// papan ini hanya memberi tahu lebih awal.
/// Nama berkas simpanan: pakai nama asli dari server bila ada.
///
/// Bila kosong, namanya dibentuk dari nama slot ditambah akhiran yang diturunkan
/// dari tipe MIME -- tanpa akhiran, berkasnya tidak dapat dibuka dengan klik
/// ganda di Windows.
String _namaBerkasLampiran(Map<String, dynamic> item, Map<String, dynamic> r) {
  final dariServer = '${r['namaFile'] ?? item['namaFile'] ?? ''}'.trim();
  if (dariServer.isNotEmpty) return dariServer;
  final tipe = '${r['tipe'] ?? item['tipe'] ?? ''}';
  final akhiran =
      tipe.contains('/') ? tipe.split('/').last.split(';').first.trim() : 'bin';
  final slot = '${item['nama'] ?? 'lampiran'}'.replaceAll(' ', '_');
  return '$slot.${akhiran.isEmpty ? 'bin' : akhiran}';
}

/// Mengunduh satu lampiran lalu menyimpannya lewat dialog simpan bawaan sistem.
///
/// Dipakai dua tempat -- keripik pada kolom Lampiran di daftar, dan tombol unduh
/// di papan lampiran -- sehingga aturan penamaan berkas dan penjaga content://
/// hanya punya satu salinan. Penanda sibuk sengaja TIDAK diurus di sini; tiap
/// pemanggil menandai bagiannya sendiri.
Future<void> _simpanLampiran(
    BuildContext context, Map<String, dynamic> item) async {
  final id = (item['lampiran_id'] as num?)?.toInt();
  if (id == null) return;
  try {
    final r = await ApiClient.instance
        .aksi('pengadaan_lampiran_unduh', {'lampiran_id': id});
    final b64 = '${r['fileBase64'] ?? ''}';
    if (b64.isEmpty) {
      throw 'Isi berkas tidak terbaca dari penyimpanan.';
    }
    final bytes = base64Decode(b64);
    final namaFile = _namaBerkasLampiran(item, r);
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan ${item['nama'] ?? 'lampiran'}',
        fileName: namaFile,
        bytes: bytes);
    if (path == null) return;
    // Jalur content:// milik Android SAF sudah ditulisi oleh saveFile dan BUKAN
    // jalur berkas biasa; menulisinya lagi lewat File() akan gagal.
    if (!path.startsWith('content://')) {
      await File(path).writeAsBytes(bytes);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lampiran disimpan: $namaFile')));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengunduh lampiran: $e')));
    }
  }
}

class _PapanLampiran extends StatefulWidget {
  final int bastId;
  const _PapanLampiran({required this.bastId});

  @override
  State<_PapanLampiran> createState() => _PapanLampiranState();
}

class _PapanLampiranState extends State<_PapanLampiran> {
  List<Map<String, dynamic>> _slot = [];
  bool _memuat = true;
  String? _sibuk;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final r = await ApiClient.instance
          .aksi('pengadaan_lampiran_daftar', {'bast_id': widget.bastId});
      _slot = ((r['data'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _slot = [];
    }
    setStateIfMounted(() => _memuat = false);
  }

  Future<void> _unggah(Map<String, dynamic> slot) async {
    final harusGambar = slot['harusGambar'] == true;
    final hasil = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: harusGambar
          ? const ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp']
          : const ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'pdf'],
      withData: true,
    );
    if (hasil == null || hasil.files.isEmpty) return;
    final berkas = hasil.files.single;
    final bytesAsal = berkas.bytes;
    if (bytesAsal == null || !mounted) return;

    // Gambar dikecilkan ke bawah 500 KB SEBELUM dikirim; server tidak
    // mengompresi apa pun. Slot ber-`harusGambar` menolak berkas yang bukan
    // gambar -- diperiksa dari ISI berkasnya, sebab penyaring ekstensi
    // FilePicker hanya melihat namanya.
    //
    // Dijalankan lewat compute(): decode+encode foto kamera resolusi tinggi
    // berat dan akan menjank UI bila berjalan di isolate utama.
    Uint8List bytes;
    try {
      bytes = await compute(
          harusGambar ? siapkanLampiranGambar : siapkanLampiranCampuran,
          bytesAsal);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error));
      return;
    }
    if (!mounted) return;

    setStateIfMounted(() => _sibuk = '${slot['kunci']}');
    try {
      final r = await ApiClient.instance.aksi('pengadaan_lampiran_unggah', {
        'bast_id': widget.bastId,
        'kunci': slot['kunci'],
        'nama_file': berkas.name,
        'file_base64': base64Encode(bytes),
      });
      if (!mounted) return;
      if (r['status'] != '00' && r['status'] != 'success') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${r['description'] ?? 'Gagal mengunggah lampiran.'}'),
            backgroundColor: Theme.of(context).colorScheme.error));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunggah: $e')));
      }
    }
    setStateIfMounted(() => _sibuk = null);
    await _muat();
  }

  Future<void> _hapus(Map<String, dynamic> slot) async {
    setStateIfMounted(() => _sibuk = '${slot['kunci']}');
    try {
      // Local-first: dicatat di antrean lokal dulu, baru dikirim. Penghapusan
      // lampiran tidak membawa berkas sehingga ringan diantre; hanya UNGGAH
      // yang tetap butuh sambungan (lihat catatan di _unggah).
      await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_lampiran_hapus',
        body: {'lampiran_id': slot['lampiran_id']},
        kunci: 'pengadaan_lampiran_hapus:${slot['lampiran_id']}',
      );
    } catch (_) {}
    setStateIfMounted(() => _sibuk = null);
    await _muat();
  }

  /// Menyimpan berkas slot ini ke perangkat, tanpa pratinjau lebih dulu.
  ///
  /// Berbeda dengan [_lihat] yang hanya sanggup menampilkan gambar, tombol ini
  /// melayani semua jenis berkas -- faktur pajak PDF pun ikut terlayani.
  Future<void> _unduh(Map<String, dynamic> slot) async {
    setStateIfMounted(() => _sibuk = '${slot['kunci']}');
    await _simpanLampiran(context, slot);
    setStateIfMounted(() => _sibuk = null);
  }

  Future<void> _lihat(Map<String, dynamic> slot) async {
    setStateIfMounted(() => _sibuk = '${slot['kunci']}');
    Map<String, dynamic>? r;
    try {
      r = await ApiClient.instance.aksi(
          'pengadaan_lampiran_unduh', {'lampiran_id': slot['lampiran_id']});
    } catch (e) {
      r = null;
    }
    setStateIfMounted(() => _sibuk = null);
    if (!mounted || r == null) return;
    final b64 = '${r['fileBase64'] ?? ''}';
    final tipe = '${r['tipe'] ?? ''}';
    if (b64.isEmpty) return;
    if (!tipe.startsWith('image/')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${r['namaFile'] ?? 'Berkas'} bertipe $tipe -- '
              'pratinjau hanya tersedia untuk gambar. Pakai tombol '
              'unduh untuk menyimpannya.')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${slot['nama']}'),
        content: SingleChildScrollView(
            child: Image.memory(base64Decode(b64), fit: BoxFit.contain)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Lampiran Dokumen',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const Text(
            'Invoice wajib diunggah dan harus berupa gambar. Lampiran lain '
            'bersifat pelengkap.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
        const SizedBox(height: 6),
        ..._slot.map(_barisSlot),
      ],
    );
  }

  Widget _barisSlot(Map<String, dynamic> slot) {
    final ada = slot['ada'] == true;
    final wajib = slot['wajib'] == true;
    final sibuk = _sibuk == '${slot['kunci']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(ada ? Icons.check_circle : Icons.upload_file,
            size: 16,
            color: ada ? Colors.green : (wajib ? Colors.red : Colors.grey)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${slot['nama']}${wajib ? ' *' : ''}',
                  style: const TextStyle(fontSize: 12)),
              Text(
                  ada
                      ? '${slot['namaFile']}'
                      : (wajib ? 'belum diunggah' : 'opsional'),
                  style: TextStyle(
                      fontSize: 10,
                      color: ada
                          ? Colors.grey
                          : (wajib ? Colors.red : Colors.grey))),
            ],
          ),
        ),
        if (sibuk)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          if (ada)
            IconButton(
                tooltip: 'Lihat',
                iconSize: 18,
                onPressed: () => _lihat(slot),
                icon: const Icon(Icons.visibility)),
          if (ada)
            IconButton(
                tooltip: 'Unduh berkas',
                iconSize: 18,
                onPressed: () => _unduh(slot),
                icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: ada ? 'Ganti berkas' : 'Unggah',
              iconSize: 18,
              onPressed: () => _unggah(slot),
              icon: const Icon(Icons.file_upload)),
          if (ada)
            IconButton(
                tooltip: 'Hapus',
                iconSize: 18,
                onPressed: () => _hapus(slot),
                icon: const Icon(Icons.delete_outline)),
        ],
      ]),
    );
  }
}
