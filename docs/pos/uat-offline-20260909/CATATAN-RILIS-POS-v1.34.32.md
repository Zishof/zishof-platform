# Catatan Rilis POS Desktop v1.34.32

Tanggal rilis: 9 September 2026
Build: `1.34.32+195`

## Ringkasan

Rilis ini memperbaiki penanganan transaksi pending ketika pusat data tidak dapat dijangkau serta membedakan gangguan jaringan dari penolakan aturan bisnis. Perubahan diterapkan pada kode bersama POS Desktop eBisnis, Al-Bahjah, Nahl, Inventory/Sales, dan Apotek.

Kasus acuan adalah transaksi `AB20909202600019` senilai Rp149.500 yang memakai Voucher Pejuang sementara saldo member SAHRUL ARIFIN di server hanya Rp3.160. Server sudah benar menolak transaksi. Klien versi lama memperlakukan pesan penolakan tanpa kode sebagai gangguan sementara sehingga mengulang pengiriman sembilan kali. Versi ini menghentikan retry otomatis, memberi status **Perlu koreksi**, mempertahankan jejak transaksi, dan menyediakan pilihan koreksi yang aman.

## Perubahan utama

- HTTP 522 dan respons non-JSON tidak lagi memicu `FormatException`; respons diubah menjadi pesan yang mudah dipahami dan tetap mempunyai tombol **Detail**.
- HTTP 5xx tetap dianggap gangguan sementara dan dapat dicoba ulang memakai backoff.
- Penolakan saldo, limit, metode pembayaran, PIN, stok, dan akses diklasifikasikan sebagai penolakan bisnis. Retry otomatis dihentikan sampai data diperbaiki.
- Transaksi berstatus **Perlu koreksi** dapat diganti ke metode pembayaran lokal yang aman hanya setelah operator mengonfirmasi bahwa pembayaran benar-benar telah diterima.
- Koreksi mempertahankan kode transaksi, waktu pembuatan, toko, kasir, item, harga, dan total; transaksi yang telah tersinkron tidak dapat diubah melalui jalur lokal.
- Riwayat sinkronisasi membedakan **Menunggu**, **Perlu koreksi**, dan **Tersinkron**.
- Pencarian katalog, racikan, produksi, batch, metode pembayaran, dan laporan Apotek memakai cache terpisah per varian, tenant, pengguna, toko, dan kata kunci.
- Laporan generik dan laporan Apotek menampilkan snapshot lokal beserta waktu pembaruan. Jika belum ada cache, pengguna mendapat penjelasan dan tombol **Detail**.
- Draf jurnal dapat dipertahankan lokal. Posting jurnal dan closing final tetap menunggu ACK server.

## Batas keselamatan local-first

Local-first menjaga kesinambungan kerja, bukan mengganti otorisasi pusat dengan keberhasilan palsu.

| Proses | Saat offline | Alasan |
|---|---|---|
| Kantin — tunai/manual | Disimpan lokal dan masuk outbox | Tidak memotong saldo pusat |
| Voucher/saldo/PIN/biometrik | Menunggu server | Mencegah saldo atau limit negatif |
| Apotek — katalog/batch/laporan | Membaca salinan lokal bertimestamp | Membantu persiapan dan penelusuran |
| Apotek — pembayaran final/obat terkendali | Menunggu server | Memerlukan stok, ED, resep, dan register pusat |
| Sales dan CRUD yang queueable | Disimpan lokal dengan ID sementara | Disinkronkan secara idempoten |
| Approval, pembatalan final, posting, closing | Draf lokal; final menunggu server | Menjaga integritas stok dan buku besar |
| Laporan | Snapshot lokal; transaksi pending belum masuk angka resmi | Laporan resmi hanya dari data final |

## Bukti UAT

- Seluruh suite Flutter: **845/845 lulus, 0 gagal**.
- UAT visual Windows: **1/1 lulus**, menghasilkan empat screenshot bukti.
- Uji kanal auto-update aktif: **lulus** untuk seluruh varian.
- Endpoint eBisnis dan Nahl kembali memberi respons JSON; respons tanpa token adalah HTTP 401 yang valid.
- Login demo eBisnis berhasil; token tidak dicetak atau dimasukkan ke dokumen.
- Lima installer Windows berhasil dibangun dari source dan versi yang sama, lengkap dengan SHA-256.

UAT otomatis tersebut tidak berarti transaksi berisiko boleh difinalkan tanpa server. Status lulus berarti setiap alur mengikuti pagar keselamatan yang ditentukan: data tidak hilang, status tidak menyesatkan, retry tidak menggandakan transaksi, dan tindakan berisiko tetap fail-closed.

## Catatan deploy

Perbaikan utama berada di aplikasi POS Desktop/Android. **Tidak diperlukan deploy server** untuk menangani kasus saldo acuan. Pagar saldo server harus tetap dipertahankan. Peningkatan server berikutnya dapat menambahkan kode penolakan bisnis terstruktur, tetapi klien v1.34.32 tetap kompatibel dengan pesan lama.

Installer Windows pada rilis ini dibangun sebagai artefak UAT tanpa Authenticode. SHA-256 disediakan untuk verifikasi integritas unduhan.
