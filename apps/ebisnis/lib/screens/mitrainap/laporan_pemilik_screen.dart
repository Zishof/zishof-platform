import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Statement pemilik kamar -- LANGKAH 5 MitraInap. Seluruh angka DIHITUNG
/// SERVER saat generate (`hotel_laporan_pemilik_generate`) dari baris
/// ROOM_CHARGE folio kamar kontrak pada periode; layar ini hanya memilih
/// kontrak+periode dan menampilkan hasil (termasuk snapshot rincian dan
/// SHA-256 dokumen). Generate periode yang sama = idempoten (server
/// mengembalikan laporan yang sudah terbit).
class LaporanPemilikScreen extends StatefulWidget {
  const LaporanPemilikScreen({super.key});

  @override
  State<LaporanPemilikScreen> createState() => _LaporanPemilikScreenState();
}

class _LaporanPemilikScreenState extends State<LaporanPemilikScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _properti = [];
  int? _propertiId;
  List<Map<String, dynamic>> _kontrak = [];
  int? _kontrakId; // null = semua kontrak properti ini
  List<Map<String, dynamic>> _laporan = [];

  @override
  void initState() {
    super.initState();
    _muatProperti();
  }

  Future<void> _muatProperti() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final data = await muatDaftarHotel('hotel_properti_list', {});
      final id = _propertiId ?? (data.isNotEmpty ? idInt(data.first['id']) : null);
      setStateIfMounted(() {
        _properti = data;
        _propertiId = id;
      });
      await _muatKontrakDanLaporan();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muatKontrakDanLaporan() async {
    final pid = _propertiId;
    if (pid == null) {
      setStateIfMounted(() {
        _kontrak = [];
        _laporan = [];
        _memuat = false;
      });
      return;
    }
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final kontrak =
          await muatDaftarHotel('hotel_kontrak_pemilik_list', {'properti_id': pid});
      final adaKontrakTerpilih =
          kontrak.any((k) => idInt(k['id']) == _kontrakId);
      final laporan = await muatDaftarHotel('hotel_laporan_pemilik_list', {
        if (adaKontrakTerpilih && _kontrakId != null)
          'kontrak_id': _kontrakId
        else
          'properti_id': pid,
      });
      setStateIfMounted(() {
        _kontrak = kontrak;
        if (!adaKontrakTerpilih) _kontrakId = null;
        _laporan = laporan;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _generate() async {
    final kontrakAktif =
        _kontrak.where((k) => k['aktif'] == true).toList();
    if (kontrakAktif.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Belum ada kontrak aktif. Buat di menu Kontrak Pemilik.')));
      return;
    }
    int? kontrakId = _kontrakId ?? idInt(kontrakAktif.first['id']);
    final kini = DateTime.now();
    DateTime dari = DateTime(kini.year, kini.month, 1);
    DateTime sampai = DateTime(kini.year, kini.month + 1, 0);
    final biayaC = TextEditingController(text: '0');

    final lanjut = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) {
        Future<void> pilih(bool awalPeriode) async {
          final hasil = await showDatePicker(
            context: c2,
            initialDate: awalPeriode ? dari : sampai,
            firstDate: DateTime(2020),
            lastDate: DateTime(2040),
          );
          if (hasil != null) {
            setD(() {
              if (awalPeriode) {
                dari = hasil;
              } else {
                sampai = hasil;
              }
            });
          }
        }

        return AlertDialog(
          title: const Text('Terbitkan Laporan Pemilik'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: kontrakId,
                decoration: const InputDecoration(
                    labelText: 'Kontrak', border: OutlineInputBorder(), isDense: true),
                items: kontrakAktif
                    .map((k) => DropdownMenuItem<int>(
                        value: idInt(k['id']),
                        child: Text(
                            'Kamar ${k['kamar_nomor'] ?? '-'} — ${k['nama_pemilik'] ?? '-'}',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setD(() => kontrakId = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => pilih(true),
                      child: Text('Dari: ${formatTanggalHotel.format(dari)}')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => pilih(false),
                      child:
                          Text('Sampai: ${formatTanggalHotel.format(sampai)}')),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: biayaC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Biaya lain-lain (opsional, mengurangi bersih)',
                      isDense: true)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c2).pop(false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.of(c2).pop(true),
                child: const Text('Terbitkan')),
          ],
        );
      }),
    );
    if (lanjut != true || !mounted) return;

    try {
      final res = await ApiClient.instance.aksi('hotel_laporan_pemilik_generate', {
        'kontrak_id': kontrakId,
        'periode_mulai': formatTanggalHotel.format(dari),
        'periode_selesai': formatTanggalHotel.format(sampai),
        'biaya': double.tryParse(biayaC.text.trim()) ?? 0,
      });
      if (!mounted) return;
      if (apiSukses(res)) {
        final idem = res['idempotent'] == true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(idem
                ? 'Periode ini sudah pernah terbit — menampilkan laporan yang ada.'
                : 'Laporan terbit: kotor ${formatRupiahHotel.format(angka(res['pendapatan_kotor']))}, '
                    'bersih ${formatRupiahHotel.format(angka(res['bersih_dibayarkan']))} '
                    '(${res['jumlah_transaksi']} transaksi).')));
        _muatKontrakDanLaporan();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal: ${apiPesan(res, 'validasi server')}'),
            backgroundColor: Theme.of(context).colorScheme.error));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menerbitkan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  void _detail(Map<String, dynamic> lp) {
    List<Map<String, dynamic>> rincian = [];
    try {
      final snap = jsonDecode('${lp['snapshot'] ?? '{}'}') as Map;
      rincian = ((snap['transaksi'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // snapshot korup/legacy: tampilkan ringkasan saja.
    }
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Laporan #${lp['id']} — Kamar ${lp['kamar_nomor'] ?? '-'}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pemilik: ${lp['nama_pemilik'] ?? '-'}'),
                Text(
                    'Periode: ${lp['periode_mulai']} s/d ${lp['periode_selesai']}'),
                const Divider(),
                Text(
                    'Pendapatan kotor: ${formatRupiahHotel.format(angka(lp['pendapatan_kotor']))}'),
                Text('Komisi operator: ${formatRupiahHotel.format(angka(lp['komisi']))}'),
                Text('Biaya lain: ${formatRupiahHotel.format(angka(lp['biaya']))}'),
                Text(
                    'Bersih dibayarkan: ${formatRupiahHotel.format(angka(lp['bersih_dibayarkan']))}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                Text('Rincian ROOM_CHARGE (${rincian.length} baris):',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                ...rincian.map((r) => Text(
                    '${r['waktu'] ?? '-'} — ${formatRupiahHotel.format(angka(r['jumlah']))}'
                    '${r['referensi'] == null ? '' : ' (${r['referensi']})'}',
                    style: const TextStyle(fontSize: 12))),
                const Divider(),
                SelectableText('SHA-256: ${lp['dokumen_hash'] ?? '-'}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Pemilik')),
      floatingActionButton: _propertiId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _generate,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Terbitkan')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: PilihPropertiHotel(
                  daftar: _properti,
                  nilai: _propertiId,
                  onUbah: (v) {
                    setStateIfMounted(() {
                      _propertiId = v;
                      _kontrakId = null;
                    });
                    _muatKontrakDanLaporan();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _kontrakId,
                  decoration: const InputDecoration(
                      labelText: 'Kontrak',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('Semua Kontrak')),
                    ..._kontrak.map((k) => DropdownMenuItem<int?>(
                        value: idInt(k['id']),
                        child: Text(
                            'Kamar ${k['kamar_nomor'] ?? '-'} — ${k['nama_pemilik'] ?? '-'}',
                            overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    setStateIfMounted(() => _kontrakId = v);
                    _muatKontrakDanLaporan();
                  },
                ),
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
                  : _laporan.isEmpty
                      ? const Center(child: Text('Belum ada laporan.'))
                      : ListView.builder(
                          itemCount: _laporan.length,
                          itemBuilder: (context, i) {
                            final lp = _laporan[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.receipt_long),
                                title: Text(
                                    'Kamar ${lp['kamar_nomor'] ?? '-'} — ${lp['nama_pemilik'] ?? '-'}'),
                                subtitle: Text(
                                    '${lp['periode_mulai']} s/d ${lp['periode_selesai']} · '
                                    'bersih ${formatRupiahHotel.format(angka(lp['bersih_dibayarkan']))}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _detail(lp),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
