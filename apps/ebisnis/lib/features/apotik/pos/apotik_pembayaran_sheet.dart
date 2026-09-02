import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Satu metode pembayaran sebagaimana dikirim `apotik_cara_bayar_list`.
///
/// [adaKembalian] adalah SATU-SATUNYA penentu apakah kolom "uang diterima"
/// dan kembalian boleh muncul. Sebelum server mengirim flag ini, klien harus
/// menebak dari nama ("tunai") — tebakan yang salah untuk metode tunai yang
/// dinamai lain. Server lama yang belum mengirimnya menghasilkan `false`,
/// sehingga kasir cukup memilih metode tanpa layar kembalian; tidak ada yang
/// dikarang.
class MetodeBayar {
  final int? id;
  final String kode;
  final String nama;
  final bool adaKembalian;
  final bool manual;
  final bool online;

  const MetodeBayar({
    required this.id,
    this.kode = '',
    this.nama = '',
    this.adaKembalian = false,
    this.manual = true,
    this.online = false,
  });

  factory MetodeBayar.dariJson(Map<String, dynamic> j) => MetodeBayar(
        id: (j['id'] as num?)?.toInt(),
        kode: '${j['kode'] ?? ''}',
        nama: '${j['nama'] ?? ''}',
        adaKembalian: j['adaKembalian'] == true,
        manual: j['manual'] != false,
        online: j['online'] == true,
      );
}

/// Satu baris pembayaran (IR-11). Satu transaksi boleh dibayar dengan lebih
/// dari satu metode — mis. sebagian tunai, sisanya QRIS.
class BarisBayar {
  MetodeBayar metode;

  /// Nominal yang DIBUKUKAN untuk metode ini.
  double nominal;

  /// Uang tunai yang diserahkan pembeli; hanya bermakna pada metode yang
  /// memberi kembalian.
  double tunai;
  String referensi;

  BarisBayar({
    required this.metode,
    this.nominal = 0,
    this.tunai = 0,
    this.referensi = '',
  });

  double get kembalian {
    if (!metode.adaKembalian) return 0;
    final k = tunai - nominal;
    return k > 0 ? k : 0;
  }

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'cara_bayar_id': metode.id,
        'nominal': nominal,
        if (metode.adaKembalian) 'tunai': tunai,
        if (metode.adaKembalian) 'kembalian': kembalian,
        if (referensi.trim().isNotEmpty) 'referensi': referensi.trim(),
      };
}

/// Hasil lembar pembayaran; dikembalikan ke POS untuk dikirim ke server.
class HasilPembayaran {
  final int? caraBayarId;
  final String namaMetode;
  final String referensi;

  /// Uang yang diterima kasir dan kembaliannya. Sejak IR-11 keduanya
  /// **dibukukan server** pada baris pembayaran.
  final double tunai;
  final double kembalian;
  final bool bukaLaci;

  /// Rincian pembayaran; berisi satu baris pada pembayaran biasa dan lebih
  /// dari satu bila kasir memecahnya.
  final List<BarisBayar> baris;

  const HasilPembayaran({
    required this.caraBayarId,
    this.namaMetode = '',
    this.referensi = '',
    this.tunai = 0,
    this.kembalian = 0,
    this.bukaLaci = false,
    this.baris = const [],
  });

  bool get terpisah => baris.length > 1;

  /// Payload larik `pembayaran` untuk `apotik_bayar`.
  List<Map<String, dynamic>> payloadPembayaran() =>
      [for (final b in baris) b.toPayload()];
}

/// Pemeriksaan pra-kirim pembayaran.
class PagarPembayaran {
  final bool boleh;
  final List<String> alasan;
  final List<String> peringatan;
  const PagarPembayaran(this.boleh, this.alasan, this.peringatan);
}

/// <h3>Lembar pembayaran POS Apotik (Fase 6).</h3>
///
/// Sejak **IR-11** (AIS r83255) server membukukan pembayaran per BARIS:
/// metode, nominal, uang diterima, kembalian, dan referensi. Karena itu satu
/// transaksi boleh dibayar dengan lebih dari satu metode, dan kembalian yang
/// ditampilkan di sini benar-benar tersimpan — bukan sekadar hitungan layar
/// seperti sebelumnya.
///
/// **Pagar yang tidak boleh dilonggarkan:** jumlah seluruh baris harus sama
/// dengan total. Server menolak selisih apa pun; layar menahannya lebih dulu
/// supaya kasir melihat sisa yang belum terbagi sebelum mengirim.
class ApotikPembayaranSheet extends StatefulWidget {
  final double total;
  final List<MetodeBayar> metode;
  final int? metodeAwalId;

  /// Laci kasir hanya ada di desktop Windows; pemanggil mematikan opsinya di
  /// platform lain supaya kasir tidak ditawari tombol yang pasti gagal.
  final bool laciTersedia;

