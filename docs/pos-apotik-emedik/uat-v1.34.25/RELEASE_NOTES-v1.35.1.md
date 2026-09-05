# Apotik v1.35.1 (build 189) - UAT/Pilot

Rilis klien Apotik ini menyelesaikan stabilisasi Kasir dan memperbarui bukti UAT serta panduan pengguna. Backend yang digunakan adalah API `apotik-v1.34.25+187` pada server demo yang telah dideploy sebelumnya. Paket ini tidak memuat WAR atau perubahan server.

## Perubahan utama

- Membuka seluruh mode Kasir: OTC/Obat Bebas, Resep Dokter, Racikan, Produksi Farmasi, dan Tebus Resep.
- Memperbaiki alur pembayaran OTC sampai transaksi tersimpan, termasuk validasi tunai, non-tunai, referensi, kembalian, dan anti-double-submit.
- Menyelesaikan alur end-to-end resep dokter, racikan, produksi farmasi, serta tebus resep campuran secara atomik.
- Menambahkan integrasi profil pasien dan alergi dari SIRS pada konteks farmasi.
- Menyegarkan screenshot UAT 1920 x 1080 dan manual pengguna 73 halaman untuk klien 1.35.1+189.

## Hasil verifikasi

- UAT server nyata: 100 operasi per alur, 500 operasi utama seluruhnya PASS.
- Post-flight idempotensi: 500/500 kode unik PASS, tanpa transaksi atau mutasi stok ganda.
- Regresi UI Kasir terfokus: 96/96 test PASS.
- Regresi penuh aplikasi: 1.020/1.020 test PASS.
- Capture seluruh menu Apotik: 13/13 menu terbuka, screenshot live PASS.
- Smoke test executable Windows release: PASS.
- Analisis statis: tidak ada error atau warning; terdapat 50 lint info yang sudah ada dan tidak memblokir build.

## Artefak

- `Apotik-v1.35.1-build189-android-uat.apk`
- `eBisnis-POS-Apotik-Setup-1.35.1.exe`
- `Laporan-UAT-dan-Panduan-Apotik-v1.35.1.docx`
- `Laporan-UAT-dan-Panduan-Apotik-v1.35.1.pdf`
- `SHA256SUMS.txt`

## Batas penggunaan dan keamanan

- APK ditandatangani sertifikat Android Debug dan hanya untuk UAT/pilot internal.
- Installer Windows belum memiliki signature Authenticode dan hanya untuk UAT/pilot internal.
- Data demo tidak boleh digunakan sebagai acuan terapi, klaim registrasi obat, atau keputusan klinis.
- Pada beban UAT sempat terlihat 17 respons gateway sementara (HTTP 502/503/timeout). Seluruh kode terdampak lulus pemeriksaan ulang dan tidak menghasilkan data ganda; tetap pantau reverse proxy/Tomcat saat beban tinggi.

## Instalasi dan rollback

- Android: pasang APK pada perangkat UAT yang mengizinkan sumber internal. Jangan distribusikan melalui kanal produksi.
- Windows: jalankan installer EXE sebagai paket UAT dan konfirmasi publisher yang belum terverifikasi hanya pada lingkungan yang disetujui.
- Rollback: gunakan artefak rilis Apotik sebelumnya, `apotik-v1.34.24`, tanpa menghapus audit trail. Reversal transaksi harus mengikuti prosedur bisnis yang disetujui.

Status rilis: **prerelease UAT/pilot - bukan paket produksi**.
