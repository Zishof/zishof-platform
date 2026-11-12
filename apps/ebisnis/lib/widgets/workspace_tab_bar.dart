import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Metadata satu tab pada bilah **Multi-Tab Workspace** (`WorkspaceTabBar`).
///
/// Dirancang generik menggunakan kunci bertipe [T] (di eBisnis dipakai untuk
/// `MenuEBisnis`) agar tidak terjadi siklus impor antar widget kerangka dan
/// mudah diuji secara terisolasi.
class WorkspaceTabItem<T> {
  final T id;
  final String label;
  final IconData icon;
  final bool pinned;

  const WorkspaceTabItem({
    required this.id,
    required this.label,
    required this.icon,
    this.pinned = false,
  });
}

/// Pengelola status daftar tab fitur yang sedang dibuka pengguna pada sesi
/// kerja Desktop (`Multi-Tab Workspace`).
///
/// Arsitektur & Tujuan Bisnis:
/// 1. Ketika pengguna Back Office mengeksplorasi beberapa menu sekaligus
///    (misalnya membuka *Dashboard*, lalu *Pelanggan*, *Produk*, *Stok Opname*,
///    dan *Laporan Transaksi*), setiap menu yang dibuka ditambahkan ke daftar
///    [openIds] dan tetap hidup di memori (`IndexedStack`) sampai pengguna
///    menekan tombol tutup `[×]` pada tab tersebut.
/// 2. Hasilnya, ketikan pencarian, filter tanggal, posisi gulir tabel, maupun
///    sub-tab yang sedang dibuka **tidak hilang/tertutup** saat berpindah menu
///    (setara dengan perilaku deretan tab `[Home] [Penilaian ×] [Laporan ×]`
///    pada portal akademik eCampus).
/// 3. Tab pertama ([pinnedId], seperti *Dashboard* atau *Kasir/POS*) bersifat
///    tersemat (*pinned*, tanpa tombol `[×]`) sehingga selalu ada minimal satu
///    halaman utama yang aktif.
/// 4. Jumlah maksimum tab terbuka dibatasi oleh [maxTabs] (bawaan 12) demi
///    menjaga konsumsi memori perangkat tetap ringan; bila penuh, tab tidak
///    tersemat paling lama yang sedang tidak aktif akan dilepas otomatis.
class WorkspaceTabController<T> extends ChangeNotifier {
  final int maxTabs;
  final List<T> _openIds = <T>[];
  T? _pinnedId;
  T? _activeId;

  WorkspaceTabController({this.maxTabs = 12}) : assert(maxTabs >= 2);

  /// Daftar seluruh tab yang sedang terbuka sesuai urutan pembukaan.
  List<T> get openIds => List<T>.unmodifiable(_openIds);

  /// Identitas tab utama yang tersemat di urutan paling kiri (tidak memiliki
  /// tombol tutup `[×]`).
  T? get pinnedId => _pinnedId;

  /// Identitas tab yang sedang aktif ditampilkan.
  T? get activeId => _activeId;

  /// Indeks tab aktif di dalam [openIds] (`0` bila belum diinisialisasi).
  int get activeIndex {
    if (_activeId == null) return 0;
    final idx = _openIds.indexOf(_activeId as T);
    return idx < 0 ? 0 : idx;
  }

  /// Memastikan tab beranda ([homeId]) terdaftar sebagai tab tersemat pertama
  /// tanpa memicu `notifyListeners()` yang tidak perlu bila sudah sinkron.
  void ensureInitialized(T homeId, {T? initialActiveId}) {
    var berubah = false;
    if (_pinnedId == null) {
      _pinnedId = homeId;
      if (!_openIds.contains(homeId)) {
        _openIds.insert(0, homeId);
      }
      berubah = true;
    } else if (!_openIds.contains(_pinnedId as T)) {
      _openIds.insert(0, _pinnedId as T);
      berubah = true;
    }

    final targetAktif = initialActiveId ?? _activeId ?? homeId;
    if (!_openIds.contains(targetAktif)) {
      _sisipkanTabDenganBatas(targetAktif);
      berubah = true;
    }
    if (_activeId != targetAktif) {
      _activeId = targetAktif;
      berubah = true;
    }
    if (berubah) {
      notifyListeners();
    }
  }

