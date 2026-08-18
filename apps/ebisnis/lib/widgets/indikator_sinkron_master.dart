import 'package:flutter/material.dart';

import '../services/master_offline.dart';

/// <h3>Indikator animasi sinkronisasi data master (offline-first).</h3>
///
/// Dipasang di `AppBar.actions` setiap layar CRUD master. Empat wujud:
/// - **diam**: tidak menggambar apa pun (tanpa antrean, tanpa gagal);
/// - **ada antrean**: ikon cloud_off berdenyut + badge jumlah menunggu --
///   data tersimpan LOKAL dan akan dikirim otomatis;
/// - **mengirim**: ikon sync berputar terus;
/// - **baru tersinkron**: centang hijau muncul membesar (elastis) + label
///   "Tersinkron" selama +-3 detik, lalu kembali diam -- inilah "indikator
///   animasi saat data berhasil terkirim ke server" yang diminta.
///
/// Sumber kebenarannya [MasterOffline.status]; widget ini juga yang
/// menghidupkan timer flush latar ([MasterOffline.pastikanTimer]) sehingga
/// layar mana pun yang memasangnya otomatis ikut menyalakan sinkron latar.
class IndikatorSinkronMaster extends StatefulWidget {
  const IndikatorSinkronMaster({super.key});

  @override
  State<IndikatorSinkronMaster> createState() => _IndikatorSinkronMasterState();
}

class _IndikatorSinkronMasterState extends State<IndikatorSinkronMaster>
    with SingleTickerProviderStateMixin {
  late final AnimationController _putar;

  @override
  void initState() {
    super.initState();
    _putar = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    MasterOffline.pastikanTimer();
  }

  @override
  void dispose() {
    _putar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StatusSinkronMaster>(
      valueListenable: MasterOffline.status,
      builder: (context, st, _) {
        if (st.fase == FaseSinkron.mengirim) {
          _putar.repeat();
        } else {
          _putar.stop();
        }
        final Widget isi;
        switch (st.fase) {
          case FaseSinkron.diam:
            isi = const SizedBox.shrink(key: ValueKey('diam'));
            break;
          case FaseSinkron.adaAntrean:
            isi = Tooltip(
              key: const ValueKey('antre'),
              message: '${st.antrean} perubahan tersimpan lokal — '
                  'akan dikirim otomatis saat online',
              child: InkWell(
                onTap: () => MasterOffline.flush(),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Badge(
                    label: Text('${st.antrean}'),
                    child: _Berdenyut(
                        child: Icon(Icons.cloud_off,
                            color: Theme.of(context).colorScheme.tertiary)),
                  ),
                ),
              ),
            );
            break;
          case FaseSinkron.mengirim:
            isi = Tooltip(
              key: const ValueKey('kirim'),
              message: 'Mengirim perubahan ke server...',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: RotationTransition(
                    turns: _putar, child: const Icon(Icons.sync)),
              ),
            );
            break;
          case FaseSinkron.baruTersinkron:
            isi = Tooltip(
              key: const ValueKey('sukses'),
              message: 'Semua perubahan tersinkron ke server',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (_, nilai, anak) =>
                        Transform.scale(scale: nilai, child: anak),
                    child: const Icon(Icons.check_circle, color: Colors.green),
                  ),
                  const SizedBox(width: 4),
                  const Text('Tersinkron',
                      style:
                          TextStyle(fontSize: 12, color: Colors.green)),
                ]),
              ),
            );
            break;
          case FaseSinkron.adaGagal:
            isi = Tooltip(
              key: const ValueKey('gagal'),
              message: 'Ada perubahan yang DITOLAK server — '
                  'buka kembali datanya lalu simpan ulang',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
              ),
            );
            break;
        }
        return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300), child: isi);
      },
    );
  }
}

/// Denyut lembut (skala 1.0 -> 1.15 bolak-balik) tanpa controller tambahan.
class _Berdenyut extends StatefulWidget {
  final Widget child;
  const _Berdenyut({required this.child});

  @override
  State<_Berdenyut> createState() => _BerdenyutState();
}

class _BerdenyutState extends State<_Berdenyut>
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
      scale: Tween<double>(begin: 1.0, end: 1.15)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child);
}
