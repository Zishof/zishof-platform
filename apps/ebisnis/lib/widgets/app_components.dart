import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Komponen bersama gaya desain baru (lihat [AppColors]) -- kartu KPI ikon
/// berwarna, badge status pil, dan pembungkus kartu section. Dipakai layar
/// yang sudah di-reskin (Ringkasan/Kasir/Produk dst, task #191-196).

/// Kartu KPI: lingkaran ikon berwarna + angka besar + label + delta opsional
/// (naik/turun dibanding periode sebelumnya) + tautan opsional ("Lihat Detail").
class AppKpiCard extends StatelessWidget {
  final IconData icon;
  final Color warna;
  final String nilai;
  final String label;
  final String? delta;
  final bool deltaPositif;
  final String? tautan;
  final VoidCallback? onTautanTap;

  const AppKpiCard({
    super.key,
    required this.icon,
    required this.warna,
    required this.nilai,
    required this.label,
    this.delta,
    this.deltaPositif = true,
    this.tautan,
    this.onTautanTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.latarLembut(warna), shape: BoxShape.circle),
            child: Icon(icon, color: warna, size: 20),
          ),
          const SizedBox(height: 10),
          Text(nilai, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(deltaPositif ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: deltaPositif ? AppColors.success : AppColors.danger),
                const SizedBox(width: 2),
                Flexible(child: Text(delta!, style: TextStyle(fontSize: 11, color: deltaPositif ? AppColors.success : AppColors.danger), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ],
          if (tautan != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: onTautanTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tautan!, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge status pil warna lembut -- dipakai kolom Status di tabel/list.
class StatusPill extends StatelessWidget {
  final String label;
  final Color warna;
  const StatusPill({super.key, required this.label, required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.latarLembut(warna), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: warna)),
    );
  }
}

/// Pembungkus kartu putih rounded standar (dgn judul opsional) dipakai semua
/// panel/section di layar yang sudah di-reskin.
class AppSectionCard extends StatelessWidget {
  final String? judul;
  final Widget? aksiJudul;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppSectionCard({super.key, this.judul, this.aksiJudul, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (judul != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(judul!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                  if (aksiJudul != null) aksiJudul!,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Tombol aksi berwarna gaya referensi (mis. "Buat PR" hijau, "Terima Barang"
/// ungu) -- filled kalau [terisi]=true (default), outline kalau false.
class AppTombolAksi extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color warna;
  final bool terisi;
  final VoidCallback? onPressed;
  const AppTombolAksi({super.key, required this.label, required this.icon, this.warna = AppColors.primary, this.terisi = true, this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (terisi) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(backgroundColor: warna, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: warna),
      label: Text(label, style: TextStyle(color: warna)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: warna.withValues(alpha: 0.4)), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    );
  }
}
