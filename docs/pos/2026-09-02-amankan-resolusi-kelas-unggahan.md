# 73. Amankan Resolusi Kelas pada Unggahan Berkas

Tanggal: 2 September 2026  
Lanjutan: audit endpoint anonim (dok. 71 menyebut pola bypass `tanpaLogin`)  
Sifat: penguatan keamanan

## Konteks

Menindaklanjuti dok. 71, pola bypass `tanpaLogin` disisir ke endpoint lain.
`/DoUpload` memakainya secara **sah**: sejumlah unggahan memang perlu berjalan
tanpa login — bukti bayar PMB dan dokumen calon anggota diunggah sebelum yang
bersangkutan punya akun. Jadi akses anonimnya tidak dicabut.

## Temuan

Alur unggah mengubah **nama kelas entitas dari klien** menjadi objek dengan
`Class.forName(clazz)` lalu `newInstance()`, dan baru sesudahnya hasilnya di-cast
ke `FileFotoLain`. Dua langkah pertama berbahaya justru **sebelum** cast:

- `Class.forName(String)` **menginisialisasi** kelas yang disebut — menjalankan
  *static initializer*-nya;
- `newInstance()` menjalankan **konstruktor tanpa-argumen**.

Keduanya berjalan meski akhirnya cast gagal. Artinya nama kelas sembarang di
classpath yang dikirim pemanggil anonim dapat memicu efek samping inisialisasi
atau konstruksi — kelas dengan cast akhir yang gagal tetap "tersentuh" lebih
dulu.

## Perbaikan: dua lapis

**Lapis pertama — `DoUpload.resolveKelasLampiran`** (pada input klien):
memuat kelas **tanpa inisialisasi** (`Class.forName(name, false, loader)`), lalu
menolak yang bukan subkelas `FileFotoLain` **sebelum** apa pun berjalan.

**Lapis kedua — `FileFotoLain.createFileFotoLain`** (chokepoint tunggal untuk
kedua pemanggilnya): memeriksa `FileFotoLain.class.isAssignableFrom(clazz)`
sebelum `newInstance()`. Ini menjaga jalur mana pun, bukan hanya `/DoUpload`.

## Dampak: nol fungsi sah terputus

Setiap layar unggah — foto profil, dokumen prestasi/karya, lampiran PMB, foto
anggota koperasi — memang memakai subkelas `FileFotoLain`. Batasan ini justru
menegaskan kontrak yang sudah berlaku, hanya kini ditegakkan lebih awal dan aman.

## Bukti

`TesUploadKelas` — **8/8 lulus**:

- subkelas `FileFotoLain` yang sah (mis. `FotoAnggotaKoperasi`) diterima;
- kelas asing (non-`FileFotoLain`) ditolak **tanpa** static initializer maupun
  konstruktornya berjalan — diamati lewat *System property*, karena membaca
  static field justru akan memicu inisialisasi yang hendak diuji;
- nama kelas tak dikenal / kosong / null ditolak dengan galat terbaca;
- lapis kedua menolak kelas non-`FileFotoLain` sebelum `newInstance`.

## Yang belum, dan mengapa tidak ditebak

Jalur anonim `/DoUpload` masih membolehkan pemanggil menyebut `ref` (id record
tujuan) apa pun, sehingga secara teori sebuah berkas dapat dilampirkan ke record
milik orang lain. Membatasi hal ini menuntut pengetahuan tiap alur pra-akun yang
sah (calon mahasiswa melampirkan ke id biodata-nya sendiri, dsb.), dan salah
batas akan memutus pendaftaran PMB. Itu keputusan tersendiri yang butuh
pemetaan alur oleh pemilik — bukan tebakan yang aman disisipkan di sini.
