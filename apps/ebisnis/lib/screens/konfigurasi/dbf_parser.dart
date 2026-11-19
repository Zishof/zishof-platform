import 'dart:convert';
import 'dart:typed_data';

/// Parser DBF (dBase III/Visual FoxPro) murni Dart utk impor master & histori
/// legacy INVENTORY CONTROL (tab "Impor DBF" Konfigurasi, varian Inventory & Sales).
///
/// Format: header 32 byte (jumlah record LE di offset 4, panjang header di 8,
/// panjang record di 10) + deskriptor field 32 byte/field (nama 11 byte ASCII,
/// tipe di 11, lebar di 16, desimal di 17) diakhiri 0x0D + record fixed-width
/// (byte pertama flag hapus 0x2A). Nomor rekaman fisik 1-based disimpan pada
/// kunci internal `_BARIS_KE` agar diteruskan sebagai `baris_ke` ke server.
class DbfField {
  final String nama;
  final String tipe;
  final int lebar;
  final int desimal;
  const DbfField(this.nama, this.tipe, this.lebar, this.desimal);
}

class DbfTabel {
  final String namaFile;
  final List<DbfField> fields;
  final List<Map<String, dynamic>> rows;
  const DbfTabel(this.namaFile, this.fields, this.rows);
}

class DbfParser {
  DbfParser._();

  static DbfTabel parse(String namaFile, Uint8List b) {
    if (b.length < 32) {
      throw const FormatException('Berkas terlalu kecil untuk DBF.');
    }
    final bd = ByteData.sublistView(b);
    final jumlahRecord = bd.getUint32(4, Endian.little);
    final panjangHeader = bd.getUint16(8, Endian.little);
    final panjangRecord = bd.getUint16(10, Endian.little);

    final fields = <DbfField>[];
    var o = 32;
    while (o + 32 <= b.length && b[o] != 0x0D && o < panjangHeader) {
      var akhirNama = o;
      while (akhirNama < o + 11 && b[akhirNama] != 0) {
        akhirNama++;
      }
      final nama = ascii
          .decode(b.sublist(o, akhirNama), allowInvalid: true)
          .trim()
          .toUpperCase();
      final tipe = String.fromCharCode(b[o + 11]);
      final lebar = b[o + 16];
      final desimal = b[o + 17];
      fields.add(DbfField(nama, tipe, lebar, desimal));
      o += 32;
    }
    if (fields.isEmpty) {
      throw FormatException('$namaFile: tidak ada field DBF terbaca.');
    }

    final rows = <Map<String, dynamic>>[];
    var pos = panjangHeader;
    for (var i = 0; i < jumlahRecord; i++) {
      if (pos + panjangRecord > b.length) break;
      final flagHapus = b[pos];
      var fpos = pos + 1;
      if (flagHapus == 0x2A) {
        pos += panjangRecord;
        continue; // record terhapus (soft delete FoxPro / settled AP-AR) -- jangan diimpor sebagai aktif.
      }
      final row = <String, dynamic>{
        '_BARIS_KE': i + 1,
        '_NAMA_FILE': namaFile,
      };
      for (final f in fields) {
        final raw = b.sublist(fpos, fpos + f.lebar);
        fpos += f.lebar;
        switch (f.tipe) {
          case 'C':
            row[f.nama] = latin1.decode(raw, allowInvalid: true).trim();
            break;
          case 'N':
          case 'F':
            final s = ascii.decode(raw, allowInvalid: true).trim();
            row[f.nama] = s.isEmpty ? null : double.tryParse(s);
            break;
          case 'D':
            final s = ascii.decode(raw, allowInvalid: true).trim();
            row[f.nama] = s.length == 8 && int.tryParse(s) != null
                ? '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}'
                : null;
            break;
          case 'L':
            final c = raw.isEmpty ? ' ' : String.fromCharCode(raw[0]);
            row[f.nama] = c == 'T' || c == 'Y' || c == 't' || c == 'y';
            break;
          default:
            // M (memo), 0 (_NullFlags), G, B -- tidak didukung; nilai dilewati.
            break;
        }
      }
      rows.add(row);
      pos += panjangRecord;
    }
    return DbfTabel(namaFile, fields, rows);
  }
}

