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
  /opt/etc/init.d/S30vpn-aim \
  /opt/etc/init.d/S31vpn-aim-web \
  /opt/etc/init.d/S41vpn-aim-sched \
  /opt/etc/init.d/S95vpn-aim-autostart \
  /opt/etc/lighttpd/vpn-aim.conf \
  /opt/etc/openvpn/aim-up.sh \
  /opt/etc/openvpn/aim-down.sh \
  /opt/sbin/aim-manager.sh \
  /opt/share/vpn-aim/index.html \
  /opt/share/vpn-aim/logo.svg \
  /opt/share/vpn-aim/cgi-bin \

  2>/dev/null

# ipk — все арх-варианты xor-openvpn (мультиарх: aarch64/mipsel/mips)
if ls /opt/share/vpn-aim/ipk/*.ipk >/dev/null 2>&1; then
  cp /opt/share/vpn-aim/ipk/*.ipk "$DEST/"
  echo "[+] ipk-вариантов: $(ls /opt/share/vpn-aim/ipk/*.ipk | wc -l) (install.sh выберет по архитектуре)"
elif [ -f /opt/var/ovpn-xor.ipk ]; then
  cp /opt/var/ovpn-xor.ipk "$DEST/openvpn-openssl-xor.ipk"   # фолбэк на старую схему
else
  echo "[!] ВАЖНО: нет .ipk в /opt/share/vpn-aim/ipk/. Положи openvpn-openssl-xor_*_<arch>.ipk туда."
fi

# Сам install.sh (тот же что ты запускаешь сейчас)
cp /opt/share/vpn-aim/install.sh "$DEST/" 2>/dev/null || \
  echo "[!] install.sh не найден в /opt/share/vpn-aim/. Скопируй вручную."

# === Опционально: пользовательские данные ===
echo
printf "Включить твои текущие профили и настройки? [y/N]: "; read ANS
if [ "$ANS" = "y" ] || [ "$ANS" = "Y" ]; then
  /opt/bin/tar czf "$DEST/vpn-xor-userdata.tar.gz" \
    /opt/etc/openvpn/profiles \
    /opt/etc/openvpn/profile-meta \
    /opt/etc/openvpn/active-profile \
    /opt/etc/openvpn/aim-mode.conf \
    /opt/etc/openvpn/aim-devices.conf \
    /opt/etc/openvpn/aim-routes.conf \
    /opt/etc/openvpn/aim-autostart.conf \
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
