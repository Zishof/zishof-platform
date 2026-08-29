# 56. Ringkasan Program UOM–Packaging–Manufaktur (Fase 0–E) — untuk Pemilik Sistem

Tanggal: 29 Agustus 2026  
Sifat: ringkasan eksekutif — rincian teknis tiap fase ada di dok. 50–55  
Rujukan: dok. 48 (peta gap vs PDF klien), dok. 49 (koreksi + rencana rinci)

## Latar

Tiga dokumen kebutuhan klien (PDF "UOM n Sales", "POS menggunakan fitur
packaging", "proses sales dan manufaktur") dipetakan ke dok. 48/49 menjadi
enam fase. **Seluruh enam fase kini terlaksana, teruji di DB UAT, dan sudah
masuk repositori** (SVN r78513–r78537; Git s.d. f791664). Total bukti:
**94 uji server hijau** (19+13+9+19+17+17) + **suite Flutter 511/511**.

## Apa yang kini bisa dilakukan sistem — per fase

### Fase 0 — Dokumen produksi benar-benar menggerakkan stok (dok. 50)
Sebelumnya dokumen ISSUE/RETURN/OUTPUT/WASTE yang diposting TIDAK mengubah
stok — angka stok berbohong. Kini tiap dokumen menggerakkan stok saat
POSTED lewat ledger khusus (`mutasi_stok_produksi`), REVERSED memulihkan
lewat kontra-baris (jejak tidak pernah dihapus), dan memproses dua kali
tidak menggandakan. Kegagalan mencatat stok MEMBATALKAN transisi status —
dokumen tidak bisa "mengaku" diposting. *Keputusan terkunci: stok bergerak
per dokumen POSTED (bukan menunggu WO selesai); dokumen lama pra-Fase 0
dibiarkan tanpa efek stok.* Bukti: 19/19.

### Fase A — Harga grosir + kemasan penuh di kasir (dok. 51)
Harga grosir ber-ambang kuantitas (contoh: ≥50 kg harga turun), per toko
atau global, ber-jendela waktu, SATU mesin untuk semua kanal (kasir
Desktop/Android dan web). Urutan terkunci: grosir menetapkan harga satuan
DULU, diskon memotong SESUDAHNYA. Qty digabung lintas baris. Kasir: pemilih
kemasan sekali-ketuk (tekan-lama produk), label kemasan yang jujur
("2 x Karung 50kg" hanya bila memang kelipatan), editor aturan harga di
form Produk. Bukti: 13/13 + uji kontrak Flutter.

### Fase B — Satuan jual per baris (dok. 52)
Kasir menjual "2 Karung 50" — SERVER yang menghitung ulang jumlah dasar
(2×50=100 kg) dan menimpa angka kiriman klien; klien hanya pratinjau.
Ambang grosir/diskon menilai qty dasar yang benar. Snapshot satuan
(satuan, qty input, faktor) tersimpan di baris untuk audit dan struk.
Bukti: 9/9 — termasuk klien yang sengaja mengirim angka salah (999)
tersimpan benar (100).

### Fase C — Reordering lengkap: min-max + rute pemenuhan (dok. 53)
Ambang stok gudang kini punya TARGET MAKSIMUM (kebijakan min-max): saran
qty = target − stok, dibulatkan NAIK ke satuan pembelian (butuh 70 kg,
karung 50 → 2 karung). Produk punya RUTE pemenuhan: BELI (pengajuan
pembelian otomatis, perilaku lama) atau PRODUKSI (draf Work Order
otomatis, merujuk BOM aktif). **Temuan penting: bug laten diperbaiki —
kueri notifikasi lama salah kolom dan diam-diam membatalkan transaksi,
sehingga pengajuan otomatis TIDAK PERNAH tersimpan sejak fitur ambang
lahir.** Kini pengajuan otomatis benar-benar berfungsi. Bukti: 19/19.

### Fase D — Reservasi komponen, kekurangan, UNBUILD (dok. 54)
Rilis Work Order mengunci kebutuhan komponen BOM (reservasi); pengeluaran
bahan ber-referensi WO memakan reservasi; batal/selesai melepasnya.
Kekurangan komponen saat rilis otomatis menjadi pengajuan pembelian
ber-rujukan WO (lewat Gudang Pemasok toko). Dokumen UNBUILD membongkar
barang jadi kembali menjadi komponen (kebalikan produksi) memakai ledger
yang sama. *Reservasi saat ini INFORMASI SAJA bagi kasir — menunggu
keputusan Anda (lihat bawah).* Bukti: 17/17.

### Fase E — MTO dan QC (dok. 55)
MTO: produk ber-rute MTO_BELI/MTO_PRODUKSI otomatis memicu pengajuan
pembelian / draf WO saat Sales Order lapangan DIKONFIRMASI — barang
dipesan dulu, dipenuhi kemudian. QC: produk bertanda "perlu QC" membuat
tiap hasil produksi yang diposting otomatis menerbitkan dokumen Quality
Alert dan MENGKARANTINA batch-nya sampai didisposisi: REWORK (produksi
ulang), UNBUILD (bongkar), SCRAP (musnahkan lewat WASTE), atau RELEASE
(lolos). Bukti: 17/17.

## Prinsip yang dijaga di semua fase

- **Server berwenang atas uang dan stok** — klien hanya pratinjau.
- **Skema selalu aditif** (kolom/tabel nullable via Hibernate, dibuat
  otomatis saat boot) — data dan perilaku lama tidak berubah makna.
- **Satu mesin per urusan** dipakai lintas kanal — tidak ada salinan logika
  (mesin harga, konversi UOM, draf WO, pencatat batch: masing-masing satu).
- **Ledger tidak pernah dihapus** — koreksi lewat gerakan lawan; idempoten
  di setiap titik tulis.

## KEPUTUSAN YANG DITUNGGU DARI ANDA

Empat hal sudah disiapkan titik pasangnya, tinggal keputusan bisnis:

1. **Harga tetap per kemasan (Metode 2 PDF)** — mis. "Rp 4.500.000/karung"
   yang tidak persis 50 × harga/kg. Mesin ambang (Metode 1) sudah jalan;
   Metode 2 tinggal satu kolom bila diminta. *(dok. 48 §6 no. 1)*
2. **Kelipatan wajib kemasan** — pembeli grosir wajib kelipatan karung,
   atau bebas ("53 kg nanggung")? Menentukan validasi baris kasir.
   *(§6 no. 2)*
3. **Reservasi menolak penjualan kasir?** — stok yang dikunci WO: sekadar
   informasi (kondisi sekarang) atau mengurangi stok yang boleh dijual
   kasir (bisa menolak transaksi)? Titik pasangnya sudah dicatat di dok.
   54. *(§6 no. 4)*
4. **Pemetaan akun jurnal** untuk dokumen produksi/waste/disposisi QC di
   dasbor Draft Jurnal — butuh rekonsiliasi akunting Anda. *(dok. 48 §7)*

Satu keputusan lain sudah diambil mengikuti analisis dokumen sendiri:
cakupan MTO = Sales Order lapangan SAJA (Pesanan POS adalah keranjang
tertahan; memaksakan MTO mengubah maknanya — §6 no. 3). Bisa ditinjau
ulang bila Anda berpendapat lain.

## Yang perlu disiapkan operasional (di luar kode)

- **Deploy ke produksi** — kolom/tabel baru dibuat otomatis saat boot
  aplikasi; tidak ada DDL manual.
- **Gudang Pemasok per toko** — prasyarat pengajuan otomatis (kekurangan
  WO dan MTO_BELI). Tanpa itu sistem tetap jujur melaporkan kebutuhan,
  hanya tidak bisa membuatkan pengajuannya.
- **Master UOM ber-kategori benar** (BERAT/VOLUME/UNIT dst.) — penegak
  kesekategorian menolak konversi lintas kategori di semua titik.
- **Hak akses menu baru** — Unbuild/Bongkar dan Quality Alert (QC)
  mengikuti gerbang menu produksi yang sudah ada.

## Jejak

Dokumen rinci: dok. 50 (Fase 0), 51 (A), 52 (B), 53 (C), 54 (D), 55 (E).
SVN: r78513–r78537. Git (repo zishof-platform): rangkaian commit
"Fase A/B/C/D/E" s.d. f791664, semua di `main` dan sudah di-push.
