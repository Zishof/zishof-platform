import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/safe_state.dart';
import 'cetak_util.dart';

final _fmtRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtQty = NumberFormat('#,##0.##', 'id_ID');
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Laporan Opname — layar legacy 09; cetaknya layar legacy 10.</h3>
///
/// KOREKSI ATAS VERSI PERTAMA LAYAR INI
/// Versi pertama menduga 09 = daftar sesi dan 10 = rinciannya. Keliru, dan baru
/// terlihat sesudah tangkapan layar aplikasi lamanya benar-benar dibuka:
///   * layar 09 adalah daftar DATAR — satu baris per produk per tanggal,
///     berkolom TGL.OPNAME, #KODE, NAMA BARANG, SAT., STOK KOMP., STOK FISIK,
///     SELISIH, HRG.POKOK, TOTAL HARGA, dengan SATU total di kanan bawah;
///   * layar 10 adalah HASIL CETAK layar 09, bukan rincian per dokumen.
/// Karena itu tampilan bawaan di sini datar per produk, dan tombol Cetak PDF
/// menghasilkan padanan layar 10. Tampilan "Per Sesi" tetap ada sebagai
/// tambahan — berguna, tetapi menjawab pertanyaan yang tidak ditanyakan layar
/// lamanya, jadi ia bukan bawaan.
///
/// Paritas fungsional tidak dapat disimpulkan dari NAMA layar lama: "Laporan
/// Opname" dan "Mencetak Laporan Opname" terdengar seperti daftar dan
/// rinciannya; keduanya ternyata satu laporan dan cetaknya.
///
/// MENGAPA LAYAR INI ADA, PADAHAL SUDAH ADA LAYAR STOK OPNAME
/// `StokOpnameScreen` adalah layar OPERASI opname POS: ia menghitung, memindai,
/// dan mengunggah — dan aksinya (`so_*`) membaca lewat entitas Hibernate yang
/// schema-nya dipatok `@Table(schema=...)`. Entitas tidak dapat melihat schema
/// tenant, sehingga 461 dokumen opname tenant terbaca NOL di sana. Layar 09-10
/// bukan layar operasi melainkan LAPORAN, dan ia butuh jalur tenant.
///
/// MENGAPA TIDAK MEMAKAI MasterOffline
/// Layar daftar lain membaca cache dulu lewat `MasterOffline.daftarCacheDulu`.
/// Di sini tidak: memakainya untuk baca murni ikut menyalakan antrean tulisnya
/// beserta timer periodiknya, dan uji widget jatuh karena timer yang menggantung.
/// Laporan ini hanya membaca, jadi ia memanggil `ApiClient` langsung.
///
/// LEBIH DAN KURANG DITAMPILKAN TERPISAH
/// Sesi yang kelebihan 50 pada satu produk dan kekurangan 50 pada produk lain
/// berselisih bersih NOL — padahal justru sesi itu yang paling perlu diperiksa.
/// Menampilkan bersihnya saja menyembunyikan tepat kasus yang dicari laporan ini.
class LaporanOpnameScreen extends StatefulWidget {
  const LaporanOpnameScreen({super.key});

  @override
  State<LaporanOpnameScreen> createState() => _LaporanOpnameScreenState();
}

