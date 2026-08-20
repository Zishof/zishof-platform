import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/checkout_service.dart';
import '../services/keranjang.dart';
import '../services/sesi.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';
import 'pindai_meja_screen.dart';

/// Keranjang + checkout.
///
/// Alurnya mengikuti `initiateCheckout()` pada _beranda_anggota.jsp:
/// segarkan saldo -> pilih saluran pembayaran -> validasi saldo & saldo
/// mengendap (khusus non-manual) -> validasi meja -> kirim satu transaksi
/// per toko (`kantin_bayar` bila otomatis, `kantin_draft_bayar` bila manual).
class KeranjangScreen extends StatefulWidget {
  const KeranjangScreen({super.key});

  @override
  State<KeranjangScreen> createState() => _KeranjangScreenState();
}

class _KeranjangScreenState extends State<KeranjangScreen> {
  final _keterangan = TextEditingController();

  List<Map<String, dynamic>> _caraBayar = [];
  String? _idCaraBayar;
  bool _memuatCaraBayar = true;
  bool _memproses = false;
  String? _galat;
  HasilCheckout? _hasil;

  @override
  void initState() {
    super.initState();
    Keranjang.instance.addListener(_gambarUlang);
    _muatCaraBayar();
  }

  @override
  void dispose() {
    Keranjang.instance.removeListener(_gambarUlang);
    _keterangan.dispose();
    super.dispose();
  }

  void _gambarUlang() {
    if (mounted) setState(() {});
  }

  bool get _manualTerpilih {
    final c = _caraBayar.firstWhere(
      (e) => '${e['id']}' == _idCaraBayar,
      orElse: () => const {},
    );
    return c['manual'] == true || '${c['manual']}' == 'true';
  }

