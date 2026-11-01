# Instruksi wajib untuk seluruh sesi AI

## Local-first adalah syarat mutlak

Setiap perubahan pada aplikasi POS/eBisnis, seluruh variannya, dan seluruh modul
baru maupun lama **WAJIB mempertahankan arsitektur local-first**. Aturan ini
merupakan gerbang rilis, bukan pilihan implementasi.

1. Layar daftar membaca cache/SQLite lokal terlebih dahulu dan melakukan
   penyegaran server di latar belakang. Data besar wajib dibaca per halaman;
   jangan membentuk seluruh snapshot pada thread UI.
2. Setiap Create, Update, dan Delete yang aman ditunda wajib melakukan transaksi
   lokal dan mencatat outbox **sebelum** mencoba jaringan. Kegagalan koneksi atau
   gangguan server tidak boleh membatalkan perubahan lokal dan tidak boleh
   menahan pengguna di form.
3. Outbox wajib idempoten, dapat dilanjutkan setelah aplikasi/perangkat dimulai
   ulang, mencoba ulang otomatis, serta menampilkan status Pending/Gagal dan
   petunjuk penyelesaian yang jelas.
4. Foto/lampiran wajib disimpan dan dapat dipratinjau dari berkas lokal, lalu
   diunggah melalui antrean. Form edit tidak boleh hanya bergantung pada URL
   server.
5. Transaksi POS/inventori memakai jurnal/outbox transaksi khusus. Jangan
   memasukkan ID sementara negatif ke payload transaksi yang membutuhkan ID
   server.
6. Aksi yang secara integritas **tidak aman diantrikan** tetap online-only:
   autentikasi/PIN/biometrik, validasi saldo, approval, posting/closing jurnal,
   pembatalan/koreksi irreversible, dan impor massal. UI wajib menjelaskan bahwa
   koneksi/konfirmasi server diperlukan; jangan menampilkan sukses lokal palsu.
7. Dilarang menambah pemanggilan mutasi langsung `ApiClient.aksi(...)` tanpa
   klasifikasi tertulis. Mutasi queueable harus memakai helper local-first;
   pengecualian online-only harus disertai alasan integritas pada komentar kode
   atau register audit.
8. Perubahan belum boleh dirilis sebelum tersedia tes kontrak yang membuktikan:
   lokal disimpan lebih dahulu, retry aman/idempoten, cache tetap terbaca saat
   server gagal, dan pengecualian online-only gagal dengan pesan edukatif.

Rujukan kanonis: `docs/pos/ATURAN-WAJIB-LOCAL-FIRST.md`.

## Pencegahan Overflow Lebar Frame / Viewport (Responsive Width Containment)

Seluruh layar aplikasi POS Desktop & Mobile (Windows, Android, Web) **WAJIB** menerapkan pencegahan overflow horizontal agar tidak pernah ada elemen yang melewati batas kanan frame/viewport (`RenderFlex overflowed by ... pixels on the right`):

1. **Dilarang keras** meletakkan `Text`, badge, atau informasi dinamis langsung di dalam `Row` tanpa pembungkus `Expanded` atau `Flexible`.
2. Untuk deretan filter, chip status, atau tombol aksi (> 2 tombol), **wajib** menggunakan `Wrap(spacing: 8, runSpacing: 8, ...)` atau `LayoutBuilder` responsif, bukan `Row` kaku.
3. Setiap kartu ringkasan/KPI menggunakan `LayoutBuilder` atau `Wrap` dengan batas `constraints.maxWidth` sehingga aman di layar kasir sempit maupun monitor widescreen.
4. Cantumkan dokumentasi Dartdoc pada widget/layar baru yang menjelaskan penerapan pembatasan lebar frame ini.


