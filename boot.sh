#!/bin/sh
# boot.sh — установка VPN+XOR панели одной командой:
#   wget -qO- https://raw.githubusercontent.com/invisible25/keenetic-vpn-xor/main/boot.sh | sh
# Скачивает последний релиз и запускает install.sh (тот сам выбирает .ipk по архитектуре).
set -e
REPO="invisible25/keenetic-vpn-xor"

[ -x /opt/bin/opkg ] || { echo "Нужен Entware на роутере (см. документацию Keenetic OPKG)."; exit 1; }

# HTTPS-загрузка: на части Entware busybox-wget без SSL — подстрахуемся ca-bundle/curl
opkg list-installed 2>/dev/null | grep -q '^ca-bundle ' || opkg install ca-bundle >/dev/null 2>&1 || true

URL="https://github.com/$REPO/releases/latest/download/vpn-xor-install-clean.tar.gz"
echo "[*] Скачиваю последний релиз..."
cd /tmp && rm -rf vpn-xor-install vpn-xor-install.tar.gz
if command -v curl >/dev/null 2>&1; then
  curl -fSL "$URL" -o vpn-xor-install.tar.gz
else
  wget -O vpn-xor-install.tar.gz "$URL"
fi

echo "[*] Распаковка и установка..."
tar xzf vpn-xor-install.tar.gz
cd vpn-xor-install && sh install.sh
