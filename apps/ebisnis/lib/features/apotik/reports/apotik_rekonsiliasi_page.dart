import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../api_client.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_state_views.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tgl = DateFormat('yyyy-MM-dd');

typedef PanggilLaporan = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// Satu baris rekap pembayaran per metode.
class RekapMetode {
  final String nama;
  final bool tunai;
  final int jumlahTransaksi;
  final double nominal;

  const RekapMetode({
    required this.nama,
    required this.tunai,
    required this.jumlahTransaksi,
    required this.nominal,
  });

  factory RekapMetode.dariJson(Map<String, dynamic> j) => RekapMetode(
        nama: '${j['nama'] ?? '-'}',
        tunai: j['tunai'] == true,
        jumlahTransaksi: ((j['jumlahTransaksi'] as num?) ?? 0).toInt(),
        nominal: ((j['nominal'] as num?) ?? 0).toDouble(),
      );
}

/// Hasil hitung rekonsiliasi laci.
class HitungLaci {
  final double kasSeharusnya;
  final double selisih;
  final bool cocok;

  /// Lebih (>0) atau kurang (<0) dinyatakan dengan kalimat, bukan hanya warna.
  final String keterangan;

  const HitungLaci({
    required this.kasSeharusnya,
    required this.selisih,
    required this.cocok,
    required this.keterangan,
  });
}

/// <h3>Rekonsiliasi kas apotek (Fase 7).</h3>
///
/// **Kenapa bukan memakai ulang `sesi_kas_*` POS umum.** Laporan tutup kas POS
/// umum menghitung uang dari `koperasi.pembelian_anggota_koperasi`; penjualan
/// apotek tidak pernah ditulis ke sana (jejaknya di
/// `sirs.detail_transaksi_pasien` kode `AJ` dan `sirs.apotik_pembayaran_transaksi`).
/// Memakainya apa adanya akan melaporkan penjualan tunai apotek sebesar NOL
/// dan memunculkan selisih kas sebesar seluruh penerimaan hari itu. Karena itu
/// angka "seharusnya" di sini diambil dari `apotik_laporan_pembayaran`
/// (AIS r83210), bukan dari sesi kas POS umum — lihat IR-06.
///
/// **Batas jujur.** Halaman ini MENGHITUNG dan MENCETAK, tetapi tidak
/// menyimpan penutupan shift ke server: belum ada tabel/aksi sesi kas untuk
/// apotek. Karena itu tidak ada tombol "Tutup Shift" yang seolah-olah
/// mengunci angka — yang ada adalah lembar hitung yang dapat dibaca, disalin,
/// dan ditandatangani di kertas seperti praktik sekarang. Menyediakan tombol
/// yang tidak menyimpan apa pun jauh lebih berbahaya daripada tidak
/// menyediakannya.
class ApotikRekonsiliasiPage extends StatefulWidget {
  final PanggilLaporan? panggil;
  final DateTime? dari;
  final DateTime? sampai;

  const ApotikRekonsiliasiPage(
      {super.key, this.panggil, this.dari, this.sampai});

  @override
  State<ApotikRekonsiliasiPage> createState() => _ApotikRekonsiliasiPageState();

  /// Aritmetika laci sebagai fungsi murni supaya dapat diuji tanpa widget.
  ///
  /// `kas seharusnya = modal awal + penerimaan TUNAI`. Penerimaan non-tunai
  /// sengaja TIDAK ikut: uangnya memang tidak pernah masuk laci.
  static HitungLaci hitung({
    required double modalAwal,
    required double penerimaanTunai,
    required double uangFisik,
  }) {
    final seharusnya = modalAwal + penerimaanTunai;
    final selisih = uangFisik - seharusnya;
    final cocok = selisih.abs() < 0.5;
    final String keterangan;
    if (cocok) {
      keterangan = 'Kas cocok dengan catatan.';
    } else if (selisih > 0) {
      keterangan = 'Uang di laci LEBIH ${_rp.format(selisih)} dari catatan — '
          'periksa kembalian yang belum diberikan atau setoran yang tercatat '
          'ganda.';
    } else {
      keterangan = 'Uang di laci KURANG ${_rp.format(-selisih)} dari catatan — '
          'periksa pengeluaran laci yang belum dicatat.';
    }
    return HitungLaci(
      kasSeharusnya: seharusnya,
      selisih: selisih,
      cocok: cocok,
      keterangan: keterangan,
    );
  }
}

class _ApotikRekonsiliasiPageState extends State<ApotikRekonsiliasiPage> {
  late final PanggilLaporan _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  late DateTime _dari =
      widget.dari ?? DateTime.now().subtract(const Duration(days: 0));
  late DateTime _sampai = widget.sampai ?? DateTime.now();

