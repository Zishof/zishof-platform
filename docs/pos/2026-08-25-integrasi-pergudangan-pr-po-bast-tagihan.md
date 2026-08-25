# Integrasi Pergudangan dengan PR, PO, BAST, Tagihan, dan Pembayaran

Tanggal: 25 Agustus 2026  
Status: **analisis desain; belum ada perubahan kode atau schema database**  
Dokumen terkait:

- [Analisis implementasi modul Pergudangan](2026-08-25-analisis-modul-pergudangan.md)
- [Fase implementasi modul Pergudangan](2026-08-25-fase-implementasi-modul-pergudangan.md)
- [Gap struktur tabel existing dan Pergudangan](2026-08-25-gap-struktur-tabel-pergudangan.md)

## 1. Kesimpulan

Modul Pergudangan mempunyai hubungan langsung dengan rangkaian proses pengadaan
`PR -> PO -> Penerimaan -> BAST -> Terima Tagihan -> Bayar Tagihan`.
Pergudangan menjadi sumber kebenaran atas barang yang benar-benar datang, lolos
pemeriksaan, ditempatkan, diretur, atau dikarantina. Namun Pergudangan bukan pemilik
data utang dan pembayaran.

Pembagian tanggung jawab yang disarankan:

| Domain | Data yang dikuasai |
|---|---|
| Pengadaan | PR, PO, pemasok, kontrak, harga, jadwal pengiriman, dan termin |
| Pergudangan | Penerimaan fisik, QC, putaway, batch/serial, mutasi, saldo, dan retur barang |
| BAST | Pengakuan formal hasil penerimaan barang atau penyelesaian jasa |
| Account Payable | Invoice/tagihan, verifikasi, pajak, potongan, dan utang pemasok |
| Kas/Bank | Instruksi pembayaran, realisasi, bukti transfer, dan rekonsiliasi |
| Akuntansi | Jurnal persediaan, utang, uang muka, beban, pajak, dan pembayaran |

## 2. Alur ujung ke ujung

```text
Permintaan kebutuhan
        |
        v
PR -> persetujuan -> PO/Kontrak -> pengiriman pemasok
                                      |
                                      v
                            Penerimaan Pergudangan
                            + pemeriksaan kuantitas
                            + QC/kondisi
                            + batch/serial/expired
                                      |
                         +------------+-------------+
                         |                          |
                         v                          v
                   Ditolak/retur             Lolos/karantina
                                                    |
                                                    v
                                             Putaway + stok
                                                    |
                                                    v
                                                   BAST
                                                    |
                                                    v
                                             Terima Tagihan
                                                    |
                                                    v
                                  Matching PO/Penerimaan/BAST/Invoice
                                                    |
                                                    v
                                           Persetujuan pembayaran
                                                    |
                                                    v
                                             Bayar Tagihan
```

## 3. Hubungan setiap dokumen dengan stok

| Dokumen/proses | Mengubah stok? | Penjelasan |
|---|---:|---|
| PR | Tidak | Hanya menyatakan kebutuhan barang/jasa. |
| PO | Tidak | Menjadi komitmen pembelian dan dasar expected receipt. |
| Pengiriman pemasok | Tidak | Barang masih dalam perjalanan dan belum diterima secara fisik. |
| Penerimaan awal | Kondisional | Dapat masuk stok karantina, belum tentu stok tersedia. |
| QC diterima dan posting receipt | Ya | Membentuk mutasi masuk pada ledger stok secara idempoten. |
| Putaway | Tidak mengubah total | Memindahkan stok antar lokasi/bin dalam gudang. |
| BAST | Tidak langsung | Mengakui hasil penerimaan; tidak boleh membuat mutasi kedua. |
| Terima tagihan | Tidak | Membentuk proses verifikasi utang, bukan pergerakan barang. |
| Bayar tagihan | Tidak | Mengurangi utang/kas-bank, bukan persediaan. |
| Retur pembelian | Ya | Membentuk mutasi keluar dan koreksi nilai/utang sesuai kebijakan. |

