import 'package:flutter/material.dart';

import '../api_client.dart';
import '../widgets/app_shell.dart';

enum BagianPengiriman {
  deliveryOrder,
  freightOrder,
  shipmentTracking,
  proofOfDelivery,
  penerimaanTransferOutlet,
  klaimDistribusi,
  reverseLogistics,
}

class PengirimanScreen extends StatefulWidget {
  final BagianPengiriman bagian;

  const PengirimanScreen({super.key, required this.bagian});

  @override
  State<PengirimanScreen> createState() => _PengirimanScreenState();
}

class _PengirimanScreenState extends State<PengirimanScreen> {
  final TextEditingController _cari = TextEditingController();
  List<Map<String, dynamic>> _data = <Map<String, dynamic>>[];
  Map<String, dynamic> _hak = <String, dynamic>{};
  bool _memuat = true;
  String? _pesan;

  _KonfigurasiPengiriman get konfigurasi =>
      _KonfigurasiPengiriman.dari(widget.bagian);

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void didUpdateWidget(covariant PengirimanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bagian != widget.bagian) _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _pesan = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(
        'distribusi_list',
        <String, dynamic>{
          'jenis': konfigurasi.kode,
          'cari': _cari.text.trim(),
          'limit': 100,
        },
      );
      if (!mounted) return;
      final mentah = hasil['data'];
      setState(() {
        _data = mentah is List
            ? mentah
                .whereType<Map>()
                .map((Map nilai) => Map<String, dynamic>.from(nilai))
                .toList()
            : <Map<String, dynamic>>[];
        _hak = hasil['hakAkses'] is Map
            ? Map<String, dynamic>.from(hasil['hakAkses'] as Map)
            : <String, dynamic>{};
      });
    } catch (e) {
      if (mounted) setState(() => _pesan = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _detail(Map<String, dynamic> ringkas) async {
    try {
      final hasil = await ApiClient.instance.aksi(
        'distribusi_detail',
        <String, dynamic>{'id': ringkas['id'], 'jenis': konfigurasi.kode},
      );
      if (!mounted) return;
      final data = hasil['data'] is Map
          ? Map<String, dynamic>.from(hasil['data'] as Map)
          : <String, dynamic>{};
      final hak = hasil['hakAkses'] is Map
          ? Map<String, dynamic>.from(hasil['hakAkses'] as Map)
          : _hak;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => _DialogDetail(
          konfigurasi: konfigurasi,
          data: data,
          hak: hak,
          onEdit: () {
            Navigator.pop(dialogContext);
            _form(data);
          },
          onStatus: (String status) {
            Navigator.pop(dialogContext);
            _ubahStatus(data, status);
          },
        ),
      );
    } catch (e) {
      _info('Gagal memuat detail: $e');
    }
  }

  Future<void> _form([Map<String, dynamic>? awal]) async {
    final berubah = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          _DialogForm(konfigurasi: konfigurasi, awal: awal),
    );
    if (berubah == true) await _muat();
  }

  Future<void> _ubahStatus(Map<String, dynamic> data, String status) async {
    final catatan = TextEditingController();
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Ubah status menjadi ${_labelStatus(status)}'),
        content: TextField(
          controller: catatan,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Catatan status (opsional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Proses')),
        ],
      ),
    );
    final catatanStatus = catatan.text.trim();
    catatan.dispose();
    if (lanjut != true) return;
    try {
      await ApiClient.instance.aksi(
        'distribusi_status',
        <String, dynamic>{
          'id': data['id'],
          'jenis': konfigurasi.kode,
          'statusDokumen': status,
          'catatanStatus': catatanStatus,
        },
      );
      _info('Status dokumen berhasil diperbarui.');
      await _muat();
    } catch (e) {
      _info('Status belum berubah: $e');
    }
  }

  void _info(String pesan) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(pesan)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: _menuPengiriman(widget.bagian),
      judul: konfigurasi.judul,
      subjudul: konfigurasi.subjudul,
      scrollable: false,
      aksiHeader: Wrap(spacing: 8, children: <Widget>[
        IconButton(
            onPressed: _memuat ? null : _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
        if (_hak['create'] == true)
          FilledButton.icon(
            onPressed: () => _form(),
            icon: const Icon(Icons.add),
            label: const Text('Buat Dokumen'),
          ),
      ]),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints batas) {
          final ringkas = batas.maxWidth < 760;
          return RefreshIndicator(
            onRefresh: _muat,
            child: ListView(
              padding: EdgeInsets.all(ringkas ? 12 : 24),
              children: <Widget>[
                TextField(
                  controller: _cari,
                  onSubmitted: (_) => _muat(),
                  decoration: InputDecoration(
                    hintText:
                        'Cari nomor, referensi, asal, tujuan, atau pengangkut...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        onPressed: _muat,
                        icon: const Icon(Icons.arrow_forward)),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                if (_pesan != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_pesan!)),
                  ),
                if (_memuat)
                  const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()))
                else if (_data.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: Text('Belum ada dokumen.'))))
                else
                  ..._data.map(_kartu),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kartu(Map<String, dynamic> item) {
    final status = '${item['statusDokumen'] ?? item['status'] ?? 'DRAFT'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Icon(konfigurasi.ikon)),
        title: Text('${item['nomor'] ?? '-'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${item['asal'] ?? '-'}  →  ${item['tujuan'] ?? '-'}\n'
          '${item['pengangkut'] ?? '-'} · ${item['waktuDibuat'] ?? item['rencana'] ?? '-'}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(_labelStatus(status),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${item['jumlahBaris'] ?? 0} baris'),
          ],
        ),
        onTap: () => _detail(item),
      ),
    );
  }
}

