# 70. Permukaan SQL dari Klien dan Penjaganya

Tanggal: 2 September 2026  
Lanjutan: dok. 69 (catatan bahwa kueri panel dirakit di sisi klien)  
Sifat: temuan keamanan + penguatan; **keputusan menyalakan proteksi ada pada pemilik**

## Apa yang ditemukan

Endpoint `/Data` menerima **SQL yang dirakit di halaman (JavaScript)** lalu
menjalankannya. Pemetaan di seluruh aplikasi:

| Jalur | Jumlah halaman |
| --- | --- |
| `action=sql` (baca) | **71** |
| `action=update_data` (tulis) | **6** |

Contoh jalur tulis: persetujuan pengajuan perubahan harga produk, penyesuaian
stok, dan penandaan transaksi "terlayani" — semuanya berupa `UPDATE` yang
dikirim dari halaman.

`SqlSecurityGuard` sudah ada dan rancangannya matang: `action=sql` dibatasi
read-only satu statement, `action=update_data` menolak DDL, keduanya menolak
objek sistem basis data dan pola kolom sensitif. **Namun modenya bawaan `off`**
(`mode_proteksi_sql_endpoint`), sehingga pada instalasi yang belum menyetelnya
tidak satu pun aturan itu berlaku.

## Yang dikerjakan sekarang

`SqlSecurityGuardSelfTest` (tanpa JUnit, tanpa basis data) mengunci aturan
penolakannya — **14/14 lulus**:

- baca menolak `UPDATE`, `DELETE`, `INSERT`, `DROP`, statement bertumpuk (jalur
  klasik injeksi), objek sistem, serta SQL kosong/null;
- tulis menolak `DROP`, `ALTER`, `TRUNCATE`, `GRANT`, dan objek sistem.

Kalau aturan ini melemah tanpa sengaja di kemudian hari, menyalakan mode
`enforce` hanya akan memberi rasa aman yang palsu — itulah yang dijaga di sini.

## Dampak bila proteksi dinyalakan: terukur, bukan tebakan

Seluruh perintah tulis yang benar-benar dipakai halaman adalah **DML** (`UPDATE`),
dan tidak ada satu pun DDL. Artinya menaikkan mode ke `enforce` **tidak akan
mematahkan** layar yang ada. Urutan yang disarankan:

```sql
-- 1) Nyalakan pencatatan dulu (tidak memutus apa pun), amati log beberapa hari.
UPDATE public.konfigurasi SET nilai = 'log' WHERE nama = 'mode_proteksi_sql_endpoint';
-- (bila barisnya belum ada)
INSERT INTO public.konfigurasi (nama, nilai)
SELECT 'mode_proteksi_sql_endpoint', 'log'
 WHERE NOT EXISTS (SELECT 1 FROM public.konfigurasi WHERE nama = 'mode_proteksi_sql_endpoint');

-- 2) Bila log tidak menunjukkan penolakan atas kueri yang sah, naikkan:
UPDATE public.konfigurasi SET nilai = 'enforce' WHERE nama = 'mode_proteksi_sql_endpoint';
```

Log penolakan muncul di keluaran server dengan awalan `[SqlSecurityGuard]`.

## Batas yang harus disadari

**Mode `enforce` tidak menutup seluruh risiko.** Ia menolak DDL, statement
bertumpuk, dan objek sistem — tetapi `UPDATE` yang bentuknya sah tetap
diizinkan. Karena SQL-nya berasal dari halaman, siapa pun yang dapat memanggil
endpoint itu dapat mengubah muatannya: menyetujui pengajuan harganya sendiri,
menyentuh baris yang bukan miliknya, atau memperbarui tabel lain — semuanya
lewat `UPDATE` yang lolos penjaga.

Menutup celah itu menuntut perubahan rancangan: memindahkan operasi tulis ke
endpoint ber-aksi (server yang menyusun kuerinya, klien hanya mengirim maksud dan
parameter), sebagaimana yang sudah dilakukan jalur POS. Itu keputusan tersendiri
dengan dampak luas — 6 halaman untuk jalur tulis, 71 untuk jalur baca — dan
sengaja **tidak** dikerjakan sebagai sisipan di tengah perbaikan laporan.

## Catatan keandalan (dikoreksi)

Penjaga membaca konfigurasi (mode dan daftar token) melalui
`Common.getKonfigurasi`, yang **sudah di-cache** oleh `KonfigurasiManager`
(backing MapDB). Jadi di produksi pembacaan itu **tidak** menghasilkan
round-trip basis data pada tiap permintaan, dan **bukan** titik lambat — koreksi
atas catatan versi awal dokumen ini yang menyarankan menambah cache; cache itu
sudah ada, menambah lapis kedua hanya akan mubazir.

Penggantungan yang teramati terjadi **di luar container** (harness tanpa
Tomcat), tempat lapisan MapDB/Hibernate belum diinisialisasi — artefak
lingkungan uji, bukan perilaku produksi. (Berbeda dari dok. 67 §4: di sana
pemanggilan konfigurasi berjalan sangat awal pada urutan boot, saat cache memang
belum siap, sehingga jalur itu sengaja memakai SQL langsung. Penjaga SQL berjalan
per-permintaan ketika aplikasi sudah penuh berjalan, jadi tidak terkena kondisi
itu.)

Konsekuensi praktis: menyalakan `mode_proteksi_sql_endpoint` ke `enforce` aman
dari sisi kinerja — tidak ada beban baca konfigurasi tambahan yang perlu
dikhawatirkan.
