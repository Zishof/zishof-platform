import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../services/layar_pelanggan_broadcaster.dart';
import '../theme/app_colors.dart';
import 'struk_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar Keranjang + Checkout, versi Mobile/Android -- bungkus tipis
/// `Scaffold`+`AppBar` di sekitar [PanelKeranjang] (dipush via Navigator,
/// full-screen, padanan pola lama). Di Windows Desktop, [PanelKeranjang]
/// dipakai LANGSUNG tertanam di sisi kanan `kasir_screen.dart` (padanan
/// tampilan referensi Electron: grid+keranjang berdampingan satu layar,
/// bukan navigasi terpisah) -- lihat `kasir_screen.dart` utk mode "Fokus
/// Keranjang" (F7) yg menyembunyikan grid & melebarkan panel ini.
class KeranjangScreen extends StatelessWidget {
  final List<ItemKeranjang> keranjang;
  /// Diisi bila keranjang ini dimuat ulang dari Keranjang Tertahan (layar
  /// Pesanan, "Muat ke Keranjang") -- dikirim sbg `draftPembelianAnggotaKoperasi`
  /// saat Tahan/Bayar berikutnya supaya server MEMPERBARUI draft yang sama,
  /// bukan membuat baris baru (lihat JavaDoc `_buatPayload` & KantinHelper.bayar).
  final int? draftIdSumber;
  final Anggota? memberAwal;
  const KeranjangScreen({super.key, required this.keranjang, this.draftIdSumber, this.memberAwal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: PanelKeranjang(keranjang: keranjang, draftIdSumber: draftIdSumber, memberAwal: memberAwal),
    );
  }
}

/// Isi Keranjang+Checkout (TANPA Scaffold/AppBar) -- lihat JavaDoc
/// [KeranjangScreen]. Menerima referensi list yang SAMA dengan pemanggil
/// (bukan salinan), jadi perubahan qty/hapus otomatis tercermin balik.
///
/// Alur checkout (padanan pos-renderer.js): pilih member (opsional) ->
/// evaluasi diskon otomatis (debounced) -> gerbang PIN bila member wajib-PIN
/// -> bayar offline-first (tulis lokal dulu, baru coba server; gagal jaringan
/// TIDAK membatalkan transaksi, hanya menunda sinkronisasinya).
class PanelKeranjang extends StatefulWidget {
  final List<ItemKeranjang> keranjang;
  final int? draftIdSumber;
  final Anggota? memberAwal;
  /// Header "Keranjang" + [aksiHeader] di kanannya (mis. tombol toggle Fokus
  /// Keranjang di Desktop) -- disembunyikan di Mobile krn `AppBar` pembungkus
  /// [KeranjangScreen] sudah menampilkan judul yang sama.
  final bool tampilkanJudul;
  final Widget? aksiHeader;
  /// Dipanggil setelah Tahan/Bayar sukses (keranjang baru saja dikosongkan)
  /// -- dipakai pemanggil yg TIDAK ikut navigasi pergi (mis. KasirScreen versi
  /// Desktop yg menanamkan panel ini langsung) utk menyegarkan status lain
  /// (mis. badge jumlah transaksi belum sinkron).
  final VoidCallback? onSelesai;
  const PanelKeranjang({
    super.key,
    required this.keranjang,
    this.draftIdSumber,
    this.memberAwal,
    this.tampilkanJudul = false,
    this.aksiHeader,
    this.onSelesai,
  });

  @override
  State<PanelKeranjang> createState() => _PanelKeranjangState();
}

class _PanelKeranjangState extends State<PanelKeranjang> {
  CaraBayar? _caraBayarTerpilih;
  bool _memproses = false;
  Anggota? _memberTerpilih;
  double? _saldoMember;
  Timer? _debounceDiskon;
  final _uangDiterimaController = TextEditingController(text: '0');
  bool _uangDiterimaManual = false;

  @override
  void initState() {
    super.initState();
    if (Sesi.instance.caraBayar.isNotEmpty) {
      _caraBayarTerpilih = Sesi.instance.caraBayar.first;
    }
    _memberTerpilih = widget.memberAwal;
    _sinkronkanUangDiterima();
  }

  @override
  void dispose() {
    _debounceDiskon?.cancel();
    _uangDiterimaController.dispose();
    LayarPelangganBroadcaster.instance.berhenti();
    super.dispose();
  }

