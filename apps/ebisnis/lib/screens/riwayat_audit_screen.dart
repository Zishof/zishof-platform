import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';

/// <h3>Layar "History" -- jelajah tabel audit (Envers/AuditTrails) LINTAS baris,
/// lengkap dengan restore satuan maupun massal.</h3>
///
/// Meniru pola `GenericRevisiHelper` (ZK): saring dulu, lihat hasilnya, baru
/// pulihkan -- satu per satu, atau seluruh yang cocok dengan saringan.
///
/// <p>Perbedaannya dengan tombol jam per baris yang sudah ada di tabel master
/// penting: tombol itu menuntut barisnya MASIH ADA untuk diklik. Baris yang sudah
/// terhapus tidak muncul di mana pun, jadi tidak ada yang bisa diklik -- padahal
/// justru baris itulah yang dicari. Layar ini menyapu tabel audit menurut rentang
/// tanggal, bukan menunggu seseorang menemukan barisnya lebih dulu.</p>
///
/// <p><b>Aturan revisi mana yang dipulihkan</b> disalin dari versi ZK: revisi
/// diurutkan dari terbaru, revisi bertipe HAPUS dilewati, lalu revisi pertama yang
/// tersisa untuk tiap baris dipakai. Artinya yang kembali adalah keadaan terakhir
/// SEBELUM baris itu dihapus.</p>
///
/// <p>Restore satuan dan restore massal memakai aksi server yang sama
/// (`revisi_pulihkan_massal`, yang satuan hanya menambah saringan id). Itu
/// disengaja: kalau jalurnya dipisah, "Pulihkan baris ini" dan "Pulihkan semua"
/// akan menyimpang pelan-pelan sampai artinya berbeda bagi yang menekannya.</p>
class RiwayatAuditScreen extends StatefulWidget {
  /// Kode entitas awal (lihat whitelist `RevisiApiHelper.ENTITAS`).
  final String entitasAwal;

  /// Tipe revisi awal: `SEMUA` | `TAMBAH` | `UBAH` | `HAPUS`.
  final String tipeAwal;

  /// Menu yang disorot di sidebar -- layar ini selalu dibuka dari layar lain.
  final MenuEBisnis menuAktif;

  /// Label tombol kembali, mengikuti layar pemanggil.
  final String labelKembali;

  /// Bila true, hanya isi audit yang dirender di dalam tab layar lain tanpa
  /// membuat AppShell/sidebar kedua.
  final bool embedded;

