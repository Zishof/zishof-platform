# 09 — Baseline Performa

## Kondisi existing yang relevan

- Pencarian obat **server-side** (`apotik_item_cari` ber-`page`) — tidak memuat
  seluruh katalog ke memori. Ini fondasi bagus dan **wajib dipertahankan**.
- Daftar hasil memakai `ListView` sederhana; jumlah item per halaman dibatasi server.
- Sejak konversi baca lokal-dulu, daftar master disajikan dari cache SQLite
  (`cache_referensi`) lalu di-merge dengan respons server.

## Risiko saat katalog membesar (ribuan–puluhan ribu obat)

| Risiko | Mitigasi yang akan dipakai |
|---|---|
| Snapshot cache besar di-decode sekali jalan | batasi cache per konteks (sudah: kunci cache per properti/filter); pertimbangkan halaman |
| Rebuild seluruh daftar tiap keystroke | debounce pencarian + `ValueKey` stabil per baris |
| Kartu obat berat (banyak badge) | widget const + `RepaintBoundary` pada kartu |
| Golden test lambat | ukuran surface tetap, font bundel |

## Target yang diukur pada Fase 8

- waktu render awal layar POS;
- waktu dari keystroke ke daftar hasil (debounce diperhitungkan);
- jumlah widget pada layar POS desktop;
- memori saat katalog besar.

Angka baseline diisi saat Fase 8 dengan alat ukur yang sama sebelum/sesudah,
agar perbandingan sahih.

## Hasil telaah Fase 8

Yang diperiksa ulang dengan test, bukan dengan perkiraan:

- **Daftar yang panjangnya mengikuti data server sudah malas.** Monitor
  kedaluwarsa (`ListView.builder`) dan antrean resep (`ListView.separated`)
  hanya membangun baris yang terlihat; diuji dengan 100 baris.
- **Katalog dan formularium sengaja TIDAK diubah menjadi grid malas.** Kartu
  obat tingginya berbeda-beda (jumlah badge keselamatan tidak sama), sedangkan
  `GridView` dengan tinggi tetap akan memotong isi kartu. Memotong badge
  high-alert demi performa adalah pertukaran yang salah. Sebagai gantinya
  jumlahnya dibatasi lewat `page_size` (POS 40, formularium 50) dan ada test
  yang menahan `page_size` katalog agar tidak melewati 60.
- **Pencarian tetap ber-debounce 300 ms** di POS, formularium, dan penerimaan;
  seluruh `TextEditingController`/`Timer` dibebaskan pada `dispose`.

Yang **tidak** diklaim: tidak ada pengukuran milidetik di sini. Angka waktu
render dari mesin pengembang tidak mewakili mesin kasir, dan mencantumkannya
hanya akan terlihat meyakinkan tanpa berarti apa-apa.