Prinsip penting: stok tidak boleh bertambah ketika PO atau invoice dibuat. Stok
bertambah hanya dari penerimaan yang diposting sesuai kebijakan QC. BAST dan tagihan
harus mereferensikan penerimaan tersebut, bukan membuat penerimaan baru.

## 4. PO bukan termin

PO bukan termin biasanya dibayar penuh setelah barang diterima dan dokumen lolos
verifikasi:

```text
PR -> PO -> Penerimaan parsial/final -> QC -> Putaway -> BAST
   -> Invoice pemasok -> matching -> persetujuan -> pembayaran penuh
```

Satu PO tetap harus mendukung:

- beberapa jadwal pengiriman;
- beberapa penerimaan parsial;
- penerimaan lebih/kurang dengan toleransi dan persetujuan;
- barang rusak, ditolak, atau dikarantina;
- beberapa BAST bila kebijakan organisasi memerlukannya;
- beberapa invoice, misalnya invoice per pengiriman;
- retur setelah penerimaan atau setelah invoice.

## 5. PO termin

Pada PO termin, jadwal pembayaran dan realisasi penerimaan adalah dua dimensi yang
berbeda. Termin tidak boleh dijadikan sumber mutasi stok.

Contoh:

| Termin | Syarat | Dampak stok | Dampak keuangan |
|---|---|---|---|
| Uang muka 20% | PO/kontrak disetujui | Tidak ada | Uang muka pemasok |
| Termin 2 sebesar 50% | Pengiriman/penerimaan minimum tercapai | Sesuai barang yang diterima | Utang/tagihan termin dikurangi uang muka bila berlaku |
| Termin final 30% | BAST final dan seluruh kewajiban selesai | Tidak ada mutasi tambahan jika receipt telah diposting | Pelunasan dan retensi bila ada |

Struktur relasinya:

```text
PO
|-- PO item
|-- Jadwal pengiriman
|   `-- Penerimaan gudang -> detail/QC/putaway -> BAST
|-- Termin pembayaran
|   `-- Tagihan termin -> verifikasi -> pembayaran
`-- Perubahan PO/adendum
```

Nilai termin dapat berbasis persentase, nominal, milestone, kuantitas diterima, atau
BAST. Setiap tagihan termin harus menyimpan dasar perhitungan dan saldo yang belum
ditagihkan agar tidak terjadi pembayaran melebihi nilai PO.

## 6. BAST barang dan BAST jasa

BAST perlu dibedakan berdasarkan objeknya:

### 6.1 BAST barang

- Dibentuk dari satu atau beberapa penerimaan gudang.
- Menampilkan qty PO, qty diterima, qty diterima QC, qty ditolak, dan kekurangan.
- Tidak membuat mutasi stok baru.
- Menyimpan pihak yang menyerahkan, menerima, memeriksa, dan menyetujui.
- Dapat menjadi syarat invoice atau termin pembayaran.

### 6.2 BAST jasa

- Tidak memiliki penerimaan stok.
- Mengacu pada PO/kontrak jasa, milestone, volume pekerjaan, atau periode layanan.
- Menjadi dasar pengakuan beban/aset dalam penyelesaian dan kelayakan penagihan.

Pemisahan ini mencegah pemaksaan seluruh PO melalui tabel stok, terutama untuk jasa,
langganan, sewa, dan pekerjaan konstruksi.

## 7. Matching sebelum tagihan dibayar

### 7.1 Two-way matching

Membandingkan PO dengan invoice. Ini hanya layak untuk kasus tertentu seperti uang
muka atau jasa yang belum membutuhkan bukti penerimaan fisik.

### 7.2 Three-way matching

Membandingkan:

1. PO dan PO item;
2. penerimaan gudang yang telah diposting;
3. invoice/tagihan pemasok.

### 7.3 Four-way matching

Menambahkan BAST atau hasil QC sebagai dokumen keempat. Model ini disarankan untuk
barang bernilai tinggi, barang terkendali, aset, dan kontrak yang mensyaratkan BAST.

Hasil matching minimal harus mencatat:

- selisih qty PO, diterima, diterima QC, dan ditagihkan;
- selisih harga, diskon, pajak, ongkos, dan pembulatan;
- toleransi yang diperbolehkan;
- alasan override serta pemberi persetujuan;
- nilai yang sudah ditagihkan dan sudah dibayar;
- status `MATCHED`, `PARTIAL`, `HOLD`, atau `REJECTED`.

## 8. Relasi struktur tabel yang diperlukan

Nama final mengikuti konvensi repository dan hasil audit schema, tetapi hubungan
logis berikut perlu tersedia:

| Tabel/logical aggregate | Relasi utama | Catatan |
|---|---|---|
| `purchase_request` | unit peminta, gudang, item | Permintaan kebutuhan; dapat berasal dari replenishment. |
| `purchase_order` | PR, pemasok, kontrak | Header komitmen pembelian. |
| `purchase_order_item` | PO, produk/UOM | Qty, harga, toleransi, gudang tujuan. |
| `purchase_order_term` | PO | Termin, milestone, persentase/nominal, jatuh tempo. |
| `inbound_shipment` | PO/pemasok | Informasi pengiriman dan expected receipt. |
| `goods_receipt` | shipment, PO, gudang | Header penerimaan fisik. |
| `goods_receipt_item` | receipt, PO item, produk | Qty diterima/rusak/ditolak dan hasil QC. |
| `putaway_task` | receipt item, lokasi sumber/tujuan | Penempatan barang ke bin. |
| `mutasi_stok` | receipt/return/transfer | Ledger stok kanonis; tidak boleh diduplikasi oleh BAST. |
| `bast` | PO/receipt/service milestone | Dokumen serah terima formal. |
| `bast_item` | BAST, receipt item/PO item | Menjaga traceability hingga item. |
| `vendor_invoice` | pemasok, PO, termin | Header tagihan. |
| `vendor_invoice_item` | invoice, PO item/receipt item | Dasar matching per item. |
| `invoice_match_result` | invoice/PO/receipt/BAST | Snapshot hasil matching dan override. |
| `payment_request` | invoice/termin | Permintaan pembayaran yang sudah disetujui. |
| `payment` | payment request, kas/bank | Realisasi pembayaran dan bukti transfer. |

Jangan membuat salinan bebas dari kode produk, pemasok, PO, atau penerimaan tanpa
menyimpan foreign key sumber. Snapshot nama/nilai boleh ditambahkan untuk kebutuhan
audit, tetapi bukan menggantikan relasi.

## 9. Status dokumen yang disarankan

| Dokumen | Status minimum |
|---|---|
| PR | `DRAFT`, `SUBMITTED`, `APPROVED`, `REJECTED`, `CONVERTED`, `CANCELLED` |
| PO | `DRAFT`, `APPROVED`, `SENT`, `PARTIALLY_RECEIVED`, `RECEIVED`, `CLOSED`, `CANCELLED` |
| Penerimaan | `DRAFT`, `IN_QC`, `PARTIALLY_ACCEPTED`, `POSTED`, `REJECTED`, `REVERSED` |
| BAST | `DRAFT`, `SUBMITTED`, `SIGNED`, `REJECTED`, `CANCELLED` |
| Tagihan | `DRAFT`, `MATCHING`, `HOLD`, `VERIFIED`, `APPROVED`, `PARTIALLY_PAID`, `PAID`, `CANCELLED` |
| Pembayaran | `DRAFT`, `APPROVED`, `PROCESSING`, `REALIZED`, `FAILED`, `REVERSED` |

Transisi status harus divalidasi di backend dan diaudit. Perubahan status tidak
boleh hanya bergantung pada tampilan Flutter/JSP/ZK.

## 10. Idempotensi dan pencegahan duplikasi

- Posting penerimaan menggunakan `idempotency_key` unik.
- BAST tidak memposting ulang receipt yang sama.
- Invoice pemasok memiliki constraint unik pemasok + nomor invoice + tenant.
- Satu invoice item tidak boleh menagihkan receipt item melebihi qty/value tersisa.
- Pembayaran menggunakan reference/idempotency unik untuk mencegah transfer ganda.
- Reversal membuat transaksi pembalik, bukan menghapus ledger atau jurnal lama.
- Semua retry API harus menghasilkan status dokumen yang sama, bukan baris baru.

## 11. Integrasi akuntansi

Contoh jurnal konseptual, tetap mengikuti konfigurasi akun dan kebijakan organisasi:

### Penerimaan barang dengan accrual

```text
Dr Persediaan / Barang Dalam Pemeriksaan
   Cr GRNI / Barang Diterima Belum Ditagih