MenuEBisnis _menuPengiriman(BagianPengiriman bagian) {
  switch (bagian) {
    case BagianPengiriman.deliveryOrder:
      return MenuEBisnis.deliveryOrder;
    case BagianPengiriman.freightOrder:
      return MenuEBisnis.freightOrder;
    case BagianPengiriman.shipmentTracking:
      return MenuEBisnis.shipmentTracking;
    case BagianPengiriman.proofOfDelivery:
      return MenuEBisnis.proofOfDelivery;
    case BagianPengiriman.penerimaanTransferOutlet:
      return MenuEBisnis.penerimaanTransferOutlet;
    case BagianPengiriman.klaimDistribusi:
      return MenuEBisnis.klaimDistribusi;
    case BagianPengiriman.reverseLogistics:
      return MenuEBisnis.reverseLogistics;
  }
}

class _DialogForm extends StatefulWidget {
  final _KonfigurasiPengiriman konfigurasi;
  final Map<String, dynamic>? awal;

  const _DialogForm({required this.konfigurasi, this.awal});

  @override
  State<_DialogForm> createState() => _DialogFormState();
}

class _DialogFormState extends State<_DialogForm> {
  late final TextEditingController nomor;
  late final TextEditingController referensi;
  late final TextEditingController asal;
  late final TextEditingController tujuan;
  late final TextEditingController asalTokoId;
  late final TextEditingController tujuanTokoId;
  late final TextEditingController pengangkut;
  late final TextEditingController pelacakan;
  late final TextEditingController penerima;
  late final TextEditingController buktiUrl;
  late final TextEditingController nomorTagihanAngkut;
  late final TextEditingController nilaiTagihanAngkut;
  late final TextEditingController tanggalTagihanAngkut;
  late final TextEditingController catatan;
  final List<_BarisForm> baris = <_BarisForm>[];
  bool menyimpan = false;