  /// Siarkan isi keranjang saat ini ke Layar Pelanggan (spec §16) --
  /// dipanggil di tiap titik mutasi keranjang (qty/member/diskon), sama
  /// dgn titik panggil `_jadwalkanEvaluasiDiskon()`.
  void _siarkanKeranjang() {
    LayarPelangganBroadcaster.instance.jadwalkanKirim(
      items: widget.keranjang
          .map((i) => {
                'nama': i.produk.nama,
                'jumlah': i.jumlah,
                'harga': i.produk.hargaJual,
                'subtotal': i.subtotalSetelahDiskon,
              })
          .toList(),
      subtotal: _subtotal,
      diskon: _totalDiskon,
      total: _total,
      memberNama: _memberTerpilih?.nama,
    );
  }

  double get _subtotal => widget.keranjang.fold(0, (s, i) => s + i.subtotal);
  double get _totalDiskon => widget.keranjang.fold(0, (s, i) => s + i.diskon);
  double get _totalCashback => widget.keranjang.fold(0, (s, i) => s + i.cashback);

  /// `basisPajak = subtotal - totalDiskon`; `pajak = basisPajak * pajakPersen%`;
  /// `total = basisPajak + pajak` -- persis rumus Desktop (spesifikasi §3.3).
  /// `pajakPersen` bernilai 0 utk toko yg tak mengaktifkan PPN, jadi rumus ini
  /// otomatis identik dgn perilaku lama (tanpa pajak) tanpa perlu flag terpisah.
  double get _basisPajak => _subtotal - _totalDiskon;
  double get _pajak => _basisPajak * Sesi.instance.pajakPersen / 100;
  double get _total => _basisPajak + _pajak;

