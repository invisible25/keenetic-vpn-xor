#!/bin/sh
# aim-manager.sh — оркестратор нескольких VPN+XOR профилей одновременно.
#
# Модель (Вариант А — по устройствам):
#   • каждый ВКЛЮЧЁННЫЙ профиль = свой openvpn-процесс на tun_aim<slot> + таблица 101+slot
#   • устройства/CIDR профиля → ip rule from/to ... lookup <table>
#   • источник истины «включён ли профиль» — ключ "enabled" в profile-meta/<name>.json
#
# Команды:
#   aim-manager.sh enable  <profile>   — пометить enabled + reconcile
#   aim-manager.sh disable <profile>   — снять enabled + reconcile
#   aim-manager.sh reconcile           — привести факт к желаемому (старт/стоп инстансов) + правила
#   aim-manager.sh apply               — только переразложить ip rule (devices/routesменялись)
#   aim-manager.sh stopall             — остановить все инстансы
#   aim-manager.sh status              — JSON со всеми профилями и их состоянием
#   aim-manager.sh schedule-tick       — исполнить события расписаний с прошлого тика (зовёт S41)
#   aim-manager.sh schedule-sync [p]   — привести enabled к расписанию (старт демона/правка)

export PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

CONF=/opt/etc/openvpn
PROFILES=$CONF/profiles
META=$CONF/profile-meta
ROUTES_FILE=$CONF/aim-routes.conf
RUN=/opt/var/run/aim
LOGDIR=/opt/var/log
BIN=/opt/sbin/openvpn
UP=$CONF/aim-up.sh
DOWN=$CONF/aim-down.sh
MAXSLOT=7
LANIF="br0 br1"

mkdir -p "$RUN" "$META" "$LOGDIR"

# ---- helpers ----
meta_get() { jq -r "$2 // empty" "$META/$1.json" 2>/dev/null; }

is_enabled() { [ "$(meta_get "$1" '.enabled')" = "true" ]; }

set_meta_enabled() {
  if [ -f "$META/$1.json" ]; then
    jq ".enabled=$2" "$META/$1.json" > "$META/$1.json.tmp" 2>/dev/null && mv "$META/$1.json.tmp" "$META/$1.json"
  else
    echo "{\"enabled\":$2}" > "$META/$1.json"
  fi
}

slot_of() { cat "$RUN/$1.slot" 2>/dev/null; }

pid_of() { cat "$RUN/$1.pid" 2>/dev/null; }

is_running() {
  P=$(pid_of "$1"); [ -n "$P" ] && kill -0 "$P" 2>/dev/null
}

