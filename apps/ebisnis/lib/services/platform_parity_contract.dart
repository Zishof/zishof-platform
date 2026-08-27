enum EbisnisPlatform { desktop, android, jsp, zkoss }

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.responsiveNavigation,
    required this.workQueue,
    required this.barcodeScan,
    required this.qrScan,
    required this.offlineQueue,
    required this.optimisticLock,
    required this.exportPdf,
    required this.exportExcel,
    required this.print,
    required this.contextualHelp,
  });

  final bool responsiveNavigation;
  final bool workQueue;
  final bool barcodeScan;
  final bool qrScan;
  final bool offlineQueue;
  final bool optimisticLock;
  final bool exportPdf;
  final bool exportExcel;
  final bool print;
  final bool contextualHelp;
}

class PlatformActionContract {
  const PlatformActionContract({
    required this.platform,
    required this.menuKey,
    required this.action,
    required this.canonicalRoute,
    required this.visible,
    required this.enabled,
    required this.writeOperation,
    required this.idempotencyRequired,
    required this.optimisticVersionRequired,
    required this.pageSize,
    required this.errorContract,
    required this.denialReason,
  });

  final EbisnisPlatform platform;
  final String menuKey;
  final String action;
  final String canonicalRoute;
  final bool visible;
  final bool enabled;
  final bool writeOperation;
  final bool idempotencyRequired;
  final bool optimisticVersionRequired;
  final int pageSize;
  final String errorContract;
  final String denialReason;
}

class PlatformParityContract {
  static const String errorContract = 'EBISNIS_ERROR_V1';
  static const int defaultPageSize = 10;
  static const int maxPageSize = 100;

  static const Map<EbisnisPlatform, PlatformCapabilities> capabilities = {
    EbisnisPlatform.desktop: PlatformCapabilities(
      responsiveNavigation: true,
      workQueue: true,
      barcodeScan: true,
      qrScan: true,
      offlineQueue: true,
      optimisticLock: true,
      exportPdf: true,
      exportExcel: true,
      print: true,
      contextualHelp: true,
    ),
    EbisnisPlatform.android: PlatformCapabilities(
      responsiveNavigation: true,
      workQueue: true,
      barcodeScan: true,
      qrScan: true,
      offlineQueue: true,
      optimisticLock: true,
      exportPdf: true,
      exportExcel: true,
      print: true,
      contextualHelp: true,
    ),
    EbisnisPlatform.jsp: PlatformCapabilities(
      responsiveNavigation: true,
      workQueue: true,
      barcodeScan: false,
      qrScan: false,
      offlineQueue: false,
      optimisticLock: true,
      exportPdf: true,
      exportExcel: true,
      print: true,
      contextualHelp: true,
    ),
    EbisnisPlatform.zkoss: PlatformCapabilities(
      responsiveNavigation: true,
      workQueue: true,
      barcodeScan: false,
      qrScan: false,
      offlineQueue: false,
      optimisticLock: true,
      exportPdf: true,
      exportExcel: true,
      print: true,
      contextualHelp: true,
    ),
  };

  static PlatformActionContract resolve({
    required EbisnisPlatform platform,
    required String menuKey,
    required String action,
    required String canonicalRoute,
    required bool isAdmin,
    required bool permissionGranted,
    int requestedPageSize = defaultPageSize,
  }) {
    final normalizedAction = action.trim().toLowerCase();
    final allowed = isAdmin || permissionGranted;
    final writeOperation = !const {
      'view',
      'export',
      'view_cost',
      'view_all_location',
    }.contains(normalizedAction);
    final pageSize = requestedPageSize <= 0
        ? defaultPageSize
        : requestedPageSize.clamp(1, maxPageSize).toInt();

    return PlatformActionContract(
      platform: platform,
      menuKey: menuKey.trim().toLowerCase(),
      action: normalizedAction,
      canonicalRoute: canonicalRoute,
      visible: allowed,
      enabled: allowed,
      writeOperation: writeOperation,
      idempotencyRequired: writeOperation,
      optimisticVersionRequired:
          writeOperation && normalizedAction != 'create',
      pageSize: pageSize,
      errorContract: errorContract,
      denialReason: allowed ? '' : 'AKSES_DITOLAK',
    );
  }
}