/// Pemetaan berkas DBF legacy yang DIKENAL -> jenis impor server (`si_import_legacy`).
/// Urutan [urutanImpor] WAJIB: bagan akun & master pihak/produk lebih dahulu,
/// diikuti opname & master harga, lalu riwayat beli/jual, dan terakhir tagihan
/// hutang/piutang (piutang_legacy menautkan faktur_penjualan yang sudah dibuat
/// oleh penjualan_legacy).
class PetaDbfLegacy {
  PetaDbfLegacy._();

  static const urutanImpor = [
    'akun_legacy',
    'supplier',
    'customer',
    'sales',
    'produk',
    'opname',
    'harga_beli',
    'harga_jual',
    'pembelian_legacy',
    'penjualan_legacy',
    'hutang_legacy',
    'piutang_legacy',
  ];

  static const labelJenis = {
    'akun_legacy': 'Bagan Akun Perkiraan (account.dbf)',
    'supplier': 'Master Supplier (SUPPLIER.DBF)',
    'customer': 'Master Customer (CUSTOMER.DBF)',
    'sales': 'Master Sales (SALES.DBF)',
    'produk': 'Master Barang + saldo (STOK.DBF)',
    'opname': 'Riwayat Stok Opname (dataopn.dbf)',
    'harga_beli': 'Harga Beli per Supplier (masterbl.DBF)',
    'harga_jual': 'Harga Jual per Customer (masterjl.DBF)',
    'pembelian_legacy': 'Riwayat Pembelian/Pengadaan (BELI.DBF)',
    'penjualan_legacy': 'Riwayat Penjualan (JUAL.DBF)',
    'hutang_legacy': 'Tagihan Hutang Aktif (Tran_Hut.DBF)',
    'piutang_legacy': 'Tagihan & Pembayaran Piutang Aktif (Tran_Piut / PIUTSEMEN)',
  };

  static String? jenisDariNamaFile(String namaFile) {
    final n = namaFile.toLowerCase().split(RegExp(r'[\\/]+')).last;
    switch (n) {
      case 'account.dbf':
        return 'akun_legacy';
      case 'supplier.dbf':
        return 'supplier';
      case 'customer.dbf':
        return 'customer';
      case 'sales.dbf':
        return 'sales';
      case 'stok.dbf':
        return 'produk';
      case 'dataopn.dbf':
        return 'opname';
      case 'masterbl.dbf':
        return 'harga_beli';
      case 'masterjl.dbf':
        return 'harga_jual';
      case 'beli.dbf':
        return 'pembelian_legacy';
      case 'jual.dbf':
        return 'penjualan_legacy';
      case 'tran_hut.dbf':
        return 'hutang_legacy';
      case 'tran_piut.dbf':
      case 'piutsemen.dbf':
        return 'piutang_legacy';
      default:
        return null;
    }
  }

  static String _s(Map<String, dynamic> r, String k) =>
      (r[k] ?? '').toString().trim();

  static double _n(Map<String, dynamic> r, String k) =>
      (r[k] as num?)?.toDouble() ?? 0;

  static int? _barisKe(Map<String, dynamic> r) =>
      (r['_BARIS_KE'] as num?)?.toInt();

