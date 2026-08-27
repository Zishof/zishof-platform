# Pencegahan file `.class` di source tree

## Aturan wajib

Semua proses kompilasi Java wajib menulis hasil `.class` ke direktori output
terpisah. File `.class` tidak boleh dibuat di direktori yang berisi `.java`,
terutama di:

- `C:\opt\AIS\ais\src\main\src`
- `C:\opt\AIS\ais\src\main\java`
- `C:\opt\AIS\ais\src\test`

Aturan ini berlaku untuk manusia, AI, IDE, skrip UAT, dan perintah terminal.
Tujuannya adalah mencegah ribuan artefak kompilasi muncul sebagai file
non-versioned di TortoiseSVN, menghindari commit biner tidak sengaja, dan menjaga
source tree tetap dapat diaudit.

## Cara kompilasi yang benar

Gunakan opsi `-d` pada `javac` dan arahkan ke direktori build sementara atau
direktori `target` yang berada di luar source tree.

Contoh PowerShell:

```powershell
$outputUat = 'C:\opt\AIS\ais\.codex-build\phase-uat'
New-Item -ItemType Directory -Force -Path $outputUat | Out-Null
javac -source 1.7 -target 1.7 -d $outputUat @daftar-source.txt
java -cp $outputUat ais.common.inventory.ContohUat
```

Untuk Maven/Ant/IDE, pastikan output mengarah ke `target/classes`,
`target/test-classes`, `build/classes`, atau direktori build khusus lain; jangan
pernah mengarah ke `src/main/src`, `src/main/java`, atau `src/test`.

## Perintah yang dilarang

Jangan menjalankan bentuk berikut dari direktori source karena `javac` akan
menaruh `.class` di sebelah `.java`:

```powershell
javac ais\common\Contoh.java
javac *.java
```

Jangan menggunakan `-d .` apabila working directory berada di dalam source
tree.

## Pemeriksaan wajib sebelum commit SVN/Git

Jalankan pemeriksaan berikut dari PowerShell:

```powershell
rg --files -g '*.class' C:\opt\AIS\ais\src\main\src C:\opt\AIS\ais\src\main\java C:\opt\AIS\ais\src\test
```

Hasil yang benar adalah kosong. Jika ada output, hentikan commit dan pastikan
file tersebut memang artefak kompilasi non-versioned sebelum dibersihkan.

Lanjutkan dengan:

```powershell
svn status C:\opt\AIS\ais\src\main\src
svn status C:\opt\AIS\ais\src\main\java
```

Tidak boleh ada `.class` berstatus `?`, `A`, atau `M`.

## Prosedur pembersihan aman

1. Pastikan target berada tepat di salah satu source root di atas.
2. Pastikan `.class` bukan file versioned dengan `svn list -R` atau
   `svn status`.
3. Hapus hanya file berakhiran `.class`; jangan menghapus direktori source,
   `.java`, resource, atau file pengguna.
4. Jalankan ulang pemeriksaan pra-commit.
5. Kompilasi ulang dengan `javac -d <output-di-luar-source>`.

## Ketentuan untuk sesi AI berikutnya

- Selalu buat direktori output kompilasi yang eksplisit dan berada di luar
  source tree.
- Jangan mengandalkan default output `javac`.
- Jangan memasukkan `.class` ke patch, SVN, Git, atau paket source.
- Setelah UAT, verifikasi ulang bahwa pencarian `.class` pada source root
  menghasilkan nol file.
- Catat lokasi output dan hasil pemeriksaan dalam dokumen handover fase terkait.

## Hasil audit 26 Agustus 2026

Pada audit awal ditemukan 3.848 file `.class` di bawah source tree. Saat
verifikasi berikutnya jumlahnya sudah nol, sehingga tidak dilakukan penghapusan
tambahan. Aturan ini dibuat untuk mencegah artefak tersebut muncul kembali.
