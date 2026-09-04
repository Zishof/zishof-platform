import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/server_config.dart';
import 'cara_bayar_screen.dart';
import 'jenis_produk_screen.dart';
import 'kelompok_aset_screen.dart';
import 'supplier_screen.dart';
import 'toko_kelola_screen.dart';

enum SisiAkunPosting { debet, kredit }

({String debet, String kredit, String urutan}) sumberAkunPosting(String jenis) {
  final kunci = jenis.toLowerCase().replaceFirst('posting_', '');
  return switch (kunci) {
    'penjualan' => (
        debet:
            'Cara Pembayaran → Akun Kas/Bank; penjualan kredit memakai Toko → Piutang Usaha.',
        kredit:
            'Jenis Produk → Akun Pendapatan; PPN keluaran ditambahkan bila transaksi berpajak.',
        urutan:
            'Master transaksi → master terkait → konfigurasi cadangan Kantin. Akun induk dan akun kosong ditolak.'
      ),
    'hpp' => (
        debet:
            'Jenis Produk → Akun HPP; bila kosong sistem membaca akun HPP bawaan Kelompok Aset.',
        kredit:
            'Master Aset barang → Akun Persediaan; bila kosong sistem membaca Kelompok Aset.',
        urutan:
            'Jenis Produk/Master Aset → Kelompok Aset → konfigurasi cadangan Kantin. Akun Persediaan harus sama dengan debet Kulakan.'
      ),
    'kulakan' => (
        debet:
            'Master Aset barang → Akun Persediaan/Pembelian; bila kosong memakai Kelompok Aset.',
        kredit:
            'Pembelian kredit: Supplier → Akun Utang. Pembelian tunai: Cara Pembayaran/Toko → Akun Kas/Bank.',
        urutan:
            'Master Aset/Supplier → Kelompok Aset/Toko/Cara Pembayaran → konfigurasi cadangan Kantin.'
      ),
    'bayar_hutang' => (
        debet: 'Supplier → Akun Utang Dagang yang akan dikurangi.',
        kredit: 'Cara Pembayaran atau Toko → Akun Kas/Bank yang dibayarkan.',
        urutan:
            'Supplier dan metode bayar harus sesuai dokumen sumber; nilai tidak boleh melebihi sisa utang.'
      ),
    'terima_piutang' => (
        debet: 'Cara Pembayaran atau Toko → Akun Kas/Bank penerimaan.',
        kredit: 'Toko → Akun Piutang Usaha yang akan dikurangi.',
        urutan:
            'Toko dan metode penerimaan harus sesuai dokumen sumber; nilai tidak boleh melebihi sisa piutang.'
      ),
    'penyesuaian' => (
        debet:
            'Ditentukan oleh jenis mutasi: Persediaan, HPP/selisih stok, Kas, atau Piutang.',
        kredit:
            'Pasangan akun ditentukan oleh arah retur, hasil stok opname, atau mutasi antar-outlet.',
        urutan:
            'Alasan transaksi → Jenis Produk/Master Aset/Kelompok Aset → Toko/Cara Pembayaran.'
      ),
    _ => (
        debet:
            'Diambil dari master sumber transaksi yang menambah aset atau beban.',
        kredit:
            'Diambil dari master sumber transaksi yang menambah utang/pendapatan atau mengurangi aset.',
        urutan:
            'Periksa alasan pada baris, lalu buka master yang ditunjuk melalui tombol penyesuaian akun.'
      ),
  };
}

/// Penjelasan ringkas yang selalu terlihat di setiap layar posting. Pengguna
/// tidak perlu menebak mengapa sebuah kode akun muncul atau master mana yang
/// harus dibuka saat pasangan jurnalnya belum tepat.
class PenjelasanSumberAkunPosting extends StatelessWidget {
  const PenjelasanSumberAkunPosting({
    super.key,
    required this.jenis,
  });

  final String jenis;

  @override
  Widget build(BuildContext context) {
    final sumber = sumberAkunPosting(jenis);
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFF93C5FD)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.account_tree_outlined, size: 18, color: Color(0xFF1D4ED8)),
          SizedBox(width: 7),
          Text('Dari mana akun jurnal diambil?',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text('DEBET  •  ${sumber.debet}',
            style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 3),
        Text('KREDIT •  ${sumber.kredit}',
            style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 3),
        Text('Urutan pencarian: ${sumber.urutan}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        const SizedBox(height: 5),
        const Text(
          'Cara mengganti: gunakan tombol Sesuaikan Akun Debet/Kredit di bawah. '
          'Sistem membuka master sumbernya, lalu muat ulang pratinjau. Posting '
          'hanya aktif untuk akun daun dan pasangan dengan total Debet = Kredit.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

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
  keterangan:
      'Ubah akun Persediaan, Pembelian, Penyusutan, atau HPP bawaan kelompok aset.',
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
    this.onSelesai,
  });

  final String jenis;
  final SisiAkunPosting sisi;
  final String alasan;
  final bool ringkas;
  final Future<void> Function()? onSelesai;

  @override
  Widget build(BuildContext context) {
    final label = sisi == SisiAkunPosting.debet
        ? 'Sesuaikan Akun Debet'
        : 'Sesuaikan Akun Kredit';
    return OutlinedButton.icon(
      key: ValueKey('sesuaikan_akun_${sisi.name}_$jenis'),
      onPressed: () async {
        await bukaCrudAkunPosting(
          context,
          jenis: jenis,
          sisi: sisi,
          alasan: alasan,
        );
        if (onSelesai != null) await onSelesai!();
      },
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
