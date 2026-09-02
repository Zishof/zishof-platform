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

/// Hasil lembar pembayaran; dikembalikan ke POS untuk dikirim ke server.
class HasilPembayaran {
  final int? caraBayarId;
  final String namaMetode;
  final String referensi;

  /// Uang yang diterima kasir. **Tidak dibukukan server** — lihat catatan
  /// pada [ApotikPembayaranSheet].
  final double tunai;
  final double kembalian;
  final bool bukaLaci;

  const HasilPembayaran({
    required this.caraBayarId,
    this.namaMetode = '',
    this.referensi = '',
    this.tunai = 0,
    this.kembalian = 0,
    this.bukaLaci = false,
  });
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
/// **Batas jujur yang harus dibaca sebelum mengubah layar ini.** Server
/// (`apotik_bayar` → `ApotikPembayaranTransaksi`) membukukan tepat tiga hal:
/// metode (`cara_bayar_id`), nominal **= total transaksi**, dan
/// `referensi_bayar`. Uang diterima dan kembalian **dihitung di kasir dan
/// tidak dikirim ke mana pun** — karena itu keduanya diberi label eksplisit di
/// layar, bukan ditampilkan seolah-olah tersimpan. Pembayaran terpisah
/// (split) juga belum mungkin: satu transaksi = satu baris pembayaran
/// bernominal penuh. Lihat IR-11 pada `docs/apotik-uiux/10-integration-requests.md`.
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
    final pagar = ApotikPembayaranSheet.periksa(
      total: widget.total,
      metode: _metode,
      tunai: _nilaiTunai,
      referensi: _referensi.text,
    );
    final tunaiAktif = _metode != null && _metode!.adaKembalian;

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
              else ...[
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
              ],
              const SizedBox(height: 16),
              if (tunaiAktif) ..._bagianTunai(t),
              if (_metode != null && !_metode!.adaKembalian) ...[
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
        'Uang diterima dan kembalian dihitung di kasir. Server hanya '
        'membukukan metode, nominal sebesar total, dan nomor referensi.',
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
    Navigator.pop(
      context,
      HasilPembayaran(
        caraBayarId: _metode?.id,
        namaMetode: _metode?.nama ?? '',
        referensi: _referensi.text.trim(),
        tunai: _nilaiTunai,
        kembalian: _kembalian,
        bukaLaci: widget.laciTersedia &&
            _bukaLaci &&
            (_metode?.adaKembalian ?? false),
      ),
    );
  }
}
