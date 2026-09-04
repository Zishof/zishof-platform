# 11 — Roadmap Implementasi Pengembangan Lanjutan Apotik

Status: **USULAN SIAP DIJADIKAN BACKLOG**  
Tanggal baseline: 5 September 2026  
Baseline aplikasi: Apotik `v1.34.24` build `186`, tenant UAT `Demo`  
Target: mengembangkan POS Apotik menjadi sistem pengelolaan apotek yang lengkap,
aman, dapat diaudit, local-first, dan siap diperluas ke banyak lokasi.

Dokumen ini melanjutkan:

- `00-current-state-audit.md` untuk kondisi awal;
- `02-api-action-map.md` untuk kontrak API yang sudah tersedia;
- `07-implementation-plan.md` untuk fase modernisasi yang telah selesai;
- `10-integration-requests.md` untuk gap backend IR-03, IR-04, IR-08, IR-09,
  dan IR-10;
- `../pos/ATURAN-WAJIB-LOCAL-FIRST.md` sebagai gerbang arsitektur dan rilis.

## 1. Ringkasan keputusan

Pengembangan dilakukan **tanpa big-bang rewrite**. Flutter Android/Windows,
Java/Tomcat, PostgreSQL, pola `ApiClient.aksi`, tabel audit, serta modul
akuntansi existing tetap dipakai. Backend dipertahankan sebagai modular
monolith; worker/outbox terpisah ditambahkan hanya untuk pekerjaan asinkron
seperti notifikasi, unggah lampiran, dan integrasi eksternal.

Urutan implementasi:

1. keputusan produk dan fondasi keselamatan;
2. hardening transaksi, stok, kas, audit, signing, dan pemulihan;
3. racikan/produksi farmasi end-to-end;
4. profil pasien dan telaah klinis;
5. recall, cold-chain, perencanaan stok, procurement, dan multi-lokasi;
6. integrasi eksternal, CRM, dan analitik lanjutan.

Estimasi dasar adalah **40 minggu kalender** untuk tim inti yang disebutkan pada
§16. Estimasi ini bukan komitmen tanggal. Pengadaan basis pengetahuan klinis,
sertifikat signing, persetujuan regulator, dan akses pihak ketiga dapat berjalan
di luar kendali tim engineering.

## 2. Kondisi saat ini dan sasaran

| Area | Baseline v1.34.24 | Sasaran akhir |
|---|---|---|
| Penjualan | OTC dan resep non-racikan, FEFO, split payment, idempotensi | Penjualan, reservasi, koreksi/reversal, dan audit lengkap |
| Resep | Antrean, detail, dispensing, pemeriksa kedua, konseling | Telaah klinis, racikan, label, serah, dan histori terapi lengkap |
| Racikan | Terbaca tetapi terkunci; belum ada aksi tulis server | Formula berversi, BOM, timbang, produksi, QC, HPP, BUD, dan etiket |
| Persediaan | Batch, FEFO, expiry, status lot, opname, retur | Ledger stok immutable, recall, reservasi, transfer, dan perencanaan |
| Cold-chain | Profil dan suhu penerimaan sebagian tersedia | Log berkala/sensor, excursion, karantina, notifikasi, dan bukti tindak lanjut |
| Kas | Sesi kas khusus apotek tersedia pada backend baru | Wajib di semua target, handover, approval selisih, dan audit lintas perangkat |
| Cetak | ESC/POS dan cetak ulang lokal | Riwayat server, bukti digital, alasan reprint, dan identitas perangkat |
| Procurement | PR–PO–BAST–tagihan–bayar tersedia; penerimaan PBF dasar | Partial receiving, three-way match, histori harga, lead time, dan scorecard PBF |
| Laporan | Penjualan, terkendali, expiry, kas, jurnal, dan keuangan | Profitabilitas batch, aging, stock turn, SLA, recall, dan dashboard eksekutif |
| Operasi | Satu konteks toko dan data cache lokal | Multi-gudang/cabang, sinkronisasi aman, dan konsolidasi tenant |
| Distribusi | APK debug-signed dan EXE unsigned untuk UAT | Signing produksi, channel rilis, auto-update terkontrol, dan rollback |

## 3. Sasaran nonfungsional

Target awal berikut harus divalidasi pada Fase 0:

