# 57. Fase Penutup — Pratinjau Grosir Kanal Web + Tampilan Reservasi WO

Tanggal: 29 Agustus 2026  
Status: kompilasi bersih (javac 1.7 EXIT=0; blok JS lolos syntax-check node);
Flutter **lulus** (suite penuh 555/555); belum di-commit  
Rujukan: dok. 51 ("yang tertinggal hanya pratinjau di kanal web"),
dok. 54 ("layar menyusul bila diminta")

Dua pekerjaan tertunda yang TERCATAT di dokumen fase sebelumnya dan tidak
membutuhkan keputusan pemilik. Sisanya (Metode 2, kelipatan wajib, reservasi
vs kasir, pemetaan akun jurnal) tetap menunggu keputusan — lihat dok. 56.

## 1. Pratinjau harga grosir di `_pos.jsp` (sisa Fase A)

Kanal web selama ini sudah MENYIMPAN harga grosir dengan benar (otoritas
final lewat `bayar`), tetapi keranjang di layar menampilkan harga katalog
sampai pembayaran. Kini:

- Saat komposisi keranjang berubah (sidik jari `id x jumlah`), JSP memanggil
  aksi **`diskon_evaluasi`** — server menjalankan
  `HargaGrosirApiHelper.terapkanKeItems` yang SAMA dengan `bayar` dan
  mengembalikan peta `hargaGrosir`. **Klien tidak menghitung ambang
  sendiri** — mesin satu, seperti kasir Desktop/Android (Fase A).
- Urutan dipertahankan: harga grosir diterapkan ke baris SEBELUM evaluasi
  diskon klien (`evaluateDiscount` menilai `hargaEfektif`), sama dengan
  urutan server (grosir menetapkan harga, diskon memotong).
- Tampilan baris: lencana "Grosir" + harga efektif + harga katalog
  dicoret; subtotal/pajak/total mengikuti harga efektif.
- Payload `bayar` dan `draft_bayar` mengirim harga efektif (server tetap
  menghitung ulang — pola Fase A/B).
- Gagal jaringan/toko belum terpilih: pratinjau diam-diam kembali ke harga
  katalog; tidak ada alur yang gagal.

**Catatan pohon**: `_pos.jsp` campuran 3241 CRLF / 46 LF di HEAD —
dinormalkan ke CRLF mayoritas, disengaja. Blok JS yang disunting
diverifikasi `node --check`; uji visual kanal web disarankan pada UAT
berikutnya (tidak ada harness JS di pohon ini).

## 2. Rincian WO menampilkan reservasi komponen (pelengkap Fase D)

- Server: `produksi_detail` untuk dokumen WO kini menyertakan array
  `reservasi` (`produkId`, `keterangan`, `qty`, `qtySisa`,
  `statusReservasi`) — murni pembacaan `production_reservation` yang sudah
  ditulis sejak rilis WO (Fase D), tanpa perubahan perilaku lain.
- Flutter (`produksi_screen.dart`): rincian WO menampilkan seksi
  "Reservasi komponen" — sisa vs kebutuhan awal per komponen + status
  (AKTIF/SELESAI/BATAL).

## Berkas

- `webapp/WEB-INF/baru/modul/kantin/pos/_pos.jsp` — pratinjau grosir
  (8 suntingan; normalisasi EOL diungkap di atas).
- `ais/action/servlet/api/ProduksiApiHelper.java` — `detail` WO + reservasi.
- Flutter `screens/produksi_screen.dart` — seksi reservasi.

## Bukti

- `javac -source 1.7` EXIT=0; blok JS tersunting lolos `node --check`.
- Flutter suite penuh **555 lulus / 0 gagal**; analyze bersih di berkas
  tersentuh.
- Perubahan server murni aditif-baca (array baru di respons detail);
  mesin grosir/diskon/reservasi tidak disentuh — buktinya tetap harness
  fase 0–E yang sudah hijau.
