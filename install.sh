#!/bin/sh
# VPN+XOR — установщик. Должен быть запущен из директории где лежит
# tarball vpn-xor-files.tar.gz и openvpn-openssl-xor.ipk.
#
#   cd /tmp/vpn-xor-install && sh install.sh
#
# Требования:
#   - Кинетик с Entware (aarch64-3.10_kn)
#   - Интернет на роутере (для opkg)

set -e

# === Цвета для красоты ===
info()  { printf "\033[1;36m[i]\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m[+]\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31m[-]\033[0m %s\n" "$1"; exit 1; }

# === Таймаут для сетевых команд ===
# opkg update/install на недоступном/медленном интернете может висеть бесконечно.
# Оборачиваем в `timeout`, если он есть (busybox/coreutils). Иначе — как есть.
TIMEOUT_BIN=$(command -v timeout 2>/dev/null || true)
run_t() {  # run_t <секунды> <команда...>
  _t=$1; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$_t" "$@"
  else
    "$@"
  fi
}

# === Проверки ===
info "Проверка Entware..."
[ -x /opt/bin/opkg ] || fail "Entware не установлен. Сначала установи Entware через USB-диск (см. документацию Keenetic OPKG)."

ARCH=$(/opt/bin/opkg print-architecture 2>/dev/null | grep '_kn' | awk '{print $2}' | sed 's/_kn.*//' | head -1)
ok "Архитектура: $ARCH"
case "$ARCH" in
  aarch64-3.10|mipsel-3.4|mips-3.4) : ;;
  *) fail "Неподдерживаемая архитектура: '$ARCH'. Поддерживаются: aarch64-3.10 (ARM: MT7981/86/88), mipsel-3.4 (MIPS LE: MT7621/7628), mips-3.4 (MIPS BE: EcoNet EN751x)." ;;
esac

# === Файлы пакета — должны лежать рядом ===
DIR=$(dirname "$0")
[ -f "$DIR/vpn-xor-files.tar.gz" ] || fail "Не найден vpn-xor-files.tar.gz в $DIR"
# .ipk под нашу архитектуру (с фолбэком на любой openvpn-openssl-xor*.ipk для совместимости)
IPK=$(ls "$DIR"/openvpn-openssl-xor_*_"$ARCH".ipk 2>/dev/null | head -1)
[ -n "$IPK" ] || IPK=$(ls "$DIR"/openvpn-openssl-xor*.ipk 2>/dev/null | head -1)
[ -n "$IPK" ] || fail "Не найден openvpn-openssl-xor .ipk под $ARCH в $DIR"

# === Зависимости Entware ===
info "opkg update..."
run_t 120 /opt/bin/opkg update >/dev/null 2>&1 || warn "opkg update вернул ошибку/таймаут, продолжаем"

info "Установка зависимостей (jq, lighttpd, iptables, ip-full)..."
run_t 300 /opt/bin/opkg install jq lighttpd lighttpd-mod-cgi iptables ip-full curl tar 2>&1 | grep -E 'Installing|Configuring' || true

# === XOR-патченый openvpn (ipk) ===
info "Установка openvpn с XOR-патчем ($(basename "$IPK"))..."
run_t 180 /opt/bin/opkg install --force-overwrite --force-reinstall "$IPK" 2>&1 | tail -5

/opt/sbin/openvpn --version 2>&1 | head -1
strings /opt/sbin/openvpn 2>/dev/null | grep -qi scramble && ok "XOR-патч в /opt/sbin/openvpn активен" || warn "scramble-строки не найдены"

# === Распаковываем файлы приложения ===
info "Распаковка файлов VPN+XOR в /opt..."
/opt/bin/tar xzf "$DIR/vpn-xor-files.tar.gz" -C /

