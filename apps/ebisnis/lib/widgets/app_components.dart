import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'safe_state.dart';

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
            data: IconThemeData(color: AppColors.primary, size: 18),
            child: loading ?? Icon(icon),
          ),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimaryOf(context),
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
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
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

/// Field pencarian standar untuk layar admin. Perubahan dikirim setelah jeda
/// pendek supaya daftar besar tidak difilter ulang di setiap keypress.
class AppSearchField extends StatefulWidget {
  final String hintText;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final Duration debounce;
  final TextEditingController? controller;

  const AppSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.initialValue = '',
    this.debounce = const Duration(milliseconds: 220),
    this.controller,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _ubah(String value) {
    setStateIfMounted(() {});
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(value));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _ubah,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Bersihkan',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  _ubah('');
                  setStateIfMounted(() {});
                },
              ),
      ),
    );
  }
}

class AppFormSection extends StatelessWidget {
  final String judul;
  final String? deskripsi;
  final List<Widget> children;
  final Widget? aksiJudul;
  final EdgeInsetsGeometry padding;

  const AppFormSection({
    super.key,
    required this.judul,
    this.deskripsi,
    required this.children,
    this.aksiJudul,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      judul: judul,
      aksiJudul: aksiJudul,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (deskripsi != null) ...[
            Text(
              deskripsi!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    );
  }
}

class AppFormTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? helperText;
  final int maxLines;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;

  const AppFormTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.helperText,
    this.maxLines = 1,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: obscureText ? 1 : maxLines,
            enabled: enabled,
            readOnly: readOnly,
            obscureText: obscureText,
            keyboardType: keyboardType,
            validator: validator,
            style: TextStyle(color: AppColors.textPrimaryOf(context)),
            decoration: AppFormStyle.fieldDecoration(
              context,
              labelText: label,
              hintText: hintText,
              helperText: helperText,
              suffixIcon: suffixIcon,
              showLabel: false,
            ),
          ),
        ],
      ),
    );
  }
}

class AppReadonlyField extends StatelessWidget {
  final String label;
  final String value;
  final String? helperText;

