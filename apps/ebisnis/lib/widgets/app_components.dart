import 'dart:async';

import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Dipanggil sambil mengetik, sesudah [debounce].
  ///
  /// Boleh null: sebagian kotak cari nilainya dibaca saat tombol ditekan, bukan
  /// sambil diketik. Kotak seperti itu tetap pantas memakai widget ini demi
  /// ikon, tombol bersihkan, dan rupa yang sama.
  final ValueChanged<String>? onChanged;
  final Duration debounce;
  final TextEditingController? controller;

  /// Label yang mengambang di atas medan.
  ///
  /// Terpisah dari [hintText] karena sebagian kotak memakai KEDUANYA dengan isi
  /// berbeda -- label menyebut apa yang dicari, hint memberi contohnya.
  final String? labelText;

  /// Teks bantuan di bawah medan, untuk menerangkan apa saja yang tercakup.
  final String? helperText;

  /// Batas baris [helperText]; perlu bila teksnya menjalar lebih dari satu baris.
  final int? helperMaxLines;

  final FocusNode? focusNode;

  /// Dipanggil saat Enter ditekan.
  ///
  /// Sebagian kotak memberi Enter arti TERSENDIRI -- mis. memilih hasil teratas
  /// -- yang berbeda dari sekadar menyaring. Tanpa ini, arti itu hilang saat
  /// kotaknya diseragamkan.
  final ValueChanged<String>? onSubmitted;

  final TextInputAction? textInputAction;

  /// Memakai [AppFormStyle.fieldDecoration], bukan tema bawaan.
  ///
  /// Isian, padding, dan border fokusnya berbeda dari tema. Layar yang sudah
  /// memakai gaya form itu akan berubah rupa bila dikonversi tanpa pilihan ini.
  final bool gayaForm;

  /// Menaruh kursor di kotak cari begitu ia tampil.
  ///
  /// Dipakai kotak cari di dalam dialog pemilih dokumen: dialognya dibuka
  /// justru untuk mencari, jadi memaksa pengguna mengklik dulu hanya
  /// menambah satu langkah tanpa guna.
  final bool autofocus;

  /// Menampilkan pemindai barcode/QR produk. Android/iOS memakai kamera HP,
  /// sedangkan Windows memakai webcam internal atau USB melalui core_hw.
  final bool scanProduk;

  /// Callback khusus sesudah kamera berhasil membaca kode. Jika null, hasil
  /// diteruskan ke [onSubmitted], lalu [onChanged] sebagai fallback.
  final ValueChanged<String>? onScanned;

  const AppSearchField({
    super.key,
    // Boleh kosong: sebagian kotak hanya berlabel, tanpa contoh isian.
    this.hintText = '',
    this.onChanged,
    this.initialValue = '',
    this.debounce = const Duration(milliseconds: 220),
    this.controller,
    this.labelText,
    this.helperText,
    this.helperMaxLines,
    this.focusNode,
    this.onSubmitted,
    this.textInputAction,
    this.gayaForm = false,
    this.autofocus = false,
    this.scanProduk = false,
    this.onScanned,
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
    final cb = widget.onChanged;
    if (cb == null) return;
    _timer = Timer(widget.debounce, () => cb(value));
  }

  Future<void> _scanProduk() async {
    final kode = await BarcodeScannerScreen.pindai(
      context,
      judul: 'Scan Barcode / QR Produk',
    );
    if (!mounted || kode == null || kode.trim().isEmpty) return;
    final nilai = kode.trim();
    _timer?.cancel();
    _controller
      ..text = nilai
      ..selection = TextSelection.collapsed(offset: nilai.length);
    setStateIfMounted(() {});
    final callback = widget.onScanned ?? widget.onSubmitted ?? widget.onChanged;
    callback?.call(nilai);
  }

  @override
  Widget build(BuildContext context) {
    final bersihkan = _controller.text.isEmpty
        ? null
        : IconButton(
            tooltip: 'Bersihkan',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              _controller.clear();
              _ubah('');
              setStateIfMounted(() {});
            },
          );
    final aksiAkhir = !widget.scanProduk
        ? bersihkan
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Scan barcode/QR dengan kamera',
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                onPressed: _scanProduk,
              ),
              if (bersihkan != null) bersihkan,
            ],
          );
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onChanged: _ubah,
      onSubmitted: widget.onSubmitted,
      decoration: widget.gayaForm
          ? AppFormStyle.fieldDecoration(
              context,
              labelText: widget.labelText ?? widget.hintText,
              hintText: widget.labelText == null ? null : widget.hintText,
              helperText: widget.helperText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: aksiAkhir,
              isDense: true,
              showLabel: widget.labelText != null,
            )
          : InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              helperText: widget.helperText,
              helperMaxLines: widget.helperMaxLines,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: aksiAkhir,
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

