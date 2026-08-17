import 'dart:io';

import 'package:core_device/core_device.dart';
import 'package:core_hw/core_hw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../app_setting.dart';
import '../app_variant.dart';
import '../api_client.dart';
import '../services/pengaturan_laci.dart';
import '../services/pengaturan_nomor_struk.dart';
import '../services/pengaturan_pembayaran.dart';
import '../services/pengaturan_struk.dart';
import '../services/pengaturan_sesi_lokal.dart';
import '../services/pengaturan_update.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'login_screen.dart';
import 'pengaturan_server_screen.dart';
import 'hak_akses_screen.dart';
import 'konfigurasi/tab_screensaver.dart';
import 'konfigurasi/tab_impor_dbf.dart';
import 'konfigurasi/tab_riwayat_cetak.dart';
import 'konfigurasi/tab_sesi_kasir.dart';
import '../product_profile.dart';
import '../widgets/safe_state.dart';

/// Layar Konfigurasi (padanan konfigurasi.html/konfigurasi-renderer.js
/// Electron) -- 5 sub-tab: Identitas Mesin (lokal, core_device), Profil Toko
/// (server, `toko_profil_ambil`/`_simpan`), Akun Pengguna (server,
/// `pedagang_list`/`pedagang_ubah`/`akun_tambah`), Screensaver (server,
/// `layar_pelanggan_slide_*`/`layar_pelanggan_screensaver_config_*` --
/// slideshow gambar di Layar Pelanggan saat idle, lihat
/// `screens/konfigurasi/tab_screensaver.dart`), Alamat Server (lokal,
/// `FormAlamatServer` yg sama dgn `PengaturanServerScreen` -- bisa diubah
/// dari DALAM aplikasi tanpa perlu logout dulu). Bagian "Tampilan Aplikasi"
/// Electron (judul window/logo) sengaja TIDAK diporting -- itu chrome desktop,
/// tak ada padanan di HP. Tab ke-6 kondisional "Impor DBF" (migrasi legacy
/// INVENTORY CONTROL, `screens/konfigurasi/tab_impor_dbf.dart`) hanya muncul
/// di varian Inventory & Sales saat login sbg Pemilik Usaha Sales/Inventory.
class KonfigurasiScreen extends StatefulWidget {
  const KonfigurasiScreen({super.key});
  @override
  State<KonfigurasiScreen> createState() => _KonfigurasiScreenState();
}

