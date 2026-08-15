import 'dart:convert';

/// Model data POS pilot -- bentuknya mengikuti persis kontrak JSON Api_eBisnis
/// (identik PosApi.java, lihat prosesKatalog/prosesKonfigurasi di server).
class Produk {
  final int id;
  final String kode;
  final String barcode;
  final String nama;
  final double hargaJual;
  final int stok;
  final int? kategoriId;
  final String kategoriNama;
  final int? kebijakanReturId;
  final String kebijakanReturNama;
  final String? gambarUrl;
  final double hargaBeli;
  final String keterangan;
  final bool izinkanJualMinusStok;
  final bool aktif;

  /// Jenis Item (`"JUAL"`/`"BAHAN"`) -- gap-closure Bahan Baku BUKAN untuk
  /// dijual langsung di Kasir, hanya jadi komponen resep produk lain (lihat
  /// [bahanBaku]). Default `"JUAL"` -- semua produk lama tanpa field ini
  /// (dari cache lokal atau respons server sebelum fitur ini) diperlakukan
  /// sbg produk jual biasa.
  final String jenisItem;

  /// Resep/Bahan Baku (BOM) -- daftar komponen `{produkId, nama, qty, harga}`
  /// dari field `bahanBaku` respons `katalog` (JSON string tersimpan apa
  /// adanya di server, dibaca ulang array persis spt yg terakhir disimpan
  /// lewat `produk_simpan`). Server HANYA menjumlahkan qty*harga tiap baris
  /// utk hargaBeli (produkId/nama tak dipakai server, sekadar identitas
  /// tampilan di form -- lihat JavaDoc `_FormProduk._BahanBakuEditor`).
  final List<Map<String, dynamic>> bahanBaku;

  /// Produk Ekstra (add-on/modifier) -- daftar id bare produk lain
  /// (`jenisItem == 'EKSTRA'`) yang boleh dipilih pelanggan saat produk ini
  /// ditambahkan ke keranjang (mis. "Kopi Susu Enak" -> ["Ekstra Topping
  /// Mesis", "Ekstra Cruble Oreo"]). Dari field `ekstraPilihan` respons
  /// `katalog` (server SUDAH mem-parse jadi array asli, bukan string JSON
  /// mentah). Resolusi id->nama/harga dilakukan lokal lewat
  /// `CoreDb.produkCacheResolveByIds` (lihat picker "Pilih Ekstra" Kasir),
  /// BUKAN dikirim ulang APA ADANYA -- beda dari [bahanBaku] yang memang
  /// sudah berisi nama/harga siap tampil dari server.
  final List<int> ekstraPilihan;

  /// URL foto produk (maks 10, urut lama->baru), dari field `fotoUrls`
  /// respons `katalog` -- gap-closure "Foto Produk". Kosong = belum ada foto
  /// diunggah (kartu Kasir tetap pakai avatar inisial placeholder). Lebih
  /// dari 1 -> kartu Kasir berganti gambar otomatis tiap 3 detik (lihat
  /// `_KartuProduk` di kasir_screen.dart), tepat 1 -> statis, TIDAK berganti.
  final List<String> fotoUrls;

  Produk({
    required this.id,
    required this.kode,
    required this.barcode,
    required this.nama,
    required this.hargaJual,
    required this.stok,
    required this.kategoriId,
    required this.kategoriNama,
    this.kebijakanReturId,
    this.kebijakanReturNama = 'Tanpa Kebijakan Retur',
    required this.gambarUrl,
    this.hargaBeli = 0,
    this.keterangan = '',
    this.izinkanJualMinusStok = false,
    this.aktif = true,
    this.jenisItem = 'JUAL',
    this.bahanBaku = const [],
    this.ekstraPilihan = const [],
    this.fotoUrls = const [],
  });

