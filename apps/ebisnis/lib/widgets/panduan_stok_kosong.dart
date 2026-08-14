import 'package:flutter/material.dart';

/// Panduan operasional sengaja lengkap (lebih dari 350 kata) agar kasir dapat
/// menyelesaikan masalah stok tanpa mencoba pembayaran berulang atau meminta
/// admin mengubah database secara langsung.
const String panduanStokKosong = '''
Pembayaran dihentikan karena jumlah stok yang tercatat di sistem lebih kecil daripada jumlah yang diminta dalam keranjang. Penghentian ini merupakan perlindungan data, bukan tanda bahwa uang pelanggan sudah diterima. Sistem tidak membuat transaksi penjualan, tidak mengurangi saldo member, dan tidak boleh mencetak struk lunas. Jangan menekan tombol Bayar berulang kali sebelum kondisi stok diselesaikan. Baca nama produk, stok tersisa, dan jumlah yang diminta pada bagian “Barang terdampak” di atas, lalu cocokkan dengan barang fisik yang benar-benar berada di meja kasir.

Langkah pertama, bila jumlah di keranjang memang terlalu banyak, tutup panduan ini, kurangi kuantitas sampai tidak melebihi stok tersedia, atau keluarkan barang yang kosong dari keranjang. Beri tahu pelanggan dengan jelas bahwa barang belum tersedia dan tawarkan produk pengganti hanya setelah memastikan nama, ukuran, varian, harga, serta stok penggantinya benar. Jangan memakai kode produk lain untuk menjual barang yang kosong karena tindakan itu membuat stok, omzet per produk, margin, laporan pajak, dan riwayat retur menjadi salah.

Langkah kedua, bila barang fisik tersedia tetapi aplikasi menunjukkan nol atau angka yang lebih kecil, jangan memaksa transaksi menjadi stok minus. Buka menu Stok Opname, pindai barcode produk yang sama, hitung seluruh unit fisik di rak, gudang, area penerimaan, dan keranjang pelanggan, lalu masukkan hasil hitung disertai catatan yang jelas. Periksa juga apakah ada penerimaan barang melalui menu Kulakan yang belum disimpan, mutasi antar-outlet yang belum diterima, batch yang masih dikarantina, atau barang kedaluwarsa yang memang tidak boleh dihitung sebagai stok layak jual. Setelah koreksi disetujui sesuai kewenangan toko, lakukan Muat Ulang atau Sinkron, cari produk kembali, dan pastikan badge stok sudah berubah sebelum mengulang pembayaran.

Langkah ketiga, apabila produk dikelola berdasarkan batch, periksa menu Kedaluwarsa. Stok total dapat terlihat ada, tetapi sistem tetap menolak bila semua batch sudah kedaluwarsa, dikarantina, belum aktif, atau jumlah batch layak jual tidak mencukupi. Pisahkan barang kedaluwarsa dari rak, jangan menjualnya, kemudian catat batch baru atau koreksi batch sesuai dokumen penerimaan. Jangan mengubah tanggal kedaluwarsa hanya agar transaksi lolos.

Langkah keempat, periksa outlet aktif pada bagian atas aplikasi. Stok setiap outlet berdiri sendiri. Barang yang tersedia di outlet lain harus dipindahkan melalui Mutasi Antar Outlet dan diterima secara resmi, bukan langsung dianggap tersedia di toko ini. Pastikan pula barcode yang dipindai benar; kemasan yang mirip dapat terhubung ke produk, satuan, atau isi per kemasan yang berbeda.

Jika setelah opname, penerimaan, pemeriksaan batch, pemilihan outlet, Muat Ulang, dan Sinkron angka masih salah, hentikan penjualan item tersebut dan hubungi supervisor. Sampaikan nama produk, kode atau barcode, outlet, stok fisik, stok di layar, jumlah yang hendak dijual, waktu kejadian, nama kasir, dan kode referensi pada Informasi Teknis. Jangan mengirim kata sandi. Supervisor dapat membandingkan Kartu Mutasi Stok, riwayat Stok Opname, Kulakan, Mutasi Antar Outlet, transaksi penjualan, retur, serta Log Error. Hubungi administrator atau developer hanya bila pemeriksaan operasional tersebut belum menemukan penyebab. Dengan urutan ini, pelanggan memperoleh penjelasan yang benar dan data stok, kas, struk, laporan, serta proses retur tetap konsisten.
''';

Future<void> tampilkanPanduanStokKosong(BuildContext context,
    {required String detail}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.inventory_2_outlined,
          color: Colors.orange, size: 38),
      title: const Text('Stok tidak mencukupi'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Barang terdampak',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SelectableText(detail),
              const Divider(height: 28),
              const Text('Panduan penyelesaian',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const SelectableText(panduanStokKosong,
                  textAlign: TextAlign.left),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Saya Mengerti'),
        ),
      ],
    ),
  );
}
