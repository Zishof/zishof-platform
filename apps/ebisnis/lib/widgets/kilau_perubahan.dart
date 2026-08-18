import 'package:flutter/material.dart';

/// <h3>Animasi "data baru/berubah dari server" utk pola baca lokal-dulu.</h3>
///
/// [KilauBaris] membungkus satu baris daftar: bila kunci baris termasuk
/// `idBaru` (hijau) atau `idBerubah` (kuning) dari emisi
/// `MasterOffline.daftarCacheDulu`, latarnya berpendar lalu memudar (~2 dtk)
/// -- user langsung tahu baris itu baru tiba/berubah di server (termasuk
/// perubahan dari kasir lain).
///
/// [BannerPerubahanServer] menampilkan strip ringkas "+N baru • N diubah •
/// N dihapus dari server" yang meluncur masuk lalu hilang sendiri -- terutama
/// utk penghapusan (barisnya sudah lenyap sehingga tidak bisa dikilaukan).
class KilauBaris extends StatelessWidget {
  final String kunci;
  final Set<String> idBaru;
  final Set<String> idBerubah;
  final Widget child;

  const KilauBaris({
    super.key,
    required this.kunci,
    required this.idBaru,
    required this.idBerubah,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final baru = idBaru.contains(kunci);
    final berubah = !baru && idBerubah.contains(kunci);
    if (!baru && !berubah) return child;
    final warna = baru ? Colors.green : Colors.amber;
    return TweenAnimationBuilder<double>(
      // Key unik per pendaran supaya baris yang sama bisa berpendar lagi
      // pada pembaruan berikutnya.
      key: ValueKey('kilau:$kunci:${identityHashCode(idBaru)}'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 2200),
      curve: Curves.easeOutCubic,
      builder: (context, nilai, anak) => DecoratedBox(
        decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.22 * nilai),
          borderRadius: BorderRadius.circular(8),
        ),
        child: anak,
      ),
      child: child,
    );
  }
}

class BannerPerubahanServer extends StatefulWidget {
  final int baru;
  final int berubah;
  final int dihapus;

  const BannerPerubahanServer({
    super.key,
    required this.baru,
    required this.berubah,
    required this.dihapus,
  });

  bool get adaPerubahan => baru > 0 || berubah > 0 || dihapus > 0;

  @override
  State<BannerPerubahanServer> createState() => _BannerPerubahanServerState();
}

class _BannerPerubahanServerState extends State<BannerPerubahanServer> {
  bool _tampil = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 5)).then((_) {
      if (mounted) setState(() => _tampil = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.adaPerubahan) return const SizedBox.shrink();
    final potongan = <String>[
      if (widget.baru > 0) '+${widget.baru} baru',
      if (widget.berubah > 0) '${widget.berubah} diubah',
      if (widget.dihapus > 0) '${widget.dihapus} dihapus',
    ];
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: !_tampil
          ? const SizedBox.shrink()
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (_, nilai, anak) => Opacity(
                  opacity: nilai.clamp(0, 1),
                  child: Transform.translate(
                      offset: Offset(0, (1 - nilai) * -8), child: anak)),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.10),
                  border:
                      Border.all(color: Colors.blue.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.cloud_sync, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Pembaruan dari server: ${potongan.join(' • ')}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
    );
  }
}