# Права
chmod +x /opt/etc/init.d/S30invnet 2>/dev/null
chmod +x /opt/etc/init.d/S31invnet-web 2>/dev/null
chmod +x /opt/etc/init.d/S40invnet-pingcheck 2>/dev/null
chmod +x /opt/etc/init.d/S41invnet-sched 2>/dev/null
chmod +x /opt/etc/init.d/S95invnet-autostart 2>/dev/null
chmod +x /opt/sbin/invnetctl 2>/dev/null
chmod +x /opt/etc/openvpn/invnet-up.sh /opt/etc/openvpn/invnet-down.sh 2>/dev/null
chmod +x /opt/etc/openvpn/invnet-fw.sh 2>/dev/null
mkdir -p /opt/etc/ndm/netfilter.d
chmod +x /opt/etc/ndm/netfilter.d/50-invnet.sh 2>/dev/null
chmod +x /opt/share/invnet/cgi-bin/* 2>/dev/null

# === Восстановление пользовательских данных (если есть в архиве) ===
# Распаковываем ДО создания дефолтных конфигов — guard'ы ниже их не перетрут.
if [ -f "$DIR/vpn-xor-userdata.tar.gz" ]; then
  info "Восстановление профилей и настроек из vpn-xor-userdata.tar.gz..."
  /opt/bin/tar xzf "$DIR/vpn-xor-userdata.tar.gz" -C /
  chmod 600 /opt/etc/openvpn/profiles/*.ovpn 2>/dev/null || true
  ok "Профили и настройки восстановлены"
fi

# === Дефолтные конфиги (не перезаписываем существующие) ===
mkdir -p /opt/etc/openvpn/profiles /opt/etc/openvpn/profile-meta /opt/var/run /opt/var/log
[ -f /opt/etc/openvpn/invnet-mode.conf ]      || echo devices > /opt/etc/openvpn/invnet-mode.conf
[ -f /opt/etc/openvpn/invnet-devices.conf ]   || : > /opt/etc/openvpn/invnet-devices.conf
[ -f /opt/etc/openvpn/invnet-routes.conf ]    || echo '[]' > /opt/etc/openvpn/invnet-routes.conf
[ -f /opt/etc/openvpn/invnet-autostart.conf ] || echo no > /opt/etc/openvpn/invnet-autostart.conf

# === Pubkey для dropbear (необязательно, упрощает SSH) ===
DB_INIT=/opt/etc/init.d/S51dropbear
if [ -f "$DB_INIT" ] && ! grep -q 'D /opt/root/\.ssh' "$DB_INIT"; then
  info "Патчу дропбир для pubkey-auth (HOME из /opt/root/)..."
  sed -i 's|\$DROPBEAR -p \$PORT -P \$PIDFILE|& -D /opt/root/.ssh|' "$DB_INIT"
fi

# === Стартуем сервисы ===
# ВАЖНО: init-скрипты форкают фоновые демоны (lighttpd, loop &), которые
# наследуют stdout. Нельзя пускать их через pipe `| head` — head ждёт EOF,
# а демон держит stdout открытым => установка зависает («sched: started PID=...»).
# Поэтому глушим stdout демонов через `>/dev/null 2>&1` и выводим свой статус.
info "Старт веб-сервера..."
/opt/etc/init.d/S31invnet-web start >/dev/null 2>&1 \
  && ok "веб-сервер запущен" || warn "веб-сервер не стартовал (см. /opt/var/log/invnet-web.err)"

info "Старт планировщика расписаний..."
/opt/etc/init.d/S41invnet-sched start >/dev/null 2>&1 \
  && ok "планировщик запущен" || warn "планировщик не стартовал"

info "Старт watchdog (автопереподключение)..."
/opt/etc/init.d/S40invnet-pingcheck start >/dev/null 2>&1 \
  && ok "watchdog запущен" || warn "watchdog не стартовал"

# === Поднять профили, помеченные enabled (мульти-профиль) ===
# reconcile поднимает OpenVPN с XOR-хендшейком — может тянуться долго.
# На свежей установке профилей нет (быстро). stdout глушим, чтобы фоновые
# процессы openvpn не держали pipe; ошибки не валят установку (|| true).
if [ -x /opt/sbin/invnetctl ]; then
  info "Запуск активных профилей (reconcile)..."
  /opt/sbin/invnetctl reconcile >/dev/null 2>&1 || true
  ok "профили приведены в соответствие"
fi

# === Проверяем, что службы реально поднялись ===
info "Проверяю, что всё запустилось..."
HEALTH_OK=yes
# Веб-панель: не просто «процесс есть», а реально отвечает на порту 8888.
if curl -s -o /dev/null --max-time 4 http://127.0.0.1:8888/ 2>/dev/null; then
  ok "веб-панель отвечает на порту 8888"
else
  HEALTH_OK=no
  warn "веб-панель не отвечает. Запусти вручную:  /opt/etc/init.d/S31invnet-web start"
  warn "и загляни в лог:  /opt/var/log/invnet-web.err"
fi
# Планировщик расписаний.
if /opt/etc/init.d/S41invnet-sched status 2>/dev/null | grep -qi running; then
  ok "планировщик расписаний работает"
else
  HEALTH_OK=no
  warn "планировщик не запущен. Запусти:  /opt/etc/init.d/S41invnet-sched start"
fi
if /opt/etc/init.d/S40invnet-pingcheck status 2>/dev/null | grep -qi running; then
  ok "watchdog переподключений работает"
else
  HEALTH_OK=no
  warn "watchdog не запущен. Запусти:  /opt/etc/init.d/S40invnet-pingcheck start"
fi

# === Финал ===
# Робастное определение LAN-IP роутера (для ссылки http://<IP>:8888/).
# Подсеть и имя моста у разных Keenetic РАЗНЫЕ (br0/br1, 192.168.1.1 /
# 192.168.88.1 / 10.x …), поэтому НЕ хардкодим. Несколько способов по порядку:
#   1) NDM RCI: спросить адрес LAN-бриджа (Bridge0) у системы Keenetic;
#   2) перебрать мосты br0/br1/… через `ip -4 addr` и взять приватный IP;
#   3) hostname -i — первый приватный адрес;
#   4) дефолт 192.168.1.1 (как самый частый).
# Туннели tun_invnet* и loopback исключаем.

# Приватный IPv4? (10.0.0.0/8, 172.16-31.0.0/12, 192.168.0.0/16)
is_private_ip() {
  case "$1" in
    10.*|192.168.*) return 0 ;;
    172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    *) return 1 ;;
  esac
}

IP=""

# --- Способ 1: NDM RCI (Keenetic) — адрес LAN-бриджа Bridge0 ---
if command -v curl >/dev/null 2>&1; then
  RCI=$(curl -s --max-time 3 http://127.0.0.1:79/rci/show/interface/Bridge0 2>/dev/null)
  # ищем "address": "192.168.x.x" (jq если есть, иначе grep)
  if [ -n "$RCI" ]; then
    if command -v jq >/dev/null 2>&1; then
      CAND=$(printf '%s' "$RCI" | jq -r '.address // empty' 2>/dev/null)
    else
      CAND=$(printf '%s' "$RCI" | grep -o '"address"[^,]*' | grep -o '[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}' | head -1)
    fi
    if [ -n "$CAND" ] && is_private_ip "$CAND"; then IP="$CAND"; fi
  fi
fi

# --- Способ 2: перебор мостов через ip -4 addr (br0, br1, ...) ---
if [ -z "$IP" ] && [ -x /opt/sbin/ip ]; then
  for IFACE in br0 br1 br2 br3; do
    CAND=$(/opt/sbin/ip -4 addr show "$IFACE" 2>/dev/null \
           | awk '/inet /{split($2,a,"/"); print a[1]; exit}')
    if [ -n "$CAND" ] && is_private_ip "$CAND"; then IP="$CAND"; break; fi
  done
fi

# --- Способ 2b: любой интерфейс с приватным IP, кроме туннелей tun_invnet* и lo ---
if [ -z "$IP" ] && [ -x /opt/sbin/ip ]; then
  CAND=$(/opt/sbin/ip -4 -o addr show 2>/dev/null \
         | awk '$2 !~ /^(lo|tun_invnet)/ {split($4,a,"/"); print a[1]}' \
         | while read -r a; do
             case "$a" in
               10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) echo "$a"; break ;;
             esac
           done)
  [ -n "$CAND" ] && IP="$CAND"
fi

# --- Способ 3: hostname -i ---
if [ -z "$IP" ]; then
  for CAND in $(hostname -i 2>/dev/null); do
    if is_private_ip "$CAND"; then IP="$CAND"; break; fi
  done
fi

# --- Способ 4: дефолт ---
[ -z "$IP" ] && IP="192.168.1.1"

echo
ok "=========================================="
ok "  VPN+XOR установлен"
ok "  Открой:  http://$IP:8888/"
ok "=========================================="
echo
echo "Что дальше:"
echo "  1. Открой http://$IP:8888/ в браузере — с любого устройства в сети роутера."
echo "  2. Вкладка «Профили» → вставь свой .ovpn → «Сохранить»."
echo "  3. Включи профиль тумблером и подожди 10-20 секунд (идёт XOR-хендшейк)."
echo "  4. Вкладка «Устройства» → отметь, кто пойдёт через VPN."
echo
echo "  Если у роутера несколько каналов в интернет или включён штатный VPN Keenetic —"
echo "  выбери в профиле физический WAN (вкладка «Профили» → ✎). Иначе openvpn может"
echo "  уходить мимо нужного канала, и подключение не поднимется."
echo
echo "Если что-то не так — проверь по SSH:"
echo "  /opt/sbin/invnetctl status              # какие профили подняты"
echo "  /opt/etc/init.d/S31invnet-web status        # веб-панель"
echo "  /opt/etc/init.d/S40invnet-pingcheck status  # watchdog переподключений
  /opt/etc/init.d/S41invnet-sched status      # планировщик"
echo "  tail -f /opt/var/log/invnet-<профиль>.log   # лог openvpn нужного профиля"
[ "$HEALTH_OK" = no ] && warn "Часть служб не поднялась — см. подсказки выше."
