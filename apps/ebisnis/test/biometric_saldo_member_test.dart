import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/biometric_capture_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'kesiapan biometrik wajib mencakup perangkat, enkripsi, matcher, dan izin',
      () {
    const device = {'fingerprint': true, 'face': true};
    final ready = PosBiometricReadiness(
      device: device,
      server: const {
        'boleh_enroll_pengguna_lain': true,
        'server_encryption_ready': true,
        'fingerprint_matcher_ready': true,
        'face_matcher_ready': true,
      },
    );
    expect(ready.enrollmentReady('FINGERPRINT'), isTrue);
    expect(ready.verificationReady('FACE'), isTrue);

    final noMatcher = PosBiometricReadiness(
      device: device,
      server: const {
        'boleh_enroll_pengguna_lain': true,
        'server_encryption_ready': true,
        'fingerprint_matcher_ready': false,
        'face_matcher_ready': false,
      },
    );
    expect(noMatcher.enrollmentReady('FACE'), isTrue);
    expect(noMatcher.verificationReady('FACE'), isFalse);
    expect(noMatcher.reason('FACE', enrollment: false), contains('Matcher'));
    final diagnostics = noMatcher.diagnostics('FINGERPRINT');
    expect(diagnostics, hasLength(4));
    expect(diagnostics.where((item) => !item.ready), hasLength(1));
    expect(diagnostics.last.label, contains('Matcher fingerprint'));
  });

  test('diagnostik biometrik menjelaskan remedi tanpa membuka template', () {
    final readiness = PosBiometricReadiness(
      device: const {
        'fingerprint': false,
        'face': false,
        'reason': 'Adapter vendor belum aktif.',
      },
      server: const {
        'boleh_enroll_pengguna_lain': false,
        'server_encryption_ready': false,
        'fingerprint_matcher_ready': false,
        'face_matcher_ready': false,
      },
    );
    final rows = readiness.diagnostics('FACE');
    expect(rows, hasLength(4));
    expect(rows.every((item) => !item.ready), isTrue);
    expect(rows[1].detail, contains('AIS_BIOMETRIC_MASTER_KEY'));
    expect(rows[2].detail, contains('Adapter vendor'));
    expect(rows.last.detail, contains('provider matcher'));
    expect(rows.map((item) => item.detail).join(), isNot(contains('base64')));
  });

  test('aturan biometrik jenis member dipetakan dari server dan cache', () {
    final server = Anggota.fromJson({
      'id': 7,
      'nama': 'Santri Contoh',
      'wajibPin': false,
      'wajibBiometricWajah': true,
      'wajibBiometricFingerprint': true,
    });
    expect(server.wajibBiometricWajah, isTrue);
    expect(server.wajibBiometricFingerprint, isTrue);

    final cache = Anggota.fromCache({
      'id': 7,
      'nama': 'Santri Contoh',
      'wajib_biometric_wajah': 1,
      'wajib_biometric_fingerprint': 1,
    });
    expect(cache.wajibBiometricWajah, isTrue);
    expect(cache.wajibBiometricFingerprint, isTrue);
  });

  test('adapter SecuGen hanya mempercayai endpoint HTTPS loopback', () {
    expect(
      SecuGenWebApiCapture.trustedLoopback(
        Uri.parse('https://127.0.0.1:8000/SGIFPCapture'),
      ),
      isTrue,
    );
    expect(
      SecuGenWebApiCapture.trustedLoopback(
        Uri.parse('https://localhost:8000/SGIFPCapture'),
      ),
      isTrue,
    );
    expect(
      SecuGenWebApiCapture.trustedLoopback(
        Uri.parse('https://scanner.example:8000/SGIFPCapture'),
      ),
      isFalse,
    );
  });

  test('respons SecuGen menghasilkan template ISO dan kualitas', () {
    final sample = SecuGenWebApiCapture.parseCaptureResponse(
      '{"ErrorCode":0,"TemplateBase64":"AQIDBA==","ImageQuality":78}',
    );
    expect(sample.modality, 'FINGERPRINT');
    expect(sample.templateFormat, 'ISO_19794_2');
    expect(sample.provider, 'SECUGEN_WEBAPI');
    expect(sample.qualityScore, 78);
  });

  test('respons error SecuGen tidak boleh menjadi template', () {
    expect(
      () => SecuGenWebApiCapture.parseCaptureResponse(
        '{"ErrorCode":54,"TemplateBase64":""}',
      ),
      throwsA(isA<PosBiometricUnavailable>()),
    );
  });

  test('checkout mengikat bukti biometrik ke kode transaksi dan ACK server',
      () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    expect(source, contains("'reference_type': 'POS_PURCHASE'"));
    expect(source, contains("'reference_id': kodeUnik"));
    expect(source, contains("'biometric_face_event_id'"));
    expect(source, contains("'biometric_fingerprint_event_id'"));
    expect(source, contains("'pin_verification_event_id'"));
    expect(source, contains("aksi('biometrik_kemampuan')"));
    expect(source, contains("verificationReady('FACE')"));
    expect(source, contains(r"'clientMutationId': 'pos-pin-$kodeUnik'"));
    expect(source, contains("await ApiClient.instance.aksi('bayar', payload)"));
    expect(source, contains('Pembayaran sudah diterima server'));
  });

  test('verifikasi pilihan tidak boleh membuang id yang baru saja didapat', () {
    // Uji di atas sudah menegaskan ketiga nama kunci MUNCUL di berkas, dan
    // tetap hijau selama cacat ini hidup: nama-nama itu ada di jalur biometrik
    // WAJIB, sementara jalur PILIHAN membuang idnya. Menegaskan sebuah nama
    // muncul tidak sama dengan menegaskan nilainya terkirim.
    //
    // Cacatnya: dialog "Verifikasi member" hanya muncul ketika PIN wajib untuk
    // cara bayar terpilih. Memilih sidik jari/wajah menjalankan verifikasi,
    // lalu mengembalikan map KOSONG. Server memeriksa pin_verification_event_id
    // terpisah (BiometricApi.validPosVerification -> false bila eventId null),
    // sehingga pembayaran ditolak dengan "Verifikasi PIN wajib dilakukan
    // kembali" kepada orang yang baru saja berhasil memindai sidik jarinya --
    // dan dialognya menawarkan sidik jari lagi, jadi jalur itu buntu.
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    expect(
      source.contains('return id == null ? null : <String, int>{};'),
      isFalse,
      reason: 'id verifikasi biometrik dibuang di jalur pilihan',
    );
    expect(source, contains("? 'biometric_face_event_id'"));
    expect(source, contains(": 'biometric_fingerprint_event_id'"));
    expect(source, contains("bukti['pin_verification_event_id'] = pinEventId;"));
  });

  test('PIN mengikuti metode pembayaran dan dialog hanya menerima angka', () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    expect(source, contains('_pinWajibUntukMetodeTerpilih'));
    expect(source, contains('FilteringTextInputFormatter.digitsOnly'));
    expect(source, contains('GridView.count('));
    expect(source, contains('PIN numerik'));
    expect(source, contains('if (!_bisaBayar) return;'));
    expect(source, contains('if (_bisaBayar) _bayar();'));
  });

  test('aturan PIN per cara bayar mendukung satu metode dan split', () {
    final tunai = CaraBayar(
      id: 1,
      nama: 'Tunai',
      manual: true,
    );
    final voucherSantri = CaraBayar(
      id: 2,
      nama: 'Voucher Santri',
      manual: false,
      wajibPin: true,
    );
    expect(pembayaranMemerlukanPin([tunai]), isFalse);
    expect(pembayaranMemerlukanPin([voucherSantri]), isTrue);
    expect(pembayaranMemerlukanPin([tunai, voucherSantri]), isTrue);
    expect(
        CaraBayar.fromJson({
          'id': 2,
          'nama': 'Voucher Santri',
          'manual': false,
          'wajibPin': true,
        }).wajibPin,
        isTrue);
  });

  test('form Jenis dan Tipe menyimpan scope cara bayar wajib PIN', () {
    final tipe =
        File('lib/screens/anggota/tab_tipe_member.dart').readAsStringSync();
    final jenis =
        File('lib/screens/anggota/tab_jenis_member.dart').readAsStringSync();
    expect(tipe, contains('daftarCaraPembayaranWajibPin'));
    expect(jenis, contains('daftar_cara_pembayaran_wajib_pin'));
    expect(tipe, contains('kosong = semua cara bayar'));
    expect(jenis, contains('kosong = semua cara bayar'));
  });
}