  Future<void> _muatCaraBayar() async {
    setState(() => _memuatCaraBayar = true);
    try {
      // Daftar ini SUDAH disaring server berdasarkan Jenis Anggota member
      // (kolom daftar_cara_pembayaran_yang_boleh_di_pilih), jadi apa pun yang
      // muncul di sini memang boleh dipakai member tersebut.
      final res =
          await ApiClient.instance.aksi('kantin_cara_bayar', const {});
      _caraBayar = ApiClient.instance.daftar(res);
      if (_caraBayar.length == 1) {
        _idCaraBayar = '${_caraBayar.first['id']}';
      }
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuatCaraBayar = false);
    }
  }

  Future<int> _saldoTerkini() async {
    try {
      final res = await ApiClient.instance.aksi('kantin_saldo', const {});
      final saldo = res['data'];
      if (saldo is num) {
        Sesi.instance.saldo = saldo.round();
      }
    } on ApiException {
      // Gagal menyegarkan bukan alasan membatalkan; validasi tetap memakai
      // angka terakhir yang diketahui, dan server tetap punya kata akhir.
    }
    return Sesi.instance.saldo;
  }

  Future<void> _checkout() async {
    final keranjang = Keranjang.instance;
    if (_idCaraBayar == null || _idCaraBayar!.isEmpty) {
      setState(() => _galat = 'Silakan pilih saluran pembayaran.');
      return;
    }
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      final saldo = await _saldoTerkini();
      CheckoutService.validasi(
        keranjang: keranjang,
        caraBayarManual: _manualTerpilih,
        saldoTerkini: saldo,
      );
      final hasil = await CheckoutService.kirim(
        keranjang: keranjang,
        idCaraBayar: _idCaraBayar!,
        manual: _manualTerpilih,
        keterangan: _keterangan.text.trim(),
      );
      if (!mounted) return;
      if (hasil.berhasil) {
        keranjang.kosongkan();
        setState(() => _hasil = hasil);
      } else {
        setState(() => _galat = hasil.tokoBerhasil > 0
            ? '${hasil.pesanGagal}\n\nCatatan: ${hasil.tokoBerhasil} dari '
                '${hasil.tokoTotal} toko sudah berhasil diproses dan TIDAK '
                'dibatalkan. Periksa halaman Pesanan sebelum mengulang.'
            : hasil.pesanGagal);
      }
    } on CheckoutDitolak catch (e) {
      setState(() => _galat = e.pesan);
    } on ApiException catch (e) {
      setState(() => _galat = e.pesan);
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasil != null) return _layarSukses(_hasil!);

    final keranjang = Keranjang.instance;
    final kelompok = keranjang.kelompokPerToko();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keranjang'),
        actions: [
          if (keranjang.items.isNotEmpty)
            IconButton(
              tooltip: 'Kosongkan keranjang',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => keranjang.kosongkan(),
            ),
        ],
      ),
      body: keranjang.items.isEmpty
          ? const Center(child: Text('Keranjang masih kosong.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final entri in kelompok.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Row(children: [
                      const Icon(Icons.store_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        entri.value.first.namaToko.isEmpty
                            ? 'Toko ${entri.key}'
                            : entri.value.first.namaToko,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ]),
                  ),
                  for (final item in entri.value)
                    _barisItem(keranjang.items.indexOf(item)),
                ],
                const Divider(height: 28),
                _ringkasan(),
                const SizedBox(height: 14),
                if (Sesi.instance.aktifkanPilihanMeja) ...[
                  _pilihanMeja(),
                  const SizedBox(height: 14),
                ],
                _pilihanCaraBayar(),
                const SizedBox(height: 12),
                TextField(
                  controller: _keterangan,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan untuk penjual (opsional)',
                    hintText: 'mis. tidak pedas, es sedikit',
                  ),
                ),
                if (_galat != null) ...[
                  const SizedBox(height: 14),
                  PanelGalat(pesan: _galat!),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _memproses ? null : _checkout,
                  icon: _memproses
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.payments_outlined),
                  label: Text(_memproses
                      ? 'Memproses transaksi...'
                      : 'Bayar ${rupiah(keranjang.grandTotal)}'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _barisItem(int index) {
    final keranjang = Keranjang.instance;
    if (index < 0 || index >= keranjang.items.length) {
      return const SizedBox.shrink();
    }
    final item = keranjang.items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.nama,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${rupiah(item.harga)} x ${item.jumlah}',
                      style: const TextStyle(fontSize: 12)),
                  if (item.diskon > 0)
                    Text('Diskon ${rupiah(item.diskon)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.green)),
                  if (item.cashback > 0)
                    Text(
                        '${Sesi.instance.labelCashback} ${rupiah(item.cashback)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.orange)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => keranjang.ubahJumlah(index, -1),
            ),
            Text('${item.jumlah}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => keranjang.ubahJumlah(index, 1),
            ),
            SizedBox(
              width: 92,
              child: Text(
                rupiah(item.totalSetelahDiskon),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ringkasan() {
    final k = Keranjang.instance;
    Widget baris(String label, String nilai, {bool tebal = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: tebal ? FontWeight.bold : FontWeight.normal)),
              Text(nilai,
                  style: TextStyle(
                      fontWeight: tebal ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        );

    return Column(
      children: [
        baris('Subtotal', rupiah(k.subtotal)),
        if (k.totalDiskon > 0) baris('Diskon', '- ${rupiah(k.totalDiskon)}'),
        baris('Total tagihan', rupiah(k.grandTotal), tebal: true),
        if (k.totalCashback > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${Sesi.instance.labelCashback} yang akan Anda terima: '
              '${rupiah(k.totalCashback)} (tidak mengurangi tagihan)',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
      ],
    );
  }

  Widget _pilihanMeja() {
    final k = Keranjang.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Meja / Pengambilan',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: k.bawaPulang,
              title: const Text('Bawa pulang (tanpa meja)'),
              onChanged: (v) => k.setBawaPulang(v == true),
            ),
            if (!k.bawaPulang)
              Row(
                children: [
                  Expanded(
                    child: Text(k.namaMeja == null
                        ? 'Belum memilih meja'
                        : 'Meja: ${k.namaMeja}'),
                  ),
                  if (k.namaMeja != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: k.hapusMeja,
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final hasil = await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PindaiMejaScreen()));
                      if (hasil is Map) {
                        k.pilihMeja('${hasil['id']}', '${hasil['nama']}');
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Scan QR Meja'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _pilihanCaraBayar() {
    if (_memuatCaraBayar) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_caraBayar.isEmpty) {
      return const PanelGalat(
        pesan: 'Belum ada saluran pembayaran yang diizinkan untuk jenis '
            'keanggotaan Anda. Hubungi pengelola kantin.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _idCaraBayar,
          decoration: const InputDecoration(labelText: 'Saluran pembayaran'),
          items: _caraBayar
              .map((c) => DropdownMenuItem(
                    value: '${c['id']}',
                    child: Text('${c['nama'] ?? ''}'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _idCaraBayar = v),
        ),
        if (_idCaraBayar != null) ...[
          const SizedBox(height: 6),
          Text(
            _manualTerpilih
                ? 'Pesanan disimpan sebagai draft. Selesaikan pembayaran di '
                    'kasir/toko yang bersangkutan.'
                : 'Tagihan dipotong langsung dari ${Sesi.instance.labelSaldo} Anda.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  Widget _layarSukses(HasilCheckout h) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi Berhasil')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 76, color: Colors.green),
              const SizedBox(height: 14),
              const Text('Transaksi Berhasil',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                h.manual
                    ? 'Pesanan telah dibuat. Silakan selesaikan pembayaran di '
                        'kasir/toko yang bersangkutan.'
                    : 'Pesanan Anda telah diteruskan ke penjual dan '
                        '${Sesi.instance.labelSaldo} Anda telah disesuaikan.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              Text('Total tagihan',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              Text(rupiah(h.total),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Selesai & Ke Beranda'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