  @override
  void initState() {
    super.initState();
    final a = widget.awal ?? <String, dynamic>{};
    nomor = TextEditingController(text: '${a['nomor'] ?? ''}');
    referensi = TextEditingController(text: '${a['referensi'] ?? ''}');
    asal = TextEditingController(text: '${a['asal'] ?? ''}');
    tujuan = TextEditingController(text: '${a['tujuan'] ?? ''}');
    asalTokoId = TextEditingController(text: '${a['asalTokoId'] ?? ''}');
    tujuanTokoId = TextEditingController(text: '${a['tujuanTokoId'] ?? ''}');
    pengangkut = TextEditingController(text: '${a['pengangkut'] ?? ''}');
    pelacakan = TextEditingController(text: '${a['nomorPelacakan'] ?? ''}');
    penerima = TextEditingController(text: '${a['penerima'] ?? ''}');
    buktiUrl = TextEditingController(text: '${a['buktiUrl'] ?? ''}');
    nomorTagihanAngkut =
        TextEditingController(text: '${a['nomorTagihanAngkut'] ?? ''}');
    nilaiTagihanAngkut =
        TextEditingController(text: '${a['nilaiTagihanAngkut'] ?? ''}');
    tanggalTagihanAngkut =
        TextEditingController(text: '${a['tanggalTagihanAngkut'] ?? ''}');
    catatan = TextEditingController(text: '${a['catatan'] ?? ''}');
    final daftar = a['baris'];
    if (daftar is List) {
      for (final nilai in daftar.whereType<Map>()) {
        baris.add(_BarisForm.dari(Map<String, dynamic>.from(nilai)));
      }
    }
    if (baris.isEmpty) baris.add(_BarisForm());
  }

