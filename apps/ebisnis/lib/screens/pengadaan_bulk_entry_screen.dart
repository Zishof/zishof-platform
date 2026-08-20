import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';

/// Jenis dokumen pengadaan yang dapat diisi massal.
enum JenisPengadaanBulk { pr, po, bast }

/// Bulk entry untuk PR, PO, dan BAST -- mengikuti skema Bulk Entry Kulakan:
/// Header, tempel/Excel, tabel item, lalu review sebelum disimpan.
///
/// Satu layar dipakai bertiga karena bentuk pekerjaannya identik (kumpulkan baris
/// barang, cocokkan ke produk, simpan sebagai dokumen); hanya isi header dan aksi
/// simpannya yang berbeda. Pencocokan baris dilakukan SERVER lewat
/// `pengadaan_barang_resolve`, sehingga aturan pencocokan sama untuk semua kanal.
class PengadaanBulkEntryScreen extends StatefulWidget {
  final JenisPengadaanBulk jenis;
  const PengadaanBulkEntryScreen({super.key, required this.jenis});

  @override
  State<PengadaanBulkEntryScreen> createState() =>
      _PengadaanBulkEntryScreenState();
}

/// Satu baris draf. `produkId` terisi setelah baris berhasil dicocokkan server.
class _BarisBulk {
  int? produkId;
  String statusCocok = 'BARU';
  String catatan = '';
  final TextEditingController kode;
  final TextEditingController nama;
  final TextEditingController jumlah;
  final TextEditingController harga;
  _BarisBulk({
    String kodeAwal = '',
    String namaAwal = '',
    String jumlahAwal = '1',
    String hargaAwal = '0',
  })  : kode = TextEditingController(text: kodeAwal),
        nama = TextEditingController(text: namaAwal),
        jumlah = TextEditingController(text: jumlahAwal),
        harga = TextEditingController(text: hargaAwal);
  void dispose() {
    kode.dispose();
    nama.dispose();
    jumlah.dispose();
    harga.dispose();
  }
}

