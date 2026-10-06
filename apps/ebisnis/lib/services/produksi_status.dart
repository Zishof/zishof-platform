class AksiStatusProduksi {
  final String status;
  final String label;
  const AksiStatusProduksi(this.status, this.label);
}

// Status mengikuti kontrak ProduksiApiHelper; otorisasi tetap diperiksa server.
List<AksiStatusProduksi> aksiStatusProduksi(
    String jenis, String status, Map<String, dynamic> hak) {
  final hasil = <AksiStatusProduksi>[];
  if (jenis == 'quality_alert') return hasil;
  if (status == 'DRAFT' && hak['setujui'] == true) {
    hasil.add(jenis == 'bill_of_material'
        ? const AksiStatusProduksi('ACTIVE', 'Aktifkan BOM')
        : jenis == 'work_order'
            ? const AksiStatusProduksi('RELEASED', 'Rilis produksi')
            : const AksiStatusProduksi('POSTED', 'Posting'));
  }
  if (jenis == 'work_order' && status == 'RELEASED' && hak['ubah'] == true) {
    hasil.add(const AksiStatusProduksi('IN_PROGRESS', 'Mulai produksi'));
  }
  if (jenis == 'work_order' &&
      status == 'IN_PROGRESS' &&
      hak['selesai'] == true) {
    hasil.add(const AksiStatusProduksi('COMPLETED', 'Selesaikan produksi'));
  }
  if (hak['balikkan'] == true) {
    if (jenis == 'bill_of_material' && status == 'ACTIVE') {
      hasil.add(const AksiStatusProduksi('RETIRED', 'Nonaktifkan BOM'));
    } else if (jenis != 'work_order' && status == 'POSTED') {
      hasil.add(const AksiStatusProduksi('REVERSED', 'Balikkan posting'));
    }
  }
  if (hak['batalkan'] == true &&
      (status == 'DRAFT' ||
          (jenis == 'work_order' &&
              (status == 'RELEASED' || status == 'IN_PROGRESS')))) {
    hasil.add(const AksiStatusProduksi('CANCELLED', 'Batalkan'));
  }
  return hasil;
}

Map<String, dynamic> payloadStatusProduksi(
        String jenis, dynamic id, String status) =>
    {
      'jenis': jenis,
      'id': id,
      'statusDokumen': status,
      'catatanStatus': 'Perubahan status dari aplikasi eBisnis',
    };