  const RiwayatAuditScreen({
    super.key,
    this.entitasAwal = 'produk',
    this.tipeAwal = 'SEMUA',
    this.menuAktif = MenuEBisnis.pesanan,
    this.labelKembali = 'Kembali',
    this.embedded = false,
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
    'jenis_produk': 'Jenis/Kategori Produk',
    'grup_produk': 'Grup Produk',
    'penyedia': 'Penyedia',
    'jenis_anggota': 'Jenis Member',
    'tipe_anggota': 'Tipe Member',
    'kebijakan_retur': 'Kebijakan Retur',
    'diskon_grup': 'Grup Aturan Diskon',
    'produk_batch': 'Batch Produk',
    'si_customer': 'Customer Inventory & Sales',
    'si_sales': 'Sales Inventory & Sales',
    'si_supplier': 'Supplier Inventory & Sales',
    'pencairan_diskon': 'Pencairan Diskon',
    'apotik_item': 'Profil Item Apotek',
    'satuan_produk': 'Satuan/UOM Produk',
    'pemasok_produk': 'Pemasok Produk',
    'pengadaan_faktur': 'Faktur Kulakan',
    'pengadaan_produk': 'Item Kulakan',
    'stok_opname': 'Detail Stok Opname',
    'sesi_stok_opname': 'Sesi Stok Opname',
    'mutasi_stok': 'Mutasi Stok Antar Outlet',
    'retur_penjualan': 'Retur Penjualan',
    'retur_pembelian': 'Retur Pembelian',
    'produksi': 'Produksi',
    'pemakaian_bahan_baku': 'Pemakaian Bahan Baku',
    'sesi_kas': 'Sesi Kas Kasir',
    'calon_anggota': 'Calon/Pengajuan Member',
    'jenis_identitas_anggota': 'Jenis Identitas Member',
    'pengajuan_limit_member': 'Pengajuan Limit Member',
    'pembayaran_anggota': 'Pembayaran Member',
    'penyesuaian_saldo_anggota': 'Penyesuaian Saldo Member',
    'pembayaran_hutang_supplier': 'Pembayaran Hutang Supplier',
    'penerimaan_piutang_customer': 'Penerimaan Piutang Customer',
    'harga_jual_customer': 'Harga Jual Customer',
    'harga_beli_supplier': 'Harga Beli Supplier',
    'pengadaan_pr': 'Pengadaan — Purchase Request',
    'pengadaan_po': 'Pengadaan — Purchase Order',
    'pengadaan_bast': 'Pengadaan — BAST',
    'pengadaan_bayar': 'Pengadaan — Pembayaran',
    'hotel_properti': 'Hotel — Properti',
    'hotel_kontrak': 'Hotel — Kontrak Pemilik',
    'hotel_tamu': 'Hotel — Tamu',
    'hotel_tipe_kamar': 'Hotel — Tipe Kamar',
    'hotel_kamar': 'Hotel — Kamar',
    'ujian': 'Ujian',
    'ujian_soal': 'Soal Ujian',
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
  final _kataKunciCtl = TextEditingController();
  final _nilaiKolomCtl = TextEditingController();
  String? _kolom;

  List<Map<String, dynamic>> _daftarEntitas = const [];
  List<Map<String, dynamic>> _kolomTersedia = const [];
  final List<Map<String, dynamic>> _hasil = [];
  bool _memuat = false;
  bool _memulihkan = false;
  bool _adaLagi = false;
  String? _galat;
  bool _pernahCari = false;

  @override
  void initState() {
    super.initState();
    _toko = Sesi.instance.tokoFilter;
    _muatDaftarEntitas();
  }

  @override
  void dispose() {
    _kataKunciCtl.dispose();
    _nilaiKolomCtl.dispose();
    super.dispose();
  }

  Future<void> _muatDaftarEntitas() async {
    try {
      final res = await ApiClient.instance.aksi('revisi_entitas');
      if (!ApiClient.statusResponsSukses(res['status'])) return;
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

  /// Saringan yang sedang berlaku. Dipakai untuk mencari DAN untuk memulihkan,
  /// dari satu tempat -- supaya yang terlihat di layar dan yang akan dipulihkan
  /// tidak mungkin berasal dari saringan yang berbeda.
  Map<String, dynamic> _saringan() {
    final kata = _kataKunciCtl.text.trim();
    final nilai = _nilaiKolomCtl.text.trim();
    return {
      'entitas': _entitas,
      'dari': _fTanggal.format(_dari),
      'sampai': _fTanggal.format(_sampai),
      'tipe': _tipe,
      if (_toko != null) 'toko': _toko,
      if (kata.isNotEmpty) 'kataKunci': kata,
      if (_kolom != null && nilai.isNotEmpty) 'kolom': _kolom,
      if (_kolom != null && nilai.isNotEmpty) 'nilai': nilai,
    };
  }

  String _ringkasanSaringan() {
    final bagian = <String>[
      _labelKode(_entitas),
      '${_fTampil.format(_dari)} s/d ${_fTampil.format(_sampai)}',
      _tipe == 'SEMUA' ? 'semua perubahan' : _tipe.toLowerCase(),
    ];
    if (_toko != null) bagian.add('toko #$_toko');
    final kata = _kataKunciCtl.text.trim();
    if (kata.isNotEmpty) bagian.add('kata kunci "$kata"');
    final nilai = _nilaiKolomCtl.text.trim();
    if (_kolom != null && nilai.isNotEmpty) bagian.add('$_kolom = "$nilai"');
    return bagian.join(' · ');
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
        ..._saringan(),
        'batas': 100,
        'mulai': lanjut ? _hasil.length : 0,
      });
      if (!ApiClient.statusResponsSukses(res['status'])) {
        throw Exception(res['description'] ?? 'Gagal memuat riwayat.');
      }
      final data = (res['data'] as List?) ?? const [];
      final kolom = (res['kolom'] as List?) ?? const [];
      setStateIfMounted(() {
        _hasil.addAll(
            data.map((e) => Map<String, dynamic>.from(e as Map)).toList());
        _adaLagi = res['adaLagi'] == true;
        if (kolom.isNotEmpty) {
          _kolomTersedia =
              kolom.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          if (_kolom != null &&
              !_kolomTersedia.any((k) => k['nama'] == _kolom)) {
            // Ganti entitas -> kolom lama bisa tidak ada lagi di entitas baru.
            _kolom = null;
            _nilaiKolomCtl.clear();
          }
        }
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

  // ── Restore ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _jalankanRestore({
    Object? id,
    required bool simulasi,
    required bool timpa,
  }) async {
    try {
      // ONLINE-ONLY: pemulihan massal dijalankan SERVER di atas jejak auditnya
      // sendiri; perangkat tidak menyimpan versi lama yang jadi bahannya.
      final res = await ApiClient.instance.aksi('revisi_pulihkan_massal', {
        ..._saringan(),
        if (id != null) 'id': id,
        'simulasi': simulasi,
        'timpaYangMasihAda': timpa,
      });
      if (!ApiClient.statusResponsSukses(res['status'])) {
        throw Exception(res['description'] ?? 'Restore ditolak server.');
      }
      return res;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(terapkanGalat(e))));
      }
      return null;
    }
  }

