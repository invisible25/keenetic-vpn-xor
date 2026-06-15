#!/bin/sh
# Возвращает iptables-правила invnet ПОСЛЕ перестройки netfilter демоном NDM.
# Ставится в /opt/etc/ndm/netfilter.d/ — NDM вызывает скрипты этого каталога при
# КАЖДОЙ перестройке, по разу на сочетание (type x table).
#   $type  = iptables | ip6tables
#   $table = filter | nat | mangle
# Требования: мгновенный, без сетевых вызовов (единая очередь NDM, таймаут ~24с).
[ "$type" = "ip6tables" ] && exit 0          # invnet работает только по IPv4
. /opt/etc/openvpn/invnet-fw.sh 2>/dev/null || exit 0

case "$table" in
  filter|mangle|nat) invnet_fw_assert_all "$table" ;;
esac
exit 0