| Dimensi | Target penerimaan |
|---|---|
| Ketersediaan | API transaksi inti 99,9% per bulan, di luar maintenance terjadwal |
| Pencarian | p95 pencarian katalog ≤ 2 detik pada 50.000 item per tenant |
| Transaksi | p95 penjualan online ≤ 5 detik, tidak termasuk waktu payment gateway |
| Konsistensi | Duplikasi stok, pembayaran, atau jurnal = 0 pada pengujian retry 10.000 kali |
| Sinkronisasi | Outbox normal terkirim ≤ 60 detik setelah jaringan tersedia |
| Pemulihan | RPO ≤ 5 menit dan RTO ≤ 60 menit untuk layanan transaksi inti |
| Audit | 100% mutasi kritis memiliki aktor, perangkat, waktu, alasan, versi, dan referensi |
| Privasi | Tidak ada data pasien pada log teknis, analitik, atau screenshot publik |
| Aksesibilitas | Tidak ada overflow pada Android/Windows; skala teks 2,0× tetap dapat digunakan |
| Kapasitas awal | 20 cabang, 50 perangkat aktif bersamaan, dan 1 juta baris ledger stok per tenant |

Angka kapasitas bukan batas permanen. Uji ulang diperlukan sebelum melewati 70%
dari asumsi volume tersebut.

## 4. Keputusan yang wajib diambil pada Fase 0

| ID | Keputusan | Pemilik keputusan | Dampak bila terlambat |
|---|---|---|---|
| DEC-01 | Sumber basis pengetahuan interaksi/dosis: berlisensi atau kurasi apoteker | Owner + Apoteker PJ + Legal | Fase telaah klinis tidak boleh dimulai |
| DEC-02 | Bentuk formula racikan, satuan timbang, toleransi, BUD, dan alur QC | Apoteker PJ | Model data racikan tidak dapat dibekukan |
| DEC-03 | PO dibuat di AIS existing atau workspace apotek | Procurement + Finance | Partial receiving dan three-way match tertunda |
| DEC-04 | Model lokasi: toko, gudang, rak, lemari terkunci, dan stok transit | Owner + Gudang | Ledger stok dan transfer berisiko dirombak |
| DEC-05 | Satu laci dipakai bersama POS umum atau laci apotek terpisah | Finance + Operasional | Perhitungan sesi kas dapat salah sumber |
| DEC-06 | Kebijakan retur, void, refund, override harga, dan approval | Owner + Finance | Kontrol maker-checker tidak dapat difinalkan |
| DEC-07 | Integrasi eksternal yang disetujui dan dasar consent pasien | Legal + Keamanan + Apoteker PJ | Fase integrasi tidak boleh go-live |
| DEC-08 | Pemilik dan penyimpanan keystore Android serta sertifikat Windows | IT/DevOps + Owner | Rilis produksi tetap tertahan |

Tidak boleh ada klaim kepatuhan regulasi hanya berdasarkan implementasi teknis.
Legal dan Apoteker Penanggung Jawab harus memvalidasi kewajiban yang berlaku pada
lokasi serta model bisnis sebelum sign-off produksi.

## 5. Arsitektur sasaran

```text
┌──────────────── Flutter Android / Windows ────────────────┐
│ UI adaptif │ Application layer │ Sync coordinator         │
│ SQLite read model │ Draft │ Domain outbox │ Local files    │
└───────────────────────────┬───────────────────────────────┘
                            │ HTTPS + auth + idempotency key
┌───────────────────────────▼───────────────────────────────┐
│                 AIS Java/Tomcat modular monolith          │
│ Resep │ Racikan │ Clinical │ Inventory │ Kas │ Procurement │
│ Patient │ Recall │ Reporting │ RBAC │ Audit                │
├───────────────────────────┬───────────────────────────────┤
│ PostgreSQL transactional  │ Transactional integration outbox│
│ ledger + workflow state   │ retry/dead-letter/replay      │
└───────────────────────────┴──────────────┬────────────────┘
                                          │
                         ┌────────────────▼───────────────┐
                         │ Worker/integration adapters     │
                         │ Notification │ e-resep │ BI │ IoT│
                         └────────────────────────────────┘
```

### Keputusan arsitektur

- **Modular monolith lebih dahulu.** Ini meminimalkan perubahan deployment dan
  transaksi lintas layanan. Kekurangannya adalah disiplin batas modul harus
  dijaga melalui package, service, dan kontrak test.
- **Ledger immutable untuk stok dan uang.** Saldo adalah proyeksi, bukan data
  utama yang diedit. Koreksi membentuk reversal/adjustment baru.
