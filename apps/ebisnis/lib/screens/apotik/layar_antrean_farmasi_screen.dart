import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../widgets/safe_state.dart';

enum ModeLayarFarmasi { semua, obatJadi, racikan }

extension ModeLayarFarmasiX on ModeLayarFarmasi {
  String get kode => switch (this) {
        ModeLayarFarmasi.semua => 'SEMUA',
        ModeLayarFarmasi.obatJadi => 'JADI',
        ModeLayarFarmasi.racikan => 'RACIKAN',
      };

  String get label => switch (this) {
        ModeLayarFarmasi.semua => 'Obat Jadi & Racikan',
        ModeLayarFarmasi.obatJadi => 'Obat Jadi',
        ModeLayarFarmasi.racikan => 'Obat Racikan',
      };

  static ModeLayarFarmasi dari(String? kode) => switch (kode) {
        'JADI' => ModeLayarFarmasi.obatJadi,
        'RACIKAN' => ModeLayarFarmasi.racikan,
        _ => ModeLayarFarmasi.semua,
      };
}

/// Layar publik Instalasi Farmasi. Endpoint server selalu mengirim identitas
/// tersamar; diagnosis, alamat, telepon, dan aturan pakai tidak pernah diminta.
class LayarAntreanFarmasiScreen extends StatefulWidget {
  final bool jendelaKedua;
  final int? tokoIdOverride;
  final String? tokoNamaOverride;
  final ModeLayarFarmasi mode;
  final List<Map<String, dynamic>>? dataPratinjau;

  const LayarAntreanFarmasiScreen({
    super.key,
    this.jendelaKedua = false,
    this.tokoIdOverride,
    this.tokoNamaOverride,
    this.mode = ModeLayarFarmasi.semua,
    this.dataPratinjau,
  });

  @override
  State<LayarAntreanFarmasiScreen> createState() =>
      _LayarAntreanFarmasiScreenState();
}

class _LayarAntreanFarmasiScreenState extends State<LayarAntreanFarmasiScreen> {
  Timer? _poll;
  Timer? _jam;
  Timer? _edukasi;
  bool _memuat = true;
  String? _error;
  DateTime _sekarang = DateTime.now();
  int _indexEdukasi = 0;
  List<Map<String, dynamic>> _data = [];

