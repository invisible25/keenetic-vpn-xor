#!/bin/sh
# Собирает полный opkg-фид в ./feed: invnet_<v>_all.ipk + XOR-openvpn (3 арх, epoch'нутый)
# + индекс Packages/Packages.gz. Именно ./feed публикуется на GitHub Pages.
#
# Использование:  sh build-feed.sh [feed-dir] [invnet-version]
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
FEED="${1:-$HERE/feed}"
INVNET_VER="${2:-}"

rm -rf "$FEED"; mkdir -p "$FEED"
sh "$HERE/build-ipk.sh"      "$INVNET_VER" "$FEED"
sh "$HERE/repack-openvpn.sh" "$HERE/openvpn" "$FEED"
sh "$HERE/make-index.sh"     "$FEED"

echo "── фид готов: $FEED ──"
ls -la "$FEED" | grep -E '\.ipk|Packages'