class _LaporanOpnameScreenState extends State<LaporanOpnameScreen>
    with JejakGalat {
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  bool _hanyaBerselisih = false;
  /// 'produk' = bentuk layar legacy 09 (bawaan); 'sesi' = ringkasan per dokumen.
  String _mode = 'produk';
  // Opname jarang harian. Jendela 30 hari seperti layar persediaan akan tampak
  // KOSONG pada sebagian besar data sungguhan, dan layar kosong terbaca sebagai
  // "tidak ada data" padahal hanya jendelanya yang terlalu sempit.
  DateTime _dari = DateTime.now().subtract(const Duration(days: 365));
  DateTime _sampai = DateTime.now();

  double _ringkasLebih = 0, _ringkasKurang = 0, _ringkasNilai = 0;
  int _ringkasProduk = 0;
  /// Benar bila angka ringkasan mencakup SELURUH rentang, bukan halaman aktif.
  /// Dibedakan karena keduanya terlihat sama di layar dan hanya salah satunya
  /// boleh disebut "total".
  bool _ringkasSeluruhRentang = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Map<String, dynamic> get _params => {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'dari': _fmtTgl.format(_dari),
        'sampai': _fmtTgl.format(_sampai),
        'hanya_berselisih': _hanyaBerselisih,
        'mode': _mode,
      };

  bool get _perProduk => _mode == 'produk';

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('si_stock_count_list', {
        ..._params,
        'page': _halaman,
        'page_size': _pageSize,
      });
      final baris = ((hasil['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .toList();
      setStateIfMounted(() {
        _data = baris;
        _total = (hasil['total'] as num?)?.toInt() ?? baris.length;
        // Mode produk mengirim total SELURUH rentang (tanpa akhiran "Halaman");
        // mode sesi hanya total halaman. Membaca kunci yang salah akan
        // menampilkan angka yang benar-benar ada tetapi berarti lain.
        _ringkasSeluruhRentang = _perProduk;
        if (_perProduk) {
          _ringkasProduk = _total;
          _ringkasLebih = (hasil['totalLebih'] as num?)?.toDouble() ?? 0;
          _ringkasKurang = (hasil['totalKurang'] as num?)?.toDouble() ?? 0;
          _ringkasNilai = (hasil['nilaiSelisih'] as num?)?.toDouble() ?? 0;
        } else {
          _ringkasProduk = (hasil['jumlahProdukHalaman'] as num?)?.toInt() ?? 0;
          _ringkasLebih = (hasil['totalLebihHalaman'] as num?)?.toDouble() ?? 0;
          _ringkasKurang = (hasil['totalKurangHalaman'] as num?)?.toDouble() ?? 0;
          _ringkasNilai = (hasil['nilaiSelisihHalaman'] as num?)?.toDouble() ?? 0;
        }
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  Future<void> _pilihTanggal({required bool dari}) async {
    final awal = dari ? _dari : _sampai;
    final hasil = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (hasil == null) return;
    setStateIfMounted(() {
      if (dari) {
        _dari = hasil;
      } else {
        _sampai = hasil;
      }
    });
    _halaman = 1;
    await _muat();
  }

  /// Seluruh sesi sesuai filter aktif (bukan halaman aktif saja), batas 1000
  /// baris. Bila terpotong, pemanggilnya memberi tahu — tanpa pemotongan diam.
  Future<(List<Map<String, dynamic>>, bool)> _ambilSemua() async {
    final semua = <Map<String, dynamic>>[];
    var terpotong = false;
    for (var p = 1; p <= 10; p++) {
      final hasil = await ApiClient.instance.aksi('si_stock_count_list', {
        ..._params,
        'page': p,
        'page_size': 100,
      });
      final baris = ((hasil['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .toList();
      semua.addAll(baris);
      final total = (hasil['total'] as num?)?.toInt() ?? semua.length;
      if (semua.length >= total) break;
      if (p == 10 && semua.length < total) terpotong = true;
    }
    return (semua, terpotong);
  }

  /// Kolom cetak mode produk = kolom layar legacy 09, urutan sama. Cetakannya
  /// dengan begitu menjadi padanan layar legacy 10.
  static const _headerProduk = [
    'Tgl. Opname',
    '#Kode',
    'Nama Barang',
    'Sat.',
    'Stok Komp.',
    'Stok Fisik',
    'Selisih',
    'Hrg. Pokok',
    'Total Harga',
  ];
  static const _headerSesi = [
    'Nomor',
    'Tanggal',
    'Gudang',
    'Status',
    'Jml Produk',
    'Lebih',
    'Kurang',
    'Selisih Bersih',
    'Nilai Selisih',
  ];

  List<String> get _headerCetak => _perProduk ? _headerProduk : _headerSesi;

  List<List<String>> _barisCetak(List<Map<String, dynamic>> data) => _perProduk
      ? data
          .map((r) => [
                '${r['tanggal'] ?? ''}',
                '${r['kode'] ?? ''}',
                '${r['nama'] ?? ''}',
                '${r['satuan'] ?? ''}',
                _fmtQty.format((r['stokSistem'] as num?) ?? 0),
                _fmtQty.format((r['stokFisik'] as num?) ?? 0),
                _fmtQty.format((r['selisih'] as num?) ?? 0),
                _fmtRp.format((r['harga'] as num?) ?? 0),
                _fmtRp.format((r['nilai'] as num?) ?? 0),
              ])
          .toList()
      : data
          .map((r) => [
                '${r['nomor'] ?? ''}',
                '${r['tanggal'] ?? ''}',
                '${r['gudang'] ?? ''}',
                '${r['status'] ?? ''}',
                _fmtQty.format((r['jumlahProduk'] as num?) ?? 0),
                _fmtQty.format((r['totalLebih'] as num?) ?? 0),
                _fmtQty.format((r['totalKurang'] as num?) ?? 0),
                _fmtQty.format((r['selisihBersih'] as num?) ?? 0),
                _fmtRp.format((r['nilaiSelisih'] as num?) ?? 0),
              ])
          .toList();

  Future<void> _cetakPdf() async {
    try {
      final (data, terpotong) = await _ambilSemua();
      if (terpotong && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Data melebihi 1000 baris — cetakan terpotong.')));
      }
      if (!mounted) return;
      await CetakUtilIs.cetakPdfTabel(
        judul: 'Laporan Opname',
        parameter: '${_fmtTgl.format(_dari)} s.d. ${_fmtTgl.format(_sampai)}'
            '${_hanyaBerselisih ? ' · hanya yang berselisih' : ''}'
            '${_kataKunci.isEmpty ? '' : ' · cari "$_kataKunci"'}',
        headers: _headerCetak,
        rows: _barisCetak(data),
        namaFile: 'laporan-opname-${_fmtTgl.format(_sampai)}.pdf',
        // Bobot mengikuti isi sebenarnya: tanggal dan kode berlebar tetap,
        // nama barang mengambil sisanya. Tanpa ini kode produk terbelah dua
        // baris dan cetakan tidak dapat diadu baris demi baris dengan cetakan
        // aplikasi lama.
        lebarKolom: _perProduk
            ? const {0: 1.8, 1: 1.5, 2: 3.0, 3: 1.3, 4: 1.3, 5: 1.3, 6: 1.3, 7: 2.3, 8: 2.4}
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal cetak: $e')));
      }
    }
  }

  Future<void> _eksporExcel() async {
    try {
      final (data, terpotong) = await _ambilSemua();
      if (terpotong && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Data melebihi 1000 baris — ekspor terpotong.')));
      }
      if (!mounted) return;
      await CetakUtilIs.eksporExcel(
        context: context,
        namaFile: 'laporan-opname-${_fmtTgl.format(_sampai)}.xlsx',
        headers: _headerCetak,
        rows: _barisCetak(data),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal ekspor: $e')));
      }
    }
  }

  /// Tabel datar per produk — kolom dan urutannya mengikuti layar legacy 09.
  ///
  /// Nama kolomnya sengaja memakai istilah layar lama ("Stok Komp.", "Hrg.
  /// Pokok"): pengguna yang sedang membandingkan kedua layar mencari kata itu,
  /// dan menggantinya dengan istilah baru membuat perbandingan jadi pekerjaan
  /// menebak.
  Widget _tabelProduk() => AppDataTable(
        minWidth: 1040,
        emptyText: 'Tidak ada baris opname pada periode ini.',
        columns: const [
          AppTableColumn('Tgl. Opname', flex: 2),
          AppTableColumn('#Kode', flex: 2),
          AppTableColumn('Nama Barang', flex: 4),
          AppTableColumn('Sat.', flex: 1),
          AppTableColumn('Stok Komp.', flex: 2, align: TextAlign.right),
          AppTableColumn('Stok Fisik', flex: 2, align: TextAlign.right),
          AppTableColumn('Selisih', flex: 2, align: TextAlign.right),
          AppTableColumn('Hrg. Pokok', flex: 2, align: TextAlign.right),
          AppTableColumn('Total Harga', flex: 2, align: TextAlign.right),
        ],
        rows: _data.map((r) {
          final selisih = (r['selisih'] as num?)?.toDouble() ?? 0;
          return AppTableRowData(
            // Menekan baris membuka sesi asalnya — penelusuran yang tidak
            // dimiliki layar lama, dan tidak mengubah bentuk laporannya.
            onTap: () => _bukaRincian({
              'id': r['idSesi'],
              'nomor': '${r['tanggal'] ?? ''}',
              'tanggal': '${r['tanggal'] ?? ''}',
            }),
            cells: [
              AppTableCell.text('${r['tanggal'] ?? ''}', flex: 2),
              AppTableCell(
                flex: 2,
                child: Text('${r['kode'] ?? ''}',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              ),
              AppTableCell.text('${r['nama'] ?? ''}', flex: 4, maxLines: 2),
              AppTableCell.text('${r['satuan'] ?? ''}', flex: 1),
              AppTableCell.text(
                  _fmtQty.format((r['stokSistem'] as num?) ?? 0),
                  flex: 2,
                  align: TextAlign.right),
              AppTableCell.text(_fmtQty.format((r['stokFisik'] as num?) ?? 0),
                  flex: 2, align: TextAlign.right),
              AppTableCell(
                flex: 2,
                align: TextAlign.right,
                child: Text(
                  _fmtQty.format(selisih),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selisih < 0
                          ? AppColors.danger
                          : (selisih > 0
                              ? AppColors.success
                              : AppColors.textPrimaryOf(context))),
                ),
              ),
              AppTableCell.text(_fmtRp.format((r['harga'] as num?) ?? 0),
                  flex: 2, align: TextAlign.right),
              AppTableCell.text(_fmtRp.format((r['nilai'] as num?) ?? 0),
                  flex: 2, align: TextAlign.right),
            ],
          );
        }).toList(),
        pagination: AppTablePagination(
          halaman: _halaman,
          totalHalaman: _totalHalaman,
          totalData: _total,
          labelData: 'baris opname',
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
      );

  Future<void> _bukaRincian(Map<String, dynamic> r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Sheet bawaan Material dibatasi 640 px, dan AppDataTable jatuh ke tata
      // letak kartu bertumpuk di bawah 720 px. Layar legacy 10 adalah laporan
      // TABULAR — sistem, fisik, dan selisih dibaca dengan diadu berdampingan —
      // jadi sheet-nya dilebarkan sampai tabelnya benar-benar terbentuk. Di
      // layar sempit nilai `min` di bawah tetap menyerahkan tata letak kartu.
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width < 760
            ? MediaQuery.of(context).size.width
            : (MediaQuery.of(context).size.width * 0.8).clamp(760.0, 1200.0),
      ),
      builder: (_) => _RincianOpnameSheet(
        id: (r['id'] as num).toInt(),
        nomor: '${r['nomor'] ?? ''}',
        tanggal: '${r['tanggal'] ?? ''}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.laporanOpname,
      judul: 'Laporan Opname',
      // Menyebut BENTUKNYA, bukan sekadar topiknya: subjudul lama ("Sesi opname")
      // menggambarkan tampilan Per Sesi, padahal bawaannya per produk -- dan
      // dokumen paritas dibaca orang yang sedang mengadu kolom demi kolom.
      subjudul: 'Stok sistem vs fisik per produk per tanggal '
          '(layar legacy 09; cetaknya layar 10)',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak/Preview PDF Laporan Opname (parameter = filter aktif)',
            onPressed: _cetakPdf),
        IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Ekspor Excel',
            onPressed: _eksporExcel),
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang',
            onPressed: _muat),
      ]),
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 260,
                            child: AppSearchField(
                              hintText: 'Cari nomor / keterangan...',
                              onChanged: (v) {
                                _kataKunci = v.trim();
                                _halaman = 1;
                                _muat();
                              },
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pilihTanggal(dari: true),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text('Dari: ${_fmtTgl.format(_dari)}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pilihTanggal(dari: false),
                            icon: const Icon(Icons.event, size: 16),
                            label: Text('Sampai: ${_fmtTgl.format(_sampai)}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          FilterChip(
                            label: const Text('Hanya yang berselisih',
                                style: TextStyle(fontSize: 12)),
                            selected: _hanyaBerselisih,
                            onSelected: (v) {
                              _hanyaBerselisih = v;
                              _halaman = 1;
                              _muat();
                            },
                          ),
                          // "Per Produk" lebih dulu, dan itu bawaannya: bentuk
                          // inilah yang sepadan dengan layar legacy 09.
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                                visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(
                                  value: 'produk',
                                  label: Text('Per Produk',
                                      style: TextStyle(fontSize: 12))),
                              ButtonSegment(
                                  value: 'sesi',
                                  label: Text('Per Sesi',
                                      style: TextStyle(fontSize: 12))),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (v) {
                              _mode = v.first;
                              _halaman = 1;
                              _muat();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _RingkasanHalaman(
                        sesi: _data.length,
                        produk: _ringkasProduk,
                        lebih: _ringkasLebih,
                        kurang: _ringkasKurang,
                        nilai: _ringkasNilai,
                        seluruhRentang: _ringkasSeluruhRentang,
                        tampilkanSesi: !_perProduk,
                      ),
                      const SizedBox(height: 12),
                      if (_perProduk)
                        _tabelProduk()
                      else
                      AppDataTable(
                        minWidth: 1040,
                        emptyText:
                            'Tidak ada sesi opname pada periode ini.',
                        columns: const [
                          AppTableColumn('Nomor', flex: 2),
                          AppTableColumn('Tanggal', flex: 2),
                          AppTableColumn('Gudang', flex: 2),
                          AppTableColumn('Status', flex: 1),
                          AppTableColumn('Produk',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Lebih',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Kurang',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Bersih',
                              flex: 1, align: TextAlign.right),
                          AppTableColumn('Nilai Selisih',
                              flex: 2, align: TextAlign.right),
                        ],
                        rows: _data.map((r) {
                          final bersih =
                              (r['selisihBersih'] as num?)?.toDouble() ?? 0;
                          return AppTableRowData(
                            onTap: () => _bukaRincian(r),
                            cells: [
                              AppTableCell(
                                flex: 2,
                                child: Text('${r['nomor'] ?? ''}',
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12)),
                              ),
                              AppTableCell.text('${r['tanggal'] ?? ''}',
                                  flex: 2),
                              AppTableCell.text('${r['gudang'] ?? ''}',
                                  flex: 2, maxLines: 2),
                              AppTableCell.text('${r['status'] ?? ''}',
                                  flex: 1),
                              AppTableCell.text(
                                  _fmtQty
                                      .format((r['jumlahProduk'] as num?) ?? 0),
                                  flex: 1,
                                  align: TextAlign.right),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.right,
                                child: Text(
                                  _fmtQty
                                      .format((r['totalLebih'] as num?) ?? 0),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.success),
                                ),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.right,
                                child: Text(
                                  _fmtQty
                                      .format((r['totalKurang'] as num?) ?? 0),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.danger),
                                ),
                              ),
                              AppTableCell(
                                flex: 1,
                                align: TextAlign.right,
                                child: Text(
                                  _fmtQty.format(bersih),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: bersih < 0
                                          ? AppColors.danger
                                          : (bersih > 0
                                              ? AppColors.success
                                              : AppColors.textPrimaryOf(
                                                  context))),
                                ),
                              ),
                              AppTableCell.text(
                                  _fmtRp
                                      .format((r['nilaiSelisih'] as num?) ?? 0),
                                  flex: 2,
                                  align: TextAlign.right),
                            ],
                          );
                        }).toList(),
                        pagination: AppTablePagination(
                          halaman: _halaman,
                          totalHalaman: _totalHalaman,
                          totalData: _total,
                          labelData: 'sesi opname',
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

/// Ringkasan HALAMAN aktif, dan dinamai begitu di layarnya.
///
/// Server sengaja mengirim `*Halaman`, bukan total seluruh rentang: menampilkan
/// angka halaman sebagai kalau-kalau total keseluruhan adalah salah-baca yang
/// tidak menimbulkan galat apa pun — hanya angka yang keliru dipercaya.
class _RingkasanHalaman extends StatelessWidget {
  final int sesi;
  final int produk;
  final double lebih;
  final double kurang;
  final double nilai;

  /// Menentukan LABELNYA, bukan angkanya. Angka halaman dan angka seluruh
  /// rentang terlihat persis sama di layar; satu-satunya yang membedakan bagi
  /// pembaca adalah tulisan di atasnya — dan menyebut angka halaman sebagai
  /// "total" adalah salah-baca yang tidak menimbulkan galat apa pun.
  final bool seluruhRentang;
  final bool tampilkanSesi;

  const _RingkasanHalaman(
      {required this.sesi,
      required this.produk,
      required this.lebih,
      required this.kurang,
      required this.nilai,
      this.seluruhRentang = false,
      this.tampilkanSesi = true});

  @override
  Widget build(BuildContext context) {
    Widget kotak(String label, String isi, {Color? warna}) => Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondaryOf(context))),
              const SizedBox(height: 2),
              Text(isi,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: warna ?? AppColors.textPrimaryOf(context))),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(runSpacing: 10, children: [
          if (tampilkanSesi) kotak('Sesi (halaman ini)', '$sesi'),
          kotak(seluruhRentang ? 'Baris (seluruh periode)' : 'Produk dihitung',
              _fmtQty.format(produk)),
          kotak(seluruhRentang ? 'Total lebih (periode)' : 'Total lebih',
              _fmtQty.format(lebih),
              warna: AppColors.success),
          kotak(seluruhRentang ? 'Total kurang (periode)' : 'Total kurang',
              _fmtQty.format(kurang),
              warna: AppColors.danger),
          kotak(
              seluruhRentang ? 'TOTAL HARGA (periode)' : 'Nilai selisih',
              _fmtRp.format(nilai),
              warna: nilai < 0 ? AppColors.danger : null),
        ]),
      ),
    );
  }
}

/// Rincian satu sesi opname — layar legacy 10.
class _RincianOpnameSheet extends StatefulWidget {
  final int id;
  final String nomor;
  final String tanggal;
  const _RincianOpnameSheet(
      {required this.id, required this.nomor, required this.tanggal});

  @override
  State<_RincianOpnameSheet> createState() => _RincianOpnameSheetState();
}

class _RincianOpnameSheetState extends State<_RincianOpnameSheet>
    with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _kepala = {};
  double _lebih = 0, _kurang = 0, _nilai = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('si_stock_count_detail', {'id': widget.id});
      setStateIfMounted(() {
        _kepala = (hasil['kepala'] as Map?)?.cast<String, dynamic>() ?? {};
        _data = ((hasil['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .toList();
        _lebih = (hasil['totalLebih'] as num?)?.toDouble() ?? 0;
        _kurang = (hasil['totalKurang'] as num?)?.toDouble() ?? 0;
        _nilai = (hasil['nilaiSelisih'] as num?)?.toDouble() ?? 0;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Rincian Opname ${widget.nomor}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                        '${widget.tanggal} · ${_kepala['gudang'] ?? ''}'
                        '${(_kepala['oleh'] ?? '').toString().isEmpty ? '' : ' · oleh ${_kepala['oleh']}'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context))),
                  ],
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop()),
            ]),
          ),
          if (!_memuat && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RingkasanHalaman(
                  sesi: 1,
                  produk: _data.length,
                  lebih: _lebih,
                  kurang: _kurang,
                  nilai: _nilai),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                AppDetailGalatOpsional(
                                    detail: detailUntuk(_error)),
                              ]),
                        ),
                      )
                    : ListView(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        children: [
                          AppDataTable(
                            minWidth: 900,
                            emptyText: 'Sesi ini tidak punya rincian produk.',
                            columns: const [
                              AppTableColumn('Kode', flex: 2),
                              AppTableColumn('Nama Barang', flex: 4),
                              AppTableColumn('Sat', flex: 1),
                              AppTableColumn('Sistem',
                                  flex: 2, align: TextAlign.right),
                              AppTableColumn('Fisik',
                                  flex: 2, align: TextAlign.right),
                              AppTableColumn('Selisih',
                                  flex: 2, align: TextAlign.right),
                              AppTableColumn('Nilai',
                                  flex: 2, align: TextAlign.right),
                            ],
                            rows: _data.map((d) {
                              final selisih =
                                  (d['selisih'] as num?)?.toDouble() ?? 0;
                              return AppTableRowData(cells: [
                                AppTableCell(
                                  flex: 2,
                                  child: Text('${d['kode'] ?? ''}',
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12)),
                                ),
                                AppTableCell.text('${d['nama'] ?? ''}',
                                    flex: 4, maxLines: 2),
                                AppTableCell.text('${d['satuan'] ?? ''}',
                                    flex: 1),
                                AppTableCell.text(
                                    _fmtQty.format(
                                        (d['stokSistem'] as num?) ?? 0),
                                    flex: 2,
                                    align: TextAlign.right),
                                AppTableCell.text(
                                    _fmtQty
                                        .format((d['stokFisik'] as num?) ?? 0),
                                    flex: 2,
                                    align: TextAlign.right),
                                AppTableCell(
                                  flex: 2,
                                  align: TextAlign.right,
                                  child: Text(
                                    _fmtQty.format(selisih),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: selisih < 0
                                            ? AppColors.danger
                                            : (selisih > 0
                                                ? AppColors.success
                                                : AppColors.textPrimaryOf(
                                                    context))),
                                  ),
                                ),
                                AppTableCell.text(
                                    _fmtRp.format((d['nilai'] as num?) ?? 0),
                                    flex: 2,
                                    align: TextAlign.right),
                              ]);
                            }).toList(),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
