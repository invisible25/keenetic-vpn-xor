#!/bin/sh
# Собирает invnet_<version>_all.ipk из ../src.
#
# Пакет — Architecture: all (панель = sh + html, компиляции нет; ставится на любой
# Keenetic). openvpn-openssl-xor поставляется отдельным per-arch пакетом (Depends).
#
# Внешний формат .ipk — gzip'нутый tar с членами ./debian-binary ./data.tar.gz
# ./control.tar.gz (именно его понимает opkg на этих Keenetic — сверено с рабочим
# openvpn .ipk). Собирается только tar+gzip, без ar → работает и на Windows/Git Bash.
#
# Использование:  sh build-ipk.sh [version] [out-dir]
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
SRC="$REPO/src"
VERSION="${1:-$(sed -n 's/^INVNET_VERSION=\([0-9.]*\).*/\1/p' "$REPO/install.sh" | head -1)}"
# раньше при неудаче парсинга тут молча подставлялась константа 1.6.0 — если она
# НИЖЕ уже опубликованной версии, opkg просто проигнорирует такой пакет как downgrade,
# и "успешный" релиз никуда не доедет. Лучше падать явно.
[ -n "$VERSION" ] || { echo "не удалось определить версию из $REPO/install.sh (INVNET_VERSION=)" >&2; exit 1; }
OUT="${2:-$HERE/out}"
PKG="invnet_${VERSION}_all.ipk"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DATA="$WORK/data"; CTRL="$WORK/control"
mkdir -p "$DATA" "$CTRL" "$OUT"
OUT=$(cd "$OUT" && pwd)     # абсолютный путь: ниже делаем cd в $WORK перед tar -czf "$OUT/..."

# ── data: файлы приложения в целевые пути /opt/... ──
inst() {  # inst <src-rel> <dest-rel-без-ведущего-слэша> [mode]
  mkdir -p "$DATA/$(dirname "$2")"
  cp "$SRC/$1" "$DATA/$2"
  chmod "${3:-644}" "$DATA/$2"
}
for s in S30invnet S31invnet-web S40invnet-pingcheck S41invnet-sched S95invnet-autostart; do
  inst "init.d/$s" "opt/etc/init.d/$s" 755
done
inst invnet-up.sh   opt/etc/openvpn/invnet-up.sh   755
inst invnet-down.sh opt/etc/openvpn/invnet-down.sh 755
inst invnet-fw.sh   opt/etc/openvpn/invnet-fw.sh   755
inst ndm/netfilter.d/50-invnet.sh opt/etc/ndm/netfilter.d/50-invnet.sh 755
inst invnetctl      opt/sbin/invnetctl 755
inst invnet.conf    opt/etc/lighttpd/invnet.conf 644          # conffile
inst invnet-lib.sh  opt/share/invnet/invnet-lib.sh 644
inst index.html     opt/share/invnet/index.html 644
# версия в подвале сайдбара = версия пакета (иначе панель врёт про свою версию).
# Проверяем результат: sed при несовпадении паттерна тихо возвращает 0 и оставляет
# файл нетронутым — без grep-проверки пакет собрался бы "зелёным" со старой версией в UI.
FOOT="$DATA/opt/share/invnet/index.html"
grep -q 'INVISIBLE NET · v' "$FOOT" || { echo "не нашёл подпись версии в index.html" >&2; exit 1; }
VESC=$(printf '%s' "$VERSION" | sed 's/[&\\#]/\\&/g')
sed -i "s#\(INVISIBLE NET · v\)[0-9][^<]*#\1$VESC#" "$FOOT"
grep -q "INVISIBLE NET · v${VERSION}<" "$FOOT" || { echo "версия не подставилась в index.html" >&2; exit 1; }
inst logo.svg       opt/share/invnet/logo.svg 644
inst logo-mark.svg  opt/share/invnet/logo-mark.svg 644
mkdir -p "$DATA/opt/share/invnet/fonts" "$DATA/opt/share/invnet/cgi-bin"
cp "$SRC/fonts/"*.woff2 "$DATA/opt/share/invnet/fonts/"; chmod 644 "$DATA/opt/share/invnet/fonts/"*
cp "$SRC/cgi-bin/"* "$DATA/opt/share/invnet/cgi-bin/"; chmod 755 "$DATA/opt/share/invnet/cgi-bin/"*

ISIZE=$(du -sk "$DATA" | awk '{print $1*1024}')

# ── control ──
cat > "$CTRL/control" <<EOF
Package: invnet
Version: $VERSION
Architecture: all
Maintainer: invisible25
Section: net
Priority: optional
Depends: openvpn-openssl (>= 1:2.6.14-4), jq, lighttpd, lighttpd-mod-cgi, iptables, ip-full, curl, tar
Installed-Size: $ISIZE
Description: Invisible Net VPN+XOR — веб-панель управления (мульти-туннель, обход DPI)
EOF
printf '/opt/etc/lighttpd/invnet.conf\n' > "$CTRL/conffiles"
cp "$HERE/scripts/postinst" "$CTRL/postinst"
cp "$HERE/scripts/prerm"    "$CTRL/prerm"
chmod 755 "$CTRL/postinst" "$CTRL/prerm"

# ── члены + внешний .ipk (порядок членов как у эталонного openvpn .ipk) ──
taropt="--owner=0 --group=0 --numeric-owner"
( cd "$DATA" && tar $taropt -czf "$WORK/data.tar.gz" ./ )
( cd "$CTRL" && tar $taropt -czf "$WORK/control.tar.gz" ./ )
printf '2.0\n' > "$WORK/debian-binary"
( cd "$WORK" && tar $taropt -czf "$OUT/$PKG" ./debian-binary ./data.tar.gz ./control.tar.gz )

echo "OK: $OUT/$PKG ($(du -h "$OUT/$PKG" | cut -f1), Installed-Size=${ISIZE})"
