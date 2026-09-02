# 75. Amankan Resolusi Kelas Entitas pada Endpoint `/Data`

Tanggal: 2 September 2026  
Lanjutan: dok. 73 (pengerasan serupa pada unggahan `/DoUpload`)  
Sifat: penguatan keamanan — menutup pola yang sama di jalur berbeda

## Konteks

Sesudah mengamankan resolusi kelas pada unggahan (dok. 73), audit dilanjutkan ke
endpoint SQL/data `/Data`. Selain jalur SQL mentah (sudah dijaga, dok. 70–72),
`/Data` punya aksi `load` dan `proses` yang mengambil **nama kelas entitas dari
klien** (field `class`) lalu memuatnya dengan `Class.forName(clazzName)` dan
memakainya sebagai `GeneralValueObject`.

## Temuan

`Class.forName(String)` **menginisialisasi** kelas yang disebut — menjalankan
*static initializer*-nya — meski akhirnya kelas itu bukan entitas yang sah. Aksi
`load` termasuk aksi baca yang dapat dipanggil tanpa login (jalur publik yang
sah, lihat dok. 71). Jadi pemanggil anonim dapat memicu inisialisasi kelas
sembarang di classpath hanya dengan menyebut namanya di field `class`.

Ini pola yang sama persis dengan temuan `/DoUpload` (dok. 73), di jalur berbeda.

## Perbaikan

Kedua titik (`load` dan `proses`) kini memakai `resolveKelasEntitas`:

1. memuat kelas **tanpa inisialisasi** — `Class.forName(name, false, loader)`;
2. memastikan turunan `GeneralValueObject` (basis semua entitas) lebih dulu;
3. menolak selain itu sebagai `ClassNotFoundException`.

Memakai `ClassNotFoundException` disengaja: penanganan nama kelas tak dikenal yang
sudah ada (`proses` membalas status `01`, bukan HTTP 500) tetap berlaku identik,
sehingga tidak ada perubahan perilaku yang terlihat pengguna — hanya kelas asing
kini ditolak **sebelum** static initializer-nya sempat berjalan.

## Dampak: nol fungsi sah terputus

Semua entitas yang di-`load`/`proses` memang turunan `GeneralValueObject` —
kodenya sendiri men-cast hasilnya ke tipe itu (`GeneralValueObject.ambilData`).
Batasan ini menegakkan kontrak yang sudah berlaku, hanya lebih awal dan aman.

## Bukti

`TesResolveEntitas` — **5/5 lulus**:

- entitas sah (`Produk`) diterima;
- kelas non-entitas ditolak sebagai `ClassNotFoundException` **tanpa** static
  initializer-nya berjalan (diamati lewat *System property*);
- nama kelas tak dikenal / kosong ditolak dengan perilaku yang sama seperti
  sebelumnya.

## Peta lengkap pengerasan resolusi kelas dari klien

| Jalur | Titik | Batas tipe | Dokumen |
| --- | --- | --- | --- |
| Unggah berkas | `DoUpload.resolveKelasLampiran` + `FileFotoLain.createFileFotoLain` | `FileFotoLain` | dok. 73 |
| Load/proses data | `DaftarDataService.resolveKelasEntitas` | `GeneralValueObject` | dok. 75 |

Keduanya memakai teknik yang sama: muat tanpa inisialisasi, batasi ke tipe dasar
yang sah, tolak sisanya sebelum kode kelas asing berjalan.
