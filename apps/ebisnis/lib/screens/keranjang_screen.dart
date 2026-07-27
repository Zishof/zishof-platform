import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import 'struk_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar Keranjang + Checkout -- menerima referensi list yang SAMA dengan
/// KasirScreen (bukan salinan), jadi perubahan qty/hapus di sini otomatis
/// tercermin balik ke KasirScreen begitu layar ini ditutup.
///
/// Alur checkout (padanan pos-renderer.js, minus fitur khusus hardware
/// Desktop -- cetak struk/laci-kasir/layar-pelanggan sengaja ditunda, lihat
/// task #178-180): pilih member (opsional) -> evaluasi diskon otomatis
/// (debounced) -> gerbang PIN bila member wajib-PIN -> bayar offline-first
/// (tulis lokal dulu, baru coba server; gagal jaringan TIDAK membatalkan
/// transaksi, hanya menunda sinkronisasinya).
class KeranjangScreen extends StatefulWidget {
  final List<ItemKeranjang> keranjang;
  const KeranjangScreen({super.key, required this.keranjang});

  @override
  State<KeranjangScreen> createState() => _KeranjangScreenState();
}

class _KeranjangScreenState extends State<KeranjangScreen> {
  CaraBayar? _caraBayarTerpilih;
  bool _memproses = false;
  Anggota? _memberTerpilih;
  double? _saldoMember;
  Timer? _debounceDiskon;

  @override
  void initState() {
    super.initState();
    if (Sesi.instance.caraBayar.isNotEmpty) {
      _caraBayarTerpilih = Sesi.instance.caraBayar.first;
    }
  }

  @override
  void dispose() {
    _debounceDiskon?.cancel();
    super.dispose();
  }

  double get _subtotal => widget.keranjang.fold(0, (s, i) => s + i.subtotal);
  double get _totalDiskon => widget.keranjang.fold(0, (s, i) => s + i.diskon);
  double get _totalCashback => widget.keranjang.fold(0, (s, i) => s + i.cashback);
  double get _total => _subtotal - _totalDiskon;

  void _ubahJumlah(ItemKeranjang item, int delta) {
    setState(() {
      item.jumlah += delta;
      if (item.jumlah <= 0) {
        widget.keranjang.remove(item);
      }
    });
    _jadwalkanEvaluasiDiskon();
  }

  /// Debounce 250ms (sama seperti pos-renderer.js) supaya tidak memanggil
  /// server di setiap ketukan stepper qty -- cukup sekali setelah kasir
  /// berhenti mengubah keranjang sesaat.
  void _jadwalkanEvaluasiDiskon() {
    _debounceDiskon?.cancel();
    _debounceDiskon = Timer(const Duration(milliseconds: 250), _evaluasiDiskon);
  }

  Future<void> _evaluasiDiskon() async {
    if (widget.keranjang.isEmpty) return;
    try {
      final hasil = await ApiClient.instance.aksi('diskon_evaluasi', {
        'id_member': _memberTerpilih?.id,
        'items': widget.keranjang
            .map((i) => {'id': i.produk.id, 'harga': i.produk.hargaJual, 'jumlah': i.jumlah})
            .toList(),
      });
      final items = (hasil['items'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        for (final it in items) {
          final m = it as Map<String, dynamic>;
          final produkId = m['id'] as int;
          final baris = widget.keranjang.where((i) => i.produk.id == produkId).toList();
          if (baris.isEmpty) continue;
          baris.first
            ..diskon = (m['diskon'] as num?)?.toDouble() ?? 0
            ..cashback = (m['cashback'] as num?)?.toDouble() ?? 0
            ..aturanDiskonId = m['aturanDiskon'] as int?;
        }
      });
    } catch (_) {
      // Evaluasi diskon gagal (mis. offline) -- keranjang tetap bisa dibayar
      // tanpa diskon otomatis, bukan alasan memblokir transaksi.
    }
  }

  Future<void> _pilihMember() async {
    final terpilih = await showDialog<Anggota>(
      context: context,
      builder: (_) => const _DialogPilihMember(),
    );
    if (terpilih != null) {
      setState(() {
        _memberTerpilih = terpilih;
        _saldoMember = null;
      });
      _jadwalkanEvaluasiDiskon();
      try {
        final hasil = await ApiClient.instance.aksi('saldo_member', {'id_member': terpilih.id});
        if (mounted) setState(() => _saldoMember = (hasil['data'] as num?)?.toDouble());
      } catch (_) {
        // Saldo tak terambil (mis. offline) -- bukan alasan membatalkan pemilihan member.
      }
    }
  }

  void _hapusMember() {
    setState(() {
      _memberTerpilih = null;
      _saldoMember = null;
    });
    _jadwalkanEvaluasiDiskon();
  }

