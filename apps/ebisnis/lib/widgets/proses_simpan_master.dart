import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/master_offline.dart';

/// <h3>Alur "Simpan" ber-indikator animasi utk SEMUA form CRUD master
/// (Desktop & Android).</h3>
///
/// Urutan yang dijamin (permintaan bisnis):
/// 1. Data ditulis LOKAL dulu (antrean outbox + snapshot daftar) -- tahap
///    "Tersimpan di perangkat" dgn centang pop.
/// 2. Dicoba kirim ke server dgn animasi mengirim; batas tunggu
///    [batasTungguKirim] -- lama/offline TIDAK menahan user.
/// 3. Hasil:
///    - terkirim -> centang hijau elastis "Terkirim ke server", dialog
///      menutup, form MENUTUP (return `{status:'success'}`);
///    - offline/lambat -> tahap "Akan dikirim otomatis nanti" sesaat, dialog
///      menutup, form TETAP MENUTUP (return `{status:'success', offline:true}`)
///      -- retry lanjut di latar tiap [MasterOffline.intervalFlush] dan
///      berhenti sendiri begitu terkirim;
///    - DITOLAK server (validasi bisnis) -> baris antrean dihapus, dialog
///      menutup, [ApiException] dilempar ulang supaya form menampilkan pesan
///      dan TIDAK menutup.
Future<Map<String, dynamic>> prosesSimpanMaster(
  BuildContext context, {
  required String aksi,
  required Map<String, dynamic> body,
  String? kunci,
  String? cacheKey,
  Map<String, dynamic>? rowLokal,
  bool hapusLokal = false,
  Duration batasTungguKirim = const Duration(seconds: 6),
  /// Id SEMENTARA (negatif) untuk baris BARU yang dibuat offline. Diteruskan ke
  /// antrean supaya pasangannya dengan id server tercatat begitu terkirim, dan
  /// baris lain yang menunjuknya ikut ditukar saat sinkron.
  int? idLokal,
  String entitas = 'master',
}) async {
  final hasil = await showDialog<_HasilProses>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogProsesSimpan(
      aksi: aksi,
      body: body,
      kunci: kunci,
      cacheKey: cacheKey,
      rowLokal: rowLokal,
      hapusLokal: hapusLokal,
      batasTungguKirim: batasTungguKirim,
      idLokal: idLokal,
      entitas: entitas,
    ),
  );
  if (hasil == null) {
    // Tidak seharusnya terjadi (barrier tak bisa ditutup) -- fail-safe.
    return {'status': 'success', 'offline': true};
  }
  if (hasil.error != null) throw hasil.error!;
  return hasil.respons ??
      {'status': 'success', if (hasil.offline) 'offline': true};
}

class _HasilProses {
  final Map<String, dynamic>? respons;
  final bool offline;
  final Object? error;
  const _HasilProses({this.respons, this.offline = false, this.error});
}

enum _Tahap { menyimpanLokal, mengirim, terkirim, antreOffline }

class _DialogProsesSimpan extends StatefulWidget {
  final String aksi;
  final Map<String, dynamic> body;
  final String? kunci;
  final int? idLokal;
  final String entitas;
  final String? cacheKey;
  final Map<String, dynamic>? rowLokal;
  final bool hapusLokal;
  final Duration batasTungguKirim;

  const _DialogProsesSimpan({
    required this.aksi,
    required this.body,
    required this.kunci,
    required this.idLokal,
    required this.entitas,
    required this.cacheKey,
    required this.rowLokal,
    required this.hapusLokal,
    required this.batasTungguKirim,
  });

  @override
  State<_DialogProsesSimpan> createState() => _DialogProsesSimpanState();
}

class _DialogProsesSimpanState extends State<_DialogProsesSimpan> {
  _Tahap _tahap = _Tahap.menyimpanLokal;
  bool _lokalSelesai = false;

  @override
  void initState() {
    super.initState();
    _jalankan();
  }