- **State machine untuk resep, racikan, recall, dan procurement.** Perpindahan
  status terjadi melalui perintah yang tervalidasi, bukan update status bebas.
- **Transactional outbox server.** Integrasi pihak ketiga tidak berada di dalam
  transaksi utama dan dapat diulang tanpa menggandakan akibat.
- **Additive migration.** Kolom/tabel/API baru kompatibel dengan klien lama;
  penghapusan kontrak dilakukan paling cepat dua rilis setelah telemetry
  membuktikan tidak ada pemakai.

Microservices baru dipertimbangkan bila satu modul membutuhkan skala, frekuensi
rilis, isolasi kegagalan, atau kepemilikan tim yang benar-benar berbeda.

## 6. Kontrak local-first

| Operasi | Klasifikasi | Perilaku wajib |
|---|---|---|
| Baca katalog, pasien, formula, daftar resep, laporan nonfinansial | Cache-first | Render SQLite, refresh server di latar belakang, pagination lokal |
| Edit draft resep/racikan, catatan konseling, pembacaan suhu, master pemasok | Queueable | Transaksi SQLite + outbox atomik sebelum jaringan |
| Lampiran resep/faktur/bukti | Queueable | Salin file lokal, preview lokal, upload resumable melalui outbox |
| Penerimaan/transfer/opname stok | Domain outbox setelah idempotensi selesai | Ledger lokal pending, server rekonsiliasi, konflik terlihat dan dapat ditindak |
| Pembayaran/penyerahan obat | Online-only | Server memvalidasi lot segar, FEFO, register terkendali, dan pembayaran |
| Approval formula/PO/void/refund/recall | Online-only | Fail-closed karena membutuhkan otorisasi dan versi server terbaru |
| Posting jurnal, closing, tutup sesi kas | Online-only | Server menghitung dan mengunci angka final |
| Telaah klinis final | Online-only | Basis pengetahuan, profil pasien, versi aturan, dan audit harus terkini |

Setiap mutasi baru wajib memiliki klasifikasi di atas sebelum code review. Mutasi
langsung `ApiClient.aksi(...)` tanpa helper local-first atau alasan online-only
tertulis adalah kegagalan gerbang rilis.

## 7. Standar kontrak perintah

Semua perintah tulis baru menggunakan envelope logis berikut, meskipun tetap
ditransmisikan melalui pola action existing:

```json
{
  "action": "apotik_<domain>_<command>",
  "request_id": "uuid",
  "idempotency_key": "uuid-stabil-per-operasi",
  "device_id": "terminal-terdaftar",
  "local_transaction_id": "uuid-lokal",
  "expected_version": 7,
  "occurred_at": "ISO-8601 dengan zona waktu",
  "payload": {}
}
```

Respons minimum:

```json
{
  "status": "success",
  "server_id": 123,
  "version": 8,
  "idempotent_replay": false,
  "sync_status": "CONFIRMED",
  "warnings": [],
  "conflicts": []
}
```

`idempotency_key` mempunyai unique constraint per tenant + action. Respons
pertama disimpan agar retry mengembalikan akibat yang sama. Konflik versi tidak
boleh ditimpa otomatis; UI menampilkan data lokal, data server, alasan, dan aksi
yang aman.

## 8. Model data logis yang ditambahkan

Nama final mengikuti konvensi AIS setelah schema review.

### Fondasi dan audit

- `apotik_idempotency_record`
- `apotik_stock_ledger`
- `apotik_stock_balance_projection`
- `apotik_stock_reservation`
- `apotik_print_event`
- `apotik_void_refund_request`
- `apotik_device_registration`
- perluasan `apotik_sesi_kas` dengan handover dan approval selisih

### Racikan

- `apotik_compound_formula` dan `apotik_compound_formula_version`
- `apotik_compound_formula_item`
- `apotik_compound_order`
- `apotik_compound_weighing`
- `apotik_compound_batch`
- `apotik_compound_qc`
- `apotik_compound_label`

### Pasien dan klinis

- `apotik_patient_profile`
- `apotik_patient_allergy`
- `apotik_patient_medication`
- `apotik_clinical_review`
- `apotik_clinical_alert`
- `apotik_clinical_override`
- `apotik_counselling_record`
- `apotik_consent_record`

### Operasional lanjutan

