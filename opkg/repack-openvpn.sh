#!/bin/sh
# Перепаковывает XOR-openvpn .ipk, поднимая Version до epoch'нутой (по умолчанию 1:2.6.14-4).
#
# Зачем: наш XOR-бинарь пакуется как пакет `openvpn-openssl` (перекрывает стоковый). У стока
# из Entware — та же базовая версия (2.6.14-4), поэтому без epoch'а opkg мог бы выбрать сток.
# Epoch (1:) детерминированно ставит НАШ XOR выше при install/upgrade. Бинарь не трогаем.
#
# Использование:  sh repack-openvpn.sh [src-dir] [out-dir] [new-version]
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
SRCDIR="${1:-$HERE/openvpn}"
OUT="${2:-$HERE/out}"
NEWVER="${3:-1:2.6.14-4}"
mkdir -p "$OUT"

found=0
for ipk in "$SRCDIR"/openvpn-openssl*_*.ipk; do
  [ -f "$ipk" ] || continue
  found=$((found+1))
  base=$(basename "$ipk")
  arch=$(echo "$base" | sed -n 's/.*_\([a-z0-9.-]*\)\.ipk$/\1/p')
  tmp=$(mktemp -d)
  tar xzf "$ipk" -C "$tmp"
  mkdir -p "$tmp/c"; tar xzf "$tmp/control.tar.gz" -C "$tmp/c"
  ctrl="$tmp/c/control"; [ -f "$ctrl" ] || ctrl="$tmp/c/./control"
  sed -i "s/^Version:.*/Version: $NEWVER/" "$ctrl"          # только версия, Package/Arch как есть
  ( cd "$tmp/c" && tar --owner=0 --group=0 --numeric-owner -czf "$tmp/control.tar.gz" ./ )
  outname="$OUT/openvpn-openssl_$(echo "$NEWVER" | tr ':' '.')_${arch}.ipk"   # ':' недопустим в имени файла
  ( cd "$tmp" && tar --owner=0 --group=0 --numeric-owner -czf "$outname" ./debian-binary ./data.tar.gz ./control.tar.gz )
  echo "repacked: $(basename "$outname")  (Version=$NEWVER arch=$arch)"
  rm -rf "$tmp"
done
[ "$found" -gt 0 ] || { echo "нет openvpn-openssl*_*.ipk в $SRCDIR" >&2; exit 1; }
