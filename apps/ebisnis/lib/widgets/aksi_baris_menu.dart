import 'package:flutter/material.dart';

/// Satu pilihan pada menu aksi baris maupun toolbar aksi adaptif.
///
/// Sesuai **ATURAN MUTLAK 14, 15, 16, 16A, 16B, 16C** di `/docs/AGENTS.md`:
/// - Digunakan baik pada menu kebab (`...`) di kolom `"Aksi"` tabel ([AksiBarisMenu])
///   maupun pada bilah aksi halaman/toolbar adaptif ([AksiToolbarMenu]).
/// - Bila [onTap] bernilai `null`, aksinya sedang tidak tersedia (tetap tampil redup
///   di dalam menu popup agar posisi urutan menu konsisten).
/// - Bila [merusak] bernilai `true`, aksi penghapusan/pembatalan dipisahkan dengan garis
///   pembatas dan diberi warna merah peringatan (`colorScheme.error`).
/// - Bila [utama] bernilai `true`, tombol pada [AksiToolbarMenu] dirender menggunakan
///   [FilledButton.icon] agar menonjol sebagai aksi primer.
class AksiBaris {
  final IconData ikon;
  final String label;

  /// `null` berarti aksinya sedang tidak tersedia -- barisnya tetap TAMPIL tetapi
  /// redup di dalam menu popup, sehingga pengguna tahu aksi itu ada namun belum dapat
  /// dipakai sekarang.
  final VoidCallback? onTap;

  /// Aksi yang merusak/menghapus diberi warna berbeda dan diletakkan terpisah.
  final bool merusak;

  /// Menandai aksi utama (primer) saat dirender sebagai tombol langsung pada toolbar.
  final bool utama;

  const AksiBaris({
    required this.ikon,
    required this.label,
    required this.onTap,
    this.merusak = false,
    this.utama = false,
  });

  /// Mendeteksi apakah label tombol merupakan aksi terminal form/dialog
  /// (`Simpan`, `Batal`, `Tutup`, `Kembali`, `Terapkan`, `Reset`) yang menurut
  /// **ATURAN MUTLAK 14 & 16** DILARANG KERAS dimasukkan ke dalam menu kebab (`...`).
  bool get adalahAksiTerminal {
    final l = label.trim().toLowerCase();
    return l == 'simpan' ||
        l.startsWith('simpan ') ||
        l == 'batal' ||
        l == 'tutup' ||
        l.startsWith('tutup ') ||
        l == 'kembali' ||
        l == 'terapkan';
  }
}

/// Tombol "..." (Kebab Menu) yang membuka daftar aksi baris tabel berikut ikon dan labelnya.
///
/// Mematuhi **ATURAN MUTLAK 14 & 16** di `/docs/AGENTS.md`:
/// 1. **Kolom `"Aksi"` di dalam Grid/Tabel**:
///    - Jika sebuah baris tabel memiliki **lebih dari 1 tombol aksi (`>= 2` aksi)**,
///      wajib diringkas menggunakan menu kebab [AksiBarisMenu] agar kolom `"Aksi"`
///      hemat ruang dan tidak memicu salah tekan di layar sentuh.
/// 2. **Larangan Kebab Tunggal (Single-Item Kebab)**:
///    - Jika daftar [aksi] pada suatu baris atau komponen **hanya memiliki 1 aksi**
///      (`aksi.length == 1`) dan [tampilLangsungJikaTunggal] bernilai `true` (default),
///      maka [AksiBarisMenu] **TIDAK** menampilkan tombol titik tiga (`...`), melainkan
///      langsung menampilkan tombol aksi tersebut secara terbuka ([IconButton] kompak di
///      dalam sel tabel sempit, atau [OutlinedButton.icon] / [FilledButton.icon] bila
///      di luar sel sempit).
/// 3. **Larangan Menyembunyikan `Simpan` / `Batal` di dalam Kebab**:
///    - Apabila terdapat item [AksiBaris] yang merupakan aksi terminal (`Simpan`, `Batal`,
///      `Tutup`, `Kembali`, `Terapkan`), item tersebut otomatis dikeluarkan dari popup
///      kebab dan dirender langsung sebagai tombol yang terlihat jelas.
class AksiBarisMenu extends StatelessWidget {
  final List<AksiBaris> aksi;