- `apotik_recall_case`, `apotik_recall_batch`, `apotik_recall_followup`
- `apotik_temperature_log`, `apotik_temperature_excursion`
- `apotik_location`, `apotik_stock_transfer`, `apotik_stock_transfer_item`
- `apotik_inventory_policy`, `apotik_replenishment_suggestion`
- `apotik_supplier_item`, `apotik_supplier_score`
- perluasan PO/BAST/penerimaan dengan kuantitas dipesan, diterima, ditolak,
  tersisa, lokasi, batch, dan status rekonsiliasi

### Integrasi dan CRM

- `apotik_integration_outbox`, `apotik_integration_attempt`
- `apotik_external_reference`
- `apotik_delivery_order`, `apotik_delivery_event`
- `apotik_customer_membership`, `apotik_reward_ledger`
- `apotik_notification_preference`, `apotik_notification_event`

Semua tabel sensitif memakai tenant scope, audit actor, timestamps, version
optimistic locking, dan soft-retention sesuai kebijakan. Soft delete tidak boleh
dipakai untuk menyamarkan pembatalan transaksi final.

## 9. Roadmap fase dan release gate

### Fase 0 — Discovery dan keputusan produk (minggu 1–2)

**Tujuan:** membekukan kontrak yang tidak boleh ditebak oleh engineering.

Deliverable:

- workshop alur resep, racikan, QC, recall, procurement, kas, dan multi-lokasi;
- keputusan DEC-01 sampai DEC-08;
- data dictionary dan state machine yang disetujui Apoteker PJ;
- threat model data pasien, obat terkendali, payment, dan perangkat;
- baseline performa, backup/restore, serta daftar integrasi;
- ADR modular monolith, ledger stok, dan domain outbox;
- data UAT anonim dan acceptance scenario tiap peran.

**Gate keluar:** seluruh keputusan memiliki owner dan tanda setuju; backlog dapat
diestimasi; tidak ada field klinis atau regulasi yang masih dikarang.

### Fase 1 — Fondasi keselamatan dan produksi (minggu 3–8)

**Tujuan:** seluruh mutasi kritis idempoten, dapat ditelusuri, dan dapat
dipulihkan sebelum fitur klinis diperluas.

Deliverable:

- envelope perintah, tabel idempotensi, dan replay response;
- ledger stok immutable + proyeksi saldo + job rekonsiliasi;
- idempotensi penerimaan, opname, retur, dan transfer;
- hardening sesi kas existing: handover, approval selisih, dan histori;
- audit server untuk cetak/reprint, void, retur, refund, override, dan buka laci;
- stop-sale recall minimum pada batch yang ditahan;
- registrasi perangkat, rotasi secret, redaksi log, dan audit role;
- keystore Android, signing Windows, SBOM, dependency scan, backup, restore drill,
  dashboard teknis, serta alert transaksi/outbox gagal;
- feature flag dan migrasi additive untuk seluruh perubahan.

API utama yang diusulkan:

- `apotik_mutasi_stok_submit/status/reconcile`
- `apotik_print_event_catat/list`
- `apotik_void_refund_ajukan/setujui/tolak`
- `apotik_sesi_kas_handover/selisih_setujui`
- `apotik_device_register/revoke`

**Gate keluar:** retry 10.000 kali tanpa duplikasi; saldo proyeksi cocok 100%
dengan ledger; restore drill memenuhi RPO/RTO; APK/EXE production-signed; seluruh
aksi irreversible fail-closed.

### Fase 2 — Racikan dan produksi farmasi (minggu 9–16)

**Tujuan:** menghilangkan jalur racikan yang masih terkunci.

Deliverable:

- formula racikan berversi, satuan, konversi, BOM, rendemen, dan instruksi;
- draft formula local-first; approval formula online-only;
- work order dari resep atau produksi stok;
- reservasi batch bahan, FEFO, penimbangan aktual, toleransi, dan alasan deviasi;
- perhitungan HPP bahan, kemasan, jasa, susut, dan pembulatan;
- label/etiket, BUD, aturan simpan, nomor batch hasil, serta QR traceability;
- pemeriksaan kedua oleh pengguna berbeda dan pelepasan hasil;
- konsumsi bahan dan hasil produksi ditulis ke ledger stok serta jurnal;
- penjualan racikan melalui kasir existing tanpa melewati item resep.

State machine minimum:

```text
DRAFT → APPROVED → RESERVED → WEIGHING → COMPOUNDED → QC_PENDING
      → RELEASED → DISPENSED
                     └→ REJECTED → CORRECTED/DISPOSED
```

API utama:

