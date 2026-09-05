import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../widgets/app_shell.dart';

class DeliveryApotikScreen extends StatefulWidget {
  const DeliveryApotikScreen({super.key});

  @override
  State<DeliveryApotikScreen> createState() => _DeliveryApotikScreenState();
}

class _DeliveryApotikScreenState extends State<DeliveryApotikScreen> {
  final _cari = TextEditingController();
  final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  List<Map<String, dynamic>> _data = const [];
  bool _memuat = true;
  String _status = '';
  String? _error;

  static const _statusList = <String>[
    '',
    'MENUNGGU',
    'DISIAPKAN',
    'DIKIRIM',
    'TERKIRIM',
    'GAGAL',
    'DIBATALKAN',
  ];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  bool _sukses(Map<String, dynamic> hasil) =>
      hasil['status'] == '00' || hasil['status'] == 'success';

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('apotik_delivery_list', {
        'page': 1,
        'page_size': 100,
        if (_status.isNotEmpty) 'status': _status,
        if (_cari.text.trim().isNotEmpty) 'keyword': _cari.text.trim(),
      });
      if (!_sukses(hasil)) {
        throw Exception(hasil['description'] ?? 'Delivery gagal dimuat.');
      }
      if (!mounted) return;
      setState(() {
        _data = ((hasil['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _memuat = false;
      });
    }
  }

  Future<void> _ubahStatus(Map<String, dynamic> baris, String status) async {
    String bukti = '';
    if (status == 'TERKIRIM') {
      final controller = TextEditingController();
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Konfirmasi obat diterima'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nama penerima / bukti serah terima',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Konfirmasi')),
          ],
        ),
      );
      bukti = controller.text.trim();
      controller.dispose();
      if (lanjut != true) return;
    }
    try {
      final hasil = await ApiClient.instance.aksi('apotik_delivery_status', {
        'id': baris['id'],
        'status': status,
        if (bukti.isNotEmpty) 'bukti_terima': bukti,
      });
      if (!_sukses(hasil)) {
        throw Exception(hasil['description'] ?? 'Status gagal diperbarui.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${baris['kode']} menjadi $status')),
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _buatOrder() async {
    final nama = TextEditingController();
    final telepon = TextEditingController();
    final alamat = TextEditingController();
    final kurir = TextEditingController(text: 'Kurir Apotik');
    final layanan = TextEditingController(text: 'SAME DAY');
    final pelacakan = TextEditingController();
    final biaya = TextEditingController(text: '0');
    final transaksi = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final simpan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delivery Order Baru'),
        content: SizedBox(
          width: 560,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _field(nama, 'Nama penerima', wajib: true),
                  _field(telepon, 'Nomor telepon'),
                  SizedBox(
                    width: 532,
                    child: TextFormField(
                      controller: alamat,
                      minLines: 2,
                      maxLines: 3,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Alamat wajib diisi'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Alamat pengiriman',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ),
                  _field(kurir, 'Kurir'),
                  _field(layanan, 'Layanan'),
                  _field(pelacakan, 'Nomor pelacakan'),
                  _field(biaya, 'Biaya kirim', angka: true),
                  _field(transaksi, 'ID transaksi', angka: true),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (simpan == true) {
      try {
        final hasil = await ApiClient.instance.aksi('apotik_delivery_simpan', {
          'nama_penerima': nama.text.trim(),
          'telepon': telepon.text.trim(),
          'alamat': alamat.text.trim(),
          'kurir': kurir.text.trim(),
          'layanan': layanan.text.trim(),
          'nomor_pelacakan': pelacakan.text.trim(),
          'biaya_kirim': num.tryParse(biaya.text) ?? 0,
          if (int.tryParse(transaksi.text) != null)
            'transaksi_id': int.parse(transaksi.text),
        });
        if (!_sukses(hasil)) {
          throw Exception(hasil['description'] ?? 'Order gagal disimpan.');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delivery order berhasil dibuat.')),
          );
          await _muat();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', ''))));
        }
      }
    }
    for (final c in [
      nama,
      telepon,
      alamat,
      kurir,
      layanan,
      pelacakan,
      biaya,
      transaksi
    ]) {
      c.dispose();
    }
  }

  Widget _field(TextEditingController controller, String label,
      {bool wajib = false, bool angka = false}) {
    return SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        keyboardType: angka ? TextInputType.number : null,
        validator: wajib
            ? (v) => (v ?? '').trim().isEmpty ? '$label wajib diisi' : null
            : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Delivery Obat',
      subjudul: 'Pengiriman, pelacakan, dan bukti serah terima pasien',
      scrollable: false,
      actionsAppBar: [
        IconButton(
            onPressed: _memuat ? null : _muat, icon: const Icon(Icons.refresh)),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _buatOrder,
          icon: const Icon(Icons.add),
          label: const Text('Order Baru'),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(children: [
        _ringkasan(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _cari,
                onSubmitted: (_) => _muat(),
                decoration: InputDecoration(
                  hintText: 'Cari kode, penerima, atau nomor pelacakan',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Cari',
                    onPressed: _muat,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: _statusList
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(s.isEmpty ? 'Semua status' : s)))
                    .toList(),
                onChanged: (v) {
                  _status = v ?? '';
                  _muat();
                },
              ),
            ),
          ]),
        ),
        Expanded(child: _isi()),
      ]),
    );
  }

  Widget _ringkasan() {
    int jumlah(String status) =>
        _data.where((e) => e['status'] == status).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF075985), Color(0xFF0F766E)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.local_shipping_outlined,
            color: Colors.white, size: 34),
        const SizedBox(width: 14),
        _angka('Total', _data.length),
        _angka('Menunggu', jumlah('MENUNGGU')),
        _angka('Disiapkan', jumlah('DISIAPKAN')),
        _angka('Dikirim', jumlah('DIKIRIM')),
        _angka('Terkirim', jumlah('TERKIRIM')),
      ]),
    );
  }

  Widget _angka(String label, int nilai) => Expanded(
        child: Column(children: [
          Text('$nilai',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Color(0xFFD1FAE5))),
        ]),
      );

  Widget _isi() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 10),
          Text(_error!),
          TextButton.icon(
              onPressed: _muat,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi')),
        ]),
      );
    }
    if (_data.isEmpty) {
      return const Center(
          child: Text('Belum ada delivery order pada filter ini.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: _data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _kartu(_data[i]),
    );
  }

  Widget _kartu(Map<String, dynamic> d) {
    final status = '${d['status'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: _warna(status).withValues(alpha: .12),
            child: Icon(Icons.delivery_dining_outlined, color: _warna(status)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${d['kode']}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                _pill(status),
              ]),
              const SizedBox(height: 5),
              Text('${d['namaPenerima']} • ${d['telepon']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${d['alamat']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Expanded(
            flex: 2,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['kurir']} • ${d['layanan']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${d['nomorPelacakan']}'),
              Text(_rupiah.format((d['biayaKirim'] as num?) ?? 0)),
            ]),
          ),
          Text('${d['waktuPesan']}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'Ubah status',
            onSelected: (s) => _ubahStatus(d, s),
            itemBuilder: (_) => _statusList
                .where((s) => s.isNotEmpty && s != status)
                .map((s) => PopupMenuItem(value: s, child: Text(s)))
                .toList(),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String status) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _warna(status).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status,
            style: TextStyle(
                color: _warna(status),
                fontSize: 10,
                fontWeight: FontWeight.w800)),
      );

  Color _warna(String status) => switch (status) {
        'TERKIRIM' => const Color(0xFF15803D),
        'DIKIRIM' => const Color(0xFF0369A1),
        'DISIAPKAN' => const Color(0xFF7C3AED),
        'GAGAL' || 'DIBATALKAN' => const Color(0xFFB91C1C),
        _ => const Color(0xFFC2410C),
      };
}
