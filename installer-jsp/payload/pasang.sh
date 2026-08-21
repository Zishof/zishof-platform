#!/usr/bin/env bash
#
# Pemasang AIS (versi JSP) untuk Linux.
#
# Paket ini SUDAH memuat Tomcat dan JVM-nya sendiri, jadi mesin target tidak
# perlu memasang Java lebih dulu dan tidak akan mengganggu Java lain yang sudah
# ada di sana -- keduanya dipasang di dalam direktori aplikasi, bukan ke sistem.
#
# Kredensial database TIDAK pernah ikut di dalam paket ini. Nilainya ditanyakan
# saat pemasangan lalu ditulis HANYA ke mesin target, pada berkas setenv.sh
# milik Tomcat dengan izin 600. Aplikasi membacanya sebagai properti JVM
# (-Durl/-Dusername/-Dpassword) yang disubstitusi Hibernate ke hibernate.cfg.xml.

set -euo pipefail

SKRIP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SKRIP_DIR
readonly MUATAN_DIR="$SKRIP_DIR/muatan"

# ---------------------------------------------------------------- tampilan ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    readonly C_JUDUL=$'\033[1;36m'
    readonly C_OK=$'\033[1;32m'
    readonly C_PERINGATAN=$'\033[1;33m'
    readonly C_GALAT=$'\033[1;31m'
    readonly C_MATI=$'\033[0m'
else
    readonly C_JUDUL='' C_OK='' C_PERINGATAN='' C_GALAT='' C_MATI=''
fi

judul()      { printf '\n%s== %s ==%s\n' "$C_JUDUL" "$*" "$C_MATI"; }
info()       { printf '   %s\n' "$*"; }
berhasil()   { printf '%s   ok%s %s\n' "$C_OK" "$C_MATI" "$*"; }
peringatan() { printf '%s   ! %s%s\n' "$C_PERINGATAN" "$*" "$C_MATI"; }
gagal()      { printf '%s   x %s%s\n' "$C_GALAT" "$*" "$C_MATI" >&2; exit 1; }

# --------------------------------------------------------------- nilai awal ---
DIR_PASANG="${AIS_DIR:-/opt/ais}"
NAMA_KONTEKS="${AIS_KONTEKS:-ais}"
PORT_HTTP="${AIS_PORT:-8080}"
PORT_SHUTDOWN="${AIS_PORT_SHUTDOWN:-8005}"
MEMORI_MAKS="${AIS_XMX:-2048m}"
PENGGUNA_LAYANAN="${AIS_USER:-ais}"

DB_HOST="${AIS_DB_HOST:-}"
DB_PORT="${AIS_DB_PORT:-5432}"
DB_NAMA="${AIS_DB_NAME:-}"
DB_USER="${AIS_DB_USER:-}"
DB_SANDI="${AIS_DB_PASSWORD:-}"

# Basis data STREAMING dipakai untuk kueri besar (laporan) lewat SessionFactory
# terpisah supaya tidak menghabiskan pool koneksi utama. Umumnya sama dengan
# basis data utama; dibuat terpisah hanya bila memang ada replika baca.
DB_STREAMING_SAMA="ya"
DB_S_HOST="" DB_S_PORT="" DB_S_NAMA="" DB_S_USER="" DB_S_SANDI=""

TANPA_TANYA=0
LEWATI_UJI_DB=0

# ------------------------------------------------------------------ argumen ---
tampilkan_bantuan() {
    cat <<'BANTUAN'
Pemasang AIS versi JSP (Linux, sudah memuat Tomcat + JVM).

Pemakaian:
  sudo ./pasang.sh [opsi]

Tanpa opsi, pemasang akan MENANYAKAN seluruh isian dan menampilkan ringkasan
untuk dikonfirmasi sebelum ada satu berkas pun yang ditulis.

Opsi:
  --tanpa-tanya          Jangan bertanya; ambil nilai dari variabel lingkungan.
                         Wajib: AIS_DB_HOST, AIS_DB_NAME, AIS_DB_USER,
                         AIS_DB_PASSWORD.
  --lewati-uji-db        Jangan menguji jangkauan server database dulu.
  --dir DIREKTORI        Direktori pemasangan (bawaan: /opt/ais)
  --konteks NAMA         Nama konteks web (bawaan: ais) -> /ais
  --port NOMOR           Port HTTP Tomcat (bawaan: 8080)
  -h, --help             Tampilkan bantuan ini.

Variabel lingkungan yang dikenali:
  AIS_DIR AIS_KONTEKS AIS_PORT AIS_PORT_SHUTDOWN AIS_XMX AIS_USER
  AIS_DB_HOST AIS_DB_PORT AIS_DB_NAME AIS_DB_USER AIS_DB_PASSWORD
  AIS_DB_STREAM_HOST AIS_DB_STREAM_PORT AIS_DB_STREAM_NAME
  AIS_DB_STREAM_USER AIS_DB_STREAM_PASSWORD

Kata sandi TIDAK pernah ditampilkan di layar maupun dicatat ke log.
BANTUAN
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tanpa-tanya)   TANPA_TANYA=1; shift ;;
        --lewati-uji-db) LEWATI_UJI_DB=1; shift ;;
        --dir)           DIR_PASANG="${2:?--dir butuh nilai}"; shift 2 ;;
        --konteks)       NAMA_KONTEKS="${2:?--konteks butuh nilai}"; shift 2 ;;
        --port)          PORT_HTTP="${2:?--port butuh nilai}"; shift 2 ;;
        -h|--help)       tampilkan_bantuan; exit 0 ;;
        *)               gagal "Opsi tidak dikenal: $1 (coba --help)" ;;
    esac