  /// Tooltip tombolnya; dibiarkan dapat diganti karena beberapa daftar memuat
  /// dokumen, bukan "data".
  final String tooltip;

  /// Bila `true` (default sesuai ATURAN MUTLAK 14), ketika hanya ada 1 aksi di dalam
  /// daftar [aksi], widget merender tombol langsung tanpa membungkusnya ke dalam kebab (`...`).
  final bool tampilLangsungJikaTunggal;

  /// Bila `true`, saat merender 1 aksi secara langsung akan selalu menampilkan teks label
  /// ([OutlinedButton.icon] / [FilledButton.icon]). Bila `false` (default untuk baris tabel),
  /// otomatis menyesuaikan dengan lebar kontainer (`LayoutBuilder`).
  final bool paksaBerlabelJikaTunggal;

  const AksiBarisMenu({
    super.key,
    required this.aksi,
    this.tooltip = 'Aksi lain',
    this.tampilLangsungJikaTunggal = true,
    this.paksaBerlabelJikaTunggal = false,
  });

  @override
  Widget build(BuildContext context) {
    final tersedia = aksi.where((a) => a.onTap != null).toList();
    if (tersedia.isEmpty) {
      // Tidak ada satu pun aksi yang dapat dipakai -- tombolnya tidak
      // ditampilkan sama sekali daripada membuka menu kosong.
      return const SizedBox.shrink();
    }

    // Pisahkan aksi terminal (Simpan / Batal / Tutup / Kembali / Terapkan)
    // karena ATURAN MUTLAK 14 & 16 melarang keras menaruhnya di dalam kebab.
    final terminal = aksi.where((a) => a.adalahAksiTerminal).toList();
    final nonTerminal = aksi.where((a) => !a.adalahAksiTerminal).toList();

    if (terminal.isNotEmpty && nonTerminal.isEmpty) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in terminal) _bangunTombolLangsung(context, a, berlabel: true),
        ],
      );
    }

    // ATURAN MUTLAK 14: Jika hanya ada 1 aksi, jangan gunakan kebab menu!
    if (tampilLangsungJikaTunggal && aksi.length == 1) {
      final tunggal = aksi.first;
      if (paksaBerlabelJikaTunggal) {
        return _bangunTombolLangsung(context, tunggal, berlabel: true);
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          // Di dalam sel tabel "Aksi" yang lebarnya sempit (<= 110px), gunakan IconButton
          // ber-tooltip agar tidak memicu overflow; di luar tabel gunakan tombol berlabel.
          final sempit = constraints.maxWidth.isFinite && constraints.maxWidth <= 110;
          return _bangunTombolLangsung(context, tunggal, berlabel: !sempit);
        },
      );
    }

    final warna = Theme.of(context).colorScheme;
    final daftarMenu = nonTerminal.isEmpty ? aksi : nonTerminal;
    final popup = PopupMenuButton<AksiBaris>(
      tooltip: tooltip,
      icon: const Icon(Icons.more_horiz, size: 20),
      position: PopupMenuPosition.under,
      onSelected: (a) => a.onTap?.call(),
      itemBuilder: (context) {
        final item = <PopupMenuEntry<AksiBaris>>[];
        final biasa = daftarMenu.where((a) => !a.merusak).toList();
        final merusak = daftarMenu.where((a) => a.merusak).toList();
        for (final a in biasa) {
          item.add(_butir(a, warna));
        }
        // Pemisah hanya bila memang ada keduanya; menu yang isinya cuma satu
        // kelompok tidak perlu garis yang tak memisahkan apa pun.
        if (biasa.isNotEmpty && merusak.isNotEmpty) {
          item.add(const PopupMenuDivider());
        }
        for (final a in merusak) {
          item.add(_butir(a, warna));
        }
        return item;
      },
    );

    if (terminal.isEmpty) {
      return popup;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final a in terminal) _bangunTombolLangsung(context, a, berlabel: true),
        popup,
      ],
    );
  }

  Widget _bangunTombolLangsung(
    BuildContext context,
    AksiBaris a, {
    required bool berlabel,
  }) {
    final warna = Theme.of(context).colorScheme;
    final l = a.label.trim().toLowerCase();
    final adalahSimpanAtauTerapkan =
        a.utama || l == 'simpan' || l.startsWith('simpan ') || l == 'terapkan';
    final adalahBatalAtauTutup =
        l == 'batal' || l == 'tutup' || l.startsWith('tutup ') || l == 'kembali';

    if (!berlabel) {
      return IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: a.label,
        onPressed: a.onTap,
        icon: Icon(
          a.ikon,
          size: 18,
          color: a.merusak ? warna.error : null,
        ),
      );
    }

    if (adalahSimpanAtauTerapkan) {
      return FilledButton.icon(
        onPressed: a.onTap,
        icon: Icon(a.ikon, size: 17),
        label: Text(a.label),
      );
    }

    if (adalahBatalAtauTutup) {
      return OutlinedButton.icon(
        onPressed: a.onTap,
        icon: Icon(a.ikon, size: 17),
        label: Text(a.label),
      );
    }

    if (a.merusak) {
      return OutlinedButton.icon(
        onPressed: a.onTap,
        icon: Icon(a.ikon, size: 17, color: warna.error),
        label: Text(a.label, style: TextStyle(color: warna.error)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: warna.error.withValues(alpha: 0.5)),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: a.onTap,
      icon: Icon(a.ikon, size: 17),
      label: Text(a.label),
    );
  }

  PopupMenuItem<AksiBaris> _butir(AksiBaris a, ColorScheme warna) {
    final aktif = a.onTap != null;
    final warnaIsi = !aktif
        ? warna.onSurface.withValues(alpha: 0.38)
        : (a.merusak ? warna.error : warna.onSurface);
    return PopupMenuItem<AksiBaris>(
      value: a,
      enabled: aktif,
      height: 40,
      child: Row(
        children: [
          Icon(a.ikon, size: 18, color: warnaIsi),
          const SizedBox(width: 12),
          Flexible(
            child: Text(a.label, style: TextStyle(fontSize: 13, color: warnaIsi)),
          ),
        ],
      ),
    );
  }
}

