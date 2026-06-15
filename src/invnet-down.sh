#!/bin/sh
# Вызывается openvpn при падении tun_invnet<slot>. Снимает NAT/forward и таблицу.
export PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin
. /opt/etc/openvpn/invnet-fw.sh
DEV="${dev:-$1}"
SLOT="${INVNET_SLOT:-${DEV#tun_invnet}}"
TABLE=$((101 + SLOT))
LOG=/opt/var/log/invnet-${INVNET_PROFILE:-$SLOT}.log

echo "[$(date '+%F %T')] down: dev=$DEV slot=$SLOT" >> "$LOG"

invnet_fw_remove_dev "$DEV"
# kill-switch без окна утечки: атомарно ставим blackhole (replace, НЕ flush),
# затем убираем tun-default. blackhole присутствует всегда → нет момента, когда
# таблица пуста и пакет привязанного устройства утёк бы в main.
ip route replace blackhole default table "$TABLE" metric 9999 2>/dev/null
ip route del default dev "$DEV" table "$TABLE" 2>/dev/null
exit 0