  double get _uangDiterima => double.tryParse(_uangDiterimaController.text.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;
  double get _kembalian => _uangDiterima - _total;

  /// "Uang Diterima" default = total (spec §3.4) SELAMA kasir belum mengetik
  /// nilai sendiri -- begitu kasir mengubahnya manual, berhenti auto-ikut
  /// total (mis. saat menerima uang pas beda dari total, spt uang tunai fisik
  /// yang dibulatkan).
  void _sinkronkanUangDiterima() {
    if (_uangDiterimaManual) return;
    final teks = _total > 0 ? _total.toStringAsFixed(0) : '0';
    if (_uangDiterimaController.text != teks) _uangDiterimaController.text = teks;
  }

  void _ubahJumlah(ItemKeranjang item, int delta) {
    setState(() {
      item.jumlah += delta;
      if (item.jumlah <= 0) {
        widget.keranjang.remove(item);
      }
      _sinkronkanUangDiterima();
    });
    _siarkanKeranjang();
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
        _sinkronkanUangDiterima();
      });
    } catch (_) {
      // Evaluasi diskon gagal (mis. offline) -- keranjang tetap bisa dibayar
      // tanpa diskon otomatis, bukan alasan memblokir transaksi.
    }
    _siarkanKeranjang();
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
      _siarkanKeranjang();
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
    _siarkanKeranjang();
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
      'pajak': _pajak,
      'id_member': _memberTerpilih?.id,
      'nama_mesin': IdentitasMesin.instance.namaMesin,
      'draftPembelianAnggotaKoperasi': widget.draftIdSumber,
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
  /// bentuk payload SAMA dgn `bayar`) lalu kosongkan keranjang. BEDA dari
  /// Bayar: TIDAK offline-first (draft yg gagal tersimpan krn offline lebih
  /// baik gagal jelas drpd diam-diam antre lokal tanpa ada layar Pesanan
  /// utk memuatnya kembali).
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
      LayarPelangganBroadcaster.instance.jadwalkanKirim(items: const [], subtotal: 0, diskon: 0, total: 0);
      if (!mounted) return;
      setState(() {
        _memberTerpilih = null;
        _saldoMember = null;
        _uangDiterimaManual = false;
        _uangDiterimaController.text = '0';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Transaksi ditahan (kode: $kodeUnik).')));
      widget.onSelesai?.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
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
      final pajakStruk = _pajak;
      widget.keranjang.clear();
      LayarPelangganBroadcaster.instance.jadwalkanKirim(items: const [], subtotal: 0, diskon: 0, total: 0);
      widget.onSelesai?.call();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => StrukScreen(
          kode: kodeUnik,
          waktu: _formatWaktuServer(waktu),
          item: itemStruk,
          total: totalStruk,
          metode: metodeNama,
          pajak: pajakStruk,
        ),
      ));
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  /// F4 "Pilih Metode Pembayaran" (padanan pos-renderer.js) -- di Electron
  /// tombol ini membuka picker khusus; di sini kita reuse dropdown metode
  /// yang sudah ada, cukup ditampilkan sbg bottom sheet supaya tetap ada
  /// TARGET nyata utk pintasan F4 (bukan sekadar fokus ke dropdown).
  Future<void> _pilihMetode() async {
    if (Sesi.instance.caraBayar.isEmpty) return;
    final dipilih = await showModalBottomSheet<CaraBayar>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: Sesi.instance.caraBayar
              .map((c) => ListTile(
                    title: Text(c.nama),
                    trailing: c == _caraBayarTerpilih ? const Icon(Icons.check, color: AppColors.primary) : null,
                    onTap: () => Navigator.of(context).pop(c),
                  ))
              .toList(),
        ),
      ),
    );
    if (dipilih != null) setState(() => _caraBayarTerpilih = dipilih);
  }

  /// Pintasan keyboard F2 Bayar/F3 Tahan/F4 Metode/F5 Member -- padanan
  /// pos-renderer.js `PETA_TOMBOL_KASIR` (lihat kasir_screen.dart utk
  /// F7/F8/F9). Desktop-only; diam di Android.
  KeyEventResult _tanganiTombolKeranjang(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      if (!_memproses) _bayar();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3) {
      if (!_memproses) _tahan();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f4) {
      _pilihMetode();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _pilihMember();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _tanganiTombolKeranjang,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.tampilkanJudul)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  const Text('Keranjang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (widget.aksiHeader != null) widget.aksiHeader!,
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _memberTerpilih == null
                ? OutlinedButton.icon(
                    onPressed: _pilihMember,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Pilih Member (opsional) · F5'),
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
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.border),
                        const SizedBox(height: 8),
                        const Text('Belum ada produk dipilih.', style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _pilihMetode,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Metode Pembayaran · F4', border: OutlineInputBorder(), isDense: true),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_caraBayarTerpilih?.nama ?? 'Pilih ›'),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
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
                    const Text('Subtotal', style: TextStyle(color: Colors.black54)),
                    Text(_formatRupiah.format(_subtotal), style: const TextStyle(color: Colors.black54)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Pajak (${Sesi.instance.pajakPersen.toStringAsFixed(0)}%)', style: const TextStyle(color: Colors.black54)),
                      Text(_formatRupiah.format(_pajak), style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_formatRupiah.format(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _uangDiterimaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Uang Diterima', border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) => setState(() => _uangDiterimaManual = true),
                ),
                if (_uangDiterima > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kembalian', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          _formatRupiah.format(_kembalian.abs()),
                          style: TextStyle(fontWeight: FontWeight.bold, color: _kembalian < 0 ? AppColors.danger : AppColors.success),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _memproses || widget.keranjang.isEmpty ? null : _tahan,
                        icon: const Icon(Icons.pause_circle_outline, size: 18),
                        label: const Text('Tahan · F3'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _memproses || widget.keranjang.isEmpty ? null : _bayar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _memproses
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Bayar · F2', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
  Timer? _penyegarTransaksiTerbaru;
  List<Anggota> _hasil = [];
  bool _mencari = false;
  bool _modeOffline = false;
  bool _transaksiTerbaru = false;

  @override
  void initState() {
    super.initState();
    _muatTransaksiTerbaru();
    // Segarkan tiap 20 detik SELAMA kotak cari masih kosong (spec §3.5) --
    // "pelanggan tadi" bisa berubah kalau kasir lain jg sedang transaksi.
    _penyegarTransaksiTerbaru = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_controller.text.trim().isEmpty) _muatTransaksiTerbaru();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _penyegarTransaksiTerbaru?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _muatTransaksiTerbaru() async {
    try {
      final hasil = await ApiClient.instance.aksi('anggota_transaksi_terbaru', {'id_toko': Sesi.instance.tokoId, 'limit': 10});
      final arr = (hasil['data'] as List?) ?? [];
      if (mounted && _controller.text.trim().isEmpty) {
        setState(() {
          _hasil = arr.map((e) => Anggota.fromJson(e as Map<String, dynamic>)).toList();
          _transaksiTerbaru = true;
          _modeOffline = false;
        });
      }
    } catch (_) {
      // Gagal muat "Transaksi Terbaru" (mis. offline) -- biarkan kotak cari
      // tetap kosong bukan alasan mengganggu, kasir tinggal mengetik manual.
    }
  }

  void _onBerubah(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _cari(v));
  }

  Future<void> _cari(String kataKunci) async {
    if (kataKunci.trim().length < 2) {
      if (kataKunci.trim().isEmpty) {
        await _muatTransaksiTerbaru();
      } else {
        setState(() => _hasil = []);
      }
      return;
    }
    setState(() {
      _mencari = true;
      _transaksiTerbaru = false;
    });
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
            if (_transaksiTerbaru && _hasil.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Align(alignment: Alignment.centerLeft, child: Text('Transaksi Terbaru', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))),
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
