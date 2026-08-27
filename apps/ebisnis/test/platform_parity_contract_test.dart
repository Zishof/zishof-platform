import 'package:ebisnis/services/platform_parity_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empat platform memakai kapabilitas inti dan kontrak error yang sama', () {
    expect(PlatformParityContract.capabilities.length, 4);
    for (final platform in EbisnisPlatform.values) {
      final capabilities = PlatformParityContract.capabilities[platform]!;
      expect(capabilities.responsiveNavigation, isTrue);
      expect(capabilities.workQueue, isTrue);
      expect(capabilities.optimisticLock, isTrue);
      expect(capabilities.exportPdf, isTrue);
      expect(capabilities.exportExcel, isTrue);
      expect(capabilities.print, isTrue);
      expect(capabilities.contextualHelp, isTrue);

      final action = PlatformParityContract.resolve(
        platform: platform,
        menuKey: 'kasir_pos',
        action: 'view',
        canonicalRoute: '/ebisnis/kasir',
        isAdmin: true,
        permissionGranted: false,
        requestedPageSize: 0,
      );
      expect(action.canonicalRoute, '/ebisnis/kasir');
      expect(action.errorContract, PlatformParityContract.errorContract);
      expect(action.pageSize, 10);
      expect(action.visible, isTrue);
      expect(action.enabled, isTrue);
      expect(action.idempotencyRequired, isFalse);
    }
  });

  test('kapabilitas perangkat hanya diklaim pada Desktop dan Android', () {
    expect(
      PlatformParityContract.capabilities[EbisnisPlatform.desktop]!
          .offlineQueue,
      isTrue,
    );
    expect(
      PlatformParityContract.capabilities[EbisnisPlatform.android]!.barcodeScan,
      isTrue,
    );
    expect(
      PlatformParityContract.capabilities[EbisnisPlatform.jsp]!.offlineQueue,
      isFalse,
    );
    expect(
      PlatformParityContract.capabilities[EbisnisPlatform.zkoss]!.qrScan,
      isFalse,
    );
  });

  test('izin, paging, idempotensi, dan optimistic version konsisten', () {
    final denied = PlatformParityContract.resolve(
      platform: EbisnisPlatform.desktop,
      menuKey: 'kasir_pos',
      action: 'view',
      canonicalRoute: '/ebisnis/kasir',
      isAdmin: false,
      permissionGranted: false,
      requestedPageSize: 999,
    );
    expect(denied.visible, isFalse);
    expect(denied.enabled, isFalse);
    expect(denied.denialReason, 'AKSES_DITOLAK');
    expect(denied.pageSize, 100);

    final create = PlatformParityContract.resolve(
      platform: EbisnisPlatform.android,
      menuKey: 'kasir_pos',
      action: 'create',
      canonicalRoute: '/ebisnis/kasir',
      isAdmin: false,
      permissionGranted: true,
    );
    expect(create.writeOperation, isTrue);
    expect(create.idempotencyRequired, isTrue);
    expect(create.optimisticVersionRequired, isFalse);

    final edit = PlatformParityContract.resolve(
      platform: EbisnisPlatform.android,
      menuKey: 'pesanan_pelanggan',
      action: 'edit_draft',
      canonicalRoute: '/ebisnis/pesanan',
      isAdmin: true,
      permissionGranted: false,
    );
    expect(edit.idempotencyRequired, isTrue);
    expect(edit.optimisticVersionRequired, isTrue);
  });
}
