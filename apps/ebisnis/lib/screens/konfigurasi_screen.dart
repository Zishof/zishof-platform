import 'package:core_device/core_device.dart';
import 'package:core_hw/core_hw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../services/pengaturan_laci.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import 'login_screen.dart';
import 'pengaturan_server_screen.dart';
import 'hak_akses_screen.dart';

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

class _KonfigurasiScreenState extends State<KonfigurasiScreen> with SingleTickerProviderStateMixin {
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
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final tombolLogout = IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Keluar');
    return AppShell(
      menuAktif: MenuEBisnis.konfigurasi,
      judul: 'Konfigurasi',
      subjudul: 'Identitas mesin, profil toko, akun pengguna, dan alamat server',
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
            unselectedLabelColor: Colors.black54,
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
        const Text(
          'Mengubah alamat server akan mengeluarkan Anda dari akun saat ini -- masuk kembali di server yang baru setelah tersimpan.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        FormAlamatServer(labelSimpan: 'Simpan & Keluar', onSelesai: onUbah),
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
  bool _memuat = true;
  bool _menyimpan = false;

  // Cash Drawer (Windows-only) -- lihat services/pengaturan_laci.dart.
  List<Printer> _daftarPrinter = [];
  String? _printerLaci;
  bool _pinAlternatif = false;
  bool _menyimpanLaci = false;
  bool _tesLaciBerjalan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _namaController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    await IdentitasMesin.instance.muat();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await PengaturanLaci.instance.muat();
      try {
        _daftarPrinter = await Printing.listPrinters();
      } catch (_) {
        _daftarPrinter = [];
      }
    }
    if (mounted) {
      setState(() {
        _namaController.text = IdentitasMesin.instance.namaMesin;
        _printerLaci = PengaturanLaci.instance.namaPrinter;
        _pinAlternatif = PengaturanLaci.instance.pinAlternatif;
        _memuat = false;
      });
    }
  }

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    await IdentitasMesin.instance.simpanNamaMesin(_namaController.text.trim());
    if (mounted) {
      setState(() => _menyimpan = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama mesin tersimpan.')));
    }
  }

