# Al-Bahjah POS 1.34.107+270 — paket uji rak dan stok opname

Tanggal build: 11 November 2026 (WIB)
Varian: `albahjah` saja
Sumber Flutter: `main` pada commit `69d9a1c24b49cadb2c79a1ab6a6500b6cb8f9cc6`, ditambah nomor paket `1.34.107+270`.

## Isi perubahan yang relevan

- Ringkasan Manajemen Rak Produk menerima bentuk jawaban ringkasan bertingkat dan bentuk field sejajar, dengan nilai cadangan yang dapat dihitung dari daftar rak.
- Pilihan rak pada Stok Opname dan SO Grand disatukan dengan daftar rak yang ikut pada baris produk. Pilihan “Rak Belum Ditentukan” dibedakan dari “Semua Rak”.
- Nama produk pada tindakan pelepasan dari rak menerima kedua nama field yang didukung jawaban layanan.
- Pesan kendala penguncian atau basis data tidak diterjemahkan menjadi “Stok belum mencukupi”.

Perubahan layanan Java terpisah telah dipublikasikan ke SVN r121206 dan pedoman terkait diperbarui pada r121207. Paket Windows/Android ini tidak memasang layanan Java dan tidak membuktikan keadaan izin atau data basis data produksi.

## Pemeriksaan dan pembuatan paket

- `git pull --ff-only origin main`: tidak ada perubahan tertunda; commit sumber `69d9a1c24b49cadb2c79a1ab6a6500b6cb8f9cc6`.
- `flutter analyze` untuk empat berkas Dart yang berubah: lulus, tanpa temuan.
- Pengujian untuk pesan kendala, opname, dan akses opname: 17 kasus lulus.
- `flutter clean`: exit 0; Flutter melaporkan folder build sedang dipakai, kemudian skrip resmi membangun ulang kedua keluaran. Pembuatan APK, executable Windows, dan pemasang Windows berakhir dengan exit 0.
- Skrip resmi: `apps/ebisnis/tool/build_semua_varian.ps1 -Hanya albahjah -IzinkanDebugSigning -IzinkanUnsignedWindows`.
- APK berstatus tanda tangan debug/UAT; pemasang Windows belum bertanda tangan. Hanya untuk pengujian internal.
- Kompilasi Java terarah untuk `PosApi`, `KantinHelper`, `RakProdukApiHelper` dan dependency source terkait lulus memakai keluaran eksternal `C:\opt\AIS\buildcheck-pos-20261111-postupdate`; terdapat 11 peringatan kompatibilitas lama, tanpa error.
- Tidak dilakukan akses tulis ke database, pemasangan/eksekusi pada perangkat, UAT pengguna, atau deployment produksi.

## Berkas dan checksum SHA-256

| Berkas | Ukuran | SHA-256 |
|---|---:|---|
| `app-albahjah-release.apk` | 200,426,892 byte | `A8B143867DC89AE535C8AAC5EBACE432E79320162F224225FAAC70CF62F6F011` |
| `Al-Bahjah-POS-Setup-1.34.107.exe` | 90,262,367 byte | `3B50DD35978487666817732F78DDC179EDC864C2B163E907A1DDE210358C6181` |
