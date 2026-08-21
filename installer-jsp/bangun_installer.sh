#!/usr/bin/env bash
#
# Membangun paket pemasang AIS (versi JSP) untuk Linux.
#
# Keluarannya SATU berkas tar.gz yang memuat:
#   - ais.war        hasil kompilasi src AIS
#   - tomcat.tar.gz  Apache Tomcat 9
#   - jre.tar.gz     Temurin JRE 8 (linux x64)
#   - pasang.sh      pemasang interaktif
#
# Tomcat dan JRE diunduh SAAT MEMBANGUN, bukan saat memasang, supaya paketnya
# dapat dipasang di server yang tidak punya akses internet -- kasus yang lazim
# untuk server database di jaringan internal.
#
# Skrip ini TIDAK pernah menyentuh kredensial apa pun. Alamat dan kata sandi
# database ditanyakan oleh pasang.sh di mesin target.

set -euo pipefail

SKRIP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SKRIP_DIR

# Sumber AIS berada di working copy SVN yang terpisah dari repositori git ini.
AIS_ROOT="${AIS_ROOT:-/c/opt/AIS/ais}"
VERSI="${VERSI:-}"
LEWATI_UNDUH="${LEWATI_UNDUH:-0}"

# Versi runtime SENGAJA dipatok: aplikasi dikompilasi dengan gaya Java 6 dan
# dijalankan di Java 8 (Tomcat 9 mensyaratkan minimal 8). Menaikkannya tanpa
# pengujian menyeluruh berisiko memutus pustaka lama yang dipakai aplikasi.
readonly TOMCAT_VERSI="${TOMCAT_VERSI:-9.0.121}"
readonly JRE_VERSI="${JRE_VERSI:-8u502b07}"
readonly JRE_TAG="${JRE_TAG:-jdk8u502-b07}"

pesan() { printf '\n== %s ==\n' "$*"; }
gagal() { printf 'x %s\n' "$*" >&2; exit 1; }

[ -n "$VERSI" ] || gagal "Setel VERSI, mis. VERSI=1.0.0 ./bangun_installer.sh"
[ -d "$AIS_ROOT/src/main/src" ] || gagal "Sumber AIS tidak ada di $AIS_ROOT (setel AIS_ROOT)."

readonly KERJA="$SKRIP_DIR/build"
readonly RAKIT="$KERJA/ais-jsp-installer-$VERSI"
readonly UNDUHAN="$SKRIP_DIR/unduhan"

rm -rf "$RAKIT"
mkdir -p "$RAKIT/muatan" "$UNDUHAN"

# ------------------------------------------------------------------- war ---
pesan "Membangun ais.war dari $AIS_ROOT"

# build.xml bawaan menunjuk tata letak lama (web/, src/). Tata letak sekarang
# adalah src/main/webapp dan src/main/src, jadi nilainya ditimpa dari CLI --
# properti CLI Ant selalu menang atas <property> di dalam berkas.
ANT_BIN="${ANT_BIN:-ant}"
command -v "$ANT_BIN" >/dev/null 2>&1 || gagal "Ant tidak ditemukan (setel ANT_BIN)."

( cd "$AIS_ROOT" && "$ANT_BIN" -f ant/build.xml \
    -Dsrc.dir="src/main/src" \
    -Dweb.dir="src/main/webapp" \
    -Ddest.dir="build-installer" \
    -Dtemp.dir="temporary-installer" \
    package )

WAR_ASAL="$AIS_ROOT/build-installer/ais.war"
[ -f "$WAR_ASAL" ] || gagal "ais.war tidak terbentuk di $WAR_ASAL"

# Keberadaan berkas TIDAK cukup sebagai bukti berhasil. Ketika jumlah entri
# melewati batas format ZIP lama, Ant menutup build dengan galat TETAPI
# meninggalkan berkas .war ratusan MB yang korup di folder tujuan. Arsipnya
# diuji betulan supaya kegagalan seperti itu tidak pernah lolos sampai ke
# server pelanggan.
uji_arsip() {
    if command -v unzip >/dev/null 2>&1; then
        unzip -tq "$1" >/dev/null 2>&1
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys,zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)" "$1"
        return $?
    fi
    if command -v python >/dev/null 2>&1; then
        python -c "import sys,zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)" "$1"
        return $?
    fi
    printf "   ! tidak ada unzip/python; keabsahan arsip tidak diuji" >&2
    printf "\n" >&2
    return 0
}

