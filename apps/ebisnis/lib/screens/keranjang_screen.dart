import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../product_profile.dart';
import '../sesi.dart';
import '../services/layar_pelanggan_broadcaster.dart';
import '../services/pengaturan_nomor_struk.dart';
import '../services/pengaturan_pembayaran.dart';
import '../services/transaksi_outbox_service.dart';
import '../services/biometric_capture_bridge.dart';
import '../theme/app_colors.dart';
import 'struk_screen.dart';
import '../widgets/safe_state.dart';
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/jejak_galat.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

const _alasanTahanBawaan = <String>[
  'Pelanggan masih memilih barang',
  'Pelanggan mengambil uang',
  'Pelanggan mengambil kartu pembayaran',
  'Pelanggan membuka aplikasi pembayaran',
  'Menunggu konfirmasi harga',
  'Menunggu pengecekan stok',
  'Menunggu persetujuan supervisor',
  'Menunggu data member',
  'Menunggu perubahan metode pembayaran',
  'Menunggu pembayaran tunai',
  'Menunggu pembayaran QRIS',
  'Menunggu pembayaran transfer',
  'Menunggu saldo member mencukupi',
  'Menunggu pesanan dilengkapi',
  'Barang perlu ditimbang ulang',
  'Barcode atau produk perlu diperiksa',
  'Antrean dialihkan sementara',
  'Pelanggan akan kembali',
  'Pesanan perlu dikonfirmasi ulang',
  'Kendala jaringan atau perangkat sementara',
];

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
  final String? draftKodeSumber;
  final Anggota? memberAwal;
  final DateTime? waktuTransaksiAwal;
  final bool semuaCaraBayarUntukMemberAwal;
  const KeranjangScreen(
      {super.key,
      required this.keranjang,
      this.draftIdSumber,
      this.draftKodeSumber,
      this.memberAwal,
      this.waktuTransaksiAwal,
      this.semuaCaraBayarUntukMemberAwal = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: PanelKeranjang(
          keranjang: keranjang,
          draftIdSumber: draftIdSumber,
          draftKodeSumber: draftKodeSumber,
          memberAwal: memberAwal,
          waktuTransaksiAwal: waktuTransaksiAwal,
          semuaCaraBayarUntukMemberAwal: semuaCaraBayarUntukMemberAwal),
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
  final String? draftKodeSumber;
  final Anggota? memberAwal;
  final DateTime? waktuTransaksiAwal;
  final bool semuaCaraBayarUntukMemberAwal;
  final Widget? pencarianBarang;

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
    this.draftKodeSumber,
    this.memberAwal,
    this.waktuTransaksiAwal,
    this.semuaCaraBayarUntukMemberAwal = false,
    this.pencarianBarang,
    this.tampilkanJudul = false,
    this.aksiHeader,
    this.onSelesai,
  });

  @override
  State<PanelKeranjang> createState() => _PanelKeranjangState();
}

class _PanelKeranjangState extends State<PanelKeranjang> {
  static const _pageSizeKeranjang = 15;
  List<CaraBayar> _caraBayarTersedia = [];
  CaraBayar? _caraBayarTerpilih;

  /// Split pembayaran (s/d 5 metode/transaksi, mis. separuh Transfer + separuh
  /// Tunai): kosong ATAU 1 elemen = mode lama satu-metode (identik perilaku
  /// sebelum fitur ini ada, `_caraBayarTerpilih` tetap sumber kebenaran).
  /// >=2 elemen = mode split aktif; elemen pertama SELALU sama dgn
  /// `_caraBayarTerpilih` (slot 1 di payload/server), sisanya dikirim sbg
  /// `caraBayarTambahan`. Lihat `_SheetPilihMetodeSplit`.
  List<_SlotBayar> _splitBayar = [];
  bool _memuatCaraBayar = false;
  bool _izinCaraBayarMemberTidakDisetel = false;
  bool _caraBayarDikunciTipe = false;
  int _versiPermintaanCaraBayar = 0;
  late bool _semuaCaraBayarUntukMemberAwal;
  bool _memproses = false;
  Anggota? _memberTerpilih;
  double? _saldoMember;

  /// Kode transaksi yang sudah menghasilkan pengajuan limit di server.
  ///
  /// Persetujuan supervisor diikat ke member, nominal, dan kode transaksi yang
  /// tepat. Karena itu percobaan Bayar setelah pengajuan disetujui wajib memakai
  /// kembali kode ini, bukan membuat nomor struk baru. Nilai dibersihkan hanya
  /// setelah pembayaran benar-benar berhasil.
  String? _kodePengajuanLimitTertunda;

  /// Metadata tampilan promo manual, dipetakan berdasarkan id aturan. Sumber
  /// kebenaran tetap berada pada setiap [ItemKeranjang], sehingga dua barang
  /// dalam transaksi yang sama boleh menggunakan promo/cashback berbeda.
  final Map<int, Map<String, dynamic>> _metadataPromoManual = {};
  Timer? _debounceDiskon;
  final _uangDiterimaController = TextEditingController(text: '0');
  String _tipeDiskonFaktur = 'NOMINAL';
  double _nilaiDiskonFaktur = 0;
  bool _uangDiterimaManual = false;
  int _halamanKeranjang = 1;
  ItemKeranjang? _itemTeratasTerakhir;
  bool _langsungTerlayani = true;
  late DateTime _waktuTransaksi;

  /// MitraInap LANGKAH 4: transaksi outlet ini ditagihkan ke folio kamar.
  /// Berisi baris dari aksi `hotel_room_charge_lookup`
  /// ({id, tamu_nama, kamar_nomor, properti_id, properti_nama}); null =
  /// pembayaran biasa. Server memvalidasi ulang (in-house + folio OPEN)
  /// SEBELUM penjualan disimpan, lalu mem-posting POS_CHARGE idempoten
  /// per bill -- di sini murni pemilihan.
  Map<String, dynamic>? _roomChargeStay;

  /// MitraInap LANGKAH 5: kirim nota ini ke dapur (server membuat TiketDapur
  /// QUEUED, idempoten per nota). SENGAJA sticky -- outlet restoran memakai
  /// ini utk hampir semua nota, jadi tidak di-reset setelah bayar.
  bool _buatTiketDapur = false;

  @override
  void initState() {
    super.initState();
    _memberTerpilih = widget.memberAwal;
    _waktuTransaksi = widget.waktuTransaksiAwal ?? DateTime.now();
    _semuaCaraBayarUntukMemberAwal =
        widget.semuaCaraBayarUntukMemberAwal && widget.memberAwal != null;
    _caraBayarTersedia = List<CaraBayar>.of(Sesi.instance.caraBayar);
    if (_caraBayarTersedia.isNotEmpty) {
      _caraBayarTerpilih =
          PengaturanPembayaran.instance.pilihDefault(_caraBayarTersedia);
    }
    _muatPreferensiDanCaraBayar();
    _sinkronkanUangDiterima();
  }

  Future<void> _muatPreferensiDanCaraBayar() async {
    await PengaturanPembayaran.instance.muat();
    if (!mounted) return;
    if (_caraBayarTersedia.isNotEmpty) {
      setStateIfMounted(() {
        _caraBayarTerpilih =
            PengaturanPembayaran.instance.pilihDefault(_caraBayarTersedia);
      });
    }
    await _muatCaraBayarUntukMember(
        _semuaCaraBayarUntukMemberAwal ? null : _memberTerpilih?.id);
  }