- `apotik_formula_list/detail/simpan/approve`
- `apotik_racikan_buat/reservasi/mulai/timbang/selesai`
- `apotik_racikan_qc/release/reject`
- `apotik_racikan_label/cost`

**Gate keluar:** 100 resep racikan dan 100 produksi stok lulus end-to-end;
seluruh bahan dapat ditelusuri ke batch sumber; petugas yang sama tidak dapat
menjadi pemeriksa kedua; hasil gagal QC tidak dapat dijual.

### Fase 3 — Profil pasien dan keselamatan klinis (minggu 17–26)

**Tujuan:** menyediakan telaah yang nyata tanpa rasa aman palsu.

Deliverable:

- profil pasien, alergi, kondisi penting, kehamilan, parameter dosis yang
  disetujui, obat aktif, histori resep, dan consent;
- adapter basis pengetahuan berlisensi/terkurasi dengan versi dataset;
- pemeriksaan alergi, interaksi, duplikasi terapi, kontraindikasi, dan rentang
  dosis sesuai data yang tersedia;
- tingkat keparahan, sumber, penjelasan, tindakan, dan override beralasan;
- telaah klinis final online-only dan selalu mencatat versi aturan;
- konseling, medikasi rutin, refill, serta serah obat terhubung ke pasien;
- penyamaran identitas berdasarkan role dan purpose;
- laporan alert, override, near miss, dan SLA resep berdasarkan `waktu_masuk`
  yang immutable.

API utama:

- `apotik_pasien_cari/detail/simpan`
- `apotik_pasien_alergi_simpan`
- `apotik_telaah_klinis_evaluasi/finalkan`
- `apotik_alert_override`
- `apotik_konseling_catat`

**Gate keluar:** hasil golden clinical cases disetujui Apoteker PJ; sistem tidak
pernah menampilkan “aman” saat sumber data gagal; override selalu membutuhkan
alasan dan kewenangan; data pasien tidak muncul pada log atau layar publik.

### Fase 4 — Inventory intelligence dan supply chain (minggu 27–34)

**Tujuan:** mengurangi kekosongan, dead stock, kehilangan expiry, dan pekerjaan
rekonsiliasi manual.

Deliverable:

- hierarki lokasi, transfer, stok transit, penerimaan tujuan, dan selisih;
- recall lengkap dari batch ke transaksi/pasien serta tindak lanjut;
- log suhu manual/sensor, excursion, karantina otomatis, disposition, dan bukti;
- min/max, reorder point, safety stock, days of cover, stock turn, dan aging;
- usulan pembelian dengan approval manusia, bukan auto-order tanpa kontrol;
- supplier catalog, histori harga, lead time, fill rate, dan scorecard;
- partial receiving dan three-way match PO–BAST–faktur;
- dashboard slow/fast moving, dead stock, potensi expiry loss, dan forecast;
- konsolidasi multi-cabang dengan isolasi tenant dan role per lokasi.

API utama:

- `apotik_transfer_buat/kirim/terima/reconcile`
- `apotik_recall_buat/aktifkan/followup/tutup`
- `apotik_suhu_catat/excursion_disposition`
- `apotik_replenishment_hitung/setujui`
- `apotik_supplier_item_list/score`
- perluasan kontrak procurement existing untuk partial receiving.

**Gate keluar:** tidak ada lot recall yang dapat dipilih; transfer parsial dan
retry tidak menggandakan stok; PO, penerimaan, tagihan, pembayaran, ledger, dan
jurnal dapat ditelusuri dua arah; cabang tidak dapat membaca data cabang lain
tanpa hak eksplisit.

### Fase 5 — Integrasi, CRM, delivery, dan BI (minggu 35–40)

**Tujuan:** memperluas ekosistem tanpa membuat transaksi inti bergantung pada
pihak ketiga.

Deliverable:

- integration outbox, adapter versioning, retry/backoff, dead-letter, replay,
  correlation ID, dan dashboard kegagalan;
- integrasi e-resep/sistem klinik yang telah disetujui;
- payment gateway/QRIS dengan callback idempoten dan rekonsiliasi;
- notifikasi refill, resep siap, delivery, dan recall berbasis consent;
- order delivery dengan verifikasi penerima serta proof of delivery;
- membership/poin sebagai reward ledger terpisah dari kas dan stok;
- data mart read-only untuk BI, profitabilitas, SLA, cohort, dan supply chain;
- ekspor/audit sesuai format yang telah divalidasi pemilik proses.

