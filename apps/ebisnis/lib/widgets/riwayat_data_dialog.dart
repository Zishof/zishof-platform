import 'package:flutter/material.dart';

import '../api_client.dart';

/// <h3>Dialog "Riwayat Data" per baris -- membaca AuditTrails/Envers lewat aksi
/// `revisi_daftar`/`revisi_detail`/`revisi_pulihkan` (RevisiApiHelper, padanan
/// GenericRevisiHelper ZK).</h3>
///
/// Dipanggil dari tombol riwayat (ikon jam) di baris tabel master mana pun:
/// `tampilkanRiwayatData(context, entitas: 'produk', id: 123, judul: nama)`.
/// Semua user login boleh MELIHAT; tombol "Pulihkan" hanya muncul bila server
/// menyatakan `bolehPulihkan` (Common.apakahAdminLain == true). Riwayat butuh
/// server (Envers) -- saat offline dialog menampilkan pesan yang jujur.
Future<void> tampilkanRiwayatData(
  BuildContext context, {
  required String entitas,
  required Object id,
  String? judul,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RiwayatDataDialog(entitas: entitas, id: id, judul: judul),
  );
}

class _RiwayatDataDialog extends StatefulWidget {
  final String entitas;
  final Object id;
  final String? judul;
  const _RiwayatDataDialog(
      {required this.entitas, required this.id, this.judul});

  @override
  State<_RiwayatDataDialog> createState() => _RiwayatDataDialogState();
}

class _RiwayatDataDialogState extends State<_RiwayatDataDialog> {
  bool _memuat = true;
  String? _galat;
  bool _bolehPulihkan = false;
  List<Map<String, dynamic>> _revisi = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final res = await ApiClient.instance.aksi('revisi_daftar', {
        'entitas': widget.entitas,
        'id': widget.id,
      });
      if (res['status'] != '00' && res['status'] != 'success') {
        throw Exception(res['description'] ?? 'Gagal memuat riwayat.');
      }
      if (!mounted) return;
      setState(() {
        _revisi = ((res['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _bolehPulihkan = res['bolehPulihkan'] == true;
        _memuat = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = e.offline
            ? 'Riwayat revisi dibaca dari server — tidak tersedia saat offline.'
            : e.pesan;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _lihatDetail(Map<String, dynamic> r) async {
    try {
      final res = await ApiClient.instance.aksi('revisi_detail', {
        'entitas': widget.entitas,
        'id': widget.id,
        'rev': r['rev'],
      });
      final nilai = (res['nilai'] as Map?) ?? {};
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Nilai pada revisi ${r['rev']}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in nilai.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: 160,
                              child: Text('${e.key}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          Expanded(
                              child: Text('${e.value ?? '-'}',
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pulihkan(Map<String, dynamic> r) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pulihkan data dari riwayat?'),
        content: Text(
            'Nilai data akan dikembalikan ke keadaan revisi ${r['rev']} '
            '(${r['tanggal']}). Perubahan setelah revisi itu akan tertimpa '
            '— dan pemulihan ini pun tercatat sebagai revisi baru.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Pulihkan')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      final res = await ApiClient.instance.aksi('revisi_pulihkan', {
        'entitas': widget.entitas,
        'id': widget.id,
        'rev': r['rev'],
      });
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sukses
              ? '${res['description'] ?? 'Data dipulihkan.'}'
              : 'Gagal: ${res['description'] ?? res['status']}')));
      if (sukses && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Color _warnaTipe(String tipe) => tipe == 'TAMBAH'
      ? Colors.green
      : tipe == 'HAPUS'
          ? Colors.red
          : Colors.orange;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.judul == null
          ? 'Riwayat Data'
          : 'Riwayat Data — ${widget.judul}'),
      content: SizedBox(
        width: 520,
        height: 400,
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Text(_galat!, textAlign: TextAlign.center))
                : _revisi.isEmpty
                    ? const Center(
                        child: Text('Belum ada riwayat utk data ini.'))
                    : ListView.separated(
                        itemCount: _revisi.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final r = _revisi[i];
                          final tipe = '${r['tipe'] ?? 'UBAH'}';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              tipe == 'TAMBAH'
                                  ? Icons.add_circle_outline
                                  : tipe == 'HAPUS'
                                      ? Icons.delete_outline
                                      : Icons.edit_outlined,
                              color: _warnaTipe(tipe),
                            ),
                            title: Text(
                                'Rev ${r['rev']} • $tipe'
                                '${r['oleh'] != null ? ' • ${r['oleh']}' : ''}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text('${r['tanggal'] ?? '-'}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    tooltip: 'Lihat nilai revisi ini',
                                    icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 20),
                                    onPressed: () => _lihatDetail(r)),
                                if (_bolehPulihkan)
                                  IconButton(
                                      tooltip:
                                          'Pulihkan data ke revisi ini (admin)',
                                      icon: const Icon(Icons.restore,
                                          size: 20),
                                      onPressed: () => _pulihkan(r)),
                              ],
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup')),
      ],
    );
  }
}
