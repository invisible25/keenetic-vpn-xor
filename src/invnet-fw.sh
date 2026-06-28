#!/bin/sh
# invnet-fw.sh — ЕДИНЫЙ источник iptables-правил invnet (NAT / forward / MSS-clamp).
#
# Зачем отдельный файл: на Keenetic netfilter принадлежит демону NDM. NDM
# перестраивает iptables «с нуля» на множестве событий (реконнект WAN/PPPoE,
# применение конфига, смена интерфейсов, профиль доступа, расписание) и при этом
# СТИРАЕТ все сторонние правила в таблицах filter/mangle (и иногда nat). Поэтому
# раньше привязанное устройство «со временем» теряло интернет: invnet-up.sh ставил
# FORWARD/MSS, а ближайшее событие NDM их сносило.
#
# Штатный механизм вернуть свои правила на этой платформе — хук-скрипты в
# /opt/etc/ndm/netfilter.d/, которые NDM вызывает ПОСЛЕ каждой перестройки.
# Логика правил живёт ТОЛЬКО здесь и source-ится тремя потребителями:
#   • invnet-up.sh                         — мгновенно при подъёме туннеля;
#   • /opt/etc/ndm/netfilter.d/50-invnet.sh — возврат после перестроек NDM;
#   • init.d/S40invnet-pingcheck       — периодическая страховка (раз в тик).
#
# Ограничения окружения: busybox sh, mips big-endian, БЕЗ сетевых вызовов
# (хук исполняется в единой очереди NDM с таймаутом ~24с).

# Конфиг WAN-политики (устройство → физический WAN-канал). Только локальное
# чтение jq, без сети — ограничение хука соблюдено. Не перетираем, если задан.
: "${WANPOL_FW:=/opt/etc/openvpn/invnet-wan-policy.conf}"
# Конфиг маршрутов (для прямых маршрутов-исключений .direct==true → их WAN).
: "${ROUTES_FW:=/opt/etc/openvpn/invnet-routes.conf}"

# Активные туннели по факту в ядре (быстро, без диска/сети). Если tun_invnet* нет —
# glob остаётся буквальным, [ -e ] его отсекает.
invnet_active_devs() {
  for _p in /sys/class/net/tun_invnet*; do
    [ -e "$_p" ] && echo "${_p##*/}"
  done
}

# Идемпотентно поставить правила для одного DEV.
#   $1 = tun_invnet<slot>
#   $2 = filter|mangle|nat  (необязательно) — поставить ТОЛЬКО эту таблицу
#        (используется хуком: NDM строит таблицы по отдельности). Пусто = все три.
invnet_fw_assert_dev() {
  _dev=$1; _only=$2
  case "${_only:-filter}" in filter)
    iptables -C FORWARD -o "$_dev" -j ACCEPT 2>/dev/null \
      || iptables -A FORWARD -o "$_dev" -j ACCEPT
    iptables -C FORWARD -i "$_dev" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
      || iptables -A FORWARD -i "$_dev" -m state --state RELATED,ESTABLISHED -j ACCEPT
  esac
  case "${_only:-mangle}" in mangle)
    iptables -t mangle -C FORWARD -o "$_dev" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
      || iptables -t mangle -A FORWARD -o "$_dev" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  esac
  case "${_only:-nat}" in nat)
    iptables -t nat -C POSTROUTING -o "$_dev" -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -o "$_dev" -j MASQUERADE
  esac
}

# Снять все правила DEV (в цикле — на случай задвоений). Для invnet-down / stop_one.
invnet_fw_remove_dev() {
  _dev=$1
  while iptables -D FORWARD -o "$_dev" -j ACCEPT 2>/dev/null; do :; done
  while iptables -D FORWARD -i "$_dev" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do :; done
  while iptables -t mangle -D FORWARD -o "$_dev" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
  while iptables -t nat -D POSTROUTING -o "$_dev" -j MASQUERADE 2>/dev/null; do :; done
}

