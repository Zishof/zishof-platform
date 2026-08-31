# 60. Butir Terbuka Dituntaskan — Metode 2, Kelipatan Wajib, Saklar Reservasi, Galat, Foto Member, Label PR/PO

Tanggal: 31 Agustus 2026  
Status: terpasang & teruji server lokal (TesButir12Uat **17/17**; Flutter
575/575); belum di-commit  
Rujukan: dok. 48 §6 (keputusan pemilik), dok. 54 (titik pasang reservasi),
dok. 56 (daftar keputusan), laporan galat 30-08

## Butir 1 — keputusan dok. 48 §6

1. **Metode 2 — harga tetap per paket** (§6 no.1): kolom `harga_paket` pada
   `aturan_harga_produk`. Mesin memakai
   `COALESCE(harga_paket/min_qty_dasar, harga)` sebagai harga satuan efektif
   — total kelipatan paket selalu persis harga paket × jumlah paket
   (4.500.000/karung isi 50 → 90.000/kg). Kolom `harga` lama tetap diisi
   turunannya supaya laporan lama tidak melihat nol. Editor kasir mendapat
   input "ATAU harga per paket/kemasan".
2. **Kelipatan wajib** (§6 no.2): kolom `kelipatan_wajib` per aturan.
   `bayar` menolak qty nanggung SETELAH grosir diterapkan (urutan dok. 51),
   dinilai atas TOTAL qty produk se-keranjang, dengan pesan terbaca +
   saran pembulatan ("Bulatkan ke 50 atau 100"). Di bawah ambang = bebas.
   Editor kasir mendapat centang "Wajib kelipatan kemasan".
3. **Reservasi mengunci stok kasir** (§6 no.4): dibangun sebagai **saklar
   konfigurasi** `kantin_pos_reservasi_mengunci` (layar Konfigurasi > Kasir
   (POS); bawaan MATI = reservasi murni informasi, perilaku hari ini —
   TIDAK ada perubahan perilaku sampai pemilik menyalakannya). Saat AKTIF,
   cek stok `bayar` (`validasiStokCukupDenganLock`) mengurangi stok live
   dengan `sum(qty_sisa)` reservasi WO AKTIF per produk+toko — persis titik
   pasang dok. 54; deskripsi kekurangan menyebut "terkunci reservasi WO".
   Semantik blokir mengikuti gerbang oversell yang ada (fail-open kecuali
   produk ber-override). Inti logika dipisah ke overload ber-flag eksplisit
   supaya teruji tanpa lapisan cache konfigurasi (MemoryDB/RMI).
4. **Pemetaan akun jurnal disposisi QC** (§7) — **TIDAK diimplementasikan**,
   sengaja: membutuhkan kode akun (persediaan, beban scrap/rework, selisih
   produksi) dari akunting pemilik; tidak ada nilai bawaan yang jujur.
   Begitu daftar akunnya diserahkan, sumber jurnalnya sudah siap (dokumen
   WASTE/UNBUILD/WO POSTED, dok. 55) dan polanya dasbor Draft Jurnal
   (dok. 06/09).

## Butir 2 — galat laporan 30-08

1. **Klasifikator galat PosApi**: cabang "stok" kini menuntut frasa
   kekurangan sungguhan ("stok tidak/belum", "melebihi stok", "stok habis",
   "sisa ", "kekurangan stok") dan mengecualikan "satuan stok" — pesan
   validasi UOM ("Satuan Stok/Dasar wajib dipilih…") tidak lagi tersamar
   menjadi judul "Stok belum mencukupi"; kini jatuh ke penolakan-bisnis
   biasa dengan kalimat aslinya.
2. **Foto member mandiri**: entitas baru `FotoAnggotaKoperasi`
   (`public.foto_anggota_koperasi`, pola persis `FotoSiswa`, mapping di
   `hibernate.streaming.cfg.xml`, tabel dibuat hbm2ddl). `ProfileImageUtil`
   kini menjadikan `AnggotaKoperasi` tanpa tautan sivitas sebagai subjek
   foto sendiri — unggah dari POS diterima, unggah ulang mengganti (tidak
   menggandakan), URL foto terbaca lewat mesin yang sama. Member BER-tautan
   tetap memakai tabel foto entitas tautannya (perilaku lama).
3. **`katalog` 502 (halaman 180)** — bukan galat aplikasi: 502 datang dari
   proxy/edge dengan badan non-JSON; klien sudah punya retry
   (`_ambilHalamanKatalogDenganRetry`) dan sinkronisasi lanjut. Perbaikan
   hakiki ada di infrastruktur (timeout proxy) atau paginasi keyset —
   dicatat sebagai kandidat pekerjaan bila masih sering muncul di lapangan.

## Butir 3 — label satuan pembelian PR/PO

`pengadaan_barang_cari` kini mengirim `satuanPembelianNama` (jatuh ke satuan
dasar bila UOM pembelian kosong); layar PR dan PO menampilkan label kolom
"Jumlah (DUS)" dan "Harga Modal /DUS" / "Harga Beli /DUS" — nilai memang
bersemantik satuan pembelian sejak dok. 59, kini terlihat.

## Berkas

Server: `AturanHargaProduk`, `HargaGrosirApiHelper` (mesin `aturanCocok` +
`cekKelipatanWajib`), `KantinHelper` (kait bayar + overload validasi stok),
`Konfigurasi` + `KonfigurasiNewAction` (saklar), `PosApi` (klasifikator),
`ProfileImageUtil` + `FotoAnggotaKoperasi` (baru) +
`hibernate.streaming.cfg.xml`, `PengadaanPosApiHelper` (cariBarang).
EOL campuran dinormalkan (Konfigurasi, KonfigurasiNewAction,
ProfileImageUtil, streaming cfg — disengaja, tercatat).  
Flutter: `harga_grosir_editor.dart` (Metode 2 + kelipatan),
`pengadaan_pr_screen.dart` + `pengadaan_po_screen.dart` (label satuan).

## Bukti — TesButir12Uat 17/17 (API admin + refleksi + SQL, server lokal)

- Metode 2 via API: aturan tersimpan tanpa harga satuan manual; turunan
  90.000 terisi; daftar membawa field baru; mesin: qty 100 → 90.000, qty 30
  → tidak cocok.
- Kelipatan: 100 sah; 53 ditolak ber-saran; 30 (di bawah ambang) bebas.
- Saklar reservasi: MATI → minta 5 dari stok 10 lolos walau 8 terkunci;
  AKTIF → kekurangan terdeteksi dengan deskripsi "terkunci reservasi WO 8".
- Klasifikator: pesan UOM sampai utuh, kode bukan lagi STOK_TIDAK_CUKUP.
- Foto member mandiri: unggah diterima, tersimpan di rumah baru, unggah
  ulang mengganti.

Flutter suite penuh **575/575**; analyze bersih di berkas tersentuh;
`satuanPembelianNama` terverifikasi di respons server hidup.
