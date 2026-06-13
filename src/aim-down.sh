#!/bin/sh
# Вызывается openvpn при падении tun_aim<slot>. Снимает NAT/forward и таблицу.
export PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin
DEV="${dev:-$1}"
SLOT="${AIM_SLOT:-${DEV#tun_aim}}"
TABLE=$((101 + SLOT))
LOG=/opt/var/log/vpn-aim-${AIM_PROFILE:-$SLOT}.log

echo "[$(date '+%F %T')] down: dev=$DEV slot=$SLOT" >> "$LOG"

iptables -t nat -D POSTROUTING -o "$DEV" -j MASQUERADE 2>/dev/null
iptables -D FORWARD -o "$DEV" -j ACCEPT 2>/dev/null
iptables -D FORWARD -i "$DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
iptables -t mangle -D FORWARD -o "$DEV" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
ip route flush table "$TABLE" 2>/dev/null
ip route add blackhole default table "$TABLE" metric 9999 2>/dev/null
exit 0
