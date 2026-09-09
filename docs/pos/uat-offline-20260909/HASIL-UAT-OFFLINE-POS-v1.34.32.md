# Hasil UAT Offline POS v1.34.32

Tanggal: 9 September 2026
Cakupan kode bersama: eBisnis, Al-Bahjah, Nahl, POS Apotek, dan Inventory & Sales.

## Keputusan UAT

**LULUS 100% pada cakupan pengujian otomatis dan bukti UI: 845/845 tes unit,
widget, kontrak API, serta regresi lulus; 1/1 skenario bukti visual Windows
lulus dan menghasilkan empat tangkapan layar.** Kedua endpoint produksi yang
diperiksa mengembalikan JSON yang sah; login demo eBisnis juga berhasil.

Status ini tidak berarti semua tindakan keuangan boleh diberi status final saat
offline. UAT justru memverifikasi batas integritas berikut:

| Fungsi | Saat offline | Alasan |
|---|---|---|
| Kantin, pembayaran Tunai/manual yang aman | Disimpan lokal dan diantre | Tidak membutuhkan saldo/limit pusat |
| Voucher, potong saldo, PIN, biometrik, atau hutang/limit | Menunggu ACK server | Mencegah saldo negatif dan otorisasi palsu |
| CRUD queueable pada master, Keuangan, Pengadaan, dan Sales | Disimpan lokal dengan ID sementara | Direkonsiliasi oleh outbox idempoten |
| Apotek: katalog obat, metode, batch, dan laporan yang pernah dimuat | Membaca salinan lokal | Stempel waktu cache selalu ditampilkan |
| Apotek: pembayaran, resep, obat terkendali, stok/FEFO | Keranjang dipertahankan; final menunggu server | Validasi global stok, kedaluwarsa, dan register wajib |
| Jurnal Umum | Draf dapat dipertahankan lokal | Posting final membutuhkan periode, akun, hak, dan nomor server |
| Posting jurnal dan closing | Tidak dinyatakan final tanpa ACK server | Mencegah buku besar/laporan tidak konsisten |
| Laporan | Menampilkan snapshot lokal beserta waktu | Transaksi pending tidak dihitung sebagai jurnal terposting |

## Perbaikan insiden AB20909202600019

Transaksi memakai Voucher Pejuang senilai Rp149.500, sedangkan saldo SAHRUL
ARIFIN yang divalidasi server adalah Rp3.160. Penolakan server benar; masalahnya
adalah klien lama menganggap pesan penolakan tanpa kode sebagai gangguan
sementara dan mencoba lagi sampai sembilan kali.

Perbaikan v1.34.32:

1. Pesan saldo/limit/metode pembayaran dari server lama diklasifikasikan sebagai
   penolakan bisnis permanen, sehingga retry otomatis dihentikan.
2. Voucher dan semua metode nonmanual yang efektif memotong deposit wajib
   memperoleh ACK server sebelum pembayaran dianggap selesai.
3. Riwayat sinkronisasi membedakan **Menunggu**, **Perlu koreksi**, dan
   **Tersinkron**.
4. Transaksi belum tersinkron dapat diganti ke metode lokal yang aman hanya
   setelah operator mengonfirmasi uang benar-benar telah diterima. Kode,
   waktu, barang, harga, pengguna, toko, dan jejak audit dipertahankan.
5. Detail kendala menampilkan panduan kepada kasir; endpoint, action, kode
   referensi, dan alasan teknis disembunyikan di tombol **Informasi Teknis**.

## Laporan saat offline

- Katalog dan hasil laporan membaca cache lokal terlebih dahulu.
- Snapshot selalu menampilkan waktu terakhir diperbarui dan peringatan bahwa
  angka mungkin belum mencakup transaksi terbaru.
- Bila filter laporan belum pernah dimuat, aplikasi menjelaskan bahwa server
  diperlukan untuk menghitung jurnal terposting. Tombol Detail tetap tersedia.
- Laporan penjualan, obat terkendali, dan kedaluwarsa Apotek memakai pola yang
  sama; register terkendali tidak pernah direka dari data lokal.

## Bukti pengujian

- `flutter analyze` pada berkas yang berubah: tanpa error.
- Seluruh suite `flutter test --no-pub`: 845 lulus, 0 gagal.
- `packages/core_db/test/core_db_test.dart`: 2 lulus, 0 gagal.
- `integration_test/offline_uat_evidence_test.dart -d windows`: 1 lulus,
  0 gagal; empat screenshot berhasil dibuat.
- Probe 9 September 2026:
  - `https://ebisnis.id/ebisnis/Api_eBisnis`: HTTP 401 JSON untuk probe tanpa
    token (respons yang diharapkan), sekitar 1.014 ms.
  - `https://an-nahl.santri.info/nahl/Api_eBisnis`: HTTP 401 JSON untuk probe
    tanpa token (respons yang diharapkan), sekitar 554 ms.
  - Login demo eBisnis: `status=success`, token tersedia, sekitar 743 ms.

## Prosedur operator

Jika transaksi berstatus **Perlu koreksi**, jangan menekan Kirim berulang.
Buka Detail, cocokkan member/metode/nominal, kemudian pilih salah satu:

- topup resmi dan kirim satu kali setelah koneksi tersedia; atau
- bila pembayaran tunai memang telah diterima, gunakan **Ganti ke Pembayaran
  Lokal**, pilih metode manual yang aman, centang konfirmasi penerimaan uang,
  lalu simpan.

Setelah sinkronisasi, cari kode transaksi yang sama pada Riwayat Penjualan.
Jangan membuat transaksi baru untuk menggantikan transaksi pending karena dapat
menggandakan penjualan.

## Catatan deploy server

Perbaikan insiden ini berada di klien POS dan tidak memerlukan perubahan server.
Pagar saldo server harus dipertahankan. Server hanya perlu dideploy ulang bila
kelak kontrak API ditingkatkan agar semua penolakan bisnis selalu membawa kode
`SALDO_TIDAK_CUKUP`, `LIMIT_TIDAK_CUKUP`, atau
`METODE_PEMBAYARAN_TIDAK_VALID`; klien v1.34.32 tetap kompatibel dengan pesan
server lama maupun kode baru.
