import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Label versi dari metadata paket build. Future disimpan bersama agar
/// perpindahan halaman yang membangun ulang AppShell tidak membaca metadata
/// platform berulang kali.
class AppVersionLabel extends StatelessWidget {
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  const AppVersionLabel({
    super.key,
    this.style,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        final nomorBuild = info.buildNumber.trim();
        final label = nomorBuild.isEmpty
            ? 'Versi ${info.version}'
            : 'Versi ${info.version} (build $nomorBuild)';
        return Padding(
          padding: padding,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: style,
          ),
        );
      },
    );
  }
}
