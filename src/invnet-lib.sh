#!/bin/sh
# Общие вспомогательные функции для CGI-скриптов invnet.

urldecode() {
  printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

# CSRF-заслон для эндпоинтов, меняющих состояние. Панель без аутентификации (известный
# пункт бэклога — авторизация логином Keenetic), поэтому единственная защита от чужого
# сайта в LAN, который дёргает наши CGI фоновым fetch(), — сверка Origin/Referer с Host
# самой панели. Обычные same-origin GET/POST из панели их не шлют вовсе — в этом случае
# пропускаем (fail-open по отсутствию заголовка, fail-closed по несовпадению значения).
# Проверено на живом lighttpd (88.1): CGI получает HTTP_ORIGIN/HTTP_REFERER/HTTP_HOST.
csrf_guard() {
  h="$HTTP_HOST"
  case "$HTTP_ORIGIN" in ''|"http://$h"|"https://$h") : ;; *)
    printf '{"error":"origin"}\n'; exit 0 ;; esac
  case "$HTTP_REFERER" in ''|"http://$h/"*|"https://$h/"*) : ;; *)
    printf '{"error":"origin"}\n'; exit 0 ;; esac
}
