import '../api_client.dart';

/// Menormalkan URL media milik server POS ke origin server yang benar-benar
/// dipilih di aplikasi. Server Java dapat berada di belakang Apache/reverse
/// proxy sehingga URL absolut yang dibentuk dari request membawa skema/host
/// internal. Path dan query tetap berasal dari respons server, tetapi origin
/// mengikuti [ApiClient.baseUrl].
String normalisasiUrlMedia(String? nilai) {
  final teks = nilai?.trim() ?? '';
  if (teks.isEmpty) return '';
  final basis = Uri.tryParse(ApiClient.baseUrl);
  final media = Uri.tryParse(teks);
  if (basis == null || media == null) return teks;

  final path = media.path;
  final mediaMilikPos = path.contains('/AmbilMediaProduk') ||
      path.contains('/AmbilMediaLayarPelangganSlide') ||
      path.contains('/AmbilMedia') ||
      path.contains('/AmbilLampiran');
  if (mediaMilikPos) {
    final basisSegmen = basis.pathSegments.where((e) => e.isNotEmpty).toList();
    if (basisSegmen.isNotEmpty) basisSegmen.removeLast();
    const endpointMedia = <String>{
      'AmbilMediaProduk',
      'AmbilMediaLayarPelangganSlide',
      'AmbilMedia',
      'AmbilLampiran',
    };
    final mediaSegmen = media.pathSegments.where((e) => e.isNotEmpty).toList();
    final indeksEndpoint =
        mediaSegmen.indexWhere((e) => endpointMedia.contains(e));
    final endpointSegmen =
        indeksEndpoint < 0 ? mediaSegmen : mediaSegmen.sublist(indeksEndpoint);
    return basis.replace(
      // URL internal kadang tidak membawa context aplikasi. Endpoint
      // media selalu dipasang kembali ke context Api_eBisnis aktif.
      pathSegments: [...basisSegmen, ...endpointSegmen],
      query: media.hasQuery ? media.query : null,
      fragment: null,
    ).toString();
  }
  if (!media.hasScheme && !media.hasAuthority) {
    return basis.origin + (teks.startsWith('/') ? teks : '/$teks');
  }
  return teks;
}

/// Fallback deterministik untuk respons server lama yang sudah membawa id
/// foto tetapi belum menyertakan `urlGambar`.
String urlFotoProdukDariId(int fotoId) {
  final basis = Uri.parse(ApiClient.baseUrl);
  final segmen = basis.pathSegments.toList();
  if (segmen.isNotEmpty) segmen.removeLast();
  return basis.replace(
    pathSegments: [...segmen, 'AmbilMediaProduk'],
    queryParameters: {'fotoId': '$fotoId'},
    fragment: null,
  ).toString();
}