  /// Alur restore: hitung dulu (tanpa menulis apa pun), tampilkan hasil hitungan,
  /// baru minta persetujuan. Restore massal tidak punya tombol "batal" -- begitu
  /// baris tertulis, keadaan sebelumnya hanya bisa dikejar lewat revisi baru.
  Future<void> _pulihkan({Object? id}) async {
    setStateIfMounted(() => _memulihkan = true);
    try {
      bool timpa = false;
      final hitung =
          await _jalankanRestore(id: id, simulasi: true, timpa: timpa);
      if (hitung == null || !mounted) return;

      final akan = (hitung['akanDipulihkan'] as num?)?.toInt() ?? 0;
      final kandidat = (hitung['kandidat'] as num?)?.toInt() ?? 0;
      final masihAda = (hitung['dilewatiMasihAda'] as num?)?.toInt() ?? 0;

      if (akan == 0 && masihAda == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tidak ada baris yang bisa dipulihkan.')));
        return;
      }

      final setuju = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLokal) => AlertDialog(
            title: Text(id == null
                ? 'Pulihkan semua yang cocok?'
                : 'Pulihkan baris #$id?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (id == null) ...[
                  const Text('Saringan yang berlaku:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(_ringkasanSaringan(),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                ],
                Text('$kandidat baris punya revisi yang bisa dipakai.'),
                Text('$akan akan dihidupkan kembali (datanya sekarang hilang).',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                // Angka ini HARUS ikut berubah saat "timpa" dicentang. Hitungan
                // tadi dibuat dengan timpa=false; membiarkannya diam berarti
                // dialog menampilkan jumlah yang bukan jumlah yang akan terjadi.
                if (masihAda > 0)
                  Text(
                    timpa
                        ? '$masihAda baris yang masih ada IKUT ditimpa '
                            '(total ${akan + masihAda} baris ditulis).'
                        : '$masihAda dilewati karena datanya masih ada.',
                    style: TextStyle(
                      color: timpa ? AppColors.danger : AppColors.textSecondary,
                      fontWeight: timpa ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Yang dipulihkan adalah keadaan terakhir sebelum baris dihapus '
                  '(revisi HAPUS sendiri dilewati) — sama seperti "Restore Terbaru" '
                  'di versi ZKoss.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: timpa,
                  title: const Text('Timpa juga baris yang masih ada',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    'Data yang sedang dipakai akan ditulis ulang dengan nilai '
                    'revisi. Tidak bisa dibatalkan.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) => setLokal(() => timpa = v ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Pulihkan')),
            ],
          ),
        ),
      );
      if (setuju != true || !mounted) return;

      final hasil =
          await _jalankanRestore(id: id, simulasi: false, timpa: timpa);
      if (hasil == null || !mounted) return;
      await _tampilkanLaporan(hasil);
      if (mounted) await _cari();
    } finally {
      setStateIfMounted(() => _memulihkan = false);
    }
  }

