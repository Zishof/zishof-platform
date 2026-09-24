import '../models.dart';

List<CaraBayar> metodePemulihanMember(Map<String, dynamic> hasil) {
  if (hasil['izinTidakDisetel'] == true) return [];
  return ((hasil['caraBayar'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => CaraBayar.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

Map<String, dynamic> identitasMemberPemulihan(Anggota? member) =>
    member == null ? {} : {'id_member': member.id, 'nama_member': member.nama};

String? validasiMemberPemulihan(
    List<CaraBayar> metode, int? metodeId, int? memberId,
    {bool memuat = false}) {
  if (memuat) return 'Tunggu pemeriksaan izin pembayaran member selesai.';
  final cocok = metode.where((m) => m.id == metodeId);
  if (cocok.isEmpty) return 'Pilih metode yang diizinkan untuk pelanggan ini.';
  if (cocok.first.wajibPilihMember && (memberId == null || memberId <= 0)) {
    return 'Pilih member/santri sebelum menyimpan pembayaran voucher atau saldo.';
  }
  return null;
}
