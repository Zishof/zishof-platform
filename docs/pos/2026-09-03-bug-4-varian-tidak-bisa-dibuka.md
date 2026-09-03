# Bug: empat varian desktop tidak bisa dibuka sama sekali (3 September 2026)

**Ringkas.** `bootstrap()` — jalur boot bersama varian **apotik, emedik,
inventory_sales, dan mitrainap** — tidak memanggil `PrefsGuard`. Satu berkas
`shared_preferences.json` yang korup membuat aplikasi menggantung sebelum
`runApp`, sehingga jendelanya dibuat tetapi **tidak pernah dirender**: bagi
pengguna, aplikasi tampak tidak bisa dibuka sama sekali, tanpa pesan apa pun.
Diperbaiki di `334752b` (satu baris) beserta test kontrak.

---

## Gejala

Proses hidup (200–300 MB RAM, tidak crash), jendela ADA dengan judul yang
benar, tetapi `IsWindowVisible == false` selamanya. Tidak ada dialog, tidak ada
entri `error_log`, tidak ada apa pun di konsol.

Penyebab gejala senyap ini ada di sisi Flutter: runner Windows hanya memanggil
`ShowWindow` **setelah frame pertama** (`SetNextFrameCallback` pada template
runner). Jadi apa pun yang menggantung sebelum `runApp` menghasilkan jendela
tak terlihat, bukan pesan kesalahan.

## Cara menemukannya (bisa dipakai ulang)

1. **Ukur, jangan menebak.** Enumerasi jendela per PID lewat `EnumWindows`
   (Win32) dan baca `IsWindowVisible`; `Process.MainWindowHandle` sering 0 dan
   menyesatkan. Kontrol wajib: enumerasi juga jendela aplikasi lain di sesi
   yang sama — kalau Explorer/browser terbaca `visible=True`, alat ukurnya
   benar.

2. **Bisect varian.** Jalankan entrypoint yang sama DENGAN dan TANPA
   `--dart-define`, plus satu varian lain sebagai pembanding:

   | Entrypoint | `--dart-define` | Jendela |
   |---|---|---|
   | `main.dart` | — | tampil |
   | `main_apotik.dart` | — | tampil |
   | `main_apotik.dart` | `EBISNIS_VARIANT=apotik` | **tidak pernah** |

   Karena bedanya hanya define, penyebabnya pasti di kode/berkas yang
   ber-namespace varian.

3. **Lokalisasi titik gantung** dengan `debugPrint` sementara di beberapa titik
   `bootstrap()` (lalu KEMBALIKAN berkasnya). Hasilnya: berhenti tepat di
   `AppThemeController.muat()` → `SharedPreferences.getInstance()`.

4. **Munculkan pesannya.** Exception di dalam `runZonedGuarded` tidak tampil di
   konsol. Entrypoint probe kecil (tanpa zone guard) yang hanya memanggil
   `SharedPreferences.getInstance()` langsung menunjukkan
   `FormatException: Unexpected character (at character 1)`.

5. Berkas `%APPDATA%\id.zishof\eBisnis POS Apotik\shared_preferences.json`
   ternyata berisi **387 byte NUL** — pola khas proses berhenti paksa/mati
   listrik di tengah penulisan.

## Akar masalah

`PrefsGuard.perbaikiJikaKorup()` sudah lama ada dan JavaDoc-nya menyebut
persis kasus ini ("app tidak bisa dibuka lagi setelah mati listrik"). Ia hanya
dipanggil `main.dart`. Ketika `main()` dipindah ke `bootstrap()` bersama,
panggilan itu tidak ikut pindah — jadi varian yang lewat `bootstrap()`
kehilangan penjaganya tanpa ada yang menyadarinya.

Rantai kegagalannya: berkas korup → `getInstance()` melempar → `await` di
`bootstrap()` tidak pernah selesai → `runApp` tidak pernah dipanggil → frame
pertama tidak pernah ada → jendela tidak pernah ditampilkan. Exception-nya
ditelan `runZonedGuarded`, yang justru membuatnya tidak meninggalkan jejak.

## Perbaikan

`bootstrap()` memanggil `await PrefsGuard.perbaikiJikaKorup()` sebelum apa pun
menyentuh `SharedPreferences`. Berkas korup **dicadangkan** menjadi
`shared_preferences.json.corrupt-<timestamp>`, bukan dihapus.

Ditambah `test/prefs_guard_kontrak_test.dart`: setiap jalur boot wajib
meng-`await` `PrefsGuard` SEBELUM `runApp`, dan keempat entrypoint varian wajib
lewat `bootstrap()` bersama — supaya penjaga ini tidak bisa hilang lagi tanpa
ketahuan.

## Verifikasi

* Varian apotik, pada berkas yang benar-benar korup: sebelum perbaikan tidak
  pernah tampil (dipantau 60 detik); sesudah perbaikan tampil dalam 20 detik,
  dan berkas korupnya terkarantina.
* Varian **MitraInap** dijalankan dari repo ini setelah perbaikan: jendela
  tampil normal — perubahan pada jalur boot bersama aman untuk varian lain.
* Suite repo ini: 746 lulus, 1 gagal (`riwayat_revisi_hak_test.dart`).
  Kegagalan itu **sudah ada sebelum** perubahan ini (diuji ulang dengan
  perubahan di-stash) dan milik pekerjaan sesi lain.

## Yang perlu diketahui saat merilis

Instalasi mana pun yang berkas preferensinya sudah terlanjur korup akan tetap
macet sampai build berisi perbaikan ini dipasang. Sampai itu terjadi,
penyelesaian manualnya: hapus/ganti nama
`%APPDATA%\id.zishof\<Nama Aplikasi>\shared_preferences.json`.
