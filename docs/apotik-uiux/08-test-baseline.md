# 08 — Baseline Test

**Sebelum** perubahan UI apapun (commit `ce3d1b9`).

- Total file test: **28** di `apps/ebisnis/test/`.
- Terkait apotik saat ini: `apotik_data_contoh_button_test.dart`,
  `pos_help_content_test.dart`, `product_profile_test.dart` (varian),
  `mobile_navigation_layout_test.dart`.
- **Golden test varian apotik: TIDAK ADA** — ini gap utama yang ditutup Fase 1.

**Hasil baseline dijalankan di worktree ini (19 Agu 2026):**

```
flutter test  ->  71 test, All tests passed!  (28 detik)
```

Angka 71 inilah pagar regresi: setiap fase berikutnya WAJIB tetap hijau dan
menambah test baru, bukan mengurangi.

## Target penambahan test

| Fase | Test wajib |
|---|---|
| 1 | unit token & breakpoint; widget status pill/empty/error; **golden** shell desktop + mobile |
| 2 | widget dashboard prioritas; golden dashboard |
| 3 | unit state machine POS (kunci saat `paymentPending`, idempotency sama saat retry); widget keranjang; golden POS desktop + mobile |
| 4 | widget antrean resep; unit transisi status resep |
| 5 | unit klasifikasi batch (expired/nearExpiry/depleted); widget FEFO picker (batch kedaluwarsa TIDAK dapat dipilih) |
| 6 | unit anti double-submit; widget banner sinkron |
| 7 | widget laporan; golden tutup shift |
| 8 | a11y (semantics, target sentuh), performa katalog besar |
