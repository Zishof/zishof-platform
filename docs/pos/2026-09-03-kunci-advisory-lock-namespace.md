# 83. Kunci Advisory Lock: Konvensi Namespace & Sentralisasi Kunci Sinkron BAST

Tanggal: 3 September 2026  
Lingkungan: UAT lokal — perubahan perilaku NIHIL (refactor + self-test)  
Rujukan: dok. 79 (advisory lock sinkron BAST), OnlineBmt (idiom advisory lock)

> Cermin dokumentasi backend (SVN `ais/docs/pos/83-kunci-advisory-lock-namespace.md`).
> Kode Java hanya ada di SVN; berkas ini salinan catatan untuk repo klien.

## Latar

`bastSinkronKulakan` diserialkan per-BAST dengan advisory lock PostgreSQL
(`pg_try_advisory_lock(hashtext("bast-sinkron:" + id))`) supaya stok Kulakan tidak
tergandakan saat dua sinkron BAST yang sama beririsan (dok. 79). Saat menyisir ulang
modul pengadaan/logistik, seluruh pemakai advisory lock di basis kode diaudit karena
**semuanya berbagi SATU ruang kunci `bigint` global** — `hashtext(teks)` memetakan
string ke 32-bit yang dilebarkan Postgres ke `bigint`. Bila dua fitur memakai string
kunci yang sama (atau tanpa namespace yang membedakannya), keduanya saling memblokir
walau tak berhubungan — bahkan berpotensi deadlock.

## Peta pemakai advisory lock

| Berkas | Kunci | Namespace |
| --- | --- | --- |
| `OnlineBmt` | `"online-bmt:" + transactionNo` | ✅ |
| `PengadaanPosApiHelper` (sinkron BAST) | `"bast-sinkron:" + id` | ✅ |
| `InitIndex` | `'init:koperasi.produk:kebijakan_retur'` | ✅ |
| `CommonPMB` | `"PMB_NO_UJIAN_SAVE_" + id + "_" + noUjian` | ✅ |
| `PenggunaanAnggaran.lockRef` | **`ref` mentah** (tanpa prefiks) | ⚠️ |

Empat dari lima memberi prefiks namespace berbeda. Satu — `PenggunaanAnggaran.lockRef`
(modul RAB) — mengunci pada `ref` mentah.

## Yang dikerjakan (pengadaan, aman, perilaku identik)

String kunci BAST disentralkan ke satu metode:

```java
static String kunciSinkronBast(Long id) {
    return "bast-sinkron:" + id;   // identik dengan konkatenasi lama
}
```

Sebelumnya string `"bast-sinkron:" + id` ditulis kembar di sisi **lock** dan sisi
**unlock**. Bila salah satu disunting dan yang lain tidak, unlock meleset — kunci
hanya lepas saat koneksi ditutup (rapuh). Kini satu sumber kebenaran menutup celah
itu. Keluaran string tidak berubah (termasuk kasus `id == null` → `"bast-sinkron:null"`),
jadi tidak ada perubahan perilaku maupun risiko jendela rolling deploy.

Invarian dikunci `PengadaanBastLockSelfTest` (tanpa JUnit, tanpa DB, **11/11 LULUS**):
deterministik (lock == unlock), memuat id, membedakan BAST, prefiks `bast-sinkron:`
ada dan tidak menabrak namespace fitur lain (`online-bmt:`, `init:`, `PMB_NO_UJIAN_SAVE_`),
serta `id null` tetap stabil tanpa NPE. Kompilasi bersih (`javac` exit 0).

## Rekomendasi (lintas modul — TIDAK diubah di sini)

`PenggunaanAnggaran.lockRef` sebaiknya diberi prefiks namespace, mis.
`hashtext("rab-ref:" + ref)`, agar seluruh kunci advisory di basis kode berpola sama
dan tak mungkin bentrok lintas fitur bila kelak ada pemakai kunci mentah lain.

Sengaja **tidak** saya ubah pada dok ini karena: (1) berada di modul RAB, di luar
lingkup pengadaan/logistik yang diminta; (2) mengubah kunci menggeser hash sehingga
menuntut perhatian pada jendela deploy; (3) berkas RAB rawan disunting sesi paralel.
Ini keputusan pemilik. Risiko saat ini rendah karena empat pemakai lain sudah
ber-namespace sehingga tak ada kunci mentah lain yang bisa ditabrak `ref`.
