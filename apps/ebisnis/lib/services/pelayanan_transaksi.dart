import '../api_client.dart';

class PelayananTransaksi {
  PelayananTransaksi._();

  static bool dimintaTerlayani(Map<String, dynamic> payload) {
    return payload['terlayani'] == true ||
        payload['langsungTerlayani'] == true ||
        payload['statusTerlayani'] == true ||
        payload['langsungDilayani'] == true ||
        payload['sudahTerlayani'] == true ||
        payload['dilayani'] == true ||
        payload['statusPelayanan'] == 'TERLAYANI';
  }

  static Object? idDariRespons(Map<String, dynamic> hasil) {
    for (final key in const [
      'idTransaksi',
      'transaksiId',
      'pembelianAnggotaKoperasi',
      'pembelianAnggotaKoperasiId',
      'pembelianId',
      'idPembelian',
      'penjualanId',
      'idPenjualan',
      'orderId',
      'id_transaksi',
      'transaksi_id',
      'pembelian_id',
      'id_pembelian',
      'penjualan_id',
      'id_penjualan',
      'id'
    ]) {
      final value = hasil[key];
      if (value != null) return value;
    }
    final data = hasil['data'];
    if (data is Map<String, dynamic>) {
      for (final key in const [
        'idTransaksi',
        'transaksiId',
        'pembelianAnggotaKoperasi',
        'pembelianAnggotaKoperasiId',
        'pembelianId',
        'idPembelian',
        'penjualanId',
        'idPenjualan',
        'orderId',
        'id_transaksi',
        'transaksi_id',
        'pembelian_id',
        'id_pembelian',
        'penjualan_id',
        'id_penjualan',
        'id'
      ]) {
        final value = data[key];
        if (value != null) return value;
      }
    }
    return _idSpesifikDariNested(hasil);
  }

  static Object? _idSpesifikDariNested(Object? node) {
    if (node is Map) {
      for (final key in const [
        'idTransaksi',
        'transaksiId',
        'pembelianAnggotaKoperasi',
        'pembelianAnggotaKoperasiId',
        'pembelianId',
        'idPembelian',
        'penjualanId',
        'idPenjualan',
        'orderId',
        'id_transaksi',
        'transaksi_id',
        'pembelian_id',
        'id_pembelian',
        'penjualan_id',
        'id_penjualan',
      ]) {
        final value = node[key];
        if (value != null) return value;
      }
      for (final value in node.values) {
        final found = _idSpesifikDariNested(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _idSpesifikDariNested(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Future<bool> tandaiJikaPerlu({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> hasilBayar,
    int percobaanCari = 4,
  }) async {
    if (!dimintaTerlayani(payload)) return false;

    final idTransaksi = idDariRespons(hasilBayar);
    if (idTransaksi != null) {
      if (await _panggilLayani({'id': idTransaksi})) return true;
    }

    final idPayload = _idDariPayload(payload);
    if (idPayload != null) {
      if (await _panggilLayani({'id': idPayload})) return true;
    }

    final kodeUnik =
        '${payload['kodeUnik'] ?? payload['clientTrxId'] ?? payload['kode'] ?? ''}'
            .trim();
    if (kodeUnik.isNotEmpty) {
      final idDariLaporan = await _cariIdTransaksiDariKode(
        kodeUnik,
        percobaan: percobaanCari,
      );
      if (idDariLaporan != null) {
        return _panggilLayani({'id': idDariLaporan});
      }

      // Beberapa server lama pernah menerima nomor transaksi langsung. Server
      // eCampus saat ini tetap mewajibkan `id`, jadi ini hanya fallback ringan.
      if (await _panggilLayani({
        'kodeUnik': kodeUnik,
        'clientTrxId': kodeUnik,
        'kode': kodeUnik,
        'nomorNota': kodeUnik,
      })) {
        return true;
      }
    }

    return false;
  }

  static Object? _idDariPayload(Map<String, dynamic> payload) {
    for (final key in const [
      'idTransaksi',
      'transaksiId',
      'pembelianAnggotaKoperasi',
      'draftPembelianAnggotaKoperasi',
      'pembelianAnggotaKoperasiId',
      'pembelianId',
      'idPembelian',
      'penjualanId',
      'idPenjualan',
      'orderId',
    ]) {
      final value = payload[key];
      if (value != null) return value;
    }
    return null;
  }

  static Future<bool> _panggilLayani(Map<String, dynamic> body) async {
    try {
      await ApiClient.instance.aksi('layani_transaksi', body);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Object?> _cariIdTransaksiDariKode(
    String kodeUnik, {
    required int percobaan,
  }) async {
    for (var attempt = 0; attempt < percobaan; attempt++) {
      try {
        for (var page = 1; page <= 5; page++) {
          final hasil = await ApiClient.instance.aksi('laporan_order_list', {
            'page': page,
            'pageSize': 100,
          });
          final data =
              ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          for (final row in data) {
            final kandidat = [
              row['nomorNota'],
              row['nomorTransaksi'],
              row['noTransaksi'],
              row['kode'],
              row['kodeTransaksi'],
              row['kodeUnik'],
              row['clientTrxId'],
            ].map((e) => e?.toString()).whereType<String>();
            if (kandidat.any((v) =>
                v == kodeUnik ||
                v.contains(kodeUnik) ||
                kodeUnik.contains(v))) {
              return row['idTransaksi'] ??
                  row['transaksiId'] ??
                  row['pembelianAnggotaKoperasiId'] ??
                  row['pembelianId'] ??
                  row['orderId'] ??
                  row['id'];
            }
          }
          if (data.length < 100) break;
        }
      } catch (_) {
        return null;
      }
      if (attempt < percobaan - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    return null;
  }
}
