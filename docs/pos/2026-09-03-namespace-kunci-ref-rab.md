# 108. Kunci Advisory Lock RAB: Terapkan Prefiks Namespace `rab-ref:`

Tanggal: 3 September 2026  
Lingkungan: UAT lokal — bukan produksi  
Modul: RAB (`ais.database.model.rab.PenggunaanAnggaran`)  
Sifat: penutupan rekomendasi dok. 83 (namespacing kunci) + self-test regresi tanpa DB  
Rujukan: dok. 83 (konvensi namespace advisory lock)

## Latar

Dok. 83 mengaudit seluruh pemakai advisory lock PostgreSQL dan menemukan bahwa
**semua berbagi SATU ruang kunci `bigint` global** — `hashtext(teks)` memetakan
string ke 32-bit yang dilebarkan Postgres ke `bigint`. Empat dari lima pemakai
sudah memberi prefiks namespace (`online-bmt:`, `bast-sinkron:`, `init:`,
`PMB_NO_UJIAN_SAVE_`). Satu-satunya pengecualian adalah
`PenggunaanAnggaran.lockRef(Session, String)` yang mengunci pada **`ref` mentah**
tanpa prefiks, sehingga isi `ref` (yang bebas ditentukan modul lain) berpotensi
memetakan ke hash yang sama dengan kunci fitur lain dan saling memblokir walau tak
berhubungan — bahkan berpotensi deadlock.

Dok. 83 sengaja tidak mengubahnya (di luar lingkup pengadaan/logistik saat itu) dan
mencatatnya sebagai keputusan pemilik. Dok. ini menutup rekomendasi tersebut.

## Yang dikerjakan

String kunci disentralkan ke satu metode (sejalan idiom `kunciSinkronBast` di
`PengadaanPosApiHelper`), dan pengikatan parameter memakai kunci ber-namespace:

```java
static String kunciRef(String ref) {
    return "rab-ref:" + ref;   // prefiks namespace, bukan ref mentah
}
// lockRef:
session.createSQLQuery("select cast(pg_advisory_xact_lock(hashtext(:ref)) as text) as kunci")
        .addScalar("kunci", org.hibernate.Hibernate.STRING)
        .setString("ref", kunciRef(ref)).uniqueResult();   // dulu: setString("ref", ref)
```

Setelah perubahan ini, **kelima** pemakai advisory lock berpola sama (semua
ber-namespace):

| Berkas | Kunci | Namespace |
| --- | --- | --- |
| `OnlineBmt` | `"online-bmt:" + transactionNo` | ✅ |
| `PengadaanPosApiHelper` (sinkron BAST) | `"bast-sinkron:" + id` | ✅ |
| `InitIndex` | `'init:koperasi.produk:kebijakan_retur'` | ✅ |
| `CommonPMB` | `"PMB_NO_UJIAN_SAVE_" + id + "_" + noUjian` | ✅ |
| `PenggunaanAnggaran.lockRef` | `"rab-ref:" + ref` | ✅ (dulu ⚠️) |

## Audit pemanggil (agar konsisten)

`lockRef` hanya dipanggil dari satu tempat: `saveOrUpdateByRef(...)`, tepat sebelum
`removeDuplicateRowsByRef`/`findPenggunaanAnggaranByRef`. Kuncinya
**`pg_advisory_xact_lock`** — kunci bertransaksi yang **lepas otomatis di akhir
transaksi**, jadi tidak ada sisi *unlock* terpisah yang bisa menyimpang dari sisi
*lock* (berbeda dengan idiom `pg_advisory_lock`/`pg_advisory_unlock` di `OnlineBmt`
dan sisi sinkron BAST). Tidak ada penulis kunci `ref` lain di basis kode. Karena
itu cukup satu titik pengikatan yang diberi prefiks; konsistensi terjaga.

## Catatan jendela rolling deploy

Mengganti kunci dari `hashtext(ref)` menjadi `hashtext("rab-ref:" + ref)`
**menggeser nilai hash**. Selama rolling deploy, node lama (mengunci pada `ref`) dan
node baru (mengunci pada `rab-ref:` + `ref`) memakai `bigint` kunci yang berbeda,
sehingga untuk `ref` yang sama **keduanya tidak saling menserialkan** pada jendela
transisi — dua proses bersamaan (satu di node lama, satu di node baru) bisa lolos
serialisasi.

Risiko jendela ini **kecil**: (1) kuncinya `pg_advisory_xact_lock` yang bertransaksi
dan berumur sangat singkat (hanya selama transaksi tulis ref, bukan sepanjang
koneksi); (2) sudah ada jaring pengaman berlapis di jalur yang sama —
`removeDuplicateRowsByRef` + retry pada `isDuplicateRefException`/
`isStaleStateException` + constraint unik `ref_penggunaan_anggaran`; (3) ini
**UAT, bukan produksi** sehingga tidak ada rolling deploy multi-node berjalan.
Dicatat di sini agar diperhatikan bila kelak dinaikkan ke produksi (mis. drain
node lama sebelum node baru menerima trafik, atau terima jendela singkat karena
lapisan pengaman lain menutupnya).

## Self-test (tanpa JUnit, tanpa DB)

`PenggunaanAnggaranLockSelfTest` (paket `ais.database.model.rab`) mengunci invarian
kunci — mengikuti pola `PengadaanBastLockSelfTest`/`DistribusiPengirimanSelfTest`:
deterministik, memuat `ref`, membedakan `ref`, prefiks `rab-ref:` ada dan tidak
menabrak namespace fitur lain, `ref` yang kebetulan sama persis dengan kunci utuh
fitur lain tetap tak menabrak setelah diberi prefiks, serta `null` stabil tanpa NPE.

Dikompilasi `javac` terhadap classpath deploy Tomcat
(`WEB-INF/{classes,lib/*}`), bukan Maven — **exit 0** (hanya catatan deprecation).
Dijalankan: **18/18 LULUS**, exit 0.

## Jejak commit (SVN `^/src`)

- `PenggunaanAnggaranLockSelfTest.java` — r83945
- `PenggunaanAnggaran.java` (kunciRef + lockRef ber-namespace) — r83947

Kedua working copy kembar (`java/` dan `src/`, dua-duanya `^/ais/src`) diselaraskan
via `svn update`.