**Gate keluar:** gangguan mitra tidak menggagalkan transaksi inti; callback
duplikat tidak menggandakan pembayaran/status; pengguna dapat menarik consent;
dead-letter dapat direplay aman; angka BI dapat direkonsiliasi ke sumber.

## 10. Backlog epic

| Epic | Isi | Fase | Dependensi | Ukuran |
|---|---|---:|---|---|
| APF-001 | ADR, state machine, data dictionary, threat model | 0 | — | M |
| APF-002 | Command envelope dan idempotency registry | 1 | APF-001 | L |
| APF-003 | Ledger stok dan proyeksi saldo | 1 | APF-002, DEC-04 | XL |
| APF-004 | Idempotensi penerimaan/opname/retur | 1 | APF-002–003 | L |
| APF-005 | Audit cetak, buka laci, reprint, void, refund | 1 | DEC-06 | L |
| APF-006 | Hardening sesi kas dan handover | 1 | DEC-05 | M |
| APF-007 | Signing, SBOM, observability, backup/restore | 1 | DEC-08 | L |
| APR-001 | Formula dan BOM racikan berversi | 2 | DEC-02, APF-003 | XL |
| APR-002 | Reservasi, timbang, produksi, dan QC | 2 | APR-001 | XL |
| APR-003 | HPP, label, BUD, dan penjualan racikan | 2 | APR-002 | L |
| APC-001 | Profil pasien, alergi, consent, histori terapi | 3 | APF-002, DEC-07 | XL |
| APC-002 | Adapter basis pengetahuan dan rule versioning | 3 | DEC-01 | XL |
| APC-003 | Clinical review, alert, override, konseling | 3 | APC-001–002 | XL |
| APC-004 | SLA resep dan laporan keselamatan | 3 | APC-003, waktu_masuk | M |
| API-001 | Lokasi, transfer, transit, dan rekonsiliasi | 4 | APF-003, DEC-04 | XL |
| API-002 | Recall dan follow-up | 4 | APF-003, APC-001 | L |
| API-003 | Cold-chain log/excursion/sensor | 4 | API-001 | L |
| API-004 | Replenishment dan inventory analytics | 4 | APF-003, API-001 | XL |
| APP-001 | Supplier catalog, partial receiving, three-way match | 4 | DEC-03, APF-004 | XL |
| AXI-001 | Integration outbox dan adapter framework | 5 | APF-002 | L |
| AXI-002 | E-resep/klinik dan payment adapter | 5 | AXI-001, DEC-07 | XL |
| AXI-003 | Notification, delivery, dan consent enforcement | 5 | AXI-001, APC-001 | L |
| AXI-004 | Membership, reward ledger, dan BI read model | 5 | AXI-001, APF-003 | L |

Ukuran: S ≤ 1 sprint, M 1–2 sprint, L 2–3 sprint, XL harus dipecah menjadi
beberapa story vertikal sebelum masuk sprint.

## 11. Strategi implementasi vertikal

Setiap epic dipecah berdasarkan irisan end-to-end, bukan per layer. Contoh untuk
racikan:

1. satu formula sederhana dapat dibuat sebagai draft local-first;
2. formula dapat disetujui online dengan optimistic lock;
3. satu resep racikan dapat mereservasi satu bahan dari satu batch;
4. penimbangan dan QC menghasilkan satu batch hasil;
5. hasil dapat dijual dan terlacak ke bahan sumber;
6. baru kemudian tambah multi-bahan, substitusi, deviasi, kemasan, dan produksi
   stok.

Setiap irisan mencakup migration, service backend, API contract, SQLite/outbox,
UI Android/Windows, permission, audit, observability, test, dokumentasi, dan
rollback flag. Tidak ada story “backend selesai” bila jalur pengguna belum dapat
diverifikasi end-to-end.

## 12. Strategi pengujian

### Lapisan wajib

- **Unit:** state machine, money, dosis, konversi satuan, FEFO, BUD, HPP, dan
  aturan akses.
- **Contract:** request/response, kompatibilitas klien lama, pagination, versi,
  idempotency replay, dan error code.
- **Database:** unique constraint, transactional outbox, audit trigger, ledger
  seimbang, migrasi maju, dan restore.
- **Local-first:** cache tetap tampil saat timeout/5xx; write lokal mendahului
  jaringan; restart melanjutkan outbox; penolakan bisnis tidak infinite retry.
- **Integration:** transaksi–stok–kas–jurnal–laporan, procurement, racikan,
  clinical knowledge, payment callback, serta integrasi eksternal.
