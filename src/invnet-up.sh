#!/bin/sh
# Вызывается openvpn при поднятии tun_invnet<slot>. Настраивает NAT/forward/MSS
# и триггерит менеджер разложить ip rule (devices/routes) по всем профилям.
export PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin
. /opt/etc/openvpn/invnet-fw.sh
DEV="${dev:-$1}"
SLOT="${INVNET_SLOT:-${DEV#tun_invnet}}"
TABLE=$((101 + SLOT))
LOG=/opt/var/log/invnet-${INVNET_PROFILE:-$SLOT}.log

echo "[$(date '+%F %T')] up: dev=$DEV slot=$SLOT profile=$INVNET_PROFILE ip=$ifconfig_local" >> "$LOG"

# default в таблицу профиля — атомарно (replace, без flush → без окна утечки)
ip route replace default dev "$DEV" table "$TABLE" 2>/dev/null
ip route replace blackhole default table "$TABLE" metric 9999 2>/dev/null  # kill-switch fallback

# NAT + forward + MSS clamp — через общую библиотеку. Тот же набор правил
# переставляет хук /opt/etc/ndm/netfilter.d/50-invnet.sh после перестроек NDM.
invnet_fw_assert_dev "$DEV"

# разложить ip rule (devices/routes) — асинхронно, чтобы не блокировать openvpn
( /opt/sbin/invnetctl apply >/dev/null 2>&1 & )
exit 0
