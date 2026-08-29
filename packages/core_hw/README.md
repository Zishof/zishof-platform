# core_hw

Adapter perangkat keras bersama untuk aplikasi POS Flutter. Paket ini menjaga
kode layar tetap lintas-platform dan memusatkan perbedaan implementasi Android,
iOS, dan Windows.

## Fitur

- Pemindaian barcode/QR melalui kamera Android/iOS.
- Pemindaian barcode/QR melalui webcam Windows.
- Dukungan scanner barcode USB yang berperilaku sebagai keyboard.
- Cetak RAW dan buka laci kasir pada Windows.

## Penggunaan

Panggil `BarcodeScannerScreen.pindai(context)` untuk membuka scanner kamera.
Nilai pertama yang valid dikembalikan sebagai `String`; pembatalan menghasilkan
`null`. Untuk scanner USB keyboard-wedge, fokuskan input barcode biasa.

```dart
final kode = await BarcodeScannerScreen.pindai(
  context,
  judul: 'Pindai produk',
);
```

## Batas biometrik

Perekaman fingerprint dan face recognition POS tidak berada dalam `core_hw`.
Kontrak dan kebijakan sensitifnya berada di
`apps/ebisnis/lib/services/biometric_capture_bridge.dart`. Fingerprint Windows
menggunakan SecuGen WebAPI lokal; Android memerlukan SDK scanner eksternal.
Face recognition wajib menghasilkan embedding dan liveness, bukan foto mentah.

## Keamanan

- Jangan menyimpan template biometrik, foto wajah, token, atau secret vendor di
  paket ini.
- Permission kamera diminta hanya saat pengguna membuka scanner.
- Kegagalan membuka kamera mengembalikan pesan yang dapat ditindaklanjuti dan
  tidak mengubah data transaksi.