uji_arsip "$WAR_ASAL" || gagal "ais.war korup: arsipnya tidak dapat dibaca."
cp -f "$WAR_ASAL" "$RAKIT/muatan/ais.war"
printf '   ais.war %s byte\n' "$(stat -c%s "$RAKIT/muatan/ais.war" 2>/dev/null || wc -c < "$RAKIT/muatan/ais.war")"

# --------------------------------------------------------------- runtime ---
unduh_sekali() {
    local url="$1" tujuan="$2"
    if [ -f "$tujuan" ]; then
        printf '   pakai berkas yang sudah ada: %s\n' "$(basename "$tujuan")"
        return 0
    fi
    printf '   mengunduh %s\n' "$(basename "$tujuan")"
    curl -fSL --retry 3 --connect-timeout 30 -o "$tujuan.sementara" "$url"
    mv -f "$tujuan.sementara" "$tujuan"
}

if [ "$LEWATI_UNDUH" -eq 0 ]; then
    pesan "Menyiapkan Tomcat $TOMCAT_VERSI"
    unduh_sekali \
        "https://archive.apache.org/dist/tomcat/tomcat-9/v$TOMCAT_VERSI/bin/apache-tomcat-$TOMCAT_VERSI.tar.gz" \
        "$UNDUHAN/apache-tomcat-$TOMCAT_VERSI.tar.gz"

    pesan "Menyiapkan Temurin JRE $JRE_VERSI (linux x64)"
    unduh_sekali \
        "https://github.com/adoptium/temurin8-binaries/releases/download/$JRE_TAG/OpenJDK8U-jre_x64_linux_hotspot_${JRE_VERSI}.tar.gz" \
        "$UNDUHAN/OpenJDK8U-jre_x64_linux_hotspot_${JRE_VERSI}.tar.gz"
fi

cp -f "$UNDUHAN/apache-tomcat-$TOMCAT_VERSI.tar.gz" "$RAKIT/muatan/tomcat.tar.gz"
cp -f "$UNDUHAN/OpenJDK8U-jre_x64_linux_hotspot_${JRE_VERSI}.tar.gz" "$RAKIT/muatan/jre.tar.gz"

# ----------------------------------------------------------------- rakit ---
pesan "Merakit paket"
cp -f "$SKRIP_DIR/payload/pasang.sh" "$RAKIT/pasang.sh"
chmod +x "$RAKIT/pasang.sh"
cp -f "$SKRIP_DIR/README.md" "$RAKIT/README.md" 2>/dev/null || true

{
    printf 'Paket    : AIS versi JSP\n'
    printf 'Versi    : %s\n' "$VERSI"
    printf 'Tomcat   : %s\n' "$TOMCAT_VERSI"
    printf 'JRE      : Temurin %s (linux x64)\n' "$JRE_VERSI"
    printf 'Target   : Linux x86_64, systemd\n'
} > "$RAKIT/VERSI.txt"

readonly HASIL="$KERJA/ais-jsp-installer-$VERSI-linux-x64.tar.gz"
rm -f "$HASIL"
( cd "$KERJA" && tar -czf "$(basename "$HASIL")" "$(basename "$RAKIT")" )

( cd "$KERJA" && sha256sum "$(basename "$HASIL")" > "$(basename "$HASIL").sha256" )

pesan "Selesai"
ls -lh "$HASIL" "$HASIL.sha256"
printf '\nCara pakai di server Linux:\n'
printf '  tar -xzf %s\n' "$(basename "$HASIL")"
printf '  cd ais-jsp-installer-%s\n' "$VERSI"
printf '  sudo ./pasang.sh\n\n'