  static const _materi =
      <({IconData icon, String judul, String isi, Color warna})>[
    (
      icon: Icons.medication_outlined,
      judul: 'Gunakan Obat dengan Tepat',
      isi:
          'Pastikan nama pasien benar. Dengarkan penjelasan farmasis, baca etiket, dan gunakan obat sesuai dosis serta waktunya.',
      warna: Color(0xFF0EA5E9)
    ),
    (
      icon: Icons.schedule_outlined,
      judul: 'Jangan Mengubah Jadwal Sendiri',
      isi:
          'Jangan menggandakan dosis yang terlupa. Tanyakan kepada farmasis bila jadwal minum obat terlewat atau menimbulkan keluhan.',
      warna: Color(0xFF7C3AED)
    ),
    (
      icon: Icons.health_and_safety_outlined,
      judul: 'Kenali Efek yang Tidak Diharapkan',
      isi:
          'Segera hubungi tenaga kesehatan bila muncul sesak, bengkak, ruam berat, penurunan kesadaran, atau keluhan lain yang mengkhawatirkan.',
      warna: Color(0xFFDC2626)
    ),
    (
      icon: Icons.inventory_2_outlined,
      judul: 'Simpan dengan Aman',
      isi:
          'Ikuti petunjuk suhu pada etiket, jauhkan dari anak-anak, kelembapan, panas, dan cahaya langsung. Jangan memakai obat kedaluwarsa.',
      warna: Color(0xFF059669)
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.dataPratinjau != null) {
      _data = widget.dataPratinjau!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _memuat = false;
    } else {
      _ambil();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _ambil());
    }
    _jam = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setStateIfMounted(() => _sekarang = DateTime.now());
    });
    _edukasi = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted) {
        setStateIfMounted(
            () => _indexEdukasi = (_indexEdukasi + 1) % _materi.length);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _jam?.cancel();
    _edukasi?.cancel();
    super.dispose();
  }

  Future<void> _ambil() async {
    if (widget.dataPratinjau != null) return;
    try {
      final hasil =
          await ApiClient.instance.aksi('apotik_antrean_farmasi_list', {
        'toko_id': widget.tokoIdOverride ?? Sesi.instance.tokoId,
        'untuk_layar': true,
        if (widget.mode != ModeLayarFarmasi.semua) 'jenis': widget.mode.kode,
      });
      if (!mounted) return;
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _memuat = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _memuat = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isi = _buildIsi(context);
    if (!widget.jendelaKedua) {
      return Scaffold(
        appBar: AppBar(title: Text('Layar Farmasi • ${widget.mode.label}')),
        body: isi,
      );
    }
    return Scaffold(backgroundColor: const Color(0xFFF3F8FC), body: isi);
  }

  Widget _buildIsi(BuildContext context) {
    final siap = _data.where((e) => e['status'] == 'SIAP').toList();
    final jadi = _data.where((e) => e['jenis'] != 'RACIKAN').toList();
    final racikan = _data.where((e) => e['jenis'] != 'JADI').toList();
    return SafeArea(
      child: Column(children: [
        _header(),
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFEF2F2),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            child: Text('Koneksi terputus • menampilkan data terakhir',
                style: TextStyle(color: Colors.red.shade700)),
          ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, box) {
                  final sempit = box.maxWidth < 820;
                  if (sempit) {
                    return ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          if (siap.isNotEmpty) _siapDiambil(siap),
                          if (widget.mode != ModeLayarFarmasi.racikan)
                            SizedBox(
                                height: 460,
                                child: _kolomAntrean(
                                    'OBAT JADI',
                                    jadi,
                                    const Color(0xFF0284C7),
                                    Icons.medication_outlined)),
                          if (widget.mode != ModeLayarFarmasi.obatJadi)
                            SizedBox(
                                height: 460,
                                child: _kolomAntrean(
                                    'OBAT RACIKAN',
                                    racikan,
                                    const Color(0xFF7C3AED),
                                    Icons.science_outlined)),
                          SizedBox(height: 480, child: _panelEdukasi()),
                        ]);
                  }
                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(children: [
                              if (siap.isNotEmpty) _siapDiambil(siap),
                              if (siap.isNotEmpty) const SizedBox(height: 14),
                              Expanded(
                                child: Row(children: [
                                  if (widget.mode != ModeLayarFarmasi.racikan)
                                    Expanded(
                                        child: _kolomAntrean(
                                            'OBAT JADI',
                                            jadi,
                                            const Color(0xFF0284C7),
                                            Icons.medication_outlined)),
                                  if (widget.mode == ModeLayarFarmasi.semua)
                                    const SizedBox(width: 14),
                                  if (widget.mode != ModeLayarFarmasi.obatJadi)
                                    Expanded(
                                        child: _kolomAntrean(
                                            'OBAT RACIKAN',
                                            racikan,
                                            const Color(0xFF7C3AED),
                                            Icons.science_outlined)),
                                ]),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(flex: 3, child: _panelEdukasi()),
                        ]),
                  );
                }),
        ),
        _footer(),
      ]),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: const BoxDecoration(
          gradient:
              LinearGradient(colors: [Color(0xFF075985), Color(0xFF0F766E)]),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.local_pharmacy_outlined,
                color: Color(0xFF0F766E), size: 30),
          ),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('INSTALASI FARMASI',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6)),
                Text(
                    (widget.tokoNamaOverride ?? Sesi.instance.tokoNama).isEmpty
                        ? 'Pelayanan dan Penyerahan Obat'
                        : widget.tokoNamaOverride ?? Sesi.instance.tokoNama,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('HH:mm:ss').format(_sekarang),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800)),
            Text(DateFormat('dd MMM yyyy', 'id_ID').format(_sekarang),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      );

  Widget _siapDiambil(List<Map<String, dynamic>> siap) {
    final tampil = siap.take(3).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFDCFCE7), Color(0xFFECFDF5)]),
        border: Border.all(color: const Color(0xFF22C55E), width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.notifications_active, color: Color(0xFF15803D)),
          SizedBox(width: 8),
          Text('SIAP DIAMBIL • SILAKAN KE LOKET',
              style: TextStyle(
                  color: Color(0xFF166534),
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 9),
        Wrap(
            spacing: 10,
            runSpacing: 10,
            children: tampil
                .map((a) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13)),
                      child: Text(
                          '${a['kodeAntrean']}  •  ${a['namaPasien']}  •  ${('${a['loket']}').isEmpty ? 'Loket Farmasi' : a['loket']}',
                          style: const TextStyle(
                              color: Color(0xFF14532D),
                              fontSize: 17,
                              fontWeight: FontWeight.w900)),
                    ))
                .toList()),
      ]),
    );
  }

  Widget _kolomAntrean(String judul, List<Map<String, dynamic>> data,
      Color warna, IconData icon) {
    final aktif = data.where((e) => e['status'] != 'SELESAI').toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x120F172A), blurRadius: 18, offset: Offset(0, 5))
          ]),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
              color: warna.withValues(alpha: .1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18))),
          child: Row(children: [
            Icon(icon, color: warna),
            const SizedBox(width: 8),
            Text(judul,
                style: TextStyle(color: warna, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('${aktif.length} antrean',
                style: TextStyle(color: warna, fontWeight: FontWeight.w700))
          ]),
        ),
        Expanded(
          child: aktif.isEmpty
              ? Center(
                  child: Text('Belum ada antrean',
                      style: TextStyle(color: Colors.blueGrey.shade400)))
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: aktif.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _kartuAntrean(aktif[i], warna),
                ),
        ),
      ]),
    );
  }

  Widget _kartuAntrean(Map<String, dynamic> a, Color warna) {
    final status = '${a['status']}';
    final siap = status == 'SIAP';
    final obat = ((a['obat'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: siap ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          border: Border.all(
              color: siap ? const Color(0xFF22C55E) : const Color(0xFFE2E8F0),
              width: siap ? 2 : 1),
          borderRadius: BorderRadius.circular(13)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
                color: warna, borderRadius: BorderRadius.circular(10)),
            child: Text('${a['kodeAntrean']}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16))),
        const SizedBox(width: 11),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${a['namaPasien']}',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if ('${a['nomorRekamMedis']}'.isNotEmpty)
            Text('RM ${a['nomorRekamMedis']}',
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
          if (obat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                  obat
                      .take(3)
                      .map((o) =>
                          '${o['nama'] ?? '-'}${o['jumlah'] == null || '${o['jumlah']}'.isEmpty ? '' : ' × ${o['jumlah']}'}')
                      .join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFF475569))),
            ),
        ])),
        const SizedBox(width: 8),
        _statusPill(status),
      ]),
    );
  }

  Widget _statusPill(String status) {
    final (label, warna) = switch (status) {
      'DISIAPKAN' => ('Sedang Disiapkan', const Color(0xFFF59E0B)),
      'SIAP' => ('Siap Diambil', const Color(0xFF16A34A)),
      _ => ('Menunggu', const Color(0xFF64748B)),
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: warna.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: warna, fontSize: 10.5, fontWeight: FontWeight.w800)));
  }

  Widget _panelEdukasi() {
    final m = _materi[_indexEdukasi];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [m.warna, Color.lerp(m.warna, Colors.black, .25)!]),
          borderRadius: BorderRadius.circular(20)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Column(
            key: ValueKey(_indexEdukasi),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('INFO & EDUKASI',
                  style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(height: 28),
              Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      shape: BoxShape.circle),
                  child: Icon(m.icon, color: Colors.white, size: 50)),
              const SizedBox(height: 24),
              Text(m.judul,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 15),
              Text(m.isi,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, height: 1.5, fontSize: 15)),
              const SizedBox(height: 24),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      _materi.length,
                      (i) => Container(
                          width: i == _indexEdukasi ? 22 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                              color: i == _indexEdukasi
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(6))))),
            ]),
      ),
    );
  }

  Widget _footer() => Container(
        color: const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: const Row(children: [
          Icon(Icons.privacy_tip_outlined, size: 15, color: Colors.white60),
          SizedBox(width: 7),
          Expanded(
              child: Text(
                  'Identitas disamarkan untuk melindungi privasi. Cocokkan nama lengkap dan obat langsung dengan petugas saat dipanggil.',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5))),
          Text('Mohon tetap berada di area tunggu',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5)),
        ]),
      );
}
