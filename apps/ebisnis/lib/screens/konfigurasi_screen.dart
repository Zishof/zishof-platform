import 'package:core_device/core_device.dart';
import 'package:core_hw/core_hw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../services/pengaturan_laci.dart';
import '../services/pengaturan_pembayaran.dart';
import '../services/pengaturan_sesi_lokal.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'login_screen.dart';
import 'pengaturan_server_screen.dart';
import 'hak_akses_screen.dart';
import '../widgets/safe_state.dart';

/// Layar Konfigurasi (padanan konfigurasi.html/konfigurasi-renderer.js
/// Electron) -- 4 sub-tab: Identitas Mesin (lokal, core_device), Profil Toko
/// (server, `toko_profil_ambil`/`_simpan`), Akun Pengguna (server,
/// `pedagang_list`/`pedagang_ubah`/`akun_tambah`), Alamat Server (lokal,
/// `FormAlamatServer` yg sama dgn `PengaturanServerScreen` -- bisa diubah
/// dari DALAM aplikasi tanpa perlu logout dulu). Bagian "Tampilan Aplikasi"
/// Electron (judul window/logo) sengaja TIDAK diporting -- itu chrome desktop,
/// tak ada padanan di HP.
class KonfigurasiScreen extends StatefulWidget {
  const KonfigurasiScreen({super.key});
  @override
  State<KonfigurasiScreen> createState() => _KonfigurasiScreenState();
}

class _KonfigurasiScreenState extends State<KonfigurasiScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
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
            labelColor: const Color(0xFF2563EB),
            unselectedLabelColor: warnaTeksSekunder,
            indicatorColor: const Color(0xFF2563EB),
            tabs: const [
              Tab(text: 'Identitas Mesin'),
              Tab(text: 'Profil Toko'),
              Tab(text: 'Akun Pengguna'),
              Tab(text: 'Alamat Server'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              const _TabIdentitasMesin(),
              const _TabProfilToko(),
              const _TabAkunPengguna(),
              _TabAlamatServer(onUbah: _logout),
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
  bool _memuat = true;
  bool _menyimpan = false;

  // Cash Drawer (Windows-only) -- lihat services/pengaturan_laci.dart.
  List<Printer> _daftarPrinter = [];
  String? _printerLaci;
  bool _pinAlternatif = false;
  bool _menyimpanLaci = false;
  bool _tesLaciBerjalan = false;
  int? _caraBayarDefaultId;
  bool _menyimpanPembayaran = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _namaController.dispose();
    _timeoutSesiController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    await IdentitasMesin.instance.muat();
    await PengaturanPembayaran.instance.muat();
    await PengaturanSesiLokal.instance.muat();
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
        _timeoutSesiController.text =
            PengaturanSesiLokal.instance.timeoutMenit.toString();
        _memuat = false;
      });
    }
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
    await PengaturanSesiLokal.instance.simpanTimeoutMenit(menit);
    if (mounted) {
      setStateIfMounted(() {
        _menyimpanPembayaran = false;
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

class _TabProfilToko extends StatefulWidget {
  const _TabProfilToko();
  @override
  State<_TabProfilToko> createState() => _TabProfilTokoState();
}

class _TabProfilTokoState extends State<_TabProfilToko> {
  bool _memuat = true;
  bool _menyimpan = false;
  String? _error;
  bool _bolehUbah = false;
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
      _pesanTerimaKasih
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
      setStateIfMounted(() => _bolehUbah = hasil['bolehUbah'] == true);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
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
          ..pesanTerimaKasih = _pesanTerimaKasih.text.trim();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil toko tersimpan.')));
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
                  children: const [
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
                              '${a['userid']} · ${a['keterangan'] ?? ''}',
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
