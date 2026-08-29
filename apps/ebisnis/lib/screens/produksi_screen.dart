import 'package:flutter/material.dart';

import '../api_client.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_shell.dart';

enum BagianProduksi {
  billOfMaterial,
  workOrder,
  materialIssue,
  materialReturn,
  productionOutput,
  productionWaste,
  productionCost,
  productionUnbuild,
  qualityAlert,
}

class ProduksiScreen extends StatefulWidget {
  final BagianProduksi bagian;
  const ProduksiScreen({super.key, required this.bagian});
  @override
  State<ProduksiScreen> createState() => _ProduksiScreenState();
}

class _ProduksiScreenState extends State<ProduksiScreen> {
  bool memuat = false;
  List<Map<String, dynamic>> dokumen = <Map<String, dynamic>>[];
  Map<String, dynamic> hak = <String, dynamic>{};
  AppErrorInfo? galatMuat;
  String pencarian = '';

  _Konfigurasi get cfg => _Konfigurasi.dari(widget.bagian);

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void didUpdateWidget(covariant ProduksiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bagian != widget.bagian) _muat();
  }

  Future<void> _muat() async {
    setState(() {
      memuat = true;
      galatMuat = null;
    });
    try {
      final r = await ApiClient.instance.aksi(
          'produksi_list', <String, dynamic>{'jenis': cfg.kode, 'limit': 200});
      if (!mounted) return;
      setState(() {
        dokumen = _daftar(r['data']);
        hak = _peta(r['hakAkses']);
      });
    } catch (e) {
      if (mounted) {
        setState(() => galatMuat = _infoGalatProduksi(e, cfg.judul));
      }
    } finally {
      if (mounted) setState(() => memuat = false);
    }
  }

  Future<void> _detail(Map<String, dynamic> ringkas) async {
    try {
      final r = await ApiClient.instance.aksi('produksi_detail',
          <String, dynamic>{'jenis': cfg.kode, 'id': ringkas['id']});
      if (!mounted) return;
      final d = _peta(r['data']);
      final h = _peta(r['hakAkses']);
      final aksi = await showDialog<String>(
          context: context, builder: (_) => _Detail(cfg: cfg, data: d, hak: h));
      if (aksi == 'ubah') await _form(d);
      if (aksi != null && aksi.startsWith('status:')) {
        await _status(d, aksi.substring(7));
      }
      if (aksi != null && aksi.startsWith('disposisi:')) {
        await _disposisi(d, aksi.substring(10));
      }
    } catch (e) {
      if (mounted) _pesan('Gagal memuat rincian: $e');
    }
  }

  Future<void> _form([Map<String, dynamic>? awal]) async {
    final berubah = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _Form(cfg: cfg, awal: awal));
    if (berubah == true) _muat();
  }

  /// Fase E: disposisi Quality Alert -- server membuat dokumen turunan
  /// (REWORK=WO, UNBUILD, SCRAP=WASTE) dan mengelola karantina batch.
  Future<void> _disposisi(Map<String, dynamic> d, String disposisi) async {
    try {
      final r = await ApiClient.instance.aksi(
          'produksi_qc_disposisi', <String, dynamic>{
        'jenis': cfg.kode,
        'id': d['id'],
        'disposisi': disposisi
      });
      final turunan = (r['turunan'] as List?)?.length ?? 0;
      _pesan('Disposisi $disposisi diterapkan'
          '${turunan > 0 ? " ($turunan dokumen turunan draf dibuat)" : ""}.');
      _muat();
    } catch (e) {
      if (mounted) _pesan('Gagal disposisi: $e');
    }
  }

  Future<void> _status(Map<String, dynamic> d, String status) async {
    try {
      await ApiClient.instance.aksi('produksi_status', <String, dynamic>{
        'jenis': cfg.kode,
        'id': d['id'],
        'status': status,
        'catatan': 'Perubahan status dari aplikasi eBisnis',
      });
      _muat();
    } catch (e) {
      if (mounted) _pesan('Gagal mengubah status: $e');
    }
  }

  void _pesan(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    final q = pencarian.toLowerCase();
    final tampil = dokumen
        .where((d) =>
            q.isEmpty ||
            '${d['nomor']} ${d['referensi']} ${d['statusDokumen']}'
                .toLowerCase()
                .contains(q))
        .toList();
    return AppShell(
      menuAktif: _menuProduksi(widget.bagian),
      judul: cfg.judul,
      subjudul: 'Kelola dokumen ${cfg.judul.toLowerCase()}',
      scrollable: false,
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        IconButton(
            onPressed: memuat ? null : _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
        if (hak['buat'] == true)
          FilledButton.icon(
              onPressed: () => _form(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah')),
      ]),
      body: Column(children: <Widget>[
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Cari ${cfg.judul.toLowerCase()}'),
                onChanged: (v) => setState(() => pencarian = v))),
        Expanded(
            child: memuat
                ? const Center(child: CircularProgressIndicator())
                : galatMuat != null
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        children: <Widget>[
                          AppErrorPanel(info: galatMuat!),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _muat,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Periksa Kembali'),
                            ),
                          ),
                        ],
                      )
                    : tampil.isEmpty
                        ? Center(
                            child:
                                Text('Belum ada ${cfg.judul.toLowerCase()}.'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                            itemCount: tampil.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final d = tampil[i];
                              return Card(
                                  child: ListTile(
                                      leading: Icon(cfg.ikon),
                                      title: Text('${d['nomor'] ?? '-'}'),
                                      subtitle: Text(
                                          '${d['statusDokumen'] ?? 'DRAFT'} · Qty ${d['qtyAktual'] ?? d['qtyRencana'] ?? 0} ${d['uom'] ?? ''}\n${d['referensi'] ?? ''}'),
                                      isThreeLine: true,
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _detail(d)));
                            })),
      ]),
      floatingActionButton: hak['buat'] == true
          ? FloatingActionButton.extended(
              onPressed: () => _form(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'))
          : null,
    );
  }
}

