import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/format.dart';
import '../widgets/navigasi.dart';
import '../widgets/panel_galat.dart';

/// Isi saldo anggota dengan kontrak yang sama seperti halaman Topup Kantin web.
///
/// Aplikasi hanya membuat tagihan bank/gateway. Saldo tidak pernah ditambah
/// dari klien; perubahan saldo tetap menunggu callback pembayaran resmi.
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  static const _nominalCepat = <int>[10000, 50000, 100000, 500000];

  final _nominal = TextEditingController();
  bool _memuat = true;
  bool _membuat = false;
  String? _galat;
  List<Map<String, dynamic>> _saluran = [];
  List<Map<String, dynamic>> _va = [];
  Map<String, dynamic>? _saluranDipilih;
  Map<String, dynamic>? _hasilTopup;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _nominal.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final info = await ApiClient.instance.aksi('kantin_info', const {});
      final data = info['data'];
      if (data is Map) {
        Sesi.instance.terapkanInfo(data.map((k, v) => MapEntry('$k', v)));
      }
      if (Sesi.instance.aktifkanTopup) {
        final saluranRes = await ApiClient.instance
            .aksi('kantin_cara_bayar', const {'topup_only': 'true'});
        _saluran = ApiClient.instance.daftar(saluranRes);
        _saluranDipilih = _saluran.isEmpty ? null : _saluran.first;
      } else {
        _saluran = [];
        _saluranDipilih = null;
      }
      final vaRes = await ApiClient.instance
          .aksi('kantin_va_list', const {'page': 1, 'limit': 20});
      _va = ApiClient.instance.daftar(vaRes);
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  double _nominalInput() {
    final angka = _nominal.text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(angka) ?? 0;
  }

  double get _biayaAdmin =>
      (_saluranDipilih?['biaya_admin'] as num?)?.toDouble() ?? 0;

  String _labelSaluran(Map<String, dynamic> saluran) {
    final kanal =
        '${saluran['nama_channel'] ?? saluran['channel'] ?? saluran['nama'] ?? '-'}';
    final metode = '${saluran['nama'] ?? ''}'.trim();
    final biaya = (saluran['biaya_admin'] as num?)?.toDouble() ?? 0;
    return [
      kanal,
      if (metode.isNotEmpty && metode != kanal) metode,
      if (biaya > 0) 'admin ${rupiah(biaya)}',
    ].join(' · ');
  }

  Future<void> _konfirmasiTopup() async {
    final nominal = _nominalInput();
    if (nominal < 10000) {
      setState(() => _galat = 'Nominal pengisian saldo minimal Rp 10.000.');
      return;
    }
    if (_saluranDipilih == null) {
      setState(() => _galat = 'Saluran pembayaran wajib dipilih.');
      return;
    }
    final total = nominal + _biayaAdmin;
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Topup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _barisKonfirmasi('Nominal topup', rupiah(nominal)),
            _barisKonfirmasi('Biaya admin', rupiah(_biayaAdmin)),
            const Divider(),
            _barisKonfirmasi('Total bayar', rupiah(total), tebal: true),
            const SizedBox(height: 12),
            const Text(
              'Saldo baru masuk setelah pembayaran berhasil dikonfirmasi oleh bank/gateway.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Buat Tagihan'),
          ),
        ],
      ),
    );
    if (lanjut == true) await _buatTopup();
  }

  Widget _barisKonfirmasi(String label, String nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(nilai,
              style: TextStyle(fontWeight: tebal ? FontWeight.bold : null)),
        ],
      ),
    );
  }

  Future<void> _buatTopup() async {
    setState(() {
      _membuat = true;
      _galat = null;
      _hasilTopup = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('kantin_topup_buat', {
        'cara_pembayaran_id': _saluranDipilih!['id'],
        'channel': '${_saluranDipilih!['channel'] ?? ''}',
        'gateway': '${_saluranDipilih!['gateway'] ?? 'smartlink'}',
        'nominal': _nominalInput(),
      });
      _hasilTopup = Map<String, dynamic>.from(hasil);
      final vaRes = await ApiClient.instance
          .aksi('kantin_va_list', const {'page': 1, 'limit': 20});
      _va = ApiClient.instance.daftar(vaRes);
    } on ApiException catch (e) {
      _galat = e.pesan;
    } finally {
      if (mounted) setState(() => _membuat = false);
    }
  }

  void _pilihNominal(int nilai) {
    _nominal.text = '$nilai';
    setState(() => _galat = null);
  }

  void _salin(String label, String nilai) {
    Clipboard.setData(ClipboardData(text: nilai));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label berhasil disalin.')),
    );
  }

  Future<void> _bukaLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _galat = 'Tautan pembayaran dari server tidak valid.');
      return;
    }
    final terbuka = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!terbuka && mounted) {
      setState(() => _galat = 'Tautan pembayaran tidak dapat dibuka.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuAnggota.isiSaldo,
      judul: 'Isi ${Sesi.instance.labelSaldo}',
      subjudul: 'Buat tagihan online dan pantau status pembayarannya.',
      onPilihMenu: navigasiMenu,
      child: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: LayoutBuilder(
                builder: (context, batas) {
                  final form = _panelTopup();
                  final riwayat = _panelRiwayat();
                  if (batas.maxWidth >= 900) {
                    return ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        if (_galat != null) ...[
                          PanelGalat(pesan: _galat!, onCobaLagi: _muat),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 390, child: form),
                            const SizedBox(width: 14),
                            Expanded(child: riwayat),
                          ],
                        ),
                      ],
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (_galat != null) ...[
                        PanelGalat(pesan: _galat!, onCobaLagi: _muat),
                        const SizedBox(height: 12),
                      ],
                      form,
                      const SizedBox(height: 14),
                      riwayat,
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _panelTopup() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${Sesi.instance.labelSaldo} saat ini',
                style: const TextStyle(fontSize: 12)),
            Text(rupiah(Sesi.instance.saldo),
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const Divider(height: 28),
            if (!Sesi.instance.aktifkanTopup)
              const Text('Fitur topup belum diaktifkan untuk akun Anda.',
                  style: TextStyle(color: Colors.black54))
            else if (_saluran.isEmpty)
              const Text(
                'Belum ada saluran topup online untuk jenis keanggotaan Anda.',
                style: TextStyle(color: Colors.black54),
              )
            else ...[
              const Text('Nominal topup',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _nominal,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  prefixText: 'Rp ',
                  hintText: 'Minimal 10.000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _nominalCepat
                    .map((n) => ActionChip(
                          label: Text(rupiah(n)),
                          onPressed: () => _pilihNominal(n),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _saluranDipilih,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cara bayar / kanal',
                  border: OutlineInputBorder(),
                ),
                items: _saluran
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_labelSaluran(s),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _saluranDipilih = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _membuat ? null : _konfirmasiTopup,
                icon: _membuat
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance_outlined),
                label: const Text('Buat Tagihan Topup'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Topup memerlukan internet. Saldo tidak berubah saat tagihan dibuat dan baru masuk setelah pembayaran terkonfirmasi.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
            if (_hasilTopup != null) ...[
              const Divider(height: 28),
              _hasilTagihan(_hasilTopup!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hasilTagihan(Map<String, dynamic> hasil) {
    final va = '${hasil['va'] ?? ''}'.trim();
    final link = '${hasil['link'] ?? ''}'.trim();
    final batasWaktu = '${hasil['billExpired'] ?? ''}'.trim();
    final nominal = ((hasil['topup'] as Map?)?['nilai'] as num?)?.toDouble() ??
        _nominalInput();
    final admin = (hasil['biayaAdministrasi'] as num?)?.toDouble() ?? 0;
    final total = (hasil['total'] as num?)?.toDouble() ?? nominal + admin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F766E),
                Color(0xFF0D9488),
                Color(0xFF0284C7),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'MENUNGGU PEMBAYARAN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (batasWaktu.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Batas: $batasWaktu',
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total yang Harus Dibayar',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rupiah(total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (total > 0)
                    FilledButton.icon(
                      onPressed: () =>
                          _salin('Nominal', '${total.round()}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Salin Nominal',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              if (admin > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Pokok ${rupiah(nominal)} + Biaya ${rupiah(admin)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
        if (va.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF5EEAD4), width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NOMOR VIRTUAL ACCOUNT',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        va,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _salin('Nomor VA', va),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Salin Kode',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (link.isNotEmpty) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _bukaLink(link),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Buka Halaman Pembayaran Online',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _panelRiwayat() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Riwayat Tagihan / Virtual Account',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Muat ulang status',
                  onPressed: _muat,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_va.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Belum ada tagihan.',
                    style: TextStyle(color: Colors.black54)),
              )
            else
              ..._va.map(_kartuVa),
          ],
        ),
      ),
    );
  }

  Widget _kartuVa(Map<String, dynamic> v) {
    final status = '${v['status_bayar'] ?? ''}'.toUpperCase();
    final warna = status == 'LUNAS'
        ? Colors.green
        : status == 'KEDALUWARSA'
            ? Colors.grey
            : Colors.orange;
    final total = (v['total'] as num?)?.toDouble() ?? 0;
    final kode = '${v['kode'] ?? ''}'.trim();
    final link = '${v['link'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: status == 'MENUNGGU' || status.isEmpty
            ? const Color(0xFFF8FAFC)
            : Colors.white,
        border: Border.all(
          color: status == 'MENUNGGU' || status.isEmpty
              ? const Color(0xFF99F6E4)
              : Colors.black12,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${v['bank'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(status.isEmpty ? 'MENUNGGU' : status,
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: warna.withValues(alpha: 0.15),
              ),
            ],
          ),
          if (kode.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: SelectableText(kode,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Salin VA',
                  onPressed: () => _salin('Nomor VA', kode),
                  icon: const Icon(Icons.copy_outlined,
                      size: 18, color: Color(0xFF0F766E)),
                ),
              ],
            ),
          if ('${v['batas_waktu'] ?? ''}'.trim().isNotEmpty)
            Text('Batas waktu: ${v['batas_waktu']}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Row(
            children: [
              Expanded(
                child: Text(rupiah(total),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F766E))),
              ),
              if (total > 0)
                IconButton(
                  tooltip: 'Salin Nominal',
                  onPressed: () => _salin('Nominal', '${total.round()}'),
                  icon: const Icon(Icons.copy_outlined,
                      size: 17, color: Color(0xFF0F766E)),
                ),
            ],
          ),
          if (status != 'LUNAS' && status != 'KEDALUWARSA' && link.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => _bukaLink(link),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Bayar Sekarang'),
              ),
            ),
        ],
      ),
    );
  }
}