done

# ------------------------------------------------------------- pemeriksaan ---
[ "$(id -u)" -eq 0 ] || gagal "Jalankan sebagai root: sudo ./pasang.sh"
[ -d "$MUATAN_DIR" ] || gagal "Folder muatan tidak ditemukan. Ekstrak ulang paketnya."

for berkas in ais.war tomcat.tar.gz jre.tar.gz; do
    [ -f "$MUATAN_DIR/$berkas" ] || gagal "Muatan tidak lengkap: $berkas tidak ada."
done

command -v tar >/dev/null 2>&1 || gagal "Perintah 'tar' tidak tersedia."

# --------------------------------------------------------------- pertanyaan ---
tanya() {
    local pesan="$1" bawaan="${2:-}" jawaban=""
    if [ -n "$bawaan" ]; then
        read -r -p "   $pesan [$bawaan]: " jawaban </dev/tty || true
        printf '%s' "${jawaban:-$bawaan}"
    else
        while [ -z "$jawaban" ]; do
            read -r -p "   $pesan: " jawaban </dev/tty || true
            [ -n "$jawaban" ] || printf '     (wajib diisi)\n' >&2
        done
        printf '%s' "$jawaban"
    fi
}

tanya_sandi() {
    local pesan="$1" satu="" dua=""
    while :; do
        read -r -s -p "   $pesan: " satu </dev/tty || true; printf '\n'
        [ -n "$satu" ] || { printf '     (wajib diisi)\n' >&2; continue; }
        read -r -s -p "   Ulangi untuk memastikan: " dua </dev/tty || true; printf '\n'
        [ "$satu" = "$dua" ] && break
        printf '     (kata sandi tidak sama, ulangi)\n' >&2
    done
    printf '%s' "$satu"
}

tanya_ya_tidak() {
    local pesan="$1" bawaan="$2" jawaban=""
    read -r -p "   $pesan (ya/tidak) [$bawaan]: " jawaban </dev/tty || true
    jawaban="${jawaban:-$bawaan}"
    case "${jawaban,,}" in
        y|ya|yes) printf 'ya' ;;
        *)        printf 'tidak' ;;
    esac
}

angka_saja() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *)           return 0 ;;
    esac
}

if [ "$TANPA_TANYA" -eq 0 ]; then
    judul "Lokasi pemasangan"
    DIR_PASANG="$(tanya 'Direktori pemasangan' "$DIR_PASANG")"
    NAMA_KONTEKS="$(tanya 'Nama konteks web (alamat jadi /<konteks>)' "$NAMA_KONTEKS")"
    while :; do
        PORT_HTTP="$(tanya 'Port HTTP Tomcat' "$PORT_HTTP")"
        angka_saja "$PORT_HTTP" && break
        peringatan "Port harus berupa angka."
    done
    MEMORI_MAKS="$(tanya 'Memori maksimum JVM (mis. 2048m atau 4g)' "$MEMORI_MAKS")"

    judul "Database utama (PostgreSQL)"
    info "Nilai berikut dipakai aplikasi untuk menyambung ke database."
    info "Kata sandi tidak akan ditampilkan saat diketik."
    DB_HOST="$(tanya 'Alamat server database' "${DB_HOST:-127.0.0.1}")"
    while :; do
        DB_PORT="$(tanya 'Port database' "$DB_PORT")"
        angka_saja "$DB_PORT" && break
        peringatan "Port harus berupa angka."
    done
    DB_NAMA="$(tanya 'Nama database' "${DB_NAMA:-ais}")"
    DB_USER="$(tanya 'Username database' "${DB_USER:-postgres}")"
    DB_SANDI="$(tanya_sandi 'Password database')"

    judul "Database untuk kueri laporan besar"
    info "Aplikasi memakai koneksi terpisah untuk kueri besar agar tidak"
    info "menghabiskan pool koneksi utama. Umumnya database yang sama."
    DB_STREAMING_SAMA="$(tanya_ya_tidak 'Pakai database yang sama' 'ya')"
    if [ "$DB_STREAMING_SAMA" = "tidak" ]; then
        DB_S_HOST="$(tanya 'Alamat server database laporan' "$DB_HOST")"
        DB_S_PORT="$(tanya 'Port database laporan' "$DB_PORT")"
        DB_S_NAMA="$(tanya 'Nama database laporan' "$DB_NAMA")"
        DB_S_USER="$(tanya 'Username database laporan' "$DB_USER")"
        DB_S_SANDI="$(tanya_sandi 'Password database laporan')"
    fi