  /// Normalisasi satu baris DBF ke kontrak `si_import_legacy.rows` per jenis.
  /// Khusus `pembayaran_piutang_legacy` dipakai untuk baris negatif pada
  /// `Tran_Piut.DBF` / `PIUTSEMEN.DBF`.
  static Map<String, dynamic>? normalisasi(
      String jenis, Map<String, dynamic> r) {
    final barisKe = _barisKe(r);
    switch (jenis) {
      case 'akun_legacy':
        if (_s(r, 'KODEPERK').isEmpty || _s(r, 'KETERANGAN').isEmpty) {
          return null;
        }
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode': _s(r, 'KODEPERK'),
          'nama': _s(r, 'KETERANGAN'),
        };
      case 'supplier':
        if (_s(r, 'KODESUPPL').isEmpty) return null;
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode': _s(r, 'KODESUPPL'),
          'nama': _s(r, 'NAMASUPPL'),
          'termin': _n(r, 'SYARAT_BYR'),
          'atas_nama': _s(r, 'ATASNAMA'),
          'alamat': _s(r, 'ALAMAT'),
          'telp': _s(r, 'NOTELPON'),
          'rekening': _s(r, 'REKRUPIAH'),
          'alamat_bank': _s(r, 'ALMBANK'),
          'wilayah': _s(r, 'WILAYAH'),
          'bank': _s(r, 'NAMABANK'),
        };
      case 'customer':
        if (_s(r, 'KODECUST').isEmpty) return null;
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode': _s(r, 'KODECUST'),
          'nama': _s(r, 'NAMACUST'),
          'termin': _n(r, 'SYARAT_BYR'),
          'atas_nama': _s(r, 'ATASNAMA'),
          'alamat': ('${_s(r, 'ALAMAT1')} ${_s(r, 'ALAMAT2')}').trim(),
          'wilayah': _s(r, 'ALAMAT'),
          'telp': _s(r, 'NOTELPON'),
          'rekening': _s(r, 'REKRUPIAH'),
          'alamat_bank': _s(r, 'ALMBANK'),
          'bank': _s(r, 'NAMABANK'),
          'diskon': _n(r, 'DISCOUNT'),
        };
      case 'sales':
        if (_s(r, 'KODESALES').isEmpty) return null;
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode': _s(r, 'KODESALES'),
          'nama': _s(r, 'NAMASALES'),
          'no_perkiraan': _s(r, 'NOPERK'),
        };
      case 'produk':
        if (_s(r, 'KODEBRG').isEmpty) return null;
        final hrgTunai = _n(r, 'HARGAJUAL2');
        final tglHarga = _s(r, 'TGLHARGA');
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode': _s(r, 'KODEBRG'),
          'nama': _s(r, 'NAMABRG'),
          'satuan': _s(r, 'SATUAN'),
          'harga_beli': _n(r, 'HARGABELI'),
          'harga_jual': _n(r, 'HARGAJUAL'),
          // HARGAJUAL2 <= 0 wajib dikirim null (bukan 0) agar tidak dianggap gratis / margin -100%.
          'harga_jual_tunai': hrgTunai > 0 ? hrgTunai : null,
          if (tglHarga.isNotEmpty) 'tanggal_harga': tglHarga,
          'stok_minimum': _n(r, 'STOKMINIM'),
          // Kesetaraan legacy layar 08: AWAL + MASUK - ABS(KELUAR) = stok berjalan.
          'stok_legacy':
              _n(r, 'AWAL') + _n(r, 'MASUK') - _n(r, 'KELUAR').abs(),
        };
      case 'opname':
        if (_s(r, 'KODEBRG').isEmpty || _s(r, 'TANGGAL').isEmpty) return null;
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode_produk': _s(r, 'KODEBRG'),
          'tanggal': _s(r, 'TANGGAL'),
          'stok_sistem': _n(r, 'STOKKOMP'),
          'stok_fisik': _n(r, 'STOKFISIK'),
          'harga_beli': _n(r, 'HARGABELI'),
        };
      case 'harga_beli':
        if (_s(r, 'KODESUPPL').isEmpty || _s(r, 'KODEBRG').isEmpty) return null;
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode_supplier': _s(r, 'KODESUPPL'),
          'kode_produk': _s(r, 'KODEBRG'),
          'tanggal': _s(r, 'TANGGAL'),
          'harga': _n(r, 'HARGABELI'),
        };
      case 'harga_jual':
        if (_s(r, 'KODEBRG').isEmpty) return null;
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'kode_customer': _s(r, 'KODECUST'),
          'kode_produk': _s(r, 'KODEBRG'),
          'tanggal': _s(r, 'TANGGAL'),
          'harga': _n(r, 'HARGAJUAL'),
        };
      case 'pembelian_legacy':
        if (_s(r, 'NOFAKTUR').isEmpty || _s(r, 'KODEBRG').isEmpty) {
          return null;
        }
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'nomor_faktur': _s(r, 'NOFAKTUR'),
          'kode_supplier': _s(r, 'KODESUPPL'),
          'kode_produk': _s(r, 'KODEBRG'),
          'nama_produk': _s(r, 'NAMABRG'),
          'tanggal': _s(r, 'TANGGAL'),
          'qty': _n(r, 'JUMLAH'),
          'harga_beli': _n(r, 'HARGABELI'),
          // Kirim kedua nama kunci (jalur tenant membaca harga_bruto/diskon_persen/diskon_nilai).
          'harga_bruto': _n(r, 'HARGAASLI'),
          'harga_asli': _n(r, 'HARGAASLI'),
          'diskon_persen': _n(r, 'DISCOUNT'),
          'diskon': _n(r, 'DISCOUNT'),
          'diskon_nilai': _n(r, 'DISCOUNT2'),
          'diskon2': _n(r, 'DISCOUNT2'),
          'nomor_batch': _s(r, 'NOBATCH'),
          'tanggal_expired': _s(r, 'TGLEXP'),
        };
      case 'penjualan_legacy':
        if (_s(r, 'NOFAKTUR').isEmpty || _s(r, 'KODEBRG').isEmpty) {
          return null;
        }
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'nomor_faktur': _s(r, 'NOFAKTUR'),
          'kode_customer': _s(r, 'KODECUST'),
          'kode_sales': _s(r, 'KODESALES'),
          'kode_produk': _s(r, 'KODEBRG'),
          'nama_produk': _s(r, 'NAMABRG'),
          'tanggal': _s(r, 'TANGGAL'),
          'qty': _n(r, 'JUMLAH'),
          'harga_beli': _n(r, 'HARGABELI'),
          'harga_jual': _n(r, 'HARGAJUAL'),
          'nomor_batch': _s(r, 'NOBATCH'),
          'tanggal_expired': _s(r, 'TGLEXP'),
        };
      case 'hutang_legacy':
        final nilaiHutang = _n(r, 'JUMLAH');
        if (_s(r, 'NOFAKTUR').isEmpty ||
            _s(r, 'KODESUPPL').isEmpty ||
            _s(r, 'TANGGAL').isEmpty ||
            nilaiHutang <= 0) {
          return null;
        }
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'nomor_faktur': _s(r, 'NOFAKTUR'),
          'kode_supplier': _s(r, 'KODESUPPL'),
          'tanggal': _s(r, 'TANGGAL'),
          'jatuh_tempo': _s(r, 'JTHTEMPO'),
          'tanggal_bayar': _s(r, 'TGLBAYAR'),
          'nilai': nilaiHutang,
        };
      case 'piutang_legacy':
        final nilaiPiutang = _n(r, 'JUMLAH');
        if (_s(r, 'NOFAKTUR').isEmpty ||
            _s(r, 'KODECUST').isEmpty ||
            _s(r, 'TANGGAL').isEmpty ||
            nilaiPiutang <= 0) {
          return null;
        }
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'sumber': _s(r, '_NAMA_FILE'),
          'nomor_faktur': _s(r, 'NOFAKTUR'),
          'kode_customer': _s(r, 'KODECUST'),
          'kode_sales': _s(r, 'KODESALES'),
          'nomor_retur': _s(r, 'NORETUR'),
          'tanggal': _s(r, 'TANGGAL'),
          'jatuh_tempo': _s(r, 'JTHTEMPO'),
          'tanggal_bayar': _s(r, 'TGLBAYAR'),
          'nilai': nilaiPiutang,
        };
      case 'pembayaran_piutang_legacy':
        final nilaiBayar = _n(r, 'JUMLAH');
        if (_s(r, 'NOFAKTUR').isEmpty ||
            _s(r, 'KODECUST').isEmpty ||
            _s(r, 'TANGGAL').isEmpty ||
            _s(r, 'TGLBAYAR').isEmpty ||
            nilaiBayar >= 0) {
          return null;
        }
        return {
          if (barisKe != null) 'baris_ke': '$barisKe',
          'sumber': _s(r, '_NAMA_FILE'),
          'nomor_faktur': _s(r, 'NOFAKTUR'),
          'kode_customer': _s(r, 'KODECUST'),
          'kode_sales': _s(r, 'KODESALES'),
          'tanggal': _s(r, 'TANGGAL'),
          'tanggal_bayar': _s(r, 'TGLBAYAR'),
          'keterangan': _s(r, 'KETBAYAR'),
          'nomor_bg': _s(r, 'NOMERBG'),
          'nama_bank': _s(r, 'NAMABANK'),
          'tanggal_bg': _s(r, 'TANGGALBG'),
          'nilai': nilaiBayar.abs(),
        };
    }
    return null;
  }
}
