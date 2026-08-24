# POS Desktop 1.33.82 — Al-Bahjah dan eBisnis

Rilis ini menyatukan koreksi alur pengadaan dan proses transfer pada dua varian Desktop Windows.

## Perubahan utama

- Tombol `Dari PR` dan `Buat PO` dipindahkan ke header halaman PO agar tidak menutup isi dashboard.
- Tombol bantuan ganda pada PO dan Terima Tagihan Vendor dihilangkan; bantuan mengambang tetap tersedia.
- Kontrol tanggal Proses Transfer diselaraskan dengan kontrol filter lain.
- Aksi `Realisasikan (dana cair)` dikunci setelah proses sudah terealisasi.
- Realisasi pembayaran vendor otomatis membentuk jurnal umum secara idempoten.

## Verifikasi

- Seluruh **356 tes Flutter lulus**.
- `dart analyze` pada berkas Flutter yang berubah: **No issues found**.
- Kompilasi backend dengan `javac -source 7 -target 7`: **lulus**.
- Build Windows dua varian: **berhasil**.
- Backend Java terkait sudah masuk SVN sampai revisi **r78258**.

## Artefak

| Varian | Berkas | Ukuran | SHA-256 |
|---|---|---:|---|
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.33.82.exe` | 46.136.815 byte | `54f61a0e5ff98e016fbc730494674056014a2c6619a7bb1a9b17513f7247acf8` |
| eBisnis | `eBisnis-Setup-1.33.82.exe` | 46.081.099 byte | `b3056cc15ec6520551f90111befb228f4d542c656b227b472d971671356c54b4` |

Manifest `.sha256.txt` disertakan untuk masing-masing installer. Pipeline lokal belum memiliki sertifikat Authenticode, sehingga installer berstatus `NotSigned` pada pemeriksaan Windows.

## Catatan deployment

Fitur jurnal otomatis membutuhkan backend minimal SVN `r78258`. Deploy backend tersebut sebelum melakukan UAT realisasi pembayaran vendor di aplikasi Desktop.