/// Penyaji harga untuk pengguna yang TIDAK diberi akses ubah harga.
///
/// Sengaja berupa LABEL (teks biasa), bukan kolom isian yang di-disable:
/// kolom disable masih terlihat seperti tempat mengetik, ikut divalidasi,
/// dan membingungkan kasir. Nilai di sini murni untuk dibaca.
class AppHargaTerkunci extends StatelessWidget {
  final String label;
  final String nilai;
  final String? catatan;

  const AppHargaTerkunci({
    super.key,
    required this.label,
    required this.nilai,
    this.catatan,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 15, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  nilai.isEmpty ? '-' : nilai,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          if (catatan != null) ...[
            const SizedBox(height: 4),
            Text(
              catatan!,
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

  /// Jejak teknis kegagalan bila banner ini dipakai untuk menampilkan galat --
  /// lihat [AppDetailGalat]. Diisi dari `JejakGalat.detailUntuk(pesan)`.
  final String? detail;

  const AppInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color = AppColors.info,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final adaDetail = (detail ?? '').trim().isNotEmpty;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(fontSize: 12, height: 1.35, color: color),
                ),
                if (adaDetail) AppDetailGalat(detail: detail!.trim()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Penyingkap "Detail Error" di bawah pesan kegagalan.
///
/// Ada karena kontrak API memisahkan `message` (kalimat untuk pengguna) dari
/// `teknis` (jejak untuk admin/developer), tetapi sebagian layar hanya
/// menampilkan `message` sehingga keterangan yang menjelaskan penyebabnya
/// hilang begitu saja. Ditutup secara bawaan supaya kasir tidak terganggu, dan
/// isinya dapat disalin utuh — itulah yang berguna saat melapor ke admin.
class AppDetailGalat extends StatelessWidget {
  final String detail;

  const AppDetailGalat({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(Icons.bug_report_outlined,
            size: 18, color: AppColors.textSecondaryOf(context)),
        title: Text(
          'Detail Error',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        subtitle: Text(
          'Buka bila perlu dikirimkan ke admin/developer.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.textSecondaryOf(context)),
              border: Border.all(color: AppColors.borderOf(context)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              detail,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                fontFamily: 'monospace',
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: detail));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Detail error disalin.')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Salin'),
            ),
          ),
        ],
      ),
    );
  }
}

/// [AppDetailGalat] yang aman dipasang langsung di dalam daftar `children`
/// tanpa pengecekan null: menghilang sendiri bila galatnya memang tidak punya
/// lapis teknis (mis. kegagalan lokal, atau banner sedang menampilkan pesan
/// validasi -- lihat `JejakGalat.detailUntuk`).
class AppDetailGalatOpsional extends StatelessWidget {
  final String? detail;

  const AppDetailGalatOpsional({super.key, this.detail});

  @override
  Widget build(BuildContext context) => (detail ?? '').trim().isEmpty
      ? const SizedBox.shrink()
      : AppDetailGalat(detail: detail!.trim());
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

  /// Keterangan teknis kegagalan (isi `ApiException.teknis` berikut kode
  /// referensinya). Disembunyikan di balik "Detail Error" yang bisa dibuka:
  /// [errorText] tetap kalimat untuk pengguna, sedangkan ini yang disalin ke
  /// admin ketika pesan penolakan server belum cukup menjelaskan.
  final String? errorDetail;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? headerTrailing;

