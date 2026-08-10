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
import '../sesi.dart';
import '../services/layar_pelanggan_broadcaster.dart';
import '../services/pelayanan_transaksi.dart';
import '../services/pengaturan_nomor_struk.dart';
import '../services/pengaturan_pembayaran.dart';
import '../theme/app_colors.dart';
import 'struk_screen.dart';
import '../widgets/safe_state.dart';
import '../widgets/app_components.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
  const KeranjangScreen(
      {super.key,
      required this.keranjang,
      this.draftIdSumber,
      this.draftKodeSumber,
      this.memberAwal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: PanelKeranjang(
          keranjang: keranjang,
          draftIdSumber: draftIdSumber,
          draftKodeSumber: draftKodeSumber,
          memberAwal: memberAwal),
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
    this.pencarianBarang,
    this.tampilkanJudul = false,
    this.aksiHeader,
    this.onSelesai,
  });

  @override
  State<PanelKeranjang> createState() => _PanelKeranjangState();
}

class _PanelKeranjangState extends State<PanelKeranjang> {
  static const _pageSizeKeranjang = 12;
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
  int _versiPermintaanCaraBayar = 0;
  bool _memproses = false;
  Anggota? _memberTerpilih;
  double? _saldoMember;
  Timer? _debounceDiskon;
  final _uangDiterimaController = TextEditingController(text: '0');
  bool _uangDiterimaManual = false;
  int _halamanKeranjang = 1;
  bool _langsungTerlayani = true;

  @override
  void initState() {
    super.initState();
    _memberTerpilih = widget.memberAwal;
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
    await _muatCaraBayarUntukMember(_memberTerpilih?.id);
  }

