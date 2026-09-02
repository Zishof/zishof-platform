# 81. Idempotensi Kulakan — Cegah Faktur & Stok Ganda

Tanggal: 3 September 2026  
Modul: Pengadaan (Kulakan / harga beli)  
Sifat: perbaikan bug integritas stok (kiriman ulang)

## Bug

`kulakan_faktur_simpan` menambah stok: membuat `PengadaanFaktur`, mencatat
penerimaan batch, dan me-recompute stok per baris. Namun aksi ini **tidak**
terdaftar di `MutasiIdempotenEBisnisUtil.AKSI_MASTER_ANTREAN`, sehingga lapisan
idempotensi PosApi (me-replay respons tersimpan berdasar `client_mutation_id`)
**melewatinya**.

Akibatnya kiriman ulang antrean membuat **faktur dan stok GANDA**:

- **lost-ack**: server sudah commit, tetapi responsnya hilang di jaringan →
  klien menganggap gagal → mengirim ulang;
- **retry offline**: antrean mengirim ulang saat koneksi pulih.

Ini kelas yang sama dengan race BAST (dok. 79), tetapi pada jalur Kulakan manual.

## Mengapa cukup mendaftarkan aksinya

Layar Kulakan memakai `prosesSimpanMaster` → `MasterOffline.antreLokal`, yang
menetapkan `client_mutation_id` **stabil per submit** dan menyimpannya di antrean.
Kirim pertama (`kirimSatuAntrean`) dan seluruh retry memakai **id yang sama**.
Maka begitu aksi masuk `AKSI_MASTER_ANTREAN`, server:

1. sebelum eksekusi, mencari respons tersimpan untuk (pengguna, aksi,
   client_mutation_id) — bila ada, kembalikan itu tanpa mengeksekusi lagi;
2. sesudah eksekusi sukses pertama, menyimpan responsnya untuk replay.

Sehingga resend id yang sama tidak pernah membuat faktur kedua.

## Aman & terbatas

- **Fail-open**: tanpa `client_mutation_id`, perilaku tak berubah.
- Logika `kulakanFakturSimpan` tidak diubah.
- **Tidak** menyentuh jalur sinkron dari BAST: itu memanggil
  `KantinHelper.kulakanFakturSimpan` langsung (bukan lewat dispatch PosApi), dan
  sudah dijaga advisory lock per-BAST (dok. 79).

## Bukti

`aksiMasterAntrean("kulakan_faktur_simpan")` = **true** (juga case-insensitive);
`"bayar"` = false; `null` = false. Kompilasi bersih (javac 1.7).

## Catatan

Berlaku setelah build server dipasang dan Tomcat di-restart. Untuk perlindungan
penuh, jalur Kulakan yang lain (bila ada yang memakai `simpanAtauAntre`
kompatibilitas, yang menyisipkan `client_mutation_id` hanya saat gagal) sebaiknya
diarahkan ke `prosesSimpanMaster` — layar Kulakan saat ini sudah memakainya.
