import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/server_config.dart';
import 'cara_bayar_screen.dart';
import 'jenis_produk_screen.dart';
import 'kelompok_aset_screen.dart';
import 'supplier_screen.dart';
import 'toko_kelola_screen.dart';

enum SisiAkunPosting { debet, kredit }

/// Tujuan CRUD sumber akun. Posting tidak boleh mengubah baris jurnal hasil
/// hitung secara langsung: yang diperbaiki adalah master sumbernya agar dokumen
/// lain dengan metode/jenis barang yang sama ikut benar.
class TargetCrudAkunPosting {
  const TargetCrudAkunPosting({
    required this.id,
    required this.label,
    required this.keterangan,
    this.webPath,
  });

  final String id;
  final String label;
  final String keterangan;
  final String? webPath;
}

const _caraBayar = TargetCrudAkunPosting(
  id: 'cara_bayar',
  label: 'Cara Pembayaran',
  keterangan: 'Ubah Akun Kas/Bank pada metode pembayaran.',
);
const _jenisProduk = TargetCrudAkunPosting(
  id: 'jenis_produk',
  label: 'Jenis Produk',
  keterangan: 'Ubah akun Pendapatan, PPN, HPP, retur, atau selisih stok.',
);
const _supplier = TargetCrudAkunPosting(
  id: 'supplier',
  label: 'Supplier (Penyedia)',
  keterangan: 'Ubah Akun Utang Dagang supplier.',
);
const _toko = TargetCrudAkunPosting(
  id: 'toko',
  label: 'Toko / Outlet',
  keterangan: 'Ubah Akun Kas/Bank atau Piutang Usaha toko.',
);
const _masterAset = TargetCrudAkunPosting(
  id: 'master_aset',
  label: 'Master Aset / Persediaan',
  keterangan: 'Ubah Akun Pembelian/Persediaan pada master aset barang.',
  webPath: 'pages/master/asset/master_asset.zul',
);
const _kelompokAset = TargetCrudAkunPosting(
  id: 'kelompok_aset',
  label: 'Kelompok Aset',
  keterangan: 'Ubah akun Persediaan, Pembelian, Penyusutan, atau HPP bawaan kelompok aset.',
);

/// Pemetaan ini dipakai tombol global maupun tombol pada baris yang belum siap.
/// [alasan] menyempitkan tujuan bila satu sisi punya beberapa sumber fallback.
List<TargetCrudAkunPosting> targetCrudAkunPosting({
  required String jenis,
  required SisiAkunPosting sisi,
  String alasan = '',
}) {
  final kunci = jenis.toLowerCase().replaceFirst('posting_', '');
  final kecil = alasan.toLowerCase();
  List<TargetCrudAkunPosting> hasil;
  switch (kunci) {
    case 'penjualan':
      hasil = sisi == SisiAkunPosting.debet
          ? const [_caraBayar]
          : const [_jenisProduk];
      break;
    case 'hpp':
      hasil = sisi == SisiAkunPosting.debet
          ? const [_jenisProduk, _kelompokAset]
          : const [_masterAset, _kelompokAset];
      break;
    case 'kulakan':
      hasil = sisi == SisiAkunPosting.debet
          ? const [_masterAset, _kelompokAset]
          : const [_supplier, _toko, _caraBayar];
      break;
    case 'bayar_hutang':
      hasil = sisi == SisiAkunPosting.debet
          ? const [_supplier]
          : const [_caraBayar, _toko];
      break;
    case 'terima_piutang':
      hasil = sisi == SisiAkunPosting.debet
          ? const [_caraBayar, _toko]
          : const [_toko, _caraBayar];
      break;
    case 'penyesuaian':
      hasil = const [
        _jenisProduk,
        _masterAset,
        _kelompokAset,
        _toko,
        _caraBayar
      ];
      break;
    default:
      hasil = const [_caraBayar, _jenisProduk, _supplier, _toko];
  }

  if (kecil.isEmpty || hasil.length == 1) return hasil;
  bool cocok(TargetCrudAkunPosting t) {
    if (kecil.contains('cara pembayaran') || kecil.contains('metode')) {
      return t.id == 'cara_bayar';
    }
    if (kecil.contains('utang supplier') || kecil.contains('penyedia')) {
      return t.id == 'supplier';
    }
    if (kecil.contains('piutang') || kecil.contains('kas/bank toko')) {
      return t.id == 'toko';
    }
    if (kecil.contains('jenis produk') ||
        kecil.contains('pendapatan') ||
        kecil.contains('ppn') ||
        (kecil.contains('hpp') && !kecil.contains('persediaan'))) {
      return t.id == 'jenis_produk';
    }
    if (kecil.contains('persediaan') || kecil.contains('master aset')) {
      return t.id == 'master_aset' || t.id == 'kelompok_aset';
    }
    return false;
  }

  final tersaring = hasil.where(cocok).toList(growable: false);
  return tersaring.isEmpty ? hasil : tersaring;
}