  /// Memuat ulang metode pembayaran setiap kali member berubah, sama seperti
  /// `loadMetodePembayaranPOS` di `_pos.jsp`. Tanpa member server mengembalikan
  /// semua cara bayar aktif; dengan member server memfilter berdasarkan
  /// `jenis_anggota_koperasi.daftar_cara_pembayaran_yang_boleh_di_pilih`.
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
      final daftar = ((hasil['caraBayar'] as List?) ?? const [])
          .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || versi != _versiPermintaanCaraBayar) return;

      final idTerpilih = _caraBayarTerpilih?.id;
      CaraBayar? pilihan;
      if (idTerpilih != null) {
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

      setStateIfMounted(() {
        _caraBayarTersedia = daftar;
        _caraBayarTerpilih = pilihan;
        // Daftar metode berganti (member baru punya izin metode berbeda) --
        // split lama bisa memuat metode yg kini tak berlaku, reset drpd
        // membawa entri tak valid ke payload checkout.
        _splitBayar = [];
        _memuatCaraBayar = false;
        _sinkronkanUangDiterima();
      });
    } catch (_) {
      if (!mounted || versi != _versiPermintaanCaraBayar) return;
      // Gagal jaringan: pertahankan snapshot terakhir untuk mode offline.
      setStateIfMounted(() => _memuatCaraBayar = false);
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
      diskon: _totalDiskon,
      total: _total,
      memberNama: _memberTerpilih?.nama,
    );
  }

  double get _subtotal => widget.keranjang.fold(0, (s, i) => s + i.subtotal);
  double get _totalDiskon => widget.keranjang.fold(0, (s, i) => s + i.diskon);
  double get _totalCashback =>
      widget.keranjang.fold(0, (s, i) => s + i.cashback);

  /// `basisPajak = subtotal - totalDiskon`; `pajak = basisPajak * pajakPersen%`;
  /// `total = basisPajak + pajak` -- persis rumus Desktop (spesifikasi §3.3).
  /// `pajakPersen` bernilai 0 utk toko yg tak mengaktifkan PPN, jadi rumus ini
  /// otomatis identik dgn perilaku lama (tanpa pajak) tanpa perlu flag terpisah.
  double get _basisPajak => _subtotal - _totalDiskon;
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

  Future<void> _tandaiTerlayaniJikaPerlu(
      Map<String, dynamic> payload, Map<String, dynamic> hasil) async {
    await PelayananTransaksi.tandaiJikaPerlu(
      payload: payload,
      hasilBayar: hasil,
      percobaanCari: 1,
    );
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
      final hasil = await ApiClient.instance.aksi('diskon_evaluasi', {
        'id_member': _memberTerpilih?.id,
        'items': widget.keranjang
            .map((i) => {
                  'id': i.produk.id,
                  'harga': i.produk.hargaJual,
                  'jumlah': i.jumlah
                })
            .toList(),
      });
      final items = (hasil['items'] as List?) ?? [];
      if (!mounted) return;
      setStateIfMounted(() {
        for (final it in items) {
          final m = it as Map<String, dynamic>;
          final produkId = m['id'] as int;
          final baris =
              widget.keranjang.where((i) => i.produk.id == produkId).toList();
          if (baris.isEmpty) continue;
          baris.first
            ..diskon = (m['diskon'] as num?)?.toDouble() ?? 0
            ..cashback = (m['cashback'] as num?)?.toDouble() ?? 0
            ..aturanDiskonId = m['aturanDiskon'] as int?;
        }
        _sinkronkanUangDiterima();
      });
    } catch (_) {
      // Evaluasi diskon gagal (mis. offline) -- keranjang tetap bisa dibayar
      // tanpa diskon otomatis, bukan alasan memblokir transaksi.
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
    });
    unawaited(_muatCaraBayarUntukMember(null));
    _siarkanKeranjang();
    _jadwalkanEvaluasiDiskon();
  }

  Future<bool> _verifikasiPinJikaPerlu() async {
    final member = _memberTerpilih;
    if (member == null || !member.wajibPin) return true;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogMasukkanPin(),
    );
    if (pin == null || pin.isEmpty) return false;
    try {
      final hasil = await ApiClient.instance
          .aksi('verifikasi_pin', {'memberId': member.id, 'pin': pin});
      final ok = hasil['ok'] == true;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PIN salah.')));
      }
      return ok;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return false;
    }
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

  Map<String, dynamic> _buatPayload(
    String kodeUnik,
    DateTime waktu, {
    bool sertakanStatusPelayanan = false,
  }) {
    return {
      'kodeUnik': kodeUnik,
      'clientTrxId': kodeUnik,
      'idToko': Sesi.instance.tokoId,
      'tokoId': Sesi.instance.tokoId,
      'kasir': Sesi.instance.userId,
      'waktu': _formatWaktuServer(waktu),
      'caraBayar': _caraBayarTerpilih!.id,
      if (_splitAktif)
        'caraBayarTambahan': _splitBayar
            .skip(1)
            .map((s) => {'caraBayar': s.caraBayar.id, 'nominal': s.nominal})
            .toList(),
      'total': _total,
      'pajak': _pajak,
      'id_member': _memberTerpilih?.id,
      'nama_mesin': IdentitasMesin.instance.namaMesin,
      if (widget.draftIdSumber != null) ...{
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
                'cashback': i.cashback,
              })
          .toList(),
    };
  }

  /// "Tahan" -- simpan keranjang sbg draft belum lunas (aksi `draft_bayar`,
  /// bentuk payload SAMA dgn `bayar`) lalu kosongkan keranjang. BEDA dari
  /// Bayar: TIDAK offline-first (draft yg gagal tersimpan krn offline lebih
  /// baik gagal jelas drpd diam-diam antre lokal tanpa ada layar Pesanan
  /// utk memuatnya kembali).
  Future<void> _tahan() async {
    if (widget.keranjang.isEmpty) return;
    if (_caraBayarTerpilih == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pilih metode pembayaran terlebih dahulu.')));
      return;
    }
    setStateIfMounted(() => _memproses = true);
    try {
      final kodeUnik = await _buatKodeUnik();
      final payload = _buatPayload(kodeUnik, DateTime.now());
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
      });
      unawaited(_muatCaraBayarUntukMember(null));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transaksi ditahan (kode: $kodeUnik).')));
      widget.onSelesai?.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  Future<void> _bayar() async {
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

    setStateIfMounted(() => _memproses = true);
    try {
      if (!await _verifikasiPinJikaPerlu()) return;

      final kodeUnik = await _buatKodeUnik();
      final waktu = DateTime.now();
      final payload =
          _buatPayload(kodeUnik, waktu, sertakanStatusPelayanan: true);

      // Offline-first: tulis PENDING lokal SEBELUM mencoba server -- kegagalan
      // jaringan di bawah tidak pernah membatalkan penjualan ini.
      await CoreDb.instance
          .simpanTransaksiPending(kodeUnik, jsonEncode(payload));

      String? pesanTundaMenuju;
      try {
        final hasilBayar = await ApiClient.instance.aksi('bayar', payload);
        await _tandaiTerlayaniJikaPerlu(payload, hasilBayar);
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
      } catch (e) {
        if (e is ApiException && e.offline) {
          pesanTundaMenuju =
              'Tidak ada koneksi -- transaksi tersimpan & akan disinkron otomatis nanti.';
        } else {
          // Server MENOLAK (bukan sekadar offline) -- batalkan, jangan lanjut ke struk.
          await CoreDb.instance.hapusTransaksiPending(kodeUnik);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.toString())));
          }
          return;
        }
      }

      if (!mounted) return;
      if (pesanTundaMenuju != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pesanTundaMenuju)));
      }

      final itemStruk = widget.keranjang
          .map((i) => {
                'nama': i.produk.nama,
                'qty': i.jumlah,
                'harga': i.produk.hargaJual
              })
          .toList();
      final metodeNama = _caraBayarTerpilih!.nama;
      final pelangganStruk = _memberTerpilih?.nama;
      final totalStruk = _total;
      final pajakStruk = _pajak;
      final uangDiterimaStruk = _uangDiterima;
      final kembalianStruk = _kembalian < 0 ? 0.0 : _kembalian;
      widget.keranjang.clear();
      LayarPelangganBroadcaster.instance
          .jadwalkanKirim(items: const [], subtotal: 0, diskon: 0, total: 0);
      setStateIfMounted(() {
        _langsungTerlayani = true;
        _splitBayar = [];
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
          pajak: pajakStruk,
          tersinkron: pesanTundaMenuju == null,
          pelanggan: pelangganStruk,
          uangDiterima: uangDiterimaStruk,
          kembalian: kembalianStruk,
        ),
      ));
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  /// F4 "Pilih Metode Pembayaran" (padanan pos-renderer.js) -- di Electron
  /// tombol ini membuka picker khusus; di sini kita reuse dropdown metode
  /// yang sudah ada, cukup ditampilkan sbg bottom sheet supaya tetap ada
  /// TARGET nyata utk pintasan F4 (bukan sekadar fokus ke dropdown).
  Future<void> _pilihMetode() async {
    if (_memuatCaraBayar || _caraBayarTersedia.isEmpty) return;
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

  /// Pintasan keyboard F2 Bayar/F3 Tahan/F4 Metode/F5 Member -- padanan
  /// pos-renderer.js `PETA_TOMBOL_KASIR` (lihat kasir_screen.dart utk
  /// F7/F8/F9). Desktop-only; diam di Android.
  KeyEventResult _tanganiTombolKeranjang(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      if (!_memproses) _bayar();
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
        AppTableColumn('Qty', width: 118, align: TextAlign.center),
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
                      if (item.diskon > 0)
                        Text('Diskon ${_formatRupiah.format(item.diskon)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 11.5)),
                    ],
                  ),
                ),
                AppTableCell.text(_formatRupiah.format(item.produk.hargaJual),
                    flex: 2, align: TextAlign.right),
                AppTableCell(
                  width: 118,
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
            _pemilihMember(),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            _labelBagian('Pilih metode pembayaran'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _memuatCaraBayar || _caraBayarTersedia.isEmpty
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
                    else
                      const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
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
  State<_SheetPilihMetodeSplit> createState() =>
      _SheetPilihMetodeSplitState();
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
      _terpilih[i].nominal = (i == n - 1) ? (widget.total - rata * (n - 1)) : rata;
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
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                              onChanged: (v) =>
                                  setState(() => s.nominal = double.tryParse(v) ?? 0),
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
                                locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
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
                    onPressed:
                        _seimbang ? () => Navigator.of(context).pop(_terpilih) : null,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Member'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Cari nama/kode identitas...',
                  prefixIcon: Icon(Icons.search)),
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
                          subtitle: Text(a.kodeIdentitas),
                          trailing: a.wajibPin
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
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
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
    100000,
    150000,
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
        width: 420,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _nominalCepat
                  .map(
                    (nominal) => OutlinedButton(
                      onPressed: () => _pilihNominal(nominal),
                      child: Text(_formatRupiah.format(nominal)),
                    ),
                  )
                  .toList(),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masukkan PIN Member'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            labelText: 'PIN', border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Verifikasi')),
      ],
    );
  }
}
