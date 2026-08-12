# HANDOVER — POS eBisnis & Al-Bahjah (2026-08-12)

> Untuk sesi/komputer berikutnya. Semua yang disebut di sini SUDAH di-push;
> cukup `git pull` di kedua repo (AIS + zishof-platform). Prompt Codex siap-pakai
> ada di §7.

## 1. Repo & branch

| Repo | Path lokal (komputer lama) | Branch | HEAD terakhir |
|---|---|---|---|
| AIS (server) | `C:\opt\AIS\ais\src\main` | `feat/new-ui-rbac-role-user` | `361eea4f` |
| zishof-platform (Flutter, eBisnis+Al-Bahjah) | `C:\opt\CodeBaseDesktopDanMobile` | `main` | `6274b47` |
| SVN | `C:\opt\CodeBaseDesktopDanMobile`, `C:\opt\eBisnis`, `C:\opt\AIS\ais-pos-kasir-android` semuanya dual-tracked ke `svn://38.47.178.34/pos/...` — **TIDAK disentuh sesi ini**: `.svn` di ketiganya bahkan melacak folder `.git` internal (setup tidak biasa), tidak ada skrip sync yang ditemukan (beda dgn AIS yang auto-mirror dari git per catatan sesi P10 sebelumnya). Kalau memang perlu di-sync manual, minta prosedurnya ke user dulu — jangan `svn commit` serampangan, resikonya nyampah ribuan blob `.git/objects/*` ke SVN. | — | — |

⚠️ Ada sesi Codex/Claude PARALEL yang aktif di working copy AIS YANG SAMA hari
ini: remote `feat/new-ui-rbac-role-user` sempat maju sendiri dgn commit
`92f95721` ("Perbaiki kelola anggota tugas kelompok...") sementara sesi ini
kerja lokal — sudah di-merge bersih (tidak ada file yg overwrite silang).
Selalu commit dgn **pathspec eksplisit** (`git add <file...>`, JANGAN
`git add -A`), `git fetch`+`git merge origin/<branch>` sebelum push kalau
ditolak "fetch first". Lihat memori `codex-concurrent-session-overwrite-commit-fast`.

## 2. Yang SELESAI + di-push sesi ini

1. **SesiKasKasir: kolom `kasirNama`/`kasirUserId`** (AIS `106edc2d`) — migrasi
   penuh semua call-site: `SesiKasUtil` (buka/tutup/sesiTerbuka/idSesiTerbuka),
   `KantinHelper`, `PosKantinAction` (ZK), `KasKasirZkAction`, `service.jsp`
   (implementasi independen), raw-SQL report di `PosApi`/`LaporanKantinUtil`/
   `DashboardKepatuhanKantinAction`. Revert exemption
   `AuditTimestampInterceptor` (solusi setengah lama, root cause aslinya sudah
   diperbaiki commit `869f858d` — lihat memori
   `bukakas-reprompt-setelah-logout-investigasi`). `mvn -o compile`: **BUILD
   SUCCESS** (6690 file). **BELUM di-deploy ke server manapun** (lihat §4.1).
2. **Fallback preview dokumen Office lampiran ter-proteksi** (AIS `361eea4f`)
   — Google Docs Viewer tak bawa sesi login eCampus, jadi utk file Office
   (bukan PDF/gambar) yg diserve lewat endpoint terproteksi (`/al?d=` atau
   `AmbilLampiran`), ganti iframe Google Viewer dgn kotak info + tombol
   "Buka/unduh lewat eCampus". 3 titik: `ProfileImageUtil`, `UrlDisplayHelper`,
   `WindowViewerHelper`.
3. **zishof-platform**: `git pull` bawa masuk 4 commit release Inventory Sales
   1.33.8/1.33.9 + perbaikan margin price tag — kerja sesi lain, tidak
   disentuh, tidak ada konflik.

## 3. Investigasi SELESAI, implementasi BELUM (siap dikerjakan sesi berikut)

### 3.1 Bug "Mutasi Tabungan" tampil kotak abu-abu kosong (Al-Bahjah POS)

User lapor tab **Pelanggan → Mutasi Tabungan** di app Al-Bahjah POS (rilis,
Flutter Windows) tampil kotak abu-abu polos, bukan tabel data.

- **Source code SUDAH benar** — dicek SEMUA 6 layar "Mutasi" di
  `apps/ebisnis/lib/` (Mutasi Tabungan, Mutasi Hutang, Mutasi Antar Outlet,
  Kartu Mutasi Stok, Monitor Keluar/Masuk, kartu-stok-mutasi di Inventory &
  Sales) — SEMUA pakai `AppDataTable` (grid asli), TIDAK ADA PDF/iframe di
  jalur render utama (PDF cuma tombol export opsional).
- Artinya kotak abu-abu itu **bukan** "lupa pakai grid" — polanya cocok dgn
  Flutter release-mode "blank ErrorWidget" (exception saat `build()`, pesan
  disembunyikan di release build, background jadi kotak abu polos kosong).
  main.dart SUDAH ada `await initializeDateFormatting('id_ID', null)` di awal
  banget (komentar di kode bahkan menjelaskan persis gejala ini) — jadi bukan
  itu penyebabnya, KECUALI installed exe Al-Bahjah v1.33.1 lebih tua dari fix
  itu (perlu dicek tanggal commit vs tanggal rilis).