  @override
  void dispose() {
    nomor.dispose();
    referensi.dispose();
    asal.dispose();
    tujuan.dispose();
    asalTokoId.dispose();
    tujuanTokoId.dispose();
    pengangkut.dispose();
    pelacakan.dispose();
    penerima.dispose();
    buktiUrl.dispose();
    nomorTagihanAngkut.dispose();
    nilaiTagihanAngkut.dispose();
    tanggalTagihanAngkut.dispose();
    catatan.dispose();
    for (final b in baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _simpan() async {
    if (tujuan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tujuan wajib diisi.')));
      return;
    }
    if (_memengaruhiStok) {
      final idAsal = int.tryParse(asalTokoId.text.trim()) ?? 0;
      final idTujuan = int.tryParse(tujuanTokoId.text.trim()) ?? 0;
      if (idAsal <= 0 || idTujuan <= 0 || idAsal == idTujuan) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'ID toko asal dan tujuan wajib diisi serta harus berbeda.')));
        return;
      }
    }
    if (_butuhBuktiSerahTerima &&
        (penerima.text.trim().isEmpty || buktiUrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nama penerima dan bukti serah terima wajib diisi.')));
      return;
    }
    if (_butuhTagihanAngkut &&
        (nomorTagihanAngkut.text.trim().isEmpty ||
            (double.tryParse(nilaiTagihanAngkut.text
                        .replaceAll('.', '')
                        .replaceAll(',', '.')) ??
                    0) <=
                0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nomor dan nilai tagihan angkut wajib diisi.')));
      return;
    }
    final barisValid = baris
        .where((b) =>
            b.nama.text.trim().isNotEmpty &&
            (double.tryParse(b.qty.text.replaceAll(',', '.')) ?? 0) > 0)
        .toList();
    if (barisValid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tambahkan minimal satu barang dengan nama dan qty.')));
      return;
    }
    setState(() => menyimpan = true);
    try {
      await ApiClient.instance.aksi(
        'distribusi_simpan',
        <String, dynamic>{
          if (widget.awal?['id'] != null) 'id': widget.awal!['id'],
          'jenis': widget.konfigurasi.kode,
          'nomor': nomor.text.trim(),
          'referensi': referensi.text.trim(),
          'asal': asal.text.trim(),
          'tujuan': tujuan.text.trim(),
          'asalTokoId': int.tryParse(asalTokoId.text.trim()),
          'tujuanTokoId': int.tryParse(tujuanTokoId.text.trim()),
          'pengangkut': pengangkut.text.trim(),
          'nomorPelacakan': pelacakan.text.trim(),
          'penerima': penerima.text.trim(),
          'buktiUrl': buktiUrl.text.trim(),
          'nomorTagihanAngkut': nomorTagihanAngkut.text.trim(),
          'nilaiTagihanAngkut': nilaiTagihanAngkut.text.trim(),
          'tanggalTagihanAngkut': tanggalTagihanAngkut.text.trim(),
          'catatan': catatan.text.trim(),
          'clientMutationId': 'dist-${DateTime.now().microsecondsSinceEpoch}',
          'baris': barisValid.map((b) => b.json()).toList(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dokumen belum tersimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.awal == null
              ? 'Buat ${widget.konfigurasi.judul}'
              : 'Edit ${widget.konfigurasi.judul}'),
          leading: IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.close)),
          actions: <Widget>[
            TextButton.icon(
                onPressed: menyimpan ? null : _simpan,
                icon: const Icon(Icons.save),
                label: const Text('Simpan')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
              _input(nomor, 'Nomor (otomatis bila kosong)'),
              _input(referensi, 'Referensi'),
              _input(asal, 'Asal'),
              _input(tujuan, 'Tujuan *'),
              if (_memengaruhiStok)
                _input(asalTokoId, 'ID toko asal *', angka: true),
              if (_memengaruhiStok)
                _input(tujuanTokoId, 'ID toko tujuan *', angka: true),
              _input(pengangkut, 'Pengangkut'),
              _input(pelacakan, 'Nomor pelacakan'),
              if (_butuhBuktiSerahTerima) _input(penerima, 'Nama penerima *'),
              if (_butuhBuktiSerahTerima)
                _input(buktiUrl, 'URL/lokasi bukti serah terima *'),
              if (_butuhTagihanAngkut)
                _input(nomorTagihanAngkut, 'Nomor tagihan angkut *'),
              if (_butuhTagihanAngkut)
                _input(nilaiTagihanAngkut, 'Nilai tagihan angkut *',
                    angka: true),
              if (_butuhTagihanAngkut)
                _input(tanggalTagihanAngkut,
                    'Tanggal tagihan (yyyy-MM-dd HH:mm:ss)'),
            ]),
            const SizedBox(height: 16),
            TextField(
                controller: catatan,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Catatan', border: OutlineInputBorder())),
            const SizedBox(height: 22),
            Row(children: <Widget>[
              Text('Rincian barang',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                  onPressed: () => setState(() => baris.add(_BarisForm())),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah baris')),
            ]),
            ...List<Widget>.generate(baris.length, _baris),
          ],
        ),
      ),
    );
  }

  bool get _memengaruhiStok =>
      widget.konfigurasi.kode == 'penerimaan_transfer_outlet' ||
      widget.konfigurasi.kode == 'reverse_logistics';

  bool get _butuhBuktiSerahTerima =>
      widget.konfigurasi.kode == 'proof_of_delivery';

  bool get _butuhTagihanAngkut => widget.konfigurasi.kode == 'freight_order';

  Widget _input(TextEditingController controller, String label,
          {bool angka = false}) =>
      SizedBox(
        width: 330,
        child: TextField(
            controller: controller,
            keyboardType: angka ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder())),
      );

  Widget _baris(int index) {
    final b = baris[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
                width: 180,
                child: TextField(
                    controller: b.produk,
                    decoration:
                        const InputDecoration(labelText: 'ID/kode produk'))),
            if (_memengaruhiStok)
              SizedBox(
                  width: 170,
                  child: TextField(
                      controller: b.produkAsal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'ID produk asal *'))),
            if (_memengaruhiStok)
              SizedBox(
                  width: 170,
                  child: TextField(
                      controller: b.produkTujuan,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'ID produk tujuan *'))),
            SizedBox(
                width: 260,
                child: TextField(
                    controller: b.nama,
                    decoration:
                        const InputDecoration(labelText: 'Nama barang'))),
            SizedBox(
                width: 100,
                child: TextField(
                    controller: b.qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'))),
            SizedBox(
                width: 100,
                child: TextField(
                    controller: b.satuan,
                    decoration: const InputDecoration(labelText: 'Satuan'))),
            SizedBox(
                width: 230,
                child: TextField(
                    controller: b.catatan,
                    decoration: const InputDecoration(labelText: 'Catatan'))),
            IconButton(
              tooltip: 'Hapus baris',
              onPressed: baris.length == 1
                  ? null
                  : () => setState(() => baris.removeAt(index).dispose()),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarisForm {
  final TextEditingController produk;
  final TextEditingController produkAsal;
  final TextEditingController produkTujuan;
  final TextEditingController nama;
  final TextEditingController qty;
  final TextEditingController satuan;
  final TextEditingController catatan;

  _BarisForm({
    String produk = '',
    String produkAsal = '',
    String produkTujuan = '',
    String nama = '',
    String qty = '1',
    String satuan = '',
    String catatan = '',
  })  : produk = TextEditingController(text: produk),
        produkAsal = TextEditingController(text: produkAsal),
        produkTujuan = TextEditingController(text: produkTujuan),
        nama = TextEditingController(text: nama),
        qty = TextEditingController(text: qty),
        satuan = TextEditingController(text: satuan),
        catatan = TextEditingController(text: catatan);

  factory _BarisForm.dari(Map<String, dynamic> nilai) => _BarisForm(
        produk:
            '${nilai['itemId'] ?? nilai['produkId'] ?? nilai['kode'] ?? ''}',
        produkAsal:
            '${nilai['sourceProductId'] ?? nilai['produkAsalId'] ?? ''}',
        produkTujuan:
            '${nilai['destinationProductId'] ?? nilai['produkTujuanId'] ?? ''}',
        nama: '${nilai['nama'] ?? nilai['namaBarang'] ?? ''}',
        qty: '${nilai['qty'] ?? 1}',
        satuan: '${nilai['uom'] ?? nilai['satuan'] ?? ''}',
        catatan: '${nilai['catatan'] ?? ''}',
      );

  Map<String, dynamic> json() {
    final id = int.tryParse(produk.text.trim());
    return <String, dynamic>{
      'itemId': id,
      'sourceProductId': int.tryParse(produkAsal.text.trim()),
      'destinationProductId': int.tryParse(produkTujuan.text.trim()),
      'kode': id == null ? produk.text.trim() : '',
      'nama': nama.text.trim(),
      'qty': double.tryParse(qty.text.replaceAll(',', '.')) ?? 0,
      'uom': satuan.text.trim(),
      'catatan': catatan.text.trim(),
    };
  }

  void dispose() {
    produk.dispose();
    produkAsal.dispose();
    produkTujuan.dispose();
    nama.dispose();
    qty.dispose();
    satuan.dispose();
    catatan.dispose();
  }
}

class _DialogDetail extends StatelessWidget {
  final _KonfigurasiPengiriman konfigurasi;
  final Map<String, dynamic> data;
  final Map<String, dynamic> hak;
  final VoidCallback onEdit;
  final ValueChanged<String> onStatus;

  const _DialogDetail({
    required this.konfigurasi,
    required this.data,
    required this.hak,
    required this.onEdit,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final status = '${data['statusDokumen'] ?? data['status'] ?? 'DRAFT'}';
    final daftar = data['baris'] is List ? data['baris'] as List : <dynamic>[];
    final riwayat = data['riwayatStatus'] is List
        ? data['riwayatStatus'] as List
        : <dynamic>[];
    final posting =
        data['postingStok'] is List ? data['postingStok'] as List : <dynamic>[];
    final aksi = _aksiStatus(status)
        .where((String s) => hak[_izinStatus(s)] == true)
        .toList();
    return AlertDialog(
      title: Text('${konfigurasi.judul} · ${data['nomor'] ?? '-'}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(spacing: 8, children: <Widget>[
                Chip(label: Text(_labelStatus(status))),
                Chip(
                    label: Text(
                        '${data['asal'] ?? '-'} → ${data['tujuan'] ?? '-'}')),
                if (data['asalTokoId'] != null || data['tujuanTokoId'] != null)
                  Chip(
                      label: Text(
                          'Toko ${data['asalTokoId'] ?? '-'} → ${data['tujuanTokoId'] ?? '-'}')),
                if ('${data['pengangkut'] ?? ''}'.isNotEmpty)
                  Chip(label: Text('${data['pengangkut']}')),
                if ('${data['nomorPelacakan'] ?? ''}'.isNotEmpty)
                  Chip(
                      avatar: const Icon(Icons.location_searching, size: 18),
                      label: Text('Resi ${data['nomorPelacakan']}')),
              ]),
              if ('${data['penerima'] ?? ''}'.isNotEmpty ||
                  '${data['buktiUrl'] ?? ''}'.isNotEmpty)
                _detailBagian(
                  'Bukti serah terima',
                  <Widget>[
                    if ('${data['penerima'] ?? ''}'.isNotEmpty)
                      Text('Penerima: ${data['penerima']}'),
                    if ('${data['buktiUrl'] ?? ''}'.isNotEmpty)
                      SelectableText('Bukti: ${data['buktiUrl']}'),
                  ],
                ),
              if ('${data['nomorTagihanAngkut'] ?? ''}'.isNotEmpty ||
                  data['nilaiTagihanAngkut'] != null)
                _detailBagian(
                  'Tagihan angkut',
                  <Widget>[
                    Text('Nomor: ${data['nomorTagihanAngkut'] ?? '-'}'),
                    Text('Nilai: ${data['nilaiTagihanAngkut'] ?? 0}'),
                    if ('${data['tanggalTagihanAngkut'] ?? ''}'.isNotEmpty)
                      Text('Tanggal: ${data['tanggalTagihanAngkut']}'),
                  ],
                ),
              if ('${data['catatan'] ?? ''}'.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${data['catatan']}')),
              const Divider(),
              Text('Rincian barang (${daftar.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              ...daftar.whereType<Map>().map((Map nilai) => ListTile(
                    dense: true,
                    title: Text(
                        '${nilai['nama'] ?? nilai['namaBarang'] ?? nilai['kode'] ?? '-'}'),
                    subtitle: Text('${nilai['catatan'] ?? ''}'),
                    trailing: Text(
                        '${nilai['qty'] ?? 0} ${nilai['uom'] ?? nilai['satuan'] ?? ''}'),
                  )),
              if (posting.isNotEmpty) ...<Widget>[
                const Divider(),
                const Text('Posting stok',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                ...posting.whereType<Map>().map((Map nilai) => ListTile(
                      dense: true,
                      leading: Icon(
                        '${nilai['jenis'] ?? ''}' == 'REVERSE'
                            ? Icons.undo
                            : Icons.inventory_2_outlined,
                      ),
                      title: Text(
                          '${nilai['jenis'] ?? 'POST'} · Qty ${nilai['qty'] ?? 0}'),
                      subtitle: Text(
                          'Produk ${nilai['sourceProductId'] ?? '-'} → ${nilai['destinationProductId'] ?? '-'}\n${nilai['waktu'] ?? ''}'),
                      isThreeLine: true,
                    )),
              ],
              if (riwayat.isNotEmpty) ...<Widget>[
                const Divider(),
                const Text('Riwayat status',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                ...riwayat.whereType<Map>().map((Map nilai) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.history),
                      title: Text(
                          '${_labelStatus('${nilai['statusLama'] ?? '-'}')} → ${_labelStatus('${nilai['statusBaru'] ?? '-'}')}'),
                      subtitle: Text(
                          '${nilai['waktu'] ?? ''} · ${nilai['userId'] ?? '-'}${'${nilai['catatan'] ?? ''}'.isEmpty ? '' : '\n${nilai['catatan']}'}'),
                      isThreeLine: '${nilai['catatan'] ?? ''}'.isNotEmpty,
                    )),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (status == 'DRAFT' && hak['update'] == true)
          TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit),
              label: const Text('Edit')),
        ...aksi.map((String s) => FilledButton.tonal(
            onPressed: () => onStatus(s), child: Text(_labelStatus(s)))),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
      ],
    );
  }

  Widget _detailBagian(String judul, List<Widget> isi) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(judul, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...isi,
          ],
        ),
      ),
    );
  }
}