  bool _memuat = true;
  String? _galat;
  List<RekapMetode> _metode = const [];
  double _totalTunai = 0;
  double _totalNonTunai = 0;
  double _penjualanLedger = 0;
  double _uangDiterima = 0;
  double _uangKembalian = 0;
  double _selisihTanpaMetode = 0;
  int _jumlahTransaksi = 0;

  final _modal = TextEditingController(text: '0');
  final _fisik = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _modal.dispose();
    _fisik.dispose();
    super.dispose();
  }

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  double _angka(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await _panggil('apotik_laporan_pembayaran', {
        'dari': _tgl.format(_dari),
        'sampai': _tgl.format(_sampai),
      });
      if (!_sukses(r)) {
        setStateIfMounted(() {
          _galat = '${r['description'] ?? 'Rekap pembayaran gagal dimuat.'}';
          _memuat = false;
        });
        return;
      }
      setStateIfMounted(() {
        _metode = ((r['perMetode'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => RekapMetode.dariJson(Map<String, dynamic>.from(e)))
            .toList();
        _totalTunai = ((r['totalTunai'] as num?) ?? 0).toDouble();
        _totalNonTunai = ((r['totalNonTunai'] as num?) ?? 0).toDouble();
        _penjualanLedger = ((r['penjualanLedger'] as num?) ?? 0).toDouble();
        _uangDiterima = ((r['totalUangDiterima'] as num?) ?? 0).toDouble();
        _uangKembalian = ((r['totalKembalian'] as num?) ?? 0).toDouble();
        _selisihTanpaMetode =
            ((r['selisihTanpaMetode'] as num?) ?? 0).toDouble();
        _jumlahTransaksi = ((r['jumlahTransaksi'] as num?) ?? 0).toInt();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _pilihPeriode(bool awal) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: awal ? _dari : _sampai,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (hasil == null) return;
    setStateIfMounted(() {
      if (awal) {
        _dari = hasil;
      } else {
        _sampai = hasil;
      }
    });
    await _muat();
  }

  /// Ringkasan siap salin/tanda tangan — pengganti jujur dari "tutup shift"
  /// yang belum dapat disimpan ke server.
  String ringkasanTeks(HitungLaci h) {
    final b = StringBuffer()
      ..writeln('REKONSILIASI KAS APOTEK')
      ..writeln('Periode  : ${_tgl.format(_dari)} s.d. ${_tgl.format(_sampai)}')
      ..writeln('Transaksi: $_jumlahTransaksi');
    for (final m in _metode) {
      b.writeln(
          '${m.nama.padRight(18)} ${m.tunai ? '(tunai)    ' : '(non-tunai)'} '
          '${_rp.format(m.nominal)}');
    }
    b
      ..writeln('Penerimaan tunai     : ${_rp.format(_totalTunai)}')
      ..writeln('Penerimaan non-tunai : ${_rp.format(_totalNonTunai)}')
      ..writeln('Modal awal           : ${_rp.format(_angka(_modal))}')
      ..writeln('Kas seharusnya       : ${_rp.format(h.kasSeharusnya)}')
      ..writeln('Uang fisik dihitung  : ${_rp.format(_angka(_fisik))}')
      ..writeln('Selisih              : ${_rp.format(h.selisih)}')
      ..writeln(h.keterangan);
    if (_selisihTanpaMetode.abs() >= 1) {
      b.writeln('Catatan: penjualan tanpa metode tercatat '
          '${_rp.format(_selisihTanpaMetode)} — tidak termasuk rekap di atas.');
    }
    b.writeln('Lembar ini TIDAK tersimpan di server (IR-06).');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    if (_galat != null) {
      return ApotikErrorState(pesan: _galat!, onCobaLagi: _muat);
    }
    if (_memuat) {
      return const ApotikLoadingState(pesan: 'Memuat rekap pembayaran…');
    }
    final h = ApotikRekonsiliasiPage.hitung(
      modalAwal: _angka(_modal),
      penerimaanTunai: _totalTunai,
      uangFisik: _angka(_fisik),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _periode(t),
          const SizedBox(height: 12),
          _kartuRekap(t),
          const SizedBox(height: 12),
          _kartuLaci(t, h),
          const SizedBox(height: 12),
          _catatanBatas(t),
        ],
      ),
    );
  }

  Widget _periode(ApotikDesignTokens t) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pilihPeriode(true),
          icon: const Icon(Icons.event, size: 16),
          label: Text('Dari ${_tgl.format(_dari)}'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pilihPeriode(false),
          icon: const Icon(Icons.event_available, size: 16),
          label: Text('Sampai ${_tgl.format(_sampai)}'),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Muat ulang',
        onPressed: _muat,
        icon: const Icon(Icons.refresh),
      ),
    ]);
  }

  Widget _kartu(ApotikDesignTokens t, String judul, List<Widget> isi) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(judul,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary)),
          const SizedBox(height: 10),
          ...isi,
        ],
      ),
    );
  }

  Widget _baris(ApotikDesignTokens t, String kiri, String kanan,
      {bool tebal = false, Color? warna}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Text(kiri,
              style: TextStyle(
                  fontSize: 12.5,
                  color: warna ?? t.textSecondary,
                  fontWeight: tebal ? FontWeight.w700 : FontWeight.w400)),
        ),
        Text(kanan,
            style: TextStyle(
                fontSize: 13,
                fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
                color: warna ?? t.textPrimary)),
      ]),
    );
  }

  Widget _kartuRekap(ApotikDesignTokens t) {
    return _kartu(t, 'Uang masuk per metode ($_jumlahTransaksi transaksi)', [
      if (_metode.isEmpty)
        Text('Belum ada pembayaran bermetode pada periode ini.',
            style: TextStyle(fontSize: 12, color: t.textSecondary))
      else
        for (final m in _metode)
          _baris(t, '${m.nama}  ${m.tunai ? '· tunai' : '· non-tunai'}',
              _rp.format(m.nominal)),
      const Divider(height: 18),
      _baris(t, 'Penerimaan tunai', _rp.format(_totalTunai), tebal: true),
      _baris(t, 'Penerimaan non-tunai', _rp.format(_totalNonTunai)),
      // IR-11: uang yang benar-benar berpindah tangan. Kas laci tetap
      // dihitung dari penerimaan (diterima - kembalian = penerimaan); dua
      // baris ini alat bukti saat selisih laci perlu ditelusuri.
      if (_uangDiterima > 0 || _uangKembalian > 0) ...[
        _baris(t, 'Uang tunai diterima', _rp.format(_uangDiterima)),
        _baris(t, 'Kembalian diberikan', _rp.format(_uangKembalian)),
      ],
      const Divider(height: 18),
      _baris(t, 'Penjualan tercatat (ledger)', _rp.format(_penjualanLedger)),
      if (_selisihTanpaMetode.abs() >= 1) ...[
        _baris(t, 'Penjualan tanpa metode tercatat',
            _rp.format(_selisihTanpaMetode),
            warna: t.warning, tebal: true),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Selisih ini BUKAN kekurangan kas: ini penjualan yang metodenya '
            'tidak pernah tercatat (mis. transaksi lama sebelum metode '
            'dicatat, atau dikirim tanpa memilih metode).',
            style: TextStyle(fontSize: 11, color: t.textSecondary),
          ),
        ),
      ],
    ]);
  }

  Widget _kartuLaci(ApotikDesignTokens t, HitungLaci h) {
    return _kartu(t, 'Hitung laci', [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _modal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            onChanged: (_) => setStateIfMounted(() {}),
            decoration: const InputDecoration(
                labelText: 'Modal awal',
                border: OutlineInputBorder(),
                isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _fisik,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            onChanged: (_) => setStateIfMounted(() {}),
            decoration: const InputDecoration(
                labelText: 'Uang fisik dihitung',
                border: OutlineInputBorder(),
                isDense: true),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _baris(t, 'Kas seharusnya (modal + tunai)', _rp.format(h.kasSeharusnya),
          tebal: true),
      _baris(t, 'Selisih', _rp.format(h.selisih),
          tebal: true, warna: h.cocok ? t.success : t.danger),
      const SizedBox(height: 6),
      Text(h.keterangan,
          style: TextStyle(
              fontSize: 12,
              color: h.cocok ? t.success : t.danger,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: ringkasanTeks(h)));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ringkasan rekonsiliasi disalin.')));
        },
        icon: const Icon(Icons.copy_all_outlined, size: 16),
        label: const Text('Salin ringkasan'),
      ),
    ]);
  }

  Widget _catatanBatas(ApotikDesignTokens t) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 17, color: t.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Lembar ini TIDAK tersimpan di server. Sesi kas POS umum '
            '(sesi_kas_*) menghitung uang dari ledger POS, yang tidak memuat '
            'penjualan apotek — memakainya akan melaporkan tunai apotek Rp 0. '
            'Penyimpanan tutup shift apotek menunggu keputusan IR-06.',
            style: TextStyle(fontSize: 11.5, color: t.textPrimary),
          ),
        ),
      ]),
    );
  }
}