else
    [ -n "$DB_HOST" ] || gagal "--tanpa-tanya butuh AIS_DB_HOST."
    [ -n "$DB_NAMA" ] || gagal "--tanpa-tanya butuh AIS_DB_NAME."
    [ -n "$DB_USER" ] || gagal "--tanpa-tanya butuh AIS_DB_USER."
    [ -n "$DB_SANDI" ] || gagal "--tanpa-tanya butuh AIS_DB_PASSWORD."
    if [ -n "${AIS_DB_STREAM_HOST:-}" ]; then
        DB_STREAMING_SAMA="tidak"
        DB_S_HOST="$AIS_DB_STREAM_HOST"
        DB_S_PORT="${AIS_DB_STREAM_PORT:-$DB_PORT}"
        DB_S_NAMA="${AIS_DB_STREAM_NAME:-$DB_NAMA}"
        DB_S_USER="${AIS_DB_STREAM_USER:-$DB_USER}"
        DB_S_SANDI="${AIS_DB_STREAM_PASSWORD:-$DB_SANDI}"
    fi
fi

if [ "$DB_STREAMING_SAMA" = "ya" ]; then
    DB_S_HOST="$DB_HOST"; DB_S_PORT="$DB_PORT"; DB_S_NAMA="$DB_NAMA"
    DB_S_USER="$DB_USER"; DB_S_SANDI="$DB_SANDI"
fi

# ------------------------------------------------------------- uji jangkauan ---
if [ "$LEWATI_UJI_DB" -eq 0 ]; then
    judul "Memeriksa jangkauan server database"
    if (exec 3<>"/dev/tcp/$DB_HOST/$DB_PORT") 2>/dev/null; then
        berhasil "$DB_HOST:$DB_PORT dapat dihubungi."
    else
        peringatan "$DB_HOST:$DB_PORT tidak dapat dihubungi dari mesin ini."
        peringatan "Pemasangan boleh diteruskan, tetapi aplikasi tidak akan"
        peringatan "berfungsi sampai jaringan atau pg_hba.conf diperbaiki."
        if [ "$TANPA_TANYA" -eq 0 ]; then
            [ "$(tanya_ya_tidak 'Tetap lanjutkan' 'tidak')" = "ya" ] || gagal "Dibatalkan."
        fi
    fi
fi

# ---------------------------------------------------------------- ringkasan ---
judul "Ringkasan"
printf '   %-28s %s\n' 'Direktori pemasangan' "$DIR_PASANG"
printf '   %-28s %s\n' 'Konteks web'          "/$NAMA_KONTEKS"
printf '   %-28s %s\n' 'Port HTTP'            "$PORT_HTTP"
printf '   %-28s %s\n' 'Memori maksimum JVM'  "$MEMORI_MAKS"
printf '   %-28s %s\n' 'Pengguna layanan'     "$PENGGUNA_LAYANAN"
printf '   %-28s %s\n' 'Database'             "$DB_USER@$DB_HOST:$DB_PORT/$DB_NAMA"
printf '   %-28s %s\n' 'Kata sandi database'  '(tersembunyi)'
if [ "$DB_STREAMING_SAMA" = "ya" ]; then
    printf '   %-28s %s\n' 'Database laporan' 'sama dengan database utama'
else
    printf '   %-28s %s\n' 'Database laporan' "$DB_S_USER@$DB_S_HOST:$DB_S_PORT/$DB_S_NAMA"
fi

