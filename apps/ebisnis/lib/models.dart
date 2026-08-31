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

  /// Pemasok utama & satuan (UOM). Sebelumnya hanya bisa terisi lewat impor
  /// Excel, sehingga katalog yang dibuat dari form Produk selalu kosong pada
  /// kedua kolom ini dan ekspor "Daftar Barang dan Jasa" ikut kosong. Kini
  /// keduanya dapat disunting langsung di form Produk.
  final String pemasokNama;
  final int? satuanId;
  final String satuanNama;
  final int? satuanPembelianId;
  final String satuanPembelianNama;

  /// Rute pemenuhan ulang stok (Fase C dok. 48 P3): '' = BELI (bawaan),
  /// 'PRODUKSI' = ambang stok memicu draf Work Order, bukan pengajuan beli.
  /// Hanya dibaca penjadwal server; klien sekadar menyunting konfigurasi.
  final String rute;

  /// QC hasil produksi (Fase E): true = tiap OUTPUT POSTED produk ini
  /// otomatis menerbitkan Quality Alert + karantina batch di server.
  final bool perluQc;

  /// Kebijakan harga beli (PDF stok & uom 30-08): false = OTOMATIS ikut
  /// faktur kulakan/BAST tervalidasi (per satuan dasar hasil konversi UOM
  /// pembelian); true = dikunci manual, faktur tidak menimpa.
  final bool hargaBeliManual;

  /// Pack/Combo (PDF 31-08): produk boleh dijual per PACK di POS dengan
  /// harga TETAP per pack (65.000/Dus, sengaja bukan isi x harga satuan).
  /// Server berwenang menimpa harga saat bayar; klien hanya pratinjau.
  final bool packAktif;
  final int? satuanPackId;
  final String satuanPackNama;
  final double? hargaPack;
  final double? faktorPackKeDasar;

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

  /// Preset kemasan produk. Barcode kemasan menambah [qtyDasar] unit stok,
  /// tanpa mengubah UOM akuntansi produk.
  final List<Map<String, dynamic>> kemasan;

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
    this.pemasokNama = '',
    this.satuanId,
    this.satuanNama = '',
    this.satuanPembelianId,
    this.satuanPembelianNama = '',
    this.rute = '',
    this.perluQc = false,
    this.hargaBeliManual = false,
    this.packAktif = false,
    this.satuanPackId,
    this.satuanPackNama = '',
    this.hargaPack,
    this.faktorPackKeDasar,
    required this.gambarUrl,
    this.hargaBeli = 0,
    this.keterangan = '',
    this.izinkanJualMinusStok = false,
    this.aktif = true,
    this.jenisItem = 'JUAL',
    this.bahanBaku = const [],
    this.ekstraPilihan = const [],
    this.kemasan = const [],
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
        pemasokNama: (j['pemasokNama'] ?? '') as String,
        satuanId: (j['satuanId'] as num?)?.toInt(),
        satuanNama: (j['satuanNama'] ?? '') as String,
        satuanPembelianId: (j['satuanPembelianId'] as num?)?.toInt(),
        satuanPembelianNama: (j['satuanPembelianNama'] ?? '') as String,
        rute: (j['rute'] ?? '') as String,
        perluQc: j['perluQc'] == true,
        hargaBeliManual: j['hargaBeliManual'] == true,
        packAktif: j['packAktif'] == true,
        satuanPackId: (j['satuanPackId'] as num?)?.toInt(),
        satuanPackNama: (j['satuanPackNama'] ?? '') as String,
        hargaPack: (j['hargaPack'] as num?)?.toDouble(),
        faktorPackKeDasar: (j['faktorPackKeDasar'] as num?)?.toDouble(),
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
        kemasan: ((j['kemasan'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
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
        'aktif': j['aktif'] == false ? 0 : 1,
        'jenis_item': (j['jenisItem'] as String?)?.isNotEmpty == true
            ? j['jenisItem']
            : 'JUAL',
        'ekstra_pilihan': jsonEncode(((j['ekstraPilihan'] as List?) ?? [])
            .map((e) => e as num)
            .toList()),
        'kemasan': jsonEncode(((j['kemasan'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()),
        'foto_urls': jsonEncode(
            ((j['fotoUrls'] as List?) ?? []).map((e) => e as String).toList()),
        'izinkan_jual_minus_stok': j['izinkanJualMinusStok'] == true ? 1 : 0,
      };

  /// Kebalikan [baseKeCacheRow] utk kolom dasarnya: baris cache lokal ->
  /// bentuk JSON `katalog`. Dipakai layar pencarian produk yang jatuh ke
  /// cache saat offline (koreksi transaksi, dialog cari produk Sales) supaya
  /// pemetaan kolom SQLite->JSON tidak digandakan di tiap layar.
  static Map<String, dynamic> cacheRowKeJson(Map<String, Object?> b) => {
        'id': b['id'],
        'kode': b['kode'] ?? '',
        'barcode': b['barcode'] ?? '',
        'nama': b['nama'] ?? '',
        'hargaJual': b['harga_jual'] ?? 0,
        'stok': b['stok'] ?? 0,
        'kategoriId': b['kategori_id'],
        'kategoriNama': b['kategori_nama'] ?? '',
        'gambarUrl': b['gambar_url'],
        'aktif': b['aktif'] != 0,
        'jenisItem':
            '${b['jenis_item'] ?? ''}'.isEmpty ? 'JUAL' : '${b['jenis_item']}',
        'ekstraPilihan': _bacaDaftarAngka(b['ekstra_pilihan']),
        'kemasan': _bacaDaftarPeta(b['kemasan']),
        'fotoUrls': _bacaDaftarTeks(b['foto_urls']),
        'izinkanJualMinusStok': b['izinkan_jual_minus_stok'] == 1,
      };

  static List<int> _bacaDaftarAngka(Object? mentah) {
    try {
      final nilai = jsonDecode('$mentah');
      return nilai is List
          ? nilai.whereType<num>().map((e) => e.toInt()).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _bacaDaftarPeta(Object? mentah) {
    try {
      final nilai = jsonDecode('$mentah');
      return nilai is List
          ? nilai
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<String> _bacaDaftarTeks(Object? mentah) {
    try {
      final nilai = jsonDecode('$mentah');
      return nilai is List ? nilai.map((e) => '$e').toList() : const [];
    } catch (_) {
      return const [];
    }
  }
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

  /// Kebijakan kontak per Tipe Member (null = server lama belum mengirim --
  /// pemakai jatuh ke default per nama, lihat kebijakan_tipe_member.dart).
  final bool? wajibHp;
  final bool? wajibEmail;

  Kategori(
      {required this.id, required this.nama, this.wajibHp, this.wajibEmail});
  factory Kategori.fromJson(Map<String, dynamic> j) => Kategori(
        id: j['id'] as int,
        nama: (j['nama'] ?? '') as String,
        wajibHp: j['wajibHp'] is bool ? j['wajibHp'] as bool : null,
        wajibEmail: j['wajibEmail'] is bool ? j['wajibEmail'] as bool : null,
      );
}

class CaraBayar {
  final int id;
  final String nama;
  final bool manual;
  final bool memotongDeposit;
  final bool wajibPin;

  /// Metode ini membentuk PIUTANG toko ke pelanggan (kolom
  /// `cara_pembayaran_koperasi.masuk_sebagai_hutang`). Bila true, kasir WAJIB
  /// memilih nama pelanggan -- server menolak piutang tanpa pemilik karena
  /// tagihannya tidak dapat ditelusuri tim keuangan.
  final bool masukSebagaiHutang;

  /// Metode ini menuntut nama pelanggan dipilih sebelum transaksi ditulis
  /// (`cara_pembayaran_koperasi.wajib_pilih_member`, nilai EFEKTIF dari server).
  ///
  /// Lebih luas daripada [masukSebagaiHutang]: metode potong saldo juga wajib
  /// mempunyai pemilik. Semua Kasbon sendiri dinormalisasi menjadi piutang.
  final bool wajibPilihMember;
  CaraBayar({
    required this.id,
    required this.nama,
    required this.manual,
    this.memotongDeposit = false,
    this.wajibPin = false,
    this.masukSebagaiHutang = false,
    bool? wajibPilihMember,
  }) : wajibPilihMember =
            wajibPilihMember ?? (masukSebagaiHutang || memotongDeposit);
  factory CaraBayar.fromJson(Map<String, dynamic> j) {
    final nama = (j['nama'] ?? '') as String;
    final namaLower = nama.toLowerCase();
    final identitas = '${j['kode'] ?? ''} $nama'
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ');
    final identitasRingkas = identitas.replaceAll(RegExp(r'\s+'), '');
    // Pengaman lintas versi: semua varian Kasbon adalah piutang customer dan
    // wajib mempunyai member/PIC, termasuk respons server lama yang masih
    // membawa kedua flag dalam keadaan false.
    final metodeKasbon = identitasRingkas.contains('kasbon');
    return CaraBayar(
      id: j['id'] as int,
      nama: nama,
      manual: j['manual'] == true,
      wajibPin: j['wajibPin'] == true || j['wajib_pin'] == true,
      masukSebagaiHutang: metodeKasbon ||
          j['masukSebagaiHutang'] == true ||
          j['masuk_sebagai_hutang'] == true,
      // Server lama tidak mengirim kunci ini sama sekali; null di sini membuat
      // konstruktor jatuh ke aturan bawaan (hutang / potong saldo), sehingga
      // klien baru + server lama tetap berperilaku seperti sebelumnya.
      wajibPilihMember: metodeKasbon
          ? true
          : (j['wajibPilihMember'] ?? j['wajib_pilih_member']) == null
              ? null
              : (j['wajibPilihMember'] == true ||
                  j['wajib_pilih_member'] == true),
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

bool pembayaranMemerlukanPin(Iterable<CaraBayar> metode) =>
    metode.any((cara) => cara.wajibPin);

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

  /// Harga satuan grosir dari server (peta `hargaGrosir` pada respons
  /// `diskon_evaluasi`); null = harga katalog berlaku. HANYA server yang
  /// mengisinya -- klien tidak menghitung ambang sendiri, supaya pratinjau
  /// dan struk (yang dihitung ulang server saat bayar) tidak pernah beda
  /// pendapat (Fase A dok. 48/49).
  double? hargaGrosir;

  /// Snapshot kemasan yang dipakai MENAMBAH baris ini (nama + isi per
  /// kemasan) -- arsip, bukan rujukan: preset kemasan yang diubah di master
  /// produk kemudian hari tidak boleh mengubah arti baris/struk lama.
  /// Stok dan qty TETAP dalam satuan dasar; ini murni label tampilan.
  String? kemasanNama;
  int? kemasanQtyDasar;

  /// Satuan JUAL per baris (Fase B dok. 48/49): kasir memilih satuan besar
  /// (mis. Karung 50) dan mengetik qty dalam satuan itu. `jumlah` TETAP
  /// satuan dasar; server menimpa/menghitung ulang jumlah dari qty_input x
  /// faktor miliknya sendiri (klien hanya pratinjau lewat UomKonversi).
  int? satuanJualId;
  String? satuanJualNama;
  double? qtyInput;
  double? faktorKeDasar;
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

  /// Harga pack per satuan DASAR (hargaPack/faktor) -- diisi saat kasir
  /// memilih menu pack; hanya berlaku selama snapshot satuan jual masih
  /// sejalan (pola swa-batal Fase B). Server tetap menimpa saat bayar.
  double? hargaPackPerDasar;

  /// Harga satuan yang benar-benar berlaku: grosir dari server menang,
  /// lalu harga pack (selama baris masih konsisten pack), lalu katalog.
  double get hargaSatuanEfektif =>
      hargaGrosir ??
      (satuanJualKonsisten && hargaPackPerDasar != null
          ? hargaPackPerDasar!
          : produk.hargaJual);

  /// Label kemasan untuk baris & struk: "2 x Karung 50kg" bila qty habis
  /// dibagi isi kemasan; bila kasir mengubah qty hingga tidak bulat lagi,
  /// jatuh ke bentuk informatif "Karung 50kg (isi N)" -- tidak berbohong
  /// mengaku kelipatan yang bukan.
  /// Snapshot satuan jual masih SEJALAN dengan qty dasar? Begitu kasir
  /// mengubah qty lewat stepper sehingga qtyInput x faktor != jumlah,
  /// snapshot gugur sendiri -- label dan payload satuan tidak dikirim,
  /// tanpa satu pun stepper perlu tahu konsep satuan jual.
  bool get satuanJualKonsisten {
    final q = qtyInput, f = faktorKeDasar;
    if (satuanJualId == null || q == null || f == null || q <= 0 || f <= 0) {
      return false;
    }
    return ((q * f) - jumlah).abs() < 1e-6;
  }

  /// Label satuan jual utk baris & struk: "2 Karung50 = 100 kg".
  String? get labelSatuanJual {
    if (!satuanJualKonsisten) return null;
    final q = qtyInput!;
    final qTeks = q == q.roundToDouble() ? '${q.round()}' : '$q';
    final dasar = produk.satuanNama.isEmpty ? 'unit' : produk.satuanNama;
    return '$qTeks ${satuanJualNama ?? ''} = $jumlah $dasar';
  }

  String? get labelKemasan {
    final nama = kemasanNama;
    final isi = kemasanQtyDasar ?? 0;
    if (nama == null || nama.isEmpty || isi <= 0) return null;
    if (jumlah % isi == 0 && jumlah >= isi) return '${jumlah ~/ isi} x $nama';
    return '$nama (isi $isi)';
  }

  double get subtotal => (hargaSatuanEfektif + _hargaEkstraPerUnit) * jumlah;
  double get subtotalSetelahDiskon => subtotal - diskon;
}

/// Menghapus salinan baris keranjang yang benar-benar identik.
///
/// Versi server lama pernah menjalankan DELETE rincian draft tanpa commit,
/// sehingga setiap kali draft dimuat lalu ditahan ulang seluruh rincian lama
/// dapat tersalin sekali lagi. UI kasir normal menggabungkan produk, promo, dan
/// ekstra yang identik pada satu baris; karena itu dua baris dengan seluruh
/// atribut berikut sama adalah salinan korup, bukan dua pilihan kasir terpisah.
/// Jumlah tidak dijumlahkan karena salinan lama sudah membawa qty yang sama.
List<ItemKeranjang> normalisasiDuplikatKeranjangTertahan(
    Iterable<ItemKeranjang> sumber) {
  final hasil = <ItemKeranjang>[];
  final terlihat = <String>{};
  for (final item in sumber) {
    final ekstra = item.ekstra
        .map((e) => '${e.id}|${e.kode}|${e.nama}|${e.harga}')
        .join(';;');
    final kunci = <Object?>[
      item.produk.id,
      item.produk.kode,
      item.produk.nama,
      item.produk.hargaJual,
      item.jumlah,
      item.diskon,
      item.cashback,
      item.aturanDiskonId,
      item.promoManual,
      item.promoManualAturanId,
      item.diskonBebas,
      item.diskonBebasTipe,
      item.diskonBebasNilai,
      ekstra,
    ].join('\u001f');
    if (terlihat.add(kunci)) hasil.add(item);
  }
  return hasil;
}

/// Waktu bisnis baru untuk draft POS yang dilanjutkan.
///
/// Draft lama hanya menjadi sumber identitas dan rincian keranjang. Waktu
/// transaksi tidak diwarisi karena pemuatan maupun penahanan ulang merupakan
/// aktivitas kasir baru yang harus tercatat pada saat tindakan itu dilakukan.
DateTime waktuTransaksiDraftDilanjutkan({DateTime? sekarang}) =>
    sekarang ?? DateTime.now();

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
  final bool pinSudahDiatur;
  final bool wajibBiometricWajah;
  final bool wajibBiometricFingerprint;
  final double maksimalTransaksiHarian;
  final double maksimalTransaksiMingguan;
  final double maksimalTransaksiBulanan;
  final bool aktif;
  final double minSaldo;
  final int? tipeAnggotaKoperasiId;
  final String tipeNama;
  final String? tanggalKadaluarsa;
  final String userid;
  final String fotoUrl;
  final String fotoNama;
  final int? fotoUkuran;

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
    this.pinSudahDiatur = false,
    this.wajibBiometricWajah = false,
    this.wajibBiometricFingerprint = false,
    this.maksimalTransaksiHarian = 0,
    this.maksimalTransaksiMingguan = 0,
    this.maksimalTransaksiBulanan = 0,
    this.aktif = true,
    required this.minSaldo,
    this.tipeAnggotaKoperasiId,
    this.tipeNama = '',
    this.tanggalKadaluarsa,
    this.userid = '',
    this.fotoUrl = '',
    this.fotoNama = '',
    this.fotoUkuran,
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
        pinSudahDiatur: j['pinSudahDiatur'] == true,
        wajibBiometricWajah: j['wajibBiometricWajah'] == true,
        wajibBiometricFingerprint: j['wajibBiometricFingerprint'] == true,
        maksimalTransaksiHarian:
            (j['maksimalTransaksiHarian'] as num?)?.toDouble() ?? 0,
        maksimalTransaksiMingguan:
            (j['maksimalTransaksiMingguan'] as num?)?.toDouble() ?? 0,
        maksimalTransaksiBulanan:
            (j['maksimalTransaksiBulanan'] as num?)?.toDouble() ?? 0,
        aktif: j['aktif'] == null ? true : j['aktif'] == true,
        minSaldo: (j['minSaldo'] as num?)?.toDouble() ?? 0,
        tipeAnggotaKoperasiId: j['tipeAnggotaKoperasiId'] as int?,
        tipeNama: (j['tipeNama'] ?? '') as String,
        tanggalKadaluarsa: j['tanggalKadaluarsa'] as String?,
        userid: (j['userid'] ?? '') as String,
        fotoUrl: (j['fotoUrl'] ?? '') as String,
        fotoNama: (j['fotoNama'] ?? '') as String,
        fotoUkuran: (j['fotoUkuran'] as num?)?.toInt(),
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
        pinSudahDiatur: (b['pin_sudah_diatur'] as int? ?? 0) == 1,
        wajibBiometricWajah: (b['wajib_biometric_wajah'] as int? ?? 0) == 1,
        wajibBiometricFingerprint:
            (b['wajib_biometric_fingerprint'] as int? ?? 0) == 1,
        maksimalTransaksiHarian:
            (b['maksimal_transaksi_harian'] as num?)?.toDouble() ?? 0,
        maksimalTransaksiMingguan:
            (b['maksimal_transaksi_mingguan'] as num?)?.toDouble() ?? 0,
        maksimalTransaksiBulanan:
            (b['maksimal_transaksi_bulanan'] as num?)?.toDouble() ?? 0,
        minSaldo: 0,
        fotoUrl: (b['foto_url'] ?? '') as String,
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
        'pin_sudah_diatur': (j['pinSudahDiatur'] == true) ? 1 : 0,
        'wajib_biometric_wajah': (j['wajibBiometricWajah'] == true) ? 1 : 0,
        'wajib_biometric_fingerprint':
            (j['wajibBiometricFingerprint'] == true) ? 1 : 0,
        'maksimal_transaksi_harian':
            (j['maksimalTransaksiHarian'] as num?)?.toDouble() ?? 0,
        'maksimal_transaksi_mingguan':
            (j['maksimalTransaksiMingguan'] as num?)?.toDouble() ?? 0,
        'maksimal_transaksi_bulanan':
            (j['maksimalTransaksiBulanan'] as num?)?.toDouble() ?? 0,
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