  /// <h3>Perbaikan susulan nota yang tercatat bayar Rp 0.</h3>
  ///
  /// Bukan bagian dari audit, tetapi tinggal di layar yang sama karena
  /// penontonnya sama: administrator yang sedang membereskan data. Aturannya
  /// dijalankan SERVER dengan method yang sama dengan penjaga saat menyimpan,
  /// jadi layar ini tidak punya versi aturannya sendiri yang bisa menyimpang.
  ///
  /// Sama seperti restore massal: dihitung dulu tanpa menulis apa pun, hasil
  /// hitungan ditampilkan, baru dimintakan persetujuan.
  Future<void> _perbaikiNilaiBayar() async {
    setStateIfMounted(() => _memulihkan = true);
    try {
      Map<String, dynamic> minta(bool simulasi) => {
            'dari': _fTanggal.format(_dari),
            'sampai': _fTanggal.format(_sampai),
            if (_toko != null) 'toko': _toko,
            'simulasi': simulasi,
            'batas': 500,
          };

      Map<String, dynamic>? hitung;
      try {
        final res =
            await ApiClient.instance.aksi('perbaiki_nilai_bayar', minta(true));
        if (!ApiClient.statusResponsSukses(res['status'])) {
          throw Exception(res['description'] ?? 'Perhitungan ditolak server.');
        }
        hitung = res;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(terapkanGalat(e))));
        }
        return;
      }
      if (!mounted) return;

      final akan = (hitung['diperbaiki'] as num?)?.toInt() ?? 0;
      final dilewati = (hitung['dilewati'] as num?)?.toInt() ?? 0;
      if (akan == 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Tidak ada nota yang perlu diperbaiki pada rentang '
                'itu${dilewati > 0 ? ' ($dilewati dilewati karena piutangnya sah).' : '.'}')));
        return;
      }

      final setuju = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Perbaiki nilai bayar yang kosong?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_fTampil.format(_dari)} s/d ${_fTampil.format(_sampai)}'
                  '${_toko == null ? ' · semua toko' : ' · toko #$_toko'}'),
              const SizedBox(height: 10),
              Text(
                  '$akan nota akan diisi nilai bayarnya sesuai metode '
                  'pembayarannya sendiri.',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (dilewati > 0)
                Text(
                    '$dilewati nota dilewati karena piutangnya SAH '
                    '(metode bertanda hutang) atau tanpa metode bayar.',
                    style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              const Text(
                'Nota yang dibayar sebagian dan nota yang sudah benar tidak '
                'tersentuh. Perubahan ini tidak dapat dibatalkan, tetapi '
                'terekam di riwayat audit tiap nota.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Perbaiki')),
          ],
        ),
      );
      if (setuju != true || !mounted) return;

      try {
        final res =
            await ApiClient.instance.aksi('perbaiki_nilai_bayar', minta(false));
        if (!ApiClient.statusResponsSukses(res['status'])) {
          throw Exception(res['description'] ?? 'Perbaikan ditolak server.');
        }
        if (mounted) await _tampilkanLaporan(res);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(terapkanGalat(e))));
        }
      }
    } finally {
      setStateIfMounted(() => _memulihkan = false);
    }
  }

  Future<void> _tampilkanLaporan(Map<String, dynamic> hasil) async {
    final rincian = (hasil['rincian'] as List?) ?? const [];
    final gagal = (hasil['gagal'] as num?)?.toInt() ?? 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gagal > 0 ? 'Selesai, sebagian gagal' : 'Restore selesai'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${hasil['description'] ?? ''}'),
              if (hasil['terpotong'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Sapuan dihentikan pada batas aman. Jalankan sekali lagi '
                    'untuk sisanya.',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              if (rincian.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Rincian:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rincian.take(60).map((r) {
                        final m = Map<String, dynamic>.from(r as Map);
                        final st = '${m['status'] ?? ''}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            '#${m['id']}  $st'
                            '${m['pesan'] != null ? ' — ${m['pesan']}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: st == 'GAGAL'
                                  ? AppColors.danger
                                  : AppColors.textSecondary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                if (rincian.length > 60)
                  Text('... dan ${rincian.length - 60} baris lagi',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  // ── Tampilan ──────────────────────────────────────────────────────────────

  String _ramah(String kode) {
    final bersih = kode
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ');
    if (bersih.isEmpty) return kode;
    return bersih
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');
  }

  String _labelKode(String kode) => _labelEntitas[kode] ?? _ramah(kode);

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
    final sibuk = _memuat || _memulihkan;
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
                onChanged: sibuk
                    ? null
                    : (v) => setStateIfMounted(() {
                          _entitas = v ?? _entitas;
                          // Kolom saringan milik entitas lama tidak berlaku lagi.
                          _kolom = null;
                          _nilaiKolomCtl.clear();
                          _kolomTersedia = const [];
                        }),
              ),
            ),
            OutlinedButton.icon(
              onPressed: sibuk ? null : () => _pilihTanggal(awal: true),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('Dari ${_fTampil.format(_dari)}'),
            ),
            OutlinedButton.icon(
              onPressed: sibuk ? null : () => _pilihTanggal(awal: false),
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
                onChanged: sibuk
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
                      sibuk ? null : (v) => setStateIfMounted(() => _toko = v),
                ),
              ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _kataKunciCtl,
                enabled: !sibuk,
                decoration: const InputDecoration(
                  labelText: 'Kata kunci',
                  hintText: 'dicari di semua kolom teks',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: sibuk ? null : (_) => _cari(),
              ),
            ),
            // Saringan kolom baru bisa dipakai setelah pencarian pertama:
            // daftar kolomnya datang dari server bersama hasil, bukan ditebak
            // di klien -- kolom yang ditebak akan meleset begitu Model berubah.
            if (_kolomTersedia.isNotEmpty) ...[
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  value: _kolom,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kolom tertentu',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('(tidak dipakai)')),
                    ..._kolomTersedia.map(
                      (k) => DropdownMenuItem<String?>(
                        value: '${k['nama']}',
                        child: Text('${k['nama']}',
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged:
                      sibuk ? null : (v) => setStateIfMounted(() => _kolom = v),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _nilaiKolomCtl,
                  enabled: !sibuk && _kolom != null,
                  decoration: const InputDecoration(
                    labelText: 'Nilai kolom',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: sibuk ? null : (_) => _cari(),
                ),
              ),
            ],
            FilledButton.icon(
              onPressed: sibuk ? null : () => _cari(),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Cari'),
            ),
            if (_pernahCari && _hasil.isNotEmpty)
              OutlinedButton.icon(
                onPressed: sibuk ? null : () => _pulihkan(),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Pulihkan Semua (sesuai filter)'),
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            // Tidak bergantung pada hasil pencarian audit: yang diperbaiki adalah
            // nota bernilai bayar kosong pada rentang tanggal, bukan baris audit
            // yang sedang tampil.
            OutlinedButton.icon(
              onPressed: sibuk ? null : _perbaikiNilaiBayar,
              icon: const Icon(Icons.healing_outlined, size: 18),
              label: const Text('Perbaiki Nilai Bayar Kosong'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.info),
            ),
            if (sibuk)
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                  if (id != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Pulihkan data terakhir baris ini',
                      icon: const Icon(Icons.restore, size: 18),
                      onPressed: _memulihkan ? null : () => _pulihkan(id: id),
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
                            '${_ramah(k)}: ${_nilaiTampil(ringkas[k])}',
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
            '${_hasil.length} perubahan${_adaLagi ? '+ (masih ada lagi)' : ''}'
            '  ·  ${_ringkasanSaringan()}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    final isi = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(widget.labelKembali),
            ),
          ),
          const SizedBox(height: 8),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Riwayat CRUD dibaca langsung dari tabel audit server. Pilih '
              'jenis data Member untuk perubahan pelanggan, atau ganti Jenis '
              'Data untuk memantau CRUD POS lain. Klik baris untuk melihat '
              'nilai dari → menjadi.',
            ),
          ),
          const SizedBox(height: 8),
        ],
        _filter(),
        const SizedBox(height: 12),
        _isi(),
      ],
    );
    if (widget.embedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: isi,
      );
    }
    return AppShell(
      menuAktif: widget.menuAktif,
      judul: 'Riwayat Perubahan Data',
      subjudul:
          'Pantau seluruh CRUD POS dari tabel audit server, termasuk data terhapus',
      body: isi,
    );
  }
}