  const ApotikPembayaranSheet({
    super.key,
    required this.total,
    required this.metode,
    this.metodeAwalId,
    this.laciTersedia = false,
  });

  @override
  State<ApotikPembayaranSheet> createState() => _ApotikPembayaranSheetState();

  /// Pagar pra-kirim sebagai fungsi MURNI agar seluruh aturannya dapat diuji
  /// tanpa merakit widget.
  static PagarPembayaran periksa({
    required double total,
    required MetodeBayar? metode,
    required double tunai,
    required String referensi,
  }) {
    final alasan = <String>[];
    final peringatan = <String>[];
    if (total <= 0) {
      alasan.add('Total transaksi 0 — tidak ada yang perlu dibayar.');
    }
    if (metode != null && metode.adaKembalian) {
      if (tunai < total) {
        alasan.add('Uang diterima kurang ${_rp.format(total - tunai)} '
            'dari total.');
      }
    }
    if (metode != null && !metode.adaKembalian && referensi.trim().isEmpty) {
      // Server menerima referensi kosong, jadi ini TIDAK boleh menahan; tetapi
      // tanpa nomor referensi pembayaran non-tunai praktis mustahil
      // direkonsiliasi dengan mutasi bank/EDC saat tutup buku.
      peringatan.add('${metode.nama}: tanpa nomor referensi, pembayaran ini '
          'sulit dicocokkan saat rekonsiliasi.');
    }
    return PagarPembayaran(alasan.isEmpty, alasan, peringatan);
  }

  /// Pagar pembayaran TERPISAH (IR-11). Aturan pentingnya: jumlah seluruh
  /// baris harus sama persis dengan total. Server menolak selisih apa pun,
  /// dan menahannya di sini membuat kasir melihat sisanya sebelum mengirim.
  static PagarPembayaran periksaSplit({
    required double total,
    required List<BarisBayar> baris,
  }) {
    final alasan = <String>[];
    final peringatan = <String>[];
    if (total <= 0) {
      alasan.add('Total transaksi 0 — tidak ada yang perlu dibayar.');
    }
    if (baris.isEmpty) {
      alasan.add('Belum ada baris pembayaran.');
      return PagarPembayaran(false, alasan, peringatan);
    }
    var jumlah = 0.0;
    for (final b in baris) {
      jumlah += b.nominal;
      if (b.nominal <= 0) {
        alasan.add('${b.metode.nama}: nominal harus lebih dari 0.');
      }
      if (b.metode.adaKembalian && b.tunai < b.nominal) {
        alasan.add('${b.metode.nama}: uang diterima kurang '
            '${_rp.format(b.nominal - b.tunai)} dari nominalnya.');
      }
      if (!b.metode.adaKembalian && b.referensi.trim().isEmpty) {
        peringatan.add('${b.metode.nama}: tanpa nomor referensi, pembayaran '
            'ini sulit dicocokkan saat rekonsiliasi.');
      }
    }
    final selisih = jumlah - total;
    if (selisih.abs() > 0.5) {
      alasan.add(selisih < 0
          ? 'Pembayaran kurang ${_rp.format(-selisih)} dari total.'
          : 'Pembayaran lebih ${_rp.format(selisih)} dari total. Kelebihan '
              'uang tunai adalah KEMBALIAN, bukan nominal yang dibukukan.');
    }
    return PagarPembayaran(alasan.isEmpty, alasan, peringatan);
  }

  /// Pecahan uang yang wajar ditawarkan di atas [total] (uang pas + pembulatan
  /// ke atas). Murni untuk mempercepat kasir; tidak ada aturan bisnis di sini.
  static List<double> saranTunai(double total) {
    if (total <= 0) return const <double>[];
    final saran = <double>{total};
    for (final kelipatan in const [5000, 10000, 50000, 100000]) {
      final bulat = (total / kelipatan).ceil() * kelipatan.toDouble();
      if (bulat > total) saran.add(bulat);
    }
    for (final lembar in const [50000.0, 100000.0]) {
      if (lembar > total) saran.add(lembar);
    }
    final urut = saran.toList()..sort();
    return urut.take(5).toList();
  }
}

class _ApotikPembayaranSheetState extends State<ApotikPembayaranSheet> {
  late MetodeBayar? _metode = widget.metode.isEmpty
      ? null
      : widget.metode.firstWhere((m) => m.id == widget.metodeAwalId,
          orElse: () => widget.metode.first);

  final _tunai = TextEditingController();
  final _referensi = TextEditingController();
  bool _bukaLaci = true;

  /// Mode terpisah (IR-11). Default MATI: mayoritas transaksi apotek dibayar
  /// dengan satu metode, dan menampilkan daftar baris untuk kasus itu hanya
  /// memperlambat kasir.
  bool _terpisah = false;
  final List<BarisBayar> _baris = [];

