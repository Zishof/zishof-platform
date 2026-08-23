import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/app_components.dart';
import '../api_client.dart';

/// Field pemilih **anggaran** (Workspace/RAB) untuk satu baris rincian biaya.
///
/// Kenapa ada di baris rincian, bukan di kepala dokumen: pemotongan anggaran di
/// AIS dicatat per baris. `PenggunaanAnggaran.prosesKasKecil`/`prosesKasBesar`
/// membaca field `workspace` pada tiap baris `formula`; baris tanpa field itu
/// dilewati dan anggarannya tidak pernah terpotong. Layar ZK memakai banbox
/// anggaran per baris untuk alasan yang sama.
///
/// Server tetap menebak anggaran dari akun biaya bila field ini dikosongkan
/// (lihat `AnggaranKeuanganUtil.lengkapiRincian`), jadi pemakainya boleh
/// memilih akun saja. Field ini dipakai ketika satu akun dipakai beberapa
/// anggaran dan pengguna ingin menunjuk yang mana.
class PemilihAnggaranField extends StatelessWidget {
  const PemilihAnggaranField({
    super.key,
    required this.aksiCari,
    required this.workspaceId,
    required this.namaAnggaran,
    required this.onDipilih,
    this.tahun,
    this.helperText,
  });

  /// Nama aksi pencarian milik modul, mis. `kas_kecil_cari_anggaran`.
  final String aksiCari;

  final String? workspaceId;
  final String? namaAnggaran;

  /// Dipanggil dengan baris anggaran terpilih, atau `null` bila dikosongkan.
  final ValueChanged<Map<String, dynamic>?> onDipilih;

  /// Tahun dokumen: anggaran difilter per tahun, sama seperti di ZK.
  final int? tahun;

  final String? helperText;

  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  @override
  Widget build(BuildContext context) {
    final terisi = (workspaceId ?? '').isNotEmpty;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Anggaran',
        helperText: helperText ??
            'Kosongkan bila ingin server menebaknya dari akun biaya.',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            terisi ? (namaAnggaran ?? 'Anggaran #$workspaceId') : 'Belum dipilih',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (terisi)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Kosongkan',
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () => onDipilih(null),
          ),
        TextButton(
          onPressed: () async {
            final pilihan = await _cari(context);
            if (pilihan != null) onDipilih(pilihan);
          },
          child: const Text('Pilih'),
        ),
      ]),
    );
  }

  Future<Map<String, dynamic>?> _cari(BuildContext context) {
    final kata = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    bool memuat = false;
    String galat = '';
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          Future<void> jalankan() async {
            setD(() {
              memuat = true;
              galat = '';
            });
            try {
              final res = await ApiClient.instance.aksi(aksiCari, {
                'cari': kata.text.trim(),
                if (tahun != null) 'tahun': tahun,
              });
              hasil = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              galat = '$e';
            } finally {
              setD(() => memuat = false);
            }
          }

          if (hasil.isEmpty && !memuat && galat.isEmpty && kata.text.isEmpty) {
            // Sekali muat di awal supaya daftar tahun berjalan langsung terlihat.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (kata.text.isEmpty && hasil.isEmpty) jalankan();
            });
          }

          return AlertDialog(
            title: const Text('Pilih Anggaran'),
            content: SizedBox(
              width: 620,
              height: 420,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: AppSearchField(
                      controller: kata,
                      hintText: 'Cari kode / nama anggaran',
                      onChanged: (_) => jalankan(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: jalankan, child: const Text('Cari')),
                ]),
                const SizedBox(height: 8),
                if (galat.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(galat, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                Expanded(
                  child: memuat
                      ? const Center(child: CircularProgressIndicator())
                      : hasil.isEmpty
                          ? const Center(
                              child: Text('Tidak ada anggaran aktif untuk tahun ini.'))
                          : ListView.builder(
                              itemCount: hasil.length,
                              itemBuilder: (_, i) {
                                final w = hasil[i];
                                final pagu = (w['pagu'] as num?)?.toDouble() ?? 0;
                                final realisasi = (w['realisasi'] as num?)?.toDouble() ?? 0;
                                return ListTile(
                                  dense: true,
                                  title: Text('${w['kode'] ?? ''} — ${w['nama'] ?? ''}'),
                                  subtitle: Text(
                                      'Pagu ${_uang.format(pagu)}'
                                      ' • realisasi ${_uang.format(realisasi)}'
                                      ' • ${w['satuanKerja'] ?? '-'}'
                                      '${(w['akunKode'] ?? '').toString().isEmpty ? '' : ' • akun ${w['akunKode']}'}'),
                                  onTap: () => Navigator.pop(c, w),
                                );
                              },
                            ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ],
          );
        },
      ),
    );
  }
}