  Future<bool> _verifikasiPinJikaPerlu() async {
    final member = _memberTerpilih;
    if (member == null || !member.wajibPin) return true;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogMasukkanPin(),
    );
    if (pin == null || pin.isEmpty) return false;
    try {
      final hasil = await ApiClient.instance.aksi('verifikasi_pin', {'memberId': member.id, 'pin': pin});
      final ok = hasil['ok'] == true;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN salah.')));
      }
      return ok;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      return false;
    }
  }

  String _buatKodeUnik() {
    final rand = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final acak = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'EBISNIS-${DateTime.now().millisecondsSinceEpoch}-$acak';
  }

  String _formatWaktuServer(DateTime d) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${pad(d.day)}-${pad(d.month)}-${d.year} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  Map<String, dynamic> _buatPayload(String kodeUnik, DateTime waktu) {
    return {
      'kodeUnik': kodeUnik,
      'clientTrxId': kodeUnik,
      'idToko': Sesi.instance.tokoId,
      'tokoId': Sesi.instance.tokoId,
      'kasir': Sesi.instance.userId,
      'waktu': _formatWaktuServer(waktu),
      'caraBayar': _caraBayarTerpilih!.id,
      'total': _total,
      'id_member': _memberTerpilih?.id,
      'nama_mesin': IdentitasMesin.instance.namaMesin,
      'draftPembelianAnggotaKoperasi': null,
      'transaksi': widget.keranjang
          .map((i) => {
                'id': i.produk.id,
                'kode': i.produk.kode,
                'nama': i.produk.nama,
                'harga': i.produk.hargaJual,
                'jumlah': i.jumlah,
                'diskon': i.diskon,
                'aturanDiskon': i.aturanDiskonId,
                'cashback': i.cashback,
              })
          .toList(),
    };
  }

  /// "Tahan" -- simpan keranjang sbg draft belum lunas (aksi `draft_bayar`,
  /// bentuk payload SAMA dgn `bayar`) lalu kosongkan keranjang & kembali ke
  /// Kasir. BEDA dari Bayar: TIDAK offline-first (draft yg gagal tersimpan
  /// krn offline lebih baik gagal jelas drpd diam-diam antre lokal tanpa ada
  /// layar Pesanan utk memuatnya kembali -- lihat task #184, "Muat ke
  /// Keranjang" dari draft ini menyusul setelah layar Pesanan dibangun).
  Future<void> _tahan() async {
    if (widget.keranjang.isEmpty) return;
    if (_caraBayarTerpilih == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pilih metode pembayaran terlebih dahulu.')));
      return;
    }
    setState(() => _memproses = true);
    try {
      final kodeUnik = _buatKodeUnik();
      final payload = _buatPayload(kodeUnik, DateTime.now());
      await ApiClient.instance.aksi('draft_bayar', payload);
      widget.keranjang.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Transaksi ditahan (kode: $kodeUnik).')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  Future<void> _bayar() async {
    if (widget.keranjang.isEmpty) return;
    if (_caraBayarTerpilih == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih metode pembayaran terlebih dahulu.')));
      return;
    }

    setState(() => _memproses = true);
    try {
      if (!await _verifikasiPinJikaPerlu()) return;

      final kodeUnik = _buatKodeUnik();
      final waktu = DateTime.now();
      final payload = _buatPayload(kodeUnik, waktu);

      // Offline-first: tulis PENDING lokal SEBELUM mencoba server -- kegagalan
      // jaringan di bawah tidak pernah membatalkan penjualan ini.
      await CoreDb.instance.simpanTransaksiPending(kodeUnik, jsonEncode(payload));

      String? pesanTundaMenuju;
      try {
        await ApiClient.instance.aksi('bayar', payload);
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
      } catch (e) {
        if (e is ApiException && e.offline) {
          pesanTundaMenuju = 'Tidak ada koneksi -- transaksi tersimpan & akan disinkron otomatis nanti.';
        } else {
          // Server MENOLAK (bukan sekadar offline) -- batalkan, jangan lanjut ke struk.
          await CoreDb.instance.hapusTransaksiPending(kodeUnik);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          return;
        }
      }

      if (!mounted) return;
      if (pesanTundaMenuju != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesanTundaMenuju)));
      }

      final itemStruk = widget.keranjang
          .map((i) => {'nama': i.produk.nama, 'qty': i.jumlah, 'harga': i.produk.hargaJual})
          .toList();
      final metodeNama = _caraBayarTerpilih!.nama;
      final totalStruk = _total;
      widget.keranjang.clear();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => StrukScreen(
          kode: kodeUnik,
          waktu: _formatWaktuServer(waktu),
          item: itemStruk,
          total: totalStruk,
          metode: metodeNama,
        ),
      ));
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keranjang'),
        actions: [
          if (widget.keranjang.isNotEmpty)
            TextButton.icon(
              onPressed: _memproses ? null : _tahan,
              icon: const Icon(Icons.pause_circle_outline, color: Colors.white),
              label: const Text('Tahan', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _memberTerpilih == null
                ? OutlinedButton.icon(
                    onPressed: _pilihMember,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Pilih Member (opsional)'),
                  )
                : Card(
                    color: const Color(0xFFFFF3E0),
                    child: ListTile(
                      leading: const Icon(Icons.person, color: Color(0xFF1E3A5F)),
                      title: Text(_memberTerpilih!.nama, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text([
                        if (_memberTerpilih!.kodeIdentitas.isNotEmpty) _memberTerpilih!.kodeIdentitas,
                        'Saldo: ${_saldoMember == null ? "..." : _formatRupiah.format(_saldoMember)}',
                        if (_memberTerpilih!.wajibPin) 'Wajib PIN',
                      ].join(' · ')),
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: _hapusMember),
                    ),
                  ),
          ),
          Expanded(
            child: widget.keranjang.isEmpty
                ? const Center(child: Text('Keranjang kosong.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: widget.keranjang.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = widget.keranjang[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.produk.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(_formatRupiah.format(item.produk.hargaJual), style: const TextStyle(color: Colors.black54)),
                                  if (item.diskon > 0)
                                    Text('Diskon ${_formatRupiah.format(item.diskon)}',
                                        style: const TextStyle(color: Color(0xFFC0563D), fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _ubahJumlah(item, -1)),
                            Text('${item.jumlah}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _ubahJumlah(item, 1)),
                            SizedBox(
                              width: 96,
                              child: Text(_formatRupiah.format(item.subtotalSetelahDiskon), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: widget.keranjang.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (Sesi.instance.caraBayar.isNotEmpty)
                      DropdownButtonFormField<CaraBayar>(
                        value: _caraBayarTerpilih,
                        decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder()),
                        items: Sesi.instance.caraBayar
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.nama)))
                            .toList(),
                        onChanged: (v) => setState(() => _caraBayarTerpilih = v),
                      ),
                    const SizedBox(height: 10),
                    if (_totalDiskon > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Diskon', style: TextStyle(color: Color(0xFFC0563D))),
                            Text('-${_formatRupiah.format(_totalDiskon)}', style: const TextStyle(color: Color(0xFFC0563D))),
                          ],
                        ),
                      ),
                    if (_totalCashback > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Cashback (masuk saldo)', style: TextStyle(color: Color(0xFF2E7D32))),
                            Text('+${_formatRupiah.format(_totalCashback)}', style: const TextStyle(color: Color(0xFF2E7D32))),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(_formatRupiah.format(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _memproses ? null : _bayar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _memproses
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Bayar', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Dialog cari+pilih member -- online (`cari_member`) dgn fallback offline
/// ke cache lokal (CoreDb.cariAnggotaCache) bila server tak terjangkau.
class _DialogPilihMember extends StatefulWidget {
  const _DialogPilihMember();

  @override
  State<_DialogPilihMember> createState() => _DialogPilihMemberState();
}

class _DialogPilihMemberState extends State<_DialogPilihMember> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Anggota> _hasil = [];
  bool _mencari = false;
  bool _modeOffline = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onBerubah(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _cari(v));
  }

  Future<void> _cari(String kataKunci) async {
    if (kataKunci.trim().length < 2) {
      setState(() => _hasil = []);
      return;
    }
    setState(() => _mencari = true);
    try {
      final hasil = await ApiClient.instance.aksi('cari_member', {'keyword': kataKunci});
      final arr = (hasil['member'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _hasil = arr.map((e) => Anggota.fromJson(e as Map<String, dynamic>)).toList();
          _modeOffline = false;
        });
      }
    } catch (_) {
      final cache = await CoreDb.instance.cariAnggotaCache(kataKunci);
      if (mounted) {
        setState(() {
          _hasil = cache.map(Anggota.fromCache).toList();
          _modeOffline = true;
        });
      }
    } finally {
      if (mounted) setState(() => _mencari = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Member'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Cari nama/kode identitas...', prefixIcon: Icon(Icons.search)),
              onChanged: _onBerubah,
            ),
            if (_modeOffline)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Menampilkan data cache (offline)', style: TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _mencari
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _hasil.length,
                      itemBuilder: (context, i) {
                        final a = _hasil[i];
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(a.nama),
                          subtitle: Text(a.kodeIdentitas),
                          trailing: a.wajibPin ? const Icon(Icons.pin, size: 18, color: Colors.orange) : null,
                          onTap: () => Navigator.of(context).pop(a),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
      ],
    );
  }
}

/// Dialog input PIN -- gerbang wajib sebelum Bayar bila member.wajibPin.
/// Dijalankan langsung di HP kasir (tanpa jalur "layar pelanggan"/monitor
/// kedua milik versi Desktop -- pada HP satu layar memang cukup begini).
class _DialogMasukkanPin extends StatefulWidget {
  const _DialogMasukkanPin();

  @override
  State<_DialogMasukkanPin> createState() => _DialogMasukkanPinState();
}

class _DialogMasukkanPinState extends State<_DialogMasukkanPin> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masukkan PIN Member'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Verifikasi')),
      ],
    );
  }
}