  void _mulaiTerpisah() {
    _baris
      ..clear()
      // Baris pertama mewarisi metode & uang yang sudah diisi kasir, supaya
      // beralih ke mode terpisah tidak menghapus pekerjaannya.
      ..add(BarisBayar(
        metode: _metode ?? widget.metode.first,
        nominal: widget.total,
        tunai: _nilaiTunai,
        referensi: _referensi.text.trim(),
      ));
    _terpisah = true;
  }

  /// Sisa yang belum tertutup baris mana pun.
  double get _sisa {
    final jumlah = _baris.fold<double>(0, (a, b) => a + b.nominal);
    final sisa = widget.total - jumlah;
    return sisa.abs() < 0.5 ? 0 : sisa;
  }

  void _tambahBaris() {
    final terpakai = _baris.map((b) => b.metode.id).toSet();
    final berikut = widget.metode.firstWhere((m) => !terpakai.contains(m.id),
        orElse: () => widget.metode.first);
    final sisa = _sisa;
    setState(() => _baris.add(BarisBayar(
          metode: berikut,
          nominal: sisa > 0 ? sisa : 0,
          tunai: berikut.adaKembalian && sisa > 0 ? sisa : 0,
        )));
  }

  @override
  void dispose() {
    _tunai.dispose();
    _referensi.dispose();
    super.dispose();
  }

