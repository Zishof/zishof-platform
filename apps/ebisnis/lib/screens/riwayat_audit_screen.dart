import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';

/// <h3>Layar "History" -- jelajah tabel audit (Envers/AuditTrails) LINTAS baris.</h3>
///
/// Padanan tab "Semua" pada `GenericRevisiHelper` versi ZK, dan pelengkap tombol
/// jam per baris yang sudah ada di tabel-tabel master.
///
/// <p>Perbedaannya penting: tombol jam per baris menuntut barisnya masih ada di
/// layar untuk diklik. Baris yang <b>sudah terhapus</b> tidak muncul di mana pun,
/// jadi tidak ada yang bisa diklik -- satu-satunya jalan menemukannya kembali
/// adalah menyapu tabel audit menurut rentang tanggal. Itulah yang layar ini
/// lakukan.</p>
///
/// <p>Rentang tanggal wajib (sama seperti versi ZK): tabel audit menyimpan seluruh
/// sejarah, dan menyapunya tanpa batas akan menarik jutaan baris.</p>
///
/// <p>Server membatasi aksinya ke ADMINISTRATOR karena hasilnya memuat data
/// terhapus dari seluruh toko -- melewati pembatasan toko/pendaftar yang berlaku
/// di layar biasa. Bila ditolak, pesannya ditampilkan apa adanya.</p>
class RiwayatAuditScreen extends StatefulWidget {
  /// Kode entitas awal (lihat whitelist `RevisiApiHelper.ENTITAS`).
  final String entitasAwal;

  /// Tipe revisi awal: `SEMUA` | `TAMBAH` | `UBAH` | `HAPUS`.
  final String tipeAwal;

  /// Menu yang disorot di sidebar -- layar ini selalu dibuka dari layar lain.
  final MenuEBisnis menuAktif;

  /// Label tombol kembali, mengikuti layar pemanggil.
  final String labelKembali;

  const RiwayatAuditScreen({
    super.key,
    this.entitasAwal = 'pesanan',
    this.tipeAwal = 'SEMUA',
    this.menuAktif = MenuEBisnis.pesanan,
    this.labelKembali = 'Kembali',
  });

  @override
  State<RiwayatAuditScreen> createState() => _RiwayatAuditScreenState();
}