Future<void> bukaCrudAkunPosting(
  BuildContext context, {
  required String jenis,
  required SisiAkunPosting sisi,
  String alasan = '',
}) async {
  final daftar =
      targetCrudAkunPosting(jenis: jenis, sisi: sisi, alasan: alasan);
  TargetCrudAkunPosting? dipilih;
  if (daftar.length == 1) {
    dipilih = daftar.first;
  } else {
    dipilih = await showDialog<TargetCrudAkunPosting>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(sisi == SisiAkunPosting.debet
            ? 'Sesuaikan Akun Debet'
            : 'Sesuaikan Akun Kredit'),
        children: [
          for (final target in daftar)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, target),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(target.label),
                subtitle: Text(target.keterangan),
              ),
            ),
        ],
      ),
    );
  }
  if (dipilih == null || !context.mounted) return;

  Widget? halaman;
  switch (dipilih.id) {
    case 'cara_bayar':
      halaman = const CaraBayarScreen();
      break;
    case 'jenis_produk':
      halaman = const JenisProdukScreen();
      break;
    case 'kelompok_aset':
      halaman = const KelompokAsetScreen();
      break;
    case 'supplier':
      halaman = const SupplierScreen();
      break;
    case 'toko':
      halaman = const TokoKelolaScreen();
      break;
  }
  if (halaman != null) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => halaman!));
    return;
  }

  final path = dipilih.webPath;
  if (path == null) return;
  final uri =
      Uri.parse(ServerConfig.instance.baseUrlTanpaEndpoint).resolve(path);
  final terbuka = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!terbuka && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Form ${dipilih.label} tidak dapat dibuka: $uri')),
    );
  }
}

class TombolSesuaikanAkunPosting extends StatelessWidget {
  const TombolSesuaikanAkunPosting({
    super.key,
    required this.jenis,
    required this.sisi,
    this.alasan = '',
    this.ringkas = false,
  });

  final String jenis;
  final SisiAkunPosting sisi;
  final String alasan;
  final bool ringkas;

  @override
  Widget build(BuildContext context) {
    final label = sisi == SisiAkunPosting.debet
        ? 'Sesuaikan Akun Debet'
        : 'Sesuaikan Akun Kredit';
    return OutlinedButton.icon(
      key: ValueKey('sesuaikan_akun_${sisi.name}_$jenis'),
      onPressed: () => bukaCrudAkunPosting(
        context,
        jenis: jenis,
        sisi: sisi,
        alasan: alasan,
      ),
      icon: Icon(Icons.build_outlined, size: ringkas ? 14 : 17),
      label: Text(label, style: TextStyle(fontSize: ringkas ? 10.5 : null)),
      style: ringkas
          ? OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              visualDensity: VisualDensity.compact,
            )
          : null,
    );
  }
}
