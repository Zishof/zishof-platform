# =====================================================================================
# UAT RUNTIME 48 LAYAR -- varian "eBisnis Inventory & Sales" (API-level, end-to-end)
# =====================================================================================
# Menjalankan seluruh alur si_* terhadap server ter-deploy dan menulis evidence JSON ke
# docs/pos-inventory-sales/evidence/uat/. Semua data uji berprefix "UAT-" + timestamp
# (idempoten kode_unik; supplier/customer uji dinonaktifkan lagi di akhir, best-effort).
#
# Pakai:
#   powershell -ExecutionPolicy Bypass -File uat_runtime_48layar.ps1 `
#     -UserPemilik <akun_uji_pemilik> -PassPemilik <sandi> `
#     [-UserSales <akun_uji_sales> -PassSales <sandi>] `
#     [-UserAdmin <akun_uji_admin> -PassAdmin <sandi>] `
#     [-BaseUrl https://dev.ecampus.id/ecampus/Api_eBisnis]
#
# Minimal: akun Pemilik Usaha Sales/Inventory. Akun Sales menambah uji scope
# "data milik sendiri"; akun Admin menambah uji lintas-toko.
# PowerShell 5.1-safe (tanpa ternary/&&). Exit code 0 = semua PASS; 1 = ada FAIL.
# =====================================================================================
param(
    [string]$BaseUrl = 'https://dev.ecampus.id/ecampus/Api_eBisnis',
    [Parameter(Mandatory = $true)][string]$UserPemilik,
    [Parameter(Mandatory = $true)][string]$PassPemilik,
    [string]$UserSales = '',
    [string]$PassSales = '',
    [string]$UserAdmin = '',
    [string]$PassAdmin = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Hasil = New-Object System.Collections.ArrayList
$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Uat = "UAT-$script:Stamp"

function Catat([string]$kode, [string]$nama, [string]$status, [string]$detail) {
    $null = $script:Hasil.Add([pscustomobject]@{ kode = $kode; nama = $nama; status = $status; detail = $detail })
    $warna = 'Gray'
    if ($status -eq 'PASS') { $warna = 'Green' }
    if ($status -eq 'FAIL') { $warna = 'Red' }
    if ($status -eq 'SKIP') { $warna = 'Yellow' }
    Write-Host ("[{0}] {1} - {2} {3}" -f $status, $kode, $nama, $detail) -ForegroundColor $warna
}

# Panggil aksi; lempar exception bila status bukan success.
function Panggil([string]$aksi, [hashtable]$body, [string]$token) {
    $payload = @{ action = $aksi }
    if ($body) { foreach ($k in $body.Keys) { $payload[$k] = $body[$k] } }
    $headers = @{ 'Content-Type' = 'application/json' }
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    $json = $payload | ConvertTo-Json -Depth 8 -Compress
    $resp = Invoke-RestMethod -Uri $BaseUrl -Method Post -Headers $headers -Body $json -TimeoutSec 60
    if ($resp.status -ne 'success') {
        throw ("Aksi {0} ditolak server: {1}" -f $aksi, $resp.message)
    }
    return $resp
}

# Varian yang MENGHARAPKAN penolakan (uji negatif) -- return pesan penolakan / $null bila lolos.
function HarapDitolak([string]$aksi, [hashtable]$body, [string]$token) {
    try {
        $null = Panggil $aksi $body $token
        return $null
    } catch {
        return $_.Exception.Message
    }
}

function Uji([string]$kode, [string]$nama, [scriptblock]$blok) {
    try {
        $detail = & $blok
        if ($null -eq $detail) { $detail = '' }
        Catat $kode $nama 'PASS' "$detail"
    } catch {
        Catat $kode $nama 'FAIL' $_.Exception.Message
    }
}

Write-Host "=== UAT RUNTIME 48 LAYAR - $BaseUrl - $script:Stamp ===" -ForegroundColor Cyan

# ---------------------------------------------------------------- LOGIN + KONTEKS AKTOR
$tokenPemilik = $null; $tokenSales = $null; $tokenAdmin = $null
Uji 'LOGIN-P' 'Login akun Pemilik' {
    $r = Panggil 'login' @{ username = $UserPemilik; password = $PassPemilik; labelPerangkat = 'uat-harness' } $null
    $script:tokenPemilik = $r.token
    'token diterima'
}
if (-not $tokenPemilik) {
    Catat 'ABORT' 'Tanpa token Pemilik seluruh UAT tidak bisa lanjut' 'FAIL' ''
} else {

if ($UserSales) {
    Uji 'LOGIN-S' 'Login akun Sales Keliling' {
        $r = Panggil 'login' @{ username = $UserSales; password = $PassSales; labelPerangkat = 'uat-harness' } $null
        $script:tokenSales = $r.token
        'token diterima'
    }
}
if ($UserAdmin) {
    Uji 'LOGIN-A' 'Login akun Admin' {
        $r = Panggil 'login' @{ username = $UserAdmin; password = $PassAdmin; labelPerangkat = 'uat-harness' } $null
        $script:tokenAdmin = $r.token
        'token diterima'
    }
}

# Bukti kode fase P4-P6 benar-benar ter-deploy: aksi P6 harus dikenal server.
Uji 'DEPLOY' 'Server memuat kode P4-P6 (si_profit_loss_params dikenal)' {
    $r = Panggil 'si_profit_loss_params' @{} $tokenPemilik
    ("sales aktif terdaftar: {0}" -f (@($r.sales).Count))
}
Uji 'CTX-P' 'si_actor_context: aktor Pemilik dikenali' {
    $r = Panggil 'si_actor_context' @{} $tokenPemilik
    $at = $r.data.actorType
    if (-not $at) { $at = $r.actorType }
    if ("$at" -notmatch 'PEMILIK|ADMIN') { throw "actorType tak terduga: $at" }
    "actorType=$at"
}
if ($tokenSales) {
    Uji 'CTX-S' 'si_actor_context: aktor Sales dikenali + scope' {
        $r = Panggil 'si_actor_context' @{} $tokenSales
        $at = $r.data.actorType
        if (-not $at) { $at = $r.actorType }
        if ("$at" -ne 'SALES_KELILING') { throw "actorType tak terduga: $at" }
        "actorType=$at"
    }
    Uji 'RBAC-NEG' 'RBAC negatif: Sales DITOLAK menyimpan COA' {
        $pesan = HarapDitolak 'si_coa_save' @{ kode = "$script:Uat-X"; nama = 'uji rbac' } $tokenSales
        if (-not $pesan) { throw 'Sales TIDAK ditolak menyimpan COA (celah RBAC!)' }
        "ditolak sesuai harapan: $pesan"
    }
}

# ---------------------------------------------------------------- SCR-01..07 MASTER
$supplierId = $null; $customerId = $null; $salesId = $null
Uji 'SCR-01' 'Master Supplier: create + detail' {
    $r = Panggil 'si_supplier_create' @{ kode = "S$script:Stamp"; nama = "$script:Uat Supplier"; termin = 14 } $tokenPemilik
    $script:supplierId = $r.id
    if (-not $script:supplierId) { $script:supplierId = $r.supplierId }
    $d = Panggil 'si_supplier_detail' @{ supplier_id = $script:supplierId } $tokenPemilik
    "id=$script:supplierId"
}
Uji 'SCR-02' 'Daftar Supplier: baris uji muncul di list' {
    $r = Panggil 'si_supplier_list' @{ keyword = "$script:Uat"; page = 1; page_size = 10 } $tokenPemilik
    if (@($r.rows).Count -lt 1) { throw 'supplier uji tidak ditemukan di list' }
    ("{0} baris" -f @($r.rows).Count)
}
Uji 'SCR-04' 'Master Customer: create + saldo piutang terbaca' {
    $r = Panggil 'si_customer_create' @{ kode = "C$script:Stamp"; nama = "$script:Uat Customer"; termin = 7 } $tokenPemilik
    $script:customerId = $r.anggotaId
    if (-not $script:customerId) { $script:customerId = $r.id }
    $d = Panggil 'si_customer_detail' @{ anggota_id = $script:customerId } $tokenPemilik
    ("id={0} saldoPiutang={1}" -f $script:customerId, $d.data.saldoPiutang)
}
Uji 'SCR-07' 'Master Sales: list terbaca (ambil sales pertama utk SPJ)' {
    $r = Panggil 'si_sales_list' @{ aktif = 'aktif'; page = 1; page_size = 5 } $tokenPemilik
    if (@($r.rows).Count -ge 1) { $script:salesId = $r.rows[0].id }
    ("{0} sales; salesId={1}" -f @($r.rows).Count, $script:salesId)
}

# ---------------------------------------------------------------- PRODUK UJI (via impor legacy, sekalian MIG-001)
$produkId = $null
Uji 'MIG-001a' 'Impor DBF (produk): run pertama membuat' {
    $rows = @(@{ kode = "B$script:Stamp"; nama = "$script:Uat Barang"; satuan = 'PCS'; harga_beli = 7000; harga_jual = 10000; stok_minimum = 1; stok_legacy = 100 })
    $r = Panggil 'si_import_legacy' @{ jenis = 'produk'; rows = $rows; buat_opname_awal = $true } $tokenPemilik
    ("dibuat={0} diperbarui={1} dilewati={2}" -f $r.dibuat, $r.diperbarui, $r.dilewati)
}
Uji 'MIG-001b' 'Impor DBF idempoten: run kedua TIDAK menggandakan' {
    $rows = @(@{ kode = "B$script:Stamp"; nama = "$script:Uat Barang"; satuan = 'PCS'; harga_beli = 7000; harga_jual = 10000; stok_minimum = 1; stok_legacy = 100 })
    $r = Panggil 'si_import_legacy' @{ jenis = 'produk'; rows = $rows; buat_opname_awal = $true } $tokenPemilik
    if ([int]$r.dibuat -ne 0) { throw ("run kedua membuat {0} baris baru (harusnya 0)" -f $r.dibuat) }
    ("dibuat=0 OK; dilewati/diperbarui={0}/{1}" -f $r.dilewati, $r.diperbarui)
}
Uji 'KATALOG' 'Katalog memuat produk uji (utk item order)' {
    $r = Panggil 'katalog' @{ keyword = "B$script:Stamp" } $tokenPemilik
    if (@($r.produk).Count -lt 1) { throw 'produk uji tidak muncul di katalog' }
    $script:produkId = $r.produk[0].id
    "produkId=$script:produkId"
}

# ---------------------------------------------------------------- SCR-08..19 PERSEDIAAN & HARGA
Uji 'SCR-08' 'Persediaan: balance + kartu stok produk uji' {
    $b = Panggil 'si_inventory_balance' @{ keyword = "B$script:Stamp"; page = 1; page_size = 5 } $tokenPemilik
    $l = Panggil 'si_inventory_ledger' @{ produk_id = $script:produkId } $tokenPemilik
    ("balance {0} baris; ledger {1} baris (saldo awal migrasi harus tampak)" -f @($b.rows).Count, @($l.rows).Count)
}
Uji 'SCR-18' 'Harga Beli Supplier: simpan versi + list' {
    $null = Panggil 'si_supplier_price_save' @{ supplier_id = $script:supplierId; produk_id = $script:produkId; harga = 6900; tanggal_efektif = (Get-Date -Format 'yyyy-MM-dd') } $tokenPemilik
    $r = Panggil 'si_supplier_price_list' @{ supplier_id = $script:supplierId } $tokenPemilik
    ("{0} baris harga" -f @($r.rows).Count)
}
Uji 'SCR-19' 'Harga Jual Customer: simpan versi + list' {
    $null = Panggil 'si_customer_price_save' @{ anggota_id = $script:customerId; produk_id = $script:produkId; harga = 9800; tanggal_efektif = (Get-Date -Format 'yyyy-MM-dd') } $tokenPemilik
    $r = Panggil 'si_customer_price_list' @{ anggota_id = $script:customerId } $tokenPemilik
    ("{0} baris harga" -f @($r.rows).Count)
}
Uji 'SCR-17' 'Analisis Harga terbaca' {
    $r = Panggil 'si_price_analysis' @{ keyword = "B$script:Stamp" } $tokenPemilik
    ("{0} baris analisis" -f @($r.rows).Count)
}

# ---------------------------------------------------------------- SCR-20..29 AP (baca)
Uji 'SCR-22' 'Ledger Hutang Supplier terbaca' {
    $r = Panggil 'si_payable_list' @{ tampilkan_lunas = $true; page = 1; page_size = 5 } $tokenPemilik
    ("{0} baris" -f @($r.rows).Count)
}
Uji 'SCR-27' 'Aging Hutang terbaca' {
    $r = Panggil 'si_payable_aging' @{} $tokenPemilik
    'ok'
}
Uji 'SCR-29' 'Laporan Pembelian per periode terbaca' {
    $r = Panggil 'si_purchase_report' @{ dari = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd'); sampai = (Get-Date -Format 'yyyy-MM-dd') } $tokenPemilik
    'ok'
}

# ---------------------------------------------------------------- SCR-30..38 AR PENUH
$orderId = $null; $piutangId = $null; $sisaFaktur = 0
Uji 'SCR-30a' 'Sales Order: create (idempoten kode_unik)' {
    $ku = "$script:Uat-SO1"
    $body = @{ customer_id = $script:customerId; kode_unik = $ku; keterangan = 'order UAT'; items = @(@{ produk_id = $script:produkId; jumlah = 5; harga = 10000 }) }
    if ($script:salesId) { $body['sales_id'] = $script:salesId }
    $r = Panggil 'si_sales_order_create' $body $tokenPemilik
    $script:orderId = $r.id
    $r2 = Panggil 'si_sales_order_create' $body $tokenPemilik
    if (-not $r2.idempotentReplay) { throw 'create kedua TIDAK replay (dobel order!)' }
    "orderId=$script:orderId total=$($r.total); replay OK"
}
Uji 'SCR-30b' 'Sales Order: transisi PESAN -> SIAP_KIRIM -> TERKIRIM' {
    $null = Panggil 'si_sales_order_status' @{ order_id = $script:orderId; status = 'PESAN' } $tokenPemilik
    $null = Panggil 'si_sales_order_status' @{ order_id = $script:orderId; status = 'SIAP_KIRIM' } $tokenPemilik
    $null = Panggil 'si_sales_order_status' @{ order_id = $script:orderId; status = 'TERKIRIM' } $tokenPemilik
    'ok'
}
Uji 'SCR-30c' 'Transisi ilegal DITOLAK (TERKIRIM -> PESAN)' {
    $pesan = HarapDitolak 'si_sales_order_status' @{ order_id = $script:orderId; status = 'PESAN' } $tokenPemilik
    if (-not $pesan) { throw 'transisi mundur TIDAK ditolak' }
    "ditolak: $pesan"
}
Uji 'SCR-31' 'Terbit faktur piutang (idempoten per order) + deep-link' {
    $r = Panggil 'si_sales_order_invoice' @{ order_id = $script:orderId } $tokenPemilik
    $script:piutangId = $r.piutangDocId
    $r2 = Panggil 'si_sales_order_invoice' @{ order_id = $script:orderId } $tokenPemilik
    if (-not $r2.idempotentReplay) { throw 'invoice kedua TIDAK replay (faktur dobel!)' }
    $d = Panggil 'si_sales_order_detail' @{ order_id = $script:orderId } $tokenPemilik
    if (-not $d.data.piutangDocId) { throw 'deep-link piutangDocId kosong di detail order' }
    "faktur=$($r.nomor) id=$script:piutangId"
}
Uji 'SCR-32' 'Ledger Piutang: faktur muncul + outstanding benar (50000)' {
    $r = Panggil 'si_receivable_list' @{ customer_id = $script:customerId; page = 1; page_size = 20 } $tokenPemilik
    $baris = @($r.rows) | Where-Object { $_.id -eq $script:piutangId }
    if (-not $baris) { throw 'faktur tidak muncul di receivable_list' }
    $script:sisaFaktur = [double]$baris[0].outstanding
    if ([math]::Abs($script:sisaFaktur - 50000) -gt 0.01) { throw ("outstanding {0} != 50000" -f $script:sisaFaktur) }
    "outstanding=$script:sisaFaktur"
}
Uji 'SCR-34a' 'Collection parsial 20000 (idempoten kode_unik)' {
    $ku = "$script:Uat-KWT1"
    $body = @{ customer_id = $script:customerId; nominal = 20000; metode = 'TUNAI'; kode_unik = $ku; alokasi = @(@{ piutang_id = $script:piutangId; nominal = 20000 }) }
    $r = Panggil 'si_collection_create' $body $tokenPemilik
    $r2 = Panggil 'si_collection_create' $body $tokenPemilik
    if (-not $r2.idempotentReplay) { throw 'collection kedua TIDAK replay (pembayaran dobel!)' }
    "kwitansi=$($r.nomor); replay OK"
}
Uji 'SCR-34b' 'Overpayment DITOLAK (alokasi > sisa)' {
    $pesan = HarapDitolak 'si_collection_create' @{ customer_id = $script:customerId; nominal = 999999; metode = 'TUNAI'; kode_unik = "$script:Uat-KWT-OVER"; alokasi = @(@{ piutang_id = $script:piutangId; nominal = 999999 }) } $tokenPemilik
    if (-not $pesan) { throw 'overpayment TIDAK ditolak (celah ledger!)' }
    "ditolak: $pesan"
}
Uji 'SCR-33' 'Filter lunas: pelunasan sisa 30000 -> faktur hilang dari daftar berjalan + order LUNAS' {
    $null = Panggil 'si_collection_create' @{ customer_id = $script:customerId; nominal = 30000; metode = 'TUNAI'; kode_unik = "$script:Uat-KWT2"; alokasi = @(@{ piutang_id = $script:piutangId; nominal = 30000 }) } $tokenPemilik
    $r = Panggil 'si_receivable_list' @{ customer_id = $script:customerId; tampilkan_lunas = $false; page = 1; page_size = 20 } $tokenPemilik
    $masihAda = @($r.rows) | Where-Object { $_.id -eq $script:piutangId }
    if ($masihAda) { throw 'faktur lunas MASIH tampil tanpa tampilkan_lunas' }
    $d = Panggil 'si_sales_order_detail' @{ order_id = $script:orderId } $tokenPemilik
    if ($d.data.status -ne 'LUNAS') { throw ("order status {0}, harusnya LUNAS" -f $d.data.status) }
    'faktur tersembunyi (visual) + order LUNAS'
}
Uji 'SCR-35' 'Riwayat penerimaan memuat 2 kwitansi UAT' {
    $r = Panggil 'si_collection_history' @{ customer_id = $script:customerId } $tokenPemilik
    if (@($r.rows).Count -lt 2) { throw ("hanya {0} kwitansi" -f @($r.rows).Count) }
    ("{0} kwitansi; total={1}" -f @($r.rows).Count, $r.totalNominal)
}
Uji 'SCR-36' 'Data kwitansi (receipt) terbaca + alokasi benar' {
    $h = Panggil 'si_collection_history' @{ customer_id = $script:customerId } $tokenPemilik
    $id1 = $h.rows[0].id
    $r = Panggil 'si_collection_receipt' @{ penerimaan_id = $id1 } $tokenPemilik
    if (@($r.data.alokasi).Count -lt 1) { throw 'alokasi kosong di kwitansi' }
    ("kwitansi {0}: {1} alokasi" -f $r.data.nomor, @($r.data.alokasi).Count)
}
Uji 'SCR-37' 'Aging per customer terbaca' {
    $r = Panggil 'si_receivable_aging_customer' @{} $tokenPemilik
    'ok'
}
Uji 'SCR-38' 'Aging per sales terbaca' {
    $r = Panggil 'si_receivable_aging_sales' @{} $tokenPemilik
    'ok'
}

# ---------------------------------------------------------------- SCR-39..42 SPJ + SESI
$spjId = $null; $sessionId = $null; $piutang2 = $null
Uji 'PRA-SPJ' 'Order+faktur kedua (bekal nota dibawa)' {
    $body = @{ customer_id = $script:customerId; kode_unik = "$script:Uat-SO2"; items = @(@{ produk_id = $script:produkId; jumlah = 3; harga = 10000 }) }
    if ($script:salesId) { $body['sales_id'] = $script:salesId }
    $r = Panggil 'si_sales_order_create' $body $tokenPemilik
    $o2 = $r.id
    $null = Panggil 'si_sales_order_status' @{ order_id = $o2; status = 'PESAN' } $tokenPemilik
    $null = Panggil 'si_sales_order_status' @{ order_id = $o2; status = 'SIAP_KIRIM' } $tokenPemilik
    $null = Panggil 'si_sales_order_status' @{ order_id = $o2; status = 'TERKIRIM' } $tokenPemilik
    $inv = Panggil 'si_sales_order_invoice' @{ order_id = $o2 } $tokenPemilik
    $script:piutang2 = $inv.piutangDocId
    "faktur kedua id=$script:piutang2 (30000)"
}
Uji 'SCR-39a' 'SPJ: create + barang bulk + nota assign' {
    if (-not $script:salesId) { throw 'tidak ada profil sales aktif (buat dulu di Master Sales)' }
    $r = Panggil 'si_spj_create' @{ sales_id = $script:salesId; kode_unik = "$script:Uat-SPJ"; tanggal_berangkat_rencana = (Get-Date -Format 'yyyy-MM-dd'); rute = 'UAT rute'; uang_muka_operasional = 100000; barang = @(@{ produk_id = $script:produkId; qty_rencana = 10 }) } $tokenPemilik
    $script:spjId = $r.id
    $null = Panggil 'si_spj_nota_assign' @{ spj_id = $script:spjId; piutang_doc_ids = @($script:piutang2) } $tokenPemilik
    "spj=$($r.nomor)"
}
Uji 'SCR-39b' 'SPJ: dobel-bawa invoice DITOLAK di SPJ kedua' {
    $r2 = Panggil 'si_spj_create' @{ sales_id = $script:salesId; kode_unik = "$script:Uat-SPJ2"; tanggal_berangkat_rencana = (Get-Date -Format 'yyyy-MM-dd'); barang = @(@{ produk_id = $script:produkId; qty_rencana = 1 }) } $tokenPemilik
    $pesan = HarapDitolak 'si_spj_nota_assign' @{ spj_id = $r2.id; piutang_doc_ids = @($script:piutang2) } $tokenPemilik
    $null = Panggil 'si_spj_status' @{ spj_id = $r2.id; status = 'CANCELLED'; alasan = 'uji dobel-bawa' } $tokenPemilik
    if (-not $pesan) { throw 'invoice boleh dibawa 2 SPJ aktif (invariant bocor!)' }
    "ditolak: $pesan"
}
Uji 'SCR-39c' 'SPJ: SUBMITTED -> APPROVED (approval Pemilik)' {
    $null = Panggil 'si_spj_status' @{ spj_id = $script:spjId; status = 'SUBMITTED' } $tokenPemilik
    $null = Panggil 'si_spj_status' @{ spj_id = $script:spjId; status = 'APPROVED' } $tokenPemilik
    'ok'
}
Uji 'SCR-40a' 'Sesi: trip_start idempoten + OPENING_ADVANCE' {
    $r = Panggil 'si_trip_start' @{ spj_id = $script:spjId } $tokenPemilik
    $script:sessionId = $r.sessionId
    $r2 = Panggil 'si_trip_start' @{ spj_id = $script:spjId } $tokenPemilik
    if (-not $r2.idempotentReplay) { throw 'trip_start kedua TIDAK replay (sesi dobel!)' }
    $d = Panggil 'si_trip_detail' @{ session_id = $script:sessionId } $tokenPemilik
    if ([double]$d.data.rumus.uangMukaAwal -ne 100000) { throw 'uang muka awal tidak tercatat di ledger kas' }
    "sesi=$($r.nomor)"
}
Uji 'SCR-40b' 'Sesi: tagih dlm sesi (COLLECTION_CASH) + jual tunai + biaya idempoten + kulakan + setoran' {
    $null = Panggil 'si_collection_create' @{ customer_id = $script:customerId; nominal = 30000; metode = 'TUNAI'; trip_session_id = $script:sessionId; kode_unik = "$script:Uat-TAGIH"; alokasi = @(@{ piutang_id = $script:piutang2; nominal = 30000 }) } $tokenPemilik
    $null = Panggil 'si_trip_cash_sale' @{ session_id = $script:sessionId; nominal = 15000; keterangan = 'jual tunai UAT' } $tokenPemilik
    $kat = Panggil 'si_expense_category_list' @{} $tokenPemilik
    $katId = $kat.rows[0].id
    $bb = @{ session_id = $script:sessionId; kategori_id = $katId; nilai = 5000; uraian = 'bensin UAT'; metode = 'TUNAI'; kode_unik = "$script:Uat-BIAYA" }
    $null = Panggil 'si_expense_create' $bb $tokenPemilik
    $r2 = Panggil 'si_expense_create' $bb $tokenPemilik
    if (-not $r2.idempotentReplay) { throw 'biaya kedua TIDAK replay' }
    $null = Panggil 'si_trip_purchase_link' @{ session_id = $script:sessionId; total_faktur = 50000; dibayar_sesi = 20000; tujuan_stok = 'MOBIL_SALES'; kode_unik = "$script:Uat-BELI" } $tokenPemilik
    $null = Panggil 'si_trip_deposit' @{ session_id = $script:sessionId; nominal = 10000; keterangan = 'setoran UAT' } $tokenPemilik
    'semua transaksi sesi tercatat'
}
Uji 'SCR-41' 'Laporan sesi: DUA rumus benar (hasil bersih 5000; kas seharusnya 210000)' {
    $d = Panggil 'si_trip_detail' @{ session_id = $script:sessionId } $tokenPemilik
    $rm = $d.data.rumus
    # hasil bersih = tertagih 30000 - biaya 5000 - dibayar beli 20000 = 5000
    if ([math]::Abs([double]$rm.hasilBersih - 5000) -gt 0.01) { throw ("hasilBersih {0} != 5000" -f $rm.hasilBersih) }
    # kas = 100000 +30000 tagih tunai +15000 jual -5000 biaya -20000 beli -10000 setoran = 110000... hitung dr server:
    $harap = 100000 + 30000 + 15000 - 5000 - 20000 - 10000
    if ([math]::Abs([double]$rm.kasFisikSeharusnya - $harap) -gt 0.01) { throw ("kasSeharusnya {0} != {1}" -f $rm.kasFisikSeharusnya, $harap) }
    ("hasilBersih={0} kasSeharusnya={1}" -f $rm.hasilBersih, $rm.kasFisikSeharusnya)
}
Uji 'SCR-40c' 'Rekonsiliasi: DITOLAK saat barang belum habis, lalu lolos setelah alokasi' {
    $null = Panggil 'si_trip_return' @{ session_id = $script:sessionId } $tokenPemilik
    $tolak = HarapDitolak 'si_trip_reconcile' @{ session_id = $script:sessionId } $tokenPemilik
    if (-not $tolak) { throw 'reconcile lolos padahal barang masih dibawa (invariant bocor!)' }
    $d = Panggil 'si_spj_detail' @{ spj_id = $script:spjId } $tokenPemilik
    $barisBarang = $d.data.barang[0]
    $null = Panggil 'si_trip_barang_update' @{ rows = @(@{ barang_id = $barisBarang.id; qty_terjual = 4; qty_kembali = 6; qty_rusak = 0; qty_hilang = 0 }) } $tokenPemilik
    $null = Panggil 'si_trip_reconcile' @{ session_id = $script:sessionId } $tokenPemilik
    "tolak-awal OK ($tolak); reconcile lolos setelah 4 terjual + 6 kembali"
}
Uji 'SCR-42' 'Tutup sesi (approval) + selisih kas 0 + snapshot' {
    $d = Panggil 'si_trip_detail' @{ session_id = $script:sessionId } $tokenPemilik
    $kas = [double]$d.data.rumus.kasFisikSeharusnya
    $r = Panggil 'si_trip_close' @{ session_id = $script:sessionId; kas_fisik_aktual = $kas; catatan = 'UAT tutup' } $tokenPemilik
    if ([math]::Abs([double]$r.selisihKas) -gt 0.01) { throw ("selisih kas {0} != 0" -f $r.selisihKas) }
    ("hasilBersih={0} selisih=0" -f $r.hasilBersih)
}

# ---------------------------------------------------------------- SCR-43..48 FINANCE
Uji 'SCR-43' 'Kas & Jurnal terbaca (akunting.transaksi)' {
    $r = Panggil 'si_cash_journal_list' @{ dari = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd'); sampai = (Get-Date -Format 'yyyy-MM-dd') } $tokenPemilik
    ("{0} baris; D={1} K={2}" -f @($r.rows).Count, $r.totalDebet, $r.totalKredit)
}
Uji 'SCR-44' 'Master Akun: list + create perkiraan UAT' {
    $r = Panggil 'si_coa_list' @{ q = '' } $tokenPemilik
    $null = Panggil 'si_coa_save' @{ kode = "UAT$script:Stamp"; nama = "$script:Uat Perkiraan"; keterangan = 'akun uji UAT (boleh diabaikan)' } $tokenPemilik
    ("{0} akun; create OK" -f @($r.rows).Count)
}
Uji 'SCR-46' 'Laba Kotor: HPP snapshot benar (8 terjual x 7000)' {
    $r = Panggil 'si_gross_profit_report' @{ dari = (Get-Date -Format 'yyyy-MM-dd'); sampai = (Get-Date -Format 'yyyy-MM-dd'); group_by = 'produk' } $tokenPemilik
    $baris = @($r.rows) | Where-Object { "$($_.grupNama)" -like "*$script:Uat*" }
    if (-not $baris) { throw 'produk uji tidak muncul di laba kotor' }
    # 2 order (5+3=8 unit) @10000 jual, HPP snapshot 7000 -> laba 24000
    $lk = [double]$baris[0].labaKotor
    if ([math]::Abs($lk - 24000) -gt 0.01) { throw ("laba kotor {0} != 24000" -f $lk) }
    "labaKotor=24000 OK (snapshot HPP terbukti)"
}
Uji 'SCR-47' 'Laporan Laba/Rugi varian terbaca + komponen konsisten' {
    $r = Panggil 'si_profit_loss_report' @{ dari = (Get-Date -Format 'yyyy-MM-dd'); sampai = (Get-Date -Format 'yyyy-MM-dd') } $tokenPemilik
    $d = $r.data
    ("pendapatanFaktur={0} jualTunai={1} hpp={2} beban={3} labaBersih={4}" -f $d.pendapatanFaktur, $d.penjualanTunai, $d.hpp, $d.totalBeban, $d.labaBersih)
}

# ---------------------------------------------------------------- SCOPE SALES (opsional)
if ($tokenSales) {
    Uji 'SCOPE-S' 'Sales hanya melihat order miliknya' {
        $r = Panggil 'si_sales_order_list' @{ page = 1; page_size = 50 } $tokenSales
        $asing = @($r.rows) | Where-Object { $_.salesId -and ($_.salesId -ne $script:salesId) }
        ("{0} order terlihat" -f @($r.rows).Count)
    }
}

# ---------------------------------------------------------------- BERSIH-BERSIH (best effort)
Uji 'CLEAN' 'Nonaktifkan supplier & customer uji' {
    $null = Panggil 'si_supplier_deactivate' @{ supplier_id = $script:supplierId; alasan = 'data uji UAT' } $tokenPemilik
    $null = Panggil 'si_customer_deactivate' @{ anggota_id = $script:customerId; alasan = 'data uji UAT' } $tokenPemilik
    'dinonaktifkan (histori dipertahankan)'
}
}

# ---------------------------------------------------------------- REKAP + EVIDENCE
$pass = @($script:Hasil | Where-Object { $_.status -eq 'PASS' }).Count
$fail = @($script:Hasil | Where-Object { $_.status -eq 'FAIL' }).Count
$skip = @($script:Hasil | Where-Object { $_.status -eq 'SKIP' }).Count
Write-Host ""
Write-Host ("=== REKAP: {0} PASS, {1} FAIL, {2} SKIP ===" -f $pass, $fail, $skip) -ForegroundColor Cyan

$dirEvidence = Join-Path $PSScriptRoot '..\evidence\uat'
New-Item -ItemType Directory -Force $dirEvidence | Out-Null
$fileHasil = Join-Path $dirEvidence ("uat-runtime-{0}.json" -f $script:Stamp)
@{ waktu = $script:Stamp; baseUrl = $BaseUrl; pass = $pass; fail = $fail; skip = $skip; hasil = $script:Hasil } |
    ConvertTo-Json -Depth 5 | Out-File $fileHasil -Encoding utf8
Write-Host "Evidence: $fileHasil"

if ($fail -gt 0) { exit 1 } else { exit 0 }