- **BLOCKER**: sudah siapkan debug build lokal (`flutter run -d windows
  --debug` dari `apps/ebisnis`, window judul "ebisnis", proses `ebisnis.exe`
  di `build\windows\x64\runner\Debug\`) utk lihat stack trace asli — tapi
  macet di layar login, TIDAK PUNYA kredensial user utk masuk. Minta user
  login sendiri di window itu, atau kasih kredensial uji.
- **Next step**: begitu bisa login, buka Pelanggan → Mutasi Tabungan, baca
  stack trace di console `flutter run` (bukan di UI — release mode
  menyembunyikannya, tapi debug mode akan print penuh ke terminal).

### 3.2 Hilangkan iframe "same-app" di JSP (permintaan eksplisit user)

User: "jangan ada yang pakai iframe yang mengarah ke sistem lain atau halaman
lain, pertahankan semua berbasis API dan halaman sendiri" — termasuk topup.
Flutter app sudah 100% bersih (tidak ada `webview_flutter`/iframe sama
sekali, dicek grep seluruh `lib/`). Yang tersisa cuma 2 titik di JSP AIS,
KEDUANYA nge-iframe halaman LAIN di app YANG SAMA (bukan sistem pihak
ketiga):

| File | Iframe | Target |
|---|---|---|
| `webapp/WEB-INF/baru/modul/kantin/toko_online.jsp:391` | `iframeAuth` (modal "Autentikasi Pengguna") | `/login` (login) & `/login?p=registrasi_calon_anggota` (daftar) |
| `webapp/WEB-INF/baru/modul/kantin/_beranda_anggota.jsp:564` | `iframeTopup` (modal "Isi Saldo Top-Up") | `/baru?...&p=kantin%2Fmember&s=topup` |

**Investigasi (agent Explore, sudah lengkap) — kesimpulan: KEDUANYA aman &
mudah dihilangkan, TIDAK ada payment gateway pihak ketiga di sisi client:**

- **Login**: `Login.java:79-175` sudah punya `POST /login?action=ajax_login`
  (form-urlencoded, balas JSON `{status,message,redirect}`) — sudah dipakai
  `login2.jsp:457-499` via `fetch()`. Registrasi
  (`p=registrasi_calon_anggota` → `form_registrasi_calon.jsp`) juga sudah
  `fetch()`-based (`POST /Data`). **Tidak ada CSRF token/filter** di
  `web.xml` — auth murni session-cookie (`credentials:'include'`). Tinggal
  panggil endpoint yg sama langsung dari `toko_online.jsp`, hapus
  `iframeAuth`.
- **Topup**: `topup.jsp` include `_topup.jsp`, yg SUDAH `fetch()`
  `POST .../s=_topup_service` (JSON) lalu `window.location.href = paymentUrl`
  (redirect top-level, bukan iframe). `_topup_service.jsp` panggil gateway
  Esmartlink **server-to-server** (`curlSmartlink`, config
  `gateway_url_va_e_smartlink`) — browser cuma terima string URL. **Tidak ada
  iframe pihak ketiga di level manapun.** Pindahkan logic `_topup.jsp` ke
  `_beranda_anggota.jsp`, hapus `iframeTopup`.
- Rekomendasi implementasi: reuse endpoint JSON yg sudah ada persis
  (`ajax_login`, `s=_topup_service`), JANGAN tulis ulang logic auth/payment
  dari nol. Alternatif lebih cepat (kalau mau minim-risiko): `<jsp:include>`
  (server-side, bukan iframe browser) fragment yg sudah ada langsung ke modal
  body — tapi cek dulu potensi bentrok ID/`<script>` duplikat kalau
  `login2.jsp`/`form_registrasi_calon.jsp`/`_topup.jsp` di-include ganda ke
  halaman yg sudah py sendiri.
- **BELUM diimplementasi** — sengaja ditunda krn user minta handover +
  pindah komputer di tengah kerja; ini task Java/JSP (login+payment,
  sensitif), lebih aman dikerjakan penuh di sesi baru drpd buru-buru sisa
  waktu sesi lama.

## 4. Blocker yang butuh keputusan/input user

### 4.1 Deploy AIS ke server produksi Al-Bahjah

Commit `106edc2d` (SesiKasKasir) + `361eea4f` (preview lampiran) **BELUM
di-deploy** kemanapun. User pilih target "Server produksi Al-Bahjah"
(ecampus.staialbahjah.ac.id) tapi:
- Tidak ada profil SSH bernama Al-Bahjah di antara ~200 profil Bitvise di
  `C:\opt\SSH` (daftar hosting banyak kampus, tidak jelas mana punya
  Al-Bahjah) — profil `.bscp`/`.tlp` itu juga GUI-only, tidak bisa dipakai
  dari command line langsung.
- Ada Tomcat LOKAL di komputer lama (`C:\opt\tomcat\apache-tomcat-9.0.89`,
  sedang tidak jalan) — bisa jadi target uji lokal kalau bukan itu maksudnya.
- **Butuh dari user**: host/SSH access + path `webapps` Tomcat tujuan di
  server produksi Al-Bahjah yg sebenarnya, ATAU konfirmasi kalau user sendiri
  yg akan deploy manual (rebuild WAR + restart, pola yg sama dgn insiden
  sebelumnya di memori `bukakas-reprompt-setelah-logout-investigasi`).

### 4.2 Publish rilis client baru (GitHub Release eBisnis/Al-Bahjah)

User eksplisit: **tunggu fix Mutasi Tabungan dulu** sebelum
build+publish rilis client baru — jangan rilis versi yg masih ada bug
kotak-abu-abu itu. Jadi §3.1 harus tuntas duluan sebelum §3.2 (iframe) dan
rilis baru digabung jadi satu publish.

## 5. Cara reproduksi debug build Mutasi Tabungan (lanjutan cepat)

```powershell
cd C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
flutter run -d windows --debug
```
Tunggu `A Dart VM Service on Windows is available at: http://127.0.0.1:...`
lalu window "ebisnis" muncul (kalau ketutup window lain, pakai
`Get-Process ebisnis` + `SetForegroundWindow` via P/Invoke PowerShell, bukan
Alt+Tab lewat computer-use — perlu grant `systemKeyCombos` kalau mau itu).
Login, buka Pelanggan → Mutasi Tabungan, exception (kalau ada) akan tercetak
penuh di terminal `flutter run` (bukan di layar — itu justru yg bikin
release build tampil kotak abu-abu kosong tanpa pesan).

## 6. Verifikasi cepat di komputer baru

```bash
cd <AIS>/src/main && git pull && cd .. && mvn -o compile        # EXIT=0, BUILD SUCCESS
```
```bash
cd <zishof-platform> && git pull && cd apps/ebisnis && flutter analyze
```

## 7. Prompt lanjutan (format Codex CLI)

```
Lanjutkan handover dari sesi Claude Code sebelumnya (2026-08-12). Baca dulu:
C:\opt\CodeBaseDesktopDanMobile\docs\pos-ebisnis-albahjah\handover_pos_ebisnis_dan_albahjah_2026-08-12.md

Prioritas urut:
1. Repro bug "Mutasi Tabungan" tampil kotak abu-abu kosong di app Flutter
   eBisnis/Al-Bahjah POS (Pelanggan > Mutasi Tabungan). Jalankan
   `flutter run -d windows --debug` di apps/ebisnis, login, buka tab itu,
   baca stack trace asli dari terminal (bukan UI -- release mode
   menyembunyikan errornya jadi kotak abu-abu polos). Source code tab itu
   sudah pakai grid AppDataTable dgn benar (bukan PDF/iframe) -- jadi ini
   genuinely crash saat render, bukan salah pilih widget. Fix akar
   masalahnya, verifikasi live di debug build, baru compile+commit+push.

2. Setelah #1 fix DAN sudah diverifikasi jalan, hilangkan 2 iframe "same-app"
   di JSP AIS sesuai permintaan eksplisit user (tidak boleh ada iframe ke
   halaman lain sama sekali, semua harus API-based + halaman sendiri):
   - webapp/WEB-INF/baru/modul/kantin/toko_online.jsp (modal Autentikasi,
     iframeAuth) -- pakai endpoint yg SUDAH ADA: POST /login?action=ajax_login
     (lihat Login.java:79-175, sudah dipakai login2.jsp) dan form registrasi
     yg sudah fetch-based (form_registrasi_calon.jsp -> POST /Data).
   - webapp/WEB-INF/baru/modul/kantin/_beranda_anggota.jsp (modal Isi Saldo
     Top-Up, iframeTopup) -- pindahkan logic _topup.jsp (sudah fetch-based,
     panggil s=_topup_service, redirect top-level ke paymentUrl -- TIDAK ada
     payment gateway pihak ketiga di sisi client, sudah dicek tuntas) ke
     halaman induk langsung.
   Detail lengkap tiap endpoint + keputusan desain ada di §3.2 handover doc.

3. Setelah #1 dan #2 beres dan sudah dites, build+publish rilis client baru
   (eBisnis + varian Al-Bahjah) ke GitHub Releases dgn versi baru.

4. Compile AIS (mvn -o compile dari folder yg berisi pom.xml, BUKAN src/main)
   sebelum commit apapun. Commit dgn pathspec eksplisit (jangan git add -A --
   ada sesi paralel lain di repo yg sama, lihat §1 handover).

5. Deploy AIS ke server produksi Al-Bahjah masih BLOCKED -- belum ada
   host/SSH/path Tomcat yg jelas (lihat §4.1 handover). Tanya user dulu
   sebelum coba nebak/nyoba connect ke server manapun.

Jangan lakukan git push --force atau apapun yg mengubah history. Selalu
`git fetch` + `git merge origin/<branch>` (bukan rebase) sebelum push kalau
ditolak, konsisten dgn pola sesi sebelumnya.
```
