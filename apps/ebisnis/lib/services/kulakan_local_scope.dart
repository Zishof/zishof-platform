import '../sesi.dart';

/// Cache riwayat Kulakan wajib dipisahkan per tenant dan toko. Tanpa lingkup
/// ini, faktur yang terakhir dilihat akun/toko A dapat sempat tampil pada akun
/// atau toko B ketika layar membaca snapshot lokal sebelum respons server tiba.
String kunciCacheKulakan({int? tenantId, int? tokoId}) =>
    'master:kulakan_faktur:tenant:${tenantId ?? 0}:toko:${tokoId ?? 0}';

String kunciCacheKulakanAktif() => kunciCacheKulakan(
      tenantId: Sesi.instance.tenantId,
      tokoId: Sesi.instance.idTokoTerpilih,
    );