class _KonfigurasiScreenState extends State<KonfigurasiScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Tab ke-6 "Impor DBF" (migrasi legacy INVENTORY CONTROL) HANYA untuk
  // varian Inventory & Sales DAN login sebagai Pemilik Usaha Sales/Inventory
  // (permintaan eksplisit; server tetap menegakkan ulang di si_import_legacy).
  // Dihitung sekali di initState -- actorType terikat sesi login, tidak
  // berubah selama layar ini hidup.
  late final bool _tampilkanImporDbf;
  late final bool _tampilkanRiwayatCetak;

  @override
  void initState() {
    super.initState();
    _tampilkanImporDbf = AppProductProfile.aktif.isInventorySales &&
        Sesi.instance.isPemilikSalesInventory;
    _tampilkanRiwayatCetak = AppProductProfile.aktif.isInventorySales &&
        (Sesi.instance.isPemilikSalesInventory || Sesi.instance.isAdmin);
    _tab = TabController(
        length:
            6 + (_tampilkanRiwayatCetak ? 1 : 0) + (_tampilkanImporDbf ? 1 : 0),
        vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await ApiClient.instance.hapusToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final tombolLogout = IconButton(
        icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Keluar');
    final warnaTeksSekunder = AppColors.textSecondaryOf(context);
    return AppShell(
      menuAktif: MenuEBisnis.konfigurasi,
      judul: 'Konfigurasi',
      subjudul:
          'Identitas mesin, profil toko, akun pengguna, dan alamat server',
      aksiHeader: tombolLogout,
      actionsAppBar: [tombolLogout],
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: warnaTeksSekunder,
            indicatorColor: AppColors.primary,
            tabs: [
              const Tab(text: 'Identitas Mesin'),
              const Tab(text: 'Profil Toko'),
              const Tab(text: 'Akun Pengguna'),
              const Tab(text: 'Screensaver'),
              const Tab(text: 'Alamat Server'),
              const Tab(text: 'Sesi Kasir'),
              if (_tampilkanRiwayatCetak) const Tab(text: 'Riwayat Cetak'),
              if (_tampilkanImporDbf) const Tab(text: 'Impor DBF'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              const _TabIdentitasMesin(),
              const _TabProfilToko(),
              const _TabAkunPengguna(),
              const TabScreensaver(),
              _TabAlamatServer(onUbah: _logout),
              const TabSesiKasir(),
              if (_tampilkanRiwayatCetak) const TabRiwayatCetak(),
              if (_tampilkanImporDbf) const TabImporDbf(),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Tab "Alamat Server" -- reuse [FormAlamatServer], TAPI "Simpan" di sini
/// (beda dari PengaturanServerScreen) memaksa keluar (logout) sekaligus
/// membersihkan seluruh stack navigasi ke LoginScreen, krn seluruh layar di
/// belakangnya (Kasir/Konfigurasi/dst) sudah terikat sesi server LAMA yang
/// baru saja diganti.
class _TabAlamatServer extends StatelessWidget {
  final Future<void> Function() onUbah;
  const _TabAlamatServer({required this.onUbah});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const AppInfoBanner(
          icon: Icons.logout_outlined,
          color: AppColors.warning,
          text:
              'Mengubah alamat server akan mengeluarkan Anda dari akun saat ini. Setelah tersimpan, masuk kembali di server yang baru.',
        ),
        const SizedBox(height: 16),
        AppFormSection(
          judul: 'Alamat Server',
          deskripsi:
              'Atur host, context path, dan protokol koneksi aplikasi POS ini.',
          children: [
            FormAlamatServer(labelSimpan: 'Simpan & Keluar', onSelesai: onUbah),
          ],
        ),
      ],
    );
  }
}

class _TabIdentitasMesin extends StatefulWidget {
  const _TabIdentitasMesin();
  @override
  State<_TabIdentitasMesin> createState() => _TabIdentitasMesinState();
}

class _TabIdentitasMesinState extends State<_TabIdentitasMesin> {
  final _namaController = TextEditingController();
  final _timeoutSesiController = TextEditingController();
  final _kodeDeviceStrukController = TextEditingController();
  bool _memuat = true;
  bool _menyimpan = false;

  // Cash Drawer (Windows-only) -- lihat services/pengaturan_laci.dart.
  List<Printer> _daftarPrinter = [];
  String? _printerLaci;
  bool _pinAlternatif = false;
  bool _menyimpanLaci = false;
  bool _tesLaciBerjalan = false;
  int? _caraBayarDefaultId;
  FormatNomorStruk _formatNomorStruk = FormatNomorStruk.defaultPos;
  bool _menyimpanPembayaran = false;
  bool _updateOtomatis = true;

  @override
  void initState() {
    super.initState();
    _kodeDeviceStrukController.addListener(_segarkanContohNomorStruk);
    _muat();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _timeoutSesiController.dispose();
    _kodeDeviceStrukController.removeListener(_segarkanContohNomorStruk);
    _kodeDeviceStrukController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    await IdentitasMesin.instance.muat();
    await PengaturanPembayaran.instance.muat();
    await PengaturanNomorStruk.instance.muat();
    await PengaturanSesiLokal.instance.muat();
    await PengaturanUpdate.instance.muat();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await PengaturanLaci.instance.muat();
      try {
        _daftarPrinter = await Printing.listPrinters();
      } catch (_) {
        _daftarPrinter = [];
      }
    }
    if (mounted) {
      setStateIfMounted(() {
        _namaController.text = IdentitasMesin.instance.namaMesin;
        _printerLaci = PengaturanLaci.instance.namaPrinter;
        _pinAlternatif = PengaturanLaci.instance.pinAlternatif;
        _caraBayarDefaultId = PengaturanPembayaran.instance.caraBayarDefaultId;
        _formatNomorStruk = PengaturanNomorStruk.instance.format;
        _kodeDeviceStrukController.text =
            PengaturanNomorStruk.instance.kodeDeviceKustom ??
                PengaturanNomorStruk.kodeDeviceDariId(
                    IdentitasMesin.instance.idMesin);
        _timeoutSesiController.text =
            PengaturanSesiLokal.instance.timeoutMenit.toString();
        _updateOtomatis = PengaturanUpdate.instance.otomatis;
        _memuat = false;
      });
    }
  }

  void _segarkanContohNomorStruk() {
    if (mounted) setStateIfMounted(() {});
  }

  String _contohNomorStruk(FormatNomorStruk format) {
    if (format != FormatNomorStruk.deviceTanggalUrut) return format.contoh;
    final kodeDevice = _kodeDeviceStrukController.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final kode = kodeDevice.isEmpty
        ? PengaturanNomorStruk.kodeDeviceDariId(IdentitasMesin.instance.idMesin)
        : kodeDevice;
    return '${kode}0608202600001';
  }

  Future<void> _simpan() async {
    setStateIfMounted(() => _menyimpan = true);
    await IdentitasMesin.instance.simpanNamaMesin(_namaController.text.trim());
    if (mounted) {
      setStateIfMounted(() => _menyimpan = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nama mesin tersimpan.')));
    }
  }

  Future<void> _simpanLaci() async {
    setStateIfMounted(() => _menyimpanLaci = true);
    await PengaturanLaci.instance
        .simpan(namaPrinter: _printerLaci, pinAlternatif: _pinAlternatif);
    if (mounted) {
      setStateIfMounted(() => _menyimpanLaci = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengaturan laci tersimpan.')));
    }
  }

  Future<void> _simpanPembayaran() async {
    final menit = int.tryParse(_timeoutSesiController.text.trim());
    if (menit == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Timeout sesi wajib diisi dalam angka menit.')));
      return;
    }

    setStateIfMounted(() => _menyimpanPembayaran = true);
    await PengaturanPembayaran.instance
        .simpan(caraBayarDefaultId: _caraBayarDefaultId);
    await PengaturanNomorStruk.instance.simpan(
      format: _formatNomorStruk,
      kodeDevice: _kodeDeviceStrukController.text,
    );
    await PengaturanSesiLokal.instance.simpanTimeoutMenit(menit);
    if (mounted) {
      setStateIfMounted(() {
        _menyimpanPembayaran = false;
        _kodeDeviceStrukController.text =
            PengaturanNomorStruk.instance.kodeDeviceKustom ??
                PengaturanNomorStruk.kodeDeviceDariId(
                    IdentitasMesin.instance.idMesin);
        _timeoutSesiController.text =
            PengaturanSesiLokal.instance.timeoutMenit.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Preferensi POS tersimpan. Timeout sesi: ${PengaturanSesiLokal.instance.timeoutMenit} menit.')));
    }
  }

  Future<void> _tesLaci() async {
    setStateIfMounted(() => _tesLaciBerjalan = true);
    try {
      await bukaLaciKasir(
          pinAlternatif: _pinAlternatif, namaPrinter: _printerLaci);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Perintah buka laci terkirim.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _tesLaciBerjalan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppFormSection(
          judul: 'Identitas Mesin',
          deskripsi:
              'Identitas fisik perangkat ini dikirim di setiap transaksi supaya laporan bisa membedakan mesin atau HP kasir yang dipakai.',
          children: [
            AppReadonlyField(
              label: 'ID Mesin',
              value: IdentitasMesin.instance.idMesin,
              helperText: 'Dibuat otomatis dan bersifat permanen.',
            ),
            AppFormTextField(
              label: 'Nama Mesin',
              controller: _namaController,
              hintText: 'mis. Kasir Depan',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTombolAksi(
                icon: Icons.save_outlined,
                label: 'Simpan',
                onPressed: _menyimpan ? null : _simpan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _pengaturanTema(context),
        const SizedBox(height: 16),
        AppFormSection(
          judul: 'Preferensi POS',
          deskripsi:
              'Atur pilihan awal di panel pembayaran. Preferensi ini hanya berlaku untuk perangkat ini.',
          children: [
            DropdownButtonFormField<int?>(
              value: Sesi.instance.caraBayar
                      .any((c) => c.id == _caraBayarDefaultId)
                  ? _caraBayarDefaultId
                  : null,
              dropdownColor: AppColors.cardBgOf(context),
              style: TextStyle(color: AppColors.textPrimaryOf(context)),
              decoration:
                  const InputDecoration(labelText: 'Metode Pembayaran Default'),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Otomatis (Tunai jika ada)')),
                ...Sesi.instance.caraBayar.map((c) =>
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.nama))),
              ],
              onChanged: (v) => setStateIfMounted(() {
                _caraBayarDefaultId = v;
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<FormatNomorStruk>(
              value: _formatNomorStruk,
              dropdownColor: AppColors.cardBgOf(context),
              style: TextStyle(color: AppColors.textPrimaryOf(context)),
              decoration:
                  const InputDecoration(labelText: 'Format Nomor Struk'),
              items: FormatNomorStruk.values
                  .map(
                    (format) => DropdownMenuItem(
                      value: format,
                      child: Text(
                          '${format.label} (${_contohNomorStruk(format)})'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setStateIfMounted(() {
                _formatNomorStruk = v ?? FormatNomorStruk.defaultPos;
              }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _kodeDeviceStrukController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                labelText: 'Kode Device Struk',
                helperText:
                    'Default dari ID Mesin. Dipakai pada format kode device + tanggal + nomor urut.',
                suffixIcon: IconButton(
                  tooltip: 'Kembalikan ke kode dari ID Mesin',
                  icon: const Icon(Icons.restore_outlined),
                  onPressed: () => setStateIfMounted(() {
                    _kodeDeviceStrukController.text =
                        PengaturanNomorStruk.kodeDeviceDariId(
                            IdentitasMesin.instance.idMesin);
                  }),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _timeoutSesiController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Timeout Sesi Lokal (menit)',
                helperText:
                    'Setelah aplikasi ditutup/background melebihi nilai ini, pengguna wajib login ulang.',
                suffixText: 'menit',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTombolAksi(
                icon: Icons.save_outlined,
                label: _menyimpanPembayaran
                    ? 'Menyimpan...'
                    : 'Simpan Preferensi POS',
                onPressed: _menyimpanPembayaran ? null : _simpanPembayaran,
              ),
            ),
          ],
        ),
        if (defaultTargetPlatform == TargetPlatform.windows) ...[
          const SizedBox(height: 16),
          AppFormSection(
            judul: 'Pembaruan Aplikasi',
            deskripsi:
                'Paket komponen diperiksa dan diverifikasi dari GitHub Releases. Aplikasi akan dibuka kembali setelah pemasangan.',
            children: [
              AppFormSwitchTile(
                title: 'Silent update otomatis',
                subtitle:
                    'Aktif secara default. Windows mungkin tetap meminta konfirmasi UAC jika aplikasi terpasang di Program Files.',
                value: _updateOtomatis,
                onChanged: (v) async {
                  await PengaturanUpdate.instance.simpanOtomatis(v);
                  if (mounted) setStateIfMounted(() => _updateOtomatis = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppFormSection(
            judul: 'Cash Drawer',
            deskripsi:
                'Laci kasir tersambung melalui printer struk thermal. Jika laci tidak terbuka, cek target printer atau coba pin alternatif.',
            children: [
              DropdownButtonFormField<String?>(
                value: _daftarPrinter.any((p) => p.name == _printerLaci)
                    ? _printerLaci
                    : null,
                dropdownColor: AppColors.cardBgOf(context),
                style: TextStyle(color: AppColors.textPrimaryOf(context)),
                decoration: const InputDecoration(labelText: 'Printer Laci'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('(Ikut printer default Windows)')),
                  ..._daftarPrinter.map((p) => DropdownMenuItem<String?>(
                      value: p.name,
                      child: Text(p.name + (p.isDefault ? ' (default)' : '')))),
                ],
                onChanged: (v) => setStateIfMounted(() => _printerLaci = v),
              ),
              const SizedBox(height: 14),
              AppFormSwitchTile(
                title: 'Pin Alternatif (Pin 5)',
                subtitle:
                    'Aktifkan kalau laci tidak terbuka dengan pengaturan pin biasa (Pin 2).',
                value: _pinAlternatif,
                onChanged: (v) => setStateIfMounted(() => _pinAlternatif = v),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: [
                  AppTombolAksi(
                    icon: Icons.save_outlined,
                    label: 'Simpan Pengaturan Laci',
                    warna: AppColors.teal,
                    onPressed: _menyimpanLaci ? null : _simpanLaci,
                  ),
                  AppTombolAksi(
                    icon: Icons.point_of_sale_outlined,
                    label: 'Tes Buka Laci',
                    warna: AppColors.warning,
                    onPressed: _tesLaciBerjalan ? null : _tesLaci,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Pemilih warna aksen aplikasi -- berlaku langsung (tanpa restart) krn
/// [AppThemeController.ubahWarna] mengubah [AppColors.primary] sekaligus
/// memberitahu `ValueListenableBuilder` di main.dart utk membangun ulang
/// `MaterialApp` dgn `ColorScheme.fromSeed` yang baru.
Widget _pengaturanTema(BuildContext context) {
  return ValueListenableBuilder<AppThemeWarna>(
    valueListenable: AppThemeController.instance.warna,
    builder: (context, warnaAktif, _) {
      return AppFormSection(
        judul: 'Tampilan',
        deskripsi:
            'Pilih warna aksen aplikasi untuk perangkat ini. Berlaku langsung di semua layar.',
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppThemeWarna.values.map((w) {
              final terpilih = w == warnaAktif;
              return InkWell(
                onTap: () => AppThemeController.instance.ubahWarna(w),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 84,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: terpilih ? w.warna : AppColors.borderOf(context),
                      width: terpilih ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: w.warna,
                          shape: BoxShape.circle,
                        ),
                        child: terpilih
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(w.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  terpilih ? FontWeight.w700 : FontWeight.w500,
                              color: AppColors.textPrimaryOf(context))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );
    },
  );
}

class _TabProfilToko extends StatefulWidget {
  const _TabProfilToko();
  @override
  State<_TabProfilToko> createState() => _TabProfilTokoState();
}

class _TabProfilTokoState extends State<_TabProfilToko> {
  bool _memuat = true;
  bool _menyimpan = false;
  bool _memilihLogo = false;
  bool _memilihLogoPriceTag = false;
  String? _error;
  bool _bolehUbah = false;
  bool _bolehTransaksiStokHabis = false;
  String? _logoStrukPath;
  String? _logoPriceTagPath;
  String _logoStrukMode = 'persegi';
  double _logoStrukSkala = 1;
  double _lebarKertasStrukMm = 80;
  double _marginKotakPriceTagMm = 2;
  final _kode = TextEditingController();
  final _nama = TextEditingController();
  final _alamat = TextEditingController();
  final _kota = TextEditingController();
  final _kodePos = TextEditingController();
  final _telp = TextEditingController();
  final _email = TextEditingController();
  final _picNama = TextEditingController();
  final _picHp = TextEditingController();
  final _npwp = TextEditingController();
  final _jamOperasional = TextEditingController();
  final _keterangan = TextEditingController();
  final _pesanTerimaKasih = TextEditingController();
  final _alasanTahan = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    for (final c in [
      _kode,
      _nama,
      _alamat,
      _kota,
      _kodePos,
      _telp,
      _email,
      _picNama,
      _picHp,
      _npwp,
      _jamOperasional,
      _keterangan,
      _pesanTerimaKasih,
      _alasanTahan
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      await PengaturanStruk.instance.muat();
      final hasil = await ApiClient.instance.aksi('toko_profil_ambil');
      final d = (hasil['data'] as Map<String, dynamic>?) ?? {};
      _kode.text = '${d['kode'] ?? ''}';
      _nama.text = '${d['nama'] ?? ''}';
      _alamat.text = '${d['alamat'] ?? ''}';
      _kota.text = '${d['kota'] ?? ''}';
      _kodePos.text = '${d['kodePos'] ?? ''}';
      _telp.text = '${d['telp'] ?? ''}';
      _email.text = '${d['email'] ?? ''}';
      _picNama.text = '${d['picNama'] ?? ''}';
      _picHp.text = '${d['picHp'] ?? ''}';
      _npwp.text = '${d['npwp'] ?? ''}';
      _jamOperasional.text = '${d['jamOperasional'] ?? ''}';
      _keterangan.text = '${d['keterangan'] ?? ''}';
      _pesanTerimaKasih.text = '${d['pesanTerimaKasih'] ?? ''}';
      _alasanTahan.text =
          ((d['alasanTahan'] as List?) ?? []).map((e) => '$e').join('\n');
      _bolehTransaksiStokHabis = d['bolehTransaksiStokHabis'] == true;
      Sesi.instance
        ..tokoNama = _nama.text.trim().isEmpty
            ? Sesi.instance.tokoNama
            : _nama.text.trim()
        ..tokoAlamat = [
          if (_alamat.text.trim().isNotEmpty) _alamat.text.trim(),
          if (_kota.text.trim().isNotEmpty) _kota.text.trim(),
          if (_kodePos.text.trim().isNotEmpty) _kodePos.text.trim(),
        ].join(', ')
        ..tokoTelp =
            _telp.text.trim().isEmpty ? _picHp.text.trim() : _telp.text.trim();
      setStateIfMounted(() {
        _bolehUbah = hasil['bolehUbah'] == true;
        _logoStrukPath = PengaturanStruk.instance.logoPath;
        _logoPriceTagPath = PengaturanStruk.instance.priceTagLogoPath;
        _logoStrukMode = PengaturanStruk.instance.logoMode;
        _logoStrukSkala = PengaturanStruk.instance.logoSkala;
        _lebarKertasStrukMm = PengaturanStruk.instance.lebarKertasMm;
        _marginKotakPriceTagMm = PengaturanStruk.instance.priceTagMarginKotakMm;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihLogoStruk() async {
    setStateIfMounted(() => _memilihLogo = true);
    try {
      final path = await PengaturanStruk.instance.pilihDanSimpanLogo();
      if (path != null && mounted) {
        setStateIfMounted(() => _logoStrukPath = path);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo struk tersimpan lokal.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memilih logo: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memilihLogo = false);
    }
  }

  Future<void> _hapusLogoStruk() async {
    await PengaturanStruk.instance.hapusLogo();
    if (mounted) {
      setStateIfMounted(() => _logoStrukPath = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Logo struk dikembalikan ke logo aplikasi.')));
    }
  }

  Future<void> _pilihLogoPriceTag() async {
    setStateIfMounted(() => _memilihLogoPriceTag = true);
    try {
      final path = await PengaturanStruk.instance.pilihDanSimpanLogoPriceTag();
      if (path != null && mounted) {
        setStateIfMounted(() => _logoPriceTagPath = path);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo price tag tersimpan lokal.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memilih logo: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memilihLogoPriceTag = false);
    }
  }

  Future<void> _hapusLogoPriceTag() async {
    await PengaturanStruk.instance.hapusLogoPriceTag();
    if (mounted) {
      setStateIfMounted(() => _logoPriceTagPath = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Logo price tag dikembalikan ke logo aplikasi.')));
    }
  }

  Future<void> _simpanMarginPriceTag() async {
    await PengaturanStruk.instance
        .simpanMarginKotakPriceTag(_marginKotakPriceTagMm);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Margin kotak price tag tersimpan.')),
      );
    }
  }

  Future<void> _simpanTampilanLogoStruk() async {
    await PengaturanStruk.instance.simpanTampilanLogo(
      mode: _logoStrukMode,
      skala: _logoStrukSkala,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tampilan logo struk tersimpan.')));
    }
  }

  Future<void> _simpanLebarKertasStruk() async {
    await PengaturanStruk.instance.simpanLebarKertas(_lebarKertasStrukMm);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ukuran kertas struk tersimpan.')),
      );
    }
  }

  Future<void> _simpan() async {
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      await ApiClient.instance.aksi('toko_profil_simpan', {
        'nama': _nama.text.trim(),
        'alamat': _alamat.text.trim(),
        'kota': _kota.text.trim(),
        'kode_pos': _kodePos.text.trim(),
        'telp': _telp.text.trim(),
        'email': _email.text.trim(),
        'pic_nama': _picNama.text.trim(),
        'pic_hp': _picHp.text.trim(),
        'npwp': _npwp.text.trim(),
        'jam_operasional': _jamOperasional.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'pesan_terima_kasih': _pesanTerimaKasih.text.trim(),
        'boleh_transaksi_stok_habis': _bolehTransaksiStokHabis,
        'alasan_tahan': _alasanTahan.text
            .split(RegExp(r'[\r\n]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      });
      if (mounted) {
        Sesi.instance
          ..tokoNama = _nama.text.trim()
          ..tokoAlamat = [
            if (_alamat.text.trim().isNotEmpty) _alamat.text.trim(),
            if (_kota.text.trim().isNotEmpty) _kota.text.trim(),
            if (_kodePos.text.trim().isNotEmpty) _kodePos.text.trim(),
          ].join(', ')
          ..tokoTelp =
              _telp.text.trim().isEmpty ? _picHp.text.trim() : _telp.text.trim()
          ..pesanTerimaKasih = _pesanTerimaKasih.text.trim()
          ..bolehTransaksiStokHabis = _bolehTransaksiStokHabis
          ..alasanTahan = _alasanTahan.text
              .split(RegExp(r'[\r\n]+'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profil dan kebijakan toko tersimpan.')));
      }
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) =>
      AppFormTextField(
        label: label,
        controller: c,
        maxLines: maxLines,
        enabled: _bolehUbah,
      );

  Widget _gridForm(List<Widget> children) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 720) return Column(children: children);
      return Wrap(
        spacing: 16,
        runSpacing: 0,
        children: children
            .map((child) => SizedBox(
                  width: (constraints.maxWidth - 16) / 2,
                  child: child,
                ))
            .toList(),
      );
    });
  }

  Widget _previewLogoStruk() {
    final path = _logoStrukPath;
    final logo = path != null
        ? Image.file(File(path), fit: BoxFit.contain)
        : Image.asset(AppVariant.logoAsset, fit: BoxFit.contain);
    final lebar = (_logoStrukMode == 'landscape' ? 180.0 : 96.0) *
        _logoStrukSkala.clamp(0.8, 1.8);
    final tinggi = (_logoStrukMode == 'landscape' ? 84.0 : 96.0) *
        _logoStrukSkala.clamp(0.8, 1.8);
    return Container(
      width: lebar,
      height: tinggi,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: logo,
    );
  }

  Widget _previewLogoPriceTag() {
    final path = _logoPriceTagPath;
    final logo = path != null
        ? Image.file(File(path), fit: BoxFit.contain)
        : Image.asset(AppVariant.logoAsset, fit: BoxFit.contain);
    return Container(
      width: 140,
      height: 72,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: logo,
    );
  }

  Widget _pengaturanPriceTag() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _previewLogoPriceTag(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Price Tag',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                    )),
                const SizedBox(height: 4),
                Text(
                  _logoPriceTagPath == null
                      ? 'Logo price tag memakai logo aplikasi. Upload PNG/JPG jika price tag perlu logo khusus.'
                      : 'Memakai logo khusus lokal untuk semua model price tag.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    AppTombolAksi(
                      icon: Icons.upload_file_outlined,
                      label: _memilihLogoPriceTag
                          ? 'Memilih...'
                          : (_logoPriceTagPath == null
                              ? 'Upload Logo Price Tag'
                              : 'Ganti Logo Price Tag'),
                      warna: AppColors.teal,
                      onPressed:
                          _memilihLogoPriceTag ? null : _pilihLogoPriceTag,
                    ),
                    if (_logoPriceTagPath != null)
                      AppTombolAksi(
                        icon: Icons.restore_outlined,
                        label: 'Gunakan Logo Aplikasi',
                        warna: AppColors.warning,
                        onPressed: _hapusLogoPriceTag,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Margin Antar Kotak: ${_marginKotakPriceTagMm.toStringAsFixed(1)} mm',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                Slider(
                  value: _marginKotakPriceTagMm.clamp(0, 8),
                  min: 0,
                  max: 8,
                  divisions: 16,
                  label: '${_marginKotakPriceTagMm.toStringAsFixed(1)} mm',
                  onChanged: (v) =>
                      setStateIfMounted(() => _marginKotakPriceTagMm = v),
                ),
                Text(
                  'Default 2 mm. Naikkan jika hasil print masih terlalu rapat atau printer bergeser.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppTombolAksi(
                    icon: Icons.grid_view_outlined,
                    label: 'Simpan Margin Price Tag',
                    warna: AppColors.primary,
                    onPressed: _simpanMarginPriceTag,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pengaturanLogoStruk() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _previewLogoStruk(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Logo Struk',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                    )),
                const SizedBox(height: 4),
                Text(
                  _logoStrukPath == null
                      ? 'Saat ini memakai logo aplikasi. Pilih PNG/JPG jika struk perlu logo toko khusus di perangkat ini.'
                      : 'Memakai logo khusus lokal. File asli sudah disalin ke data aplikasi perangkat ini.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    AppTombolAksi(
                      icon: Icons.upload_file_outlined,
                      label: _memilihLogo
                          ? 'Memilih...'
                          : (_logoStrukPath == null
                              ? 'Upload Logo Struk'
                              : 'Ganti Logo Struk'),
                      warna: AppColors.teal,
                      onPressed: _memilihLogo ? null : _pilihLogoStruk,
                    ),
                    if (_logoStrukPath != null)
                      AppTombolAksi(
                        icon: Icons.restore_outlined,
                        label: 'Gunakan Logo Aplikasi',
                        warna: AppColors.warning,
                        onPressed: _hapusLogoStruk,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _logoStrukMode,
                  dropdownColor: AppColors.cardBgOf(context),
                  style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  decoration:
                      const InputDecoration(labelText: 'Rasio Logo Struk'),
                  items: const [
                    DropdownMenuItem(
                        value: 'persegi', child: Text('1 x 1 / Persegi')),
                    DropdownMenuItem(
                        value: 'landscape',
                        child: Text('Persegi panjang / Landscape')),
                  ],
                  onChanged: (v) => setStateIfMounted(() {
                    _logoStrukMode = v ?? 'persegi';
                  }),
                ),
                const SizedBox(height: 10),
                Text(
                  'Ukuran Logo: ${(_logoStrukSkala * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                Slider(
                  value: _logoStrukSkala.clamp(0.8, 1.8),
                  min: 0.8,
                  max: 1.8,
                  divisions: 10,
                  label: '${(_logoStrukSkala * 100).round()}%',
                  onChanged: (v) =>
                      setStateIfMounted(() => _logoStrukSkala = v),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppTombolAksi(
                    icon: Icons.tune_outlined,
                    label: 'Simpan Tampilan Logo',
                    warna: AppColors.primary,
                    onPressed: _simpanTampilanLogoStruk,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<double>(
                  value: _lebarKertasStrukMm,
                  dropdownColor: AppColors.cardBgOf(context),
                  style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  decoration:
                      const InputDecoration(labelText: 'Ukuran Kertas Struk'),
                  items: PengaturanStruk.opsiLebarKertasMm
                      .map(
                        (lebar) => DropdownMenuItem<double>(
                          value: lebar,
                          child: Text('${lebar.toStringAsFixed(0)} mm'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setStateIfMounted(() {
                    _lebarKertasStrukMm = v ?? 80;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  'Preview dan hasil cetak struk akan mengikuti lebar kertas ini.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppTombolAksi(
                    icon: Icons.receipt_long_outlined,
                    label: 'Simpan Ukuran Kertas',
                    warna: AppColors.teal,
                    onPressed: _simpanLebarKertasStruk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!,
                style: TextStyle(color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi'))
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_bolehUbah)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: AppInfoBanner(
              icon: Icons.lock_outline,
              color: AppColors.warning,
              text:
                  'Hanya admin atau supervisor toko yang dapat mengubah profil ini.',
            ),
          ),
        AppFormSection(
          judul: 'Kebijakan Stok Toko Aktif',
          deskripsi:
              'Berlaku hanya untuk ${_nama.text.trim().isEmpty ? 'toko yang sedang dipilih' : _nama.text.trim()}. Toko lain tidak ikut berubah.',
          children: [
            AppFormSwitchTile(
              title: 'Paksa semua produk boleh stok minus',
              subtitle: _bolehTransaksiStokHabis
                  ? 'AKTIF — seluruh produk di toko ini boleh dijual saat stok nol atau minus, walaupun izin pada produk tidak dicentang.'
                  : 'NONAKTIF — ikuti izin “Boleh dijual walau stok minus” pada masing-masing produk. Ini adalah pilihan default yang lebih aman.',
              value: _bolehTransaksiStokHabis,
              onChanged: _bolehUbah
                  ? (nilai) =>
                      setStateIfMounted(() => _bolehTransaksiStokHabis = nilai)
                  : null,
            ),
            if (_bolehUbah)
              Align(
                alignment: Alignment.centerLeft,
                child: AppTombolAksi(
                  icon: Icons.save_outlined,
                  label: _menyimpan ? 'Menyimpan...' : 'Simpan Kebijakan Stok',
                  onPressed: _menyimpan ? null : _simpan,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AppFormSection(
          judul: 'Profil Toko',
          deskripsi:
              'Data ini dipakai untuk informasi operasional, laporan, dan teks pada struk.',
          children: [
            AppReadonlyField(label: 'Kode Toko', value: _kode.text),
            _gridForm([
              _field('Nama Toko', _nama),
              _field('Kota', _kota),
              _field('Kode Pos', _kodePos),
              _field('Telepon', _telp),
              _field('Email', _email),
              _field('PIC Nama', _picNama),
              _field('PIC HP', _picHp),
              _field('NPWP', _npwp),
              _field('Jam Operasional', _jamOperasional),
            ]),
            _field('Alamat', _alamat, maxLines: 2),
            _field('Keterangan', _keterangan, maxLines: 2),
            _field('Pesan Terima Kasih (di struk)', _pesanTerimaKasih,
                maxLines: 2),
            _field(
              'Pilihan Alasan Transaksi Ditahan (satu alasan per baris)',
              _alasanTahan,
              maxLines: 12,
            ),
            _pengaturanLogoStruk(),
            _pengaturanPriceTag(),
            if (_bolehUbah)
              Align(
                alignment: Alignment.centerLeft,
                child: AppTombolAksi(
                  icon: Icons.save_outlined,
                  label: _menyimpan ? 'Menyimpan...' : 'Simpan Profil',
                  onPressed: _menyimpan ? null : _simpan,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TabAkunPengguna extends StatefulWidget {
  const _TabAkunPengguna();
  @override
  State<_TabAkunPengguna> createState() => _TabAkunPenggunaState();
}

class _TabAkunPenggunaState extends State<_TabAkunPengguna> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  bool _bolehKelola = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('pedagang_list');
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _bolehKelola = hasil['bolehKelola'] == true;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _bukaForm({Map<String, dynamic>? akun}) async {
    final tersimpan = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _FormAkun(akun: akun));
    if (tersimpan == true) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!,
                style: TextStyle(color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi'))
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _bolehKelola
          ? FloatingActionButton.extended(
              onPressed: () => _bukaForm(),
              icon: const Icon(Icons.person_add),
              label: const Text('Tambah Akun'))
          : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            if (Sesi.instance.isAdmin)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AppFormSection(
                  judul: 'Hak Akses',
                  deskripsi:
                      'Atur menu yang boleh diakses oleh setiap grup pengguna.',
                  aksiJudul: IconButton(
                    tooltip: 'Buka Hak Akses',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const HakAksesScreen())),
                  ),
                  children: [
                    AppInfoBanner(
                      icon: Icons.admin_panel_settings_outlined,
                      color: AppColors.primary,
                      text: 'Pengaturan hak akses hanya tersedia untuk admin.',
                    ),
                  ],
                ),
              ),
            if (_data.isEmpty)
              Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('Belum ada akun.',
                          style: TextStyle(
                              color: AppColors.textSecondaryOf(context)))))
            else
              AppFormSection(
                judul: 'Daftar Akun',
                deskripsi:
                    'Kelola akun pengguna POS dan status supervisor toko.',
                children: [
                  ..._data.map((a) {
                    final aktif = a['aktif'] == true;
                    final supervisor = a['supervisor'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: AppColors.cardBgOf(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: AppColors.borderOf(context)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.latarLembut(
                                aktif ? AppColors.primary : AppColors.danger),
                            child: Icon(Icons.person_outline,
                                color: aktif
                                    ? AppColors.primary
                                    : AppColors.danger),
                          ),
                          title: Text('${a['nama']}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimaryOf(context))),
                          subtitle: Text(
                              '${a['userid']} Ã‚Â· ${a['keterangan'] ?? ''}',
                              style: TextStyle(
                                  color: AppColors.textSecondaryOf(context))),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              if (supervisor)
                                const StatusPill(
                                    label: 'Supervisor', warna: AppColors.info),
                              StatusPill(
                                label: aktif ? 'Aktif' : 'Nonaktif',
                                warna: aktif
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ],
                          ),
                          onTap: _bolehKelola ? () => _bukaForm(akun: a) : null,
                        ),
                      ),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FormAkun extends StatefulWidget {
  final Map<String, dynamic>? akun;
  const _FormAkun({required this.akun});
  @override
  State<_FormAkun> createState() => _FormAkunState();
}

class _FormAkunState extends State<_FormAkun> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userid;
  late final TextEditingController _password;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  bool _aktif = true;
  bool _supervisor = false;
  bool _menyimpan = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.akun;
    _userid = TextEditingController(text: a?['userid'] ?? '');
    _password = TextEditingController();
    _nama = TextEditingController(text: a?['nama'] ?? '');
    _keterangan = TextEditingController(text: a?['keterangan'] ?? '');
    _aktif = a?['aktif'] ?? true;
    _supervisor = a?['supervisor'] ?? false;
  }

  @override
  void dispose() {
    _userid.dispose();
    _password.dispose();
    _nama.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final ubah = widget.akun != null;
      if (ubah) {
        await ApiClient.instance.aksi('pedagang_ubah', {
          'id': widget.akun!['id'],
          'nama': _nama.text.trim(),
          'keterangan': _keterangan.text.trim(),
          'aktif': _aktif,
          'supervisor': _supervisor,
          if (_password.text.isNotEmpty) 'password_baru': _password.text,
        });
      } else {
        await ApiClient.instance.aksi('akun_tambah', {
          'userid': _userid.text.trim(),
          'password': _password.text,
          'nama': _nama.text.trim(),
          'toko_id': Sesi.instance.tokoId,
          'keterangan': _keterangan.text.trim(),
          'supervisor': _supervisor,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.akun != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null)
                AppInfoBanner(
                  icon: Icons.error_outline,
                  color: AppColors.danger,
                  text: _error!,
                ),
              if (_error != null) const SizedBox(height: 12),
              AppFormSection(
                judul: ubah ? 'Ubah Akun' : 'Tambah Akun',
                deskripsi:
                    'Lengkapi identitas pengguna dan peran operasionalnya.',
                children: [
                  if (!ubah)
                    AppFormTextField(
                      label: 'User ID',
                      controller: _userid,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Wajib diisi'
                          : null,
                    ),
                  AppFormTextField(
                    label: 'Nama',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                    label: ubah ? 'Password Baru' : 'Password',
                    helperText: ubah
                        ? 'Kosongkan jika password tidak diubah.'
                        : 'Minimal 6 karakter.',
                    controller: _password,
                    obscureText: true,
                    validator: (v) => (!ubah && (v == null || v.length < 6))
                        ? 'Minimal 6 karakter'
                        : null,
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                  ),
                  AppFormSwitchTile(
                    title: 'Supervisor',
                    subtitle:
                        'Supervisor dapat mengakses fitur pengelolaan tertentu sesuai izin server.',
                    value: _supervisor,
                    onChanged: (v) => setStateIfMounted(() => _supervisor = v),
                  ),
                  if (ubah)
                    AppFormSwitchTile(
                      title: 'Aktif',
                      subtitle: 'Nonaktifkan untuk mencegah akun digunakan.',
                      value: _aktif,
                      onChanged: (v) => setStateIfMounted(() => _aktif = v),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: AppTombolAksi(
                      icon: Icons.save_outlined,
                      label: _menyimpan ? 'Menyimpan...' : 'Simpan',
                      onPressed: _menyimpan ? null : _simpan,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
