import 'platform_parity_contract.dart';

/// Kontrak fitur ABChicken yang harus tersedia dari source Flutter yang sama.
///
/// Kontrak ini tidak memberi izin baru. Menu tetap mengikuti hak akses server.
/// Perbedaan perangkat hanya boleh terjadi pada cara memakai perangkat keras;
/// alur bisnis, aksi API, dan hasil datanya harus sama.
class AbChickenFeatureSpec {
  const AbChickenFeatureSpec({
    required this.id,
    required this.department,
    required this.menuPath,
    required this.actions,
    this.desktopMode = 'native',
    this.androidMode = 'native',
  });

  final String id;
  final String department;
  final String menuPath;
  final Set<String> actions;
  final String desktopMode;
  final String androidMode;

  bool supports(EbisnisPlatform platform) =>
      platform == EbisnisPlatform.desktop ||
      platform == EbisnisPlatform.android;
}

class AbChickenFeatureContract {
  static const Set<EbisnisPlatform> officialPlatforms = {
    EbisnisPlatform.desktop,
    EbisnisPlatform.android,
  };

  static const List<AbChickenFeatureSpec> features = [
    AbChickenFeatureSpec(
        id: 'DKB-01',
        department: 'Operational',
        menuPath: 'Operasional > Kasir/POS',
        actions: {'order', 'billing', 'print_customer', 'print_kitchen'}),
    AbChickenFeatureSpec(
        id: 'DKB-02',
        department: 'Operational',
        menuPath: 'Operasional > Kasir/POS > Keranjang',
        actions: {'queue_number', 'order_note'}),
    AbChickenFeatureSpec(
        id: 'DKB-03',
        department: 'Operational',
        menuPath: 'Produksi > Waste & Susut Produksi',
        actions: {'waste', 'return'}),
    AbChickenFeatureSpec(
        id: 'DKB-04',
        department: 'Operational',
        menuPath: 'Operasional > Kasir/POS > Meal Pegawai',
        actions: {'manager_meal', 'crew_meal'}),
    AbChickenFeatureSpec(
        id: 'DKB-05',
        department: 'Operational',
        menuPath: 'Transaksi & Laporan > Penjualan',
        actions: {'hourly_sales', 'item_sales', 'special_menu_sales'}),
    AbChickenFeatureSpec(
        id: 'DKB-06',
        department: 'Operational',
        menuPath: 'Akuntansi > Laba Rugi',
        actions: {'profit_loss', 'cogs'}),
    AbChickenFeatureSpec(
        id: 'DKB-07',
        department: 'Operational',
        menuPath: 'Operasional > Self Order / QR Menu',
        actions: {'publish_qr', 'self_order'},
        desktopMode: 'qr-publisher',
        androidMode: 'qr-browser'),
    AbChickenFeatureSpec(
        id: 'DKB-08',
        department: 'Operational',
        menuPath: 'Operasional > Pengaturan Shift Otomatis',
        actions: {'open_shift', 'close_shift'}),
    AbChickenFeatureSpec(
        id: 'DKB-09',
        department: 'Operational',
        menuPath: 'Operasional > Kasir/POS',
        actions: {'offline_catalog', 'offline_cart', 'outbox_sync'}),
    AbChickenFeatureSpec(
        id: 'DKB-10',
        department: 'Research & Development',
        menuPath: 'Master Data > Grup Produk',
        actions: {'bulk_hpp_store'}),
    AbChickenFeatureSpec(
        id: 'DKB-11',
        department: 'Research & Development',
        menuPath: 'Master Data > Produk > Resep',
        actions: {'bulk_delete_recipe_menu'}),
    AbChickenFeatureSpec(
        id: 'DKB-12',
        department: 'Research & Development',
        menuPath: 'Master Data > Produk > Resep',
        actions: {'bulk_delete_ingredient'}),
    AbChickenFeatureSpec(
        id: 'DKB-13',
        department: 'Research & Development',
        menuPath: 'Master Data > Produk > Custom Menu',
        actions: {'bulk_custom_menu'}),
    AbChickenFeatureSpec(
        id: 'DKB-14',
        department: 'Research & Development',
        menuPath: 'Dashboard > Produk',
        actions: {'best_seller', 'slow_mover'}),
    AbChickenFeatureSpec(
        id: 'DKB-15',
        department: 'Research & Development',
        menuPath: 'Transaksi & Laporan > Penjualan Produk',
        actions: {'product_sales'}),
    AbChickenFeatureSpec(
        id: 'DKB-16',
        department: 'Research & Development',
        menuPath: 'Transaksi & Laporan > Penjualan > Sales Type',
        actions: {'sales_type_report'}),
    AbChickenFeatureSpec(
        id: 'DKB-17',
        department: 'Research & Development',
        menuPath: 'Master Data > Produk > Harga per Kanal',
        actions: {'channel_price'}),
    AbChickenFeatureSpec(
        id: 'DKB-18',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Ringkasan Penjualan',
        actions: {'gross_sales', 'discount', 'refund', 'net_sales'}),
    AbChickenFeatureSpec(
        id: 'DKB-19',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Laba Kotor',
        actions: {'gross_profit'}),
    AbChickenFeatureSpec(
        id: 'DKB-20',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Metode Pembayaran',
        actions: {'payment_breakdown'}),
    AbChickenFeatureSpec(
        id: 'DKB-21',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Produk Terjual',
        actions: {'daily_store_item'}),
    AbChickenFeatureSpec(
        id: 'DKB-22',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Retur Penjualan',
        actions: {'refund_item'}),
    AbChickenFeatureSpec(
        id: 'DKB-23',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Transaksi',
        actions: {'daily', 'monthly', 'yearly'}),
    AbChickenFeatureSpec(
        id: 'DKB-24',
        department: 'Audit & Surveillance',
        menuPath: 'Transaksi & Laporan > Rekonsiliasi Sesi',
        actions: {'shift_income', 'shift_expense'}),
    AbChickenFeatureSpec(
        id: 'DKB-25',
        department: 'Audit & Surveillance',
        menuPath: 'Inventory & Sales > Riwayat Stok',
        actions: {
          'opening',
          'purchase',
          'usage',
          'transfer',
          'adjustment',
          'waste',
          'closing'
        }),
    AbChickenFeatureSpec(
        id: 'DKB-26',
        department: 'Audit & Surveillance',
        menuPath: 'Inventory & Sales > Rekonsiliasi Stok',
        actions: {'stock_variance'}),
    AbChickenFeatureSpec(
        id: 'DKB-27',
        department: 'Audit & Surveillance',
        menuPath: 'Produksi > Waste & Susut Produksi',
        actions: {'waste_summary'}),
    AbChickenFeatureSpec(
        id: 'DKB-28',
        department: 'HRD',
        menuPath: 'SDM / HRD > Cuti & Izin',
        actions: {'leave_request'}),
    AbChickenFeatureSpec(
        id: 'DKB-29',
        department: 'HRD',
        menuPath: 'SDM / HRD > Kehadiran',
        actions: {
          'photo_attendance',
          'fingerprint_attendance',
          'qr_attendance'
        },
        desktopMode: 'camera-scanner-bridge',
        androidMode: 'device-camera-biometric'),
    AbChickenFeatureSpec(
        id: 'DKB-30',
        department: 'HRD',
        menuPath: 'SDM / HRD > Cuti & Izin',
        actions: {'sick_request', 'supervisor_approval', 'hr_approval'}),
    AbChickenFeatureSpec(
        id: 'DKB-31',
        department: 'HRD',
        menuPath: 'SDM / HRD > Kedisiplinan',
        actions: {'discipline_chart'}),
    AbChickenFeatureSpec(
        id: 'DKB-32',
        department: 'HRD',
        menuPath: 'SDM / HRD > Kehadiran',
        actions: {'attendance_history', 'attendance_export'}),
    AbChickenFeatureSpec(
        id: 'DKB-33',
        department: 'HRD',
        menuPath: 'SDM / HRD > Pegawai',
        actions: {'employee_account', 'app_attendance'}),
    AbChickenFeatureSpec(
        id: 'DKB-34',
        department: 'HRD',
        menuPath: 'SDM / HRD > Payroll',
        actions: {'overtime_order', 'overtime_approval', 'payroll'}),
    AbChickenFeatureSpec(
        id: 'DKB-35',
        department: 'HRD',
        menuPath: 'SDM / HRD > Payroll > Jenjang Gaji',
        actions: {'salary_tenure', 'salary_percentage'}),
    AbChickenFeatureSpec(
        id: 'DKB-36',
        department: 'HRD',
        menuPath: 'SDM / HRD > Payroll',
        actions: {'cash_advance_deduction', 'automatic_deduction'}),
    AbChickenFeatureSpec(
        id: 'DKB-37',
        department: 'HRD',
        menuPath: 'SDM / HRD > Payroll > Slip Saya',
        actions: {'self_service_payslip'}),
    AbChickenFeatureSpec(
        id: 'DKB-38',
        department: 'HRD',
        menuPath: 'SDM / HRD > Pegawai',
        actions: {'employee_user_id'}),
    AbChickenFeatureSpec(
        id: 'DKB-39',
        department: 'HRD',
        menuPath: 'SDM / HRD > Aturan Potongan',
        actions: {'field_visit_note', 'audit_verification'}),
    AbChickenFeatureSpec(
        id: 'DKB-40',
        department: 'HRD',
        menuPath: 'SDM / HRD > Aturan Potongan',
        actions: {'sudden_resignation_deduction'}),
    AbChickenFeatureSpec(
        id: 'DKB-41',
        department: 'HRD',
        menuPath: 'SDM / HRD > Aturan Potongan',
        actions: {'minimum_tenure_exemption'}),
    AbChickenFeatureSpec(
        id: 'DKB-42',
        department: 'Purchase',
        menuPath: 'Pengadaan > PR',
        actions: {'purchase_request'}),
    AbChickenFeatureSpec(
        id: 'DKB-43',
        department: 'Purchase',
        menuPath: 'Pengadaan > Laporan PR',
        actions: {'purchase_request_report'}),
    AbChickenFeatureSpec(
        id: 'DKB-44',
        department: 'Purchase',
        menuPath: 'Master Data > Pemasok',
        actions: {'supplier_list'}),
    AbChickenFeatureSpec(
        id: 'DKB-45',
        department: 'Purchase',
        menuPath: 'Inventory & Sales > Kulakan',
        actions: {'purchase_list'}),
    AbChickenFeatureSpec(
        id: 'DKB-46',
        department: 'Purchase',
        menuPath: 'Inventory & Sales > Hutang Supplier',
        actions: {
          'purchase_by_supplier',
          'purchase_by_type',
          'purchase_by_item'
        }),
    AbChickenFeatureSpec(
        id: 'DKB-47',
        department: 'Purchase',
        menuPath: 'Inventory & Sales > Hutang Supplier',
        actions: {'due_reminder'}),
    AbChickenFeatureSpec(
        id: 'DKB-48',
        department: 'Purchase',
        menuPath: 'Inventory & Sales > Retur Pembelian',
        actions: {'supplier_return'}),
    AbChickenFeatureSpec(
        id: 'DKB-49',
        department: 'Supply Chain',
        menuPath: 'Pengadaan > PO',
        actions: {'direct_po'}),
    AbChickenFeatureSpec(
        id: 'DKB-50',
        department: 'Supply Chain',
        menuPath: 'Pengadaan > PO',
        actions: {'warehouse_reduce_po'}),
    AbChickenFeatureSpec(
        id: 'DKB-51',
        department: 'Supply Chain',
        menuPath: 'Distribusi & Pengiriman > Surat Jalan',
        actions: {
          'delivery_note',
          'warehouse_check',
          'checker_check',
          'outlet_check',
          'signatures'
        }),
    AbChickenFeatureSpec(
        id: 'DKB-52',
        department: 'Supply Chain',
        menuPath: 'Pengadaan > PO > Riwayat Stok Outlet',
        actions: {'outlet_usage', 'outlet_balance'}),
    AbChickenFeatureSpec(
        id: 'DKB-53',
        department: 'Supply Chain',
        menuPath: 'Distribusi & Pengiriman > Laporan',
        actions: {
          'daily_delivery',
          'weekly_delivery',
          'monthly_delivery',
          'delivery_by_item',
          'delivery_by_outlet'
        }),
    AbChickenFeatureSpec(
        id: 'DKB-54',
        department: 'Supply Chain',
        menuPath: 'Distribusi & Pengiriman > Retur Outlet',
        actions: {'outlet_return'}),
    AbChickenFeatureSpec(
        id: 'DKB-55',
        department: 'General Affair',
        menuPath: 'Inventaris GA > Pengajuan',
        actions: {'store_request', 'ga_approval', 'finance_approval'}),
    AbChickenFeatureSpec(
        id: 'DKB-56',
        department: 'General Affair',
        menuPath: 'Inventaris GA > Daftar Aset',
        actions: {'inventory_by_store'}),
    AbChickenFeatureSpec(
        id: 'DKB-57',
        department: 'General Affair',
        menuPath: 'Inventaris GA > Retur',
        actions: {'asset_return_request'}),
    AbChickenFeatureSpec(
        id: 'DKB-58',
        department: 'General Affair',
        menuPath: 'Inventaris GA > Perpindahan',
        actions: {'asset_transfer_request'}),
  ];

  static AbChickenFeatureSpec byId(String id) =>
      features.firstWhere((feature) => feature.id == id);
}