used_slots() { cat "$RUN"/*.slot 2>/dev/null; }

alloc_slot() {
  # уже есть — вернуть
  s=$(slot_of "$1"); [ -n "$s" ] && { echo "$s"; return; }
  used=" $(used_slots | tr '\n' ' ') "
  i=0
  while [ "$i" -le "$MAXSLOT" ]; do
    case "$used" in *" $i "*) : ;; *) echo "$i" > "$RUN/$1.slot"; echo "$i"; return;; esac
    i=$((i+1))
  done
  return 1   # нет свободных слотов
}

# ---- запуск одного профиля ----
start_one() {
  PROFILE=$1
  CFG="$PROFILES/$PROFILE.ovpn"
  [ -f "$CFG" ] || { echo "[$PROFILE] нет конфига"; return 1; }
  is_running "$PROFILE" && return 0

  SLOT=$(alloc_slot "$PROFILE") || { echo "[$PROFILE] нет свободных слотов"; return 1; }
  DEV="tun_aim$SLOT"
  PIDF="$RUN/$PROFILE.pid"
  LOGF="$LOGDIR/vpn-aim-$PROFILE.log"

  # снять застрявший интерфейс этого слота
  n=0
  while ip link show "$DEV" >/dev/null 2>&1; do
    ip link set "$DEV" down 2>/dev/null; ip link delete "$DEV" 2>/dev/null
    n=$((n+1)); [ "$n" -ge 20 ] && break; sleep 0.2 2>/dev/null || sleep 1
  done

  # WAN-policy: трафик к VPN-серверам этого профиля через выбранный канал
  WAN=$(meta_get "$PROFILE" '.wan')
  if [ -n "$WAN" ]; then
    PRIO=$((30 + SLOT))   # WAN-policy: выше правил устройств, но ниже системных
    for r in $(grep -E '^remote ' "$CFG" 2>/dev/null | awk '{print $2}' | sort -u); do
      case "$r" in
        *[a-z]*) IP=$(nslookup "$r" 2>/dev/null | awk '/^Address [0-9]/{print $3; exit}') ;;
        *)       IP="$r" ;;
      esac
      [ -n "$IP" ] && ip rule add to "$IP" oif "$WAN" priority "$PRIO" 2>/dev/null
    done
  fi

  "$BIN" \
    --config "$CFG" \
    --dev "$DEV" --dev-type tun \
    --setenv AIM_PROFILE "$PROFILE" \
    --setenv AIM_SLOT "$SLOT" \
    --daemon "vpn-aim-$PROFILE" --writepid "$PIDF" --log-append "$LOGF" \
    --script-security 2 \
    --route-nopull \
    --pull-filter ignore "redirect-gateway" \
    --pull-filter ignore "route" \
    --pull-filter ignore "dhcp-option" \
    --up "$UP" --down "$DOWN" --route-up "$UP"
  echo "[$PROFILE] start slot=$SLOT dev=$DEV"
}

# ---- остановка одного профиля ----
stop_one() {
  PROFILE=$1
  SLOT=$(slot_of "$PROFILE")
  P=$(pid_of "$PROFILE")
  [ -n "$P" ] && kill "$P" 2>/dev/null
  i=0; while [ -n "$P" ] && kill -0 "$P" 2>/dev/null; do i=$((i+1)); [ "$i" -ge 6 ] && kill -9 "$P" 2>/dev/null; sleep 1; done
  rm -f "$RUN/$PROFILE.pid"
  if [ -n "$SLOT" ]; then
    TABLE=$((101 + SLOT))
    PRIOW=$((30 + SLOT))
    while ip rule del table "$TABLE" 2>/dev/null; do :; done
    while ip rule del priority "$PRIOW" 2>/dev/null; do :; done
    ip route flush table "$TABLE" 2>/dev/null
    DEV="tun_aim$SLOT"
    iptables -t nat -D POSTROUTING -o "$DEV" -j MASQUERADE 2>/dev/null
    ip link show "$DEV" >/dev/null 2>&1 && ip link delete "$DEV" 2>/dev/null
  fi
  rm -f "$RUN/$PROFILE.slot"
  echo "[$PROFILE] stop"
}

# ---- разложить ip rule для одного профиля (по его meta + глобальным CIDR) ----
apply_one() {
  PROFILE=$1
  SLOT=$(slot_of "$PROFILE"); [ -z "$SLOT" ] && return 0
  DEV="tun_aim$SLOT"; TABLE=$((101 + SLOT))
  ip link show "$DEV" >/dev/null 2>&1 || return 0

  # default route в таблицу профиля
  ip route flush table "$TABLE" 2>/dev/null
  ip route add default dev "$DEV" table "$TABLE" 2>/dev/null

  # очистить старые from/to правила этого профиля и заново.
  # Приоритеты ниже 100 — чтобы перебить fwmark-правила Keenetic (политики доступа, prio 100-110).
  P_DEV=$((50 + SLOT)); P_ALL=$((70 + SLOT))
  while ip rule del priority "$P_DEV" 2>/dev/null; do :; done
  while ip rule del priority "$P_ALL" 2>/dev/null; do :; done

  MODE=$(meta_get "$PROFILE" '.mode'); [ -z "$MODE" ] && MODE=devices
  if [ "$MODE" = "all" ]; then
    for L in $LANIF; do ip rule add iif "$L" lookup "$TABLE" priority "$P_ALL" 2>/dev/null; done
  else
    meta_get "$PROFILE" '.devices[]?' | while read -r ip; do
      ip=$(echo "$ip" | tr -d '[:space:]'); [ -z "$ip" ] && continue
      ip rule add from "$ip" lookup "$TABLE" priority "$P_DEV" 2>/dev/null
    done
  fi
}

# ---- глобальные CIDR-маршруты → через primary (минимальный slot) активный профиль ----
apply_routes() {
  P_CIDR=40
  while ip rule del priority "$P_CIDR" 2>/dev/null; do :; done
  [ -f "$ROUTES_FILE" ] || return 0
  # primary = профиль с минимальным слотом среди запущенных
  PRIMARY=""; MINSLOT=99
  for sf in "$RUN"/*.slot; do
    [ -f "$sf" ] || continue
    pr=$(basename "$sf" .slot); s=$(cat "$sf")
    is_running "$pr" || continue
    [ "$s" -lt "$MINSLOT" ] && { MINSLOT=$s; PRIMARY=$pr; }
  done
  [ -z "$PRIMARY" ] && return 0
  TABLE=$((101 + MINSLOT))
  jq -r '.[] | select(.enabled != false) | .cidr' "$ROUTES_FILE" 2>/dev/null | while read -r cidr; do
    cidr=$(echo "$cidr" | tr -d '[:space:]'); [ -z "$cidr" ] && continue
    ip rule add to "$cidr" lookup "$TABLE" priority "$P_CIDR" 2>/dev/null
  done
}

# ---- reconcile: факт → желаемое ----
reconcile() {
  for f in "$PROFILES"/*.ovpn; do
    [ -f "$f" ] || continue
    pr=$(basename "$f" .ovpn)
    if is_enabled "$pr"; then start_one "$pr"; else is_running "$pr" && stop_one "$pr"; fi
  done
  # лишние слоты без профиля
  for sf in "$RUN"/*.slot; do
    [ -f "$sf" ] || continue
    pr=$(basename "$sf" .slot)
    [ -f "$PROFILES/$pr.ovpn" ] || stop_one "$pr"
  done
  sleep 1
  apply
}

apply() {
  for sf in "$RUN"/*.slot; do
    [ -f "$sf" ] || continue
    apply_one "$(basename "$sf" .slot)"
  done
  apply_routes
}

stopall() {
  for sf in "$RUN"/*.slot; do [ -f "$sf" ] && stop_one "$(basename "$sf" .slot)"; done
}

# ---- расписание (как «Расписание» в Keenetic) ----
# В meta профиля: .schedule = {enabled, actions:[{do:start|stop, hh, mm, dow:[1..7]}]}
# dow: 1=Пн … 7=Вс (date +%u). События edge-triggered: срабатывают в свой момент,
# между событиями ручной тумблер работает как обычно.

sched_now() {
  ND=$(date +%u)
  h=$(date +%H); m=$(date +%M)
  NM=$(( ${h#0} * 60 + ${m#0} ))
}

# Самое недавнее (по времени назад) событие профиля: $1=мета-файл.
# Выводит "do ago_min" события с минимальным ago или ничего, если событий нет.
sched_recent() {
  jq -r --argjson nd "$ND" --argjson nm "$NM" '
    [ .schedule.actions[]? | . as $a | ($a.dow[]?) as $d
      | ((($nd - $d + 7) % 7) * 1440 + ($nm - ($a.hh*60 + $a.mm))) as $ago0
      | {do: $a.do, ago: (if $ago0 < 0 then $ago0 + 10080 else $ago0 end)}
    ] | sort_by(.ago) | if length > 0 then "\(.[0].do) \(.[0].ago)" else empty end
  ' "$1" 2>/dev/null
}

sched_apply_state() {
  # $1=profile $2=start|stop $3=пометка для лога; возвращает 0 если состояние изменили
  cur=$(meta_get "$1" '.enabled'); [ "$cur" = "true" ] || cur=false
  if [ "$2" = "start" ] && [ "$cur" != "true" ]; then
    set_meta_enabled "$1" true
    echo "[$(date '+%F %T')] [расписание] $1 → старт$3" >> "$LOGDIR/vpn-aim-action.log"
    return 0
  elif [ "$2" = "stop" ] && [ "$cur" = "true" ]; then
    set_meta_enabled "$1" false
    echo "[$(date '+%F %T')] [расписание] $1 → стоп$3" >> "$LOGDIR/vpn-aim-action.log"
    return 0
  fi
  return 1
}

schedule_tick() {
  NOW=$(date +%s)
  LAST=$(cat "$RUN/sched.last" 2>/dev/null); [ -z "$LAST" ] && LAST=$((NOW - 30))
  echo "$NOW" > "$RUN/sched.last"
  NOWFLOOR=$(( NOW - NOW % 60 ))
  sched_now
  CH=0
  for f in "$META"/*.json; do
    [ -f "$f" ] || continue
    pr=$(basename "$f" .json)
    [ -f "$PROFILES/$pr.ovpn" ] || continue
    [ "$(jq -r '.schedule.enabled // false' "$f" 2>/dev/null)" = "true" ] || continue
    set -- $(sched_recent "$f")
    [ -z "$1" ] && continue
    # событие сработало, если его минута попала в окно (последний тик, сейчас]
    occ=$(( NOWFLOOR - $2 * 60 ))
    [ "$occ" -gt "$LAST" ] || continue
    sched_apply_state "$pr" "$1" "" && CH=1
  done
  [ "$CH" = 1 ] && reconcile
}

schedule_sync() {
  ONLY=$1
  sched_now
  CH=0
  for f in "$META"/*.json; do
    [ -f "$f" ] || continue
    pr=$(basename "$f" .json)
    [ -n "$ONLY" ] && [ "$pr" != "$ONLY" ] && continue
    [ -f "$PROFILES/$pr.ovpn" ] || continue
    [ "$(jq -r '.schedule.enabled // false' "$f" 2>/dev/null)" = "true" ] || continue
    set -- $(sched_recent "$f")
    [ -z "$1" ] && continue
    sched_apply_state "$pr" "$1" " (синхронизация)" && CH=1
  done
  [ "$CH" = 1 ] && reconcile
  # окно тика сдвигаем только при полном sync (старт демона); per-profile sync
  # из CGI не должен съедать события других профилей, попавшие в это окно
  [ -z "$ONLY" ] && date +%s > "$RUN/sched.last"
  return 0
}

status_json() {
  echo '['
  first=1
  for f in "$PROFILES"/*.ovpn; do
    [ -f "$f" ] || continue
    pr=$(basename "$f" .ovpn)
    en=false; is_enabled "$pr" && en=true
    run=false; is_running "$pr" && run=true
    slot=$(slot_of "$pr"); [ -z "$slot" ] && slot=-1
    ip=""
    [ "$run" = true ] && [ "$slot" != "-1" ] && ip=$(ip -br -4 addr show "tun_aim$slot" 2>/dev/null | awk '{print $3}')
    remote=$(grep -E '^remote ' "$f" 2>/dev/null | head -1 | awk '{print $2}')
    wan=$(meta_get "$pr" '.wan')
    mode=$(meta_get "$pr" '.mode'); [ -z "$mode" ] && mode=devices
    devc=$(jq -r '.devices | length // 0' "$META/$pr.json" 2>/dev/null); [ -z "$devc" ] && devc=0
    sched=false; [ "$(meta_get "$pr" '.schedule.enabled')" = "true" ] && sched=true
    [ "$first" -eq 0 ] && echo ','
    first=0
    printf '{"name":"%s","enabled":%s,"running":%s,"slot":%s,"ip":"%s","remote":"%s","wan":"%s","mode":"%s","devices_count":%s,"sched":%s}' \
      "$pr" "$en" "$run" "$slot" "$ip" "$remote" "$wan" "$mode" "$devc" "$sched"
  done
  echo; echo ']'
}

case "$1" in
  enable)   jq --arg e true  '.enabled=($e=="true")' "$META/$2.json" 2>/dev/null > "$META/$2.json.tmp" 2>/dev/null && mv "$META/$2.json.tmp" "$META/$2.json" 2>/dev/null || { mkdir -p "$META"; echo '{"enabled":true}' > "$META/$2.json"; }; reconcile ;;
  disable)  [ -f "$META/$2.json" ] && jq '.enabled=false' "$META/$2.json" > "$META/$2.json.tmp" 2>/dev/null && mv "$META/$2.json.tmp" "$META/$2.json"; reconcile ;;
  reconcile) reconcile ;;
  apply)     apply ;;
  stopall)   stopall ;;
  status)    status_json ;;
  schedule-tick) schedule_tick ;;
  schedule-sync) schedule_sync "$2" ;;
  start-one) start_one "$2"; sleep 1; apply ;;
  stop-one)  stop_one "$2"; apply ;;
  *) echo "usage: $0 {enable|disable|reconcile|apply|stopall|status|schedule-tick|schedule-sync} [profile]"; exit 1 ;;
esac
