# 02 — Peta API Action (kontrak nyata server)

Sumber: `ais/action/servlet/api/ApotikApiDispatcher.java` + `ApotikApiHelper.java` (767 baris).
Seluruh aksi lewat `ApiClient.instance.aksi(nama, body)` → POST `/Data` (PosApi).
Sukses = `status == '00'` atau `'success'`.

## Aksi yang BENAR-BENAR tersedia (14)

| Aksi | Dipakai layar | Field respons utama |
|---|---|---|
| `apotik_item_cari` | Kasir, Persediaan | `id, kode, nama, kandungan, barcode, satuan, stok, hargaJual, lasa, terkendali` + `page` |
| `apotik_item_batch` | Kasir (FEFO), Persediaan | `id, kedaluwarsa, stok` per batch |
| `apotik_item_profil_simpan` | Persediaan | — |
| `apotik_bayar` | Kasir | `kode, total, idempoten` |
| `apotik_resep_list` | Kasir (sheet resep) | `id, kode, status, diagnosa, ditebus` |
| `apotik_resep_detail` | Kasir | baris obat + `racikan`, `jumlah`, `sisa`, `lasa`, `terkendali`, `hargaJual` |
| `apotik_terima_barang` | Persediaan (PBF) | — |
| `apotik_opname_simpan` | Persediaan | — |
| `apotik_retur_simpan` | Persediaan | — |
| `apotik_batch_monitor` | (belum dipakai UI) | monitor batch |
| `apotik_laporan_penjualan` | Laporan | — |
| `apotik_laporan_kedaluwarsa` | Laporan | — |
| `apotik_laporan_terkendali` | Laporan | — |
| `apotik_provision_demo` | Beranda (admin) | data contoh |

Ditambah aksi bersama: `konfigurasi` (aksesMenu, identitas), `revisi_daftar/detail/pulihkan`
(riwayat AuditTrails), `hak_akses_*`.

## GAP BACKEND — mockup meminta data yang server BELUM punya

Aturan dokumen §3: *"Mockup tidak boleh diimplementasikan secara buta"* dan §24:
*"membuat integration request untuk gap backend, bukan memalsukan success"*.

| Kebutuhan mockup | Status server | Rencana UI |
|---|---|---|
| Golongan obat (Rx/OTC/keras/narkotika), bentuk sediaan, kekuatan | **tidak ada** (hanya `lasa`, `terkendali`, `kandungan`) | tampilkan yang ada; sisanya baru dirender bila field muncul — TIDAK dikarang |
| `high_alert`, `cold_chain` | **tidak ada** | idem; integration request IR-01 |
| Batch: lokasi, saldo ditahan, karantina, recall, rusak | **tidak ada** (hanya `kedaluwarsa`, `stok`) | FEFO picker pakai data nyata; status lain disembunyikan sampai API siap (IR-02) |
| Peringatan klinis (alergi, interaksi, duplikasi, dosis) | **tidak ada** | panel telaah menampilkan "belum tersedia dari server" — bukan hasil palsu (IR-03) |
| Racikan/compounding (formula, BOM, etiket) | **read-only** di `apotik_resep_detail` | baris racikan tetap TERKUNCI dengan alasan jujur (perilaku existing dipertahankan) (IR-04) |
| Double-check pemeriksa kedua, konseling | **tidak ada** | tidak dibuat tombol yang tidak menulis apa pun (IR-05) |
| Buka/tutup shift, kas laci | **tidak ada** aksi apotik (`sesi_kas_*` milik POS umum) | dievaluasi memakai `sesi_kas_*` bila kontraknya cocok (IR-06) |
| Metode pembayaran (QRIS/kartu/split) | `apotik_bayar` tanpa daftar metode | hanya tampilkan metode yang dikirim server (IR-07) |
| Printer, laci kas, cetak ulang | **tidak ada** | panel perangkat menampilkan status lokal saja (IR-08) |
| PO PBF & partial receiving, bukti suhu | hanya `apotik_terima_barang` | form penerimaan sesuai field yang diterima server (IR-09) |
| SLA resep/racikan | **tidak ada** | dashboard memakai metrik yang bisa dihitung dari data nyata (IR-10) |

**Kesimpulan:** ±60% konten visual mockup dapat diwujudkan sekarang; sisanya
menunggu backend. Layar dibangun agar field baru cukup ditambahkan tanpa rombak UI.
