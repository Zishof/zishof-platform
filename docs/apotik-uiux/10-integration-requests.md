# 10 — Integration Request (gap backend)

Daftar data yang **diminta mockup tetapi belum ada di server**. Sesuai aturan
dokumen perintah (§3, §24): gap dicatat sebagai permintaan integrasi, **tidak
dipalsukan** menjadi sukses/angka karangan di UI.

Semua UI Fase 1–3 sudah dibangun agar field baru cukup **ditambahkan**, tanpa
merombak layar.

| ID | Kebutuhan | Kondisi server sekarang | Dampak UI sekarang | Usulan perubahan backend |
|---|---|---|---|---|
| **IR-01** ✅ | Atribut obat: golongan (Rx/OTC/keras/narkotika), bentuk sediaan, kekuatan, `high_alert`, `cold_chain` | `apotik_item_cari` hanya mengirim `lasa`, `terkendali`, `kandungan`, `barcode`, `satuan`, `stok`, `hargaJual` | `MedicationCard` hanya menampilkan yang ada; badge Rx/high-alert/cold-chain tidak dirender | tambah field pada `ApotikApiHelper.itemCari` (sumbernya sebagian sudah ada di profil item) |
| **IR-02** ✅ | Status batch: lokasi, saldo ditahan, karantina, recall, rusak | `apotik_item_batch` / `apotik_batch_monitor` hanya `kedaluwarsa`, `sisa` | UI menurunkan sendiri `expired`/`nearExpiry`/`depleted`; status lain tidak ditampilkan | tambah kolom status lot + endpoint ubah status |
| **IR-03** | Peringatan klinis: alergi, interaksi, duplikasi terapi, dosis | tidak ada | panel telaah tidak dibuat (menghindari kesan sudah diperiksa) | endpoint telaah + sumber data alergi pasien |
| **IR-04** | Racikan/compounding: formula, BOM, HPP, etiket | `apotik_resep_detail` hanya **membaca** flag `racikan` | mode Racikan & Produksi tampil TERKUNCI beserta alasannya; baris racikan resep tetap terkunci (perilaku existing) | endpoint buat/kerjakan racikan |
| **IR-05** ✅ | Double-check pemeriksa kedua, konseling | **SUDAH ADA** — entity `ApotikDispensingLog` + aksi `apotik_dispensing_status`/`_catat`; server MENOLAK pemeriksa kedua yang sama dengan penyiap | tombol dirakit hanya bila server mendukung | selesai |
| **IR-06** ◑ | Buka/tutup shift & kas laci untuk apotik | **pertanyaannya sudah terjawab:** `SesiKasUtil` menghitung uang dari `koperasi.pembelian_anggota_koperasi`, sedangkan penjualan apotek ada di `sirs.detail_transaksi_pasien` (AJ) + `sirs.apotik_pembayaran_transaksi` — memakai ulang `sesi_kas_*` apa adanya akan melaporkan tunai apotek Rp 0. Rekap uang masuk apotek kini tersedia lewat `apotik_laporan_pembayaran` (r83210) | tab **Rekonsiliasi Kas** menghitung kas seharusnya dari rekap itu; TIDAK ada tombol "Tutup Shift" karena penutupannya belum dapat disimpan — lembar hitungnya dapat disalin/ditandatangani di kertas | sisa keputusan: tambahkan sumber apotek ke `SesiKasUtil` **atau** buat `apotik_sesi_kas_buka/tutup` sendiri |
| **IR-07** ✅ | Daftar metode pembayaran apotik | **SUDAH ADA** — `apotik_cara_bayar_list` + pencatatan di `ApotikPembayaranTransaksi` | dropdown hanya dirakit bila server mengirim daftar | selesai |
| **IR-08** ◑ | Printer, laci kas, cetak ulang, bukti digital | perangkat: **sudah** lewat `core_hw` (jalur RAW ESC/POS Windows) — server: masih tidak ada riwayat cetak maupun bukti digital | struk teks + buka laci + cetak ulang **lokal** sudah jalan (Fase 6); cetak ulang hanya untuk transaksi terakhir di mesin ini dan ditandai `CETAK ULANG` | endpoint riwayat cetak + bukti digital, supaya cetak ulang mungkin dilakukan dari mesin lain dan terlacak |
| **IR-09** | PO PBF, partial receiving, bukti suhu cold-chain | hanya `apotik_terima_barang` | form penerimaan sebatas field yang diterima server | endpoint PO + penerimaan sebagian + lampiran suhu |
| **IR-10** ◑ | SLA resep/racikan, transaksi pending, cold-chain di dasbor | **sebagian ada** — `apotik_metrik_operasional` (r83268) menghitung resep menunggu, batch kedaluwarsa/segera/ditahan, obat habis, transaksi & nilai hari ini dengan COUNT atas SELURUH baris | kartu dasbor memakai angka pasti itu; bila server lama, angka jatuh ke daftar terpotong dan ditandai "100+" alih-alih menyajikan batas halaman sebagai fakta | sisa: kolom `waktu_masuk` pada `sirs.resep` supaya SLA waktu tunggu dapat dihitung jujur |
| **IR-11** ✅ | Uang diterima, kembalian, dan pembayaran terpisah (split) | **SUDAH ADA** — `apotik_pembayaran_transaksi` kini punya kolom `tunai`/`kembalian`, dan `apotik_bayar` menerima larik `pembayaran` [{cara_bayar_id, nominal, tunai, kembalian, referensi}] yang jumlahnya wajib sama dengan total (AIS r83255) | lembar pembayaran punya mode "Bayar terpisah" dengan penanda sisa; kembalian yang tampil benar-benar tersimpan | selesai |

