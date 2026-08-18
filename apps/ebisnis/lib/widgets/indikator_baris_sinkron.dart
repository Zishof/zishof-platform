import 'package:flutter/material.dart';

import '../services/master_offline.dart';
import '../theme/app_colors.dart';

/// Kunci sinkron sebuah baris tabel master: baris hasil create offline
/// membawa `_kunci` dari snapshot cache (lihat MasterOffline.terapkanLokal);
/// baris normal memakai `'<entitas>:<id>'` — sama persis dengan [kunci] yang
/// dipakai layar saat memanggil MasterOffline.simpanAtauAntre.
String kunciBarisMaster(String entitas, Map row) {
  final k = row['_kunci'];
  if (k is String && k.isNotEmpty) return k;
  return '$entitas:${row['id']}';
}

/// <h3>Indikator sinkron PER-BARIS pada tabel data master.</h3>
///
/// Dipasang di sel pertama tiap baris (biasanya lewat helper layar). Tiga
/// wujud, mengikuti [MasterOffline.statusBaris]:
/// - **menunggu**: awan-offline kecil berdenyut — baris tersimpan lokal dan
///   sedang menunggu giliran dikirim;
/// - **baru tersinkron**: centang hijau muncul membesar (elastis) begitu
///   baris INI terbukti sampai ke server (kirim langsung maupun flush
///   antrean), lalu memudar setelah beberapa detik;
/// - **gagal**: ikon galat merah — server menolak baris ini, buka lagi
///   datanya dan simpan ulang.
/// Di luar itu widget tidak menggambar apa pun (lebar 0).
class IndikatorBarisSinkron extends StatelessWidget {
  final String kunci;
  const IndikatorBarisSinkron({super.key, required this.kunci});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MasterOffline.revisiBaris,
      builder: (context, _, __) {
        final st = MasterOffline.statusBaris(kunci);
        final Widget isi;
        switch (st) {
          case null:
            isi = const SizedBox.shrink(key: ValueKey('baris-diam'));
            break;
          case StatusBarisSinkron.menunggu:
            isi = const Tooltip(
              key: ValueKey('baris-menunggu'),
              message: 'Tersimpan lokal — menunggu sinkron ke server',
              child: Padding(
                padding: EdgeInsets.only(right: 6),
                child: _DenyutKecil(
                  child: Icon(Icons.cloud_off,
                      size: 16, color: AppColors.warning),
                ),
              ),
            );
            break;
          case StatusBarisSinkron.baruTersinkron:
            isi = Tooltip(
              key: const ValueKey('baris-sukses'),
              message: 'Baris ini berhasil terkirim ke server',
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (_, nilai, anak) =>
                      Transform.scale(scale: nilai, child: anak),
                  child: const Icon(Icons.check_circle,
                      size: 16, color: AppColors.success),
                ),
              ),
            );
            break;
          case StatusBarisSinkron.gagal:
            isi = const Tooltip(
              key: ValueKey('baris-gagal'),
              message: 'DITOLAK server — buka datanya lalu simpan ulang',
              child: Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.error_outline,
                    size: 16, color: AppColors.danger),
              ),
            );
            break;
        }
        return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250), child: isi);
      },
    );
  }
}

/// Sel teks tabel dengan indikator sinkron baris di depannya — pengganti
/// langsung `AppTableCell.text` utk kolom pertama layar master.
class SelTeksDenganSinkron extends StatelessWidget {
  final String kunci;
  final String teks;
  final TextStyle? style;
  const SelTeksDenganSinkron(
      {super.key, required this.kunci, required this.teks, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IndikatorBarisSinkron(kunci: kunci),
      Expanded(
        child: Text(teks,
            style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

/// Denyut lembut versi kecil (skala 1.0 -> 1.2) utk ikon 16px di baris tabel.
class _DenyutKecil extends StatefulWidget {
  final Widget child;
  const _DenyutKecil({required this.child});

  @override
  State<_DenyutKecil> createState() => _DenyutKecilState();
}

class _DenyutKecilState extends State<_DenyutKecil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.2)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child);
}
