import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Layar dapur (kitchen ticket) -- LANGKAH 5 MitraInap. Tiket dibuat otomatis
/// oleh checkout kasir (payload `hotel_tiket_dapur=true` pada aksi bayar,
/// idempoten per nota); layar ini hanya memindahkan status lewat
/// `hotel_kitchen_ticket_update`. Transisi DIVALIDASI SERVER
/// (QUEUED→PREPARING→READY→SERVED, batal hanya dari QUEUED/PREPARING) --
/// tombol di sini sekadar cermin aturan itu, bukan sumber kebenarannya.
class TiketDapurScreen extends StatefulWidget {
  const TiketDapurScreen({super.key});

  @override
  State<TiketDapurScreen> createState() => _TiketDapurScreenState();
}

class _TiketDapurScreenState extends State<TiketDapurScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _properti = [];
  int? _propertiId; // null = semua properti
  bool _hanyaAktif = true;
  List<Map<String, dynamic>> _tiket = [];

  @override
  void initState() {
    super.initState();
    _muatAwal();
  }

  Future<void> _muatAwal() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final data = await muatDaftarHotel('hotel_properti_list', {});
      setStateIfMounted(() => _properti = data);
      await _muatTiket();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muatTiket() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final body = <String, dynamic>{
        'status': _hanyaAktif ? 'AKTIF' : 'SEMUA',
        if (_propertiId != null) 'properti_id': _propertiId,
      };
      final data = await muatDaftarHotel('hotel_kitchen_ticket_list', body);
      setStateIfMounted(() {
        _tiket = data;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _ubahStatus(Map<String, dynamic> t, String ke) async {
    try {
      final res = await ApiClient.instance
          .aksi('hotel_kitchen_ticket_update', {'id': t['id'], 'status': ke});
      if (!mounted) return;
      if (apiSukses(res)) {
        _muatTiket();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal: ${apiPesan(res, 'transisi ditolak')}'),
            backgroundColor: Theme.of(context).colorScheme.error));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal memperbarui: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  Color _warnaStatus(String status) {
    switch (status) {
      case 'QUEUED':
        return Colors.orange;
      case 'PREPARING':
        return Colors.blue;
      case 'READY':
        return Colors.green;
      case 'SERVED':
        return Colors.grey;
      default:
        return Colors.red; // CANCELLED
    }
  }

  /// Cermin klien atas transisi sah server (tombol yang ditawarkan saja --
  /// server tetap menolak transisi liar).
  List<Widget> _tombolAksi(Map<String, dynamic> t) {
    final status = '${t['status'] ?? 'QUEUED'}';
    final aksi = <Widget>[];
    void tambah(String label, String ke, {bool bahaya = false}) {
      aksi.add(TextButton(
        onPressed: () => _ubahStatus(t, ke),
        child: Text(label,
            style: bahaya ? const TextStyle(color: Colors.red) : null),
      ));
    }

    if (status == 'QUEUED') {
      tambah('Mulai Masak', 'PREPARING');
      tambah('Batalkan', 'CANCELLED', bahaya: true);
    } else if (status == 'PREPARING') {
      tambah('Siap', 'READY');
      tambah('Batalkan', 'CANCELLED', bahaya: true);
    } else if (status == 'READY') {
      tambah('Sajikan', 'SERVED');
    }
    return aksi;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiket Dapur'),
        actions: [
          IconButton(
              onPressed: _memuat ? null : _muatTiket,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _propertiId,
                  decoration: const InputDecoration(
                      labelText: 'Properti',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Semua Properti')),
                    ..._properti.map((p) => DropdownMenuItem<int?>(
                        value: idInt(p['id']),
                        child: Text('${p['nama'] ?? p['id']}',
                            overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    setStateIfMounted(() => _propertiId = v);
                    _muatTiket();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_hanyaAktif ? 'Antrean Aktif' : 'Semua Status'),
                selected: _hanyaAktif,
                onSelected: (v) {
                  setStateIfMounted(() => _hanyaAktif = v);
                  _muatTiket();
                },
              ),
            ]),
            const SizedBox(height: 12),
            if (_galat != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_galat!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _tiket.isEmpty
                      ? const Center(child: Text('Tidak ada tiket.'))
                      : RefreshIndicator(
                          onRefresh: _muatTiket,
                          child: ListView.builder(
                            itemCount: _tiket.length,
                            itemBuilder: (context, i) {
                              final t = _tiket[i];
                              final status = '${t['status'] ?? 'QUEUED'}';
                              final item =
                                  (t['item'] as List? ?? const <dynamic>[])
                                      .whereType<Map>()
                                      .toList();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(
                                              'Nota ${t['kode_nota'] ?? '-'}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                        ),
                                        Chip(
                                          label: Text(status,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12)),
                                          backgroundColor:
                                              _warnaStatus(status),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                      ]),
                                      Text(
                                          '${t['waktu_nota'] ?? ''}'
                                          '${t['catatan'] == null || '${t['catatan']}'.isEmpty ? '' : ' — ${t['catatan']}'}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600)),
                                      const SizedBox(height: 6),
                                      ...item.map((r) => Text(
                                          '• ${r['nama'] ?? '-'} × ${angka(r['qty']).toStringAsFixed(angka(r['qty']) % 1 == 0 ? 0 : 2)}')),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: _tombolAksi(t),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