```

### Invoice telah diverifikasi

```text
Dr GRNI
Dr Pajak Masukan (bila berlaku)
   Cr Utang Pemasok
```

### Uang muka termin

```text
Dr Uang Muka Pemasok
   Cr Kas/Bank
```

### Pembayaran tagihan

```text
Dr Utang Pemasok
   Cr Kas/Bank
```

Jurnal aktual harus idempoten, seimbang, memiliki referensi dokumen sumber, dan
tidak boleh dipicu dua kali oleh receipt, BAST, atau tombol pembayaran.

## 12. Skenario khusus yang wajib didukung

- Satu PR menjadi beberapa PO atau satu PO menggabungkan beberapa PR.
- PO barang dan jasa dalam kontrak yang sama.
- Penerimaan parsial, lebih, kurang, rusak, dan ditolak.
- Barang langsung dipakai tetapi tetap memiliki jejak penerimaan.
- Barang konsinyasi yang belum menjadi persediaan milik organisasi.
- Drop shipment ke unit selain gudang utama.
- Invoice tanpa PO dengan otorisasi khusus.
- Tagihan sebelum barang datang, khusus uang muka/termin.
- Retensi, denda, potongan, PPN/PPh, dan biaya pengiriman.
- Retur setelah invoice atau pembayaran.
- Pembatalan receipt yang telah memiliki BAST/invoice wajib melalui reversal terkontrol.

## 13. UAT integrasi minimum

1. PR disetujui dan dikonversi menjadi PO tanpa mengubah stok.
2. PO diterima parsial; hanya qty yang lolos QC masuk ledger.
3. Putaway memindahkan lokasi tanpa mengubah total stok gudang.
4. BAST dari receipt tidak menambah stok untuk kedua kali.
5. Invoice melebihi qty receipt tertahan oleh matching.
6. Invoice sesuai PO dan receipt dapat diverifikasi.
7. PO termin uang muka tidak menambah stok.
8. Termin berikutnya menghitung nilai tersisa dengan benar.
9. Pembayaran yang diulang dengan reference sama tidak terposting dua kali.
10. Retur membalik stok dan memperbarui exposure utang secara terlacak.
11. Laporan PO, penerimaan, BAST, invoice, pembayaran, stok, dan jurnal dapat
    ditelusuri hingga dokumen sumber yang sama.

## 14. Keputusan sebelum implementasi

Sebelum DDL/API dibuat, perlu dipastikan:

1. kapan ownership barang berpindah dan kapan stok dianggap tersedia;
2. apakah BAST wajib per receipt, per PO, per termin, atau hanya kategori tertentu;
3. toleransi qty/harga dan siapa yang boleh override;
4. kebijakan accrual GRNI dan waktu posting persediaan;
5. aturan uang muka, retensi, pajak, dan pembayaran parsial;
6. apakah satu invoice boleh mencakup beberapa PO/receipt;
7. tabel existing mana yang menjadi canonical PR, PO, BAST, tagihan, dan pembayaran;
8. feature flag serta strategi migrasi dokumen lama.

## 15. Rekomendasi

Pergudangan harus dibangun sebagai bagian dari proses `procure-to-pay`, tetapi tetap
memiliki batas domain yang jelas. Gunakan `mutasi_stok` sebagai ledger kanonis dan
hubungkan receipt, BAST, invoice, pembayaran, dan jurnal melalui referensi dokumen
yang dapat ditelusuri. Hindari menyalin ulang transaksi penerimaan pada BAST atau
tagihan karena akan menimbulkan stok, utang, atau jurnal ganda.
