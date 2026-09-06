import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../widgets/app_shell.dart';

class MembershipApotikScreen extends StatefulWidget {
  const MembershipApotikScreen({super.key});

  @override
  State<MembershipApotikScreen> createState() => _MembershipApotikScreenState();
}

class _MembershipApotikScreenState extends State<MembershipApotikScreen> {
  final _cari = TextEditingController();
  List<Map<String, dynamic>> _data = const [];
  bool _memuat = true;
  String _status = '';
  String? _error;

  static const _statusList = ['', 'AKTIF', 'NONAKTIF', 'DIBLOKIR'];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  bool _sukses(Map<String, dynamic> hasil) =>
      hasil['status'] == '00' || hasil['status'] == 'success';

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('apotik_membership_list', {
        'page': 1,
        'page_size': 100,
        if (_status.isNotEmpty) 'status': _status,
        if (_cari.text.trim().isNotEmpty) 'keyword': _cari.text.trim(),
      });
      if (!_sukses(hasil)) {
        throw Exception(hasil['description'] ?? 'Membership gagal dimuat.');
      }
      if (!mounted) return;
      setState(() {
        _data = ((hasil['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _memuat = false;
      });
    }
  }

  Future<void> _buatAnggota() async {
    final nama = TextEditingController();
    final telepon = TextEditingController();
    final pasien = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String tier = 'REGULER';
    bool consent = false;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) {
        return AlertDialog(
          title: const Text('Daftarkan Member Apotik'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: nama,
                  autofocus: true,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Nama anggota wajib diisi'
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Nama anggota',
                      prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: telepon,
                      decoration:
                          const InputDecoration(labelText: 'Nomor telepon'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: pasien,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'ID pasien'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tier,
                  decoration: const InputDecoration(labelText: 'Tier'),
                  items: const ['REGULER', 'GOLD', 'PLATINUM']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setDialog(() => tier = v ?? 'REGULER'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consent,
                  title: const Text('Izinkan pengingat refill'),
                  subtitle: const Text(
                      'Notifikasi hanya dikirim berdasarkan consent'),
                  onChanged: (v) => setDialog(() => consent = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Daftarkan'),
            ),
          ],
        );
      }),
    );
    if (simpan == true) {
      await _aksi(
        'apotik_membership_simpan',
        {
          'nama': nama.text.trim(),
          'telepon': telepon.text.trim(),
          'tier': tier,
          'status': 'AKTIF',
          'consent_notifikasi': consent,
          if (int.tryParse(pasien.text) != null)
            'pasien_id': int.parse(pasien.text),
        },
        'Member baru berhasil didaftarkan.',
      );
    }
    nama.dispose();
    telepon.dispose();
    pasien.dispose();
  }

