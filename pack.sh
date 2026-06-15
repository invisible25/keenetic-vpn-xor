#!/bin/sh
# Упаковывает текущую установку VPN+XOR в портативный архив
# для установки на другой Кинетик.
#
# Создаёт /tmp/vpn-xor-install.tar.gz — отсылай его на новый роутер.

set -e

DEST=/tmp/vpn-xor-install
rm -rf "$DEST" && mkdir -p "$DEST"

echo "[+] Упаковываю файлы приложения..."
# Системные файлы — всегда одни и те же
/opt/bin/tar czf "$DEST/vpn-xor-files.tar.gz" \
  /opt/etc/init.d/S30invnet \
  /opt/etc/init.d/S31invnet-web \
  /opt/etc/init.d/S40invnet-pingcheck \
  /opt/etc/init.d/S41invnet-sched \
  /opt/etc/init.d/S95invnet-autostart \
  /opt/etc/lighttpd/invnet.conf \
  /opt/etc/openvpn/invnet-up.sh \
  /opt/etc/openvpn/invnet-down.sh \
  /opt/etc/openvpn/invnet-fw.sh \
  /opt/etc/ndm/netfilter.d/50-invnet.sh \
  /opt/sbin/invnetctl \
  /opt/share/invnet/invnet-lib.sh \
  /opt/share/invnet/index.html \
  /opt/share/invnet/logo.svg \
  /opt/share/invnet/cgi-bin \

  2>/dev/null

# ipk — все арх-варианты xor-openvpn (мультиарх: aarch64/mipsel/mips)
if ls /opt/share/invnet/ipk/*.ipk >/dev/null 2>&1; then
  cp /opt/share/invnet/ipk/*.ipk "$DEST/"
  echo "[+] ipk-вариантов: $(ls /opt/share/invnet/ipk/*.ipk | wc -l) (install.sh выберет по архитектуре)"
elif [ -f /opt/var/ovpn-xor.ipk ]; then
  cp /opt/var/ovpn-xor.ipk "$DEST/openvpn-openssl-xor.ipk"   # фолбэк на старую схему
else
  echo "[!] ВАЖНО: нет .ipk в /opt/share/invnet/ipk/. Положи openvpn-openssl-xor_*_<arch>.ipk туда."
fi

# Сам install.sh (тот же что ты запускаешь сейчас)
cp /opt/share/invnet/install.sh "$DEST/" 2>/dev/null || \
  echo "[!] install.sh не найден в /opt/share/invnet/. Скопируй вручную."

# === Опционально: пользовательские данные ===
echo
printf "Включить твои текущие профили и настройки? [y/N]: "; read ANS
if [ "$ANS" = "y" ] || [ "$ANS" = "Y" ]; then
  /opt/bin/tar czf "$DEST/vpn-xor-userdata.tar.gz" \
    /opt/etc/openvpn/profiles \
    /opt/etc/openvpn/profile-meta \
    /opt/etc/openvpn/active-profile \
    /opt/etc/openvpn/invnet-mode.conf \
    /opt/etc/openvpn/invnet-devices.conf \
    /opt/etc/openvpn/invnet-routes.conf \
    /opt/etc/openvpn/invnet-autostart.conf \
    2>/dev/null
  echo "[+] Пользовательские данные включены (профили, маршруты, выбранные устройства)"
fi

# Финальный архив
cd /tmp && /opt/bin/tar czf vpn-xor-install.tar.gz vpn-xor-install/
SIZE=$(du -h vpn-xor-install.tar.gz | cut -f1)
rm -rf "$DEST"

echo
echo "========================================="
echo "  Готово: /tmp/vpn-xor-install.tar.gz ($SIZE)"
echo "========================================="
echo
echo "Дальше:"
echo "  1. Скопируй архив на свой комп:"
echo "     scp -O -P 222 root@$(hostname -I 2>/dev/null | awk '{print $1}'):/tmp/vpn-xor-install.tar.gz ."
echo
echo "  2. Закинь на новый Кинетик (с уже установленным Entware):"
echo "     scp -O -P 222 vpn-xor-install.tar.gz root@NEW.KEENETIC.IP:/tmp/"
echo
echo "  3. На новом Кинетике:"
echo "     ssh -p 222 root@NEW.KEENETIC.IP"
echo "     cd /tmp && /opt/bin/tar xzf vpn-xor-install.tar.gz && cd vpn-xor-install"
echo "     sh install.sh"