/// Bilah Aksi Toolbar Adaptif (Header / Filter / Sub-Tab) sesuai **ATURAN MUTLAK 14 & 16**
/// di `/docs/AGENTS.md`:
///
/// 1. **Tampilkan 3, 4, s/d 5 Tombol Utama Terlebih Dahulu (Sesuai Lebar Layar)**:
///    - Layar Sangat Lebar (`>= 1280px`): Menampilkan **5 tombol** utama secara langsung.
///    - Layar Desktop Standar (`>= 900px`): Menampilkan **4 tombol** utama secara langsung.
///    - Layar Tablet / Menengah (`>= 600px`): Menampilkan **3 tombol** utama secara langsung.
///    - Layar Sempit / Ponsel (`< 600px`): Menampilkan **2–3 tombol** utama secara langsung.
/// 2. **Selebihnya Ditaruh di Menu Kebab (`...`) pada Posisi Paling Kanan**:
///    - Hanya tombol urutan ke-`(N+1)` dan seterusnya yang dimasukkan ke dalam satu tombol
///      kebab (`...`) di ujung paling kanan.
///    - Apabila sisa tombol hanya 1 buah dan tidak menghemat ruang bila dijadikan kebab,
///      maka tombol tersebut ditampilkan langsung (mencegah kebab berisi 1 item).
/// 3. **Tombol `Simpan` / `Batal` Tidak Boleh Masuk Kebab**:
///    - Seluruh aksi dengan label `Simpan*`, `Batal`, `Tutup`, `Kembali`, atau `Terapkan`
///      selalu diprioritaskan tampil langsung di luar menu kebab.
class AksiToolbarMenu extends StatelessWidget {
  final List<AksiBaris> aksi;
  final String tooltip;

  /// Batas eksplisit jumlah tombol yang tampil langsung di luar kebab.
  /// Bila `null`, dihitung otomatis berdasarkan lebar layar (`3`, `4`, atau `5` tombol).
  final int? maksTampilLangsung;

  /// Bila `true`, digunakan di dalam `AppBar.actions` mobile sehingga memakai gaya kompak.
  final bool modeAppBarMobile;

