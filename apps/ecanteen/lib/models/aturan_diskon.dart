/// Satu baris aturan diskon dari aksi `kantin_aturan_diskon`.
///
/// Nilai boolean dari server bisa datang sebagai `true`, `"true"`, atau `"t"`
/// (Postgres) -- persis seperti yang ditangani versi JSP, jadi pembacaannya
/// dibuat toleran.
class AturanDiskon {
  final String id;
  final String? produk;
  final String? toko;
  final bool berlakuSemuaMember;
  final String? jenisAnggota;
  final String? tipeAnggota;
  final double persentase;
  final double maksimalPotongan;
  final double nominal;
  final bool potonganLangsung;
  final bool berlakuPerHariDanPerToko;
  final DateTime? tanggalMulai;
  final DateTime? tanggalSelesai;

  /// Sudah terpakai hari ini (dari server) -- batas harian per aturan.
  double terpakaiHariIni;

  /// Akumulator sementara selama menghitung ulang keranjang.
  double terpakaiDiKeranjang = 0;

  AturanDiskon({
    required this.id,
    this.produk,
    this.toko,
    required this.berlakuSemuaMember,
    this.jenisAnggota,
    this.tipeAnggota,
    required this.persentase,
    required this.maksimalPotongan,
    required this.nominal,
    required this.potonganLangsung,
    required this.berlakuPerHariDanPerToko,
    this.tanggalMulai,
    this.tanggalSelesai,
    this.terpakaiHariIni = 0,
  });

  factory AturanDiskon.dariJson(Map<String, dynamic> j) => AturanDiskon(
        id: '${j['id'] ?? ''}',
        produk: _teksAtauNull(j['produk']),
        toko: _teksAtauNull(j['toko']),
        berlakuSemuaMember: _bool(j['berlaku_semua_member']),
        jenisAnggota: _teksAtauNull(j['jenis_anggota']),
        tipeAnggota: _teksAtauNull(j['tipe_anggota']),
        persentase: _double(j['persentase']),
        maksimalPotongan: _double(j['maksimal_potongan']),
        nominal: _double(j['nominal']),
        potonganLangsung: _bool(j['potongan_langsung']),
        berlakuPerHariDanPerToko: _bool(j['berlaku_per_hari_dan_per_toko']),
        tanggalMulai: _tanggal(j['tanggal_mulai_iso'] ?? j['tanggal_mulai']),
        tanggalSelesai:
            _tanggal(j['tanggal_selesai_iso'] ?? j['tanggal_selesai']),
        terpakaiHariIni: _double(j['terpakai_hari_ini']),
      );

  static String? _teksAtauNull(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static bool _bool(Object? v) {
    if (v is bool) return v;
    final s = '$v'.trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }

  static double _double(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.replaceAll(',', '.')) ?? 0;
  }

  static DateTime? _tanggal(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    if (s.isEmpty || s == 'null') return null;
    return DateTime.tryParse(s);
  }
}
