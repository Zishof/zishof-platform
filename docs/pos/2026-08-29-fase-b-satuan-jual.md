# Fase B — Satuan Jual per Baris (Karung/Dus di Kasir)

Tanggal: 29 Agustus 2026  
Status: server + kasir **lulus** (TesSatuanJual 9/9 di DB UAT; Flutter
493/493, analyze bersih di berkas tersentuh); belum di-commit  
Rujukan: SVN `docs/pos/52-fase-b-satuan-jual.md` (keputusan lengkap),
dok. 48 §4 Fase 2, dok. 49 Fase B

## Ringkas

Kasir kini bisa menjual "2 Karung 50" dan seluruh sistem tetap berpikir
dalam satuan dasar:

- **Server berwenang.** `KantinHelper.terapkanSatuanJual` berjalan di `bayar`
  SEBELUM harga grosir dan diskon: memuat SatuanProduk, menegakkan kategori
  UOM di satu titik (`faktorUomInputKeDasar`), lalu **menimpa** `jumlah`
  kiriman klien dengan `qty_input × faktor` miliknya sendiri. Harness
  membuktikan: klien mengirim 999, tersimpan 100.
- **Urutan dikunci:** satuan jual → qty dasar benar → ambang grosir menilai
  qty itu → diskon memotong terakhir.
- **Snapshot audit** tiga kolom nullable (`satuan_jual`, `qty_input`,
  `faktor_ke_dasar`) di baris POS (`inventory.Pembelian`) dan baris SO
  lapangan (`SalesOrderLapanganItem`); `qty` tetap satuan dasar.

## Sisi kasir (repo ini)

- `models.dart`: `ItemKeranjang.satuanJualId/satuanJualNama/qtyInput/
  faktorKeDasar` + `satuanJualKonsisten` + `labelSatuanJual`
  ("2 Karung 50 = 100 kg"). **Swa-batal**: begitu stepper mengubah qty dasar
  hingga `qtyInput × faktor ≠ jumlah`, label dan payload satuan gugur
  sendiri — tidak ada stepper yang perlu tahu konsep satuan jual, dan tidak
  ada klaim yang berbohong (pola label kemasan Fase A).
- `keranjang_screen.dart`: tombol satuan di samping tombol qty manual (hanya
  produk ber-satuan dasar) → dialog: pilih satuan SEKATEGORI dari `uom_list`,
  ketik qty, pratinjau `UomKonversi` ("= 100 kg (pratinjau; server menghitung
  ulang)"), tombol Terapkan hanya aktif bila hasil dasar BULAT (karena
  `ItemKeranjang.jumlah` bertipe int). Terapkan → isi 4 field + `jumlah`,
  `_evaluasiDiskon()` jalan ulang. Payload `bayar` menyertakan
  `satuan_jual_id` + `qty_input` hanya bila snapshot sejalan; struk memakai
  `labelSatuanJual` (menang atas label kemasan — satu klaim per baris).
  Perlu daring untuk membuka pemilih (daftar UOM dari master) — transaksi
  offline tetap jalan tanpa satuan jual, sengaja.
- `test/satuan_jual_kontrak_test.dart` (baru, 6 uji): label sejalan;
  swa-batal saat qty diubah; tanpa snapshot tanpa klaim; qty/faktor tak sah;
  pratinjau `UomKonversi` cocok aturan server (BIGGER/SMALLER + tolak lintas
  kategori); label satuan menang atas label kemasan.

## Bukti

- Server `TesSatuanJual` 9/9 (DB UAT, refleksi ke fungsi persis yang dipanggil
  `bayar`): timpa jumlah, snapshot faktor, baris tanpa satuan tak disentuh,
  tolak lintas kategori / qty nol / satuan tak dikenal.
- `javac 1.7` EXIT=0; mirror SVN `src`/`java` md5 identik.
- Flutter: suite penuh **493 lulus / 0 gagal**; analyze tanpa temuan di
  ketiga berkas tersentuh.

## Perhatian pohon bersama

`keranjang_screen.dart` dan `models.dart` juga memuat suntingan sesi lain
yang belum di-commit — saat commit, pisahkan hunk (teknik blob
`git hash-object` + `git update-index`, commit TANPA pathspec).