MenuEBisnis _menuProduksi(BagianProduksi bagian) {
  switch (bagian) {
    case BagianProduksi.billOfMaterial:
      return MenuEBisnis.produksiBom;
    case BagianProduksi.workOrder:
      return MenuEBisnis.produksiWorkOrder;
    case BagianProduksi.materialIssue:
      return MenuEBisnis.produksiMaterialIssue;
    case BagianProduksi.materialReturn:
      return MenuEBisnis.produksiMaterialReturn;
    case BagianProduksi.productionOutput:
      return MenuEBisnis.produksiOutput;
    case BagianProduksi.productionWaste:
      return MenuEBisnis.produksiWaste;
    case BagianProduksi.productionCost:
      return MenuEBisnis.produksiCosting;
    case BagianProduksi.productionUnbuild:
      return MenuEBisnis.produksiUnbuild;
    case BagianProduksi.qualityAlert:
      return MenuEBisnis.produksiQualityAlert;
  }
}

AppErrorInfo _infoGalatProduksi(Object error, String judulDokumen) {
  final dasar = error is ApiException
      ? error.info
      : AppErrorInfo.dari(error, aktivitas: 'memuat $judulDokumen');
  final jejak = error is ApiException
      ? '${error.pesan}\n${error.teknis}'.toLowerCase()
      : error.toString().toLowerCase();
  if (jejak.contains('inventory_production.production_document') &&
      (jejak.contains('does not exist') ||
          jejak.contains('tidak ada') ||
          jejak.contains('sqlgrammar'))) {
    return AppErrorInfo(
      judul: 'Modul Produksi belum siap di server',
      pesan:
          'Struktur penyimpanan Produksi belum selesai dipasang di server. Data tidak berubah dan menu lain tetap dapat digunakan.',
      solusi: const <String>[
        'Tidak perlu menekan Muat Ulang berulang atau memasang ulang aplikasi; tindakan tersebut tidak membuat struktur server.',
        'Kasir dapat melanjutkan pekerjaan pada menu lain. Catat kode referensi di bawah dan kirimkan kepada admin aplikasi.',
        'Admin perlu memastikan deployment backend memuat seluruh entity dan konfigurasi Hibernate Produksi, kemudian menjalankan ulang server agar pembaruan skema selesai.',
        'Setelah admin menyatakan server siap, kembali ke menu Produksi lalu tekan Periksa Kembali satu kali.',
      ],
      teknis: dasar.teknis,
      kodeReferensi: dasar.kodeReferensi,
    );
  }
  return dasar;
}

class _Form extends StatefulWidget {
  final _Konfigurasi cfg;
  final Map<String, dynamic>? awal;
  const _Form({required this.cfg, this.awal});
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final keyForm = GlobalKey<FormState>();
  late final Map<String, TextEditingController> c;
  late List<Map<String, dynamic>> baris;
  late List<Map<String, dynamic>> genealogi;
  bool simpan = false;

