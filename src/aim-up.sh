#!/bin/sh
# Вызывается openvpn при поднятии tun_aim<slot>. Настраивает NAT/forward/MSS
# и триггерит менеджер разложить ip rule (devices/routes) по всем профилям.
export PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin
DEV="${dev:-$1}"
SLOT="${AIM_SLOT:-${DEV#tun_aim}}"
TABLE=$((101 + SLOT))
LOG=/opt/var/log/vpn-aim-${AIM_PROFILE:-$SLOT}.log

echo "[$(date '+%F %T')] up: dev=$DEV slot=$SLOT profile=$AIM_PROFILE ip=$ifconfig_local" >> "$LOG"

# default route в таблицу профиля
ip route flush table "$TABLE" 2>/dev/null
ip route add default dev "$DEV" table "$TABLE" 2>/dev/null

# NAT + forward + MSS clamp
iptables -t nat -C POSTROUTING -o "$DEV" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$DEV" -j MASQUERADE
iptables -C FORWARD -o "$DEV" -j ACCEPT 2>/dev/null || iptables -A FORWARD -o "$DEV" -j ACCEPT
iptables -C FORWARD -i "$DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t mangle -C FORWARD -o "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A FORWARD -o "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# разложить ip rule (devices/routes) — асинхронно, чтобы не блокировать openvpn
( /opt/sbin/aim-manager.sh apply >/dev/null 2>&1 & )
exit 0
