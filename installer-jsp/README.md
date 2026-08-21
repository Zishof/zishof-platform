# Pemasang AIS versi JSP untuk Linux

Paket pemasang mandiri untuk aplikasi AIS (versi JSP) di server Linux. Tomcat
dan JVM sudah termuat di dalam paket, jadi server target tidak perlu memasang
Java lebih dulu — dan Java lain yang sudah ada di server itu tidak terganggu,
karena keduanya dipasang di dalam direktori aplikasi, bukan ke sistem.

## Untuk operator: memasang di server

```bash
tar -xzf ais-jsp-installer-<versi>-linux-x64.tar.gz
cd ais-jsp-installer-<versi>
sudo ./pasang.sh
```

Pemasang akan menanyakan seluruh isian lebih dulu, menampilkan ringkasannya,
dan baru menulis berkas setelah Anda menyetujuinya:

| Isian | Bawaan | Keterangan |
|---|---|---|
| Direktori pemasangan | `/opt/ais` | Semua isi paket masuk ke sini |
| Nama konteks web | `ais` | Alamat menjadi `/ais` |
| Port HTTP | `8080` | Port yang didengarkan Tomcat |
| Memori maksimum JVM | `2048m` | Sesuaikan dengan RAM server |
| Alamat server database | — | Host PostgreSQL |
| Port database | `5432` | |
| Nama database | `ais` | |
| Username database | `postgres` | |
| Password database | — | Diketik tersembunyi, dikonfirmasi dua kali |
| Database laporan | sama | Koneksi terpisah untuk kueri besar |

Sebelum melanjutkan, pemasang menguji apakah server database dapat dihubungi
dari mesin itu. Bila tidak, Anda diberi tahu dan boleh memilih untuk tetap
lanjut — pemasangannya sendiri tetap sah, aplikasinya saja yang belum berfungsi
sampai jaringan atau `pg_hba.conf` diperbaiki.

Setelah selesai:

```
Alamat aplikasi  : http://<alamat-server>:8080/ais
Endpoint API POS : http://<alamat-server>:8080/ais/Api_eBisnis
Log Tomcat       : /opt/ais/tomcat/logs/catalina.out
Layanan          : systemctl status ais
```

### Pemasangan tanpa tanya jawab

Untuk otomasi, isian diambil dari variabel lingkungan:

```bash
sudo AIS_DB_HOST=10.0.0.5 AIS_DB_NAME=ais AIS_DB_USER=ais_app \
     AIS_DB_PASSWORD='...' ./pasang.sh --tanpa-tanya
```

Jangan menaruh kata sandi langsung di baris perintah pada mesin bersama —
riwayat shell dan daftar proses dapat terbaca pengguna lain. Lebih baik pakai
berkas lingkungan yang izinnya dibatasi.

### Memasang ulang / memperbarui

Menjalankan `pasang.sh` di direktori yang sama akan menghentikan layanan,
mengganti aplikasi dan JVM, lalu menjalankannya kembali. **Konfigurasi Tomcat
dan `setenv.sh` dipertahankan**, sehingga isian database tidak perlu diketik
ulang dan penyetelan operator tidak hilang.

## Di mana kredensial database disimpan

Kredensial **tidak pernah** ikut di dalam paket pemasang. Nilainya ditanyakan
saat pemasangan lalu ditulis hanya ke mesin target, pada:

```
/opt/ais/tomcat/bin/setenv.sh      (izin 600, milik pengguna layanan)
```

Aplikasi membacanya sebagai properti JVM (`-Durl`, `-Dusername`, `-Dpassword`,
dan padanan `_streaming`), yang disubstitusi Hibernate ke `hibernate.cfg.xml`.
Berkas itu **tidak boleh** disalin, dibagikan, atau dimasukkan ke sistem kendali
versi.

## Catatan keamanan

Pemasang menjalankan Tomcat sebagai pengguna sistem tanpa shell (`ais`), bukan
sebagai root, dan menghapus aplikasi bawaan Tomcat (`manager`, `host-manager`,
`examples`, `docs`) yang tidak dipakai.

Yang **belum** ditangani pemasang dan tetap tanggung jawab operator: **HTTPS**.
Pasang Nginx atau Apache sebagai reverse proxy dengan sertifikat di depan
Tomcat. Aplikasi POS mengirim kata sandi dan token pada setiap permintaan, jadi
menjalankannya di HTTP polos hanya layak untuk jaringan internal tertutup.

Perlu diketahui juga: bila server dikonfigurasi mengalihkan HTTP ke HTTPS
secara permanen, POS versi 1.33.71 ke atas sudah mengikuti pengalihan itu
dengan benar. Versi sebelumnya akan gagal pada seluruh aksi, termasuk login.

---

## Untuk pengembang: membangun paket

```bash
cd installer-jsp
VERSI=1.0.0 AIS_ROOT=/c/opt/AIS/ais ./bangun_installer.sh
```

Skrip akan:

1. Mengompilasi `src/main/src` AIS menjadi `ais.war` lewat `ant/build.xml`.
   Tata letak lama pada `build.xml` (`web/`, `src/`) ditimpa dari baris perintah
   ke tata letak sekarang (`src/main/webapp`, `src/main/src`).
2. Mengunduh Apache Tomcat 9 dan Temurin JRE 8 (linux x64), lalu menyimpannya di
   `unduhan/` agar build berikutnya tidak mengunduh ulang.
3. Merakit semuanya menjadi satu `tar.gz` beserta berkas `.sha256`.

Hasilnya di `build/ais-jsp-installer-<versi>-linux-x64.tar.gz`.

Versi Tomcat dan JRE **sengaja dipatok**: aplikasi dikompilasi dengan gaya Java
6 dan dijalankan di Java 8 (Tomcat 9 mensyaratkan minimal 8). Menaikkannya tanpa
pengujian menyeluruh berisiko memutus pustaka lama yang dipakai aplikasi. Untuk
mengubahnya, setel `TOMCAT_VERSI`, `JRE_VERSI`, dan `JRE_TAG`.

Unduhan dan hasil build tidak masuk repositori — lihat `.gitignore` di folder
ini. Yang di-commit hanya skripnya; berkas binernya dilampirkan ke rilis GitHub.