  @override
  void initState() {
    super.initState();
    final a = widget.awal ?? <String, dynamic>{};
    c = <String, TextEditingController>{};
    for (final k in <String>[
      'nomor',
      'referensi',
      'bomId',
      'qtyRencana',
      'qtyAktual',
      'uom',
      'biayaBahan',
      'biayaTenagaKerja',
      'biayaOverhead',
      'catatan'
    ]) {
      c[k] = TextEditingController(text: '${a[k] ?? ''}');
    }
    baris = _daftar(a['baris']);
    genealogi = _daftar(a['genealogi']);
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _tambahBaris() async {
    final x = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _BarisDialog());
    if (x != null) setState(() => baris.add(x));
  }

  Future<void> _tambahGenealogi() async {
    final x = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _GenealogiDialog());
    if (x != null) setState(() => genealogi.add(x));
  }

  Future<void> _simpan() async {
    if (!(keyForm.currentState?.validate() ?? false)) return;
    setState(() => simpan = true);
    try {
      final a = widget.awal ?? <String, dynamic>{};
      await ApiClient.instance.aksi('produksi_simpan', <String, dynamic>{
        'jenis': widget.cfg.kode,
        'id': a['id'],
        'nomor': c['nomor']!.text.trim(),
        'referensi': c['referensi']!.text.trim(),
        'bomId': _int(c['bomId']!.text),
        'qtyRencana': _num(c['qtyRencana']!.text),
        'qtyAktual': _num(c['qtyAktual']!.text),
        'uom': c['uom']!.text.trim(),
        'biayaBahan': _num(c['biayaBahan']!.text),
        'biayaTenagaKerja': _num(c['biayaTenagaKerja']!.text),
        'biayaOverhead': _num(c['biayaOverhead']!.text),
        'catatan': c['catatan']!.text.trim(),
        'baris': baris,
        'genealogi': genealogi,
        'clientMutationId': a['clientMutationId'] ??
            'MOBILE-${DateTime.now().millisecondsSinceEpoch}',
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => simpan = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
          child: Scaffold(
        appBar: AppBar(
            title: Text(widget.awal == null
                ? 'Tambah ${widget.cfg.judul}'
                : 'Ubah ${widget.cfg.judul}')),
        body: Form(
            key: keyForm,
            child:
                ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              _input(c['nomor']!, 'Nomor dokumen *', wajib: true),
              _input(c['referensi']!, 'Referensi'),
              Row(children: <Widget>[
                Expanded(child: _input(c['bomId']!, 'ID BOM', angka: true)),
                const SizedBox(width: 12),
                Expanded(child: _input(c['uom']!, 'UOM'))
              ]),
              Row(children: <Widget>[
                Expanded(
                    child:
                        _input(c['qtyRencana']!, 'Qty rencana', angka: true)),
                const SizedBox(width: 12),
                Expanded(
                    child: _input(c['qtyAktual']!, 'Qty aktual', angka: true))
              ]),
              Row(children: <Widget>[
                Expanded(
                    child:
                        _input(c['biayaBahan']!, 'Biaya bahan', angka: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: _input(c['biayaTenagaKerja']!, 'Biaya tenaga',
                        angka: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: _input(c['biayaOverhead']!, 'Overhead', angka: true))
              ]),
              _input(c['catatan']!, 'Catatan', maxLines: 3),
              _judul('Baris bahan / hasil / biaya', _tambahBaris),
              ...baris.asMap().entries.map((e) => ListTile(
                  title: Text(
                      '${e.value['tipeBaris']} · ${e.value['nama'] ?? e.value['kode'] ?? '-'}'),
                  subtitle: Text(
                      'Qty ${e.value['qty'] ?? 0} ${e.value['uom'] ?? ''} · Lot ${e.value['lot'] ?? '-'}'),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => baris.removeAt(e.key))))),
              _judul('Genealogi lot bahan → hasil', _tambahGenealogi),
              ...genealogi.asMap().entries.map((e) => ListTile(
                  title: Text(
                      'Baris ${e.value['inputLineNo']} → ${e.value['outputLineNo']}'),
                  subtitle: Text(
                      '${e.value['lotBahan'] ?? '-'} → ${e.value['lotHasil'] ?? '-'} · Qty ${e.value['qty'] ?? 0}'),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          setState(() => genealogi.removeAt(e.key))))),
              const SizedBox(height: 24),
              FilledButton.icon(
                  onPressed: simpan ? null : _simpan,
                  icon: const Icon(Icons.save),
                  label: Text(simpan ? 'Menyimpan...' : 'Simpan')),
            ])),
      ));
}

class _BarisDialog extends StatefulWidget {
  const _BarisDialog();
  @override
  State<_BarisDialog> createState() => _BarisDialogState();
}

