#!/bin/sh
# Генерит opkg-индекс Packages/Packages.gz из каталога с .ipk.
# Работает и на Windows/Git Bash (только tar/gzip/sha256sum/md5sum), без opkg-utils.
#
# Использование:  sh make-index.sh <feed-dir>
set -e
FEED="${1:?usage: make-index.sh <feed-dir>}"
cd "$FEED"

: > Packages
n=0
for ipk in *.ipk; do
  [ -f "$ipk" ] || continue
  tmp=$(mktemp -d)
  tar xzf "$ipk" -C "$tmp"                       # → debian-binary, data.tar.gz, control.tar.gz
  mkdir -p "$tmp/c"; tar xzf "$tmp/control.tar.gz" -C "$tmp/c"
  ctrl="$tmp/c/control"; [ -f "$ctrl" ] || ctrl="$tmp/c/./control"
  size=$(wc -c < "$ipk" | tr -d ' ')
  sha=$(sha256sum "$ipk" | awk '{print $1}')
  md5=$(md5sum "$ipk" | awk '{print $1}')
  sed -e '/^[[:space:]]*$/d' "$ctrl" >> Packages   # поля control без пустых строк
  {
    echo "Filename: $ipk"
    echo "Size: $size"
    echo "SHA256sum: $sha"
    echo "MD5Sum: $md5"
    echo ""
  } >> Packages
  rm -rf "$tmp"
  n=$((n+1))
done

gzip -9c Packages > Packages.gz
echo "OK: $n пакет(ов) → $FEED/Packages(.gz)"
