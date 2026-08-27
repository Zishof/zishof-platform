# Rilis Al-Bahjah POS Desktop 1.33.91 (build 149)

Tanggal rilis: 27 Agustus 2026

## Perubahan

- Semua metode dengan kode/nama mengandung **Kasbon** otomatis dicatat sebagai **Piutang Customer**.
- Kasbon wajib mempunyai member sebagai customer/PJ/PIC; Kasbon Divisi/Operasional memakai member sebagai PIC yang mewakili divisi.
- Master Cara Pembayaran menampilkan kolom **Piutang Customer** dan **Wajib PIC**. Kedua aturan tidak dapat dimatikan untuk metode Kasbon.
- Pesan checkout menjelaskan apa yang terjadi dan mengarahkan kasir memilih **Member/PIC** sebelum melanjutkan.
- Diagnostik Posting menampilkan dokumen, setting akun yang belum lengkap, serta tindakan yang perlu dilakukan admin.
- Installer Al-Bahjah mengecualikan executable varian lain yang mungkin tertinggal pada folder build.

## Backend

- SVN: `r78389` — seluruh Kasbon dinormalisasi menjadi `masuk_sebagai_hutang=true` dan `wajib_pilih_member=true` secara idempoten saat startup.
- API penyimpanan master menegakkan aturan yang sama agar Kasbon tidak dapat kembali dianggap pembayaran lunas.
- Java 8 compilation: berhasil untuk `CaraPembayaranKoperasi`, `PosApi`, `KantinHelper`, dan `InitIndex` beserta dependensinya.

Normalisasi master dapat membuat transaksi Kasbon historis yang sebelumnya salah berstatus bukan hutang muncul pada saldo piutang customer. Tim keuangan wajib merekonsiliasi Mutasi Hutang/Piutang Member sebelum penerimaan piutang atau posting massal.

## UAT dan pre-deploy

- [x] Test khusus Kasbon/PIC dan refresh metode pembayaran: 9/9 lulus.
- [x] Seluruh suite Flutter: 395/395 lulus.
- [x] `git diff --check`: lulus untuk perubahan rilis.
- [x] Build Windows Desktop varian `albahjah`: berhasil.
- [x] Installer hanya memuat executable `ebisnis_albahjah.exe`; executable varian lain dikecualikan.
- [x] SHA-256 manifest cocok dengan perhitungan ulang.
- [x] Product/File version executable: `1.33.91+149`.

## Build dan publikasi

- Varian: `albahjah`.
- Platform: Windows Desktop saja (`-SkipAndroid`).
- Versi: `1.33.91+149`.
- Skrip: `tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah`.
- Commit implementasi: `db6143a`.
- Commit versi: `8f4c87a`.
- Backend SVN: `r78389`.
- Tag GitHub: `v1.33.91-build149`.
- Authenticode: `NotSigned` karena pipeline lokal belum memiliki sertifikat.

## Artefak

| Berkas | Ukuran | SHA-256 |
|---|---:|---|
| `Al-Bahjah-POS-Setup-1.33.91.exe` | 47.071.956 byte | `05723D1778ACB47FDAE8B0041284906E9374C4E2A499623CBE2BA65123AE57CE` |

Manifest: `Al-Bahjah-POS-Setup-1.33.91.exe.sha256.txt`.

## Setelah pemasangan

1. Pastikan backend minimal sudah memuat SVN `r78389` dan telah direstart agar normalisasi idempoten berjalan.
2. Pada desktop tekan **Sinkronkan**, kemudian **Muat Ulang**.
3. Buka **Master Data > Cara Pembayaran** dan pastikan setiap Kasbon menunjukkan **Piutang Customer = Ya** serta **Wajib PIC = Ya**.
4. Pastikan **Maksimal Boleh Utang** pada Tipe Member cukup untuk kebijakan Kasbon terkait.
5. Uji transaksi kecil: pilih member/PIC, pilih Kasbon Divisi, bayar, lalu periksa Mutasi Hutang/Piutang Member.
6. Untuk transaksi pending yang pernah ditolak, buka **Pesanan > Transaksi Pending > Coba Kirim Transaksi Pending** setelah batas dan master benar.

## Rollback

- Hentikan rollout bila Kasbon tidak masuk saldo piutang customer, Kasbon dapat dibayar tanpa PIC, atau saldo historis berubah di luar hasil rekonsiliasi yang disetujui.
- Installer desktop dapat dikembalikan ke `1.33.90`; jangan membalik normalisasi master atau mengubah transaksi historis secara manual. Eskalasi koreksi ledger kepada supervisor/tim keuangan agar jejak audit tetap utuh.
