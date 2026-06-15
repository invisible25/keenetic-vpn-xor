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

# Переутвердить все активные туннели. $1 (необязательно) = таблица (для хука).
invnet_fw_assert_all() {
  for _d in $(invnet_active_devs); do invnet_fw_assert_dev "$_d" "$1"; done
}