List<String> _aksiStatus(String status) {
  switch (status) {
    case 'DRAFT':
      return <String>['SUBMITTED', 'CANCELLED'];
    case 'SUBMITTED':
      return <String>['APPROVED', 'REJECTED', 'CANCELLED'];
    case 'APPROVED':
      return <String>['IN_PROGRESS', 'COMPLETED', 'CANCELLED'];
    case 'IN_PROGRESS':
      return <String>['COMPLETED', 'CANCELLED'];
    case 'REJECTED':
      return <String>['DRAFT'];
    case 'COMPLETED':
      return <String>['REVERSED'];
    default:
      return <String>[];
  }
}

String _izinStatus(String status) {
  if (status == 'SUBMITTED') return 'submit';
  if (status == 'APPROVED') return 'approve';
  if (status == 'REJECTED') return 'reject';
  if (status == 'CANCELLED') return 'cancel';
  if (status == 'REVERSED') return 'reverse';
  return 'update';
}

String _labelStatus(String status) => status
    .toLowerCase()
    .split('_')
    .map((String kata) =>
        kata.isEmpty ? kata : '${kata[0].toUpperCase()}${kata.substring(1)}')
    .join(' ');

class _KonfigurasiPengiriman {
  final String kode;
  final String judul;
  final String subjudul;
  final IconData ikon;

