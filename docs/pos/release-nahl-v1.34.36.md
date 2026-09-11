# Rilis Nahl POS v1.34.36 (build 199)

Rilis khusus varian **TokoQu Al-Bahjah An Nahl**. Artefak dan kanal pembaruan
tidak dicampur dengan varian Al-Bahjah, eBisnis, Apotek, atau Inventory & Sales.

## Artefak UAT

| Artefak | Ukuran | SHA-256 | Signing |
|---|---:|---|---|
| `TokoQu-Al-Bahjah-An-Nahl-1.34.36-build-199-UAT.apk` | 191.531.089 byte | `1A513E80531ED0E37F16C6F6CDE83CD1CF4245A29B466F0462A063E88155C0B9` | Android Debug — **khusus UAT internal** |
| `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.36-UAT.exe` | 86.178.218 byte | `460CE670FB54D3B1D430BECA109223E45332C011174112E70A4BB917A6E99A1F` | Unsigned — **khusus UAT internal** |

Kedua artefak adalah prerelease UAT, bukan paket produksi. Keystore varian lain
tidak digunakan silang.

## Perubahan

- Tambah Produk Cepat kini selalu memakai kode produk nonkosong.
- UOM stok dan pembelian wajib dipilih serta ikut dikirim ke server.
- Master UOM dapat dibaca dari cache agar alur pembuatan produk tetap
  local-first ketika jaringan tidak stabil.
- Draf produk dengan ID lokal sementara tidak dapat masuk transaksi POS.
- Stok masuk/opname dan perubahan stok lokal kini disimpan atomik bersama
  antrean sinkron; stok lokal langsung menjadi acuan sebelum dikirim ke server.
- Penjualan mengurangi stok lokal tepat satu kali. Retry kode transaksi yang
  sama tidak lagi mengurangi stok untuk kedua kalinya.
- Sinkron transaksi menunggu stok masuk/opname produk terkait diterima server
  lebih dahulu, sehingga urutan `masuk -> keluar` tetap benar.
- Refresh katalog dari server tidak menimpa stok lokal yang masih memiliki
  mutasi pending/gagal.
- Edit nama/harga produk tidak lagi mengirim ulang nilai stok lama sebagai
  stok opname baru.
- Backend pencegahan checkout ganda tersedia pada SVN r88715.

## Catatan operasional

Rilis ini mencegah kesalahan baru. Rilis tidak otomatis mengubah stok `AN000710`,
`AN001000`, atau menghapus 42 pasangan transaksi historis yang terdeteksi,
karena tindakan tersebut memerlukan verifikasi fisik/keuangan dan pembalikan
resmi.

Lihat hasil lengkap pada
`docs/pos/uat-nahl-v1.34.36-20260911/HASIL-UAT-ULANG-WA.md`.
