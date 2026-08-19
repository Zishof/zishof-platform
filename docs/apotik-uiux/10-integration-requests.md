# 10 — Integration Request (gap backend)

Daftar data yang **diminta mockup tetapi belum ada di server**. Sesuai aturan
dokumen perintah (§3, §24): gap dicatat sebagai permintaan integrasi, **tidak
dipalsukan** menjadi sukses/angka karangan di UI.

Semua UI Fase 1–3 sudah dibangun agar field baru cukup **ditambahkan**, tanpa
merombak layar.

| ID | Kebutuhan | Kondisi server sekarang | Dampak UI sekarang | Usulan perubahan backend |
|---|---|---|---|---|
| **IR-01** | Atribut obat: golongan (Rx/OTC/keras/narkotika), bentuk sediaan, kekuatan, `high_alert`, `cold_chain` | `apotik_item_cari` hanya mengirim `lasa`, `terkendali`, `kandungan`, `barcode`, `satuan`, `stok`, `hargaJual` | `MedicationCard` hanya menampilkan yang ada; badge Rx/high-alert/cold-chain tidak dirender | tambah field pada `ApotikApiHelper.itemCari` (sumbernya sebagian sudah ada di profil item) |
| **IR-02** | Status batch: lokasi, saldo ditahan, karantina, recall, rusak | `apotik_item_batch` / `apotik_batch_monitor` hanya `kedaluwarsa`, `sisa` | UI menurunkan sendiri `expired`/`nearExpiry`/`depleted`; status lain tidak ditampilkan | tambah kolom status lot + endpoint ubah status |
| **IR-03** | Peringatan klinis: alergi, interaksi, duplikasi terapi, dosis | tidak ada | panel telaah tidak dibuat (menghindari kesan sudah diperiksa) | endpoint telaah + sumber data alergi pasien |
| **IR-04** | Racikan/compounding: formula, BOM, HPP, etiket | `apotik_resep_detail` hanya **membaca** flag `racikan` | mode Racikan & Produksi tampil TERKUNCI beserta alasannya; baris racikan resep tetap terkunci (perilaku existing) | endpoint buat/kerjakan racikan |
| **IR-05** | Double-check pemeriksa kedua, konseling | tidak ada | tidak dibuat tombol yang tidak menulis apa pun | endpoint verifikasi kedua (identitas akun sendiri) |
| **IR-06** | Buka/tutup shift & kas laci untuk apotik | `sesi_kas_*` milik POS umum; belum dipetakan ke apotik | kartu/menu shift tidak dibuat | putuskan: pakai ulang `sesi_kas_*` atau aksi apotik sendiri |
| **IR-07** | Daftar metode pembayaran apotik (tunai/QRIS/kartu/split) | `apotik_bayar` tanpa daftar metode | hanya alur bayar tunggal | kirim konfigurasi metode seperti `cara_bayar_list` POS |
| **IR-08** | Printer, laci kas, cetak ulang, bukti digital | tidak ada | struk belum dibangun (layar lama pun menulis "menyusul") | endpoint riwayat cetak + kontrak perangkat |
| **IR-09** | PO PBF, partial receiving, bukti suhu cold-chain | hanya `apotik_terima_barang` | form penerimaan sebatas field yang diterima server | endpoint PO + penerimaan sebagian + lampiran suhu |
| **IR-10** | SLA resep/racikan, transaksi pending, cold-chain di dashboard | tidak ada | kartu untuk metrik ini **tidak dibuat** (ada test yang menjaga) | endpoint metrik operasional |

## Keputusan yang diminta

Dua jalur, keduanya sah:

1. **Tanpa perubahan backend** — UI tetap seperti sekarang: jujur menampilkan
   apa yang ada, sisanya terkunci dengan alasan. Fase 4–7 tetap bisa berjalan
   untuk bagian yang didukung API.
2. **Dengan perubahan backend** — kerjakan IR-01, IR-02, IR-07 lebih dulu
   (dampak terbesar untuk kasir & keselamatan batch), memakai pola yang sama
   dengan penambahan API MitraInap. Setelah itu UI-nya tinggal menyalakan
   badge/kolom yang sudah disiapkan.
