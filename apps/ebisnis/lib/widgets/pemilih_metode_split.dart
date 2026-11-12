import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';

/// Satu alokasi pembayaran pada transaksi yang memakai satu atau beberapa
/// metode. Nominal slot pertama tetap dikirim eksplisit oleh klien; server akan
/// menyimpannya sebagai sisa total setelah slot 2-5 agar kompatibel dengan
/// model transaksi lama.
class SlotBayar {
  final CaraBayar caraBayar;
  double nominal;

  SlotBayar(this.caraBayar, this.nominal);

  SlotBayar salin() => SlotBayar(caraBayar, nominal);
}

/// Pembanding kanonis (permanen/paten) untuk mengurutkan metode pembayaran pada
/// tampilan dan penyimpanan Split Payment di seluruh permukaan POS (Desktop,
/// Android, dan Koreksi Transaksi), selaras dengan `bandingkanCaraBayarSplitPaten`
/// di `KantinHelper.java` serta `kantin_pos_split_helper.js` pada Web POS.
///
/// **Mengapa urutan ini WAJIB dikunci (tidak boleh mengikuti urutan klik):**
/// Sebelumnya slot ditambahkan secara kronologis (`_terpilih.add(...)`). Bila
/// transaksi sebelumnya memakai `Voucher Pejuang`, maka `Voucher Pejuang` muncul
/// di baris atas dan `Tunai` di bawah; bila transaksi sebelumnya memakai `Tunai`,
/// posisinya terbalik (`Tunai` di atas, `Voucher Pejuang` di bawah). Kasir yang
/// bekerja cepat mengandalkan ingatan posisi tangan (*muscle memory*) sehingga
/// nominal voucher ratusan ribu terketik ke kolom `Tunai` dan menyebabkan
/// selisih uang fisik di laci kasir saat tutup shift.
///
/// **Aturan urutan paten (deterministik 100%):**
/// 1. Metode uang fisik tunai (`adalahTunai` / `adaKembalian == true`, seperti
///    `Tunai`) **SELALU terkunci di urutan paling atas (Baris #1)** kapan pun
///    `Tunai` ikut dipilih, baik dipasangkan dengan `Voucher Pejuang`, `QRIS`,
///    `Transfer`, `EDC`, maupun `Kasbon`.
/// 2. Seluruh metode non-tunai (Voucher, QRIS, Transfer, Saldo, Kasbon) selalu
///    berada **di bawah Tunai**, diurutkan tetap berdasarkan abjad nama metode
///    (`nama.trim().toLowerCase()` ASC), lalu `id` ASC sebagai pemutus seri.
int bandingkanCaraBayarSplitPaten(CaraBayar a, CaraBayar b) {
  if (a.adalahTunai != b.adalahTunai) {
    return a.adalahTunai ? -1 : 1;
  }
  final urutNama =
      a.nama.trim().toLowerCase().compareTo(b.nama.trim().toLowerCase());
  if (urutNama != 0) return urutNama;
  return a.id.compareTo(b.id);
}

/// Mengembalikan salinan daftar [SlotBayar] yang sudah diurutkan mengikuti
/// aturan posisi paten [bandingkanCaraBayarSplitPaten] tanpa mengubah nominal
/// yang sudah melekat pada masing-masing metode.
List<SlotBayar> urutkanSlotSplitPaten(Iterable<SlotBayar> slot) {
  final hasil = slot.map((s) => s.salin()).toList();
  hasil.sort((a, b) => bandingkanCaraBayarSplitPaten(a.caraBayar, b.caraBayar));
  return hasil;
}

/// Kategori visual ringkas untuk memberi lencana warna tegas pada baris metode
/// pembayaran agar kasir langsung membedakan uang fisik laci vs voucher/non-tunai.
String labelKategoriCaraBayar(CaraBayar cara) {
  if (cara.adalahTunai) return 'TUNAI • LACI KAS';
  if (cara.masukSebagaiHutang) return 'PIUTANG / KASBON';
  if (cara.memotongDepositEfektif) return 'SALDO MEMBER';
  return 'NON-TUNAI / VOUCHER';
}