  const AppFormSheet({
    super.key,
    required this.scrollController,
    required this.title,
    this.subtitle,
    required this.icon,
    this.errorText,
    this.errorDetail,
    required this.children,
    required this.actions,
    this.headerTrailing,
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
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
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
              if (headerTrailing != null) ...[
                const SizedBox(width: 12),
                headerTrailing!,
              ],
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
          if ((errorDetail ?? '').trim().isNotEmpty)
            AppDetailGalat(detail: errorDetail!.trim()),
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

/// Kartu KPI shared: mengikuti gaya Dashboard Bisnis - Ringkasan Umum, yaitu
/// kartu putih dengan ikon bulat di kiri dan teks ringkas di kanan.
class AppKpiCard extends StatelessWidget {
  final IconData icon;
  final Color warna;
  final String nilai;
  final String label;
  final String? delta;
  final bool deltaPositif;
  final String? tautan;
  final VoidCallback? onTautanTap;
  final VoidCallback? onTap;
  final String? tooltip;

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
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final kartu = AppSectionCard(
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
                        fontSize: 16,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimaryOf(context)),
                    maxLines: 2,
                    overflow: TextOverflow.visible),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        color: AppColors.textSecondaryOf(context),
                        fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.visible),
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
    if (onTap == null) return kartu;

    Widget hasil = Semantics(
      button: true,
      label: tooltip ?? '$label: $nilai',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: kartu,
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      hasil = Tooltip(message: tooltip!, child: hasil);
    }
    return hasil;
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

/// Jumlah baris per halaman untuk tabel yang TIDAK mengurus pagingnya sendiri.
///
/// Dipasang di satu tempat, bukan di tiap layar: sebelum ini 44 dari 73 tabel
/// merender seluruh barisnya sekaligus, sehingga daftar 200-an baris membuat
/// pemuatan pertama terasa berat dan -- pada tab tanpa area gulir sendiri --
/// barisnya bahkan tidak dapat dicapai sama sekali.
const int kBarisPerHalamanTabel = 15;

class AppDataTable extends StatefulWidget {
  final List<AppTableColumn> columns;
  final List<AppTableRowData> rows;

  /// Paging yang diurus PEMANGGIL (biasanya paging sisi server). Bila diisi,
  /// tabel ini tidak memotong apa pun -- barisnya sudah sepotong halaman.
  final AppTablePagination? pagination;
  final String emptyText;
  final double minWidth;

  /// Setel false untuk tabel yang memang harus tampil utuh sekaligus, mis.
  /// ringkasan tiga baris di dalam dialog, di mana bilah halaman justru
  /// mengganggu. Tabel panjang tidak boleh memakai ini.
  final bool pagingOtomatis;

  /// Label satuan baris pada bilah halaman ("204 anggota", "18 produk").
  final String labelData;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.pagination,
    this.emptyText = 'Tidak ada data.',
    this.minWidth = 760,
    this.pagingOtomatis = true,
    this.labelData = 'data',
  });

  @override
  State<AppDataTable> createState() => _AppDataTableState();
}

class _AppDataTableState extends State<AppDataTable> {
  int _halaman = 1;
  final ScrollController _verticalController = ScrollController();

  bool get _pagingSendiri =>
      widget.pagination == null &&
      widget.pagingOtomatis &&
      widget.rows.length > kBarisPerHalamanTabel;

  int get _totalHalaman =>
      (widget.rows.length / kBarisPerHalamanTabel).ceil().clamp(1, 1 << 30);

  @override
  void didUpdateWidget(covariant AppDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Daftar menyusut (mis. pengguna menyaring) bisa membuat halaman yang
    // sedang dibuka tidak ada lagi. Tanpa penjepitan ini tabel tampak KOSONG
    // padahal datanya ada -- kegagalan yang mudah disalahartikan sebagai
    // "datanya hilang".
    if (widget.rows.length != oldWidget.rows.length &&
        _halaman > _totalHalaman) {
      _halaman = _totalHalaman;
    }
  }

  List<AppTableRowData> get _barisTampil {
    if (!_pagingSendiri) return widget.rows;
    final mulai = (_halaman - 1) * kBarisPerHalamanTabel;
    if (mulai >= widget.rows.length) return const [];
    final sampai =
        (mulai + kBarisPerHalamanTabel).clamp(0, widget.rows.length).toInt();
    return widget.rows.sublist(mulai, sampai);
  }

  void _keHalaman(int h) {
    final tujuan = h.clamp(1, _totalHalaman);
    if (tujuan == _halaman) return;
    setState(() => _halaman = tujuan);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baris = _barisTampil;
    final pagingTampil = widget.pagination ??
        (_pagingSendiri
            ? AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: widget.rows.length,
                labelData: widget.labelData,
                onSebelumnya:
                    _halaman > 1 ? () => _keHalaman(_halaman - 1) : null,
                onBerikutnya: _halaman < _totalHalaman
                    ? () => _keHalaman(_halaman + 1)
                    : null,
              )
            : null);