if [ "$TANPA_TANYA" -eq 0 ]; then
    printf '\n'
    [ "$(tanya_ya_tidak 'Lanjutkan pemasangan dengan isian di atas' 'ya')" = "ya" ] \
        || gagal "Dibatalkan. Tidak ada berkas yang diubah."
fi

# ------------------------------------------------------------------ pasang ---
judul "Menyiapkan direktori"
DIR_TOMCAT="$DIR_PASANG/tomcat"
DIR_JRE="$DIR_PASANG/jre"

PEMASANGAN_ULANG=0
if [ -d "$DIR_TOMCAT" ]; then
    PEMASANGAN_ULANG=1
    info "Pemasangan lama terdeteksi; layanan akan dihentikan lebih dulu."
    systemctl stop ais 2>/dev/null || true
    # Konfigurasi dan data DIPERTAHANKAN. Hanya aplikasi & runtime yang diganti,
    # supaya pemasangan ulang tidak menghapus penyetelan operator.
    rm -rf "$DIR_TOMCAT/webapps/$NAMA_KONTEKS" "$DIR_TOMCAT/webapps/$NAMA_KONTEKS.war"
    rm -rf "$DIR_TOMCAT/work" "$DIR_JRE"
fi

mkdir -p "$DIR_PASANG"

judul "Memasang JVM"
mkdir -p "$DIR_JRE"
tar -xzf "$MUATAN_DIR/jre.tar.gz" -C "$DIR_JRE" --strip-components=1
[ -x "$DIR_JRE/bin/java" ] || gagal "JVM gagal diekstrak."
berhasil "$("$DIR_JRE/bin/java" -version 2>&1 | head -1)"

if [ "$PEMASANGAN_ULANG" -eq 0 ]; then
    judul "Memasang Tomcat"
    mkdir -p "$DIR_TOMCAT"
    tar -xzf "$MUATAN_DIR/tomcat.tar.gz" -C "$DIR_TOMCAT" --strip-components=1
    [ -f "$DIR_TOMCAT/bin/catalina.sh" ] || gagal "Tomcat gagal diekstrak."
    # Aplikasi bawaan Tomcat tidak dipakai dan menambah permukaan serangan.
    rm -rf "$DIR_TOMCAT"/webapps/examples \
           "$DIR_TOMCAT"/webapps/docs \
           "$DIR_TOMCAT"/webapps/host-manager \
           "$DIR_TOMCAT"/webapps/manager \
           "$DIR_TOMCAT"/webapps/ROOT
    berhasil "Tomcat terpasang di $DIR_TOMCAT"
else
    info "Tomcat yang sudah ada dipertahankan beserta konfigurasinya."
fi

judul "Menyetel port"
SERVER_XML="$DIR_TOMCAT/conf/server.xml"
[ -f "$SERVER_XML" ] || gagal "server.xml tidak ditemukan."
cp -f "$SERVER_XML" "$SERVER_XML.bak.$(date +%Y%m%d%H%M%S)"
sed -i -E "s|(<Server[^>]*port=\")[0-9]+(\")|\1$PORT_SHUTDOWN\2|" "$SERVER_XML"
sed -i -E "s|(<Connector[^>]*port=\")8080(\"[^>]*protocol=\"HTTP/1.1\")|\1$PORT_HTTP\2|" "$SERVER_XML"
berhasil "HTTP $PORT_HTTP, shutdown $PORT_SHUTDOWN"

judul "Memasang aplikasi"
cp -f "$MUATAN_DIR/ais.war" "$DIR_TOMCAT/webapps/$NAMA_KONTEKS.war"
berhasil "webapps/$NAMA_KONTEKS.war"

judul "Menulis konfigurasi database"
SETENV="$DIR_TOMCAT/bin/setenv.sh"
# Ditulis dengan umask ketat SEBELUM isinya ada, supaya kata sandi tidak pernah
# sempat terbaca proses lain walau sesaat.
( umask 077; : > "$SETENV" )
{
    printf '#!/bin/sh\n'
    printf '# Dihasilkan oleh pemasang AIS. BERISI KATA SANDI DATABASE.\n'
    printf '# Jangan disalin, dibagikan, atau dimasukkan ke sistem kendali versi.\n'
    printf '\n'
    printf 'JAVA_HOME="%s"\n' "$DIR_JRE"
    printf 'export JAVA_HOME\n'
    printf '\n'
    printf 'CATALINA_OPTS="-Xmx%s -XX:+UseG1GC -Dfile.encoding=UTF-8"\n' "$MEMORI_MAKS"
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Djava.awt.headless=true"\n'
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Durl=%s"\n' \
        "jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAMA"
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Dusername=%s"\n' "$DB_USER"
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Dpassword=%s"\n' "$DB_SANDI"
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Durl_streaming=%s"\n' \
        "jdbc:postgresql://$DB_S_HOST:$DB_S_PORT/$DB_S_NAMA"
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Dusername_streaming=%s"\n' "$DB_S_USER"
    printf 'CATALINA_OPTS="$CATALINA_OPTS -Dpassword_streaming=%s"\n' "$DB_S_SANDI"
    printf 'export CATALINA_OPTS\n'
} >> "$SETENV"
chmod 600 "$SETENV"
berhasil "$SETENV (izin 600, hanya pemilik yang dapat membaca)"