  Future<void> _jalankan() async {
    try {
      // Tahap 1: SELALU tulis lokal dulu -- inilah jaminan offline-first.
      final idAntrean = await MasterOffline.antreLokal(
        widget.aksi,
        widget.body,
        kunci: widget.kunci,
        cacheKey: widget.cacheKey,
        rowLokal: widget.rowLokal,
        hapusLokal: widget.hapusLokal,
        idLokal: widget.idLokal,
        entitas: widget.entitas,
      );
      if (!mounted) return;
      setState(() => _lokalSelesai = true);
      // Beri mata waktu melihat centang "tersimpan lokal" sebelum lanjut.
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() => _tahap = _Tahap.mengirim);

      // Tahap 2: coba kirim baris itu, dibatasi waktu -- offline/lambat
      // tidak boleh menyandera jendela (langsung tutup, retry di latar).
      Map<String, dynamic>? respons;
      var offline = false;
      try {
        respons = await MasterOffline.kirimSatuAntrean(
          idAntrean,
          widget.aksi,
          widget.body,
          kunci: widget.kunci,
        ).timeout(widget.batasTungguKirim);
      } on TimeoutException {
        offline = true; // masih tercatat PENDING -- flush latar melanjutkan.
      } on ApiException catch (e) {
        if (!e.offline) {
          // Penolakan bisnis: baris antrean sudah dihapus service; form harus
          // tetap terbuka menampilkan pesan -- teruskan error ke pemanggil.
          if (mounted) {
            Navigator.of(context).pop(_HasilProses(error: e));
          }
          return;
        }
        offline = true;
      }
      if (!mounted) return;
      setState(
          () => _tahap = offline ? _Tahap.antreOffline : _Tahap.terkirim);
      await Future<void>.delayed(offline
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 850));
      if (!mounted) return;
      Navigator.of(context)
          .pop(_HasilProses(respons: respons, offline: offline));
    } catch (e) {
      // Kegagalan tak terduga (mis. DB lokal) -- jangan menelan error.
      if (mounted) Navigator.of(context).pop(_HasilProses(error: e));
    }
  }

  Widget _baris(
      {required bool aktif,
      required bool selesai,
      required IconData ikon,
      required String teks,
      Color? warnaSelesai}) {
    final warna = selesai
        ? (warnaSelesai ?? Colors.green)
        : aktif
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).disabledColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: selesai
                ? TweenAnimationBuilder<double>(
                    key: ValueKey('selesai-$teks'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.elasticOut,
                    builder: (_, nilai, anak) =>
                        Transform.scale(scale: nilai, child: anak),
                    child: Icon(Icons.check_circle, color: warna, size: 22),
                  )
                : aktif
                    ? SizedBox(
                        key: ValueKey('aktif-$teks'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: warna),
                      )
                    : Icon(ikon, key: ValueKey('diam-$teks'),
                        color: warna, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(teks,
                style: TextStyle(
                    fontSize: 13.5,
                    color: warna,
                    fontWeight:
                        aktif || selesai ? FontWeight.w600 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mengirimAktif = _tahap == _Tahap.mengirim;
    final terkirim = _tahap == _Tahap.terkirim;
    final antre = _tahap == _Tahap.antreOffline;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _baris(
                aktif: !_lokalSelesai,
                selesai: _lokalSelesai,
                ikon: Icons.save_outlined,
                teks: 'Tersimpan di perangkat',
              ),
              _baris(
                aktif: mengirimAktif,
                selesai: terkirim,
                ikon: antre ? Icons.cloud_off : Icons.cloud_upload_outlined,
                teks: terkirim
                    ? 'Terkirim ke server'
                    : antre
                        ? 'Offline — akan dikirim otomatis nanti'
                        : 'Mengirim ke server...',
                warnaSelesai: Colors.green,
              ),
              if (antre)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'Pengiriman diulang di latar dan berhenti sendiri '
                      'begitu berhasil.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).hintColor)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
