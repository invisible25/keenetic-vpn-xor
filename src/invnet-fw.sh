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

# iptables с повтором при занятой блокировке xtables. Пока NDM перестраивает netfilter,
# любой наш вызов падает с кодом 4 («Another app is currently holding the xtables lock»).
# Раньше `-C` в этот момент «не находил» правило, и следом `-A` добавлял его ещё раз:
# на 88.1 за несколько дней набралось до 4 копий каждого правила прямых маршрутов.
# -w не берём: в iptables 1.4.21 он ждёт бесконечно, а хук NDM обязан уложиться в ~24с.
ipt() {
  _k=0
  while :; do
    iptables "$@" 2>/dev/null; _rc=$?
    [ "$_rc" -eq 4 ] || return "$_rc"
    _k=$((_k+1)); [ "$_k" -ge 40 ] && return "$_rc"
    sleep 0.25 2>/dev/null || sleep 1
  done
}

# Снимок цепочки в формате `iptables -S` (строка = правило). $1=таблица $2=цепочка.
ipt_snap() {
  _k=0
  while :; do
    _snap=$(iptables -t "$1" -S "$2" 2>/dev/null); _rc=$?
    [ "$_rc" -eq 4 ] || break
    _k=$((_k+1)); [ "$_k" -ge 40 ] && break
    sleep 0.25 2>/dev/null || sleep 1
  done
  [ "$_rc" -eq 0 ] && printf '%s\n' "$_snap"
  return "$_rc"
}

# Привести желаемые правила к виду из снимка: одна сверка вместо вызова iptables на КАЖДОЕ
# правило. На слабом Giga SE вызов стоит ~15мс, а на 126 прямых маршрутов их было 378 при
# каждой проверке — несколько секунд на тик сторожа и 25–30с на одну правку маршрута в панели.
#   $1 = таблица, $2 = цепочка, stdin = желаемые правила в формате `-A <цепочка> …`
# Недостающие ставит (сперва -C: если адрес записан не в том виде, в каком его печатает
# iptables, снимок правило не найдёт, а -C найдёт — дубля не будет), лишние копии снимает.
# Правила, которых нет в желаемом списке, НЕ трогает: цепочки общие с NDM.
ipt_sync() {
  _tbl=$1; _ch=$2
  _want=$(cat)
  [ -n "$_want" ] || return 0
  # снимок — во временный файл, а не в awk -v: цепочки NDM бывают в сотни строк
  _sf="/tmp/.invnet-ipt.$$"
  ipt_snap "$_tbl" "$_ch" > "$_sf" || : > "$_sf"
  # FILENAME, а не NR==FNR: при пустом снимке (цепочка пуста, снимок не удался) NR==FNR
  # остаётся истинным и для желаемого списка — он весь ушёл бы в «уже есть»
  printf '%s\n' "$_want" | awk -v snap="$_sf" '
    FILENAME == snap { if ($0 != "") cnt[$0]++; next }
    $0 == "" || seen[$0]++ { next }
    { c = cnt[$0] + 0
      if (c == 0) print "ADD " $0
      else for (k = 1; k < c; k++) print "DUP " $0 }' "$_sf" - \
  | while read -r _op _line; do
      _spec=${_line#-A }
      case "$_op" in
        ADD) ipt -t "$_tbl" -C $_spec || ipt -t "$_tbl" -A $_spec ;;
        DUP) ipt -t "$_tbl" -D $_spec ;;
      esac
    done
  rm -f "$_sf"
}

# CIDR в том виде, как его печатает `iptables -S`: адрес сети без хостовых битов и маска
# всегда явно (/32 для одиночного адреса). Вход и выход — строки «<канал> <cidr>».
invnet_fw_norm_pairs() {
  awk 'NF == 2 { split($2, p, "/"); pre = (p[2] == "" ? 32 : p[2] + 0)
         if (split(p[1], o, ".") != 4) next
         ip = ((o[1] * 256 + o[2]) * 256 + o[3]) * 256 + o[4]
         b = 2 ^ (32 - pre); ip = int(ip / b) * b
         a = int(ip / 16777216); ip -= a * 16777216
         c2 = int(ip / 65536); ip -= c2 * 65536
         c3 = int(ip / 256); c4 = ip - c3 * 256
         printf "%s %d.%d.%d.%d/%d\n", $1, a, c2, c3, c4, pre }'
}

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
    ipt -C FORWARD -o "$_dev" -j ACCEPT || ipt -A FORWARD -o "$_dev" -j ACCEPT
    ipt -C FORWARD -i "$_dev" -m state --state RELATED,ESTABLISHED -j ACCEPT \
      || ipt -A FORWARD -i "$_dev" -m state --state RELATED,ESTABLISHED -j ACCEPT
  esac
  case "${_only:-mangle}" in mangle)
    ipt -t mangle -C FORWARD -o "$_dev" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu \
      || ipt -t mangle -A FORWARD -o "$_dev" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  esac
  case "${_only:-nat}" in nat)
    ipt -t nat -C POSTROUTING -o "$_dev" -j MASQUERADE || ipt -t nat -A POSTROUTING -o "$_dev" -j MASQUERADE
  esac
}

# Снять все правила DEV (в цикле — на случай задвоений). Для invnet-down / stop_one.
invnet_fw_remove_dev() {
  _dev=$1
  while ipt -D FORWARD -o "$_dev" -j ACCEPT; do :; done
  while ipt -D FORWARD -i "$_dev" -m state --state RELATED,ESTABLISHED -j ACCEPT; do :; done
  while ipt -t mangle -D FORWARD -o "$_dev" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; do :; done
  while ipt -t nat -D POSTROUTING -o "$_dev" -j MASQUERADE; do :; done
}