- **UI:** Android/Windows, 1920×1080, ukuran Android sasaran, text scale 2,0×,
  keyboard, scanner, printer, dan offline banner.
- **Security:** tenant isolation, RBAC, maker-checker, IDOR, injection, redaksi
  PII, secret rotation, device revoke, dan dependency scanning.
- **Performance:** katalog 50.000, ledger 1 juta, antrean/outbox besar, laporan,
  dan sinkronisasi setelah offline panjang.
- **Recovery:** backup restore, worker crash, duplicate callback, partial upload,
  database failover, dan jam perangkat salah.
- **UAT:** kasir, apoteker, gudang, procurement, finance, admin, auditor, serta
  pasien/layar publik memakai data sample anonim.

### Quality gate per release

1. `dart format` dan scoped `flutter analyze` bersih.
2. Seluruh test existing tetap hijau; test baru mencakup happy path dan failure.
3. Tidak ada mutasi langsung tanpa klasifikasi local-first/online-only.
4. Screenshot bukti berisi data nyata/sample, bukan placeholder.
5. Database migration telah diuji pada salinan schema produksi dan audit schema.
6. Reconciliation stok, kas, dan jurnal bernilai nol selisih atau mempunyai
   pengecualian yang disetujui.
7. Threat model dan permission map diperbarui.
8. Dokumentasi operator, runbook, release notes, checksum, dan rollback tersedia.
9. APK/EXE ditandatangani sesuai channel distribusi.
10. Sign-off pemilik proses terkait tercatat.

## 13. Observability dan operasi

Dashboard operasional minimum:

- error rate dan latency per action;
- jumlah outbox pending/gagal, umur tertua, retry, dan dead-letter;
- idempotent replay dan duplicate rejection;
- drift antara stock projection dan ledger;
- batch recall/ditahan yang masih mempunyai reservasi;
- resep per status, SLA, alert klinis, dan override;
- sesi kas belum ditutup, selisih, void/refund menunggu approval;
- temperature excursion terbuka;
- integration callback gagal atau tertunda;
- versi aplikasi aktif dan perangkat yang belum memperbarui.

Log teknis hanya menyimpan ID korelasi dan identitas teknis yang diperlukan.
Nama pasien, alamat, nomor telepon, diagnosa, isi resep, token, dan payload
payment tidak boleh ditulis mentah.

## 14. Deployment, rollout, dan rollback

### Urutan rollout

1. migrasi additive dan backend kompatibel lama;
2. deploy worker dalam kondisi consumer/feature flag mati;
3. aktifkan telemetry dan shadow calculation;
4. deploy Flutter ke tenant `Demo`;
5. jalankan seed idempoten dan UAT volume;
6. pilot satu lokasi dan beberapa perangkat;
7. rekonsiliasi paralel stok/kas/jurnal minimal 7 hari operasional;
8. aktifkan per role/lokasi secara bertahap;
9. perluas setelah metric dan sign-off memenuhi gate.

### Rollback

- matikan feature flag; jangan menghapus tabel/kolom baru saat insiden;
- klien lama tetap dapat memakai kontrak lama;
- hentikan worker/integrasi tanpa membatalkan transaksi utama;
- pertahankan outbox dan audit untuk replay setelah perbaikan;
- reversal dilakukan melalui command resmi, bukan SQL ad-hoc;
- rollback binary bila crash/error meningkat, tetapi migration additive tetap;
- eskalasi dan hentikan penyerahan obat bila integritas batch, resep, atau pasien
  tidak dapat dipastikan.

Trigger rollback wajib meliputi transaksi ganda, stok negatif tak terjelaskan,
lot recall dapat dijual, pemeriksa kedua dapat sama, jurnal tidak seimbang,
selisih kas material tanpa sumber, kebocoran data pasien, atau integrasi yang
mengubah status berulang.

