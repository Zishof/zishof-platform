import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api_client.dart';
import '../../../sesi.dart';
import '../../../widgets/safe_state.dart';
import '../../../services/master_offline.dart';
import '../../../widgets/kilau_perubahan.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_lokal_dulu.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

typedef PanggilResep = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// <h3>Antrean Resep &amp; Dispensing (Fase 4, mockup 03).</h3>
///
/// Master-detail adaptif: daftar resep di kiri, rincian + daftar periksa
/// pra-serah di kanan (desktop) atau halaman terpisah (mobile).
///
/// Panel telaah klinis memakai profil pasien, diagnosis, dan alergi aktif dari
/// model SIRS. Pencocokan alergi dibuat fail-safe: hanya relasi persis ke item
/// obat yang ditandai sebagai konflik. Interaksi obat, duplikasi terapi, dan
/// pemeriksaan dosis belum dinyatakan aman sampai basis pengetahuan klinis
/// tersedia. Daftar periksa operasional tetap mencakup obat terkendali,
/// high-alert, LASA, cold-chain, stok, pemeriksaan kedua, dan konseling.
class ApotikResepPage extends StatefulWidget {
  final PanggilResep? panggil;

  /// Pemuat "lokal dulu" untuk daftar antrean. Detail resep, dispensing, dan
  /// penebusan tetap lewat [panggil] karena semuanya butuh server saat itu
  /// juga (lihat core/apotik_lokal_dulu.dart).
  final MuatDaftarApotik? muatDaftar;
  const ApotikResepPage({super.key, this.panggil, this.muatDaftar});

  @override
  State<ApotikResepPage> createState() => _ApotikResepPageState();
}

class _ApotikResepPageState extends State<ApotikResepPage> {
  late final MuatDaftarApotik _muatDaftar =
      widget.muatDaftar ?? MasterOffline.daftarCacheDulu;
  late final PanggilResep _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  bool _memuat = true;
  String? _galat;
  bool _hanyaMenunggu = true;
  List<Map<String, dynamic>> _daftar = [];
  int _totalDaftar = 0;

  Map<String, dynamic>? _terpilih;
  List<Map<String, dynamic>> _baris = [];
  bool _memuatDetail = false;
  String? _galatDetail;
  Map<String, dynamic> _statusDispensing = {};
  Map<String, dynamic> _telaahKlinis = {};
  Map<String, dynamic> _informasiResep = {};