# ── WAN-политика: LAN-устройство → физический WAN-канал (минуя VPN) ──
# Без NAT/FORWARD пакет уходит в WAN с приватным src и попадает под policy DROP
# NDM. Правила точечные по паре (устройство, WAN). Идемпотентно; $1 = таблица
# (filter|nat) для хука, пусто = filter+nat. Mangle для WAN-политики не нужен.

# Пары «<wan> <ip>/32» включённых записей.
invnet_fw_wanpol_pairs() {
  [ -f "$WANPOL_FW" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.[] | select(.enabled != false) | .wan as $w | .devices[]? | "\($w) \(.)"' "$WANPOL_FW" 2>/dev/null \
    | invnet_fw_norm_pairs
}

invnet_fw_assert_wanpol() {
  _only=$1
  _p=$(invnet_fw_wanpol_pairs); [ -n "$_p" ] || return 0
  case "${_only:-filter}" in filter)
    printf '%s\n' "$_p" | awk '{
        print "-A FORWARD -s " $2 " -o " $1 " -j ACCEPT"
        print "-A FORWARD -d " $2 " -i " $1 " -m state --state RELATED,ESTABLISHED -j ACCEPT" }' \
      | ipt_sync filter FORWARD
  esac
  case "${_only:-nat}" in nat)
    printf '%s\n' "$_p" | awk '{ print "-A POSTROUTING -s " $2 " -o " $1 " -j MASQUERADE" }' \
      | ipt_sync nat POSTROUTING
  esac
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
    while ipt -D FORWARD -s "$_ip" -o "$_wan" -j ACCEPT; do :; done
    while ipt -D FORWARD -d "$_ip" -i "$_wan" -m state --state RELATED,ESTABLISHED -j ACCEPT; do :; done
    while ipt -t nat -D POSTROUTING -s "$_ip" -o "$_wan" -j MASQUERADE; do :; done
  done
}

# ── Прямые маршруты-исключения: forwarding/NAT для <cidr> через физический WAN,
# минуя VPN. Правила ТОЧЕЧНЫЕ по паре (cidr, wan) — не пересекаются с broad-правилами
# NDM на том же канале (их нельзя трогать) и безопасно снимаются. $1 = таблица для хука.

# Пары «<wan> <cidr>» прямых маршрутов. $1 = enabled (только включённые, по умолчанию)
# или all (включая выключенные — всё, для чего invnet мог когда-то поставить правила).
invnet_fw_directroute_pairs() {
  [ -f "$ROUTES_FW" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  if [ "$1" = "all" ]; then
    jq -r '.[]? | select(.direct == true) | "\(.wan // "") \(.cidr)"' "$ROUTES_FW" 2>/dev/null
  else
    jq -r '.[]? | select(.enabled != false and .direct == true) | "\(.wan // "") \(.cidr)"' "$ROUTES_FW" 2>/dev/null
  fi | invnet_fw_norm_pairs
}

invnet_fw_assert_directroutes() {
  _only=$1
  _p=$(invnet_fw_directroute_pairs enabled); [ -n "$_p" ] || return 0
  case "${_only:-filter}" in filter)
    printf '%s\n' "$_p" | awk '{
        print "-A FORWARD -d " $2 " -o " $1 " -j ACCEPT"
        print "-A FORWARD -s " $2 " -i " $1 " -m state --state RELATED,ESTABLISHED -j ACCEPT" }' \
      | ipt_sync filter FORWARD
  esac
  case "${_only:-nat}" in nat)
    printf '%s\n' "$_p" | awk '{ print "-A POSTROUTING -d " $2 " -o " $1 " -j MASQUERADE" }' \
      | ipt_sync nat POSTROUTING
  esac
}

# Снять правила перечисленных пар (stdin: «<wan> <cidr>»), вместе со всеми копиями.
invnet_fw_remove_directroute_pairs() {
  while read -r _w _c; do
    { [ -z "$_w" ] || [ -z "$_c" ]; } && continue
    while ipt -D FORWARD -d "$_c" -o "$_w" -j ACCEPT; do :; done
    while ipt -D FORWARD -s "$_c" -i "$_w" -m state --state RELATED,ESTABLISHED -j ACCEPT; do :; done
    while ipt -t nat -D POSTROUTING -d "$_c" -o "$_w" -j MASQUERADE; do :; done
  done
}

# Снять правила только тех пар, что были в конфиге ДО правки ($1 = вывод
# `invnet_fw_directroute_pairs all`, снятый до записи), но не остались включёнными после.
# Прежде cgi-bin/routes снимал ВСЕ пары до записи, а apply ставил их обратно: на 126 прямых
# маршрутах это ~750 вызовов iptables на один щелчок тумблера.
invnet_fw_prune_directroutes() {
  [ -n "$1" ] || return 0
  _kf="/tmp/.invnet-keep.$$"
  invnet_fw_directroute_pairs enabled > "$_kf"
  printf '%s\n' "$1" | awk -v keep="$_kf" 'FILENAME == keep { K[$0] = 1; next } $0 != "" && !($0 in K) && !seen[$0]++' "$_kf" - \
    | invnet_fw_remove_directroute_pairs
  rm -f "$_kf"
}

# Снять правила ВСЕХ прямых маршрутов текущего конфига (включая выключенные).
invnet_fw_remove_directroutes() {
  invnet_fw_directroute_pairs all | invnet_fw_remove_directroute_pairs
}

# Переутвердить все активные туннели + WAN-политику + прямые маршруты.
# $1 (необязательно) = таблица (для хука).
invnet_fw_assert_all() {
  for _d in $(invnet_active_devs); do invnet_fw_assert_dev "$_d" "$1"; done
  invnet_fw_assert_wanpol "$1"
  invnet_fw_assert_directroutes "$1"
}