  /// Memuat ulang metode pembayaran setiap kali member berubah, sama seperti
  /// `loadMetodePembayaranPOS` di `_pos.jsp`. Tanpa member server mengembalikan
  /// semua cara bayar aktif; dengan member server memfilter berdasarkan
  /// irisan izin Jenis Member dan Tipe Member. Respons juga membawa metode
  /// default serta status kunci agar perilaku Desktop/Android sama.
  ///
  /// Nomor versi mencegah respons lama menimpa pilihan member yang lebih baru
  /// bila kasir mengganti member ketika permintaan sebelumnya masih berjalan.
  /// Saat offline daftar terakhir dipertahankan, mengikuti perilaku POS desktop
  /// agar checkout offline tidak kehilangan metode yang sudah tersedia.
  Future<void> _muatCaraBayarUntukMember(int? memberId) async {
    final versi = ++_versiPermintaanCaraBayar;
    if (mounted) setStateIfMounted(() => _memuatCaraBayar = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('cara_bayar_list', {'id_member': memberId});
      final izinTidakDisetel = hasil['izinTidakDisetel'] == true;
      final caraBayarTerkunci = hasil['caraBayarTerkunci'] == true;
      final caraBayarDefaultId = (hasil['caraBayarDefaultId'] as num?)?.toInt();
      final daftar = ((hasil['caraBayar'] as List?) ?? const [])
          .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || versi != _versiPermintaanCaraBayar) return;

      final idTerpilih = _caraBayarTerpilih?.id;
      CaraBayar? pilihan;
      if (caraBayarDefaultId != null) {
        for (final cara in daftar) {
          if (cara.id == caraBayarDefaultId) {
            pilihan = cara;
            break;
          }
        }
      }
      if (pilihan == null && idTerpilih != null) {
        for (final cara in daftar) {
          if (cara.id == idTerpilih) {
            pilihan = cara;
            break;
          }
        }
      }
      // _pos.jsp otomatis memilih bila hasil filter hanya satu. Untuk daftar
      // lebih dari satu, pertahankan pilihan lama hanya jika masih diizinkan.
      if (pilihan == null && daftar.length == 1) pilihan = daftar.first;

      final metodeMenurutId = <int, CaraBayar>{
        for (final cara in daftar) cara.id: cara,
      };
      final splitMasihDiizinkan = !caraBayarTerkunci &&
          _splitBayar.isNotEmpty &&
          _splitBayar
              .every((slot) => metodeMenurutId.containsKey(slot.caraBayar.id));
      final splitTersegar = splitMasihDiizinkan
          ? _splitBayar
              .map((slot) =>
                  _SlotBayar(metodeMenurutId[slot.caraBayar.id]!, slot.nominal))
              .toList()
          : <_SlotBayar>[];

      setStateIfMounted(() {
        _caraBayarTersedia = daftar;
        _caraBayarTerpilih = pilihan;
        _izinCaraBayarMemberTidakDisetel = memberId != null && izinTidakDisetel;
        _caraBayarDikunciTipe = memberId != null && caraBayarTerkunci;
        // Refresh ketika picker dibuka tidak boleh menghapus split yang masih
        // sah. Bila member/config berubah dan salah satu metode tak lagi
        // diizinkan, barulah seluruh split dibatalkan agar payload tidak
        // membawa metode lama.
        _splitBayar = splitTersegar;
        if (_splitBayar.isNotEmpty) {
          _caraBayarTerpilih = _splitBayar.first.caraBayar;
        }
        _memuatCaraBayar = false;
        _sinkronkanUangDiterima();
      });
    } catch (_) {
      if (!mounted || versi != _versiPermintaanCaraBayar) return;
      // Gagal jaringan: pertahankan snapshot terakhir untuk mode offline.
      setStateIfMounted(() {
        _memuatCaraBayar = false;
        _izinCaraBayarMemberTidakDisetel = false;
      });
    }
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
      diskon: _totalDiskonSemua,
      total: _total,
      memberNama: _memberTerpilih?.nama,
    );
  }

  double get _subtotal => widget.keranjang.fold(0, (s, i) => s + i.subtotal);
  double get _totalDiskon => widget.keranjang.fold(0, (s, i) => s + i.diskon);
  double get _totalCashback =>
      widget.keranjang.fold(0, (s, i) => s + i.cashback);

  double get _dasarDiskonFaktur =>
      (_subtotal - _totalDiskon).clamp(0, double.infinity).toDouble();
  double get _diskonFaktur {
    if (_nilaiDiskonFaktur <= 0) return 0;
    final nilai = _tipeDiskonFaktur == 'PERSEN'
        ? _dasarDiskonFaktur * _nilaiDiskonFaktur.clamp(0, 100) / 100
        : _nilaiDiskonFaktur;
    return nilai.clamp(0, _dasarDiskonFaktur).toDouble();
  }

  double get _totalDiskonSemua => _totalDiskon + _diskonFaktur;

  /// `basisPajak = subtotal - totalDiskon`; `pajak = basisPajak * pajakPersen%`;
  /// `total = basisPajak + pajak` -- persis rumus Desktop (spesifikasi §3.3).
  /// `pajakPersen` bernilai 0 utk toko yg tak mengaktifkan PPN, jadi rumus ini
  /// otomatis identik dgn perilaku lama (tanpa pajak) tanpa perlu flag terpisah.
  double get _basisPajak => _subtotal - _totalDiskonSemua;
  double get _pajak => _basisPajak * Sesi.instance.pajakPersen / 100;
  double get _total => _basisPajak + _pajak;

  double get _uangDiterima =>
      double.tryParse(
          _uangDiterimaController.text.replaceAll(RegExp('[^0-9.]'), '')) ??
      0;
  double get _kembalian => _uangDiterima - _total;
  bool get _metodeTunai {
    final caraBayar = _caraBayarTerpilih;
    if (caraBayar == null) return false;
    final nama = caraBayar.nama.toLowerCase();
    return caraBayar.manual ||
        nama.contains('tunai') ||
        nama.contains('cash') ||
        nama.contains('kas');
  }

  bool get _splitAktif => _splitBayar.length >= 2;

  bool _metodeMemotongDeposit(CaraBayar caraBayar) {
    final nama = caraBayar.nama.toLowerCase();
    return caraBayar.memotongDeposit ||
        nama.contains('deposit') ||
        nama.contains('saldo');
  }

  double _nominalDepositTerpakai() {
    if (_splitAktif) {
      return _splitBayar
          .where((slot) => _metodeMemotongDeposit(slot.caraBayar))
          .fold<double>(0, (sum, slot) => sum + slot.nominal);
    }
    final caraBayar = _caraBayarTerpilih;
    if (caraBayar == null || !_metodeMemotongDeposit(caraBayar)) return 0;
    return _total;
  }

  List<Map<String, dynamic>> _pembayaranStruk() {
    if (_splitAktif) {
      return _splitBayar
          .map((slot) => {
                'nama': slot.caraBayar.nama,
                'nominal': slot.nominal,
              })
          .toList();
    }
    final caraBayar = _caraBayarTerpilih;
    if (caraBayar == null) return const [];
    return [
      {'nama': caraBayar.nama, 'nominal': _total}
    ];
  }

  List<Map<String, dynamic>> _pembayaranPayload() {
    final slots = _splitAktif
        ? _splitBayar
        : (_caraBayarTerpilih == null
            ? const <_SlotBayar>[]
            : [_SlotBayar(_caraBayarTerpilih!, _total)]);
    return slots
        .map((slot) => {
              'caraBayar': slot.caraBayar.id,
              'caraBayarId': slot.caraBayar.id,
              'idCaraBayar': slot.caraBayar.id,
              'nama': slot.caraBayar.nama,
              'namaCaraBayar': slot.caraBayar.nama,
              'metode': slot.caraBayar.nama,
              'metodePembayaran': slot.caraBayar.nama,
              'nominal': slot.nominal,
              'jumlah': slot.nominal,
              'amount': slot.nominal,
            })
        .toList();
  }

  double? _angkaDariMap(Map<String, dynamic>? map, Iterable<String> keys) {
    if (map == null) return null;
    for (final key in keys) {
      final nilai = map[key];
      if (nilai is num) return nilai.toDouble();
      if (nilai is String) {
        final parsed =
            double.tryParse(nilai.replaceAll(RegExp('[^0-9.-]'), ''));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  double? _saldoDepositDariResponse(Map<String, dynamic>? hasil) {
    const keys = [
      'saldo',
      'saldoSisa',
      'sisaSaldo',
      'saldoAkhir',
      'saldoMember',
      'sisaDeposit',
      'depositSisa',
      'depositAkhir',
    ];
    final langsung = _angkaDariMap(hasil, keys);
    if (langsung != null) return langsung;
    final data = hasil?['data'];
    if (data is Map<String, dynamic>) return _angkaDariMap(data, keys);
    if (data is Map) {
      return _angkaDariMap(Map<String, dynamic>.from(data), keys);
    }
    return null;
  }

  double? _saldoDepositSetelahBayar(Map<String, dynamic>? hasilBayar) {
    final saldoResponse = _saldoDepositDariResponse(hasilBayar);
    if (saldoResponse != null) return saldoResponse;
    final nominalDeposit = _nominalDepositTerpakai();
    final saldoAwal = _saldoMember;
    if (nominalDeposit <= 0 || saldoAwal == null) return null;
    final saldoAkhir = saldoAwal - nominalDeposit;
    return saldoAkhir < 0 ? 0 : saldoAkhir;
  }

  // Saat split aktif, "Uang Diterima" mengacu ke TOTAL transaksi tapi kasir
  // membaginya ke beberapa metode -- validasi "uang kurang dari total" tidak
  // relevan lagi (kasir bisa saja terima Rp0 tunai kalau semua slot non-tunai),
  // jadi gerbang ini dilewati saat split aktif; nominal per slot sudah
  // divalidasi seimbang dgn total di `_SheetPilihMetodeSplit` sendiri.
  bool get _uangTunaiKurang =>
      !_splitAktif && _metodeTunai && _uangDiterima + 0.0001 < _total;
  bool get _bisaBayar =>
      !_memproses &&
      !_memuatCaraBayar &&
      _caraBayarTerpilih != null &&
      widget.keranjang.isNotEmpty &&
      !_uangTunaiKurang;

  void _aturUangDiterima(double nilai) {
    setStateIfMounted(() {
      _uangDiterimaManual = true;
      _uangDiterimaController.text =
          nilai <= 0 ? '0' : nilai.toStringAsFixed(0);
    });
  }

  Future<void> _bukaDialogUangDiterima() async {
    final nilai = await showDialog<double>(
      context: context,
      builder: (_) => _DialogUangDiterima(
        nilaiAwal: _uangDiterima,
        total: _total,
      ),
    );
    if (nilai != null) _aturUangDiterima(nilai);
  }

  /// "Uang Diterima" default = total (spec §3.4) SELAMA kasir belum mengetik
  /// nilai sendiri -- begitu kasir mengubahnya manual, berhenti auto-ikut
  /// total (mis. saat menerima uang pas beda dari total, spt uang tunai fisik
  /// yang dibulatkan).
  void _sinkronkanUangDiterima() {
    if (_uangDiterimaManual) return;
    final teks = _total > 0 ? _total.toStringAsFixed(0) : '0';
    if (_uangDiterimaController.text != teks) {
      _uangDiterimaController.text = teks;
    }
  }

  void _ubahJumlah(ItemKeranjang item, int delta) {
    setStateIfMounted(() {
      item.jumlah += delta;
      if (item.jumlah <= 0) {
        widget.keranjang.remove(item);
      }
      _sinkronkanUangDiterima();
    });
    _siarkanKeranjang();
    _jadwalkanEvaluasiDiskon();
  }

  void _aturJumlahItem(ItemKeranjang item, int jumlah) {
    final jumlahBaru = jumlah < 1 ? 1 : jumlah;
    if (!widget.keranjang.contains(item) || item.jumlah == jumlahBaru) return;
    setStateIfMounted(() {
      item.jumlah = jumlahBaru;
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
      // SENGAJA tidak menyertakan `i.ekstra` di sini -- baris ekstra memang
      // belum dibuat diskon-eligible sendiri di fase ini (bukan oversight),
      // diskon tetap dievaluasi hanya thd produk dasar per baris.
      //
      // Baris dgn `promoManual == true` (gap-closure "Aktivasi Manual")
      // menyertakan `hanya_aturan_id` PER-ITEM (bukan diomit) supaya server
      // hanya mengevaluasi ulang rule yang sengaja dipilih kasir utk baris
      // itu -- max-potongan cap-nya tetap segar tiap recalc, sama seperti
      // baris auto-apply, sekaligus mencegah baris ini "lolos" kembali ke
      // mode auto-apply. Baris lain (promoManual == false) tetap dikirim
      // TANPA `hanya_aturan_id`, jadi satu batch call ini otomatis mendukung
      // keranjang campuran (sebagian manual, sebagian auto).
      final hasil = await ApiClient.instance.aksi('diskon_evaluasi', {
        // Wajib dikirim juga untuk akun admin/multi-toko. Tanpa ini server hanya
        // dapat menebak toko dari akun pedagang; pada kasir multi-toko evaluasi
        // gagal lalu keranjang tampak seolah tidak memperoleh diskon grup.
        'toko_id': Sesi.instance.tokoId,
        'id_member': _memberTerpilih?.id,
        'items': widget.keranjang
            .map((i) => {
                  'id': i.produk.id,
                  'harga': i.produk.hargaJual,
                  'jumlah': i.jumlah,
                  if (i.promoManual && i.promoManualAturanId != null)
                    'hanya_aturan_id': i.promoManualAturanId,
                })
            .toList(),
      });
      final items = (hasil['items'] as List?) ?? [];
      if (!mounted) return;
      setStateIfMounted(() {
        // Dipetakan per-INDEKS (BUKAN per produk.id) -- respons server `items`
        // SEJAJAR urutan `items` yg dikirim di request (index i <-> keranjang[i]
        // krn dibangun dari `widget.keranjang.map(...)` di atas, urutan sama).
        // Wajib per-indeks krn 2 baris keranjang boleh punya produk.id SAMA
        // (kombinasi Produk Ekstra beda) sekaligus status manual/auto berbeda --
        // kalau dikunci id (`.where(id==produkId).first`), hasil satu baris bisa
        // salah menimpa baris lain yg id-nya kebetulan sama.
        for (var idx = 0;
            idx < items.length && idx < widget.keranjang.length;
            idx++) {
          final m = items[idx] as Map<String, dynamic>;
          final item = widget.keranjang[idx];
          if (item.diskonBebas) {
            final nilaiBaris = item.subtotal;
            final diskon = item.diskonBebasTipe == 'PERSEN'
                ? nilaiBaris * item.diskonBebasNilai.clamp(0, 100) / 100
                : item.diskonBebasNilai.clamp(0, nilaiBaris);
            item
              ..diskon = diskon.toDouble()
              ..cashback = 0
              ..aturanDiskonId = null;
            continue;
          }
          widget.keranjang[idx]
            ..diskon = (m['diskon'] as num?)?.toDouble() ?? 0
            ..cashback = (m['cashback'] as num?)?.toDouble() ?? 0
            ..aturanDiskonId = m['aturanDiskon'] as int?;
        }
        _sinkronkanUangDiterima();
      });
    } catch (e) {
      // Evaluasi diskon gagal (mis. offline) -- keranjang tetap bisa dibayar
      // tanpa diskon otomatis, bukan alasan memblokir transaksi.
      //
      // TAPI kegagalan ini TIDAK boleh senyap: server tetap menghitung ulang
      // promo saat menyimpan dan tidak memakai nilai kasir, jadi keranjang yang
      // tampak tanpa diskon bisa tercatat dengan diskon. Struk kertas lalu
      // menyebut angka lebih besar daripada yang tercatat, dan pelanggan
      // terlanjur membayar kelebihan (kasus nota AB22008202600004, 20-08-2026).
      // Kasir diberi tahu supaya sadar angka di layar belum tentu final.
      unawaited(CoreDb.instance.catatErrorLog(
        sumber: 'diskon-evaluasi',
        tingkat: 'WARN',
        pesan: 'Evaluasi diskon otomatis gagal; keranjang memakai harga penuh.',
        detail: '$e',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 4),
          backgroundColor: Colors.orange,
          content: Text('Diskon otomatis belum dapat diperiksa. Total di layar'
              ' memakai harga penuh dan masih bisa disesuaikan server.'),
        ));
      }
    }
    _siarkanKeranjang();
  }

  Future<void> _pilihMember() async {
    final terpilih = await showDialog<Anggota>(
      context: context,
      builder: (_) => const _DialogPilihMember(),
    );
    if (terpilih != null) {
      setStateIfMounted(() {
        _memberTerpilih = terpilih;
        _saldoMember = null;
        _semuaCaraBayarUntukMemberAwal = false;
      });
      unawaited(_muatCaraBayarUntukMember(terpilih.id));
      _siarkanKeranjang();
      _jadwalkanEvaluasiDiskon();
      try {
        final hasil = await ApiClient.instance
            .aksi('saldo_member', {'id_member': terpilih.id});
        if (mounted) {
          setStateIfMounted(
              () => _saldoMember = (hasil['data'] as num?)?.toDouble());
        }
      } catch (_) {
        // Saldo tak terambil (mis. offline) -- bukan alasan membatalkan pemilihan member.
      }
    }
  }

  void _hapusMember() {
    setStateIfMounted(() {
      _memberTerpilih = null;
      _saldoMember = null;
      _semuaCaraBayarUntukMemberAwal = false;
    });
    unawaited(_muatCaraBayarUntukMember(null));
    _siarkanKeranjang();
    _jadwalkanEvaluasiDiskon();
  }

  /// Buka picker "Promo Manual" (gap-closure "Aktivasi Manual", Fase 2
  /// Stretch) -- padanan `_pilihMember` di atas, tapi sumber daftarnya aksi
  /// `diskon_manual_list` (HANYA rule `aktivasiManual=true` yg eligible utk
  /// minimal satu item keranjang saat ini, lihat kontrak server di JavaDoc
  /// modul ini). Batal (tutup sheet tanpa pilih) -- tidak mengubah apa pun.
  Future<void> _bukaPickerPromoManual([ItemKeranjang? itemPilihan]) async {
    if (widget.keranjang.isEmpty) return;
    final target = itemPilihan ??
        await showModalBottomSheet<ItemKeranjang>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _SheetPilihItemPromoManual(
              daftar: List<ItemKeranjang>.of(widget.keranjang)),
        );
    if (target == null || !mounted) return;
    List<Map<String, dynamic>> daftar;
    try {
      final hasil = await ApiClient.instance.aksi('diskon_manual_list', {
        'toko_id': Sesi.instance.tokoId,
        'id_member': _memberTerpilih?.id,
        'items': [
          {
            'id': target.produk.id,
            'harga': target.produk.hargaJual,
            'jumlah': target.jumlah,
          }
        ],
      });
      daftar = ((hasil['promo'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      // Diskon bebas tetap tersedia saat daftar master promo tidak dapat
      // dimuat, termasuk ketika kasir sedang offline.
      daftar = <Map<String, dynamic>>[];
    }
    if (!mounted) return;
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _SheetPilihPromoManual(daftar: daftar, namaItem: target.produk.nama),
    );
    if (dipilih == null) return;
    if (dipilih['diskonBebas'] == true) {
      await _terapkanDiskonBebas(target);
    } else {
      await _terapkanPromoManual(target, dipilih);
    }
  }

  Future<void> _terapkanDiskonBebas(ItemKeranjang target) async {
    var tipe = target.diskonBebas ? target.diskonBebasTipe : 'NOMINAL';
    final controller = TextEditingController(
        text: target.diskonBebas && target.diskonBebasNilai > 0
            ? target.diskonBebasNilai.toStringAsFixed(0)
            : '');
    String? pesan;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Diskon Bebas - ${target.produk.nama}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tipe,
                  decoration: const InputDecoration(
                      labelText: 'Jenis diskon', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'NOMINAL', child: Text('Nominal (Rp)')),
                    DropdownMenuItem(
                        value: 'PERSEN', child: Text('Persentase (%)')),
                  ],
                  onChanged: (v) => setDialogState(() {
                    tipe = v ?? 'NOMINAL';
                    pesan = null;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tipe == 'PERSEN'
                        ? 'Persentase diskon'
                        : 'Nominal diskon',
                    suffixText: tipe == 'PERSEN' ? '%' : 'Rp',
                    helperText:
                        'Maksimal nilai item ${_formatRupiah.format(target.subtotal)}.',
                    errorText: pesan,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final nilai = double.tryParse(
                    controller.text.replaceAll(',', '.').trim());
                final tidakValid = nilai == null ||
                    nilai < 0 ||
                    (tipe == 'PERSEN' && nilai > 100) ||
                    (tipe == 'NOMINAL' && nilai > target.subtotal);
                if (tidakValid) {
                  setDialogState(() => pesan = tipe == 'PERSEN'
                      ? 'Persentase harus antara 0 sampai 100.'
                      : 'Nominal tidak boleh melebihi nilai item.');
                  return;
                }
                Navigator.pop(dialogContext, {'tipe': tipe, 'nilai': nilai});
              },
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (hasil == null || !mounted) return;
    final nilai = (hasil['nilai'] as num).toDouble();
    final jenis = '${hasil['tipe']}';
    setStateIfMounted(() {
      target
        ..diskonBebas = true
        ..diskonBebasTipe = jenis
        ..diskonBebasNilai = nilai
        ..diskon = jenis == 'PERSEN'
            ? target.subtotal * nilai / 100
            : nilai.clamp(0, target.subtotal).toDouble()
        ..cashback = 0
        ..aturanDiskonId = null
        ..promoManual = false
        ..promoManualAturanId = null;
      _sinkronkanUangDiterima();
    });
    _siarkanKeranjang();
  }

  /// Terapkan satu aturan hanya pada satu baris barang. Server tetap menjadi
  /// sumber kebenaran untuk eligibilitas dan nominal diskon/cashback.
  Future<void> _terapkanPromoManual(
      ItemKeranjang target, Map<String, dynamic> promo) async {
    final aturanId = promo['id'] as int;
    try {
      final hasil = await ApiClient.instance.aksi('diskon_evaluasi', {
        'toko_id': Sesi.instance.tokoId,
        'id_member': _memberTerpilih?.id,
        'items': [
          {
            'id': target.produk.id,
            'harga': target.produk.hargaJual,
            'jumlah': target.jumlah,
            'hanya_aturan_id': aturanId,
          }
        ],
      });
      final items = (hasil['items'] as List?) ?? [];
      if (!mounted) return;
      final m = items.isEmpty ? null : items.first as Map<String, dynamic>;
      final aturanDiskon = m?['aturanDiskon'] as int?;
      final cocok = aturanDiskon != null;
      setStateIfMounted(() {
        target
          ..diskon = (m?['diskon'] as num?)?.toDouble() ?? 0
          ..cashback = (m?['cashback'] as num?)?.toDouble() ?? 0
          ..aturanDiskonId = aturanDiskon
          ..promoManual = cocok
          ..promoManualAturanId = cocok ? aturanId : null
          ..diskonBebas = false
          ..diskonBebasNilai = 0;
        if (cocok) _metadataPromoManual[aturanId] = promo;
        _sinkronkanUangDiterima();
      });
      _siarkanKeranjang();
      if (!mounted) return;
      if (!cocok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Promo "${promo['namaAturan'] ?? ''}" tidak berlaku untuk ${target.produk.nama}.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menerapkan promo: $e')));
    }
  }

  void _hapusPromoManualItem(ItemKeranjang item) {
    setStateIfMounted(() {
      item
        ..promoManual = false
        ..promoManualAturanId = null
        ..diskonBebas = false
        ..diskonBebasNilai = 0;
    });
    _jadwalkanEvaluasiDiskon();
  }

  /// Lepas semua promo manual; setiap baris kembali ke evaluasi otomatis.
  void _hapusPromoManual() {
    setStateIfMounted(() {
      for (final i in widget.keranjang) {
        if (i.promoManual || i.diskonBebas) {
          i.promoManual = false;
          i.promoManualAturanId = null;
          i.diskonBebas = false;
          i.diskonBebasNilai = 0;
        }
      }
      _metadataPromoManual.clear();
    });
    _jadwalkanEvaluasiDiskon();
  }

  bool get _saldoAkanDipotong => _nominalDepositTerpakai() > 0.0001;

  bool get _pinWajibUntukMetodeTerpilih {
    if (_memberTerpilih == null) return false;
    if (_splitAktif) {
      return pembayaranMemerlukanPin(_splitBayar
          .where((slot) => slot.nominal > 0)
          .map((slot) => slot.caraBayar));
    }
    final cara = _caraBayarTerpilih;
    return cara != null && pembayaranMemerlukanPin([cara]);
  }

  bool get _memberMemilikiLimitTransaksi {
    final member = _memberTerpilih;
    return member != null &&
        (member.maksimalTransaksiHarian > 0 ||
            member.maksimalTransaksiMingguan > 0 ||
            member.maksimalTransaksiBulanan > 0);
  }

  bool get _biometrikWajibUntukSaldo {
    final member = _memberTerpilih;
    return member != null &&
        _saldoAkanDipotong &&
        (member.wajibBiometricWajah || member.wajibBiometricFingerprint);
  }

  bool get _verifikasiMemberWajibServer {
    final member = _memberTerpilih;
    return member != null &&
        (_pinWajibUntukMetodeTerpilih ||
            (_saldoAkanDipotong &&
                (member.wajibBiometricWajah ||
                    member.wajibBiometricFingerprint)));
  }

  Future<int?> _verifikasiBiometrik(PosBiometricCaptureBridge bridge,
      String modality, String kodeUnik) async {
    try {
      final sample = await bridge.capture(modality);
      final hasil =
          await ApiClient.instance.aksi('verifikasi_biometrik_member', {
        'memberId': _memberTerpilih!.id,
        'modality': sample.modality,
        'probe_base64': sample.templateBase64,
        'template_format': sample.templateFormat,
        'provider': sample.provider,
        'liveness_score': sample.livenessScore,
        'captured_at_epoch': DateTime.now().millisecondsSinceEpoch,
        'reference_type': 'POS_PURCHASE',
        'reference_id': kodeUnik,
        'clientMutationId':
            'pos-bio-$kodeUnik-${sample.modality.toLowerCase()}',
      });
      final ok = hasil['ok'] == true;
      final eventId = (hasil['biometricEventId'] as num?)?.toInt();
      if (!ok || eventId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('${hasil['message'] ?? 'Biometrik tidak cocok.'}')));
        }
        return null;
      }
      return eventId;
    } catch (e) {
      if (mounted) snackbarGalat(context, e);
      return null;
    }
  }

  Future<int?> _verifikasiPin(String kodeUnik) async {
    if (!mounted) return null;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogMasukkanPin(),
    );
    if (pin == null || pin.isEmpty) return null;
    try {
      final hasil = await ApiClient.instance.aksi('verifikasi_pin', {
        'memberId': _memberTerpilih!.id,
        'pin': pin,
        'captured_at_epoch': DateTime.now().millisecondsSinceEpoch,
        'reference_type': 'POS_PURCHASE',
        'reference_id': kodeUnik,
        'clientMutationId': 'pos-pin-$kodeUnik',
      });
      final ok = hasil['ok'] == true;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PIN salah.')));
      }
      if (!ok) return null;
      return (hasil['pinVerificationEventId'] as num?)?.toInt();
    } catch (e) {
      if (mounted) snackbarGalat(context, e);
      return null;
    }
  }

  /// Mengembalikan event biometrik yang harus ikut payload checkout. Null
  /// berarti verifikasi dibatalkan/gagal dan pembayaran tidak boleh lanjut.
  Future<Map<String, int>?> _verifikasiMemberJikaPerlu(String kodeUnik) async {
    final member = _memberTerpilih;
    if (member == null) return <String, int>{};
    final bridge = PosBiometricCaptureBridge();
    final capability = await bridge.capabilities();
    if (!mounted) return null;

    if (_biometrikWajibUntukSaldo) {
      final kurang = <String>[];
      if (member.wajibBiometricWajah && capability['face'] != true) {
        kurang.add('kamera dengan face-liveness');
      }
      if (member.wajibBiometricFingerprint &&
          capability['fingerprint'] != true) {
        kurang.add('scanner fingerprint member');
      }
      if (kurang.isNotEmpty) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Perangkat biometrik belum siap'),
              content: Text(
                  'Jenis member ini mewajibkan ${kurang.join(' dan ')} sebelum saldo dipotong. '
                  'Pembayaran dihentikan; pilih metode lain atau sambungkan perangkat yang sesuai.'),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Mengerti')),
              ],
            ),
          );
        }
        return null;
      }
      final bukti = <String, int>{};
      if (member.wajibBiometricWajah) {
        final id = await _verifikasiBiometrik(bridge, 'FACE', kodeUnik);
        if (id == null) return null;
        bukti['biometric_face_event_id'] = id;
      }
      if (member.wajibBiometricFingerprint) {
        final id = await _verifikasiBiometrik(bridge, 'FINGERPRINT', kodeUnik);
        if (id == null) return null;
        bukti['biometric_fingerprint_event_id'] = id;
      }
      if (_pinWajibUntukMetodeTerpilih) {
        final id = await _verifikasiPin(kodeUnik);
        if (id == null) return null;
        bukti['pin_verification_event_id'] = id;
      }
      return bukti;
    }

    if (!_pinWajibUntukMetodeTerpilih) return <String, int>{};
    final pilihan = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Verifikasi member'),
        children: [
          if (capability['fingerprint'] == true)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'FINGERPRINT'),
              child: const ListTile(
                leading: Icon(Icons.fingerprint),
                title: Text('Sidik jari'),
                subtitle: Text('Verifikasi melalui scanner institusi'),
              ),
            ),
          if (capability['face'] == true)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'FACE'),
              child: const ListTile(
                leading: Icon(Icons.face),
                title: Text('Pengenalan wajah'),
                subtitle: Text('Memerlukan pemeriksaan liveness'),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'PIN'),
            child: const ListTile(
              leading: Icon(Icons.pin),
              title: Text('PIN member'),
              subtitle: Text(
                  'Metode cadangan saat perangkat biometrik tidak tersedia'),
            ),
          ),
        ],
      ),
    );
    if (pilihan == null) return null;
    if (pilihan != 'PIN') {
      final id = await _verifikasiBiometrik(bridge, pilihan, kodeUnik);
      return id == null ? null : <String, int>{};
    }
    final pinEventId = await _verifikasiPin(kodeUnik);
    return pinEventId == null
        ? null
        : <String, int>{'pin_verification_event_id': pinEventId};
  }

  Future<String> _buatKodeUnik() async {
    final kodeDraft = widget.draftKodeSumber?.trim();
    if (widget.draftIdSumber != null &&
        kodeDraft != null &&
        kodeDraft.isNotEmpty) {
      return kodeDraft;
    }
    return PengaturanNomorStruk.instance.buatNomor();
  }

  String _formatWaktuServer(DateTime d) {
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${pad(d.day)}-${pad(d.month)}-${d.year} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  /// Kontrol "Tagihkan ke Kamar" -- hanya dirakit pada varian MitraInap
  /// (lihat pemakaian di build). Memilih tamu butuh koneksi (lookup server);
  /// transaksi offline tetap sah asal tamu sudah dipilih saat online, karena
  /// payload dibawa outbox apa adanya.
  Widget _pemilihRoomCharge() {
    final stay = _roomChargeStay;
    return InkWell(
      onTap: _memproses ? null : _pilihRoomCharge,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Tagihkan ke Kamar (folio tamu)',
            border: _radiusInput,
            isDense: true),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                  stay == null
                      ? 'Tidak (bayar langsung)'
                      : '${stay['tamu_nama'] ?? '-'} — Kamar ${stay['kamar_nomor'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (stay != null)
              InkWell(
                onTap: () => setStateIfMounted(() => _roomChargeStay = null),
                child: const Icon(Icons.clear, size: 18),
              )
            else
              const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pilihRoomCharge() async {
    List<Map<String, dynamic>> daftarStay;
    try {
      final res = await ApiClient.instance.aksi('hotel_room_charge_lookup', {});
      if (res['status'] != '00' && res['status'] != 'success') {
        throw Exception(res['description'] ?? 'Gagal memuat tamu in-house.');
      }
      daftarStay = ((res['stay'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Butuh koneksi server untuk memuat tamu in-house: $e')));
      return;
    }
    if (!mounted) return;
    if (daftarStay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Tidak ada tamu in-house. Check-in dilakukan dari menu Check-in / Check-out.')));
      return;
    }
    final pilihan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) {
        var filter = '';
        return StatefulBuilder(builder: (c2, setD) {
          final tersaring = daftarStay.where((s) {
            if (filter.isEmpty) return true;
            final teks =
                '${s['tamu_nama'] ?? ''} ${s['kamar_nomor'] ?? ''} ${s['properti_nama'] ?? ''}'
                    .toLowerCase();
            return teks.contains(filter);
          }).toList();
          return AlertDialog(
            title: const Text('Tagihkan ke Kamar'),
            content: SizedBox(
              width: 420,
              height: 380,
              child: Column(children: [
                AppSearchField(
                  hintText: 'Cari nama tamu / nomor kamar',
                  autofocus: true,
                  debounce: Duration.zero,
                  onChanged: (v) => setD(() => filter = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: tersaring.isEmpty
                      ? const Center(child: Text('Tidak ada yang cocok.'))
                      : ListView.builder(
                          itemCount: tersaring.length,
                          itemBuilder: (context, i) {
                            final s = tersaring[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.hotel_outlined),
                              title: Text(
                                  '${s['tamu_nama'] ?? '-'} — Kamar ${s['kamar_nomor'] ?? '-'}'),
                              subtitle: Text('${s['properti_nama'] ?? ''}'),
                              onTap: () => Navigator.of(c2).pop(s),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(c2).pop(),
                  child: const Text('Batal')),
            ],
          );
        });
      },
    );
    if (pilihan == null) return;
    setStateIfMounted(() => _roomChargeStay = pilihan);
  }

  Map<String, dynamic> _buatPayload(
    String kodeUnik,
    DateTime waktu, {
    bool sertakanStatusPelayanan = false,
  }) {
    final pembayaranSplit =
        _splitAktif ? _pembayaranPayload() : const <Map<String, dynamic>>[];
    final pembayaranUtama =
        pembayaranSplit.isNotEmpty ? pembayaranSplit.first['nominal'] : null;
    return {
      'kodeUnik': kodeUnik,
      'clientTrxId': kodeUnik,
      'idToko': Sesi.instance.tokoId,
      'tokoId': Sesi.instance.tokoId,
      'kasir': Sesi.instance.userId,
      'waktu': _formatWaktuServer(waktu),
      'caraBayar': _caraBayarTerpilih!.id,
      'caraBayarNama': _caraBayarTerpilih!.nama,
      if (_splitAktif) ...{
        'caraBayarNominal': pembayaranUtama,
        'nominalCaraBayar': pembayaranUtama,
        'caraBayarUtamaNominal': pembayaranUtama,
        'caraBayarTambahan': _splitBayar
            .skip(1)
            .map((s) => {
                  'caraBayar': s.caraBayar.id,
                  'caraBayarId': s.caraBayar.id,
                  'nama': s.caraBayar.nama,
                  'namaCaraBayar': s.caraBayar.nama,
                  'metode': s.caraBayar.nama,
                  'metodePembayaran': s.caraBayar.nama,
                  'nominal': s.nominal,
                  'jumlah': s.nominal,
                })
            .toList(),
        'pembayaran': pembayaranSplit,
        'rincianPembayaran': pembayaranSplit,
        'metodePembayaranList': pembayaranSplit,
        'splitPembayaran': pembayaranSplit,
        'multiPembayaran': pembayaranSplit,
      },
      'total': _total,
      'pajak': _pajak,
      'diskon_faktur_tipe': _tipeDiskonFaktur,
      'diskon_faktur_nilai': _nilaiDiskonFaktur,
      'id_member': _memberTerpilih?.id,
      'nama_member': _memberTerpilih?.nama,
      'nama_mesin': IdentitasMesin.instance.namaMesin,
      'id_perangkat': IdentitasMesin.instance.idMesin,
      if (_roomChargeStay != null) ...{
        'hotel_menginap_id': _roomChargeStay!['id'],
        'hotel_properti_id': _roomChargeStay!['properti_id'],
      },
      if (_buatTiketDapur) 'hotel_tiket_dapur': true,
      if (widget.draftIdSumber != null) ...{
        // `id` adalah nama kanonis yang dibaca endpoint draft_bayar. Alias
        // di bawah tetap dikirim untuk kompatibilitas server/klien lama.
        // Tanpa field kanonis ini, menahan ulang keranjang hasil resume
        // dianggap sebagai draft baru dan menimbulkan transaksi ganda.
        'id': widget.draftIdSumber,
        'draftPembelianAnggotaKoperasi': widget.draftIdSumber,
        'draftPembelianAnggotaKoperasiId': widget.draftIdSumber,
        'idDraftPembelianAnggotaKoperasi': widget.draftIdSumber,
        'draft_pembelian_anggota_koperasi': widget.draftIdSumber,
        'draft_pembelian_anggota_koperasi_id': widget.draftIdSumber,
        'id_draft_pembelian_anggota_koperasi': widget.draftIdSumber,
        'draftPembelianId': widget.draftIdSumber,
        'draft_pembelian_id': widget.draftIdSumber,
        'draftId': widget.draftIdSumber,
        'draft_id': widget.draftIdSumber,
        'idDraft': widget.draftIdSumber,
      },
      if (widget.draftKodeSumber != null &&
          widget.draftKodeSumber!.trim().isNotEmpty) ...{
        'kodeDraft': widget.draftKodeSumber!.trim(),
        'draftKode': widget.draftKodeSumber!.trim(),
        'kodeDraftPembelianAnggotaKoperasi': widget.draftKodeSumber!.trim(),
        'kode_draft_pembelian_anggota_koperasi': widget.draftKodeSumber!.trim(),
      },
      if (sertakanStatusPelayanan) ...{
        'terlayani': _langsungTerlayani,
        'langsungTerlayani': _langsungTerlayani,
        'statusTerlayani': _langsungTerlayani,
        'langsungDilayani': _langsungTerlayani,
        'sudahTerlayani': _langsungTerlayani,
        'dilayani': _langsungTerlayani,
        'statusPelayanan': _langsungTerlayani ? 'TERLAYANI' : 'MENUNGGU',
      },
      'transaksi': widget.keranjang
          .map((i) => {
                'id': i.produk.id,
                'kode': i.produk.kode,
                'nama': i.produk.nama,
                'harga': i.produk.hargaJual,
                'jumlah': i.jumlah,
                'diskon': i.diskon,
                'aturanDiskon': i.aturanDiskonId,
                'diskon_bebas': i.diskonBebas,
                if (i.diskonBebas) ...{
                  'diskon_bebas_tipe': i.diskonBebasTipe,
                  'diskon_bebas_nilai': i.diskonBebasNilai,
                },
                'cashback': i.cashback,
                // Purely ADDITIVE (gap-closure "Produk Ekstra") -- selalu
                // disertakan sbg array, kosong utk mayoritas baris tanpa
                // add-on (lihat JavaDoc [ItemEkstra] di models.dart).
                'ekstra': i.ekstra
                    .map((e) => {
                          'id': e.id,
                          'kode': e.kode,
                          'nama': e.nama,
                          'harga': e.harga,
                          'jumlah': e.jumlah,
                        })
                    .toList(),
              })
          .toList(),
    };
  }

  /// "Tahan" -- simpan keranjang sbg draft belum lunas (aksi `draft_bayar`,
  /// bentuk payload SAMA dgn `bayar`) lalu kosongkan keranjang. BEDA dari
  /// Bayar: TIDAK offline-first (draft yg gagal tersimpan krn offline lebih
  /// baik gagal jelas drpd diam-diam antre lokal tanpa ada layar Pesanan
  /// utk memuatnya kembali).
  Future<String?> _pilihAlasanTahan() async {
    final daftar = Sesi.instance.alasanTahan.isEmpty
        ? _alasanTahanBawaan
        : Sesi.instance.alasanTahan;
    var pilihan = daftar.first;
    final lainController = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Mengapa transaksi ditahan?'),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pilih satu alasan. Alasan akan disimpan dan ditampilkan pada daftar Pesanan.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final alasan in daftar)
                          RadioListTile<String>(
                            dense: true,
                            value: alasan,
                            groupValue: pilihan,
                            title: Text(alasan),
                            onChanged: (nilai) => setDialogState(
                                () => pilihan = nilai ?? pilihan),
                          ),
                        RadioListTile<String>(
                          dense: true,
                          value: '__LAINNYA__',
                          groupValue: pilihan,
                          title: const Text('Lainnya'),
                          onChanged: (_) =>
                              setDialogState(() => pilihan = '__LAINNYA__'),
                        ),
                        if (pilihan == '__LAINNYA__')
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextField(
                              controller: lainController,
                              autofocus: true,
                              maxLength: 200,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Tuliskan alasan lainnya',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  final hasil = pilihan == '__LAINNYA__'
                      ? lainController.text.trim()
                      : pilihan;
                  if (hasil.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Alasan lainnya wajib diisi.')));
                    return;
                  }
                  Navigator.pop(dialogContext, hasil);
                },
                child: const Text('Tahan Transaksi'),
              ),
            ],
          ),
        ),
      );
    } finally {
      lainController.dispose();
    }
  }

  Future<void> _tahan() async {
    if (widget.keranjang.isEmpty) return;
    if (_caraBayarTerpilih == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pilih metode pembayaran terlebih dahulu.')));
      return;
    }
    final alasanTahan = await _pilihAlasanTahan();
    if (alasanTahan == null || alasanTahan.isEmpty) return;
    setStateIfMounted(() => _memproses = true);
    try {
      final kodeUnik = await _buatKodeUnik();
      // Menahan ulang adalah aktivitas baru. Jangan simpan kembali timestamp
      // draft lama maupun waktu saat draft pertama kali dimuat.
      final waktu = waktuTransaksiDraftDilanjutkan();
      _waktuTransaksi = waktu;
      final payload = _buatPayload(kodeUnik, waktu);
      payload['keterangan'] = alasanTahan;
      await ApiClient.instance.aksi('draft_bayar', payload);
      widget.keranjang.clear();
      LayarPelangganBroadcaster.instance
          .jadwalkanKirim(items: const [], subtotal: 0, diskon: 0, total: 0);
      if (!mounted) return;
      setStateIfMounted(() {
        _memberTerpilih = null;
        _saldoMember = null;
        _langsungTerlayani = true;
        _uangDiterimaManual = false;
        _uangDiterimaController.text = '0';
        _splitBayar = [];
        _nilaiDiskonFaktur = 0;
        _tipeDiskonFaktur = 'NOMINAL';
      });
      unawaited(_muatCaraBayarUntukMember(null));
      final keteranganSukses = widget.draftIdSumber == null
          ? 'Transaksi ditahan (kode: $kodeUnik).'
          : 'Transaksi tertahan diperbarui (kode: $kodeUnik).';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(keteranganSukses)));
      widget.onSelesai?.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  /// Nama metode yang MEMICU keharusan memilih pelanggan. Pada split bayar
  /// pemicunya belum tentu slot 1, dan menyebut metode yang salah di dialog
  /// membuat kasir mencari-cari kesalahan di tempat yang keliru.
  String _namaMetodeWajibMember() {
    if (_caraBayarTerpilih?.wajibPilihMember == true) {
      return _caraBayarTerpilih!.nama;
    }
    for (final s in _splitBayar) {
      if (s.caraBayar.wajibPilihMember && s.nominal > 0) {
        return s.caraBayar.nama;
      }
    }
    return _caraBayarTerpilih?.nama ?? '';
  }

  /// True bila metode bayar terpilih (slot 1 atau slot split mana pun) menuntut
  /// member sebagai pemilik hutang atau sekadar PJ/PIC, tetapi belum dipilih.
  bool get _perluMemberAtauPic {
    if (_memberTerpilih != null) return false;
    // Memakai wajibPilihMember, BUKAN hanya masukSebagaiHutang: selain seluruh
    // Kasbon, metode potong saldo juga tidak bermakna tanpa pemilik/PIC.
    if (_caraBayarTerpilih?.wajibPilihMember == true) return true;
    for (final s in _splitBayar) {
      if (s.caraBayar.wajibPilihMember && s.nominal > 0) return true;
    }
    return false;
  }

  Future<void> _bayar() async {
    // Pertahanan terhadap pintasan F2/race: member baru memicu pemuatan ulang
    // aturan pembayaran. Jangan pernah mengirim transaksi memakai snapshot
    // metode member sebelumnya sebelum aturan server selesai diterapkan.
    if (!_bisaBayar) return;
    if (widget.keranjang.isEmpty) return;
    if (_caraBayarTerpilih == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pilih metode pembayaran terlebih dahulu.')));
      return;
    }
    if (_uangTunaiKurang) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Uang diterima kurang ${_formatRupiah.format((_total - _uangDiterima).abs())}.')));
      return;
    }
    // PIUTANG WAJIB BERPEMILIK: metode ber-flag masukSebagaiHutang membentuk
    // tagihan toko ke pelanggan. Tanpa nama pelanggan, tim keuangan tidak dapat
    // menagih -- server pun menolaknya. Kasir langsung diarahkan memilih
    // pelanggan di sini, bukan dibiarkan gagal setelah menekan Bayar.
    if (_perluMemberAtauPic) {
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Pilih Member / PIC'),
          content: Text(
              'Metode "${_namaMetodeWajibMember()}" wajib mempunyai penanggung jawab. '
              'Pilih member/PIC terlebih dahulu agar transaksi dapat ditelusuri tim '
              'keuangan. Semua metode Kasbon langsung dicatat sebagai piutang customer; '
              'untuk Kasbon Divisi/Operasional, member menjadi customer sekaligus PJ/PIC '
              'yang mewakili divisi.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Pilih Member / PIC')),
          ],
        ),
      );
      if (!mounted) return;
      if (lanjut == true) await _pilihMember();
      if (!mounted) return;
      if (_memberTerpilih == null) return; // tetap belum dipilih -> batalkan
    }

    String? kodePercobaan;
    setStateIfMounted(() => _memproses = true);
    try {
      kodePercobaan = _kodePengajuanLimitTertunda ?? await _buatKodeUnik();
      final kodeUnik = kodePercobaan;
      final buktiBiometrik = await _verifikasiMemberJikaPerlu(kodeUnik);
      if (buktiBiometrik == null) return;
      final waktu =
          widget.draftIdSumber == null ? DateTime.now() : _waktuTransaksi;
      final payload =
          _buatPayload(kodeUnik, waktu, sertakanStatusPelayanan: true);
      payload.addAll(buktiBiometrik);
      final sesiKasLokal = await CoreDb.instance.sesiKasAktif();
      final kodeSesiKas = '${sesiKasLokal?['kode'] ?? ''}'.trim();
      if (kodeSesiKas.isNotEmpty) payload['kode_sesi_kas'] = kodeSesiKas;

      final payloadPending = Map<String, dynamic>.from(payload);
      payloadPending['pengiriman_pending'] = true;
      Map<String, dynamic>? hasilServer;
      if (_verifikasiMemberWajibServer || _memberMemilikiLimitTransaksi) {
        // Bukti biometrik berumur pendek dan diikat ke kode transaksi. Karena
        // itu pembayaran saldo wajib menunggu ACK server dan tidak boleh masuk
        // outbox berulang yang baru terkirim setelah bukti kedaluwarsa. Hal
        // yang sama berlaku bila tipe member mempunyai limit: server harus
        // menghitung periode dan, bila perlu, membuat pengajuan supervisor
        // sebelum kasir menganggap transaksi selesai.
        hasilServer = await ApiClient.instance.aksi('bayar', payload);
        await CoreDb.instance.simpanTransaksiPending(
            kodeUnik, jsonEncode(payloadPending),
            akunKunci: Sesi.instance.userId,
            tokoId: Sesi.instance.tokoId,
            idPerangkat: IdentitasMesin.instance.idMesin);
        await CoreDb.instance.simpanHasilServerTransaksi(kodeUnik, hasilServer);
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_verifikasiMemberWajibServer
                ? 'Identitas member terverifikasi. Pembayaran sudah diterima server.'
                : 'Batas transaksi member sudah diverifikasi. Pembayaran diterima server.')));
      } else {
        // Transaksi biasa tetap local-first: tulis PENDING sebelum mencoba
        // server, lalu kirim/retry idempoten di background.
        await CoreDb.instance.simpanTransaksiPending(
            kodeUnik, jsonEncode(payloadPending),
            akunKunci: Sesi.instance.userId,
            tokoId: Sesi.instance.tokoId,
            idPerangkat: IdentitasMesin.instance.idMesin);
        TransaksiOutboxService.instance.kirimDiBackground();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Transaksi aman tersimpan di lokal. Pengiriman ke server berjalan di background; jika gagal akan dicoba lagi dalam 10 menit.')));
      }

      // Ekstra diratakan (flatten) jadi baris tersendiri TEPAT setelah induknya
      // -- StrukScreen tak kenal struktur bersarang, cuma daftar {nama,qty,
      // harga} datar (lihat JavaDoc StrukScreen._itemPdf). Prefiks "   + "
      // sbg indentasi visual, qty ekstra ikut qty induk (kontrak server: 1
      // ekstra berlaku per 1 unit induk, lihat JavaDoc [ItemEkstra]).
      final itemStruk = <Map<String, dynamic>>[];
      for (final i in widget.keranjang) {
        itemStruk.add({
          'nama': i.produk.nama,
          'qty': i.jumlah,
          'harga': i.produk.hargaJual,
          'diskon': i.diskon,
          'cashback': i.cashback,
        });
        for (final e in i.ekstra) {
          itemStruk.add({
            'nama': '   + ${e.nama}',
            'qty': i.jumlah,
            'harga': e.harga,
          });
        }
      }
      final metodeNama = _caraBayarTerpilih!.nama;
      final pelangganStruk = _memberTerpilih?.nama;
      final totalStruk = _total;
      final diskonFakturStruk = _diskonFaktur;
      final pajakStruk = _pajak;
      final pembayaranStruk = _pembayaranStruk();
      final double? uangDiterimaStruk = _splitAktif ? null : _uangDiterima;
      final double? kembalianStruk =
          _splitAktif ? null : (_kembalian < 0 ? 0.0 : _kembalian);
      final saldoStruk = _saldoDepositSetelahBayar(null);
      _kodePengajuanLimitTertunda = null;
      widget.keranjang.clear();
      // Broadcast "sukses" (bukan sekadar keranjang-kosong biasa) --
      // mengosongkan tampilan keranjang di Layar Pelanggan SEKALIGUS memberi
      // sinyal pindah ke layar ucapan terima kasih + rating (gap-closure
      // "Survey Kepuasan Pelanggan", lihat JavaDoc kirimSukses).
      LayarPelangganBroadcaster.instance.kirimSukses();
      setStateIfMounted(() {
        _langsungTerlayani = true;
        _splitBayar = [];
        _nilaiDiskonFaktur = 0;
        _tipeDiskonFaktur = 'NOMINAL';
        _roomChargeStay = null;
      });
      widget.onSelesai?.call();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => StrukScreen(
          kode: kodeUnik,
          waktu: _formatWaktuServer(waktu),
          item: itemStruk,
          total: totalStruk,
          metode: metodeNama,
          pembayaran: pembayaranStruk,
          pajak: pajakStruk,
          diskonFaktur: diskonFakturStruk,
          tersinkron: false,
          pelanggan: pelangganStruk,
          uangDiterima: uangDiterimaStruk,
          kembalian: kembalianStruk,
          saldo: saldoStruk,
        ),
      ));
    } catch (e, stackTrace) {
      if (e is ApiException &&
          e.kode == 'PENGAJUAN_LIMIT_MENUNGGU' &&
          kodePercobaan != null) {
        final pesanLimit = e.pesan.toLowerCase();
        // Keputusan ditolak atau isi checkout sudah berubah berarti persetujuan
        // lama tidak boleh digunakan. Selain dua keadaan itu, jangan mengganti
        // kode pada retry karena persetujuan supervisor di backend hanya sah
        // untuk transaksi, member, dan nominal yang sama.
        _kodePengajuanLimitTertunda =
            pesanLimit.contains('ditolak') || pesanLimit.contains('berbeda')
                ? null
                : kodePercobaan;
      }
      // Kegagalan sebelum pemanggilan API (mis. tulis outbox SQLite, pembuatan
      // nomor struk, atau serialisasi payload) dahulu hanya sampai ke zone
      // handler global. Akibatnya tombol kembali normal tanpa penjelasan dan
      // kasir mengira tombol Bayar tidak bekerja. Semua kegagalan checkout
      // sekarang selalu dicatat dan ditampilkan dengan detail yang bisa disalin.
      await CoreDb.instance.catatErrorLog(
        sumber: 'checkout-pos',
        tingkat: 'ERROR',
        pesan: e.toString(),
        detail: stackTrace.toString(),
      );
      if (mounted) {
        await tampilkanKesalahan(context, e, aktivitas: 'menyimpan pembayaran');
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  /// F4 "Pilih Metode Pembayaran" (padanan pos-renderer.js) -- di Electron
  /// tombol ini membuka picker khusus; di sini kita reuse dropdown metode
  /// yang sudah ada, cukup ditampilkan sbg bottom sheet supaya tetap ada
  /// TARGET nyata utk pintasan F4 (bukan sekadar fokus ke dropdown).
  Future<void> _pilihMetode() async {
    if (_memuatCaraBayar) return;

    // Jangan mengandalkan snapshot konfigurasi saat login. Metode pembayaran
    // dapat diubah admin ketika aplikasi Kasir 2/3 tetap terbuka; muat ulang
    // persis sebelum dialog ditampilkan supaya seluruh perangkat pada toko
    // yang sama melihat izin member/metode terbaru tanpa harus logout.
    await _muatCaraBayarUntukMember(
        _semuaCaraBayarUntukMemberAwal ? null : _memberTerpilih?.id);
    if (!mounted || _caraBayarTersedia.isEmpty) return;
    final awal = _splitBayar.isNotEmpty
        ? _splitBayar
        : (_caraBayarTerpilih != null
            ? [_SlotBayar(_caraBayarTerpilih!, _total)]
            : <_SlotBayar>[]);
    final hasil = await showModalBottomSheet<List<_SlotBayar>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetPilihMetodeSplit(
        daftarMetode: _caraBayarTersedia,
        terpilihAwal: awal,
        total: _total,
      ),
    );
    if (hasil == null || hasil.isEmpty) return;
    setStateIfMounted(() {
      _caraBayarTerpilih = hasil.first.caraBayar;
      _splitBayar = hasil.length >= 2 ? hasil : [];
    });
  }

  Future<void> _aturDiskonFaktur() async {
    var tipe = _tipeDiskonFaktur;
    final controller = TextEditingController(
        text: _nilaiDiskonFaktur > 0
            ? _nilaiDiskonFaktur.toStringAsFixed(
                _nilaiDiskonFaktur == _nilaiDiskonFaktur.roundToDouble()
                    ? 0
                    : 2)
            : '');
    try {
      final hasil = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Potongan Faktur'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Potongan ini mengurangi total pembelian dan akan tercetak pada struk.'),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'NOMINAL', label: Text('Nominal Rupiah')),
                      ButtonSegment(value: 'PERSEN', label: Text('Persentase')),
                    ],
                    selected: {tipe},
                    onSelectionChanged: (nilai) =>
                        setDialogState(() => tipe = nilai.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    decoration: InputDecoration(
                      labelText: tipe == 'PERSEN'
                          ? 'Persentase potongan (%)'
                          : 'Nominal potongan (Rp)',
                      helperText: tipe == 'PERSEN'
                          ? 'Maksimal 100%'
                          : 'Maksimal sebesar total barang',
                      border: _radiusInput,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal')),
              TextButton(
                  onPressed: () => Navigator.pop(
                      dialogContext, {'tipe': 'NOMINAL', 'nilai': 0.0}),
                  child: const Text('Hapus Potongan')),
              FilledButton(
                onPressed: () {
                  final nilai = double.tryParse(controller.text
                          .replaceAll('.', '')
                          .replaceAll(',', '.')) ??
                      0;
                  Navigator.pop(dialogContext, {'tipe': tipe, 'nilai': nilai});
                },
                child: const Text('Terapkan'),
              ),
            ],
          ),
        ),
      );
      if (hasil == null) return;
      setStateIfMounted(() {
        _tipeDiskonFaktur = hasil['tipe'] as String;
        final nilai = (hasil['nilai'] as num).toDouble();
        _nilaiDiskonFaktur = _tipeDiskonFaktur == 'PERSEN'
            ? nilai.clamp(0, 100).toDouble()
            : nilai.clamp(0, _dasarDiskonFaktur).toDouble();
        _splitBayar = [];
        _sinkronkanUangDiterima();
      });
      _siarkanKeranjang();
    } finally {
      controller.dispose();
    }
  }

  /// Pintasan keyboard F2 Bayar/F3 Tahan/F4 Metode/F5 Member -- padanan
  /// pos-renderer.js `PETA_TOMBOL_KASIR` (lihat kasir_screen.dart utk
  /// F7/F8/F9). Desktop-only; diam di Android.
  bool _sedangInputTeksAktif() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _tanganiTombolKeranjang(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_sedangInputTeksAktif()) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      if (_bisaBayar) _bayar();
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

  static const _radiusInput =
      OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)));

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _tanganiTombolKeranjang,
      child: ColoredBox(
        color: AppColors.pageBgOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.tampilkanJudul && widget.pencarianBarang == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.shopping_cart,
                        size: 18, color: AppColors.textPrimaryOf(context)),
                    const SizedBox(width: 8),
                    Text('Keranjang',
                        style: TextStyle(
                            color: AppColors.textPrimaryOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (widget.aksiHeader != null) widget.aksiHeader!,
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final checkoutSamping = constraints.maxWidth >= 760;
                  if (checkoutSamping) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _kartuManajemenItem()),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 360,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: double.infinity,
                              child: _panelCheckout(samping: true),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _daftarItemKeranjang()),
                      _panelCheckout(samping: false),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pemilihMember() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labelBagian('Ambil Data Member'),
          const SizedBox(height: 8),
          _memberTerpilih == null
              ? SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _pilihMember,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add_alt, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Pilih Member (opsional) - F5',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.warning),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                      child: Text(_memberTerpilih!.nama.isNotEmpty
                          ? _memberTerpilih!.nama[0].toUpperCase()
                          : '?'),
                    ),
                    title: Text(_memberTerpilih!.nama,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                        [
                          if (_memberTerpilih!.kodeIdentitas.isNotEmpty)
                            _memberTerpilih!.kodeIdentitas,
                          'Saldo: ${_saldoMember == null ? "..." : _formatRupiah.format(_saldoMember)}',
                          if (_memberTerpilih!.wajibPin) 'Wajib PIN',
                          if (_memberTerpilih!.wajibBiometricWajah)
                            'Wajib Wajah',
                          if (_memberTerpilih!.wajibBiometricFingerprint)
                            'Wajib Fingerprint',
                        ].join(' - '),
                        style: const TextStyle(fontSize: 11.5)),
                    trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _hapusMember),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _pilihWaktuTransaksi() async {
    final sekarang = DateTime.now();
    final tanggalAwal =
        _waktuTransaksi.isAfter(sekarang) ? sekarang : _waktuTransaksi;
    final tanggal = await showDatePicker(
      context: context,
      initialDate: tanggalAwal,
      firstDate: DateTime(2000),
      lastDate: sekarang,
      helpText: 'Pilih tanggal transaksi',
    );
    if (tanggal == null || !mounted) return;
    final jam = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_waktuTransaksi),
      helpText: 'Pilih jam transaksi',
    );
    if (jam == null || !mounted) return;
    final pilihan = DateTime(
      tanggal.year,
      tanggal.month,
      tanggal.day,
      jam.hour,
      jam.minute,
    );
    if (pilihan.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Tanggal dan jam transaksi tidak boleh di masa depan.')));
      return;
    }
    setStateIfMounted(() => _waktuTransaksi = pilihan);
  }

  Widget _pemilihWaktuTransaksiTertahan() {
    if (widget.draftIdSumber == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labelBagian('Tanggal transaksi'),
          const SizedBox(height: 8),
          InkWell(
            onTap: _memproses ? null : _pilihWaktuTransaksi,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Tanggal dan jam transaksi',
                helperText:
                    'Transaksi tertahan akan disimpan pada tanggal/jam ini.',
                border: _radiusInput,
                isDense: true,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('dd-MM-yyyy HH:mm').format(_waktuTransaksi)),
                  const Icon(Icons.calendar_month_outlined, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pintu masuk pengaturan promo per barang. Kasir memilih barang dahulu,
  /// kemudian memilih promo/cashback yang eligible khusus untuk barang itu.
  Widget _promoManualPicker() {
    if (widget.keranjang.isEmpty) return const SizedBox.shrink();
    final jumlahAktif =
        widget.keranjang.where((i) => i.promoManual || i.diskonBebas).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labelBagian('Promo Manual'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _bukaPickerPromoManual(),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text(jumlahAktif == 0
                  ? 'Atur Promo per Item'
                  : '$jumlahAktif item memakai promo/diskon bebas'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (jumlahAktif > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _hapusPromoManual,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Lepas semua promo/diskon'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _labelBagian(String teks) {
    final warna = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: warna,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          teks,
          style: TextStyle(
            color: warna,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _kartuManajemenItem() {
    if (widget.pencarianBarang == null) return _daftarItemKeranjang();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: AppColors.gelap(context)
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _labelBagian('Item yang dibeli'),
                  const SizedBox(height: 10),
                  widget.pencarianBarang!,
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart,
                      size: 18, color: AppColors.textPrimaryOf(context)),
                  const SizedBox(width: 8),
                  Text('Keranjang',
                      style: TextStyle(
                          color: AppColors.textPrimaryOf(context),
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(child: _daftarItemKeranjang(dibungkusCard: false)),
          ],
        ),
      ),
    );
  }

  Widget _daftarItemKeranjang({bool dibungkusCard = true}) {
    if (widget.keranjang.isEmpty) {
      _itemTeratasTerakhir = null;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 40, color: AppColors.borderOf(context)),
            const SizedBox(height: 8),
            Text('Belum ada produk dipilih.',
                style: TextStyle(color: AppColors.textSecondaryOf(context))),
          ],
        ),
      );
    }
    // Bila hasil scan baru mengubah item teratas ketika kasir sedang berada
    // di halaman paging berikutnya, langsung kembali ke halaman pertama agar
    // item yang baru dipindai benar-benar terlihat tanpa klik tambahan.
    final itemTeratas = widget.keranjang.first;
    if (!identical(_itemTeratasTerakhir, itemTeratas)) {
      _itemTeratasTerakhir = itemTeratas;
      _halamanKeranjang = 1;
    }
    final totalHalaman = (widget.keranjang.length / _pageSizeKeranjang)
        .ceil()
        .clamp(1, 999999)
        .toInt();
    final halaman = _halamanKeranjang.clamp(1, totalHalaman).toInt();
    final awal = (halaman - 1) * _pageSizeKeranjang;
    final itemHalamanIni =
        widget.keranjang.skip(awal).take(_pageSizeKeranjang).toList();
    final tabel = AppDataTable(
      minWidth: 620,
      columns: const [
        AppTableColumn('Item', flex: 4),
        AppTableColumn('Harga', flex: 2, align: TextAlign.right),
        AppTableColumn('Qty', width: 154, align: TextAlign.center),
        AppTableColumn('Subtotal', flex: 2, align: TextAlign.right),
      ],
      rows: itemHalamanIni
          .map((item) => AppTableRowData(cells: [
                AppTableCell(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.produk.nama,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                      // Sub-baris ekstra terpilih -- gaya sama dgn sub-baris
                      // Diskon di bawah ini (indentasi via prefiks "+", warna
                      // sekunder supaya tetap kalah tonjol drpd nama produk).
                      for (final e in item.ekstra)
                        Text('+ ${e.nama}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textSecondaryOf(context),
                                fontSize: 11.5)),
                      if (item.diskon > 0)
                        Text('Diskon ${_formatRupiah.format(item.diskon)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 11.5)),
                      if (item.cashback > 0)
                        Text('Cashback ${_formatRupiah.format(item.cashback)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.success, fontSize: 11.5)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _bukaPickerPromoManual(item),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                            icon: Icon(
                                item.promoManual || item.diskonBebas
                                    ? Icons.sell
                                    : Icons.sell_outlined,
                                size: 14),
                            label: Text(
                              item.diskonBebas
                                  ? 'Diskon bebas ${item.diskonBebasTipe == 'PERSEN' ? '${item.diskonBebasNilai.toStringAsFixed(0)}%' : _formatRupiah.format(item.diskonBebasNilai)}'
                                  : item.promoManual
                                      ? '${_metadataPromoManual[item.promoManualAturanId]?['namaAturan'] ?? 'Promo manual'}'
                                      : 'Atur promo item',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          if (item.promoManual || item.diskonBebas)
                            IconButton(
                              tooltip: 'Lepas promo item ini',
                              onPressed: () => _hapusPromoManualItem(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.close, size: 14),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                AppTableCell.text(_formatRupiah.format(item.produk.hargaJual),
                    flex: 2, align: TextAlign.right),
                AppTableCell(
                  width: 154,
                  align: TextAlign.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _tombolBulat(Icons.remove, () => _ubahJumlah(item, -1)),
                      SizedBox(
                        width: 32,
                        child: Text('${item.jumlah}',
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      _tombolBulat(Icons.add, () => _ubahJumlah(item, 1)),
                      const SizedBox(width: 4),
                      _tombolQtyManual(item),
                    ],
                  ),
                ),
                AppTableCell.text(
                    _formatRupiah.format(item.subtotalSetelahDiskon),
                    flex: 2,
                    align: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ]))
          .toList(),
      pagination: AppTablePagination(
        halaman: halaman,
        totalHalaman: totalHalaman,
        totalData: widget.keranjang.length,
        labelData: 'item',
        onSebelumnya: halaman > 1
            ? () => setStateIfMounted(() => _halamanKeranjang = halaman - 1)
            : null,
        onBerikutnya: halaman < totalHalaman
            ? () => setStateIfMounted(() => _halamanKeranjang = halaman + 1)
            : null,
      ),
    );
    final daftar = SingleChildScrollView(child: tabel);
    if (!dibungkusCard) return daftar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: AppColors.gelap(context)
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: daftar,
      ),
    );
  }

  Widget _panelCheckout({required bool samping}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppColors.gelap(context)
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: Offset(samping ? -2 : 0, samping ? 0 : -2),
                )
              ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pemilihWaktuTransaksiTertahan(),
            _pemilihMember(),
            _promoManualPicker(),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            _labelBagian('Pilih metode pembayaran'),
            const SizedBox(height: 8),
            InkWell(
              // Tetap dapat diketuk ketika snapshot kosong: _pilihMetode akan
              // meminta daftar terbaru ke server. Hanya permintaan yang sedang
              // berjalan yang mencegah ketukan ganda.
              onTap: _memuatCaraBayar || _caraBayarDikunciTipe
                  ? null
                  : _pilihMetode,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Metode Pembayaran - F4',
                    border: _radiusInput,
                    isDense: true),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                          _memuatCaraBayar
                              ? 'Memuat metode...'
                              : _caraBayarTersedia.isEmpty
                                  ? (_memberTerpilih == null
                                      ? 'Tidak ada metode aktif'
                                      : 'Tidak ada metode yang diizinkan')
                                  : _splitAktif
                                      ? '${_splitBayar.length} Metode (Split)'
                                      : _caraBayarTerpilih?.nama ?? 'Pilih',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (_memuatCaraBayar)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else if (_caraBayarDikunciTipe)
                      const Icon(Icons.lock_outline, size: 18)
                    else
                      const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
            if (_izinCaraBayarMemberTidakDisetel) ...[
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Izin metode pembayaran untuk jenis member ini belum '
                  'disetel. Sementara semua metode aktif dapat dipilih; '
                  'mohon admin melengkapi konfigurasinya.',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            ],
            if (_caraBayarDikunciTipe) ...[
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cara pembayaran dikunci oleh Tipe Member dan dipilih otomatis.',
                  style: TextStyle(fontSize: 11, color: AppColors.success),
                ),
              ),
            ],
            if (AppProductProfile.aktif.isMitraInap) ...[
              const SizedBox(height: 8),
              _pemilihRoomCharge(),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Buat tiket dapur untuk nota ini'),
                value: _buatTiketDapur,
                onChanged: _memproses
                    ? null
                    : (v) =>
                        setStateIfMounted(() => _buatTiketDapur = v == true),
              ),
            ],
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            if (_totalDiskon > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Diskon',
                        style: TextStyle(color: Color(0xFFC0563D))),
                    Text('-${_formatRupiah.format(_totalDiskon)}',
                        style: const TextStyle(color: Color(0xFFC0563D))),
                  ],
                ),
              ),
            if (_diskonFaktur > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        _tipeDiskonFaktur == 'PERSEN'
                            ? 'Potongan Faktur (${_nilaiDiskonFaktur.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '')}%)'
                            : 'Potongan Faktur',
                        style: const TextStyle(color: Color(0xFFC0563D))),
                    Text('-${_formatRupiah.format(_diskonFaktur)}',
                        style: const TextStyle(color: Color(0xFFC0563D))),
                  ],
                ),
              ),
            if (_totalCashback > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cashback (masuk saldo)',
                        style: TextStyle(color: Color(0xFF2E7D32))),
                    Text('+${_formatRupiah.format(_totalCashback)}',
                        style: const TextStyle(color: Color(0xFF2E7D32))),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal',
                    style:
                        TextStyle(color: AppColors.textSecondaryOf(context))),
                Text(_formatRupiah.format(_subtotal),
                    style:
                        TextStyle(color: AppColors.textSecondaryOf(context))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      'Pajak (${Sesi.instance.pajakPersen.toStringAsFixed(0)}%)',
                      style:
                          TextStyle(color: AppColors.textSecondaryOf(context))),
                  Text(_formatRupiah.format(_pajak),
                      style:
                          TextStyle(color: AppColors.textSecondaryOf(context))),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(_formatRupiah.format(_total),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _memproses || widget.keranjang.isEmpty
                    ? null
                    : _aturDiskonFaktur,
                icon: const Icon(Icons.percent_outlined, size: 18),
                label: Text(_diskonFaktur > 0
                    ? 'Ubah Potongan Faktur'
                    : 'Tambah Potongan Faktur'),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            InkWell(
              onTap: _memproses ? null : _bukaDialogUangDiterima,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Uang Diterima',
                  border: _radiusInput,
                  isDense: true,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatRupiah.format(_uangDiterima),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.payments_outlined,
                      size: 18,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _memproses ? null : _bukaDialogUangDiterima,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Input Uang Diterima'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (_uangDiterima > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kembalian',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      _formatRupiah.format(_kembalian.abs()),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kembalian < 0
                              ? AppColors.danger
                              : AppColors.success),
                    ),
                  ],
                ),
              ),
            if (_uangTunaiKurang)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppInfoBanner(
                  icon: Icons.warning_amber_outlined,
                  color: AppColors.danger,
                  text:
                      'Uang diterima kurang ${_formatRupiah.format((_total - _uangDiterima).abs())}.',
                ),
              ),
            const SizedBox(height: 14),
            CheckboxListTile(
              value: _langsungTerlayani,
              onChanged: _memproses
                  ? null
                  : (v) =>
                      setStateIfMounted(() => _langsungTerlayani = v ?? true),
              title: const Text(
                'Langsung terlayani',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _langsungTerlayani
                    ? 'Riwayat tersimpan sebagai Terlayani'
                    : 'Riwayat tersimpan sebagai Menunggu',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _memproses || widget.keranjang.isEmpty ? null : _tahan,
                    icon: const Icon(Icons.pause_circle_outline, size: 18),
                    label: const Text('Tahan - F3',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _bisaBayar ? _bayar : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _memproses
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Bayar - F2',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bukaDialogQtyManual(ItemKeranjang item) async {
    final jumlah = await showDialog<int>(
      context: context,
      builder: (_) => _DialogInputJumlahKeranjang(
        namaProduk: item.produk.nama,
        jumlahAwal: item.jumlah,
      ),
    );
    if (jumlah != null) _aturJumlahItem(item, jumlah);
  }

  Widget _tombolQtyManual(ItemKeranjang item) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        tooltip: 'Input qty manual',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.edit_outlined, size: 15),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.pageBgOf(context),
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _bukaDialogQtyManual(item),
      ),
    );
  }

  Widget _tombolBulat(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 16),
        style: IconButton.styleFrom(
            backgroundColor: AppColors.pageBgOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            shape: const CircleBorder()),
        onPressed: onPressed,
      ),
    );
  }
}

