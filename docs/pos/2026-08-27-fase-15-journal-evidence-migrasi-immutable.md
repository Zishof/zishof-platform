# Fase 15 — Journal Evidence Migrasi Immutable

## Hasil fase

Fase 15 menyediakan fondasi penyimpanan evidence migrasi yang append-only, dapat diverifikasi, idempoten, dan kompatibel Java 1.7. Fondasi ini mengikat keputusan rollout Fase 13 dan keputusan dekomisioning Fase 14 pada rekaman audit yang dapat diperiksa integritasnya sebelum gerbang berikutnya dibuka.

Fase ini **tidak** mengaktifkan writer produksi, mengubah feature flag, menjalankan migrasi database, menghentikan legacy, atau menghapus artefak. Aktivasi produksi tetap memerlukan evidence nyata, rehearsal rollback/restore, dan sign-off sesuai registry Fase 13–14.

## Implementasi

Source canonical:

- `C:\opt\AIS\ais\src\main\src\ais\common\EbisnisMigrationEvidenceJournal.java`
- `C:\opt\AIS\ais\src\main\src\ais\common\test\EbisnisMigrationEvidenceJournalSelfTest.java`

Mirror source:

- `C:\opt\AIS\ais\src\main\java\ais\common\EbisnisMigrationEvidenceJournal.java`
- `C:\opt\AIS\ais\src\main\java\ais\common\test\EbisnisMigrationEvidenceJournalSelfTest.java`

API utama:

- `append(File, Request)` menambahkan satu event secara atomik dan tersinkron ke media penyimpanan;
- `read(File)` membaca snapshot immutable seluruh entry yang sudah tervalidasi;
- `verify(File)` memeriksa format, urutan, payload hash, previous hash, dan record hash seluruh journal.

Tidak tersedia API update atau delete. Koreksi harus dicatat sebagai event baru dengan identitas, alasan, aktor, referensi, dan payload evidence yang baru.

## Kontrak record

Setiap entry menyimpan:

| Field | Fungsi |
|---|---|
| `formatVersion` | Versi format serialisasi journal |
| `sequence` | Nomor urut monoton dalam satu file |
| `occurredAt` | Waktu event menurut pemanggil |
| `eventId` | Kunci idempotensi event |
| `workflow` | Alur sumber, misalnya rollout atau dekomisioning |
| `scopeIdentity` | Identitas tenant/lokasi/writer/canary yang dinilai |
| `stage` | Tahap registry ketika evidence dibuat |
| `decisionCode` | Kode keputusan atau hasil gerbang |
| `actor` | Pelaku/owner yang mencatat evidence |
| `reference` | Referensi tiket, laporan, snapshot, atau sign-off |
| `evidencePayload` | Payload evidence yang sudah disanitasi |
| `payloadHash` | SHA-256 payload evidence |
| `previousHash` | Hash entry sebelumnya |
| `recordHash` | SHA-256 atas seluruh isi record dan rantai sebelumnya |

Nilai teks diserialisasi sebagai UTF-8 lalu diubah menjadi heksadesimal. Dengan demikian newline, tab, karakter non-ASCII, dan delimiter dari data tidak dapat merusak struktur satu-record-per-line.

## Integritas, konkurensi, dan durabilitas

- Seluruh file diverifikasi sebelum append baru diterima.
- Record pertama menggunakan akar rantai yang deterministik; setiap record berikutnya mengikat `previousHash` ke `recordHash` sebelumnya.
- Perubahan isi, penghapusan/penyisipan baris, perubahan urutan, dan truncation terdeteksi oleh `verify`.
- Append menggunakan `RandomAccessFile`, `FileChannel`, dan exclusive `FileLock` sehingga dua proses/thread tidak menulis bagian record yang saling bertumpuk.
- `FileDescriptor.sync()` dipanggil sebelum operasi dianggap selesai.
- File yang belum ada diperlakukan sebagai journal kosong yang valid.
- Journal yang korup tidak boleh menerima append baru sampai dipulihkan dari salinan terpercaya atau direkonsiliasi melalui prosedur insiden.

## Idempotensi dan konflik