    final table = AppSectionCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final bounded = constraints.hasBoundedWidth;
                final lebarTabel =
                    bounded ? constraints.maxWidth : widget.minWidth;
                if (bounded && lebarTabel < 720) {
                  return _AppCompactTable(
                    columns: widget.columns,
                    rows: baris,
                    emptyText: widget.emptyText,
                  );
                }
                // Pada desktop/tablet semua kolom mengikuti lebar konten.
                // Jangan memaksa minWidth dan horizontal-scroll: pola lama
                // membuat kolom paling kanan tampak terpotong oleh viewport.
                return SizedBox(
                  width: lebarTabel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AppTableHeader(columns: widget.columns),
                      if (baris.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 36),
                          child: Center(
                            child: Text(
                              widget.emptyText,
                              style: TextStyle(
                                  color: AppColors.textSecondaryOf(context),
                                  fontSize: 13),
                            ),
                          ),
                        )
                      else
                        ...baris.map((row) => _AppTableRow(row: row)),
                    ],
                  ),
                );
              },
            ),
            if (pagingTampil != null) _AppTableFooter(pagination: pagingTampil),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, viewport) {
        if (!viewport.hasBoundedHeight || !viewport.maxHeight.isFinite) {
          return table;
        }
        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          thickness: 8,
          radius: const Radius.circular(8),
          child: SingleChildScrollView(
            controller: _verticalController,
            primary: false,
            child: table,
          ),
        );
      },
    );
  }
}

class _AppCompactTable extends StatelessWidget {
  final List<AppTableColumn> columns;
  final List<AppTableRowData> rows;
  final String emptyText;

  const _AppCompactTable({
    required this.columns,
    required this.rows,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
        child: Center(
          child: Text(
            emptyText,
            style: TextStyle(
              color: AppColors.textSecondaryOf(context),
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return Column(
      children: rows.map((row) {
        final content = LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 480;
            final cellWidth = twoColumns
                ? (constraints.maxWidth - 44) / 2
                : constraints.maxWidth - 32;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                border:
                    Border(top: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 14,
                children: List<Widget>.generate(row.cells.length, (index) {
                  final cell = row.cells[index];
                  final label = index < columns.length
                      ? columns[index].label.toUpperCase()
                      : '';
                  return SizedBox(
                    width: cellWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: AppColors.textSecondaryOf(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.35,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Align(
                          alignment: _AppTableRow.alignment(cell.align),
                          child: cell.child,
                        ),
                      ],
                    ),
                  );
                }),
              ),
            );
          },
        );
        if (row.onTap == null) return content;
        return InkWell(onTap: row.onTap, child: content);
      }).toList(),
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
                    alignment: alignment(cell.align),
                    child: cell.child,
                  ),
                ))
            .toList(),
      ),
    );
    if (row.onTap == null) return content;
    return InkWell(onTap: row.onTap, child: content);
  }

  static Alignment alignment(TextAlign align) {
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

/// Tombol aksi baku untuk dialog tambah/ubah data.
///
/// Proses simpan dijalankan ketika dialog masih terbuka. Dialog hanya ditutup
/// setelah [onSubmit] mengembalikan `true`; kegagalan validasi, jaringan, atau
/// server mempertahankan seluruh nilai isian sehingga pengguna dapat langsung
/// memperbaiki dan mencoba kembali.
class AppCrudDialogActions extends StatefulWidget {
  final Future<bool> Function() onSubmit;
  final bool enabled;
  final String submitLabel;
  final String cancelLabel;
  final String failureMessage;

  const AppCrudDialogActions({
    super.key,
    required this.onSubmit,
    this.enabled = true,
    this.submitLabel = 'Simpan',
    this.cancelLabel = 'Batal',
    this.failureMessage =
        'Belum berhasil disimpan. Periksa isian lalu coba kembali.',
  });

  @override
  State<AppCrudDialogActions> createState() => _AppCrudDialogActionsState();
}

class _AppCrudDialogActionsState extends State<AppCrudDialogActions> {
  bool _menyimpan = false;
  String? _galat;

  Future<void> _simpan() async {
    if (_menyimpan) return;
    setState(() {
      _menyimpan = true;
      _galat = null;
    });

    var berhasil = false;
    try {
      berhasil = await widget.onSubmit();
    } catch (e) {
      if (mounted) {
        setState(() => _galat = e.toString().replaceFirst('Exception: ', ''));
      }
    }

    if (!mounted) return;
    if (berhasil) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _menyimpan = false;
      _galat ??= widget.failureMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_galat != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
              ),
              child: Text(
                _galat!,
                style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _menyimpan ? null : () => Navigator.pop(context, false),
                child: Text(widget.cancelLabel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _menyimpan || !widget.enabled ? null : _simpan,
                child: _menyimpan
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Menyimpan...'),
                        ],
                      )
                    : Text(widget.submitLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