  @override
  void initState() {
    super.initState();
    _muat();
  }

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  List<Map<String, dynamic>> _data(Map<String, dynamic> r) =>
      ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  /// Diff emisi server -> animasi baris resep yang baru masuk antrean.
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Baca LOKAL DULU: antrean yang terakhir terlihat tetap terbaca saat
      // jaringan mati. Penebusannya sendiri tetap butuh server -- yang
      // di-cache hanya DAFTARnya, bukan izin menyerahkan obat.
      await _muatDaftar(
        'apotik_resep_list',
        {'hanya_menunggu': _hanyaMenunggu, 'page_size': 100},
        kunciCacheResepApotik(hanyaMenunggu: _hanyaMenunggu),
        onData: (hasil) {
          if (!mounted) return;
          final dariServer = hasil['dariServer'] == true;
          setStateIfMounted(() {
            _daftar = ((hasil['data'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _totalDaftar = ((hasil['total'] as num?) ?? _daftar.length).toInt();
            _idBaru = dariServer
                ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
                : {};
            _idBerubah = dariServer
                ? Set<String>.from(
                    hasil['idBerubah'] as Set? ?? const <String>{})
                : {};
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        if (_daftar.isEmpty) _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _pilih(Map<String, dynamic> resep) async {
    setStateIfMounted(() {
      _terpilih = resep;
      _memuatDetail = true;
      _galatDetail = null;
      _baris = [];
      _statusDispensing = {};
      _telaahKlinis = {};
      _informasiResep = {};
    });
    try {
      final r =
          await _panggil('apotik_resep_detail', {'resep_id': resep['id']});
      if (!_sukses(r)) {
        setStateIfMounted(() {
          _galatDetail = '${r['description'] ?? 'Gagal memuat rincian resep.'}';
          _memuatDetail = false;
        });
        return;
      }
      Map<String, dynamic> statusD = {};
      try {
        final s = await _panggil(
            'apotik_dispensing_status', {'resep_id': resep['id']});
        if (_sukses(s)) statusD = s;
      } catch (_) {
        // Server lama tanpa IR-05: bagian dispensing disembunyikan, bukan galat.
      }
      setStateIfMounted(() {
        _baris = _data(r);
        _statusDispensing = statusD;
        _telaahKlinis = r['telaahKlinis'] is Map
            ? Map<String, dynamic>.from(r['telaahKlinis'] as Map)
            : <String, dynamic>{};
        final informasi =
            r['informasiResep'] ?? _telaahKlinis['informasiResep'];
        _informasiResep = informasi is Map
            ? Map<String, dynamic>.from(informasi)
            : <String, dynamic>{};
        _memuatDetail = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galatDetail = '$e';
        _memuatDetail = false;
      });
    }
  }

  /// Daftar periksa pra-serah dari DATA NYATA (bukan pengetahuan klinis).
  List<({String teks, ApotikStatusNada nada})> _daftarPeriksa() {
    final hasil = <({String teks, ApotikStatusNada nada})>[];
    final terkendali = _baris.where((b) => b['terkendali'] == true).length;
    final highAlert = _baris.where((b) => b['highAlert'] == true).length;
    final lasa = _baris.where((b) => b['lasa'] == true).length;
    final coldChain = _baris.where((b) => b['coldChain'] == true).length;
    final racikan = _baris.where((b) => b['racikan'] == true).length;
    final stokKurang = _baris.where((b) {
      final butuh = ((b['jumlah'] as num?) ?? 0).toDouble();
      final stok = ((b['stok'] as num?) ?? 0).toDouble();
      return stok < butuh;
    }).toList();

    if (terkendali > 0) {
      hasil.add((
        teks: '$terkendali obat TERKENDALI — wajib identitas pembeli dan '
            'tercatat di register',
        nada: ApotikStatusNada.bahaya
      ));
    }
    if (highAlert > 0) {
      hasil.add((
        teks: '$highAlert obat HIGH-ALERT — pastikan pemeriksaan kedua',
        nada: ApotikStatusNada.bahaya
      ));
    }
    if (lasa > 0) {
      hasil.add((
        teks: '$lasa obat LASA (nama/rupa mirip) — baca ulang sebelum ambil',
        nada: ApotikStatusNada.peringatan
      ));
    }
    if (coldChain > 0) {
      hasil.add((
        teks: '$coldChain obat COLD-CHAIN — siapkan wadah 2-8 °C',
        nada: ApotikStatusNada.info
      ));
    }
    for (final b in stokKurang) {
      hasil.add((
        teks: 'Stok kurang: ${b['nama']} (butuh ${b['jumlah']}, '
            'tersedia ${b['stok']})',
        nada: ApotikStatusNada.bahaya
      ));
    }
    if (racikan > 0) {
      hasil.add((
        teks: '$racikan baris RACIKAN belum dapat diserahkan lewat kasir '
            '(belum tersedia dari server)',
        nada: ApotikStatusNada.peringatan
      ));
    }
    if (hasil.isEmpty) {
      hasil.add((
        teks: 'Tidak ada penanda risiko pada data obat resep ini',
        nada: ApotikStatusNada.sukses
      ));
    }
    return hasil;
  }

  Future<void> _catatDispensing(String jenis) async {
    final resep = _terpilih;
    if (resep == null) return;
    final catatan = TextEditingController();
    final penyiap = TextEditingController();
    final isDoubleCheck = jenis == 'DOUBLE_CHECK';
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isDoubleCheck ? 'Pemeriksaan Kedua' : 'Catat Konseling'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isDoubleCheck) ...[
            Text(
                'Pemeriksa kedua harus akun BERBEDA dari penyiap obat. '
                'Server menolak bila sama.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            TextField(
                controller: penyiap,
                decoration: const InputDecoration(
                    labelText: 'User ID penyiap obat *',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
          ],
          TextField(
              controller: catatan,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
                  isDense: true)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Catat')),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;
    try {
      final r = await _panggil('apotik_dispensing_catat', {
        'resep_id': resep['id'],
        'jenis': jenis,
        if (isDoubleCheck) 'penyiap_user_id': penyiap.text.trim(),
        'catatan': catatan.text.trim(),
      });
      if (!mounted) return;
      // Pesan server ditampilkan apa adanya, termasuk penolakan aturan
      // pemeriksa kedua.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${r['description'] ?? (_sukses(r) ? 'Tercatat.' : r['status'])}'),
        backgroundColor:
            _sukses(r) ? null : Theme.of(context).colorScheme.error,
      ));
      if (_sukses(r)) await _pilih(resep);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal mencatat: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return ApotikResponsive(builder: (context, layout) {
      final master = _panelDaftar(t, layout);
      if (!layout.isDesktop) {
        return Scaffold(
            backgroundColor: t.surfaceMuted, body: SafeArea(child: master));
      }
      return Scaffold(
        backgroundColor: t.surfaceMuted,
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 360, child: master),
          Expanded(child: _panelDetail(t)),
        ]),
      );
    });
  }

  Widget _panelDaftar(ApotikDesignTokens t, ApotikLayout layout) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ApotikPageHeader(
          judul: 'Antrean Resep',
          subjudul: _hanyaMenunggu ? 'Menunggu ditebus' : 'Semua resep',
          aksi: [
            IconButton(
                onPressed: _memuat ? null : _muat,
                tooltip: 'Muat ulang',
                icon: const Icon(Icons.refresh)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            FilterChip(
              label: Text(_hanyaMenunggu ? 'Menunggu' : 'Semua'),
              selected: _hanyaMenunggu,
              onSelected: (v) {
                setStateIfMounted(() => _hanyaMenunggu = v);
                _muat();
              },
            ),
            const Spacer(),
            if (!_memuat)
              Text(
                  _totalDaftar > _daftar.length
                      ? '${_daftar.length} dari $_totalDaftar resep'
                      : '${_daftar.length} resep',
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _memuat
              ? const ApotikLoadingState(pesan: 'Memuat antrean resep…')
              : _galat != null
                  ? ApotikErrorState(pesan: _galat!, onCobaLagi: _muat)
                  : _daftar.isEmpty
                      ? const ApotikEmptyState(
                          ikon: Icons.description_outlined,
                          judul: 'Tidak ada resep menunggu',
                          petunjuk:
                              'Resep baru dari dokter akan muncul di sini '
                              'begitu tercatat di sistem.')
                      : ListView.separated(
                          itemCount: _daftar.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: t.border),
                          itemBuilder: (context, i) => KilauBaris(
                            kunci: MasterOffline.kunciBaris(_daftar[i]),
                            idBaru: _idBaru,
                            idBerubah: _idBerubah,
                            child: _barisResep(t, _daftar[i], layout),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _barisResep(
      ApotikDesignTokens t, Map<String, dynamic> r, ApotikLayout layout) {
    final ditebus = r['ditebus'] == true;
    final terpilih = _terpilih != null && _terpilih!['id'] == r['id'];
    return ListTile(
      dense: true,
      selected: terpilih,
      selectedTileColor: t.primarySoft,
      leading: Icon(Icons.description_outlined,
          color: ditebus ? t.textSecondary : t.clinicalPurple),
      title: Text('${r['kode'] ?? r['id']}',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: t.textPrimary)),
      subtitle: Text(
          [
            if ('${r['pasienNama'] ?? ''}'.trim().isNotEmpty)
              '${r['pasienNama']}${'${r['nomorRekamMedis'] ?? ''}'.trim().isEmpty ? '' : ' (${r['nomorRekamMedis']})'}',
            if ('${r['dokterNama'] ?? ''}'.trim().isNotEmpty)
              'dr. ${r['dokterNama']}',
            if ('${r['diagnosa'] ?? ''}'.trim().isNotEmpty) '${r['diagnosa']}',
            if (r['jumlahBaris'] != null) '${r['jumlahBaris']} baris',
          ].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
      trailing: ditebus
          ? const ApotikStatusPill(
              teks: 'Ditebus',
              nada: ApotikStatusNada.sukses,
              ikon: Icons.check_circle_outline,
              penjelasan: 'Sudah diserahkan lewat kasir',
              rapat: true)
          : const ApotikStatusPill(
              teks: 'Menunggu',
              nada: ApotikStatusNada.peringatan,
              ikon: Icons.schedule,
              penjelasan: 'Belum ditebus',
              rapat: true),
      onTap: () async {
        await _pilih(r);
        if (!mounted || layout.isDesktop) return;
        // Mobile: detail dibuka sebagai halaman penuh, bukan panel sempit.
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('${r['kode'] ?? r['id']}')),
            body: _panelDetail(t),
          ),
        ));
      },
    );
  }

  Widget _panelDetail(ApotikDesignTokens t) {
    if (_terpilih == null) {
      return const ApotikEmptyState(
        ikon: Icons.touch_app_outlined,
        judul: 'Pilih resep',
        petunjuk: 'Pilih satu resep di daftar untuk melihat rincian obat dan '
            'daftar periksa sebelum diserahkan.',
      );
    }
    if (_memuatDetail) {
      return const ApotikLoadingState(pesan: 'Memuat rincian resep…');
    }
    if (_galatDetail != null) {
      return ApotikErrorState(
          pesan: _galatDetail!, onCobaLagi: () => _pilih(_terpilih!));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Resep ${_terpilih!['kode'] ?? ''}',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.textPrimary)),
        if ('${_terpilih!['diagnosa'] ?? ''}'.trim().isNotEmpty)
          Text('${_terpilih!['diagnosa']}',
              style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
        const SizedBox(height: 14),
        _kotakInformasiResep(t),
        const SizedBox(height: 14),
        _kotakKeselamatanKlinis(t),
        const SizedBox(height: 14),
        _kotakDaftarPeriksa(t),
        const SizedBox(height: 14),
        _kotakDispensing(t),
        const SizedBox(height: 14),
        Text('Obat pada resep',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.textPrimary)),
        const SizedBox(height: 6),
        for (final b in _baris) _barisObat(t, b),
      ],
    );
  }

  Map<String, dynamic> _peta(dynamic nilai) =>
      nilai is Map ? Map<String, dynamic>.from(nilai) : <String, dynamic>{};

  String _icd(dynamic nilai) {
    final daftar = (nilai as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map((e) => '${e['kode'] ?? ''} ${e['nama'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return daftar.join(', ');
  }

  Widget _barisInformasi(
      ApotikDesignTokens t, IconData ikon, String label, String nilai) {
    if (nilai.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, size: 16, color: t.clinicalPurple),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: t.textSecondary)),
        ),
        Expanded(
          child:
              Text(nilai, style: TextStyle(fontSize: 12, color: t.textPrimary)),
        ),
      ]),
    );
  }

