import 'dart:convert';

enum StatusPerbandinganTransaksi {
  sama,
  hanyaLokal,
  hanyaServer,
  berbeda,
  duplikat,
}

class BarisPerbandinganTransaksi {
  const BarisPerbandinganTransaksi({
    required this.kode,
    required this.status,
    required this.jumlahLokal,
    required this.jumlahServer,
    required this.totalLokal,
    required this.totalServer,
    required this.asalLokal,
    required this.asalServer,
  });

  final String kode;
  final StatusPerbandinganTransaksi status;
  final int jumlahLokal;
  final int jumlahServer;
  final double totalLokal;
  final double totalServer;
  final String asalLokal;
  final String asalServer;
}

class HasilPerbandinganTransaksi {
  const HasilPerbandinganTransaksi(this.baris);

  final List<BarisPerbandinganTransaksi> baris;

  int jumlah(StatusPerbandinganTransaksi status) =>
      baris.where((item) => item.status == status).length;

  int get jumlahSelisih => baris
      .where((item) => item.status != StatusPerbandinganTransaksi.sama)
      .length;
}

/// Membandingkan arsip lokal dan laporan server tanpa mengubah salah satunya.
/// Kode transaksi adalah identitas idempoten; jumlah kemunculan turut diperiksa
/// agar duplikasi yang sudah telanjur ada tidak tersembunyi oleh Map/set.
HasilPerbandinganTransaksi bandingkanTransaksiLokalDanServer(
    List<Map<String, Object?>> lokal, List<Map<String, dynamic>> server) {
  final lokalByKode = <String, List<Map<String, Object?>>>{};
  final serverByKode = <String, List<Map<String, dynamic>>>{};
  for (final row in lokal) {
    final kode = '${row['kode_unik'] ?? ''}'.trim().toLowerCase();
    if (kode.isNotEmpty) {
      lokalByKode.putIfAbsent(kode, () => <Map<String, Object?>>[]).add(row);
    }
  }
  for (final row in server) {
    final kode = kodeTransaksiServer(row);
    if (kode.isNotEmpty) {
      serverByKode.putIfAbsent(kode, () => <Map<String, dynamic>>[]).add(row);
    }
  }

  final semuaKode = <String>{...lokalByKode.keys, ...serverByKode.keys}.toList()
    ..sort();
  final hasil = <BarisPerbandinganTransaksi>[];
  for (final kode in semuaKode) {
    final daftarLokal = lokalByKode[kode] ?? const <Map<String, Object?>>[];
    final daftarServer = serverByKode[kode] ?? const <Map<String, dynamic>>[];
    final totalLokal =
        daftarLokal.isEmpty ? 0.0 : _totalLokal(daftarLokal.first);
    final totalServer =
        daftarServer.isEmpty ? 0.0 : _angka(daftarServer.first['totalBiaya']);
    StatusPerbandinganTransaksi status;
    if (daftarLokal.length > 1 || daftarServer.length > 1) {
      status = StatusPerbandinganTransaksi.duplikat;
    } else if (daftarLokal.isEmpty) {
      status = StatusPerbandinganTransaksi.hanyaServer;
    } else if (daftarServer.isEmpty) {
      status = StatusPerbandinganTransaksi.hanyaLokal;
    } else if ((totalLokal - totalServer).abs() > 0.01) {
      status = StatusPerbandinganTransaksi.berbeda;
    } else {
      status = StatusPerbandinganTransaksi.sama;
    }
    hasil.add(BarisPerbandinganTransaksi(
      kode: kode,
      status: status,
      jumlahLokal: daftarLokal.length,
      jumlahServer: daftarServer.length,
      totalLokal: totalLokal,
      totalServer: totalServer,
      asalLokal: _asalLokal(daftarLokal),
      asalServer: _asalServer(daftarServer),
    ));
  }
  hasil.sort((a, b) {
    final aSama = a.status == StatusPerbandinganTransaksi.sama ? 1 : 0;
    final bSama = b.status == StatusPerbandinganTransaksi.sama ? 1 : 0;
    if (aSama != bSama) return aSama.compareTo(bSama);
    return a.kode.compareTo(b.kode);
  });
  return HasilPerbandinganTransaksi(hasil);
}

String _gabungAsal(Iterable<String> nilai) {
  final unik = nilai.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  return unik.isEmpty ? '-' : unik.join(' · ');
}

String _asalLokal(List<Map<String, Object?>> daftar) => _gabungAsal(
      daftar.map((row) {
        var username = '${row['akun_kunci'] ?? ''}'.trim();
        var mesin = '${row['id_perangkat'] ?? ''}'.trim();
        try {
          final payload = jsonDecode('${row['payload_json'] ?? '{}'}');
          if (payload is Map) {
            username =
                '${payload['sumber_username'] ?? payload['kasir_user_id'] ?? payload['kasir'] ?? username}'
                    .trim();
            mesin =
                '${payload['sumber_mesin'] ?? payload['nama_mesin'] ?? payload['id_perangkat'] ?? mesin}'
                    .trim();
          }
        } catch (_) {
          // Kolom indeks lokal tetap cukup untuk menampilkan asal saat payload rusak.
        }
        return '${username.isEmpty ? '-' : username} / ${mesin.isEmpty ? '-' : mesin}';
      }),
    );

String _asalServer(List<Map<String, dynamic>> daftar) => _gabungAsal(
      daftar.map((row) {
        final username =
            '${row['kasirUserId'] ?? row['kasir'] ?? row['username'] ?? '-'}'
                .trim();
        final mesin =
            '${row['namaMesin'] ?? row['mesin'] ?? row['idPerangkat'] ?? row['deviceName'] ?? '-'}'
                .trim();
        return '${username.isEmpty ? '-' : username} / ${mesin.isEmpty ? '-' : mesin}';
      }),
    );

String kodeTransaksiServer(Map<String, dynamic> row) {
  for (final kunci in const <String>[
    'kodeUnik',
    'clientTrxId',
    'kodeTransaksi',
    'nomorTransaksi',
    'nomorNota',
    'kode'
  ]) {
    final nilai = '${row[kunci] ?? ''}'.trim();
    if (nilai.isEmpty || nilai == '-') continue;
    if (kunci == 'nomorNota') {
      final cocok = RegExp(r'\(([^()]+)\)\s*$').firstMatch(nilai);
      final kodeLama = cocok?.group(1)?.trim() ?? '';
      if (kodeLama.isNotEmpty) return kodeLama.toLowerCase();
    }
    return nilai.toLowerCase();
  }
  return '';
}

double _totalLokal(Map<String, Object?> row) {
  try {
    final payload = jsonDecode('${row['payload_json'] ?? '{}'}');
    if (payload is Map) {
      return _angka(payload['total'] ?? payload['totalBiaya']);
    }
  } catch (_) {
    // Payload rusak tetap muncul sebagai selisih/total nol untuk diaudit.
  }
  return 0;
}

double _angka(dynamic nilai) {
  if (nilai is num) return nilai.toDouble();
  return double.tryParse('${nilai ?? ''}'.replaceAll(',', '.')) ?? 0;
}
