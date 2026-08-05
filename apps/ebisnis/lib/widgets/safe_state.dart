import 'package:flutter/material.dart';

extension SafeStateExtension<T extends StatefulWidget> on State<T> {
  /// Guard kecil untuk update UI setelah operasi async selesai.
  ///
  /// Pakai ini hanya untuk mutasi state yang memang mengubah hasil build.
  /// Untuk Timer, StreamSubscription, AnimationController, poller, atau kerja
  /// berulang, tetap batalkan sumber pekerjaannya di dispose agar CPU tidak
  /// terus dipakai setelah widget hilang.
  void setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    // Centralized wrapper: setState adalah protected API State, dan extension
    // bukan subclass. Pemakaian ini sengaja dibatasi di helper ini supaya
    // screen tidak perlu menebar ignore analyzer di banyak file.
    // ignore: invalid_use_of_protected_member
    setState(fn);
  }
}
