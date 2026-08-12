import 'dart:io';

import 'package:core_update/core_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferensi dan pemasang pembaruan komponen Windows.
///
/// Paket ZIP berisi isi folder Release Flutter (EXE, DLL, data). Helper
/// PowerShell berjalan di luar proses aplikasi, menunggu POS berhenti, lalu
/// menyalin komponen baru dan membuka aplikasi kembali. Data pengguna tetap
/// berada di AppData dan tidak ikut ditimpa.
class PengaturanUpdate {
  PengaturanUpdate._();
  static final instance = PengaturanUpdate._();

  static const _kOtomatis = 'update_komponen_otomatis';
  static const _kPercobaanVersi = 'update_percobaan_versi';
  static const _kPercobaanWaktu = 'update_percobaan_waktu';

  bool otomatis = true;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    otomatis = sp.getBool(_kOtomatis) ?? true;
  }

  Future<void> simpanOtomatis(bool nilai) async {
    otomatis = nilai;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kOtomatis, nilai);
  }

  Future<bool> cobaPasangOtomatis(InfoUpdate info) async {
    await muat();
    if (!Platform.isWindows || !otomatis) return false;
    final url = info.urlPaketWindows;
    final sha256 = info.sha256PaketWindows;
    if (url == null || sha256 == null || sha256.length != 64) return false;

    final sp = await SharedPreferences.getInstance();
    final terakhirVersi = sp.getString(_kPercobaanVersi);
    final terakhirMs = sp.getInt(_kPercobaanWaktu) ?? 0;
    final baruSajaDicoba = terakhirVersi == info.versi &&
        DateTime.now().millisecondsSinceEpoch - terakhirMs <
            const Duration(hours: 6).inMilliseconds;
    if (baruSajaDicoba) return false;

    await sp.setString(_kPercobaanVersi, info.versi);
    await sp.setInt(_kPercobaanWaktu, DateTime.now().millisecondsSinceEpoch);
    final paket = await WindowsUpdatePackage.unduhDanVerifikasi(
      url: url,
      sha256Diharapkan: sha256,
      versi: info.versi,
    );
    await _jalankanHelper(paket, info.versi);
    return true;
  }

  Future<void> _jalankanHelper(File paket, String versi) async {
    final exe = File(Platform.resolvedExecutable);
    final direktoriInstalasi = exe.parent.path;
    final temp = Directory.systemTemp.path;
    final worker = File('$temp${Platform.pathSeparator}pos-update-worker.ps1');
    final launcher =
        File('$temp${Platform.pathSeparator}pos-update-launch.ps1');

    await worker.writeAsString(r'''
param(
  [Parameter(Mandatory=$true)][string]$Package,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][string]$ExePath,
  [Parameter(Mandatory=$true)][int]$ParentPid
)
$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:TEMP ('pos-update-stage-' + [guid]::NewGuid())
$backup = Join-Path $env:TEMP ('pos-update-backup-' + [guid]::NewGuid())
try {
  Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  Expand-Archive -LiteralPath $Package -DestinationPath $stage -Force
  Copy-Item -Path (Join-Path $InstallDir '*') -Destination $backup -Recurse -Force
  Copy-Item -Path (Join-Path $stage '*') -Destination $InstallDir -Recurse -Force
  Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  if (Test-Path -LiteralPath $backup) {
    Copy-Item -Path (Join-Path $backup '*') -Destination $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir -ErrorAction SilentlyContinue
  throw
} finally {
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Package -Force -ErrorAction SilentlyContinue
}
''');

    final workerArgs = [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      worker.path,
      '-Package',
      paket.path,
      '-InstallDir',
      direktoriInstalasi,
      '-ExePath',
      exe.path,
      '-ParentPid',
      '$pid',
    ];

    var perluElevasi = false;
    final tes = File(
        '$direktoriInstalasi${Platform.pathSeparator}.pos-update-write-test');
    try {
      await tes.writeAsString(versi);
      await tes.delete();
    } catch (_) {
      perluElevasi = true;
    }

    if (perluElevasi) {
      String kutipArgumen(String nilai) => '"${nilai.replaceAll('"', r'\"')}"';
      String literalPowerShell(String nilai) =>
          "'${nilai.replaceAll("'", "''")}'";
      final barisArgumen = workerArgs.map(kutipArgumen).join(' ');
      await launcher.writeAsString(
          "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList ${literalPowerShell(barisArgumen)}");
      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', launcher.path],
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start('powershell.exe', workerArgs,
          mode: ProcessStartMode.detached);
    }
    exit(0);
  }
}
