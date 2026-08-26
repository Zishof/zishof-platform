# Verifikasi biometrik sebelum pembayaran saldo member

## Keputusan

Jenis Member mempunyai dua aturan independen: **Wajib Verifikasi Biometric
Wajah** dan **Wajib Verifikasi Fingerprint**. Aturan hanya menjadi gerbang ketika
metode pembayaran benar-benar memotong deposit/saldo member. Bila keduanya
aktif, keduanya harus berhasil; PIN tidak menggantikan biometric yang wajib.

Pembayaran biasa tetap local-first. Pembayaran saldo yang mewajibkan biometric
harus online dan menunggu pengakuan server karena bukti biometric berumur lima
menit. Menaruh bukti tersebut dalam antrean offline akan menghasilkan transaksi
yang baru dikirim setelah buktinya kedaluwarsa.

## Alur

```text
Kasir memilih member dan metode pembayaran
                 |
                 v
Apakah metode memotong saldo dan jenis member mewajibkan biometric?
       | tidak                              | ya
       v                                    v
Simpan lokal -> outbox             Periksa SDK/perangkat
-> retry idempoten                         |
                                  capture wajah/fingerprint
                                             |
                                  server mencocokkan template
                                             |
                                  event MATCHED + kode transaksi
                                             |
                                  checkout mengirim event_id
                                             |
                                  server memvalidasi ulang:
                                  kasir, member, modality,
                                  kode transaksi, umur <= 5 menit
                                             |
                                  potong saldo + ACK server
                                             |
                                  simpan salinan transaksi lokal
```

## Batas perangkat

- Desktop dapat menggunakan scanner USB jika vendor menyediakan SDK yang
  menghasilkan template kompatibel dengan matcher server.
- Kamera harus disertai face embedding dan pemeriksaan liveness; foto biasa
  tidak dianggap bukti biometric.
- Sensor fingerprint bawaan Android pada umumnya hanya mengautentikasi pemilik
  perangkat melalui Android Keystore dan tidak mengekspor template sidik jari.
  Sensor tersebut tidak dapat dipakai mencocokkan banyak member. Untuk kasus
  kasir diperlukan scanner eksternal/terminal khusus beserta vendor SDK.
- Jika perangkat/metode wajib tidak tersedia, pembayaran saldo dihentikan
  secara fail-closed. Kasir dapat memilih metode pembayaran non-saldo.

## Data dan keamanan

- Server menyimpan template terenkripsi, bukan foto mentah.
- Bukti checkout berupa ID `BiometricEvent`, bukan template/probe.
- Event diikat ke actor, subject, modality, purpose `POS_PURCHASE`, dan
  `reference_id = kodeUnik` sehingga tidak dapat digunakan untuk transaksi lain.
- Perubahan kebijakan Jenis Member diaudit oleh Hibernate Envers.
- Snapshot aturan disimpan dalam `anggota_cache` agar UI offline tidak salah
  menampilkan kebijakan yang lebih longgar.

## Pengembangan berikutnya

Setelah vendor perangkat Al-Bahjah dipilih, buat implementasi native MethodChannel
`ais_mobile/biometric_capture` untuk Android dan Windows, lalu jalankan uji
perangkat nyata: enrolment, false accept/reject, liveness, cabut USB saat capture,
pergantian kasir, replay event, dan transaksi split-payment.