class _BarisDialogState extends State<_BarisDialog> {
  String tipe = 'INPUT';
  bool stok = true;
  final c =
      List<TextEditingController>.generate(8, (_) => TextEditingController());
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Tambah baris produksi'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            DropdownButtonFormField<String>(
                value: tipe,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                      value: 'INPUT', child: Text('Bahan masuk proses')),
                  DropdownMenuItem(
                      value: 'OUTPUT', child: Text('Hasil produksi')),
                  DropdownMenuItem(
                      value: 'WASTE', child: Text('Waste / susut')),
                  DropdownMenuItem(value: 'COST', child: Text('Biaya tambahan'))
                ],
                onChanged: (v) => setState(() => tipe = v ?? 'INPUT')),
            _input(c[0], 'ID item', angka: true),
            _input(c[1], 'Kode'),
            _input(c[2], 'Nama'),
            _input(c[3], 'Qty', angka: true),
            _input(c[4], 'UOM'),
            _input(c[5], 'Lot / batch'),
            _input(c[6], 'Biaya satuan', angka: true),
            _input(c[7], 'Catatan'),
            SwitchListTile(
                value: stok,
                onChanged: (v) => setState(() => stok = v),
                title: const Text('Memengaruhi stok'))
          ])),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(context, <String, dynamic>{
                      'tipeBaris': tipe,
                      'itemId': _int(c[0].text),
                      'kode': c[1].text.trim(),
                      'nama': c[2].text.trim(),
                      'qty': _num(c[3].text),
                      'uom': c[4].text.trim(),
                      'lot': c[5].text.trim(),
                      'biayaSatuan': _num(c[6].text),
                      'catatan': c[7].text.trim(),
                      'memengaruhiStok': stok
                    }),
                child: const Text('Tambah'))
          ]);
}

class _GenealogiDialog extends StatefulWidget {
  const _GenealogiDialog();
  @override
  State<_GenealogiDialog> createState() => _GenealogiDialogState();
}

class _GenealogiDialogState extends State<_GenealogiDialog> {
  final c =
      List<TextEditingController>.generate(5, (_) => TextEditingController());
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Genealogi lot'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            _input(c[0], 'Nomor baris input', angka: true),
            _input(c[1], 'Nomor baris output', angka: true),
            _input(c[2], 'Lot bahan'),
            _input(c[3], 'Lot hasil'),
            _input(c[4], 'Qty', angka: true)
          ]),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(context, <String, dynamic>{
                      'inputLineNo': _int(c[0].text),
                      'outputLineNo': _int(c[1].text),
                      'lotBahan': c[2].text.trim(),
                      'lotHasil': c[3].text.trim(),
                      'qty': _num(c[4].text)
                    }),
                child: const Text('Tambah'))
          ]);
}

