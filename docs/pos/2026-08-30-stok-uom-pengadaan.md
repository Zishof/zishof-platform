# 59. PDF "stok & uom" — Rantai Pengadaan (PR→PO→BAST) Sadar-UOM

Tanggal: 30 Agustus 2026  
Status: terpasang & teruji di server lokal (TesStokUomUat **14/14**, skenario
PDF persis; Flutter 575/575); belum di-commit  
Rujukan: PDF klien "stok & uom" (30-08), dok. 51/52 (mesin konversi UOM),
dok. 58 (skema koperasi)

## Peta kebutuhan PDF vs sistem

1. **Master produk ber-UOM jual & beli** — SUDAH ADA (`satuan`,
   `satuan_pembelian`, Fase A/B).
2. **PR/PO diinput per satuan pembelian (DUS) dengan harga per DUS** —
   SUDAH menjadi kontrak jalur kulakan: `kulakanFakturSimpan` menerima qty
   & harga dalam satuan PEMBELIAN (bawaan `produk.satuanPembelian` bila
   `satuan_input_id` tak dikirim) dan mengonversinya lewat
   `faktorUomInputKeDasar` yang SAMA dengan kasir. Baris pengadaan
   menyimpan snapshot lengkap (satuan input, qty input, faktor).
3. **BAST divalidasi → stok otomatis terkonversi ke satuan dasar** —
   **CELAH DITUTUP**: `bastPutusan` SETUJUI kini langsung memanggil jalur
   sinkron Kulakan resmi yang sama dengan tombol manual. Gagal sinkron
   TIDAK membatalkan persetujuan — dilaporkan jujur
   (`sinkronOtomatis`/`peringatanSinkron`), tombol manual tetap jadi jalur
   ulang; sudah-pernah-sinkron tidak menggandakan stok. Pengguna tanpa hak
   sinkron: persetujuan tercatat + peringatan minta pemegang hak.
4. **Harga beli master otomatis terkonversi dari harga per DUS**
   (1.200.000/DUS isi 6 → 200.000/botol) — **CELAH DITUTUP**:
   `kulakanFakturSimpan` kini menyetel `Produk.hargaBeli` = harga dasar
   hasil konversi tiap faktur (gerbang `bolehUbahHarga` sudah menjaga di
   pintu fungsi).
5. **"Tergantung kebijakan … pilihan settingan pada produk manual atau
   sesuai PO"** — **DIBANGUN**: kolom baru `Produk.harga_beli_manual`
   (nullable; kosong/false = otomatis ikut faktur — bawaan sesuai PDF;
   true = dikunci manual, faktur tidak menimpa). Form Produk Flutter dapat
   saklar "Harga beli manual (tidak ikut faktur)"; `produk_simpan` +
   `katalog` membawa fieldnya.
6. **Stok on hand berubah otomatis saat BAST tervalidasi / stok opname** —
   BAST kini otomatis (no. 3); opname sudah ada sejak lama.

## Berkas

- `Produk.java` — kolom `harga_beli_manual` (aditif, hbm2ddl).
- `KantinHelper.java` — `kulakanFakturSimpan` menyetel harga beli master
  (hormati flag); `produk_simpan` menerima `harga_beli_manual`.
- `PosApi.java` — katalog mengirim `hargaBeliManual`.
- `PengadaanPosApiHelper.java` — `bastPutusan` SETUJUI → sinkron otomatis.
- Flutter `models.dart`, `produk_screen.dart` (saklar kebijakan),
  `test/mto_qc_kontrak_test.dart` (+1 uji).

## Bukti — TesStokUomUat 14/14 (ujung-ke-ujung lewat API, akun admin)

Skenario PDF persis (kecap botol, DUS isi 6):

- faktur 2 DUS @1.200.000 → baris pengadaan 12 botol @200.000; stok
  produk otomatis 12; **harga beli master 200.000**;
- flag manual + master 150.000 → faktur berikutnya TIDAK menimpa; stok
  tetap bertambah;
- **BAST SETUJUI → stok otomatis +12** (2 DUS×6), BAST tertanda faktur;
  SETUJUI ulang tidak menggandakan (respons jujur menyebut sudah sinkron);
- harga master tetap terkunci manual meski BAST membawa harga DUS.

Flutter suite penuh 575/575; analyze bersih di berkas tersentuh.

## Catatan

- Layar PR/PO Flutter/JSP belum menampilkan LABEL satuan pembelian di
  kolom qty/harga (nilai sudah benar-semantik satuan pembelian; label =
  polesan UX menyusul bila diminta).
- Contoh angka PDF "stok 540 → 552" = delta +12 yang sama dengan bukti di
  atas (kolom stok dihitung ulang dari ledger, bukan angka bebas).