  const AksiToolbarMenu({
    super.key,
    required this.aksi,
    this.tooltip = 'Aksi lainnya',
    this.maksTampilLangsung,
    this.modeAppBarMobile = false,
  });

  static int hitungBatasTampilUntukLebar(double lebarLayar, {bool mobileAppBar = false}) {
    if (mobileAppBar) {
      return lebarLayar >= 480 ? 3 : 2;
    }
    if (lebarLayar >= 1280) return 5;
    if (lebarLayar >= 900) return 4;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final aktifAtauTampil = aksi.where((a) => a.onTap != null || a.adalahAksiTerminal).toList();
    if (aktifAtauTampil.isEmpty) {
      return const SizedBox.shrink();
    }

    final lebarLayar = MediaQuery.sizeOf(context).width;
    final batas = maksTampilLangsung ??
        hitungBatasTampilUntukLebar(lebarLayar, mobileAppBar: modeAppBarMobile);

    // Pisahkan aksi terminal (Simpan / Batal / Tutup / Kembali / Terapkan) agar
    // TIDAK PERNAH masuk ke dalam kebab menu.
    final wajibTampil = <AksiBaris>[];
    final kandidatBiasa = <AksiBaris>[];
    for (final a in aksi) {
      if (a.adalahAksiTerminal) {
        wajibTampil.add(a);
      } else {
        kandidatBiasa.add(a);
      }
    }

    final sisaSlot = (batas - wajibTampil.length).clamp(0, kandidatBiasa.length);
    List<AksiBaris> tampilLangsung;
    List<AksiBaris> masukKebab;

    if (kandidatBiasa.length <= sisaSlot || kandidatBiasa.length == sisaSlot + 1) {
      // Jika semua muat, atau sisanya hanya 1 tombol (sehingga membuat kebab hanya berisi 1 item),
      // tampilkan semuanya secara langsung tanpa kebab!
      tampilLangsung = [...wajibTampil, ...kandidatBiasa];
      masukKebab = const [];
    } else {
      tampilLangsung = [
        ...wajibTampil,
        ...kandidatBiasa.take(sisaSlot),
      ];
      masukKebab = kandidatBiasa.skip(sisaSlot).toList();
    }

    if (modeAppBarMobile) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in tampilLangsung)
            IconButton(
              tooltip: a.label,
              onPressed: a.onTap,
              icon: Icon(a.ikon, size: 20),
            ),
          if (masukKebab.isNotEmpty)
            AksiBarisMenu(
              tooltip: tooltip,
              aksi: masukKebab,
              tampilLangsungJikaTunggal: false,
            ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < tampilLangsung.length; i++)
          _bangunTombolToolbar(context, tampilLangsung[i], urutanPertama: i == 0),
        if (masukKebab.isNotEmpty)
          // Menu kebab ditempatkan di posisi PALING KANAN untuk menampung sisa aksi sekunder.
          AksiBarisMenu(
            tooltip: tooltip,
            aksi: masukKebab,
            tampilLangsungJikaTunggal: false,
          ),
      ],
    );
  }

  Widget _bangunTombolToolbar(
    BuildContext context,
    AksiBaris a, {
    required bool urutanPertama,
  }) {
    final warna = Theme.of(context).colorScheme;
    final l = a.label.trim().toLowerCase();
    final adalahPrimer = a.utama ||
        l == 'simpan' ||
        l.startsWith('simpan ') ||
        l.startsWith('tambah ') ||
        l == 'terapkan';

    if (a.merusak) {
      return OutlinedButton.icon(
        onPressed: a.onTap,
        icon: Icon(a.ikon, size: 17, color: warna.error),
        label: Text(a.label, style: TextStyle(color: warna.error)),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: warna.error.withValues(alpha: 0.5)),
        ),
      );
    }

    if (adalahPrimer) {
      return FilledButton.icon(
        onPressed: a.onTap,
        icon: Icon(a.ikon, size: 17),
        label: Text(a.label),
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
      );
    }

    return OutlinedButton.icon(
      onPressed: a.onTap,
      icon: Icon(a.ikon, size: 17),
      label: Text(a.label),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}