  Future<void> _simpanLaci() async {
    setState(() => _menyimpanLaci = true);
    await PengaturanLaci.instance.simpan(namaPrinter: _printerLaci, pinAlternatif: _pinAlternatif);
    if (mounted) {
      setState(() => _menyimpanLaci = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan laci tersimpan.')));
    }
  }

  Future<void> _tesLaci() async {
    setState(() => _tesLaciBerjalan = true);
    try {
      await bukaLaciKasir(pinAlternatif: _pinAlternatif, namaPrinter: _printerLaci);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perintah buka laci terkirim.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      if (mounted) setState(() => _tesLaciBerjalan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Identitas fisik perangkat ini -- dikirim di setiap transaksi supaya laporan bisa membedakan mesin/HP kasir yang mana.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 16),
        TextField(
          readOnly: true,
          controller: TextEditingController(text: IdentitasMesin.instance.idMesin),
          decoration: const InputDecoration(labelText: 'ID Mesin (permanen, otomatis)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _namaController,
          decoration: const InputDecoration(labelText: 'Nama Mesin (bisa diubah)', hintText: 'mis. Kasir Depan', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 180,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF9DB7F3),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _menyimpan ? null : _simpan,
              child: _menyimpan
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan'),
            ),
          ),
        ),
        if (defaultTargetPlatform == TargetPlatform.windows) ...[
          const Divider(height: 40),
          const Text('Cash Drawer (Buka Laci)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          const Text(
            'Laci kasir tidak punya driver sendiri -- ia tersambung via kabel ke printer struk thermal. '
            'Kalau laci tidak terbuka, biasanya penyebabnya salah target printer (bukan berarti printer defaultnya) '
            'atau salah pin (coba "Pin Alternatif" kalau pin biasa tak berhasil).',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _daftarPrinter.any((p) => p.name == _printerLaci) ? _printerLaci : null,
            decoration: const InputDecoration(labelText: 'Printer Laci', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('(Ikut printer default Windows)')),
              ..._daftarPrinter.map((p) => DropdownMenuItem<String?>(value: p.name, child: Text(p.name + (p.isDefault ? ' (default)' : '')))),
            ],
            onChanged: (v) => setState(() => _printerLaci = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pin Alternatif (Pin 5)', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Aktifkan kalau laci tak terbuka dengan pengaturan pin biasa (Pin 2).', style: TextStyle(fontSize: 11)),
            value: _pinAlternatif,
            onChanged: (v) => setState(() => _pinAlternatif = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF99C9C3),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _menyimpanLaci ? null : _simpanLaci,
                  child: _menyimpanLaci
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Simpan Pengaturan Laci'),
                ),
              ),
              SizedBox(
                width: 180,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFF8B27C),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _tesLaciBerjalan ? null : _tesLaci,
                  child: _tesLaciBerjalan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Tes Buka Laci'),
                ),
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
    for (final c in [_kode, _nama, _alamat, _kota, _kodePos, _telp, _email, _picNama, _picHp, _npwp, _jamOperasional, _keterangan, _pesanTerimaKasih]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
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
      setState(() => _bolehUbah = hasil['bolehUbah'] == true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _simpan() async {
    setState(() {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil toko tersimpan.')));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          enabled: _bolehUbah,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), const SizedBox(height: 12), ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi'))]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_bolehUbah)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Hanya admin/supervisor toko yang dapat mengubah profil ini.', style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic)),
          ),
        TextField(controller: _kode, readOnly: true, decoration: const InputDecoration(labelText: 'Kode Toko', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        _field('Nama Toko', _nama),
        _field('Alamat', _alamat, maxLines: 2),
        _field('Kota', _kota),
        _field('Kode Pos', _kodePos),
        _field('Telepon', _telp),
        _field('Email', _email),
        _field('PIC Nama', _picNama),
        _field('PIC HP', _picHp),
        _field('NPWP', _npwp),
        _field('Jam Operasional', _jamOperasional),
        _field('Keterangan', _keterangan, maxLines: 2),
        _field('Pesan Terima Kasih (di struk)', _pesanTerimaKasih, maxLines: 2),
        if (_bolehUbah)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _menyimpan ? null : _simpan,
              child: _menyimpan ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan'),
            ),
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
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('pedagang_list');
      setState(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _bolehKelola = hasil['bolehKelola'] == true;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _bukaForm({Map<String, dynamic>? akun}) async {
    final tersimpan = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _FormAkun(akun: akun));
    if (tersimpan == true) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), const SizedBox(height: 12), ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi'))]),
        ),
      );
    }
    return Scaffold(
      floatingActionButton: _bolehKelola ? FloatingActionButton.extended(onPressed: () => _bukaForm(), icon: const Icon(Icons.person_add), label: const Text('Tambah Akun')) : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            if (Sesi.instance.isAdmin)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Hak Akses'),
                  subtitle: const Text('Atur menu yang boleh diakses tiap Grup Pengguna'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HakAksesScreen())),
                ),
              ),
            if (_data.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Belum ada akun.')))
            else
              ..._data.map((a) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('${a['nama']} (${a['userid']})', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${a['keterangan'] ?? ''}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (a['supervisor'] == true) const Text('Supervisor', style: TextStyle(fontSize: 10, color: Color(0xFF0284C7))),
                          Text(a['aktif'] == true ? 'Aktif' : 'Nonaktif', style: TextStyle(fontSize: 10, color: a['aktif'] == true ? const Color(0xFF2E7D32) : Colors.red)),
                        ],
                      ),
                      onTap: _bolehKelola ? () => _bukaForm(akun: a) : null,
                    ),
                  )),
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
    setState(() {
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
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.akun != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              Text(ubah ? 'Ubah Akun' : 'Tambah Akun', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
              if (!ubah)
                TextFormField(
                  controller: _userid,
                  decoration: const InputDecoration(labelText: 'User ID *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
              if (!ubah) const SizedBox(height: 12),
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(labelText: 'Nama *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: ubah ? 'Password Baru (kosongkan jika tak diubah)' : 'Password *', border: const OutlineInputBorder()),
                validator: (v) => (!ubah && (v == null || v.length < 6)) ? 'Minimal 6 karakter' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _keterangan, decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder())),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Supervisor'), value: _supervisor, onChanged: (v) => setState(() => _supervisor = v)),
              if (ubah) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktif'), value: _aktif, onChanged: (v) => setState(() => _aktif = v)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _menyimpan ? null : _simpan,
                  child: _menyimpan ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