class _Detail extends StatelessWidget {
  final _Konfigurasi cfg;
  final Map<String, dynamic> data;
  final Map<String, dynamic> hak;
  const _Detail({required this.cfg, required this.data, required this.hak});
  @override
  Widget build(BuildContext context) {
    final baris = _daftar(data['baris']),
        gen = _daftar(data['genealogi']),
        events = _daftar(data['riwayatStatus']);
    final status = '${data['statusDokumen'] ?? 'DRAFT'}';
    return Dialog.fullscreen(
        child: Scaffold(
            appBar: AppBar(title: Text('${cfg.judul} ${data['nomor'] ?? ''}')),
            body:
                ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              Wrap(spacing: 8, children: <Widget>[
                Chip(label: Text(status)),
                Chip(
                    label: Text(
                        'Qty ${data['qtyAktual'] ?? data['qtyRencana'] ?? 0} ${data['uom'] ?? ''}')),
                Chip(label: Text('Biaya ${data['totalBiaya'] ?? 0}'))
              ]),
              if ('${data['catatan'] ?? ''}'.isNotEmpty)
                ListTile(
                    title: const Text('Catatan'),
                    subtitle: Text('${data['catatan']}')),
              const Divider(),
              const Text('Baris produksi',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...baris.map((b) => ListTile(
                  title: Text(
                      '${b['tipeBaris']} · ${b['nama'] ?? b['kode'] ?? '-'}'),
                  subtitle: Text(
                      'Qty ${b['qty']} ${b['uom'] ?? ''} · Lot ${b['lot'] ?? '-'}'))),
              if (gen.isNotEmpty) ...<Widget>[
                const Divider(),
                const Text('Genealogi',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...gen.map((g) => ListTile(
                    title: Text(
                        'Baris ${g['inputLineNo']} → ${g['outputLineNo']}'),
                    subtitle: Text(
                        '${g['lotBahan'] ?? '-'} → ${g['lotHasil'] ?? '-'} · Qty ${g['qty']}')))
              ],
              if (events.isNotEmpty) ...<Widget>[
                const Divider(),
                const Text('Riwayat status',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...events.map((e) => ListTile(
                    title: Text('${e['dari']} → ${e['ke']}'),
                    subtitle:
                        Text('${e['aktor'] ?? '-'} · ${e['waktu'] ?? ''}')))
              ]
            ]),
            bottomNavigationBar: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: <Widget>[
                          if (hak['ubah'] == true && status == 'DRAFT')
                            OutlinedButton.icon(
                                onPressed: () => Navigator.pop(context, 'ubah'),
                                icon: const Icon(Icons.edit),
                                label: const Text('Ubah')),
                          // Fase E: Quality Alert didisposisi, bukan disetujui.
                          if (cfg.kode == 'quality_alert' && status == 'DRAFT')
                            ...[
                              'REWORK',
                              'UNBUILD',
                              'SCRAP',
                              'RELEASE'
                            ].map((dsp) => OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(context, 'disposisi:$dsp'),
                                child: Text(dsp))),
                          if (cfg.kode != 'quality_alert' &&
                              hak['setujui'] == true &&
                              status == 'DRAFT')
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, 'status:APPROVED'),
                                child: const Text('Setujui')),
                          if (hak['setujui'] == true && status == 'APPROVED')
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, 'status:POSTED'),
                                child: const Text('Posting')),
                          if (hak['batalkan'] == true && status != 'CANCELLED')
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, 'status:CANCELLED'),
                                child: const Text('Batalkan'))
                        ])))));
  }
}

Widget _input(TextEditingController c, String label,
        {bool wajib = false, bool angka = false, int maxLines = 1}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
            controller: c,
            maxLines: maxLines,
            keyboardType: angka
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            decoration: InputDecoration(labelText: label),
            validator: wajib
                ? (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null
                : null));
Widget _judul(String s, VoidCallback f) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(children: <Widget>[
      Expanded(
          child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold))),
      TextButton.icon(
          onPressed: f,
          icon: const Icon(Icons.add),
          label: const Text('Tambah'))
    ]));
Map<String, dynamic> _peta(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _daftar(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];
double _num(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0;
int? _int(String v) => v.trim().isEmpty ? null : int.tryParse(v.trim());

class _Konfigurasi {
  final String kode, judul;
  final IconData ikon;
  const _Konfigurasi(this.kode, this.judul, this.ikon);
  factory _Konfigurasi.dari(BagianProduksi b) {
    switch (b) {
      case BagianProduksi.billOfMaterial:
        return const _Konfigurasi('bill_of_material', 'Bill of Material',
            Icons.account_tree_outlined);
      case BagianProduksi.workOrder:
        return const _Konfigurasi('work_order', 'Work Order Produksi',
            Icons.precision_manufacturing_outlined);
      case BagianProduksi.materialIssue:
        return const _Konfigurasi(
            'material_issue', 'Material Issue', Icons.output_outlined);
      case BagianProduksi.materialReturn:
        return const _Konfigurasi('material_return', 'Material Return',
            Icons.keyboard_return_outlined);
      case BagianProduksi.productionOutput:
        return const _Konfigurasi(
            'production_output', 'Hasil Produksi', Icons.inventory_2_outlined);
      case BagianProduksi.productionWaste:
        return const _Konfigurasi('production_waste', 'Waste & Susut Produksi',
            Icons.delete_sweep_outlined);
      case BagianProduksi.productionCost:
        return const _Konfigurasi(
            'production_cost', 'Biaya Produksi', Icons.calculate_outlined);
      case BagianProduksi.productionUnbuild:
        // Fase D: bongkar barang jadi -- kebalikan OUTPUT+ISSUE dalam satu
        // dokumen (jadi keluar, komponen BOM kembali); arah per-baris di server.
        return const _Konfigurasi('production_unbuild', 'Unbuild / Bongkar',
            Icons.unarchive_outlined);
      case BagianProduksi.qualityAlert:
        // Fase E: terbit otomatis saat OUTPUT produk ber-QC diposting;
        // disposisi REWORK/UNBUILD/SCRAP/RELEASE lewat tombol di rincian.
        return const _Konfigurasi(
            'quality_alert', 'Quality Alert (QC)', Icons.verified_outlined);
    }
  }
}