## 15. Risiko dan mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Basis pengetahuan klinis tidak tersedia | Telaah klinis tertunda/menyesatkan | Fail-closed; jangan tampilkan “aman”; selesaikan DEC-01 lebih awal |
| Model stok existing bukan ledger penuh | Migrasi saldo dan histori kompleks | Snapshot pembuka, dual-write terbatas, rekonsiliasi, dan cutover per lokasi |
| Retry menggandakan stok/integrasi | Kerugian dan ketidaksesuaian laporan | Idempotency registry, unique constraint, replay test, callback fingerprint |
| Perubahan schema audit tertinggal | Transaksi induk rollback | Generator/check migration untuk schema utama dan audit dalam CI |
| Konflik offline antarpengguna | Data lokal menimpa server | Versioning, conflict inbox, tidak ada last-write-wins untuk data kritis |
| Scope regulasi berubah | Rework dan go-live tertahan | Validasi legal/apoteker pada discovery dan sebelum setiap release |
| Multi-cabang membuka data lintas lokasi | Insiden privasi/tenant | Tenant/location scope pada query, contract test isolasi, least privilege |
| Integrasi pihak ketiga tidak stabil | Antrean menumpuk | Transactional outbox, circuit breaker, backoff, dead-letter, manual replay |
| Tim terlalu kecil untuk semua jalur paralel | Kualitas turun | Batasi WIP; satu vertical slice selesai sebelum epic berikutnya |

## 16. Asumsi tim dan tata kelola

Estimasi 40 minggu mengasumsikan:

- 1 Product Owner yang dapat mengambil keputusan mingguan;
- 1 Apoteker Penanggung Jawab/Product Specialist;
- 2 Flutter engineer;
- 2 Java/PostgreSQL engineer;
- 1 QA automation + 1 QA/UAT;
- 0,5–1 DevOps/Security;
- dukungan paruh waktu Finance, Procurement, Legal/Privacy, dan operasional toko.

Cadence yang disarankan adalah sprint dua minggu, demo setiap sprint, dan release
train paling lambat enam minggu. Satu owner teknis menjaga kontrak lintas Flutter,
AIS, PostgreSQL, audit schema, dan akuntansi.

Jika tim hanya berisi 2–3 engineer, jangan menjalankan semua fase paralel. Urutan
tetap dipertahankan dan durasi disesuaikan; fitur klinis tidak boleh dipercepat
dengan mengurangi validasi ahli.

## 17. Definition of Done

Sebuah pengembangan hanya selesai bila:

- acceptance criteria pemilik proses terpenuhi;
- data model, API, audit, permission, local-first, dan observability lengkap;
- retry/restart tidak menggandakan efek;
- kegagalan jaringan serta penolakan bisnis menghasilkan status yang jujur;
- stok/kas/jurnal dapat direkonsiliasi ke ledger dan dokumen sumber;
- data sensitif tidak bocor ke log atau layar publik;
- test unit, contract, integration, UI, security, performance terkait lulus;
- migrasi utama dan audit schema telah diuji;
- feature flag, rollback, runbook, manual pengguna, serta release notes tersedia;
- build ditandatangani sesuai channel dan sign-off tercatat.

## 18. Sepuluh pekerjaan pertama

Urutan ini dapat langsung dipindahkan ke issue tracker:

1. Selesaikan DEC-01 sampai DEC-08 dan tetapkan owner/tanggal keputusan.
2. Buat ADR ledger stok, idempotency registry, dan transactional outbox.
3. Inventaris seluruh mutasi Apotik serta klasifikasikan queueable/online-only.
4. Tambah contract test duplikasi untuk penerimaan, opname, retur, dan pembayaran.
5. Rancang dan migrasikan `apotik_idempotency_record` berikut audit table-nya.
6. Jadikan `apotik_terima_barang` idempoten tanpa mengubah kontrak klien lama.
7. Rancang ledger stok dan rekonsiliasi terhadap saldo batch existing.
8. Tambah audit server untuk cetak ulang, void/refund, dan identitas perangkat.
9. Jalankan restore drill serta selesaikan keystore Android/sertifikat Windows.
10. Pecah APR-001 menjadi vertical slice formula racikan paling sederhana.

## 19. Hal yang ditinjau ulang saat sistem tumbuh

- Pemisahan service baru hanya bila profiling membuktikan modular monolith tidak
  memenuhi isolasi atau kapasitas.
- Partitioning/archival ledger saat satu tabel mendekati batas operasional yang
  disepakati DBA.
- Read replica/data warehouse ketika laporan mengganggu transaksi.
- Dedicated message broker ketika throughput outbox atau jumlah integrasi
  melampaui kemampuan worker database polling.
- Multi-region hanya setelah kebutuhan bisnis dan RPO/RTO mengharuskannya.
- Search engine terpisah hanya bila PostgreSQL trigram/full-text tidak lagi
  memenuhi target pencarian.

Keputusan tersebut harus berbasis telemetry dan biaya nyata, bukan antisipasi
yang belum terbukti.