/// Validasi bersama untuk checkout dan koreksi transaksi. Toleransi Rp 1
/// mengikuti kontrak server untuk selisih pembulatan angka desimal.
String? validasiAlokasiPembayaran(Iterable<SlotBayar> slot, double total) {
  final daftar = slot.toList();
  if (daftar.isEmpty) return 'Pilih sedikitnya satu metode pembayaran.';
  if (daftar.length > 5) return 'Maksimal 5 metode pembayaran per transaksi.';
  final id = <int>{};
  for (var i = 0; i < daftar.length; i++) {
    final baris = daftar[i];
    if (!id.add(baris.caraBayar.id)) {
      return 'Metode ${baris.caraBayar.nama} dipilih lebih dari satu kali.';
    }
    if (!baris.nominal.isFinite || baris.nominal <= 0) {
      return 'Nominal ${baris.caraBayar.nama} (baris ke-${i + 1}) harus lebih dari Rp 0.';
    }
  }
  final dialokasikan =
      daftar.fold<double>(0, (jumlah, baris) => jumlah + baris.nominal);
  if ((dialokasikan - total).abs() >= 1) {
    final rupiah =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return 'Total alokasi ${rupiah.format(dialokasikan)} harus sama dengan '
        'total transaksi ${rupiah.format(total)}.';
  }
  return null;
}

/// Pemilih pembayaran bersama untuk checkout dan koreksi transaksi. Ketuk
/// baris untuk satu metode penuh, atau centang beberapa metode dan isi nominal
/// masing-masing sampai total alokasi seimbang.
///
/// Dilengkapi 3 pengaman anti salah-input bagi kasir:
/// 1. **Posisi Baris Paten ([urutkanSlotSplitPaten])**: Urutan baris pada bagian
///    `Bagi Nominal per Metode` selalu terkunci (`Tunai` selalu Baris #1 di atas,
///    `Voucher` / `Non-Tunai` selalu di bawahnya), tidak peduli metode mana yang
///    dicentang lebih dulu atau metode apa yang aktif pada transaksi sebelumnya.
/// 2. **Hitung Otomatis Selisih (Auto-Remainder)**: Pada split 2 metode, begitu
///    kasir mengetik nominal di salah satu kotak (mis. mengetik nominal Voucher
///    di baris bawah), kotak pasangannya (`Tunai` di baris atas) otomatis terisi
///    sisa `total - nominal` tanpa hitung manual. Untuk split 3–5 metode tersedia
///    tombol sekali klik `Isi sisa` pada baris yang diinginkan.
/// 3. **Penanda Visual Tegas**: Nomor urut terkunci (`1`, `2`, ...) disertai
///    lencana warna `TUNAI • LACI KAS` vs `NON-TUNAI / VOUCHER`.
class PemilihMetodeSplit extends StatefulWidget {
  final List<CaraBayar> daftarMetode;
  final List<SlotBayar> terpilihAwal;
  final double total;

  /// Muat ulang daftar metode dari server tanpa menutup sheet.
  final Future<List<CaraBayar>?> Function()? muatUlang;

  const PemilihMetodeSplit({
    super.key,
    required this.daftarMetode,
    required this.terpilihAwal,
    required this.total,
    this.muatUlang,
  });

  @override
  State<PemilihMetodeSplit> createState() => _PemilihMetodeSplitState();
}

class _PemilihMetodeSplitState extends State<PemilihMetodeSplit> {
  late List<SlotBayar> _terpilih;
  late List<CaraBayar> _metode;
  final Map<int, TextEditingController> _controllers = {};
  bool _menyinkron = false;