  Widget _kotakInformasiResep(ApotikDesignTokens t) {
    final pasien = _peta(_informasiResep['pasien']);
    final dokter = _peta(_informasiResep['dokter']);
    final asal = _peta(_informasiResep['asalResep']);
    final diagnosis = _peta(_informasiResep['diagnosis']);
    final sample = _informasiResep['dataSample'] == true;
    final rm = '${pasien['nomorRekamMedis'] ?? pasien['kode'] ?? ''}'.trim();
    final demografi = [
      if ('${pasien['jenisKelamin'] ?? ''}'.trim().isNotEmpty)
        '${pasien['jenisKelamin']}',
      if (pasien['umur'] != null) '${pasien['umur']} tahun',
      if ('${pasien['tanggalLahir'] ?? ''}'.trim().isNotEmpty)
        'lahir ${pasien['tanggalLahir']}',
    ].join(' • ');
    final dokterDetail = [
      '${dokter['nama'] ?? ''}'.trim(),
      if ('${dokter['kode'] ?? ''}'.trim().isNotEmpty) '${dokter['kode']}',
      if ('${dokter['kategori'] ?? ''}'.trim().isNotEmpty)
        '${dokter['kategori']}',
    ].where((e) => e.isNotEmpty).join(' • ');
    final kunjungan = [
      '${asal['ringkasan'] ?? ''}'.trim(),
      if ('${asal['kodeKunjungan'] ?? ''}'.trim().isNotEmpty)
        'Kunjungan ${asal['kodeKunjungan']}',
      if ('${asal['statusKunjungan'] ?? ''}'.trim().isNotEmpty)
        '${asal['statusKunjungan']}',
      if ('${asal['penjamin'] ?? ''}'.trim().isNotEmpty)
        'Penjamin: ${asal['penjamin']}',
    ].where((e) => e.isNotEmpty).join(' • ');
    final icd = _icd(diagnosis['icdAkhir']);
    final diagnosisDetail = [
      if (icd.isNotEmpty) icd,
      if ('${diagnosis['ringkasan'] ?? ''}'.trim().isNotEmpty)
        '${diagnosis['ringkasan']}',
      if ('${diagnosis['kesimpulanPemeriksaan'] ?? ''}'.trim().isNotEmpty)
        '${diagnosis['kesimpulanPemeriksaan']}',
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.description_outlined, size: 18, color: t.clinicalPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Informasi lengkap resep dokter',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary)),
          ),
          if (sample)
            const ApotikStatusPill(
              teks: 'DATA SAMPLE/UAT',
              nada: ApotikStatusNada.info,
              ikon: Icons.science_outlined,
              penjelasan: 'Data sintetis, bukan resep pasien nyata',
              rapat: true,
            ),
        ]),
        if (_informasiResep.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Asal resep, dokter, pasien, dan diagnosis belum terhubung pada data ini.',
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
          ),
        _barisInformasi(t, Icons.event_outlined, 'Tanggal resep',
            '${_informasiResep['tanggalResep'] ?? ''}'),
        _barisInformasi(
            t,
            Icons.person_outline,
            'Pasien / RM',
            [
              '${pasien['nama'] ?? ''}'.trim(),
              if (rm.isNotEmpty) 'RM $rm',
              demografi,
            ].where((e) => e.isNotEmpty).join(' • ')),
        _barisInformasi(
            t, Icons.medical_services_outlined, 'Dokter/peresep', dokterDetail),
        _barisInformasi(
            t, Icons.local_hospital_outlined, 'Asal pelayanan', kunjungan),
        _barisInformasi(t, Icons.monitor_heart_outlined, 'Diagnosis/indikasi',
            diagnosisDetail),
        _barisInformasi(t, Icons.chat_bubble_outline, 'Keluhan pasien',
            '${diagnosis['keluhanPasien'] ?? ''}'),
        _barisInformasi(t, Icons.fact_check_outlined, 'Anamnesis',
            '${diagnosis['hasilAnamnesis'] ?? ''}'),
        _barisInformasi(t, Icons.call_received_outlined, 'Dokter pengirim',
            '${asal['dokterPengirim'] ?? ''}'),
        _barisInformasi(t, Icons.location_on_outlined, 'Alamat pasien',
            '${pasien['alamat'] ?? ''}'),
        _barisInformasi(t, Icons.phone_outlined, 'Kontak pasien',
            '${pasien['telepon'] ?? ''}'),
      ]),
    );
  }

  Widget _kotakKeselamatanKlinis(ApotikDesignTokens t) {
    final pasien = _telaahKlinis['pasien'] is Map
        ? Map<String, dynamic>.from(_telaahKlinis['pasien'] as Map)
        : <String, dynamic>{};
    final alergi = ((_telaahKlinis['alergiAktif'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final peringatan = ((_telaahKlinis['peringatan'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final adaBahaya = peringatan.any((e) => e['tingkat'] == 'BAHAYA');
    final evaluasiLengkap = _telaahKlinis['evaluasiOtomatisLengkap'] == true;
    final warna = adaBahaya ? t.danger : t.clinicalPurple;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: adaBahaya ? t.danger.withValues(alpha: .06) : t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: adaBahaya ? t.danger : t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.health_and_safety_outlined, size: 18, color: warna),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Keselamatan klinis pasien',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary)),
          ),
          ApotikStatusPill(
            teks: adaBahaya ? 'Alergi terdeteksi' : 'Telaah apoteker',
            nada: adaBahaya ? ApotikStatusNada.bahaya : ApotikStatusNada.klinis,
            ikon: adaBahaya ? Icons.warning_amber : Icons.medical_information,
            penjelasan: 'Ringkasan dari profil pasien SIRS',
            rapat: true,
          ),
        ]),
        const SizedBox(height: 10),
        if (pasien.isNotEmpty)
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: t.primarySoft,
              child: Icon(Icons.person_outline, color: t.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${pasien['nama'] ?? '-'}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: t.textPrimary)),
                    Text(
                        '${pasien['kode'] ?? '-'}'
                        '${'${pasien['jenisKelamin'] ?? ''}'.isEmpty ? '' : ' • ${pasien['jenisKelamin']}'}',
                        style:
                            TextStyle(fontSize: 11.5, color: t.textSecondary)),
                  ]),
            ),
          ])
        else
          Text('Profil pasien belum terhubung dengan resep.',
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        if (alergi.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Alergi aktif',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: alergi
                .map((a) => ApotikStatusPill(
                      teks:
                          '${a['substansi'] ?? '-'} • ${a['keparahan'] ?? '-'}',
                      nada: a['cocokEksakDenganResep'] == true
                          ? ApotikStatusNada.bahaya
                          : ApotikStatusNada.peringatan,
                      ikon: Icons.warning_amber_rounded,
                      penjelasan: '${a['reaksi'] ?? ''}',
                    ))
                .toList(),
          ),
        ],
        for (final alert in peringatan)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                alert['tingkat'] == 'BAHAYA'
                    ? Icons.error_outline
                    : alert['tingkat'] == 'PERINGATAN'
                        ? Icons.warning_amber
                        : Icons.info_outline,
                size: 15,
                color: alert['tingkat'] == 'BAHAYA'
                    ? t.danger
                    : alert['tingkat'] == 'PERINGATAN'
                        ? t.warning
                        : t.info,
              ),
              const SizedBox(width: 7),
              Expanded(
                  child: Text('${alert['pesan'] ?? ''}',
                      style: TextStyle(fontSize: 11.5, color: t.textPrimary))),
            ]),
          ),
        if (!evaluasiLengkap)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.fact_check_outlined, size: 15, color: t.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Interaksi obat, duplikasi terapi, dan kesesuaian dosis '
                  'wajib ditelaah apoteker.',
                  style: TextStyle(fontSize: 11.5, color: t.textSecondary),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _kotakDaftarPeriksa(ApotikDesignTokens t) {
    final periksa = _daftarPeriksa();
    Color warna(ApotikStatusNada n) => switch (n) {
          ApotikStatusNada.bahaya => t.danger,
          ApotikStatusNada.peringatan => t.warning,
          ApotikStatusNada.sukses => t.success,
          ApotikStatusNada.info => t.info,
          _ => t.textSecondary,
        };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.fact_check_outlined, size: 17, color: t.primary),
          const SizedBox(width: 8),
          Text('Daftar periksa sebelum diserahkan',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ]),
        const SizedBox(height: 8),
        for (final p in periksa)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.circle, size: 7, color: warna(p.nada)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(p.teks,
                      style: TextStyle(fontSize: 12, color: t.textPrimary))),
            ]),
          ),
        const SizedBox(height: 10),
      ]),
    );
  }

  Widget _kotakDispensing(ApotikDesignTokens t) {
    // Server lama tanpa IR-05 tidak mengirim penanda ini -> bagian
    // disembunyikan daripada menampilkan tombol yang tidak menulis apa pun.
    if (_statusDispensing.isEmpty) return const SizedBox.shrink();
    final sudahCek = _statusDispensing['sudahDoubleCheck'] == true;
    final sudahKonseling = _statusDispensing['sudahKonseling'] == true;
    final catatan = ((_statusDispensing['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_user_outlined, size: 17, color: t.clinicalPurple),
          const SizedBox(width: 8),
          Text('Pemeriksaan kedua & konseling',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ]),
        const SizedBox(height: 8),
        for (final c in catatan)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                '${c['jenis'] == 'DOUBLE_CHECK' ? 'Pemeriksaan kedua' : 'Konseling'}'
                ' oleh ${c['pelakuUserId']} • ${c['waktu']}',
                style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: sudahCek ? null : () => _catatDispensing('DOUBLE_CHECK'),
            icon: const Icon(Icons.how_to_reg_outlined, size: 16),
            label: Text(sudahCek ? 'Sudah diperiksa' : 'Pemeriksaan kedua'),
          ),
          OutlinedButton.icon(
            onPressed:
                sudahKonseling ? null : () => _catatDispensing('KONSELING'),
            icon: const Icon(Icons.record_voice_over_outlined, size: 16),
            label:
                Text(sudahKonseling ? 'Sudah dikonseling' : 'Catat konseling'),
          ),
        ]),
      ]),
    );
  }

  Widget _barisObat(ApotikDesignTokens t, Map<String, dynamic> b) {
    final racikan = b['racikan'] == true;
    final butuh = ((b['jumlah'] as num?) ?? 0).toDouble();
    final stok = ((b['stok'] as num?) ?? 0).toDouble();
    final sediaan = [
      '${b['kekuatan'] ?? ''}'.trim(),
      '${b['bentukSediaan'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(' • ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(color: racikan ? t.warning : t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${b['nama'] ?? '-'}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        b['lasa'] == true ? FontWeight.w800 : FontWeight.w600,
                    color: t.textPrimary)),
          ),
          Text(
              '${butuh.toStringAsFixed(butuh % 1 == 0 ? 0 : 2)} '
              '${b['satuan'] ?? ''}',
              style: TextStyle(fontSize: 12.5, color: t.textPrimary)),
        ]),
        if (sediaan.isNotEmpty)
          Text(sediaan,
              style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
        if ('${b['keterangan'] ?? ''}'.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${b['keterangan']}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: t.clinicalPurple)),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (racikan) ApotikStatusPill.racikan(),
          if (b['terkendali'] == true) ApotikStatusPill.terkendali(),
          if (b['highAlert'] == true) ApotikStatusPill.highAlert(),
          if (b['lasa'] == true) ApotikStatusPill.lasa(),
          if (b['coldChain'] == true) ApotikStatusPill.coldChain(),
          if (stok < butuh)
            ApotikStatusPill(
                teks: 'Stok kurang ($stok)',
                nada: ApotikStatusNada.bahaya,
                ikon: Icons.production_quantity_limits_outlined,
                penjelasan: 'Tersedia $stok, dibutuhkan $butuh'),
        ]),
        if ((b['hargaJual'] as num?) != null && (b['hargaJual'] as num) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_rp.format((b['hargaJual'] as num).toDouble()),
                style: TextStyle(fontSize: 12, color: t.primary)),
          ),
      ]),
    );
  }
}

/// Kunci menu yang mengatur akses layar ini (fail-closed di server).
bool bolehBukaAntreanResep() =>
    Sesi.instance.bolehMenuVarianBaru('apotik_resep') ||
    Sesi.instance.bolehMenuVarianBaru('apotik_kasir');
