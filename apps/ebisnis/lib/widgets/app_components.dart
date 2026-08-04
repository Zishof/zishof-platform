import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Komponen bersama gaya desain baru (lihat [AppColors]) -- kartu KPI ikon
/// berwarna, badge status pil, dan pembungkus kartu section. Dipakai layar
/// yang sudah di-reskin (Ringkasan/Kasir/Produk dst, task #191-196).

class HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Widget? loading;
  final String? tooltip;

  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip ?? label,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: IconTheme(
            data: const IconThemeData(color: AppColors.primary, size: 18),
            child: loading ?? Icon(icon),
          ),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class HeaderActionSurface extends StatelessWidget {
  final IconData icon;
  final String label;

  const HeaderActionSurface({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AppColors.latarLembut(warna), shape: BoxShape.circle),
            child: Icon(icon, color: warna, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nilai,
                    style: const TextStyle(
                        fontSize: 19,
                        height: 1.1,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        color: AppColors.sidebarBg,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (delta != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                          deltaPositif
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 12,
                          color: deltaPositif
                              ? AppColors.success
                              : AppColors.danger),
                      const SizedBox(width: 2),
                      Expanded(
                          child: Text(delta!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: deltaPositif
                                      ? AppColors.success
                                      : AppColors.danger),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
                if (tautan != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onTautanTap,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(tautan!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 14, color: AppColors.primary),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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
      decoration: BoxDecoration(
          color: AppColors.latarLembut(warna),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: warna),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
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
  const AppSectionCard(
      {super.key,
      this.judul,
      this.aksiJudul,
      required this.child,
      this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    Widget isiKartu() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (judul != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(judul!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary)),
                ),
                if (aksiJudul != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: aksiJudul!,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isi = isiKartu();
            if (!constraints.hasBoundedHeight) return isi;
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: isi,
              ),
            );
          },
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
  const AppTombolAksi(
      {super.key,
      required this.label,
      required this.icon,
      this.warna = AppColors.primary,
      this.terisi = true,
      this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (terisi) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
        style: ElevatedButton.styleFrom(
            backgroundColor: warna,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: warna),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, style: TextStyle(color: warna)),
      ),
      style: OutlinedButton.styleFrom(
          side: BorderSide(color: warna.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    );
  }
}