  Future<void> _mutasiPoin(Map<String, dynamic> member) async {
    final poin = TextEditingController();
    final catatan = TextEditingController();
    bool perolehan = true;
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) {
        return AlertDialog(
          title: Text('Poin ${member['nama']}'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.add_circle_outline),
                      label: Text('Perolehan')),
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.redeem_outlined),
                      label: Text('Penukaran')),
                ],
                selected: {perolehan},
                onSelectionChanged: (v) => setDialog(() => perolehan = v.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: poin,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah poin'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: catatan,
                decoration:
                    const InputDecoration(labelText: 'Referensi / catatan'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Proses')),
          ],
        );
      }),
    );
    final nilai = int.tryParse(poin.text) ?? 0;
    if (lanjut == true && nilai > 0) {
      await _aksi(
        'apotik_membership_poin',
        {
          'id': member['id'],
          'poin': perolehan ? nilai : -nilai,
          'referensi': 'MEMBERSHIP-APP',
          'keterangan': catatan.text.trim(),
        },
        'Saldo poin berhasil diperbarui.',
      );
    }
    poin.dispose();
    catatan.dispose();
  }

  Future<void> _aturRefill(Map<String, dynamic> member) async {
    final obat = TextEditingController(text: '${member['obatRutin'] ?? ''}');
    final interval =
        TextEditingController(text: '${member['intervalRefillHari'] ?? 30}');
    final tanggal =
        TextEditingController(text: '${member['tanggalRefillBerikut'] ?? ''}');
    bool consent = member['consentNotifikasi'] == true;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) {
        return AlertDialog(
          title: Text('Jadwal Refill • ${member['nama']}'),
          content: SizedBox(
            width: 500,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: obat,
                decoration: const InputDecoration(
                    labelText: 'Obat rutin',
                    prefixIcon: Icon(Icons.medication_outlined)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Interval (hari)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: tanggal,
                    decoration:
                        const InputDecoration(labelText: 'Refill (yyyy-MM-dd)'),
                  ),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                title: const Text('Consent notifikasi aktif'),
                onChanged: (v) => setDialog(() => consent = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Simpan Jadwal'),
            ),
          ],
        );
      }),
    );
    if (simpan == true) {
      await _aksi(
        'apotik_membership_refill',
        {
          'id': member['id'],
          'obat_rutin': obat.text.trim(),
          'interval_refill_hari': int.tryParse(interval.text) ?? 0,
          'tanggal_refill_berikut': tanggal.text.trim(),
          'consent_notifikasi': consent,
        },
        'Jadwal refill berhasil diperbarui.',
      );
    }
    obat.dispose();
    interval.dispose();
    tanggal.dispose();
  }

  Future<void> _aksi(
      String nama, Map<String, dynamic> body, String pesan) async {
    try {
      final hasil = await ApiClient.instance.aksi(nama, body);
      if (!_sukses(hasil)) {
        throw Exception(hasil['description'] ?? 'Data gagal diproses.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(pesan)));
      await _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Membership & Refill',
      subjudul: 'Loyalitas pelanggan, reward ledger, dan pengingat obat rutin',
      scrollable: false,
      actionsAppBar: [
        IconButton(
            tooltip: 'Segarkan',
            onPressed: _memuat ? null : _muat,
            icon: const Icon(Icons.refresh)),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _buatAnggota,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Member Baru'),
        ),
        const SizedBox(width: 12),
      ],
      body: Column(children: [
        _ringkasan(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _cari,
                onSubmitted: (_) => _muat(),
                decoration: InputDecoration(
                  hintText: 'Cari kode member, nama, telepon, atau obat rutin',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      onPressed: _muat, icon: const Icon(Icons.arrow_forward)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: _statusList
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(s.isEmpty ? 'Semua status' : s)))
                    .toList(),
                onChanged: (v) {
                  _status = v ?? '';
                  _muat();
                },
              ),
            ),
          ]),
        ),
        Expanded(child: _isi()),
      ]),
    );
  }

  Widget _ringkasan() {
    final aktif = _data.where((e) => e['status'] == 'AKTIF').length;
    final consent = _data.where((e) => e['consentNotifikasi'] == true).length;
    final terjadwal = _data
        .where((e) => '${e['tanggalRefillBerikut'] ?? ''}'.isNotEmpty)
        .length;
    final poin = _data.fold<int>(
        0, (total, e) => total + ((e['poin'] as num?)?.toInt() ?? 0));
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF831843), Color(0xFFBE185D)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.loyalty_outlined, color: Colors.white, size: 34),
        const SizedBox(width: 12),
        _angka('Total Member', _data.length),
        _angka('Aktif', aktif),
        _angka('Consent', consent),
        _angka('Refill Terjadwal', terjadwal),
        _angka('Total Poin', poin),
      ]),
    );
  }

  Widget _angka(String label, int nilai) => Expanded(
        child: Column(children: [
          Text('$nilai',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(color: Color(0xFFFCE7F3), fontSize: 12)),
        ]),
      );

  Widget _isi() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 10),
          Text(_error!),
          TextButton.icon(
              onPressed: _muat,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi')),
        ]),
      );
    }
    if (_data.isEmpty) return const Center(child: Text('Belum ada member.'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: _data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _kartu(_data[i]),
    );
  }

  Widget _kartu(Map<String, dynamic> m) {
    final aktif = m['status'] == 'AKTIF';
    final consent = m['consentNotifikasi'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFBE185D).withValues(alpha: .12),
            child: const Icon(Icons.person_outline, color: Color(0xFFBE185D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('${m['nama']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 8),
                _pill('${m['tier']}', const Color(0xFF7C3AED)),
                const SizedBox(width: 5),
                _pill('${m['status']}',
                    aktif ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
              ]),
              const SizedBox(height: 5),
              Text('${m['kode']} • RM ${m['nomorRm']} • ${m['telepon']}'),
            ]),
          ),
          Expanded(
            flex: 2,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['obatRutin']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  'Refill ${m['tanggalRefillBerikut']} • ${m['intervalRefillHari']} hari'),
              Row(children: [
                Icon(
                    consent
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    size: 15,
                    color: consent ? const Color(0xFF15803D) : Colors.grey),
                const SizedBox(width: 4),
                Text(consent ? 'Notifikasi diizinkan' : 'Tanpa consent'),
              ]),
            ]),
          ),
          SizedBox(
            width: 100,
            child: Column(children: [
              Text('${m['poin']}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const Text('poin', style: TextStyle(fontSize: 11)),
            ]),
          ),
          IconButton(
              tooltip: 'Atur refill',
              onPressed: () => _aturRefill(m),
              icon: const Icon(Icons.event_repeat_outlined)),
          IconButton(
              tooltip: 'Mutasi poin',
              onPressed: () => _mutasiPoin(m),
              icon: const Icon(Icons.redeem_outlined)),
        ]),
      ),
    );
  }

  Widget _pill(String teks, Color warna) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(teks,
            style: TextStyle(
                color: warna, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}
