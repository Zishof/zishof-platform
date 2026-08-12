# Release eBisnis v1.31.1

## Tema Aplikasi & Alamat Server Bawaan per Varian

- **Pengaturan tema baru** di menu Konfigurasi > Identitas Mesin > "Tampilan" -- pilih warna aksen aplikasi (Biru/Merah/Hijau/Abu-abu), berlaku langsung ke seluruh layar tanpa perlu restart. Pilihan tersimpan per perangkat.
- **Alamat server bawaan per varian build** -- varian Al-Bahjah POS sekarang langsung tersambung ke `siraj.albahjah.or.id/albahjah` sejak instalasi pertama, tanpa perlu mengisi layar "Pengaturan Alamat Server" secara manual. Varian eBisnis (multi-institusi) tidak berubah -- tetap wajib diisi manual seperti biasa.

## Perbaikan

- **Mutasi Stok Antar Outlet**: perbaiki crash layar (`RenderBox was not laid out`) yang bisa muncul saat membuka layar ini.
- **Dialog "Buka Kas Terlebih Dahulu"** dirapikan -- sebelumnya melebar mengikuti seluruh panel kasir, sekarang jadi kartu kompak di tengah layar seperti dialog pada umumnya.

## Instalasi
- **Windows**: unduh `eBisnis-Setup-1.31.1.exe` (atau `Al-Bahjah-POS-Setup-1.31.1.exe` untuk varian bermerek Al-Bahjah) dan jalankan.
