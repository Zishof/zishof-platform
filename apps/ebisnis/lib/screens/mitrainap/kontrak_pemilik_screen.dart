import 'package:flutter/material.dart';

import '../../widgets/indikator_sinkron_master.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/riwayat_data_dialog.dart';
import '../../widgets/safe_state.dart';
import 'mitrainap_common.dart';

/// Kontrak pemilik kamar (kondotel) -- LANGKAH 5 MitraInap. Satu kamar dimiliki
/// investor; operator memungut `persen_komisi` dari pendapatan kamar. Angka
/// pendapatan TIDAK pernah diisi dari layar ini -- statement dihitung server
/// (lihat LaporanPemilikScreen / aksi hotel_laporan_pemilik_generate).
class KontrakPemilikScreen extends StatefulWidget {
  const KontrakPemilikScreen({super.key});

  @override
  State<KontrakPemilikScreen> createState() => _KontrakPemilikScreenState();
}

class _KontrakPemilikScreenState extends State<KontrakPemilikScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _properti = [];
  int? _propertiId;
  List<Map<String, dynamic>> _kontrak = [];

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
      await _muatKontrak();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muatKontrak() async {
    final pid = _propertiId;
    if (pid == null) {
      setStateIfMounted(() {
        _kontrak = [];
        _memuat = false;
      });
      return;
    }
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final data =
          await muatDaftarHotel('hotel_kontrak_pemilik_list', {'properti_id': pid});
      setStateIfMounted(() {
        _kontrak = data;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _formKontrak(Map<String, dynamic>? awal) async {
    final pid = _propertiId;
    if (pid == null) return;
    List<Map<String, dynamic>> kamar;
    try {
      kamar = await muatDaftarHotel('hotel_kamar_list', {'properti_id': pid});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal memuat kamar: $e')));
      return;
    }
    if (!mounted) return;
    if (kamar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Belum ada kamar pada properti ini.')));
      return;
    }
    int? kamarId = idInt(awal?['kamar_id']) ?? idInt(kamar.first['id']);
    final namaC = TextEditingController(text: '${awal?['nama_pemilik'] ?? ''}');
    final refC =
        TextEditingController(text: '${awal?['referensi_pemilik'] ?? ''}');
    final persenC =
        TextEditingController(text: '${awal?['persen_komisi'] ?? 20}');
    DateTime? dari = awal?['berlaku_dari'] == null
        ? DateTime.now()
        : DateTime.tryParse('${awal?['berlaku_dari']}');
    DateTime? sampai = awal?['berlaku_sampai'] == null
        ? null
        : DateTime.tryParse('${awal?['berlaku_sampai']}');
    bool aktif = awal == null || awal['aktif'] == true;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) {
        Future<void> pilihTanggal(bool awalPeriode) async {
          final hasil = await showDatePicker(
            context: c2,
            initialDate: (awalPeriode ? dari : sampai) ?? DateTime.now(),
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
          title: Text(awal == null ? 'Kontrak Baru' : 'Ubah Kontrak'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  value: kamarId,
                  decoration: const InputDecoration(
                      labelText: 'Kamar', border: OutlineInputBorder(), isDense: true),
                  items: kamar
                      .map((k) => DropdownMenuItem<int>(
                          value: idInt(k['id']),
                          child: Text('Kamar ${k['nomor'] ?? k['id']}')))
                      .toList(),
                  onChanged: (v) => setD(() => kamarId = v),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: namaC,
                    decoration: const InputDecoration(
                        labelText: 'Nama Pemilik *', isDense: true)),
                const SizedBox(height: 8),
                TextField(
                    controller: refC,
                    decoration: const InputDecoration(
                        labelText: 'Referensi (KTP/NPWP/kode investor)',
                        isDense: true)),
                const SizedBox(height: 8),
                TextField(
                    controller: persenC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Komisi Operator (%) 0..100', isDense: true)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => pilihTanggal(true),
                      child: Text('Dari: ${dari == null ? '-' : formatTanggalHotel.format(dari!)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => pilihTanggal(false),
                      child: Text(
                          'Sampai: ${sampai == null ? '(tanpa batas)' : formatTanggalHotel.format(sampai!)}'),
                    ),
                  ),
                ]),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: aktif,
                  onChanged: (v) => setD(() => aktif = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c2).pop(false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.of(c2).pop(true),
                child: const Text('Simpan')),
          ],
        );
      }),
    );
    if (simpan != true || !mounted) return;

    final persen = double.tryParse(persenC.text.trim()) ?? -1;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      // Saat offline daftar TIDAK dimuat ulang (muatDaftarHotel online-only).
      final res = await prosesSimpanMaster(context,
          aksi: 'hotel_kontrak_pemilik_simpan',
          body: {
            if (awal != null) 'id': awal['id'],
            'properti_id': pid,
            'kamar_id': kamarId,
            'nama_pemilik': namaC.text.trim(),
            'referensi_pemilik': refC.text.trim(),
            'persen_komisi': persen,
            'berlaku_dari':
                dari == null ? null : formatTanggalHotel.format(dari!),
            if (sampai != null)
              'berlaku_sampai': formatTanggalHotel.format(sampai!),
            'aktif': aktif,
          },
          kunci: awal != null
              ? 'hotel_kontrak:${awal['id']}'
              : 'hotel_kontrak:baru:${DateTime.now().microsecondsSinceEpoch}');
      if (!mounted) return;
      if (res['offline'] != true) _muatKontrak();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontrak Pemilik'),
        actions: const [IndikatorSinkronMaster()],
      ),
      floatingActionButton: _propertiId == null
          ? null
          : FloatingActionButton(
              onPressed: () => _formKontrak(null),
              tooltip: 'Kontrak baru',
              child: const Icon(Icons.add)),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PilihPropertiHotel(
              daftar: _properti,
              nilai: _propertiId,
              onUbah: (v) {
                setStateIfMounted(() => _propertiId = v);
                _muatKontrak();
              },
            ),
            const SizedBox(height: 12),
            if (_galat != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_galat!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _kontrak.isEmpty
                      ? const Center(
                          child: Text('Belum ada kontrak pada properti ini.'))
                      : ListView.builder(
                          itemCount: _kontrak.length,
                          itemBuilder: (context, i) {
                            final k = _kontrak[i];
                            final aktif = k['aktif'] == true;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(Icons.meeting_room,
                                    color: aktif ? Colors.teal : Colors.grey),
                                title: Row(children: [
                                  Expanded(
                                      child: Text(
                                          'Kamar ${k['kamar_nomor'] ?? '-'} — ${k['nama_pemilik'] ?? '-'}')),
                                  IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip:
                                          'Riwayat data ini (AuditTrails)',
                                      icon: const Icon(Icons.history,
                                          size: 16),
                                      onPressed: () => tampilkanRiwayatData(
                                          context,
                                          entitas: 'hotel_kontrak',
                                          id: k['id'],
                                          judul:
                                              'Kamar ${k['kamar_nomor'] ?? '-'}')),
                                ]),
                                subtitle: Text(
                                    'Komisi ${angka(k['persen_komisi']).toStringAsFixed(2)}% · '
                                    '${k['berlaku_dari'] ?? '-'} s/d ${k['berlaku_sampai'] ?? 'tanpa batas'}'
                                    '${aktif ? '' : ' · NONAKTIF'}'),
                                onTap: () => _formKontrak(k),
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