  @override
  void initState() {
    super.initState();
    _metode = List<CaraBayar>.of(widget.daftarMetode);
    _terpilih = urutkanSlotSplitPaten(widget.terpilihAwal);
    _sinkronkanSemuaController();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  TextEditingController _controllerUntuk(SlotBayar slot) {
    return _controllers.putIfAbsent(
      slot.caraBayar.id,
      () => TextEditingController(text: _formatAngkaInput(slot.nominal)),
    );
  }

  String _formatAngkaInput(double nilai) {
    if (!nilai.isFinite || nilai <= 0) return '0';
    return nilai.round().toString();
  }

  /// Menyinkronkan teks pada seluruh [TextEditingController] dengan nilai
  /// [SlotBayar.nominal] terbaru kecuali controller `idSedangDiketik` agar
  /// posisi kursor kasir tidak melompat saat sedang mengetik.
  void _sinkronkanSemuaController({int? kecualiId}) {
    final idAktif = <int>{};
    for (final slot in _terpilih) {
      idAktif.add(slot.caraBayar.id);
      final ctrl = _controllerUntuk(slot);
      if (slot.caraBayar.id == kecualiId) continue;
      final teksTarget = _formatAngkaInput(slot.nominal);
      if (ctrl.text != teksTarget) {
        ctrl.value = TextEditingValue(
          text: teksTarget,
          selection: TextSelection.collapsed(offset: teksTarget.length),
        );
      }
    }
    final hapusId =
        _controllers.keys.where((id) => !idAktif.contains(id)).toList();
    for (final id in hapusId) {
      _controllers.remove(id)?.dispose();
    }
  }

  void _urutkanPaten() {
    _terpilih.sort(
        (a, b) => bandingkanCaraBayarSplitPaten(a.caraBayar, b.caraBayar));
  }

  Future<void> _sinkronkanMetode() async {
    if (_menyinkron || widget.muatUlang == null) return;
    setState(() => _menyinkron = true);
    try {
      final baru = await widget.muatUlang!.call();
      if (!mounted) return;
      if (baru == null || baru.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Metode pembayaran tidak dapat dimuat. Periksa koneksi lalu coba lagi.')));
        return;
      }
      setState(() {
        _metode = List<CaraBayar>.of(baru);
        _terpilih
            .removeWhere((s) => !_metode.any((c) => c.id == s.caraBayar.id));
        _urutkanPaten();
        _sinkronkanSemuaController();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Daftar metode pembayaran diperbarui dari server.')));
    } finally {
      if (mounted) setState(() => _menyinkron = false);
    }
  }

  void _toggle(CaraBayar cara) {
    final index = _terpilih.indexWhere((s) => s.caraBayar.id == cara.id);
    if (index >= 0) {
      setState(() {
        _terpilih.removeAt(index);
        // Bila tersisa tepat 1 metode, kembalikan nominalnya ke total penuh
        // supaya bila kasir mencentang metode lain lagi transisinya tetap bersih.
        if (_terpilih.length == 1 && widget.total > 0) {
          _terpilih.first.nominal = widget.total;
        }
        _urutkanPaten();
        _sinkronkanSemuaController();
      });
      return;
    }
    if (_terpilih.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Maksimal 5 metode pembayaran per transaksi.')));
      return;
    }
    setState(() {
      final transisiDariMetodeTunggalPenuh = _terpilih.length == 1 &&
          widget.total > 0 &&
          (_terpilih.first.nominal - widget.total).abs() < 1;
      _terpilih.add(SlotBayar(cara, 0));
      _urutkanPaten();
      if (transisiDariMetodeTunggalPenuh ||
          _terpilih.every((s) => s.nominal == 0)) {
        _bagiRata();
      }
      _sinkronkanSemuaController();
    });
  }

  void _bagiRata() {
    if (_terpilih.length < 2 || widget.total <= 0) return;
    final banyak = _terpilih.length;
    final rata = (widget.total / banyak).floorToDouble();
    for (var i = 0; i < banyak; i++) {
      _terpilih[i].nominal =
          i == banyak - 1 ? widget.total - rata * (banyak - 1) : rata;
    }
  }

  /// Mengubah nominal satu slot saat kasir mengetik angka.
  ///
  /// Khusus ketika kasir membagi ke **2 metode** (kasus paling sering di
  /// lapangan: `Tunai` + `Voucher Pejuang` atau `Tunai` + `QRIS`), begitu kasir
  /// mengetik nominal valid yang lebih besar dari 0 dan lebih kecil dari total
  /// belanja pada salah satu kotak, kotak pasangannya **otomatis diisi dengan
  /// selisih `total - nilaiBaru`**. Kasir cukup mengetik 1 kali (misalnya
  /// mengetik nilai Voucher Rp 15.000), maka kolom Tunai otomatis menjadi
  /// Rp 3.000 tanpa risiko salah hitung atau salah kolom.
  void _ubahNominalSlot(SlotBayar slotDiedit, String teks) {
    final nilaiBaru = double.tryParse(teks) ?? 0;
    setState(() {
      slotDiedit.nominal = nilaiBaru;
      if (_terpilih.length == 2 &&
          widget.total > 0 &&
          nilaiBaru > 0 &&
          nilaiBaru < widget.total) {
        final pasangan = _terpilih.firstWhere(
          (s) => s.caraBayar.id != slotDiedit.caraBayar.id,
        );
        pasangan.nominal = (widget.total - nilaiBaru).roundToDouble();
      }
      _sinkronkanSemuaController(kecualiId: slotDiedit.caraBayar.id);
    });
  }

  /// Mengisi nominal `slot` agar tepat menutup sisa alokasi yang belum terbagi
  /// (sangat membantu ketika kasir menggabungkan 3 sampai 5 metode pembayaran).
  void _isiSisaKeSlot(SlotBayar slot) {
    final alokasiLain = _terpilih
        .where((s) => s.caraBayar.id != slot.caraBayar.id)
        .fold<double>(0, (sum, s) => sum + s.nominal);
    final target = (widget.total - alokasiLain).roundToDouble();
    if (target <= 0) return;
    setState(() {
      slot.nominal = target;
      _sinkronkanSemuaController();
    });
  }

  double get _totalDialokasikan =>
      _terpilih.fold(0.0, (jumlah, slot) => jumlah + slot.nominal);
  double get _sisa => widget.total - _totalDialokasikan;
  String? get _galat => validasiAlokasiPembayaran(_terpilih, widget.total);

  Color _warnaLencana(CaraBayar cara) {
    if (cara.adalahTunai) return const Color(0xFF1B7F3B);
    if (cara.masukSebagaiHutang) return const Color(0xFFB45309);
    if (cara.memotongDepositEfektif) return const Color(0xFF0369A1);
    return const Color(0xFF4338CA);
  }

  IconData _ikonCaraBayar(CaraBayar cara) {
    if (cara.adalahTunai) return Icons.payments_outlined;
    if (cara.masukSebagaiHutang) return Icons.receipt_long_outlined;
    if (cara.memotongDepositEfektif) return Icons.account_balance_wallet_outlined;
    return Icons.confirmation_number_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final rupiah =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Ketuk baris untuk bayar penuh dengan 1 metode, atau centang kotak untuk menggabungkan sampai 5 metode.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (widget.muatUlang != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _menyinkron ? null : _sinkronkanMetode,
                      icon: _menyinkron
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync, size: 16),
                      label: const Text('Sinkronkan cara pembayaran'),
                    ),
                  ),
                ),
              ..._metode.map((cara) {
                final aktif = _terpilih.any((s) => s.caraBayar.id == cara.id);
                return ListTile(
                  dense: true,
                  leading: Checkbox(
                    value: aktif,
                    onChanged: (_) => _toggle(cara),
                  ),
                  title: Text(cara.nama),
                  trailing: cara.adalahTunai
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B7F3B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Posisi #1',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B7F3B),
                            ),
                          ),
                        )
                      : null,
                  onTap: () => Navigator.of(context)
                      .pop([SlotBayar(cara, widget.total)]),
                );
              }),
              if (_terpilih.length >= 2) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 16, color: Color(0xFF1B7F3B)),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Bagi Nominal per Metode (Urutan Terkunci)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        'Total ${rupiah.format(widget.total)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    _terpilih.length == 2
                        ? 'Posisi paten: Tunai selalu di atas, Voucher/Non-Tunai selalu di bawah. Ketik salah satu nominal, sisanya dihitung otomatis.'
                        : 'Posisi paten: Tunai selalu di atas, metode lainnya berurutan tetap di bawah.',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                ...List.generate(_terpilih.length, (idx) {
                  final slot = _terpilih[idx];
                  final cara = slot.caraBayar;
                  final warna = _warnaLencana(cara);
                  final alokasiLain = _totalDialokasikan - slot.nominal;
                  final targetSisa = (widget.total - alokasiLain).roundToDouble();
                  final bisaIsiSisa =
                      _sisa.abs() >= 1 && targetSisa > 0 && (targetSisa - slot.nominal).abs() >= 1;
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: warna.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: warna,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cara.nama,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_ikonCaraBayar(cara),
                                      size: 12, color: warna),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      labelKategoriCaraBayar(cara),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: warna,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (bisaIsiSisa) ...[
                          const SizedBox(width: 6),
                          TextButton(
                            key: ValueKey('isi-sisa-split-${cara.id}'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _isiSisaKeSlot(slot),
                            child: const Text('Isi sisa',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ],
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 145,
                          child: TextFormField(
                            key: ValueKey('nominal-split-${cara.id}'),
                            controller: _controllerUntuk(slot),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            decoration: const InputDecoration(
                              prefixText: 'Rp ',
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                            ),
                            onTap: () {
                              final ctrl = _controllerUntuk(slot);
                              ctrl.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: ctrl.text.length,
                              );
                            },
                            onChanged: (nilai) => _ubahNominalSlot(slot, nilai),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sisa belum dialokasikan',
                          style: TextStyle(fontSize: 12)),
                      Text(
                        rupiah.format(_sisa),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _galat == null ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_galat != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(_galat!,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: ElevatedButton(
                    onPressed: _galat == null
                        ? () => Navigator.of(context)
                            .pop(urutkanSlotSplitPaten(_terpilih))
                        : null,
                    child: const Text('Terapkan Split Pembayaran'),
                  ),
                ),
              ] else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