judul "Menyiapkan pengguna layanan"
if ! id -u "$PENGGUNA_LAYANAN" >/dev/null 2>&1; then
    useradd --system --home-dir "$DIR_PASANG" --shell /usr/sbin/nologin "$PENGGUNA_LAYANAN"
    berhasil "Pengguna sistem '$PENGGUNA_LAYANAN' dibuat."
else
    info "Pengguna '$PENGGUNA_LAYANAN' sudah ada."
fi
chown -R "$PENGGUNA_LAYANAN":"$PENGGUNA_LAYANAN" "$DIR_PASANG"
chmod 600 "$SETENV"
chown "$PENGGUNA_LAYANAN":"$PENGGUNA_LAYANAN" "$SETENV"

judul "Mendaftarkan layanan systemd"
if command -v systemctl >/dev/null 2>&1; then
    UNIT=/etc/systemd/system/ais.service
    {
        printf '[Unit]\n'
        printf 'Description=AIS (versi JSP) di Tomcat\n'
        printf 'After=network-online.target\n'
        printf 'Wants=network-online.target\n'
        printf '\n[Service]\n'
        printf 'Type=forking\n'
        printf 'User=%s\n' "$PENGGUNA_LAYANAN"
        printf 'Group=%s\n' "$PENGGUNA_LAYANAN"
        printf 'Environment=JAVA_HOME=%s\n' "$DIR_JRE"
        printf 'Environment=CATALINA_HOME=%s\n' "$DIR_TOMCAT"
        printf 'Environment=CATALINA_BASE=%s\n' "$DIR_TOMCAT"
        printf 'Environment=CATALINA_PID=%s/temp/tomcat.pid\n' "$DIR_TOMCAT"
        printf 'ExecStart=%s/bin/startup.sh\n' "$DIR_TOMCAT"
        printf 'ExecStop=%s/bin/shutdown.sh\n' "$DIR_TOMCAT"
        printf 'Restart=on-failure\n'
        printf 'RestartSec=10\n'
        # Tomcat membuka port di atas 1024, jadi tidak perlu hak istimewa apa pun.
        printf 'NoNewPrivileges=true\n'
        printf 'PrivateTmp=true\n'
        printf 'ProtectSystem=full\n'
        printf 'ProtectHome=true\n'
        printf '\n[Install]\n'
        printf 'WantedBy=multi-user.target\n'
    } > "$UNIT"
    chmod 644 "$UNIT"
    systemctl daemon-reload
    systemctl enable ais >/dev/null 2>&1 || true
    berhasil "$UNIT"

    judul "Menjalankan layanan"
    systemctl restart ais
    # Deploy WAR pertama kali memerlukan waktu; beri kesempatan sebelum memeriksa.
    for _ in $(seq 1 30); do
        if systemctl is-active --quiet ais; then break; fi
        sleep 1
    done
    if systemctl is-active --quiet ais; then
        berhasil "Layanan 'ais' berjalan."
    else
        peringatan "Layanan belum berjalan. Periksa: journalctl -u ais -n 100"
    fi
else
    peringatan "systemd tidak tersedia. Jalankan manual:"
    peringatan "  JAVA_HOME=$DIR_JRE $DIR_TOMCAT/bin/startup.sh"
fi

judul "Selesai"
info "Alamat aplikasi : http://<alamat-server>:$PORT_HTTP/$NAMA_KONTEKS"
info "Endpoint API POS: http://<alamat-server>:$PORT_HTTP/$NAMA_KONTEKS/Api_eBisnis"
info "Log Tomcat      : $DIR_TOMCAT/logs/catalina.out"
info "Konfigurasi DB  : $SETENV"
printf '\n'
peringatan "Sebelum dipakai di produksi, pasang HTTPS di depan Tomcat"
peringatan "(mis. Nginx atau Apache sebagai reverse proxy). POS mengirim kata"
peringatan "sandi dan token pada setiap permintaan."
printf '\n'
