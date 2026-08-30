# Rilis eBisnis POS Desktop 1.34.14

Tanggal rilis: 31 Agustus 2026  
Varian: **eBisnis Desktop (Windows x64)**  
Build: **1.34.14+176**  
Commit sumber: `a6145ace6b44082e5cc954e337168ffa9f0c1efd`

## Perubahan utama

- Menambahkan kebijakan harga beli per produk:
  - **otomatis** mengikuti faktur Kulakan/BAST yang tervalidasi dan sudah
    dikonversi ke satuan dasar; atau
  - **manual** untuk mengunci harga beli agar faktur tidak menimpanya.
- Model katalog, formulir Produk, payload lokal-first, dan kontrak uji sudah
  membawa atribut `hargaBeliManual` secara kompatibel dengan katalog lama.
- Dokumentasi rantai pengadaan sadar-UOM PR -> PO -> BAST dilengkapi sebagai
  rujukan implementasi dan UAT.

## Bukti verifikasi

- `flutter analyze` pada berkas yang berubah: **lulus, 0 masalah**.
- Uji kontrak kebijakan harga beli: **4/4 lulus**.
- Suite Flutter penuh: **575/575 lulus**.
- Clean build Windows x64 dari sumber terbaru: **berhasil**.
- Installer:
  `eBisnis-Setup-1.34.14.exe` (85.832.540 byte).
- SHA-256:
  `D281FC60F08E9CD1224402EB1775A11D3E2D599D3C8899B4BEF6D8589913A4B4`.

Kompilasi native menampilkan warning konversi angka dari dependensi pihak
ketiga `flutter_zxing`; warning tersebut tidak menghentikan build dan seluruh
pengujian aplikasi tetap lulus.

## UAT pascarilis

1. Pasang aplikasi dan pastikan versi di aplikasi menunjukkan 1.34.14.
2. Buka Produk, ubah satu produk, lalu pastikan sakelar **Harga beli manual
   (tidak ikut faktur)** tersimpan setelah form dibuka ulang.
3. Dalam kondisi sakelar mati, proses faktur Kulakan/BAST tervalidasi dan
   pastikan harga beli mengikuti harga satuan dasar hasil konversi UOM.
4. Dalam kondisi sakelar aktif, ulangi faktur dan pastikan harga beli manual
   tidak ditimpa.
5. Putuskan koneksi ketika menyimpan perubahan Produk; data harus tetap
   tersimpan lokal dan masuk antrean sinkronisasi, bukan hilang.

## Catatan distribusi dan rollback

Installer Windows saat ini **belum ditandatangani secara digital**. Windows
dapat menampilkan peringatan penerbit tidak dikenal; distribusikan hanya dari
halaman rilis GitHub resmi dan cocokkan SHA-256 di atas.

Jika ditemukan regresi yang menghambat operasional, hentikan pemutakhiran dan
pasang kembali installer eBisnis Desktop 1.34.12 dari rilis GitHub sebelumnya.
Data lokal tidak boleh dihapus saat rollback. Laporkan log error dan langkah
reproduksi sebelum mencoba sinkronisasi ulang.
