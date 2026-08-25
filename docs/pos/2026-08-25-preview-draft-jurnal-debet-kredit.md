# Preview Draft Jurnal Debet/Kredit

Tanggal: 2026-08-25

## Masalah

Popup rincian **Draft Jurnal** hanya menampilkan dokumen sumber (tanggal, uraian, dan nilai). Tampilan tersebut belum memperlihatkan bentuk jurnal yang akan diposting, sehingga pengguna tidak dapat memeriksa akun Debet/Kredit sebelum data benar-benar masuk ke tabel jurnal.

## Perubahan

- Endpoint `draft_jurnal_rincian` kini dapat mengirim baris jurnal sementara: kode akun, nama akun, Debet, Kredit, total Debet, total Kredit, dan status keseimbangan.
- Untuk modul **Kas Besar**, pemetaan akun mengikuti logika ZKoss `PostingKasBesarAction`:
  - Kas Besar yang terkait Kas Kecil: Debet akun Jenis Kas Kecil, Kredit akun Jenis Kas Besar.
  - Kas Besar biasa: Debet akun penerima Jenis Kas Besar, Kredit akun Jenis Kas Besar.
  - Nilai negatif membalik posisi Debet/Kredit.
- Popup Desktop menampilkan dokumen sumber sebagai referensi, lalu tabel jurnal dengan kolom Akun, Debet, dan Kredit serta total keseimbangan.
- Bila konfigurasi akun belum lengkap, pengguna memperoleh pesan akun yang perlu dilengkapi; sistem tidak membuat jurnal semu dengan akun kosong.

## Batas transaksi

Preview ini hanya membentuk objek transfer data di memori. Tidak ada `save`, `update`, atau penyimpanan ke tabel jurnal. Penyimpanan tetap terjadi hanya melalui proses posting yang telah ada.

## Kontrak respons tambahan

- `jurnal[]`: `kodeAkun`, `namaAkun`, `debet`, `kredit`
- `totalDebet`
- `totalKredit`
- `jurnalSeimbang`
- `pesanJurnal`

## Verifikasi

- Kompilasi backend Java 1.7.
- Analisis statis Flutter pada `draft_jurnal_screen.dart`.
- Pemeriksaan bahwa session dari `openSession()` tetap ditutup melalui `HibernateUtil.closeSessionQuietly()` di blok `finally` (clear/disconnect/close).
