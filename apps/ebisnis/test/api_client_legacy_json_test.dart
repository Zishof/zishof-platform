import 'package:ebisnis/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalisasi respons JSON AIS lama', () {
    test('mempertahankan JSON murni', () {
      const json = '{"status":"success"}';
      expect(ApiClient.normalisasiJsonRespons(json), json);
    });

    test('membuang satu prefix toast script sebelum objek JSON', () {
      const respons = '<script type="text/javascript">'
          "tampilkanToast('peringatan','error');</script>"
          '{"status":"success","peringatan":"sinkronisasi dilewati"}';
      expect(
        ApiClient.normalisasiJsonRespons(respons),
        '{"status":"success","peringatan":"sinkronisasi dilewati"}',
      );
    });

    test('membuang prefix dan suffix script tanpa memotong isi string JSON',
        () {
      const respons = '<script>toast()</script>'
          '{"status":"success","detail":"nilai {uji} dan \\"kutip\\""}'
          '<script>telemetry()</script>';
      expect(
        ApiClient.normalisasiJsonRespons(respons),
        '{"status":"success","detail":"nilai {uji} dan \\"kutip\\""}',
      );
    });

    test('tidak menyamarkan HTML atau script tanpa JSON', () {
      const html = '<html><body>502</body></html>';
      const script = '<script>alert(1)</script><html>rusak</html>';
      expect(ApiClient.normalisasiJsonRespons(html), html);
      expect(ApiClient.normalisasiJsonRespons(script), script);
    });
  });
}