## Status per 2 September 2026

**Selesai:** IR-01, IR-02, IR-05, IR-07 (backend + UI).
**Sebagian:** IR-08 — sisi perangkat (printer, laci, cetak ulang) selesai di
Fase 6; sisi server (riwayat cetak, bukti digital) masih terbuka.
**Masih terbuka:** IR-03, IR-04, IR-09.
**Sebagian:** IR-06 (baca selesai, simpan belum), IR-10 (angka pasti selesai;
SLA waktu tunggu menunggu kolom `waktu_masuk` pada `sirs.resep` — satu-satunya
stempel waktu yang ada sekarang, `tanggal_dirubah`, berubah tiap penyuntingan
sehingga "menunggu 40 menit" yang dihitung darinya akan sering salah).

**IR-11 selesai (AIS r83255).** Sekaligus menutup lubang lama: kolom IR-01 dan
IR-02 ternyata belum pernah punya skrip migrasi tabel audit di repo. Skrip
`docs/sql/2026-09-02-apotik-audit-kolom-baru.sql` kini mencakup ketiganya dan
**wajib dijalankan sebelum restart** — tanpa itu INSERT ke
`new_audit.<tabel>__audit` gagal dan transaksi induknya ikut ter-rollback,
sehingga penyimpanan yang tampak wajar di layar justru hilang.
**Sebagian:** IR-06 — sisi baca (rekap uang masuk per metode) selesai di
Fase 7; yang belum ada adalah PENYIMPANAN buka/tutup shift apotek.

**Tambahan backend Fase 6 (r83182).** `apotik_cara_bayar_list` kini juga
mengirim `adaKembalian` dan `online`. Tanpa `adaKembalian`, klien terpaksa
menebak metode tunai dari namanya (`ilike "tunai"`) — tebakan yang salah untuk
metode tunai yang dinamai lain, dan salah pula sebaliknya. Sekarang kolom
"uang diterima" + kembalian muncul HANYA bila server memang menyatakan metode
itu memberi kembalian; server lama yang belum mengirim flag ini menghasilkan
`false`, jadi kasir cukup memilih metode tanpa layar kembalian.

**IR-03 (peringatan klinis) tidak dapat dikerjakan hanya dengan pemrograman.**
Alergi, interaksi obat, duplikasi terapi, dan pemeriksaan dosis menuntut basis
pengetahuan obat (sumber data berlisensi atau kurasi apoteker). Membuat panel
yang selalu berkata "tidak ada peringatan" LEBIH BERBAHAYA daripada tidak
punya panel sama sekali, karena memberi rasa aman palsu. Layar resep karena
itu menampilkan daftar periksa dari data nyata dan menyatakan terang-terangan
apa yang belum diperiksa sistem.

## Keputusan yang diminta

Dua jalur, keduanya sah:

1. **Tanpa perubahan backend** — UI tetap seperti sekarang: jujur menampilkan
   apa yang ada, sisanya terkunci dengan alasan. Fase 4–7 tetap bisa berjalan
   untuk bagian yang didukung API.
2. **Dengan perubahan backend** — kerjakan IR-01, IR-02, IR-07 lebih dulu
   (dampak terbesar untuk kasir & keselamatan batch), memakai pola yang sama
   dengan penambahan API MitraInap. Setelah itu UI-nya tinggal menyalakan
   badge/kolom yang sudah disiapkan.
