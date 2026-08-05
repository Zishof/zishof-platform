import 'package:flutter/material.dart';

extension SafeStateExtension on State {
  void setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
