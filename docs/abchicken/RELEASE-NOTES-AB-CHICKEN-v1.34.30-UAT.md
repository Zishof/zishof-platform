# AB Chicken v1.34.30+193 — Prerelease UAT

Tag rilis: `abchicken-v1.34.30-uat-20260909`

## Status kandidat

Kandidat ini khusus varian `abchicken`. UAT transaksional end-to-end POS Desktop lulus seluruh gate
yang ditetapkan. APK Android berhasil dibangun dengan signature produksi. Installer Windows berhasil
dibangun, tetapi belum memiliki signature Authenticode publik sehingga kandidat dipublikasikan sebagai
**prerelease UAT**, bukan rilis produksi final.

## Isolasi tenant dan kanal pembaruan

- Domain: `abchiken.ebisnis.id`.
- Context path: `ebisnis`.
- Slug tenant: `abchiken`.
- Mode tenant: `TENANT_ONLY`.
- Schema bisnis: `abchiken`.
- Schema audit: `abchiken__audit`.
- Kode build: `abchicken`.
- Package ID Android: `id.zishof.ebisnis.abchicken`.
- Kanal pembaruan: prefix tag `abchicken-` dan kata kunci aset `abchicken`.
- Penyimpanan lokal memakai namespace `abchicken`.

Rilis ini tidak membawa installer atau APK eBisnis umum, Al-Bahjah, maupun Nahl. Tag prerelease khusus
AB Chicken tidak menggantikan rilis `latest` global dan updater tidak boleh mengambil aset lintas varian.

## Hasil UAT

| Gate | Hasil |
|---|---:|
| Kontrak aplikasi | 23/23 lulus |
| Isolasi updater | 7/7 lulus |
| Analisis statis berkas inti | 0 temuan |
| Data dan layar | 13/13 lulus |
| Proses end-to-end POS Desktop | 10/10 lulus |
| Laporan akuntansi | 6/6 lulus |

Data pilot memuat 170 pesanan outlet, 50 resep/BOM, masing-masing 170 PR, PO, BAST vendor, tagihan,
pembayaran, produksi, dan pengiriman, 80 klaim/backorder, serta 120 penjualan POS. Transaksi UAT
membentuk jurnal 307–312. Laporan menghasilkan 608 baris jurnal dan Buku Besar; Neraca seimbang dengan
selisih Rp0. Saldo awal kas/bank pilot belum dimuat sehingga saldo akhir Arus Kas dapat negatif walaupun
aritmetika dan keterlacakan jurnal lulus.

Alur yang dibuktikan adalah pesanan bahan baku outlet, alokasi stok gudang, PR/PO ketika stok kurang,
BAST vendor, terima tagihan, pembayaran vendor, produksi/packing, Delivery Order, status delivery,
BAST outlet, klaim/retur/backorder, produksi outlet, penjualan POS, posting jurnal, dan laporan keuangan.
Semua tindakan operasional dilakukan melalui POS Desktop; Web dibatasi untuk registrasi tenant,
konfigurasi administratif, pemantauan, dan audit.

## Paket Android

- Nama: `app-abchicken-release.apk`.
- Versi: `1.34.30`, build `193`.
- Minimum SDK: 23; target SDK: 35.
- Signature: produksi, `CN=eBisnis Inventory, O=eBisnis.id, C=ID`.
- SHA-256: `b4bf4838150812ab87e92d5ad4d345a6fafead1d75b2898fc67412d1af1c10fb`.

APK memakai kontrak fitur dan server yang sama dengan POS Desktop. Host build tidak memiliki perangkat
Android dan emulator x86_64 tidak dapat berjalan tanpa driver akselerasi virtualisasi. Oleh sebab itu,
APK tidak diklaim telah menjalani UAT UI end-to-end pada perangkat; lakukan smoke test instalasi, login,
sinkronisasi, satu transaksi, dan pembaruan pada perangkat Android sasaran sebelum promosi produksi.

## Paket Windows

- Nama: `AB-Chicken-Setup-1.34.30.exe`.
- Executable aplikasi: `abchicken.exe`.
- Identitas: `AB Chicken`, versi `1.34.30+193`.
- SHA-256: `bc6cd57983a366be229f32ce09bcb46e928db93223ba8e56cd3814eed6df0633`.

Installer hanya menjalankan executable AB Chicken dan tidak memasang executable varian lain. Artefak
belum ditandatangani Authenticode karena sertifikat publik organisasi tidak tersedia pada mesin build.
Gunakan hanya untuk UAT internal sampai proses signing Windows diselesaikan.

## Dokumentasi yang disertakan

- Manual dan bukti UAT E2E AB Chicken dalam DOCX dan PDF.
- Presentasi UAT E2E POS Desktop dan kesiapan Android.
- Panduan integrasi Rumah Pemotongan Ayam (RPA) dalam DOCX dan PDF.
- Presentasi rancangan sistem terpadu RPA, POS Desktop, dan POS Android.
- Bukti tangkapan layar asli dan beranotasi, CSV hasil gate, diagram beresolusi tinggi, serta checksum.

Dokumen RPA adalah baseline desain dan rencana UAT, bukan bukti bahwa proses RPA telah dieksekusi pada
server. Cakupannya meliputi PR Gudang Pusat, PO internal ke RPA, penerimaan ayam hidup dari peternak,
produksi pemotongan menjadi daging, transaksi internal/eksternal, Delivery Order, BAST Gudang Pusat,
posting akuntansi, dan siklus pengadaan berikutnya.

## Catatan keamanan dan migrasi

Kredensial UAT, konfigurasi database, keystore, dan password signing tidak disertakan. Importer menuju
produksi harus memvalidasi mapping tenant/domain/schema, menjalankan dry-run, menjaga referensi dokumen,
memverifikasi jumlah baris dan checksum, serta menyediakan rollback. Saldo awal dan hasil stock opname
wajib disetujui sebelum cutover produksi.

## Syarat promosi ke produksi

1. Lakukan smoke test APK pada perangkat Android fisik.
2. Tandatangani installer Windows dengan sertifikat Authenticode organisasi.
3. Muat dan setujui saldo awal kas/bank serta stok awal.
4. Verifikasi backup, dry-run importer, rekonsiliasi jurnal, dan prosedur rollback.
5. Jalankan UAT RPA tersendiri setelah modul dan data RPA tersedia; panduan saat ini baru baseline desain.