  double get _nilaiTunai =>
      double.tryParse(_tunai.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  double get _kembalian {
    if (_metode == null || !_metode!.adaKembalian) return 0;
    final k = _nilaiTunai - widget.total;
    return k > 0 ? k : 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final pagar = _terpisah
        ? ApotikPembayaranSheet.periksaSplit(total: widget.total, baris: _baris)
        : ApotikPembayaranSheet.periksa(
            total: widget.total,
            metode: _metode,
            tunai: _nilaiTunai,
            referensi: _referensi.text,
          );
    final tunaiAktif = !_terpisah && _metode != null && _metode!.adaKembalian;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: t.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Lihat catatan yang sama pada panel keranjang: nominal turun
              // ke baris sendiri saat skala teks membesar.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text('Pembayaran',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary)),
                  Text(_rp.format(widget.total),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: t.primary)),
                ],
              ),
              const SizedBox(height: 14),
              if (widget.metode.isEmpty)
                _catatan(
                    t,
                    Icons.info_outline,
                    'Server belum mengirim daftar metode pembayaran. '
                    'Transaksi tetap dapat dibukukan, tetapi metodenya '
                    'tidak akan tercatat.')
              else if (_terpisah) ...[
                Row(children: [
                  Expanded(
                    child: Text('Pembayaran terpisah',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.textSecondary)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _terpisah = false),
                    child: const Text('Kembali ke satu metode'),
                  ),
                ]),
                const SizedBox(height: 6),
                for (var i = 0; i < _baris.length; i++) _kartuBaris(t, i),
                Row(children: [
                  Expanded(
                    child: Text(
                      _sisa == 0
                          ? 'Seluruh total sudah terbagi.'
                          : _sisa > 0
                              ? 'Sisa belum terbagi ${_rp.format(_sisa)}'
                              : 'Kelebihan ${_rp.format(-_sisa)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _sisa == 0 ? t.successText : t.warningText),
                    ),
                  ),
                  if (widget.metode.length > 1)
                    TextButton.icon(
                      onPressed: _tambahBaris,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Tambah metode'),
                    ),
                ]),
              ] else ...[
                Text('Metode',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in widget.metode)
                      ChoiceChip(
                        label: Text(m.nama.isEmpty ? '(tanpa nama)' : m.nama),
                        selected: _metode?.id == m.id,
                        onSelected: (_) => setState(() {
                          _metode = m;
                          if (!m.adaKembalian) _tunai.clear();
                        }),
                      ),
                  ],
                ),
                if (widget.metode.length > 1)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(_mulaiTerpisah),
                      icon: const Icon(Icons.call_split, size: 16),
                      label: const Text('Bayar terpisah'),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              if (tunaiAktif) ..._bagianTunai(t),
              if (!_terpisah && _metode != null && !_metode!.adaKembalian) ...[
                TextField(
                  controller: _referensi,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nomor referensi / approval',
                    hintText: 'mis. nomor approval EDC atau berita transfer',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (pagar.alasan.isNotEmpty)
                _kotakPesan(t, pagar.alasan, galat: true),
              if (pagar.peringatan.isNotEmpty)
                _kotakPesan(t, pagar.peringatan, galat: false),
              if (widget.laciTersedia && tunaiAktif)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Buka laci kasir setelah bayar'),
                  value: _bukaLaci,
                  onChanged: (v) => setState(() => _bukaLaci = v),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: ApotikBreakpoints.targetSentuhMinimum,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: ApotikBreakpoints.targetSentuhMinimum,
                    child: FilledButton.icon(
                      onPressed: pagar.boleh ? _selesai : null,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(tunaiAktif && _kembalian > 0
                          ? 'Bayar — kembali ${_rp.format(_kembalian)}'
                          : 'Bayar'),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bagianTunai(ApotikDesignTokens t) {
    return [
      TextField(
        controller: _tunai,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Uang diterima',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in ApotikPembayaranSheet.saranTunai(widget.total))
            OutlinedButton(
              onPressed: () =>
                  setState(() => _tunai.text = s.toStringAsFixed(0)),
              child: Text(_rp.format(s)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
          border: Border.all(color: t.border),
        ),
        child: Row(children: [
          Expanded(
            child: Text('Kembalian',
                style: TextStyle(fontSize: 13, color: t.textSecondary)),
          ),
          Text(_rp.format(_kembalian),
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        'Uang diterima dan kembalian ikut dibukukan pada baris pembayaran, '
        'sehingga selisih laci dapat ditelusuri sampai transaksinya.',
        style: TextStyle(fontSize: 11, color: t.textSecondary),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _catatan(ApotikDesignTokens t, IconData ikon, String teks) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, size: 16, color: t.textSecondary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(teks,
                style: TextStyle(fontSize: 12, color: t.textSecondary))),
      ]),
    );
  }

  Widget _kotakPesan(ApotikDesignTokens t, List<String> pesan,
      {required bool galat}) {
    final warna = galat ? t.danger : t.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: warna.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(galat ? Icons.block : Icons.warning_amber_rounded,
            size: 16, color: warna),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in pesan)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(p,
                      style: TextStyle(fontSize: 12, color: t.textPrimary)),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  void _selesai() {
    final baris = _terpisah
        ? List<BarisBayar>.from(_baris)
        : <BarisBayar>[
            if (_metode != null)
              BarisBayar(
                metode: _metode!,
                nominal: widget.total,
                tunai: _metode!.adaKembalian ? _nilaiTunai : 0,
                referensi: _referensi.text.trim(),
              ),
          ];
    final adaTunai = baris.any((b) => b.metode.adaKembalian);
    Navigator.pop(
      context,
      HasilPembayaran(
        // Baris pertama tetap dikirim sebagai cara_bayar_id tunggal agar
        // server lama membukukan metode alih-alih kehilangan jejaknya.
        caraBayarId: baris.isEmpty ? null : baris.first.metode.id,
        namaMetode: baris.map((b) => b.metode.nama).join(' + '),
        referensi: baris.isEmpty ? '' : baris.first.referensi.trim(),
        tunai: baris.fold<double>(0, (a, b) => a + b.tunai),
        kembalian: baris.fold<double>(0, (a, b) => a + b.kembalian),
        bukaLaci: widget.laciTersedia && _bukaLaci && adaTunai,
        baris: baris,
      ),
    );
  }

  /// Satu baris pembayaran pada mode terpisah.
  Widget _kartuBaris(ApotikDesignTokens t, int i) {
    final b = _baris[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: b.metode.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Metode',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                for (final m in widget.metode)
                  DropdownMenuItem<int>(
                      value: m.id,
                      child: Text(m.nama, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                b.metode = widget.metode
                    .firstWhere((m) => m.id == v, orElse: () => b.metode);
                if (!b.metode.adaKembalian) b.tunai = 0;
              }),
            ),
          ),
          if (_baris.length > 1)
            IconButton(
              tooltip: 'Hapus baris ini',
              onPressed: () => setState(() => _baris.removeAt(i)),
              icon: const Icon(Icons.close, size: 18),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: b.nominal == 0 ? '' : b.nominal.toStringAsFixed(0),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Nominal dibukukan',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (v) => setState(() {
                b.nominal = double.tryParse(v) ?? 0;
                if (!b.metode.adaKembalian) b.tunai = b.nominal;
              }),
            ),
          ),
          if (b.metode.adaKembalian) ...[
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: b.tunai == 0 ? '' : b.tunai.toStringAsFixed(0),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: const InputDecoration(
                    labelText: 'Uang diterima',
                    border: OutlineInputBorder(),
                    isDense: true),
                onChanged: (v) =>
                    setState(() => b.tunai = double.tryParse(v) ?? 0),
              ),
            ),
          ],
        ]),
        if (!b.metode.adaKembalian) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: b.referensi,
            decoration: const InputDecoration(
                labelText: 'Nomor referensi / approval',
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: (v) => setState(() => b.referensi = v),
          ),
        ],
        if (b.kembalian > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Kembalian ${_rp.format(b.kembalian)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
            ),
          ),
      ]),
    );
  }
}
