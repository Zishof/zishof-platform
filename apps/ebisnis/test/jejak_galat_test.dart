import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/widgets/jejak_galat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penolakan server datang dua lapis: kalimat untuk pengguna, dan jejak teknis.
/// [JejakGalat] menjaga keduanya tetap berpasangan -- termasuk saat layar
/// berganti menampilkan pesan lain, yang dulu membuat detail lama ikut terbawa.
class _LayarUji extends StatefulWidget {
  const _LayarUji();

  @override
  State<_LayarUji> createState() => _LayarUjiState();
}

class _LayarUjiState extends State<_LayarUji> with JejakGalat {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

ApiException _penolakan() => ApiException(
      'Jenis keanggotaan member ini tidak diizinkan menerima topup lewat kasir.',
      aktivitas: 'topup_saldo',
      kode: 'PERMINTAAN_DITOLAK',
      judul: 'Belum dapat diproses',
      kodeReferensi: 'API-XYZ123',
      solusi: const ['Perbaiki data sesuai penjelasan di atas.'],
      teknis: 'status=91; action=topup_saldo',
    );

void main() {
  testWidgets('detail hanya ikut pesan yang menyertainya', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _LayarUji()));
    final state = tester.state<_LayarUjiState>(find.byType(_LayarUji));

    final pesan = state.terapkanGalat(_penolakan());
    expect(pesan, contains('tidak diizinkan menerima topup'));
    expect(pesan, contains('Perbaiki data sesuai penjelasan'),
        reason: 'satu langkah solusi ikut ditampilkan');

    final detail = state.detailUntuk(pesan);
    expect(detail, isNotNull);
    expect(detail, contains('API-XYZ123'));
    expect(detail, contains('status=91'));

    // Inti perbaikan: pesan validasi lokal tidak boleh mewarisi detail lama.
    expect(state.detailUntuk('Member wajib dipilih.'), isNull);
    expect(state.detailUntuk(null), isNull);
  });

  testWidgets('galat non-API tidak mengarang lapis teknis', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _LayarUji()));
    final state = tester.state<_LayarUjiState>(find.byType(_LayarUji));

    final pesan = state.terapkanGalat(const FormatException('berkas rusak'));
    expect(state.detailUntuk(pesan), isNull);
  });

  testWidgets('snackbar galat menyediakan jalan ke panel teknis',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => snackbarGalat(context, _penolakan()),
            child: const Text('picu'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('picu'));
    await tester.pumpAndSettle();

    expect(find.textContaining('tidak diizinkan menerima topup'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.textContaining('status=91'), findsNothing);

    await tester.tap(find.text('Detail'));
    await tester.pumpAndSettle();

    expect(find.text('Informasi Teknis'), findsOneWidget);
    await tester.tap(find.text('Informasi Teknis'));
    await tester.pumpAndSettle();
    expect(find.textContaining('status=91'), findsOneWidget);
  });
}
