# Standar Provisioning Tenant Baru eBisnis POS: Toko Default, Akun Kasir/Admin, dan Sinkronisasi Produk

Dokumen ini adalah SOP dan checklist wajib teknis setiap kali mendaftarkan atau mengonfigurasi **Tenant Baru** pada ekosistem eBisnis POS (Desktop, Mobile, dan Backend), agar tidak ada langkah yang terlewat dan aplikasi POS langsung siap digunakan tanpa kendala katalog kosong atau kegagalan autentikasi.

---

## 1. Aturan Wajib Tenant Baru (Checklist Standar)

Setiap tenant baru yang didaftarkan wajib memenuhi 4 pilar dasar:

1. **Minimal Memiliki 1 Toko Default**
   - Secara default, nama toko disamakan dengan **nama Tenant**.
   - Toko harus tercatat pada tabel `koperasi.toko` (relasi multi-toko backend) dengan field `pendaftar = <id_pendaftar_tenant>`.
   - Jika tenant menggunakan schema terisolasi (misal `{tenant_slug}.toko`), toko juga harus dicatatkan di schema tersebut.
   - Atribut toko default wajib:
     - `aktif`: `true`
     - `boleh_transaksi_stok_habis`: `true` (memungkinkan penjualan saat stok awal belum selesai di-opname)
     - `semua_boleh_ubah_harga`: `true` (atau sesuai kebijakan tenant)
     - `unit_usaha_json`: `'["RESTORAN_KANTIN"]'` (atau unit usaha terkait)

2. **Minimal Memiliki 1 Akun Admin dan 1 Akun Kasir**
   - **Akun Admin Tenant**:
     - Role: `am` (Admin Penuh)
     - Terhubung ke `pendaftar = <id_pendaftar_tenant>`
     - Mengarah ke toko default: `toko_aktif_multi_toko = <id_toko_default>`
   - **Akun Kasir Tenant**:
     - Role: `Kantin` (atau `am` jika membutuhkan akses manajemen penuh pada POS)
     - Terhubung ke `pendaftar = <id_pendaftar_tenant>`
     - Mengarah ke toko default: `toko_aktif_multi_toko = <id_toko_default>`
   - Standar kredensial awal (uji coba): kata sandi default `123` (dienkripsi menggunakan DES AIS: `QgUsCfRMbe4=`).

3. **Sinkronisasi Katalog Produk Langsung ke Toko Default**
   - Backend `PosApi` menyaring katalog produk melalui relasi `koperasi.produk` dengan filter `toko = <id_toko_default>` dan `toko.pendaftar = <id_pendaftar>`.
   - Semua produk awal tenant harus masuk ke tabel `koperasi.produk` dengan kolom `toko` yang mengarah tepat ke `<id_toko_default>`.
   - Pastikan nama produk, kode, barcode, harga jual (`hargajual`), dan harga beli (`hargabeli`) lengkap.

4. **Izin Penjualan Minus Stok (Minus Stok Diizinkan)**
   - Pada masa onboarding / uji coba tenant baru, seluruh produk diset:
     - `izinkan_jual_minus_stok = true` pada tabel `koperasi.produk`.
     - `boleh_transaksi_stok_habis = true` pada tabel `koperasi.toko`.
   - Hal ini memastikan kasir dapat langsung melakukan transaksi tanpa diblokir oleh validasi stok nol.

---

## 2. Blueprint SQL Template Provisioning Tenant Baru

Jalankan script template berikut di PostgreSQL (`database: ebisnis`) dengan menyesuaikan variabel tenant:

```sql
-- ============================================================================
-- SCRIPT TEMPLATE PROVISIONING TENANT BARU
-- Variabel:
--   :tenant_slug       := 'sarimpijaya'
--   :tenant_name       := 'Sarimpi Jaya Frozen'
--   :pendaftar_id      := 11
--   :default_toko_id   := 7
--   :admin_username    := 'admin_sarimpi'
--   :kasir_username    := 'kasir_sarimpi'
--   :default_password  := '123' (DES Hash: 'QgUsCfRMbe4=')
-- ============================================================================

BEGIN;

-- 1. Toko Default di Schema koperasi.toko
INSERT INTO koperasi.toko (
    id, nama, kode, pendaftar, aktif,
    boleh_transaksi_stok_habis, semua_boleh_ubah_harga,
    unit_usaha_json, tanggal_dirubah, oleh
) VALUES (
    7, 
    'Sarimpi Jaya Frozen', 
    'SARIMPI-001', 
    11, 
    true,
    true, 
    true,
    '["RESTORAN_KANTIN"]', 
    NOW(), 
    'admin'
) ON CONFLICT (id) DO UPDATE SET
    nama = EXCLUDED.nama,
    kode = EXCLUDED.kode,
    pendaftar = EXCLUDED.pendaftar,
    aktif = true,
    boleh_transaksi_stok_habis = true,
    semua_boleh_ubah_harga = true;

-- 2. Toko di Schema Tenant (Bila tenant memiliki schema terisolasi)
INSERT INTO sarimpijaya.toko (
    id, nama, kode, aktif, tanggal_dirubah, oleh
) VALUES (
    7, 
    'Sarimpi Jaya Frozen', 
    'SARIMPI-001', 
    true, 
    NOW(), 
    'admin'
) ON CONFLICT (id) DO UPDATE SET
    nama = EXCLUDED.nama,
    kode = EXCLUDED.kode,
    aktif = true;

-- 3. Akun Admin Tenant (Role 'am')
INSERT INTO public.tbmuser (
    userid, usernama, userpassword, userrole, 
    toko_aktif_multi_toko, pendaftar, aktif, tanggal_dirubah, oleh
) VALUES (
    'admin_sarimpi', 
    'Admin Sarimpi Jaya', 
    'QgUsCfRMbe4=', 
    'am', 
    7, 
    11, 
    true, 
    NOW(), 
    'admin'
) ON CONFLICT (userid) DO UPDATE SET
    usernama = EXCLUDED.usernama,
    userpassword = EXCLUDED.userpassword,
    userrole = EXCLUDED.userrole,
    toko_aktif_multi_toko = EXCLUDED.toko_aktif_multi_toko,
    pendaftar = EXCLUDED.pendaftar,
    is_encripted = null,
    aktif = true;

-- 4. Akun Kasir Tenant (Role 'Kantin' atau 'am')
INSERT INTO public.tbmuser (
    userid, usernama, userpassword, userrole, 
    toko_aktif_multi_toko, pendaftar, aktif, tanggal_dirubah, oleh
) VALUES (
    'kasir_sarimpi', 
    'Kasir Sarimpi Jaya', 
    'QgUsCfRMbe4=', 
    'Kantin', 
    7, 
    11, 
    true, 
    NOW(), 
    'admin'
) ON CONFLICT (userid) DO UPDATE SET
    usernama = EXCLUDED.usernama,
    userpassword = EXCLUDED.userpassword,
    userrole = EXCLUDED.userrole,
    toko_aktif_multi_toko = EXCLUDED.toko_aktif_multi_toko,
    pendaftar = EXCLUDED.pendaftar,
    is_encripted = null,
    aktif = true;

-- 5. Sinkronisasi Katalog Produk ke Toko Default & Izinkan Minus Stok
INSERT INTO koperasi.produk (
    id, aktif, nama, kode, barcode, hargabeli, hargajual, toko,
    izinkan_jual_minus_stok, stok, stok_minimum, jenis_item, tanggal_dirubah, oleh
)
SELECT
    p.id,
    true,
    p.nama,
    p.kode,
    p.barcode,
    p.harga_beli_terakhir,
    p.harga_jual_standar,
    7,     -- default_toko_id
    true,  -- izinkan_jual_minus_stok = true (Wajib)
    100,   -- stok awal default
    p.stok_minimum,
    'JUAL',
    NOW(),
    'admin'
FROM sarimpijaya.produk p
ON CONFLICT (id) DO UPDATE SET
    nama = EXCLUDED.nama,
    kode = EXCLUDED.kode,
    barcode = EXCLUDED.barcode,
    hargabeli = EXCLUDED.hargabeli,
    hargajual = EXCLUDED.hargajual,
    toko = EXCLUDED.toko,
    izinkan_jual_minus_stok = true,
    aktif = true;

COMMIT;
```

---

## 3. Catatan Penting Mengenai Cache Server & Autentikasi

1. **Enkripsi Sandi eBisnis**:
   - String sandi disimpan terenkripsi dengan algoritma DES key `coreSDP` (`ais.common.DesEncrypter`).
   - Sandi `123` = `QgUsCfRMbe4=`.
   - Kolom `is_encripted` pada `public.tbmuser` disarankan bernilai `null` agar mekanisme filter autentikasi mencocokkan hash secara konsisten.
2. **Tomcat In-Memory Cache (Hibernate Session)**:
   - Jika kredensial kasir/admin diubah langsung pada level PostgreSQL saat server Tomcat sedang running, Hibernate Session / EHCache mungkin masih menyimpan state objek pengguna lama.
   - Bila login menghasilkan pesan *"Nama pengguna atau kata sandi tidak valid"*, lakukan refresh session dengan merestart service Tomcat eBisnis secara bersih:
     ```bash
     /backup4/tomcat_ebisnis/bin/shutdown.sh 10 -force
     /backup4/tomcat_ebisnis/bin/startup.sh
     ```
3. **Verifikasi API Endpoint**:
   - Uji login endpoint:
     ```bash
     curl -s -X POST -H "Content-Type: application/json" \
       -d '{"action":"login","username":"kasir_sarimpi","password":"123","labelPerangkat":"Test"}' \
       https://{subdomain}.ebisnis.id/ebisnis/Api_eBisnis
     ```
   - Uji katalog produk:
     ```bash
     curl -s -X POST \
       -H "Authorization: Bearer <TOKEN>" \
       -H "X-Tenant-Id: <TENANT_ID>" \
       -H "Content-Type: application/json" \
       -d '{"action":"katalog","tokoId":<TOKO_ID>}' \
       https://{subdomain}.ebisnis.id/ebisnis/Api_eBisnis
     ```
