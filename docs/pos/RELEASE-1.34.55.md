# v1.34.55 build 218 - rilis Windows & Android Al-Bahjah dan TokoQu An Nahl

Rilis ini menaikkan versi aplikasi dari `1.34.54+217` menjadi `1.34.55+218`
dan membangun ulang installer Windows serta APK Android untuk varian:

- Al-Bahjah POS (Windows Setup & Android APK)
- TokoQu Al-Bahjah An Nahl (Windows Setup & Android APK)

## Ringkasan Perubahan & Fitur

1. **Laporan Transaksi - Rincian Produk (TokoQu An Nahl & Al-Bahjah)**:
   - Menambahkan kolom **Metode** (Metode Pembayaran) pada tabel sub-tab Rincian Produk.
   - Menambahkan kolom **Metode** pada ekspor dokumen dinamis (PDF, Excel, Word).
   - Memperbaiki filter **Metode Bayar**: pemetaan `metode` ke `metodeExact` di backend (`daftarOrderDenganSesi` & `prosesLaporanRincianProduk`) dan frontend (`_filter`) sehingga saat memilih metode pembayaran (mis. "QRS - BSI", "Voucher Santri", dll.) dan menekan "Terapkan", daftar rincian dan rekap produk terfilter secara akurat.

2. **Perbaikan Error Popup `mutasi_piutang_detail`**:
   - Menambahkan routing aksi `mutasi_piutang_detail` ke `KantinHelper.mutasiPiutangDetail` di `PosApi.java`.
   - Menambahkan otorisasi di `bolehAksesActionKantin` untuk modul anggota.
   - Menambahkan flag `bolehEntryPelunasanPiutang` pada respons konfigurasi.

3. **Laporan Faktur Belum Lunas (Custom Kolom Al-Bahjah)**:
   - Menambahkan kolom **Nomor Identitas** (`coalesce(nullif(trim(a.kode_identitas),''), nullif(trim(a.kode),''), '-')`) untuk menampilkan NIPY/NIM/ID Member.
   - Menambahkan kolom **Tipe Member** (`coalesce(nullif(trim(ta.nama),''), nullif(trim(a.tipe),''), nullif(trim(ja.nama),''), '-')`).
   - Filter pencarian pelanggan (`qc`) diperluas untuk mencakup nama, nomor identitas, kode pelanggan, dan tipe/kategori member.

## Validasi build

Perintah build:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_semua_varian.ps1 -Hanya albahjah,nahl -IzinkanUnsignedWindows -IzinkanDebugSigning
```

Hasil: Lulus, 4 artefak berhasil dibuat.

## Artefak Rilis

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.55/` dan tidak disimpan di Git.

| Varian | Berkas | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah POS (Windows) | `Al-Bahjah-POS-Setup-1.34.55.exe` | 90.034.940 byte | `8cd91d8f03203c052d9ab5f977c745334ab29d269f30f9e6286603cd9751d810` |
| Al-Bahjah POS (Android) | `app-albahjah-release.apk` | 196.525.675 byte | `f981b7b6d2bee5a7db3e3f56a18a2b45a6554aabba77941e90c452f07ca3ec1d` |
| TokoQu An Nahl (Android) | `app-nahl-release.apk` | 196.514.303 byte | `c272895521a0ca6e632597b588a74f6dffcbd72a150f5592812da77277d10121` |
| TokoQu An Nahl (Windows) | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.55.exe` | 90.064.309 byte | `1e810d5ad8af5394badfa61d79054fde7630c3b55ccbe85746395e6a573f8574` |
