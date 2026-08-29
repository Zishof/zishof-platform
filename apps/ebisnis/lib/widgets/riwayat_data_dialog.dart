import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  static final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static const _labelField = <String, String>{
    'kode': 'Kode produk',
    'barcode': 'Barcode',
    'nama': 'Nama produk',
    'jenisProduk': 'Kategori/Jenis produk',
    'jenisItem': 'Jenis item',
    'hargaBeli': 'Harga beli',
    'hargaJual': 'Harga jual',
    'stok': 'Stok',
    'stokMinimum': 'Stok minimum',
    'aktif': 'Status aktif',
    'satuan': 'Satuan penjualan/dasar',
    'satuanPembelian': 'Satuan pembelian',
    'pemasok': 'Pemasok utama',
    'toko': 'Toko',
    'batch': 'Batch',
    'tanggalExpired': 'Tanggal kedaluwarsa',
    'imageUrl': 'Alamat foto',
    'imagePath': 'Lokasi foto',
    'adaFileGambar': 'Memiliki foto',
    'izinkanJualMinusStok': 'Boleh dijual saat stok minus',
    'bahanBaku': 'Resep/bahan baku',
    'ekstraPilihan': 'Pilihan ekstra',
    'kemasan': 'Kemasan/barcode multi-unit',
    'grupProduk': 'Grup produk',
    'rute': 'Rute pemenuhan stok',
    'perluQc': 'Wajib pemeriksaan mutu (QC)',
    'catatan': 'Catatan',
    'keterangan': 'Keterangan',
    'kodeIdentitas': 'Kode identitas',
    'jenisIdentitas': 'Jenis identitas',
    'alamat': 'Alamat',
    'userid': 'ID pengguna',
    'tanggalKadaluarsa': 'Tanggal kedaluwarsa akun',
    'koperasi': 'Koperasi',
    'mahasiswa': 'Data mahasiswa',
    'dosen': 'Data dosen',
    'guru': 'Data guru',
    'siswa': 'Data siswa',
    'calonSiswa': 'Data calon siswa',
    'pegawai': 'Data pegawai',
    'tbmuser': 'Akun pengguna',
    'satuanKerja': 'Satuan kerja',
    'jenisAnggotaKoperasi': 'Jenis member',
    'tipeAnggotaKoperasi': 'Tipe member',
    'tipe': 'Tipe',
    'telp': 'Telepon',
    'hp': 'Nomor HP',
    'nomorHpNormalisasi': 'Nomor HP ternormalisasi',
    'email': 'Email',
    'jenisIdentitasAnggotaKoperasi': 'Master jenis identitas',
    'tanggal': 'Tanggal menjadi member',
    'dibuatOleh': 'Dibuat oleh',
    'calonAnggotaKoperasi': 'Pengajuan calon member',
    'tanggalBerhenti': 'Tanggal berhenti',
    'alasanBerhenti': 'Alasan berhenti',
    'pihakTerkait': 'Pihak terkait',
    'kelasLesDipilih': 'Kelas les dipilih',
    'jumlahPeringatan': 'Jumlah peringatan',
    'limitKredit': 'Batas kredit/piutang',
  };
  bool _memuat = true;
  String? _galat;
  bool _bolehPulihkan = false;
  List<Map<String, dynamic>> _revisi = [];

  String _label(String field) {
    final khusus = _labelField[field];
    if (khusus != null) return khusus;
    final bersih = field
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ');
    if (bersih.isEmpty) return field;
    return bersih
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');
  }

  String _nilai(Object? nilai, String field) {
    if (nilai == null) return '(kosong)';
    if (nilai is bool) return nilai ? 'Ya/Aktif' : 'Tidak/Nonaktif';
    if (nilai is num && field.toLowerCase().contains('harga')) {
      return _rupiah.format(nilai);
    }
    final teks = '$nilai'.trim();
    return teks.isEmpty || teks == 'null' ? '(kosong)' : teks;
  }

  List<Map<String, dynamic>> _perubahan(Map<String, dynamic> revisi) =>
      ((revisi['perubahan'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Future<void> _lihatPerubahan(Map<String, dynamic> revisi) async {
    final perubahan = _perubahan(revisi);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Perubahan revisi ${revisi['rev']}'),
        content: SizedBox(
          width: 620,
          child: perubahan.isEmpty
              ? const Text(
                  'Tidak ada perbedaan field bisnis yang dapat ditampilkan. '
                  'Kemungkinan revisi hanya mengubah metadata teknis audit.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${revisi['tanggal'] ?? '-'}'
                        '${revisi['oleh'] == null ? '' : ' · oleh ${revisi['oleh']}'}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      for (final p in perubahan)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_label('${p['field'] ?? ''}'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text('${p['jenisData'] ?? 'Data'}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black54)),
                              const SizedBox(height: 5),
                              SelectableText(
                                '${_nilai(p['dari'], '${p['field']}')}  →  '
                                '${_nilai(p['menjadi'], '${p['field']}')}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pulihkan(Map<String, dynamic> r) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pulihkan data dari riwayat?'),
        content:
            Text('Nilai data akan dikembalikan ke keadaan revisi ${r['rev']} '
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
                ? Center(child: Text(_galat!, textAlign: TextAlign.center))
                : _revisi.isEmpty
                    ? const Center(
                        child: Text('Belum ada riwayat utk data ini.'))
                    : ListView.separated(
                        itemCount: _revisi.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final r = _revisi[i];
                          final tipe = '${r['tipe'] ?? 'UBAH'}';
                          final perubahan = _perubahan(r);
                          final ringkas = perubahan.take(2).map((p) {
                            final field = '${p['field'] ?? ''}';
                            return '${_label(field)}: '
                                '${_nilai(p['dari'], field)} → '
                                '${_nilai(p['menjadi'], field)}';
                          }).join('\n');
                          return ListTile(
                            dense: true,
                            isThreeLine: perubahan.isNotEmpty,
                            onTap: () => _lihatPerubahan(r),
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
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${r['tanggal'] ?? '-'}'
                                '${ringkas.isEmpty ? '' : '\n$ringkas'}'
                                '${perubahan.length > 2 ? '\n+${perubahan.length - 2} data lain berubah' : ''}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    tooltip: 'Lihat seluruh nilai pada revisi',
                                    icon: const Icon(Icons.visibility_outlined,
                                        size: 20),
                                    onPressed: () => _lihatDetail(r)),
                                if (_bolehPulihkan)
                                  IconButton(
                                      tooltip:
                                          'Pulihkan data ke revisi ini (admin)',
                                      icon: const Icon(Icons.restore, size: 20),
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