class _PengadaanBulkEntryScreenState extends State<PengadaanBulkEntryScreen> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  final _tempel = TextEditingController();
  final _keterangan = TextEditingController();
  final _kodeInvoice = TextEditingController();
  final _kirim = TextEditingController();
  final _kodeTagihan = TextEditingController();
  final _tglTagihan = TextEditingController();
  final _kurir = TextEditingController();
  final List<_BarisBulk> _baris = [];
  int? _penyediaId;

  /// Anggaran untuk bulk entry PR. Wajib kecuali dinyatakan tanpa anggaran --
  /// aturan yang sama dengan form PR satuan, ditegakkan juga oleh server.
  int? _anggaranId;
  String _anggaranNama = '';
  bool _tanpaAnggaran = false;
  String _penyediaNama = '';
  bool _sibuk = false;

  bool get _perluPenyedia => widget.jenis != JenisPengadaanBulk.pr;
  bool get _perluAnggaran => widget.jenis == JenisPengadaanBulk.pr;

  String get _judul {
    switch (widget.jenis) {
      case JenisPengadaanBulk.pr:
        return 'Bulk Entry Permintaan Pembelian';
      case JenisPengadaanBulk.po:
        return 'Bulk Entry Pemesanan Pembelian';
      case JenisPengadaanBulk.bast:
        return 'Bulk Entry Penerimaan Barang';
    }
  }

  String get _subjudul {
    switch (widget.jenis) {
      case JenisPengadaanBulk.pr:
        return 'Draf permintaan massal; tersimpan sebagai PR berstatus DRAFT.';
      case JenisPengadaanBulk.po:
        return 'Draf pesanan massal; tersimpan sebagai PO berstatus DRAFT.';
      case JenisPengadaanBulk.bast:
        return 'Draf penerimaan massal tanpa PO; tersimpan sebagai BAST DRAFT.';
    }
  }

  /// Kunci snapshot daftar yang ikut diperbarui optimistis saat luring.
  String get _cacheKey {
    switch (widget.jenis) {
      case JenisPengadaanBulk.pr:
        return 'master:pengadaan_pr';
      case JenisPengadaanBulk.po:
        return 'master:pengadaan_po';
      case JenisPengadaanBulk.bast:
        return 'master:pengadaan_bast';
    }
  }

  String get _aksiSimpan {
    switch (widget.jenis) {
      case JenisPengadaanBulk.pr:
        return 'pengadaan_pr_simpan';
      case JenisPengadaanBulk.po:
        return 'pengadaan_po_simpan';
      case JenisPengadaanBulk.bast:
        return 'pengadaan_bast_simpan';
    }
  }

  @override
  void dispose() {
    _tempel.dispose();
    _keterangan.dispose();
    _kodeInvoice.dispose();
    _kirim.dispose();
    _kodeTagihan.dispose();
    _tglTagihan.dispose();
    _kurir.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _subtotal =>
      _baris.fold(0, (s, b) => s + _angka(b.jumlah.text) * _angka(b.harga.text));

  int get _jumlahCocok => _baris.where((b) => b.produkId != null).length;
  int get _jumlahBelum => _baris.length - _jumlahCocok;

  /// Pesan yang MENGHALANGI penyimpanan. Ditampilkan di bagian review supaya
  /// pengguna tahu persis apa yang kurang sebelum menekan Simpan.
  List<String> get _penghalang {
    final pesan = <String>[];
    if (_baris.isEmpty) {
      pesan.add('Belum ada baris barang.');
    }
    if (_perluPenyedia && _penyediaId == null) {
      pesan.add('Penyedia/vendor belum dipilih.');
    }
    if (_perluAnggaran && !_tanpaAnggaran && _anggaranId == null) {
      pesan.add('Anggaran belum dipilih. Centang "Tanpa anggaran" bila '
          'permintaan ini memang tidak membebani anggaran.');
    }
    if (_jumlahBelum > 0) {
      pesan.add('$_jumlahBelum baris belum cocok dengan produk. '
          'Tekan "Cek Produk" lalu perbaiki kode atau namanya.');
    }
    final nol = _baris.where((b) => _angka(b.jumlah.text) <= 0).length;
    if (nol > 0) {
      pesan.add('$nol baris memiliki jumlah nol.');
    }
    return pesan;
  }

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(teks),
        backgroundColor:
            sukses ? null : Theme.of(context).colorScheme.error));
  }

  /// Pisahkan baris tempelan. TAB, titik koma, dan koma diterima sebagai pemisah,
  /// mengikuti kebiasaan tempel dari Excel maupun teks biasa.
  List<String> _pecah(String baris) {
    if (baris.contains('\t')) return baris.split('\t');
    if (baris.contains(';')) return baris.split(';');
    return baris.split(',');
  }

  void _tambahDariTempelan() {
    final teks = _tempel.text.trim();
    if (teks.isEmpty) {
      _pesan('Tempelkan dulu baris fakturnya.', sukses: false);
      return;
    }
    var ditambah = 0;
    for (final baris in teks.split('\n')) {
      final bersih = baris.trim();
      if (bersih.isEmpty) continue;
      final kolom = _pecah(bersih).map((e) => e.trim()).toList();
      String ambil(int i) => i < kolom.length ? kolom[i] : '';
      final kode = ambil(0);
      final nama = ambil(1);
      if (kode.isEmpty && nama.isEmpty) continue;
      _baris.add(_BarisBulk(
        kodeAwal: kode,
        namaAwal: nama,
        jumlahAwal: ambil(2).isEmpty ? '1' : ambil(2),
        hargaAwal: ambil(3).isEmpty ? '0' : ambil(3),
      ));
      ditambah++;
    }
    _tempel.clear();
    setState(() {});
    _pesan('$ditambah baris ditambahkan ke draf. Tekan "Cek Produk" untuk mencocokkan.');
  }

  /// Cocokkan seluruh baris ke Produk POS lewat server, lalu tandai hasilnya.
  Future<void> _cekProduk() async {
    if (_baris.isEmpty) {
      _pesan('Belum ada baris untuk dicocokkan.', sukses: false);
      return;
    }
    setStateIfMounted(() => _sibuk = true);
    try {
      final payload = _baris
          .map((b) => {
                'kode': b.kode.text.trim(),
                'nama': b.nama.text.trim(),
                'jumlah': _angka(b.jumlah.text),
                'hargaBeli': _angka(b.harga.text),
              })
          .toList();
      final r = await ApiClient.instance
          .aksi('pengadaan_barang_resolve', {'baris': payload});
      if (!mounted) return;
      if (r['status'] != '00' && r['status'] != 'success') {
        _pesan('${r['description'] ?? 'Gagal mencocokkan baris.'}', sukses: false);
        return;
      }
      final data = ((r['data'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (var i = 0; i < data.length && i < _baris.length; i++) {
        final d = data[i];
        final b = _baris[i];
        b.statusCocok = '${d['statusCocok'] ?? 'TIDAK ADA'}';
        b.catatan = '${d['catatan'] ?? ''}';
        b.produkId = (d['produk_id'] as num?)?.toInt();
        if (b.produkId != null) {
          b.kode.text = '${d['kodeProduk'] ?? b.kode.text}';
          b.nama.text = '${d['namaProduk'] ?? b.nama.text}';
          if (_angka(b.harga.text) <= 0) {
            b.harga.text = '${(d['hargaBeli'] as num?)?.toDouble() ?? 0}';
          }
        }
      }
      setStateIfMounted(() {});
      _pesan('Cocok ${r['jumlahCocok'] ?? 0}, ganda ${r['jumlahGanda'] ?? 0}, '
          'tidak ditemukan ${r['jumlahTidakAda'] ?? 0}.');
    } catch (e) {
      _pesan('Gagal mencocokkan: $e', sukses: false);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _unduhFormat() async {
    try {
      final bytes = buildSimpleXlsx(
        sheetName: 'Format Bulk Pengadaan',
        headers: const [
          'kode_barcode [WAJIB]',
          'nama_barang [pengingat, boleh kosong]',
          'jumlah [WAJIB]',
          'harga_beli [WAJIB]',
        ],
        rows: const [
          ['8999999999999', 'Contoh Barang', 12, 7500],
        ],
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan format bulk pengadaan',
        fileName: 'format-bulk-pengadaan.xlsx',
        bytes: bytes,
      );
      _pesan(path == null ? 'Penyimpanan dibatalkan.' : 'Format tersimpan.');
    } catch (e) {
      _pesan('Gagal membuat format: $e', sukses: false);
    }
  }

  Future<void> _unggahExcel() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) return;
      final rows = readSimpleXlsx(bytes);
      var ditambah = 0;
      // Baris pertama dianggap judul kolom bila sel pertamanya bukan angka/kode data.
      for (var i = 1; i < rows.length; i++) {
        final kolom = rows[i];
        String ambil(int j) => j < kolom.length ? kolom[j].trim() : '';
        final kode = ambil(0);
        final nama = ambil(1);
        if (kode.isEmpty && nama.isEmpty) continue;
        _baris.add(_BarisBulk(
          kodeAwal: kode,
          namaAwal: nama,
          jumlahAwal: ambil(2).isEmpty ? '1' : ambil(2),
          hargaAwal: ambil(3).isEmpty ? '0' : ambil(3),
        ));
        ditambah++;
      }
      setStateIfMounted(() {});
      _pesan('$ditambah baris dimuat dari Excel. Tekan "Cek Produk" untuk mencocokkan.');
    } catch (e) {
      _pesan('Gagal membaca Excel: $e', sukses: false);
    }
  }

  Future<void> _pilihPenyedia() async {
    final q = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    final dipilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> cari() async {
          try {
            final r = await ApiClient.instance.aksi(
                'pengadaan_penyedia_cari', {'keyword': q.text.trim(), 'limit': 50});
            hasil = ((r['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } catch (_) {
            hasil = [];
          }
          setLocal(() {});
        }

        if (hasil.isEmpty && q.text.isEmpty) cari();
        return AlertDialog(
          title: const Text('Pilih Penyedia / Vendor'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(children: [
              TextField(
                controller: q,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Cari kode / nama penyedia',
                    suffixIcon: IconButton(
                        onPressed: cari, icon: const Icon(Icons.search))),
                onSubmitted: (_) => cari(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: hasil.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text('${hasil[i]['nama'] ?? '-'}'),
                    subtitle: Text('${hasil[i]['kode'] ?? ''}'),
                    onTap: () => Navigator.pop(dctx, hasil[i]),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx), child: const Text('Tutup'))
          ],
        );
      }),
    );
    q.dispose();
    if (dipilih == null) return;
    setState(() {
      _penyediaId = (dipilih['id'] as num?)?.toInt();
      _penyediaNama = '${dipilih['nama'] ?? ''}';
    });
  }

  Future<void> _pilihTanggal(TextEditingController c) async {
    final pilih = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pilih == null) return;
    setState(() => c.text = DateFormat('dd-MM-yyyy').format(pilih));
  }


  /// Pemilih Anggaran untuk bulk entry PR. Memakai aksi yang sama dengan form PR
  /// satuan, sehingga daftar dan angkanya identik.
  Future<void> _pilihAnggaran() async {
    final r = await ApiClient.instance
        .aksi('pengadaan_anggaran_cari', const {'limit': 50});
    if (!mounted) return;
    final daftar = ((r['data'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (daftar.isEmpty) {
      _pesan('${r['catatan'] ?? 'Tidak ada anggaran aktif.'}', sukses: false);
      return;
    }
    final pilih = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Pilih Anggaran'),
        children: daftar
            .map((a) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, a),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['kode'] ?? ''} ${a['nama'] ?? ''}'.trim()),
                      Text('sisa ${_fmtRp.format(a['sisa'] ?? 0)}',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (pilih == null || !mounted) return;
    setState(() {
      _anggaranId = (pilih['id'] as num?)?.toInt();
      _anggaranNama = '${pilih['kode'] ?? ''} ${pilih['nama'] ?? ''}'.trim();
    });
  }

  Future<void> _simpan() async {
    if (_penghalang.isNotEmpty) {
      _pesan(_penghalang.first, sukses: false);
      return;
    }
    setStateIfMounted(() => _sibuk = true);
    try {
      final detail = _baris
          .where((b) => b.produkId != null)
          .map((b) => {
                'produk_id': b.produkId,
                if (widget.jenis == JenisPengadaanBulk.bast)
                  'diterima': _angka(b.jumlah.text)
                else
                  'jumlah': _angka(b.jumlah.text),
                'hargaBeli': _angka(b.harga.text),
              })
          .toList();
      final body = <String, dynamic>{
        'keterangan': _keterangan.text.trim(),
        if (_perluAnggaran) 'tanpaAnggaran': _tanpaAnggaran,
        if (_perluAnggaran && !_tanpaAnggaran && _anggaranId != null)
          'workspace_id': _anggaranId,
        'detail': detail,
        if (_penyediaId != null) 'penyedia_id': _penyediaId,
        if (widget.jenis == JenisPengadaanBulk.po) ...{
          'kodeInvoice': _kodeInvoice.text.trim(),
          'pengirimanPalingLambat': _kirim.text.trim(),
        },
        if (widget.jenis == JenisPengadaanBulk.bast) ...{
          'kodeTagihan': _kodeTagihan.text.trim(),
          'tanggalTagihan': _tglTagihan.text.trim(),
          'kurir': _kurir.text.trim(),
        },
      };
      // Local-first: dokumen hasil bulk entry ditulis ke antrean perangkat dulu.
      // Entri massal biasanya dikerjakan di gudang; sinyal di sana jarang bagus.
      final r = await prosesSimpanMaster(
        context,
        aksi: _aksiSimpan,
        body: body,
        kunci: '$_aksiSimpan:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: _cacheKey,
      );
      if (!mounted) return;
      _pesan(r['offline'] == true
          ? 'Tersimpan di perangkat, akan dikirim otomatis.'
          : 'Tersimpan sebagai ${r['kode'] ?? ''}.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _pesan('Gagal menyimpan: $e', sukses: false);
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Widget _kartu(String judul, String? catatan, Widget isi) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(judul, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (catatan != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Text(catatan,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            if (catatan == null) const SizedBox(height: 10),
            isi,
          ],
        ),
      ),
    );
  }

  Widget _bagianHeader() {
    return _kartu(
      'Header Dokumen',
      'Data belum menjadi dokumen sampai Anda menekan Simpan di bagian Review.',
      Column(children: [
        if (_perluAnggaran)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              // Saat tanpa anggaran, pemilihnya DISEMBUNYIKAN -- bukan dimatikan.
              if (!_tanpaAnggaran)
                Expanded(
                  child: InkWell(
                    onTap: _pilihAnggaran,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Anggaran *',
                        isDense: true,
                        suffixIcon: Icon(Icons.search, size: 18),
                      ),
                      child: Text(
                          _anggaranNama.isEmpty
                              ? 'Belum dipilih'
                              : _anggaranNama,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                )
              else
                const Expanded(
                  child: Text('Permintaan ini tidak membebani anggaran.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              const SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  value: _tanpaAnggaran,
                  onChanged: (v) => setState(() {
                    _tanpaAnggaran = v ?? false;
                    if (_tanpaAnggaran) {
                      _anggaranId = null;
                      _anggaranNama = '';
                    }
                  }),
                ),
                const SizedBox(
                  width: 56,
                  child: Text('Tanpa anggaran',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10)),
                ),
              ]),
            ]),
          ),
        if (_perluPenyedia)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: _pilihPenyedia,
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Penyedia / Vendor *',
                    isDense: true,
                    suffixIcon: Icon(Icons.search, size: 18)),
                child:
                    Text(_penyediaNama.isEmpty ? 'Belum dipilih' : _penyediaNama),
              ),
            ),
          ),
        if (widget.jenis == JenisPengadaanBulk.po)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _kodeInvoice,
                decoration: const InputDecoration(
                    labelText: 'No. invoice / referensi vendor', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: TextField(
                controller: _kirim,
                readOnly: true,
                onTap: () => _pilihTanggal(_kirim),
                decoration: const InputDecoration(
                    labelText: 'Kirim paling lambat',
                    isDense: true,
                    suffixIcon: Icon(Icons.event, size: 16)),
              ),
            ),
          ]),
        if (widget.jenis == JenisPengadaanBulk.bast)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _kodeTagihan,
                decoration: const InputDecoration(
                    labelText: 'No. tagihan / faktur vendor', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _tglTagihan,
                readOnly: true,
                onTap: () => _pilihTanggal(_tglTagihan),
                decoration: const InputDecoration(
                    labelText: 'Tanggal tagihan',
                    isDense: true,
                    suffixIcon: Icon(Icons.event, size: 16)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _kurir,
                decoration: const InputDecoration(
                    labelText: 'Kurir / pengirim', isDense: true),
              ),
            ),
          ]),
        const SizedBox(height: 10),
        TextField(
          controller: _keterangan,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Keterangan'),
        ),
      ]),
    );
  }

  Widget _bagianTempel() {
    return _kartu(
      'Excel / Tempel Draf',
      'Urutan kolom: kode/barcode, nama, jumlah, harga beli. '
          'Pemisah boleh TAB, titik koma, atau koma.',
      Column(children: [
        TextField(
          controller: _tempel,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: 'Tempel baris di sini', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unduhFormat,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Unduh Format Excel')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _unggahExcel,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Unggah Excel ke Draf')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _tambahDariTempelan,
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Tambahkan dari Tempelan')),
          OutlinedButton.icon(
              onPressed: _sibuk ? null : _cekProduk,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Cek Produk')),
          OutlinedButton.icon(
              onPressed: _sibuk
                  ? null
                  : () => setState(() => _baris.add(_BarisBulk())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah Baris Kosong')),
          OutlinedButton.icon(
              onPressed: _sibuk
                  ? null
                  : () {
                      for (final b in _baris) {
                        b.dispose();
                      }
                      setState(() => _baris.clear());
                      _pesan('Draf dikosongkan.');
                    },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset Draf')),
        ]),
      ]),
    );
  }

  Color _warnaStatus(_BarisBulk b) {
    if (b.produkId != null) return const Color(0xFF2E7D32);
    if (b.statusCocok == 'GANDA') return const Color(0xFFB8860B);
    if (b.statusCocok == 'TIDAK ADA') return Colors.red;
    return Colors.grey;
  }

  Widget _bagianItem() {
    return _kartu(
      'Data Item (${_baris.length} baris)',
      _baris.isEmpty
          ? 'Belum ada baris. Tempel, unggah Excel, atau tambah baris kosong.'
          : 'Perbaiki kode atau nama pada baris yang belum cocok, lalu tekan "Cek Produk" lagi.',
      _baris.isEmpty
          ? const SizedBox.shrink()
          : Column(children: [
              for (var i = 0; i < _baris.length; i++) _barisItem(i, _baris[i]),
            ]),
    );
  }

  Widget _barisItem(int i, _BarisBulk b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 26,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
            )),
        SizedBox(
            width: 130,
            child: TextField(
                controller: b.kode,
                decoration:
                    const InputDecoration(labelText: 'Kode', isDense: true))),
        const SizedBox(width: 6),
        Expanded(
            child: TextField(
                controller: b.nama,
                decoration: const InputDecoration(
                    labelText: 'Nama barang', isDense: true))),
        const SizedBox(width: 6),
        SizedBox(
            width: 70,
            child: TextField(
                controller: b.jumlah,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Jumlah', isDense: true))),
        const SizedBox(width: 6),
        SizedBox(
            width: 110,
            child: TextField(
                controller: b.harga,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'Harga', isDense: true))),
        const SizedBox(width: 6),
        SizedBox(
            width: 105,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  _fmtRp.format(_angka(b.jumlah.text) * _angka(b.harga.text)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            )),
        const SizedBox(width: 6),
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Tooltip(
              message: b.catatan,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: _warnaStatus(b).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(b.produkId != null ? 'COCOK' : b.statusCocok,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _warnaStatus(b))),
              ),
            ),
          ),
        ),
        IconButton(
            onPressed: () {
              setState(() => _baris.remove(b));
              b.dispose();
            },
            icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  Widget _bagianReview() {
    final halangan = _penghalang;
    return _kartu(
      'Review & Simpan',
      'Periksa ringkasan berikut sebelum dokumen dibuat.',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _kotakAngka('Baris', '${_baris.length}'),
          _kotakAngka('Cocok', '$_jumlahCocok'),
          _kotakAngka('Belum cocok', '$_jumlahBelum'),
          _kotakAngka('Subtotal', _fmtRp.format(_subtotal)),
        ]),
        const SizedBox(height: 12),
        if (halangan.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('Draf siap disimpan.',
                style: TextStyle(fontSize: 12)),
          )
        else
          for (final p in halangan)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(p, style: const TextStyle(fontSize: 12))),
              ]),
            ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: (_sibuk || halangan.isNotEmpty) ? null : _simpan,
            icon: const Icon(Icons.save),
            label: Text(_sibuk ? 'Menyimpan...' : 'Simpan Dokumen'),
          ),
        ),
      ]),
    );
  }

  Widget _kotakAngka(String label, String nilai) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(nilai, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_judul, style: const TextStyle(fontSize: 16)),
              Text(_subjudul, style: const TextStyle(fontSize: 11)),
            ]),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _bagianHeader(),
            _bagianTempel(),
            _bagianItem(),
            _bagianReview(),
          ]),
        ),
      ),
    );
  }
}
