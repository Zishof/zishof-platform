# Pemilih Anggaran Berhenti Memuat Saat Data Kosong

Tanggal: 2026-08-25

## Gejala

Dialog **Pilih Anggaran** menampilkan indikator memuat tanpa henti ketika belum
ada anggaran pada tahun dokumen.

## Akar masalah

Pemuat awal dijalankan berdasarkan kondisi `hasil.isEmpty`. Respons kosong yang
sah tetap memenuhi kondisi tersebut setelah request selesai. Setiap rebuild
kemudian menjadwalkan request baru sehingga dialog berulang antara selesai dan
memuat tanpa pernah menampilkan keadaan kosong.

## Perubahan

- Pemuat awal kini memiliki penanda tersendiri dan hanya dijalankan satu kali.
- Respons `data` kosong atau bukan daftar dinormalisasi menjadi daftar kosong.
- Hasil request lama tidak boleh menimpa pencarian yang lebih baru.
- Request dibatasi 30 detik dan menampilkan pesan yang dapat ditindaklanjuti.
- Penyelesaian request setelah dialog ditutup tidak lagi memperbarui UI.
- Kondisi tanpa anggaran sekarang menampilkan pesan
  **Tidak ada anggaran aktif untuk tahun ini.**

Perbaikan berada pada widget bersama sehingga berlaku untuk pemilih anggaran di
Kas Besar, Kas Kecil, reimbursement, dan penggantian kas.