# ── WAN-политика: LAN-устройство → физический WAN-канал (минуя VPN) ──
# Без NAT/FORWARD пакет уходит в WAN с приватным src и попадает под policy DROP
# NDM. Правила точечные по паре (устройство, WAN). Идемпотентно; $1 = таблица
# (filter|nat) для хука, пусто = filter+nat. Mangle для WAN-политики не нужен.
invnet_fw_assert_wanpol() {
  _only=$1
  [ -f "$WANPOL_FW" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.[] | select(.enabled != false) | .wan as $w | .devices[]? | "\($w) \(.)"' "$WANPOL_FW" 2>/dev/null \
  | while read -r _wan _ip; do
    { [ -z "$_wan" ] || [ -z "$_ip" ]; } && continue
    case "${_only:-filter}" in filter)
      iptables -C FORWARD -s "$_ip" -o "$_wan" -j ACCEPT 2>/dev/null \
        || iptables -A FORWARD -s "$_ip" -o "$_wan" -j ACCEPT
      iptables -C FORWARD -d "$_ip" -i "$_wan" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
        || iptables -A FORWARD -d "$_ip" -i "$_wan" -m state --state RELATED,ESTABLISHED -j ACCEPT
    esac
    case "${_only:-nat}" in nat)
      iptables -t nat -C POSTROUTING -s "$_ip" -o "$_wan" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s "$_ip" -o "$_wan" -j MASQUERADE
    esac
  done
}

# Снять все правила WAN-политики ПО ТЕКУЩЕМУ конфигу (включая disabled). Зовётся
# из save-wan-policy ДО перезаписи конфига — тогда снимаются старые пары без
# отдельного state-файла. После записи нового конфига apply переутвердит.
invnet_fw_remove_wanpol() {
  [ -f "$WANPOL_FW" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.[]? | .wan as $w | .devices[]? | "\($w) \(.)"' "$WANPOL_FW" 2>/dev/null \
  | while read -r _wan _ip; do
    { [ -z "$_wan" ] || [ -z "$_ip" ]; } && continue
    while iptables -D FORWARD -s "$_ip" -o "$_wan" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D FORWARD -d "$_ip" -i "$_wan" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do :; done
    while iptables -t nat -D POSTROUTING -s "$_ip" -o "$_wan" -j MASQUERADE 2>/dev/null; do :; done
  done
}

# ── Прямые маршруты-исключения: forwarding/NAT для <cidr> через физический WAN,
# минуя VPN. Правила ТОЧЕЧНЫЕ по паре (cidr, wan) — не пересекаются с broad-правилами
# NDM на том же канале (их нельзя трогать) и безопасно снимаются. $1 = таблица для хука.
invnet_fw_assert_directroutes() {
  _only=$1
  [ -f "$ROUTES_FW" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.[] | select(.enabled != false and .direct == true) | "\(.wan // "") \(.cidr)"' "$ROUTES_FW" 2>/dev/null \
  | while read -r _w _c; do
    { [ -z "$_w" ] || [ -z "$_c" ]; } && continue
    case "${_only:-filter}" in filter)
      iptables -C FORWARD -d "$_c" -o "$_w" -j ACCEPT 2>/dev/null || iptables -A FORWARD -d "$_c" -o "$_w" -j ACCEPT
      iptables -C FORWARD -s "$_c" -i "$_w" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
        || iptables -A FORWARD -s "$_c" -i "$_w" -m state --state RELATED,ESTABLISHED -j ACCEPT
    esac
    case "${_only:-nat}" in nat)
      iptables -t nat -C POSTROUTING -d "$_c" -o "$_w" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -d "$_c" -o "$_w" -j MASQUERADE
    esac
  done
}

# Снять точечные правила прямых маршрутов ПО ТЕКУЩЕМУ конфигу (включая disabled).
# Зовётся из cgi-bin/routes ДО перезаписи конфига — старые пары снимаются без state.
invnet_fw_remove_directroutes() {
  [ -f "$ROUTES_FW" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.[]? | select(.direct == true) | "\(.wan // "") \(.cidr)"' "$ROUTES_FW" 2>/dev/null \
  | while read -r _w _c; do
    { [ -z "$_w" ] || [ -z "$_c" ]; } && continue
    while iptables -D FORWARD -d "$_c" -o "$_w" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D FORWARD -s "$_c" -i "$_w" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do :; done
    while iptables -t nat -D POSTROUTING -d "$_c" -o "$_w" -j MASQUERADE 2>/dev/null; do :; done
  done
}

# Переутвердить все активные туннели + WAN-политику + прямые маршруты.
# $1 (необязательно) = таблица (для хука).
invnet_fw_assert_all() {
  for _d in $(invnet_active_devs); do invnet_fw_assert_dev "$_d" "$1"; done
  invnet_fw_assert_wanpol "$1"
  invnet_fw_assert_directroutes "$1"
}
