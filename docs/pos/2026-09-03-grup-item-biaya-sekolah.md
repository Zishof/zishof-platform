# Grup Item Biaya Sekolah

Tanggal: 3 September 2026

## Tujuan

Menambahkan master `GrupItemBiayaSekolah` agar satu grup dapat memiliki banyak
`ItemBiayaSekolah`. Grup dipakai sebagai kepala kelompok pada daftar pembayaran
siswa dan sebagai metadata pengelompokan pada API tagihan sekolah.

Catatan penamaan: basis kode tidak memiliki kelas `JenisItemBiayaSekolah`.
Entitas item yang dipakai oleh tagihan adalah `ItemBiayaSekolah`, sehingga
relasi OneToMany dipasang ke kelas tersebut.

## Perubahan

- Entitas baru `sekolah.grup_item_biaya_sekolah`, diaudit Envers.
- Relasi dua arah:
  - `GrupItemBiayaSekolah.itemBiayaSekolahs`: `@OneToMany(mappedBy = "grupItemBiayaSekolah")`.
  - `ItemBiayaSekolah.grupItemBiayaSekolah`: `@ManyToOne`.
- Tab **Grup Item Biaya Sekolah** ditambahkan di halaman **Konfigurasi Akun Item**.
  Tab menyediakan cari, tambah, ubah, aktif/nonaktif, hapus, sekolah, dan jumlah
  item anggota.
- Form Item Biaya memiliki pilihan **Grup Item Biaya**. Pilihan dibatasi pada
  grup aktif di sekolah yang sama.
- `PembayaranOnline` mengurutkan item berdasarkan grup dan menampilkan kepala
  kelompok menggunakan komponen ZK `Group`. Item tanpa grup tetap memakai
  tampilan lama.
- API internal sekolah memakai helper tunggal `TagihanApiGrupUtil`:
  - `TagihanSiswa` di seluruh jalur respons tagihan/pembayaran.
  - `PsbCalonApi` pada rincian tagihan calon siswa.
- Kontrak lama dipertahankan. Field `grup_id`, `grup_kode`, `grup_nama`,
  dan `grup_ta` tetap tersedia, tetapi menunjuk grup item bila item sudah
  dikelompokkan. Bila belum ada grup, nilainya tetap berasal dari
  `PengaturanBiaya`.
- Field tambahan:
  - `grup_key`: kunci bebas benturan (`item:<id>` atau `pengaturan:<id>`).
  - `grup_item_biaya_id`: ID grup item (hanya bila ada).
  - `grup_item_biaya_aktif`: penanda penggunaan grup baru.

## Migrasi

Jalankan sebelum restart aplikasi:

```powershell
psql -d <database> -f C:\opt\AIS\ais\src\main\webapp\sql\migrasi_grup_item_biaya_sekolah_20260902.sql
```

Migrasi membuat tabel grup, menambah FK logis pada item biaya, indeks, dan kolom
audit pada tabel audit item biaya lama. Setelah itu restart Tomcat agar Hibernate
mendaftarkan entitas serta tabel audit entitas baru.

## UAT

1. Buka **Konfigurasi Akun Item**.
2. Buka tab **Grup Item Biaya Sekolah**, lalu buat satu grup.
3. Ubah dua atau lebih Item Biaya pada sekolah yang sama dan pilih grup tersebut.
4. Buka Pembayaran Online untuk siswa yang memiliki tagihan dari item-item itu.
5. Pastikan kepala grup berwarna tampil sekali dan seluruh item terkait berada di
   bawah kepala grup.
6. Panggil API tagihan siswa/PSB dan pastikan semua item anggota mengirim
   `grup_key` yang sama serta `grup_item_biaya_aktif=true`.
7. Pastikan item tanpa grup masih tampil dan responsnya tetap menggunakan
   pengelompokan `PengaturanBiaya`.

## Verifikasi teknis

- `mvn -DskipTests compile`: **BUILD SUCCESS**.
- XML parse: kedua ZUL yang diubah/ditambah dan dua `hibernate.cfg.xml`: **OK**.
- Hash SHA-256 seluruh pasangan `src/main/java` dan `src/main/src`: identik.
- Perubahan hanya menambah metadata pada API; pembayaran dan nominal tidak
  dimutasi oleh helper pengelompokan.

## Hotfix startup Hibernate (3 September 2026)

Saat SessionFactory dibangun, Hibernate sempat gagal dengan
`PropertyNotFoundException: Could not find a setter for property labelTampilan`.
Entity memakai property access karena `@Id` berada pada getter, sehingga getter
turunan `getLabelTampilan()` ikut dianggap sebagai properti persisten.

Getter tersebut kini diberi `@javax.persistence.Transient`. Tidak diperlukan
kolom database maupun setter baru karena `labelTampilan` hanya label hasil
gabungan kode dan nama. Verifikasi setelah perbaikan:

- `mvn -DskipTests compile`: **BUILD SUCCESS**.
- Bytecode `GrupItemBiayaSekolah.class` memuat runtime annotation
  `javax.persistence.Transient` pada `getLabelTampilan()`.
- Kedua source mirror memiliki hash SHA-256 yang identik.
