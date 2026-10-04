import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/services/produksi_status.dart';

void main() {
  const hak = {
    'setujui': true,
    'ubah': true,
    'selesai': true,
    'balikkan': true,
    'batalkan': true
  };
  test('WO follows release, start, complete; never APPROVED or POSTED', () {
    for (final pair in {
      'DRAFT': 'RELEASED',
      'RELEASED': 'IN_PROGRESS',
      'IN_PROGRESS': 'COMPLETED'
    }.entries) {
      final actions = aksiStatusProduksi('work_order', pair.key, hak);
      expect(actions.first.status, pair.value);
      expect(actions.map((a) => a.status), isNot(contains('APPROVED')));
      expect(actions.map((a) => a.status), isNot(contains('POSTED')));
    }
    expect(aksiStatusProduksi('work_order', 'COMPLETED', hak), isEmpty);
  });
  test('BOM activates and retires; stock document posts then reverses', () {
    expect(aksiStatusProduksi('bill_of_material', 'DRAFT', hak).first.status,
        'ACTIVE');
    expect(aksiStatusProduksi('bill_of_material', 'ACTIVE', hak).single.status,
        'RETIRED');
    for (final type in [
      'material_issue',
      'material_return',
      'production_output',
      'production_waste',
      'production_cost',
      'production_unbuild'
    ]) {
      expect(aksiStatusProduksi(type, 'DRAFT', hak).first.status, 'POSTED');
      expect(aksiStatusProduksi(type, 'POSTED', hak).single.status, 'REVERSED');
    }
  });
  test('permissions fail closed and QC retains its separate disposition', () {
    expect(aksiStatusProduksi('work_order', 'DRAFT', {}), isEmpty);
    expect(aksiStatusProduksi('work_order', 'IN_PROGRESS', {'setujui': true}),
        isEmpty);
    expect(aksiStatusProduksi('quality_alert', 'DRAFT', hak), isEmpty);
    expect(aksiStatusProduksi('material_issue', 'REVERSED', hak), isEmpty);
  });
  test('status request uses server fields and preserves document identity', () {
    expect(payloadStatusProduksi('work_order', 20, 'RELEASED'), {
      'jenis': 'work_order',
      'id': 20,
      'statusDokumen': 'RELEASED',
      'catatanStatus': 'Perubahan status dari aplikasi eBisnis',
    });
  });
}