  factory Produk.fromJson(Map<String, dynamic> j) => Produk(
        id: j['id'] as int,
        kode: (j['kode'] ?? '') as String,
        barcode: (j['barcode'] ?? '') as String,
        nama: (j['nama'] ?? '') as String,
        hargaJual: (j['hargaJual'] as num?)?.toDouble() ?? 0,
        stok: (j['stok'] as num?)?.toInt() ?? 0,
        kategoriId: j['kategoriId'] as int?,
        kategoriNama: (j['kategoriNama'] ?? '') as String,
        kebijakanReturId: (j['kebijakanReturId'] as num?)?.toInt(),
        kebijakanReturNama:
            (j['kebijakanReturNama'] ?? 'Tanpa Kebijakan Retur') as String,
        gambarUrl: j['gambarUrl'] as String?,
        hargaBeli: (j['hargaBeli'] as num?)?.toDouble() ?? 0,
        keterangan: (j['keterangan'] ?? '') as String,
        izinkanJualMinusStok: j['izinkanJualMinusStok'] == true,
        // katalog tidak mengirim "aktif" eksplisit (hanya baris aktif yg dikembalikan kecuali admin
        // mode semuaToko) -- default true, dikoreksi lewat form Ubah bila memang dinonaktifkan.
        aktif: j['aktif'] == null ? true : j['aktif'] == true,
        jenisItem: (j['jenisItem'] as String?)?.isNotEmpty == true
            ? j['jenisItem'] as String
            : 'JUAL',
        bahanBaku:
            ((j['bahanBaku'] as List?) ?? []).cast<Map<String, dynamic>>(),
        ekstraPilihan: ((j['ekstraPilihan'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        fotoUrls:
            ((j['fotoUrls'] as List?) ?? []).map((e) => e as String).toList(),
      );

  /// Baris utk `CoreDb.replaceProdukCache` -- dipakai bersama oleh KasirScreen
  /// dan ProdukScreen (keduanya menyegarkan cache lokal yg sama dari respons
  /// `katalog` yang identik) supaya pemetaan JSON->kolom SQLite tidak dobel.
  static Map<String, Object?> baseKeCacheRow(Map<String, dynamic> j) => {
        'id': j['id'],
        'kode': j['kode'] ?? '',
        'barcode': j['barcode'] ?? '',
        'nama': j['nama'] ?? '',
        'harga_jual': j['hargaJual'] ?? 0,
        'stok': j['stok'] ?? 0,
        'kategori_id': j['kategoriId'],
        'kategori_nama': j['kategoriNama'] ?? '',
        'gambar_url': j['gambarUrl'],
        'aktif': 1,
        'jenis_item': (j['jenisItem'] as String?)?.isNotEmpty == true
            ? j['jenisItem']
            : 'JUAL',
        'ekstra_pilihan': jsonEncode(((j['ekstraPilihan'] as List?) ?? [])
            .map((e) => e as num)
            .toList()),
        'foto_urls': jsonEncode(
            ((j['fotoUrls'] as List?) ?? []).map((e) => e as String).toList()),
      };
}

class KebijakanRetur {
  final int id;
  final String nama;
  final String keterangan;
  final bool aktif;
  final bool bawaan;
  const KebijakanRetur(
      {required this.id,
      required this.nama,
      required this.keterangan,
      required this.aktif,
      required this.bawaan});
  factory KebijakanRetur.fromJson(Map<String, dynamic> j) => KebijakanRetur(
      id: (j['id'] as num).toInt(),
      nama: '${j['nama'] ?? ''}',
      keterangan: '${j['keterangan'] ?? ''}',
      aktif: j['aktif'] != false,
      bawaan: j['bawaan'] == true);
}

class Kategori {
  final int id;
  final String nama;
  Kategori({required this.id, required this.nama});
  factory Kategori.fromJson(Map<String, dynamic> j) =>
      Kategori(id: j['id'] as int, nama: (j['nama'] ?? '') as String);
}

class CaraBayar {
  final int id;
  final String nama;
  final bool manual;
  final bool memotongDeposit;
  CaraBayar({
    required this.id,
    required this.nama,
    required this.manual,
    this.memotongDeposit = false,
  });
  factory CaraBayar.fromJson(Map<String, dynamic> j) {
    final nama = (j['nama'] ?? '') as String;
    final namaLower = nama.toLowerCase();
    return CaraBayar(
      id: j['id'] as int,
      nama: nama,
      manual: j['manual'] == true,
      memotongDeposit: j['memotongDeposit'] == true ||
          j['memotong_deposit'] == true ||
          j['potongSaldo'] == true ||
          j['potong_saldo'] == true ||
          j['memotongSaldo'] == true ||
          j['memotong_saldo'] == true ||
          namaLower.contains('deposit') ||
          namaLower.contains('saldo'),
    );
  }
}

/// Satu pilihan Produk Ekstra (add-on/modifier) yang dilekatkan ke satu baris
/// [ItemKeranjang] -- bentuknya mengikuti persis kontrak `ekstra` dlm
/// `transaksi` (aksi `bayar`/`draft_bayar`, lihat JavaDoc
/// `PanelKeranjang._buatPayload`). [jumlah] SELALU `1` di payload (server
/// mengalikan otomatis dgn qty produk induk, lihat JavaDoc
/// [ItemKeranjang.subtotal]) -- field ini tetap disimpan (bukan konstanta
/// dihardcode saat kirim) supaya bentuk model persis mengikuti kontrak JSON.
class ItemEkstra {
  final int id;
  final String kode;
  final String nama;
  final double harga;
  final int jumlah;
  const ItemEkstra(
      {required this.id,
      required this.kode,
      required this.nama,
      required this.harga,
      this.jumlah = 1});
}

/// Satu baris di keranjang -- disalin dari [Produk] + jumlah yang dipilih kasir.
/// [diskon]/[cashback]/[aturanDiskonId] diisi hasil `diskon_evaluasi` (lihat
/// KeranjangScreen._evaluasiDiskon) -- default 0/null sebelum evaluasi pertama.
/// [ekstra] diisi lewat picker "Pilih Ekstra" (KasirScreen._tambahKeKeranjang)
/// saat [produk] punya [Produk.ekstraPilihan] -- kosong (default) utk mayoritas
/// baris biasa tanpa add-on.
///
/// [promoManual]/[promoManualAturanId] (gap-closure "Aktivasi Manual", Fase 2
/// Stretch) -- diisi KeranjangScreen._terapkanPromoManual saat kasir sengaja
/// memilih satu AturanDiskon lewat picker "Promo Manual" (BUKAN hasil
/// auto-apply biasa). [promoManual]=true menggerbangi _evaluasiDiskon
/// (debounced auto-recalc tiap perubahan keranjang) supaya baris ini TIDAK
/// ditimpa balik ke mode auto-apply -- lihat JavaDoc _evaluasiDiskon.
class ItemKeranjang {
  final Produk produk;
  int jumlah;
  double diskon;
  double cashback;
  int? aturanDiskonId;
  final List<ItemEkstra> ekstra;
  bool promoManual;
  int? promoManualAturanId;
  bool diskonBebas;
  String diskonBebasTipe;
  double diskonBebasNilai;
  ItemKeranjang(
      {required this.produk,
      this.jumlah = 1,
      this.diskon = 0,
      this.cashback = 0,
      this.aturanDiskonId,
      this.ekstra = const [],
      this.promoManual = false,
      this.promoManualAturanId,
      this.diskonBebas = false,
      this.diskonBebasTipe = 'NOMINAL',
      this.diskonBebasNilai = 0});

  /// Harga ekstra dijumlahkan PER UNIT produk induk (padanan cara server
  /// mengalikan `ekstra` dgn qty induk saat checkout, lihat JavaDoc
  /// [ItemEkstra]) -- jadi total di layar (subtotal/total/kembalian) SELALU
  /// cocok dgn yang akan dihitung ulang server, bukan cuma harga produk dasar.
  double get _hargaEkstraPerUnit => ekstra.fold(0.0, (s, e) => s + e.harga);
  double get subtotal => (produk.hargaJual + _hargaEkstraPerUnit) * jumlah;
  double get subtotalSetelahDiskon => subtotal - diskon;
}

/// Menempatkan baris yang baru ditambahkan/dipindai di urutan pertama.
///
/// Fungsi ini memindahkan objek yang sama (bukan membuat salinan), sehingga
/// qty, diskon, cashback, ekstra, dan referensi yang dipakai checkout tetap
/// utuh. Produk yang dipindai ulang juga kembali terlihat paling atas.
void tempatkanItemKeranjangTerbaruDiDepan(
    List<ItemKeranjang> keranjang, ItemKeranjang item) {
  keranjang.remove(item);
  keranjang.insert(0, item);
}

/// Anggota/member koperasi -- superset bentuk JSON dari 3 aksi berbeda:
/// `cari_member` (subset ringkas: id/nama/kodeIdentitas/wajibPin/minSaldo,
/// dipakai picker Kasir), `anggota_list`/`anggota_sync_list` (lengkap, dipakai
/// layar Anggota manajemen). Field yg tak dikirim salah satu aksi cukup
/// default kosong/false/0 -- TIDAK error, krn semua factory pakai `??`.
class Anggota {
  final int id;
  final String nama;
  final String kode;
  final String kodeIdentitas;
  final String hp;
  final String telp;
  final String email;
  final String keterangan;
  final int? jenisAnggotaKoperasiId;
  final String jenisNama;
  final bool wajibPin;
  final bool aktif;
  final double minSaldo;
  final int? tipeAnggotaKoperasiId;
  final String tipeNama;
  final String? tanggalKadaluarsa;
  final String userid;

  Anggota({
    required this.id,
    required this.nama,
    this.kode = '',
    required this.kodeIdentitas,
    this.hp = '',
    this.telp = '',
    this.email = '',
    this.keterangan = '',
    this.jenisAnggotaKoperasiId,
    this.jenisNama = '',
    required this.wajibPin,
    this.aktif = true,
    required this.minSaldo,
    this.tipeAnggotaKoperasiId,
    this.tipeNama = '',
    this.tanggalKadaluarsa,
    this.userid = '',
  });

  factory Anggota.fromJson(Map<String, dynamic> j) => Anggota(
        id: j['id'] as int,
        nama: (j['nama'] ?? '') as String,
        kode: (j['kode'] ?? '') as String,
        kodeIdentitas: (j['kodeIdentitas'] ?? '') as String,
        hp: (j['hp'] ?? '') as String,
        telp: (j['telp'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        keterangan: (j['keterangan'] ?? '') as String,
        jenisAnggotaKoperasiId: j['jenisAnggotaKoperasiId'] as int?,
        jenisNama: (j['jenisNama'] ?? '') as String,
        wajibPin: j['wajibPin'] == true,
        aktif: j['aktif'] == null ? true : j['aktif'] == true,
        minSaldo: (j['minSaldo'] as num?)?.toDouble() ?? 0,
        tipeAnggotaKoperasiId: j['tipeAnggotaKoperasiId'] as int?,
        tipeNama: (j['tipeNama'] ?? '') as String,
        tanggalKadaluarsa: j['tanggalKadaluarsa'] as String?,
        userid: (j['userid'] ?? '') as String,
      );

  /// Dari baris cache lokal (anggota_cache, kolom snake_case SQLite) -- dipakai
  /// picker member saat offline, lihat CoreDb.cariAnggotaCache.
  factory Anggota.fromCache(Map<String, Object?> b) => Anggota(
        id: b['id'] as int,
        nama: (b['nama'] ?? '') as String,
        kode: (b['kode'] ?? '') as String,
        kodeIdentitas: (b['kode_identitas'] ?? '') as String,
        hp: (b['hp'] ?? '') as String,
        telp: (b['telp'] ?? '') as String,
        email: (b['email'] ?? '') as String,
        jenisNama: (b['jenis_nama'] ?? '') as String,
        wajibPin: (b['wajib_pin'] as int? ?? 0) == 1,
        minSaldo: 0,
      );

  /// Baris utk `CoreDb.upsertAnggotaCache` dari respons `anggota_sync_list`.
  static Map<String, Object?> keCacheRow(Map<String, dynamic> j) => {
        'id': j['id'],
        'kode': j['kode'] ?? '',
        'nama': j['nama'] ?? '',
        'kode_identitas': j['kodeIdentitas'] ?? '',
        'hp': j['hp'] ?? '',
        'telp': j['telp'] ?? '',
        'email': j['email'] ?? '',
        'jenis_nama': j['jenisNama'] ?? '',
        'wajib_pin': (j['wajibPin'] == true) ? 1 : 0,
        'foto_url': j['fotoUrl'],
      };
}

/// Satu item di dalam [Pesanan] -- bentuk sama dgn `transaksi`/keranjang saat
/// checkout, dikembalikan lagi APA ADANYA dari draft oleh aksi `pesanan_list`.
///
/// [draftItemId]/[indukId] (gap-closure "Produk Ekstra") -- [draftItemId]
/// adalah id baris draft ITU SENDIRI, [indukId] null utk baris dasar, atau
/// berisi [draftItemId] baris induknya utk baris ekstra. Dipakai
/// PesananScreen._muatKeKeranjang mengelompokkan lagi baris ekstra yg
/// datang FLAT dari server jadi [ItemEkstra] bersarang di [ItemKeranjang]
/// induknya saat "Muat ke Keranjang" (resume Keranjang Tertahan) -- tanpa
/// ini, tiap ekstra akan muncul sbg baris keranjang mandiri sendiri-sendiri.
class ItemPesanan {
  final int? produkId;
  final String kode;
  final String nama;
  final double harga;
  final double jumlah;
  final double diskon;
  final double cashback;
  final int? aturanDiskonId;
  final int? draftItemId;
  final int? indukId;

  ItemPesanan({
    required this.produkId,
    required this.kode,
    required this.nama,
    required this.harga,
    required this.jumlah,
    required this.diskon,
    required this.cashback,
    required this.aturanDiskonId,
    this.draftItemId,
    this.indukId,
  });

  factory ItemPesanan.fromJson(Map<String, dynamic> j) => ItemPesanan(
        produkId: _intNullable(j['id'] ??
            j['produkId'] ??
            j['idProduk'] ??
            j['produk_id'] ??
            j['barangId'] ??
            j['idBarang'] ??
            j['barang_id']),
        kode: (j['kode'] ?? '') as String,
        nama: (j['nama'] ?? '') as String,
        harga: (j['harga'] as num?)?.toDouble() ?? 0,
        jumlah: (j['jumlah'] as num?)?.toDouble() ?? 0,
        diskon: (j['diskon'] as num?)?.toDouble() ?? 0,
        cashback: (j['cashback'] as num?)?.toDouble() ?? 0,
        aturanDiskonId: _intNullable(j['aturanDiskon'] ??
            j['aturanDiskonId'] ??
            j['aturan_diskon'] ??
            j['aturan_diskon_id']),
        draftItemId: _intNullable(j['draftItemId'] ?? j['draft_item_id']),
        indukId: _intNullable(j['indukId'] ?? j['induk_id']),
      );
}

int? _intNullable(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// Pesanan online (dibuat pembeli sendiri) ATAU Keranjang Tertahan (ditahan
/// kasir lewat "Tahan") -- keduanya baris `DraftPembelianAnggotaKoperasi` yang
/// SAMA, dibedakan lewat [dariPembeliOnline] (lihat JavaDoc `prosesPesananList`
/// di PosApi.java). Bentuk JSON mengikuti aksi `pesanan_list`.
class Pesanan {
  final int id;
  final String kode;
  final String pemesan;
  final int? anggotaId;
  final double totalBiaya;
  final bool lunas;
  final int? lunasId;
  final double totalDiskon;
  final double totalCashback;
  final String tokoNama;
  final String keterangan;
  final String tanggalPembayaran;
  final int? caraBayarId;
  final bool dariPembeliOnline;
  final String kasirLoginNama;
  final String? namaMesin;
  final List<ItemPesanan> items;

  Pesanan({
    required this.id,
    required this.kode,
    required this.pemesan,
    required this.anggotaId,
    required this.totalBiaya,
    required this.lunas,
    required this.lunasId,
    required this.totalDiskon,
    required this.totalCashback,
    required this.tokoNama,
    required this.keterangan,
    required this.tanggalPembayaran,
    required this.caraBayarId,
    required this.dariPembeliOnline,
    required this.kasirLoginNama,
    required this.namaMesin,
    required this.items,
  });

  factory Pesanan.fromJson(Map<String, dynamic> j) => Pesanan(
        id: j['id'] as int,
        kode: (j['kode'] ?? '') as String,
        pemesan: (j['pemesan'] ?? '') as String,
        anggotaId: j['anggotaId'] as int?,
        totalBiaya: (j['totalBiaya'] as num?)?.toDouble() ?? 0,
        lunas: j['lunas'] == true,
        lunasId: j['lunasId'] as int?,
        totalDiskon: (j['totalDiskon'] as num?)?.toDouble() ?? 0,
        totalCashback: (j['totalCashback'] as num?)?.toDouble() ?? 0,
        tokoNama: (j['tokoNama'] ?? '') as String,
        keterangan: (j['keterangan'] ?? '') as String,
        tanggalPembayaran: (j['tanggalPembayaran'] ?? '') as String,
        caraBayarId: j['caraBayarId'] as int?,
        dariPembeliOnline: j['dariPembeliOnline'] == true,
        kasirLoginNama: (j['kasirLoginNama'] ?? '') as String,
        namaMesin: j['namaMesin'] as String?,
        items: ((j['items'] as List?) ?? [])
            .map((e) => ItemPesanan.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