  /// Membuka tab [id] bila belum ada di bilah tab, lalu menjadikannya tab aktif.
  void activateOrOpen(T id) {
    var berubah = false;
    if (!_openIds.contains(id)) {
      _sisipkanTabDenganBatas(id);
      berubah = true;
    }
    if (_activeId != id) {
      _activeId = id;
      berubah = true;
    }
    if (berubah) {
      notifyListeners();
    }
  }

  void _sisipkanTabDenganBatas(T id) {
    if (_openIds.length >= maxTabs) {
      for (var i = 0; i < _openIds.length; i++) {
        final kandidat = _openIds[i];
        if (kandidat != _pinnedId && kandidat != _activeId) {
          _openIds.removeAt(i);
          break;
        }
      }
    }
    _openIds.add(id);
  }

  /// Menutup satu tab [id] (kecuali tab tersemat [pinnedId]).
  ///
  /// Mengembalikan identitas tab yang menjadi aktif setelah penutupan, atau
  /// `null` bila tab tersebut tersemat / tidak ditemukan.
  T? closeTab(T id) {
    if (id == _pinnedId) return _activeId;
    final idx = _openIds.indexOf(id);
    if (idx < 0) return _activeId;
    _openIds.removeAt(idx);
    if (_openIds.isEmpty && _pinnedId != null) {
      _openIds.add(_pinnedId as T);
    }
    if (_activeId == id && _openIds.isNotEmpty) {
      final idxPengganti = (idx - 1).clamp(0, _openIds.length - 1);
      _activeId = _openIds[idxPengganti];
    }
    notifyListeners();
    return _activeId;
  }

  /// Menutup seluruh tab selain [keepId] dan tab utama [pinnedId], lalu
  /// mengaktifkan [keepId].
  T? closeOthers(T keepId) {
    _openIds.removeWhere((e) => e != _pinnedId && e != keepId);
    if (!_openIds.contains(keepId)) {
      _openIds.add(keepId);
    }
    _activeId = keepId;
    notifyListeners();
    return _activeId;
  }

  /// Menutup seluruh tab yang dapat ditutup dan kembali ke tab utama [pinnedId].
  T? closeAllClosable() {
    _openIds.removeWhere((e) => e != _pinnedId);
    if (_openIds.isNotEmpty) {
      _activeId = _openIds.first;
    }
    notifyListeners();
    return _activeId;
  }

  /// Menghapus seluruh daftar tab saat pengguna keluar (logout) agar sesi akun
  /// berikutnya bersih.
  void reset() {
    if (_openIds.isEmpty && _pinnedId == null && _activeId == null) return;
    _openIds.clear();
    _pinnedId = null;
    _activeId = null;
    notifyListeners();
  }
}

/// Bilah daftar tab horizontal (`Multi-Tab Workspace Bar`) yang diletakkan
/// tepat di bawah bilah status atas (`_AppTopbar`) pada tampilan Desktop.
///
/// Fitur interaksi:
/// - Klik tab untuk berpindah instan antar fitur tanpa menutup halaman lain.
/// - Klik tombol `[×]` atau klik tengah mouse (*middle-click*) untuk menutup tab.
/// - Tombol menu cepat di sisi kanan (ketika ada > 1 tab terbuka) untuk
///   **Tutup Tab Lainnya** atau **Tutup Semua Tab**.
class WorkspaceTabBar<T> extends StatefulWidget {
  final List<WorkspaceTabItem<T>> tabs;
  final T activeId;
  final ValueChanged<T> onSelect;
  final ValueChanged<T> onClose;
  final ValueChanged<T>? onCloseOthers;
  final VoidCallback? onCloseAll;

  const WorkspaceTabBar({
    super.key,
    required this.tabs,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    this.onCloseOthers,
    this.onCloseAll,
  });

  @override
  State<WorkspaceTabBar<T>> createState() => _WorkspaceTabBarState<T>();
}