class _RiwayatAuditScreenState extends State<RiwayatAuditScreen>
    with JejakGalat {
  static final _fTanggal = DateFormat('yyyy-MM-dd');
  static final _fTampil = DateFormat('dd/MM/yyyy');
  static final _fAngka = NumberFormat.decimalPattern('id');

  /// Label yang lebih ramah daripada kode entitas mentah dari server. Kode yang
  /// tidak terdaftar di sini tetap tampil apa adanya -- daftar entitas di server
  /// bertambah dari waktu ke waktu, dan layar ini tidak boleh ikut usang.
  static const Map<String, String> _labelEntitas = {
    'pesanan': 'Pesanan (draft pembelian anggota)',
    'pesanan_item': 'Item Pesanan',
    'pembelian': 'Transaksi Pembelian',
    'transaksi': 'Transaksi (nota lunas)',
    'produk': 'Produk',
    'anggota': 'Anggota/Member',
    'toko': 'Toko',
    'diskon': 'Aturan Diskon',
    'cara_bayar': 'Cara Pembayaran',
  };

  /// Kolom yang paling menolong saat menelusuri baris hilang, ditampilkan lebih
  /// dulu bila ada. Sisanya menyusul sesuai urutan dari server.
  static const List<String> _kolomUtama = [
    'kode',
    'oleh',
    'tanggalPembayaran',
    'totalBiaya',
    'bayar',
    'toko',
    'anggotaKoperasi',
    'keterangan',
  ];

  late String _entitas = widget.entitasAwal;
  late String _tipe = widget.tipeAwal;
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();
  int? _toko;

  List<Map<String, dynamic>> _daftarEntitas = const [];
  final List<Map<String, dynamic>> _hasil = [];
  bool _memuat = false;
  bool _adaLagi = false;
  String? _galat;
  bool _pernahCari = false;

  @override
  void initState() {
    super.initState();
    _toko = Sesi.instance.tokoFilter;
    _muatDaftarEntitas();
  }

  Future<void> _muatDaftarEntitas() async {
    try {
      final res = await ApiClient.instance.aksi('revisi_entitas');
      if (res['status'] != '00') return;
      final data = (res['data'] as List?) ?? const [];
      setStateIfMounted(() {
        _daftarEntitas =
            data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      // Combo entitas gagal dimuat bukan alasan menutup layar: entitas awal
      // dari pemanggil tetap bisa dicari.
    }
  }

  Future<void> _cari({bool lanjut = false}) async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
      _pernahCari = true;
      if (!lanjut) _hasil.clear();
    });
    try {
      final res = await ApiClient.instance.aksi('revisi_jelajah', {
        'entitas': _entitas,
        'dari': _fTanggal.format(_dari),
        'sampai': _fTanggal.format(_sampai),
        'tipe': _tipe,
        if (_toko != null) 'toko': _toko,
        'batas': 100,
        'mulai': lanjut ? _hasil.length : 0,
      });
      if (res['status'] != '00') {
        throw Exception(res['description'] ?? 'Gagal memuat riwayat.');
      }
      final data = (res['data'] as List?) ?? const [];
      setStateIfMounted(() {
        _hasil.addAll(
            data.map((e) => Map<String, dynamic>.from(e as Map)).toList());
        _adaLagi = res['adaLagi'] == true;
      });
    } catch (e) {
      setStateIfMounted(() => _galat = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihTanggal({required bool awal}) async {
    final kini = DateTime.now();
    final pilih = await showDatePicker(
      context: context,
      initialDate: awal ? _dari : _sampai,
      firstDate: DateTime(kini.year - 8),
      // Audit tidak pernah memuat kejadian masa depan.
      lastDate: kini,
      helpText: awal ? 'Riwayat sejak tanggal' : 'Riwayat sampai tanggal',
    );
    if (pilih == null) return;
    setStateIfMounted(() {
      if (awal) {
        _dari = pilih;
        if (_dari.isAfter(_sampai)) _sampai = _dari;
      } else {
        _sampai = pilih;
        if (_sampai.isBefore(_dari)) _dari = _sampai;
      }
    });
  }

  String _labelKode(String kode) => _labelEntitas[kode] ?? kode;

  Color _warnaTipe(String tipe) {
    if (tipe == 'HAPUS') return AppColors.danger;
    if (tipe == 'TAMBAH') return AppColors.success;
    return AppColors.warning;
  }

  /// Nilai `ringkas` dirapikan seadanya: angka diberi pemisah ribuan, sisanya
  /// apa adanya. Sengaja tidak menebak satuan/mata uang -- ini layar forensik,
  /// nilai mentah justru lebih dipercaya daripada nilai yang sudah "dipercantik".
  String _nilaiTampil(Object? v) {
    if (v == null) return '-';
    if (v is num) return _fAngka.format(v);
    return '$v';
  }

  List<String> _urutKunci(Map<String, dynamic> ringkas) {
    final kunci = <String>[];
    for (final k in _kolomUtama) {
      if (ringkas.containsKey(k)) kunci.add(k);
    }
    for (final k in ringkas.keys) {
      if (!kunci.contains(k)) kunci.add(k);
    }
    return kunci;
  }

  Widget _filter() {
    final daftar = _daftarEntitas.isEmpty
        ? [
            {'kode': _entitas}
          ]
        : _daftarEntitas;
    final adaKode = daftar.any((e) => e['kode'] == _entitas);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                value: adaKode ? _entitas : daftar.first['kode'] as String,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Jenis data',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: daftar
                    .map((e) => DropdownMenuItem<String>(
                          value: '${e['kode']}',
                          child: Text(_labelKode('${e['kode']}'),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: _memuat
                    ? null
                    : (v) => setStateIfMounted(() => _entitas = v ?? _entitas),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _memuat ? null : () => _pilihTanggal(awal: true),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('Dari ${_fTampil.format(_dari)}'),
            ),
            OutlinedButton.icon(
              onPressed: _memuat ? null : () => _pilihTanggal(awal: false),
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text('Sampai ${_fTampil.format(_sampai)}'),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _tipe,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Perubahan',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'SEMUA', child: Text('Semua')),
                  DropdownMenuItem(value: 'HAPUS', child: Text('Terhapus')),
                  DropdownMenuItem(value: 'UBAH', child: Text('Diubah')),
                  DropdownMenuItem(value: 'TAMBAH', child: Text('Ditambah')),
                ],
                onChanged: _memuat
                    ? null
                    : (v) => setStateIfMounted(() => _tipe = v ?? _tipe),
              ),
            ),
            if (Sesi.instance.bolehSemuaToko &&
                Sesi.instance.daftarTokoFilter.isNotEmpty)
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<int?>(
                  value: _toko,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Toko',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Semua Toko')),
                    ...Sesi.instance.daftarTokoFilter.map(
                      (t) => DropdownMenuItem<int?>(
                        value: t['id'] as int?,
                        child: Text('${t['nama'] ?? ''}',
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged:
                      _memuat ? null : (v) => setStateIfMounted(() => _toko = v),
                ),
              ),
            FilledButton.icon(
              onPressed: _memuat ? null : () => _cari(),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Cari'),
            ),
            if (_memuat)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  Widget _baris(Map<String, dynamic> r) {
    final tipe = '${r['tipe'] ?? ''}';
    final ringkas = r['ringkas'] is Map
        ? Map<String, dynamic>.from(r['ringkas'] as Map)
        : <String, dynamic>{};
    final kunci = _urutKunci(ringkas);
    final id = r['id'];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: id == null
            ? null
            : () => tampilkanRiwayatData(
                  context,
                  entitas: _entitas,
                  id: id,
                  judul: '${_labelKode(_entitas)} #$id',
                ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _warnaTipe(tipe).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tipe,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _warnaTipe(tipe),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('#${id ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${r['tanggal'] ?? ''}   (rev ${r['rev'] ?? '-'})',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
              if (kunci.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: kunci
                      .take(10)
                      .map((k) => Text(
                            '$k: ${_nilaiTampil(ringkas[k])}',
                            style: const TextStyle(fontSize: 12),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _isi() {
    if (_galat != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(height: 8),
            Text(_galat!),
          ],
        ),
      );
    }
    if (!_pernahCari) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'Tentukan jenis data dan rentang tanggal, lalu tekan Cari.\n'
          'Pilih "Terhapus" untuk menemukan baris yang sudah lenyap dari layar '
          'biasa -- termasuk transaksi yang hilang dari daftar.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    if (_hasil.isEmpty && !_memuat) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'Tidak ada perubahan tercatat pada rentang itu.\n'
          'Perlu diingat: audit hanya merekam perubahan yang lewat aplikasi. '
          'Baris yang dihapus langsung di basis data TIDAK meninggalkan jejak '
          'di sini.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_hasil.length} perubahan${_adaLagi ? '+ (masih ada lagi)' : ''}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        ..._hasil.map(_baris),
        if (_adaLagi)
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: _memuat ? null : () => _cari(lanjut: true),
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('Muat lagi'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: widget.menuAktif,
      judul: 'History (Riwayat Audit)',
      subjudul: 'Menelusuri tabel audit -- termasuk baris yang sudah terhapus',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(widget.labelKembali),
            ),
          ),
          const SizedBox(height: 8),
          _filter(),
          const SizedBox(height: 12),
          _isi(),
        ],
      ),
    );
  }
}