  const _KonfigurasiPengiriman(this.kode, this.judul, this.subjudul, this.ikon);

  static _KonfigurasiPengiriman dari(BagianPengiriman bagian) {
    switch (bagian) {
      case BagianPengiriman.deliveryOrder:
        return const _KonfigurasiPengiriman(
            'delivery_order',
            'Delivery Order',
            'Pelepasan barang dari gudang menuju outlet.',
            Icons.assignment_turned_in_outlined);
      case BagianPengiriman.freightOrder:
        return const _KonfigurasiPengiriman(
            'freight_order',
            'Freight Order / Rute / Muatan',
            'Rencana pengangkut, rute, muatan, dan jadwal.',
            Icons.local_shipping_outlined);
      case BagianPengiriman.shipmentTracking:
        return const _KonfigurasiPengiriman(
            'shipment_tracking',
            'Shipment & Tracking',
            'Pelacakan perjalanan dan kejadian pengiriman.',
            Icons.route_outlined);
      case BagianPengiriman.proofOfDelivery:
        return const _KonfigurasiPengiriman(
            'proof_of_delivery',
            'Proof of Delivery',
            'Bukti serah terima dan penyelesaian pengiriman.',
            Icons.fact_check_outlined);
      case BagianPengiriman.penerimaanTransferOutlet:
        return const _KonfigurasiPengiriman(
            'penerimaan_transfer_outlet',
            'Penerimaan Transfer Outlet',
            'Penerimaan, verifikasi, dan selisih barang di outlet.',
            Icons.inventory_outlined);
      case BagianPengiriman.klaimDistribusi:
        return const _KonfigurasiPengiriman(
            'klaim_distribusi',
            'Selisih / Kerusakan / Klaim',
            'Pencatatan selisih, kerusakan, kehilangan, dan klaim.',
            Icons.report_problem_outlined);
      case BagianPengiriman.reverseLogistics:
        return const _KonfigurasiPengiriman(
            'reverse_logistics',
            'Retur & Reverse Logistics',
            'Arus balik barang dari outlet ke gudang atau vendor.',
            Icons.keyboard_return_outlined);
    }
  }
}
