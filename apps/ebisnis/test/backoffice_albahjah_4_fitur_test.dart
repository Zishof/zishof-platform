import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/simpan_berkas_helper.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:ebisnis/widgets/workspace_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Temuan 4: SimpanBerkasHelper bebas rename & jaga ekstensi', () {
    test('bersihkanNamaSaran menghapus karakter ilegal & memberi ekstensi', () {
      expect(
        SimpanBerkasHelper.bersihkanNamaSaran(
          'Laporan: Kasir/Nov*2026?',
          allowedExtensions: const ['xlsx'],
        ),
        'Laporan_ Kasir_Nov_2026_.xlsx',
      );
      expect(
        SimpanBerkasHelper.bersihkanNamaSaran(
          '   ',
          allowedExtensions: const ['pdf'],
        ),
        'berkas_unduhan.pdf',
      );
    });

    test('pastikanEkstensiPath menjaga ekstensi saat pengguna rename nama file',
        () {
      expect(
        SimpanBerkasHelper.pastikanEkstensiPath(
          r'D:\Laporan Toko\Rekap Penjualan Santri Nov',
          allowedExtensions: const ['xlsx'],
        ),
        r'D:\Laporan Toko\Rekap Penjualan Santri Nov.xlsx',
      );
      expect(
        SimpanBerkasHelper.pastikanEkstensiPath(
          r'D:\Laporan Toko\Rekap_Manual.XLSX',
          allowedExtensions: const ['xlsx'],
        ),
        r'D:\Laporan Toko\Rekap_Manual.XLSX',
      );
      expect(
        SimpanBerkasHelper.pastikanEkstensiPath(
          'content://com.android.externalstorage.documents/document/primary%3ARekap',
          allowedExtensions: const ['pdf'],
        ),
        'content://com.android.externalstorage.documents/document/primary%3ARekap',
      );
    });

    test(
        'Penjaga statis: tidak ada lagi pemanggilan FilePicker.platform.saveFile di luar SimpanBerkasHelper',
        () {
      final dir = Directory('lib');
      final pelanggar = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll(r'\', '/');
        if (rel.endsWith('lib/services/simpan_berkas_helper.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('FilePicker.platform.saveFile')) {
          pelanggar.add(rel);
        }
      }
      expect(
        pelanggar,
        isEmpty,
        reason:
            'Seluruh alur simpan/download berkas wajib memakai SimpanBerkasHelper agar di Windows bebas rename tanpa blokir OFN_FILEMUSTEXIST: ${pelanggar.join(', ')}',
      );
    });
  });

  group('Temuan 1 & 2: Model Kategori Member Kasir & Unit Sivitas', () {
    test('Kategori.fromJson membaca flag defaultKasir, kategoriSivitas, dipilih',
        () {
      final umum = Kategori.fromJson({
        'id': 5,
        'nama': 'Umum',
        'wajibHp': true,
        'wajibEmail': false,
        'defaultKasir': true,
        'kategoriSivitas': false,
      });
      expect(umum.id, 5);
      expect(umum.nama, 'Umum');
      expect(umum.defaultKasir, isTrue);
      expect(umum.kategoriSivitas, isFalse);
      expect(umum.wajibHp, isTrue);

      final santri = Kategori.fromJson({
        'id': 3,
        'nama': 'Siswa',
        'wajibHp': false,
        'defaultKasir': false,
        'kategoriSivitas': true,
      });
      expect(santri.kategoriSivitas, isTrue);
      expect(santri.defaultKasir, isFalse);
      expect(santri.wajibHp, isFalse);

      final biasa = Kategori.fromJson({
        'id': 1,
        'nama': 'Biasa',
        'dipilih': true,
      });
      expect(biasa.dipilih, isTrue);
    });

    test('Anggota.fromJson membaca tipeNama dan unit pesantren/sekolah', () {
      final a = Anggota.fromJson({
        'id': 101,
        'nama': 'Sazkia Khoiru',
        'kode': 'SISWA-8821',
        'kodeIdentitas': 'SISWA-8821',
        'tipeAnggotaKoperasiId': 3,
        'tipeNama': 'Siswa',
        'unit': 'Pesantren Tahfidz Al Bahjah',
        'wajibPin': false,
        'minSaldo': 0,
      });
      expect(a.nama, 'Sazkia Khoiru');
      expect(a.tipeNama, 'Siswa');
      expect(a.unit, 'Pesantren Tahfidz Al Bahjah');
    });
  });

  group('Temuan 3: Multi-Tab Workspace Controller & AppShell', () {
    setUp(() {
      resetWorkspaceTabsEBisnis();
      Sesi.instance.reset();
    });

    tearDown(() {
      resetWorkspaceTabsEBisnis();
      Sesi.instance.reset();
    });

    test(
        'WorkspaceTabController mengelola buka, pindah, tutup, tutup lainnya, dan batas tab',
        () {
      final ctrl = WorkspaceTabController<String>(maxTabs: 4);
      ctrl.ensureInitialized('home');
      expect(ctrl.openIds, ['home']);
      expect(ctrl.pinnedId, 'home');
      expect(ctrl.activeId, 'home');

      ctrl.activateOrOpen('pelanggan');
      ctrl.activateOrOpen('produk');
      ctrl.activateOrOpen('laporan');
      expect(ctrl.openIds, ['home', 'pelanggan', 'produk', 'laporan']);
      expect(ctrl.activeId, 'laporan');

      // Membuka tab ke-5 saat maxTabs=4 menggusur tab non-pinned tertua yang tidak aktif ('pelanggan').
      ctrl.activateOrOpen('opname');
      expect(ctrl.openIds, ['home', 'produk', 'laporan', 'opname']);
      expect(ctrl.activeId, 'opname');

      // Tab tersemat ('home') tidak dapat ditutup.
      ctrl.closeTab('home');
      expect(ctrl.openIds.first, 'home');

      // Menutup tab aktif mengaktifkan tab tetangga sebelumnya.
      final setelahTutup = ctrl.closeTab('opname');
      expect(setelahTutup, 'laporan');
      expect(ctrl.activeId, 'laporan');

      // Tutup tab lainnya menyisakan tab pinned + tab yang dipertahankan.
      ctrl.closeOthers('produk');
      expect(ctrl.openIds, ['home', 'produk']);
      expect(ctrl.activeId, 'produk');

      // Tutup semua tab yang dapat ditutup kembali ke tab utama.
      ctrl.closeAllClosable();
      expect(ctrl.openIds, ['home']);
      expect(ctrl.activeId, 'home');
    });

    testWidgets(
        'WorkspaceTabBar merender tab terbuka, mempertahankan input di IndexedStack, dan menutup tab via [x]',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = WorkspaceTabController<String>(maxTabs: 8)
        ..ensureInitialized('home');
      final ketikanPelanggan = TextEditingController();
      addTearDown(ketikanPelanggan.dispose);

      Widget bangunUji() {
        return MaterialApp(
          home: AnimatedBuilder(
            animation: ctrl,
            builder: (context, _) {
              final tabs = ctrl.openIds
                  .map((id) => WorkspaceTabItem<String>(
                        id: id,
                        label: id == 'home'
                            ? 'Home'
                            : (id == 'pelanggan' ? 'Pelanggan' : 'Produk'),
                        icon: Icons.tab,
                        pinned: id == ctrl.pinnedId,
                      ))
                  .toList();
              return Scaffold(
                body: Column(
                  children: [
                    WorkspaceTabBar<String>(
                      tabs: tabs,
                      activeId: ctrl.activeId ?? 'home',
                      onSelect: ctrl.activateOrOpen,
                      onClose: ctrl.closeTab,
                      onCloseOthers: ctrl.closeOthers,
                      onCloseAll: ctrl.closeAllClosable,
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: ctrl.activeIndex,
                        children: ctrl.openIds.map((id) {
                          if (id == 'pelanggan') {
                            return Center(
                              child: TextField(
                                key: const Key('input-cari-pelanggan'),
                                controller: ketikanPelanggan,
                              ),
                            );
                          }
                          return Center(child: Text('Halaman $id'));
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(bangunUji());
      expect(find.byKey(const Key('workspace-tab-bar')), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      // Tab Home tersemat tidak punya tombol close.
      expect(
          find.byKey(const ValueKey('close-workspace-tab-home')), findsNothing);

      // Buka Pelanggan, ketik pencarian "sazkia khoiru", lalu buka Produk.
      ctrl.activateOrOpen('pelanggan');
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('input-cari-pelanggan')), 'sazkia khoiru');
      await tester.pump();

      ctrl.activateOrOpen('produk');
      await tester.pumpAndSettle();
      expect(find.text('Pelanggan'), findsOneWidget);
      expect(find.text('Produk'), findsOneWidget);

      // Klik kembali ke tab Pelanggan: ketikan pencarian tetap terjaga utuh!
      await tester.tap(find.text('Pelanggan'));
      await tester.pumpAndSettle();
      expect(ketikanPelanggan.text, 'sazkia khoiru');

      // Tutup tab Produk melalui tombol [x].
      await tester.tap(find.byKey(const ValueKey('close-workspace-tab-produk')));
      await tester.pumpAndSettle();
      expect(find.text('Produk'), findsNothing);
      expect(ketikanPelanggan.text, 'sazkia khoiru');
    });
  });
}