  const AppReadonlyField({
    super.key,
    required this.label,
    required this.value,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.gelap(context)
                  ? AppColors.darkPageBg
                  : const Color(0xFFF8FAFC),
              border: Border.all(color: AppColors.borderOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (helperText != null) ...[
            const SizedBox(height: 6),
            Text(
              helperText!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AppFormSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppFormSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Text(
          title,
          style:
              TextStyle(fontSize: 13, color: AppColors.textPrimaryOf(context)),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class AppInfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const AppInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color = AppColors.info,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.latarLembut(color),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class AppFormStyle {
  AppFormStyle._();

  static InputDecoration fieldDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? helperText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool isDense = false,
    bool showLabel = true,
  }) {
    return InputDecoration(
      labelText: showLabel ? labelText : null,
      hintText: hintText,
      helperText: helperText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: isDense,
      filled: true,
      fillColor: AppColors.gelap(context)
          ? AppColors.darkPageBg
          : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }
}

class AppFormSheet extends StatelessWidget {
  final ScrollController scrollController;
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? errorText;
  final List<Widget> children;
  final List<Widget> actions;

  const AppFormSheet({
    super.key,
    required this.scrollController,
    required this.title,
    this.subtitle,
    required this.icon,
    this.errorText,
    required this.children,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Center(
          child: Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.borderOf(context),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.latarLembut(AppColors.primary),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.textPrimaryOf(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          AppInfoBanner(
            icon: Icons.error_outline,
            text: errorText!,
            color: AppColors.danger,
          ),
        ],
        const SizedBox(height: 14),
        ...children,
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: actions,
        ),
      ],
    );
  }
}

class AppDetailDialogShell extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final double width;

  const AppDetailDialogShell({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
    this.width = 820,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
      actions: actions,
    );
  }
}

class AppDetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const AppDetailChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final warna = color ?? AppColors.textSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: warna),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ],
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
                    style: TextStyle(
                        fontSize: 19,
                        height: 1.1,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimaryOf(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        color: AppColors.textSecondaryOf(context),
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
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Icon(Icons.chevron_right,
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
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimaryOf(context))),
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
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppColors.gelap(context)
            ? const []
            : [
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

  /// `null` -- ikut [AppColors.primary] (tema aktif), diresolusi di
  /// [build] (bukan default parameter) krn [AppColors.primary] sekarang
  /// bisa berubah runtime (pilihan tema di Konfigurasi), jadi tidak lagi
  /// nilai konstan yang sah utk default value.
  final Color? warna;
  final bool terisi;
  final VoidCallback? onPressed;
  const AppTombolAksi(
      {super.key,
      required this.label,
      required this.icon,
      this.warna,
      this.terisi = true,
      this.onPressed});

  @override
  Widget build(BuildContext context) {
    final warnaEfektif = warna ?? AppColors.primary;
    if (terisi) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
        style: ElevatedButton.styleFrom(
            backgroundColor: warnaEfektif,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: warnaEfektif),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, style: TextStyle(color: warnaEfektif)),
      ),
      style: OutlinedButton.styleFrom(
          side: BorderSide(color: warnaEfektif.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    );
  }
}

class AppTableColumn {
  final String label;
  final int flex;
  final TextAlign align;
  final double? width;

  const AppTableColumn(
    this.label, {
    this.flex = 1,
    this.align = TextAlign.left,
    this.width,
  });
}

class AppTableCell {
  final Widget child;
  final int flex;
  final TextAlign align;
  final double? width;

  const AppTableCell({
    required this.child,
    this.flex = 1,
    this.align = TextAlign.left,
    this.width,
  });

  factory AppTableCell.text(
    String value, {
    int flex = 1,
    TextAlign align = TextAlign.left,
    double? width,
    TextStyle? style,
    int maxLines = 1,
  }) {
    return AppTableCell(
      flex: flex,
      align: align,
      width: width,
      child: Text(
        value,
        textAlign: align,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style ?? const TextStyle(fontSize: 12.5),
      ),
    );
  }
}

class AppTableRowData {
  final List<AppTableCell> cells;
  final VoidCallback? onTap;

  const AppTableRowData({
    required this.cells,
    this.onTap,
  });
}

class AppTablePagination {
  final int halaman;
  final int totalHalaman;
  final int totalData;
  final VoidCallback? onSebelumnya;
  final VoidCallback? onBerikutnya;
  final String labelData;

  const AppTablePagination({
    required this.halaman,
    required this.totalHalaman,
    required this.totalData,
    this.onSebelumnya,
    this.onBerikutnya,
    this.labelData = 'data',
  });
}

class AppDataTable extends StatelessWidget {
  final List<AppTableColumn> columns;
  final List<AppTableRowData> rows;
  final AppTablePagination? pagination;
  final String emptyText;
  final double minWidth;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.pagination,
    this.emptyText = 'Tidak ada data.',
    this.minWidth = 760,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final lebarTabel = constraints.hasBoundedWidth &&
                        constraints.maxWidth > minWidth
                    ? constraints.maxWidth
                    : minWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: lebarTabel,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AppTableHeader(columns: columns),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 36),
                            child: Center(
                              child: Text(
                                emptyText,
                                style: TextStyle(
                                    color: AppColors.textSecondaryOf(context),
                                    fontSize: 13),
                              ),
                            ),
                          )
                        else
                          ...rows.map((row) => _AppTableRow(row: row)),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (pagination != null) _AppTableFooter(pagination: pagination!),
          ],
        ),
      ),
    );
  }
}

class _AppTableHeader extends StatelessWidget {
  final List<AppTableColumn> columns;

  const _AppTableHeader({required this.columns});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.pageBgOf(context),
      child: Row(
        children: columns
            .map((column) => _AppTableSlot(
                  flex: column.flex,
                  width: column.width,
                  child: Text(
                    column.label.toUpperCase(),
                    textAlign: column.align,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _AppTableRow extends StatelessWidget {
  final AppTableRowData row;

  const _AppTableRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: row.cells
            .map((cell) => _AppTableSlot(
                  flex: cell.flex,
                  width: cell.width,
                  child: Align(
                    alignment: _alignment(cell.align),
                    child: cell.child,
                  ),
                ))
            .toList(),
      ),
    );
    if (row.onTap == null) return content;
    return InkWell(onTap: row.onTap, child: content);
  }

  static Alignment _alignment(TextAlign align) {
    switch (align) {
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
        return Alignment.center;
      default:
        return Alignment.centerLeft;
    }
  }
}

class _AppTableSlot extends StatelessWidget {
  final Widget child;
  final int flex;
  final double? width;

  const _AppTableSlot({
    required this.child,
    required this.flex,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final wrapped = Padding(
      padding: const EdgeInsets.only(right: 14),
      child: child,
    );
    if (width != null) return SizedBox(width: width, child: wrapped);
    return Expanded(flex: flex, child: wrapped);
  }
}

class _AppTableFooter extends StatelessWidget {
  final AppTablePagination pagination;

  const _AppTableFooter({required this.pagination});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${pagination.totalData} ${pagination.labelData}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondaryOf(context)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: pagination.onSebelumnya,
          ),
          Text(
            'Halaman ${pagination.halaman} / ${pagination.totalHalaman}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: pagination.onBerikutnya,
          ),
        ],
      ),
    );
  }
}