class _WorkspaceTabBarState<T> extends State<WorkspaceTabBar<T>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabs.isEmpty) return const SizedBox.shrink();
    final adaTabDapatDitutup = widget.tabs.any((t) => !t.pinned);
    final borderWarna = AppColors.borderOf(context);
    final latarStrip = AppColors.pageBgOf(context);

    return Container(
      key: const Key('workspace-tab-bar'),
      height: 40,
      decoration: BoxDecoration(
        color: latarStrip,
        border: Border(bottom: BorderSide(color: borderWarna)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              thickness: 3,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
                itemCount: widget.tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final tab = widget.tabs[index];
                  final aktif = tab.id == widget.activeId;
                  return _KartuTabWorkspace<T>(
                    item: tab,
                    aktif: aktif,
                    onTap: () => widget.onSelect(tab.id),
                    onClose: tab.pinned ? null : () => widget.onClose(tab.id),
                  );
                },
              ),
            ),
          ),
          if (adaTabDapatDitutup &&
              (widget.onCloseOthers != null || widget.onCloseAll != null))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: PopupMenuButton<String>(
                key: const Key('workspace-tab-overflow'),
                tooltip: 'Kelola tab terbuka',
                icon: Icon(
                  Icons.tab_unselected_outlined,
                  size: 17,
                  color: AppColors.textSecondaryOf(context),
                ),
                onSelected: (aksi) {
                  if (aksi == 'tutup_lainnya') {
                    widget.onCloseOthers?.call(widget.activeId);
                  } else if (aksi == 'tutup_semua') {
                    widget.onCloseAll?.call();
                  }
                },
                itemBuilder: (_) => [
                  if (widget.onCloseOthers != null)
                    const PopupMenuItem<String>(
                      value: 'tutup_lainnya',
                      child: Row(
                        children: [
                          Icon(Icons.cleaning_services_outlined, size: 17),
                          SizedBox(width: 8),
                          Text('Tutup Tab Lainnya'),
                        ],
                      ),
                    ),
                  if (widget.onCloseAll != null)
                    const PopupMenuItem<String>(
                      value: 'tutup_semua',
                      child: Row(
                        children: [
                          Icon(Icons.clear_all, size: 18),
                          SizedBox(width: 8),
                          Text('Tutup Semua Tab'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KartuTabWorkspace<T> extends StatefulWidget {
  final WorkspaceTabItem<T> item;
  final bool aktif;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _KartuTabWorkspace({
    required this.item,
    required this.aktif,
    required this.onTap,
    this.onClose,
  });

  @override
  State<_KartuTabWorkspace<T>> createState() => _KartuTabWorkspaceState<T>();
}

class _KartuTabWorkspaceState<T> extends State<_KartuTabWorkspace<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final aktif = widget.aktif;
    final warnaUtama = AppColors.primary;
    final warnaTeks = aktif
        ? warnaUtama
        : AppColors.textSecondaryOf(context);
    final latar = aktif
        ? AppColors.cardBgOf(context)
        : (_hover
            ? AppColors.cardBgOf(context).withValues(alpha: 0.72)
            : AppColors.cardBgOf(context).withValues(alpha: 0.42));
    final warnaBorder = aktif
        ? warnaUtama.withValues(alpha: 0.42)
        : AppColors.borderOf(context);

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kMiddleMouseButton &&
            widget.onClose != null) {
          widget.onClose!();
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(maxWidth: 230),
              padding: EdgeInsets.fromLTRB(
                11,
                0,
                widget.onClose != null ? 5 : 12,
                0,
              ),
              decoration: BoxDecoration(
                color: latar,
                border: Border(
                  top: BorderSide(
                    color: aktif ? warnaUtama : warnaBorder,
                    width: aktif ? 2.4 : 1,
                  ),
                  left: BorderSide(color: warnaBorder),
                  right: BorderSide(color: warnaBorder),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.item.pinned ? Icons.home_outlined : widget.item.icon,
                    size: 15,
                    color: warnaTeks,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                        color: warnaTeks,
                      ),
                    ),
                  ),
                  if (widget.onClose != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Tutup tab ${widget.item.label}',
                      child: InkResponse(
                        key: ValueKey('close-workspace-tab-${widget.item.id}'),
                        radius: 12,
                        onTap: widget.onClose,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: aktif
                                ? warnaUtama
                                : AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
