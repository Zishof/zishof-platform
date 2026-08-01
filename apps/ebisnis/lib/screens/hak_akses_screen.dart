import 'package:flutter/material.dart';
import '../api_client.dart';

/// Layar admin "Hak Akses" -- editor 13 checkbox per-menu untuk Grup
/// Pengguna (Tbmrole.ebisnisMenu), gap-closure: mekanisme ini sudah lama ada
/// (dipakai layar ZK TbmroleAction + gerbang server EbisnisMenuKatalog),
/// tapi sebelum ini HANYA bisa diedit lewat layar ZK desktop-browser --
/// tidak terjangkau dari klien mobile/desktop Flutter. Admin-only: server
/// (KantinHelper.ebisnisRoleList/ebisnisRoleMenuAmbil/ebisnisRoleMenuSimpan)
/// menolak akun yang punya toko (pedagang != null), bukan cuma supervisor
/// toko, karena Tbmrole tidak terikat satu toko.
class HakAksesScreen extends StatefulWidget {
  const HakAksesScreen({super.key});
  @override
  State<HakAksesScreen> createState() => _HakAksesScreenState();
}

class _HakAksesScreenState extends State<HakAksesScreen> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftarRole = [];

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
      final hasil = await ApiClient.instance.aksi('ebisnis_role_list');
      _daftarRole = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hak Akses')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Gagal memuat: $_error'),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _muat, child: const Text('Coba Lagi')),
                    ],
                  ),
                )
              : _daftarRole.isEmpty
                  ? const Center(child: Text('Tidak ada Grup Pengguna aktif.'))
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _daftarRole.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final r = _daftarRole[i];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.badge_outlined),
                              title: Text('${r['roleName']}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _EditHakAksesScreen(roleId: '${r['roleId']}', roleName: '${r['roleName']}'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _EditHakAksesScreen extends StatefulWidget {
  final String roleId;
  final String roleName;
  const _EditHakAksesScreen({required this.roleId, required this.roleName});
  @override
  State<_EditHakAksesScreen> createState() => _EditHakAksesScreenState();
}

class _EditHakAksesScreenState extends State<_EditHakAksesScreen> {
  bool _memuat = true;
  bool _menyimpan = false;
  bool _supervisor = false;
  String? _error;
  List<Map<String, dynamic>> _menu = [];

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
      final hasil = await ApiClient.instance.aksi('ebisnis_role_menu_ambil', {'role_id': widget.roleId});
      _menu = ((hasil['menu'] as List?) ?? []).cast<Map<String, dynamic>>();
      _supervisor = hasil['supervisor'] == true;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    try {
      final payload = <String, bool>{for (final m in _menu) '${m['kunci']}': m['boleh'] == true};
      await ApiClient.instance.aksi('ebisnis_role_menu_simpan', {'role_id': widget.roleId, 'menu': payload});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hak akses berhasil disimpan.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hak Akses: ${widget.roleName}')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Gagal memuat: $_error'))
              : Column(
                  children: [
                    if (_supervisor)
                      Container(
                        width: double.infinity,
                        color: Colors.amber.shade100,
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          'Grup ini bertanda Supervisor -- otomatis boleh mengakses SEMUA menu, checkbox di bawah tidak berpengaruh.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _menu.length,
                        itemBuilder: (context, i) {
                          final m = _menu[i];
                          return CheckboxListTile(
                            title: Text('${m['label']}'),
                            value: m['boleh'] == true,
                            onChanged: _supervisor
                                ? null
                                : (v) => setState(() => _menu[i] = {...m, 'boleh': v == true}),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      minimum: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _menyimpan ? null : _simpan,
                          child: _menyimpan
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Simpan'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