- Pengulangan `eventId` dengan request yang identik mengembalikan entry yang sudah ada tanpa menambah baris.
- Pengulangan `eventId` dengan isi berbeda ditolak sebagai konflik.
- `eventId` wajib stabil dari sumber proses; jangan membangkitkan ID baru pada setiap retry untuk keputusan yang sama.
- Koreksi bisnis bukan retry: gunakan event baru dan cantumkan referensi event yang dikoreksi.

## Batas keamanan

Hash chain memberikan **integritas**, bukan kerahasiaan atau non-repudiation kriptografis. Karena itu:

- jangan menyimpan password, token, PIN, secret, data kartu, atau data pribadi mentah pada `evidencePayload`;
- simpan ringkasan, ID referensi, jumlah, checksum artefak, dan lokasi evidence yang sudah dikontrol akses;
- lindungi file dengan ACL sistem operasi, backup immutable/WORM, retensi, audit akses, dan salinan di lokasi berbeda;
- untuk produksi, adapter repository berikutnya harus menggunakan penyimpanan durable terpusat dan identitas aktor yang terautentikasi.

## Hubungan dengan Fase 13 dan Fase 14

Journal tidak menggantikan registry keputusan. Registry tetap menentukan apakah transisi legal; journal menyimpan bukti bahwa evaluasi dan keputusan tersebut benar-benar terjadi.

Urutan integrasi yang diwajibkan:

1. evaluasi transisi pada registry Fase 13 atau Fase 14;
2. kumpulkan evidence dan sign-off yang diwajibkan;
3. tulis event journal dengan scope identity dan stage yang sama;
4. verifikasi journal;
5. baru izinkan orkestrator meneruskan langkah berikutnya;
6. jika penulisan/verifikasi journal gagal, transisi harus berhenti aman.

## Prosedur operasional

1. Gunakan satu journal per batas keamanan/retensi yang jelas, bukan satu file global tanpa pemilik.
2. Pastikan direktori journal bukan direktori source atau output build.
3. Sanitasi payload sebelum membentuk `Request`.
4. Gunakan `eventId` stabil dan `scopeIdentity` canonical dari registry.
5. Panggil `append`, lalu simpan `sequence` dan `recordHash` pada audit proses.
6. Jalankan `verify` sebelum dan sesudah pemindahan/backup file.
7. Jika verifikasi gagal, hentikan rollout/dekomisioning, isolasi file, pulihkan salinan terpercaya, dan catat insiden; jangan menimpa record lama.

## UAT

Kompilasi menggunakan:

```text
javac -source 1.7 -target 1.7 -d C:\opt\AIS\ais\.codex-build\phase15 ...
```

Hasil:

- `EbisnisMigrationEvidenceJournalSelfTest`: **LULUS, 25 pemeriksaan**;
- regresi `EbisnisMigrationRolloutRegistrySelfTest`: **LULUS, 57 pemeriksaan**;
- regresi `EbisnisLegacyDecommissionRegistrySelfTest`: **LULUS, 43 pemeriksaan**;
- source canonical dan mirror: **identik SHA-256**;
- tidak ada `.class` di direktori paket Java canonical atau mirror;
- output kompilasi hanya berada di `C:\opt\AIS\ais\.codex-build`.

UAT mencakup append/read, urutan dan hash chain, payload Unicode/multiline, idempotensi, konflik event ID, immutable list, tampering, truncation, penolakan append pada journal korup, dan append serentak.

## Gerbang sebelum produksi

- Tentukan repository durable (database audit append-only atau object storage WORM) dan kebijakan retensinya.
- Tambahkan autentikasi aktor serta otorisasi penulisan evidence.
- Integrasikan orkestrator Fase 13–14 dengan pola fail-closed.
- Lakukan backup/restore drill dan verifikasi hash setelah restore.
- Tambahkan monitoring untuk verification failure, duplicate conflict, write failure, dan pertumbuhan storage.
- Jalankan pilot staging dengan evidence nyata dan review Security/DBA/Owner.

## Fase berikutnya

Fase 16 sebaiknya membuat adapter repository durable dan orkestrator evidence gate yang menghubungkan registry Fase 13–14 ke journal secara fail-closed, disertai failure injection, restore/replay drill, monitoring, dan UAT konkurensi pada staging. Fondasi file journal pada fase ini tetap berguna sebagai reference implementation dan fallback lokal terkontrol, bukan sebagai satu-satunya penyimpanan produksi.