class _DialogInputJumlahKeranjang extends StatefulWidget {
  final String namaProduk;
  final int jumlahAwal;
  const _DialogInputJumlahKeranjang({
    required this.namaProduk,
    required this.jumlahAwal,
  });
  @override
  State<_DialogInputJumlahKeranjang> createState() =>
      _DialogInputJumlahKeranjangState();
}

class _DialogInputJumlahKeranjangState
    extends State<_DialogInputJumlahKeranjang> {
  late final TextEditingController _controller;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.jumlahAwal.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _terapkan() {
    final nilai = int.tryParse(_controller.text.trim());
    if (nilai == null || nilai < 1) {
      setState(() => _error = 'Qty minimal 1.');
      return;
    }
    Navigator.of(context).pop(nilai);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Input Qty Manual'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.namaProduk,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Qty',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _terapkan(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _terapkan,
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}

/// Satu slot pembayaran (metode + nominal) dlm split pembayaran s/d 5
/// metode/transaksi. Lihat JavaDoc `_PanelKeranjangState._splitBayar`.
class _SlotBayar {
  final CaraBayar caraBayar;
  double nominal;
  _SlotBayar(this.caraBayar, this.nominal);
}

/// Bottom sheet pilih metode pembayaran -- padanan `_pos.jsp` modal "Pilih
/// Metode Pembayaran": tap BARIS (di luar checkbox) = pilih SATU metode utk
/// bayar penuh & langsung tutup (perilaku lama, zero-friction utk kasus
/// mayoritas satu-metode); centang ikon checkbox = gabungkan s/d 5 metode
/// (split pembayaran), memunculkan panel bagi nominal di bawah daftar.
class _SheetPilihMetodeSplit extends StatefulWidget {
  final List<CaraBayar> daftarMetode;
  final List<_SlotBayar> terpilihAwal;
  final double total;
  const _SheetPilihMetodeSplit({
    required this.daftarMetode,
    required this.terpilihAwal,
    required this.total,
  });

  @override
  State<_SheetPilihMetodeSplit> createState() => _SheetPilihMetodeSplitState();
}

class _SheetPilihMetodeSplitState extends State<_SheetPilihMetodeSplit> {
  late List<_SlotBayar> _terpilih;

  @override
  void initState() {
    super.initState();
    _terpilih = widget.terpilihAwal
        .map((s) => _SlotBayar(s.caraBayar, s.nominal))
        .toList();
  }

  void _toggle(CaraBayar c) {
    final idx = _terpilih.indexWhere((s) => s.caraBayar.id == c.id);
    if (idx >= 0) {
      setState(() => _terpilih.removeAt(idx));
      return;
    }
    if (_terpilih.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Maksimal 5 metode pembayaran per transaksi.')));
      return;
    }
    setState(() {
      _terpilih.add(_SlotBayar(c, 0));
      _bagiRataJikaKosong();
    });
  }

  /// Default bagi rata SEKALI saat jumlah slot berubah (semua nominal masih
  /// 0) -- tidak dijalankan ulang tiap render supaya angka yg sudah diedit
  /// manual kasir tidak direset.
  void _bagiRataJikaKosong() {
    if (_terpilih.length < 2 || widget.total <= 0) return;
    if (!_terpilih.every((s) => s.nominal == 0)) return;
    final n = _terpilih.length;
    final rata = (widget.total / n).floorToDouble();
    for (var i = 0; i < n; i++) {
      _terpilih[i].nominal =
          (i == n - 1) ? (widget.total - rata * (n - 1)) : rata;
    }
  }

  double get _totalDialokasikan =>
      _terpilih.fold(0.0, (sum, s) => sum + s.nominal);
  double get _sisa => widget.total - _totalDialokasikan;
  bool get _seimbang => _sisa.abs() < 1;

  @override
  Widget build(BuildContext context) {
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
                    'Ketuk baris utk bayar penuh 1 metode, atau centang kotak utk gabungkan s/d 5 metode (split bayar).',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              ...widget.daftarMetode.map((c) {
                final aktif = _terpilih.any((s) => s.caraBayar.id == c.id);
                return ListTile(
                  leading: Checkbox(
                    value: aktif,
                    onChanged: (_) => _toggle(c),
                  ),
                  title: Text(c.nama),
                  onTap: () =>
                      Navigator.of(context).pop([_SlotBayar(c, widget.total)]),
                );
              }),
              if (_terpilih.length >= 2) ...[
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Bagi Nominal per Metode',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ..._terpilih.map((s) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(s.caraBayar.nama,
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 140,
                            child: TextFormField(
                              key: ValueKey('nominal-split-${s.caraBayar.id}'),
                              initialValue: s.nominal.toStringAsFixed(0),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                prefixText: 'Rp ',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(
                                  () => s.nominal = double.tryParse(v) ?? 0),
                            ),
                          ),
                        ],
                      ),
                    )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sisa belum dialokasikan',
                          style: TextStyle(fontSize: 12)),
                      Text(
                        NumberFormat.currency(
                                locale: 'id_ID',
                                symbol: 'Rp ',
                                decimalDigits: 0)
                            .format(_sisa),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _seimbang ? Colors.green : Colors.red),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: ElevatedButton(
                    onPressed: _seimbang
                        ? () => Navigator.of(context).pop(_terpilih)
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

/// Langkah pertama promo manual: pilih tepat satu baris keranjang. Object
/// dikembalikan berdasarkan identitas baris, sehingga dua baris produk sama
/// dengan ekstra berbeda tidak saling tertukar.
class _SheetPilihItemPromoManual extends StatelessWidget {
  final List<ItemKeranjang> daftar;
  const _SheetPilihItemPromoManual({required this.daftar});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.shopping_cart_outlined),
              title: Text('Pilih item yang akan diberi promo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Promo/cashback manual diterapkan per item.'),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: daftar.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = daftar[index];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(item.produk.nama),
                    subtitle: Text([
                      '${item.jumlah} x ${_formatRupiah.format(item.produk.hargaJual)}',
                      if (item.diskonBebas) 'Sudah memakai diskon bebas',
                      if (item.promoManual) 'Sudah memakai promo manual',
                    ].join(' - ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet "Promo Manual" (gap-closure "Aktivasi Manual", Fase 2 Stretch)
/// -- padanan visual `_SheetPilihEkstra` (kasir_screen.dart): daftar
/// ListTile, tap SATU baris = pilih & tutup (tanpa tombol konfirmasi
/// terpisah, sama seperti baris metode pembayaran non-split di
/// [_SheetPilihMetodeSplitState] di atas). Sumber daftar HANYA rule
/// `aktivasiManual=true` yg eligible utk minimal satu item keranjang saat
/// ini (aksi `diskon_manual_list`, sudah difilter server -- lihat JavaDoc
/// [_PanelKeranjangState._bukaPickerPromoManual]).
class _SheetPilihPromoManual extends StatelessWidget {
  final List<Map<String, dynamic>> daftar;
  final String namaItem;
  const _SheetPilihPromoManual({required this.daftar, required this.namaItem});

  String _keterangan(Map<String, dynamic> promo) {
    final persentase = (promo['persentase'] as num?)?.toDouble() ?? 0;
    final nominal = (promo['nominal'] as num?)?.toDouble() ?? 0;
    final potonganLangsung = promo['potonganLangsung'] != false;
    final besaran = persentase > 0
        ? 'Potongan ${persentase.toStringAsFixed(0)}%'
        : 'Potongan ${_formatRupiah.format(nominal)}';
    return potonganLangsung ? besaran : '$besaran (cashback)';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.sell_outlined,
                        size: 18, color: AppColors.textPrimaryOf(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Pilih promo untuk $namaItem',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimaryOf(context),
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: daftar.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(Icons.percent_outlined),
                        title: const Text('Diskon Bebas'),
                        subtitle: const Text(
                            'Masukkan potongan nominal atau persentase tanpa master promo.'),
                        onTap: () => Navigator.of(context)
                            .pop(<String, dynamic>{'diskonBebas': true}),
                      );
                    }
                    final p = daftar[i - 1];
                    return ListTile(
                      leading: const Icon(Icons.sell_outlined),
                      title: Text('${p['namaAturan'] ?? ''}'),
                      subtitle: Text([
                        _keterangan(p),
                        if ('${p['keterangan'] ?? ''}'.isNotEmpty)
                          '${p['keterangan']}',
                      ].join(' - ')),
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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
    _penyegarTransaksiTerbaru =
        Timer.periodic(const Duration(seconds: 20), (_) {
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
      final hasil = await ApiClient.instance.aksi('anggota_transaksi_terbaru',
          {'id_toko': Sesi.instance.tokoId, 'limit': 10});
      final arr = (hasil['data'] as List?) ?? [];
      if (mounted && _controller.text.trim().isEmpty) {
        setStateIfMounted(() {
          _hasil = arr
              .map((e) => Anggota.fromJson(e as Map<String, dynamic>))
              .toList();
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
        setStateIfMounted(() => _hasil = []);
      }
      return;
    }
    setStateIfMounted(() {
      _mencari = true;
      _transaksiTerbaru = false;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('cari_member', {'keyword': kataKunci});
      final arr = (hasil['member'] as List?) ?? [];
      if (mounted) {
        setStateIfMounted(() {
          _hasil = arr
              .map((e) => Anggota.fromJson(e as Map<String, dynamic>))
              .toList();
          _modeOffline = false;
        });
      }
    } catch (_) {
      final cache = await CoreDb.instance.cariAnggotaCache(kataKunci);
      if (mounted) {
        setStateIfMounted(() {
          _hasil = cache.map(Anggota.fromCache).toList();
          _modeOffline = true;
        });
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _tambahMemberBaru() async {
    final anggota = await showDialog<Anggota>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogTambahMemberCepat(),
    );
    if (anggota != null && mounted) Navigator.of(context).pop(anggota);
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
            AppSearchField(
              controller: _controller,
              hintText: 'Cari nama/kode/telepon/email...',
              autofocus: true,
              debounce: Duration.zero,
              onChanged: _onBerubah,
            ),
            if (_modeOffline)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Menampilkan data cache (offline)',
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            if (_transaksiTerbaru && _hasil.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Transaksi Terbaru',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondaryOf(context)))),
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
                          subtitle: Text([
                            if (a.kodeIdentitas.isNotEmpty) a.kodeIdentitas,
                            if (a.hp.isNotEmpty) a.hp,
                            if (a.hp.isEmpty && a.telp.isNotEmpty) a.telp,
                            if (a.email.isNotEmpty) a.email,
                          ].join(' • ')),
                          trailing: a.wajibBiometricWajah ||
                                  a.wajibBiometricFingerprint
                              ? const Icon(Icons.verified_user_outlined,
                                  size: 18, color: Colors.teal)
                              : a.wajibPin
                                  ? const Icon(Icons.pin,
                                      size: 18, color: Colors.orange)
                                  : null,
                          onTap: () => Navigator.of(context).pop(a),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
            onPressed: _tambahMemberBaru,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Tambah Member Baru')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
      ],
    );
  }
}

class _DialogTambahMemberCepat extends StatefulWidget {
  const _DialogTambahMemberCepat();

  @override
  State<_DialogTambahMemberCepat> createState() =>
      _DialogTambahMemberCepatState();
}

class _DialogTambahMemberCepatState extends State<_DialogTambahMemberCepat> {
  final _formKey = GlobalKey<FormState>();
  final _nama = TextEditingController();
  final _hp = TextEditingController();
  bool _menyimpan = false;

  @override
  void dispose() {
    _nama.dispose();
    _hp.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      final body = {
        'nama': _nama.text.trim(),
        'hp': _hp.text.trim(),
      };
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster) -- dialog
      // proses tampil di atas dialog tambah-member kasir (memang diinginkan).
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'anggota_simpan_cepat',
        body: body,
        kunci: 'anggota:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:anggota',
        rowLokal: body,
      );
      if (hasil['offline'] == true) {
        // Belum ada id dari server -- member tersimpan lokal tapi belum bisa
        // dipilih utk transaksi ini; tutup dialog tanpa memilih member.
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      final raw = hasil['member'];
      if (raw is! Map) {
        throw const FormatException('Data member tidak tersedia pada balasan.');
      }
      final anggota = Anggota.fromJson(Map<String, dynamic>.from(raw));
      if (!mounted) return;
      final sudahAda = hasil['dipakaiYangSudahAda'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sudahAda
            ? 'Nomor sudah terdaftar. Member ${anggota.nama} dipilih; tidak dibuat duplikat.'
            : 'Member ${anggota.nama} berhasil ditambahkan.'),
      ));
      Navigator.of(context).pop(anggota);
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'menambahkan member');
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Member Baru'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nomor telepon menjadi identitas unik. Jika nomor sudah terdaftar, aplikasi otomatis memilih member lama dan tidak membuat data ganda.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nama,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Member *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Nama member wajib diisi.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hp,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+() -]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Nomor Telepon / WhatsApp *',
                  hintText: 'Contoh: 081234567890',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) {
                  final digit = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  if (digit.isEmpty) return 'Nomor telepon wajib diisi.';
                  if (digit.length < 9 || digit.length > 16) {
                    return 'Nomor telepon belum valid.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (!_menyimpan) _simpan();
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _menyimpan ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _menyimpan ? null : _simpan,
          icon: _menyimpan
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_menyimpan ? 'Menyimpan...' : 'Simpan & Pilih'),
        ),
      ],
    );
  }
}

class _DialogUangDiterima extends StatefulWidget {
  final double nilaiAwal;
  final double total;

  const _DialogUangDiterima({
    required this.nilaiAwal,
    required this.total,
  });

  @override
  State<_DialogUangDiterima> createState() => _DialogUangDiterimaState();
}

class _DialogUangDiterimaState extends State<_DialogUangDiterima> {
  static const _nominalCepat = <int>[
    5000,
    10000,
    15000,
    20000,
    25000,
    30000,
    50000,
    75000,
    100000,
    150000,
    200000,
    250000,
    300000,
    500000,
    750000,
    1000000,
  ];

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final nilai =
        widget.nilaiAwal > 0 ? widget.nilaiAwal : widget.total.ceilToDouble();
    _controller = TextEditingController(
      text: nilai <= 0 ? '' : nilai.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _nilai {
    final teks = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(teks) ?? 0;
  }

  void _pilihNominal(int nominal) {
    setState(() {
      _controller.text = nominal.toString();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _simpan() => Navigator.of(context).pop(_nilai);

  @override
  Widget build(BuildContext context) {
    final nilai = _nilai;
    final kembalian = nilai - widget.total;
    return AlertDialog(
      title: const Text('Uang Diterima'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Nominal Uang',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _simpan(),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final jumlahKolom = constraints.maxWidth >= 480 ? 4 : 3;
                final lebarTombol =
                    (constraints.maxWidth - ((jumlahKolom - 1) * 8)) /
                        jumlahKolom;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _nominalCepat
                      .map(
                        (nominal) => SizedBox(
                          width: lebarTombol,
                          child: OutlinedButton(
                            onPressed: () => _pilihNominal(nominal),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_formatRupiah.format(nominal)),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(color: AppColors.textSecondaryOf(context)),
                ),
                Text(
                  _formatRupiah.format(widget.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  kembalian < 0 ? 'Kurang' : 'Kembalian',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _formatRupiah.format(kembalian.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kembalian < 0 ? AppColors.danger : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _simpan,
          child: const Text('Gunakan Nominal'),
        ),
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

  void _tekanAngka(String angka) {
    if (_controller.text.length >= 12) return;
    setState(() => _controller.text += angka);
  }

  void _hapusSatu() {
    if (_controller.text.isEmpty) return;
    setState(() => _controller.text =
        _controller.text.substring(0, _controller.text.length - 1));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masukkan PIN Member'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN numerik',
                helperText: 'Gunakan keypad di bawah atau papan ketik angka.',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) =>
                  v.isEmpty ? null : Navigator.of(context).pop(v.trim()),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.75,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final angka in const [
                  '1',
                  '2',
                  '3',
                  '4',
                  '5',
                  '6',
                  '7',
                  '8',
                  '9'
                ])
                  FilledButton.tonal(
                    onPressed: () => _tekanAngka(angka),
                    child: Text(angka),
                  ),
                OutlinedButton(
                  onPressed: _controller.text.isEmpty
                      ? null
                      : () => setState(() => _controller.clear()),
                  child: const Text('C'),
                ),
                FilledButton.tonal(
                  onPressed: () => _tekanAngka('0'),
                  child: const Text('0'),
                ),
                OutlinedButton(
                  onPressed: _controller.text.isEmpty ? null : _hapusSatu,
                  child: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        ElevatedButton(
            onPressed: _controller.text.isEmpty
                ? null
                : () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Verifikasi')),
      ],
    );
  }
}
