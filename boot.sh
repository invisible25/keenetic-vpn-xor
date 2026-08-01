#!/bin/sh
# boot.sh — установка VPN+XOR и настройка штатного канала обновлений, одной командой:
#   curl -fsSL https://raw.githubusercontent.com/invisible25/keenetic-vpn-xor/main/boot.sh | sh
#
# Скрипт ИДЕМПОТЕНТЕН и приводит роутер к одному состоянию независимо от того, как панель
# попала на него раньше: пакетом, старым tarball-скриптом или руками. После него обновление
# делается штатно:  opkg update && opkg upgrade invnet
#
# По шагам:
#   1) чинит HTTPS для opkg (busybox-wget без TLS → wget-ssl), иначе фид на github.io не тянется;
#   2) прописывает opkg-фид invnet;
#   3) ставит/обновляет пакет invnet (--force-overwrite: у tarball-установок файлы панели
#      лежат в /opt «ничьи», их надо перенять под управление пакета);
#   4) если фид недоступен (нет сети/заблокирован) — откатывается на tarball-релиз, чтобы
#      клиент всё равно обновился; фид при этом остаётся прописан на будущее.
set -e

REPO="invisible25/keenetic-vpn-xor"
FEED_URL="https://invisible25.github.io/keenetic-vpn-xor"
FEED_CONF="/opt/etc/opkg/invnet.conf"

info() { printf "\033[1;36m[i]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[+]\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m[-]\033[0m %s\n" "$1"; exit 1; }

# Сетевые команды на мёртвом канале висят бесконечно — ограничиваем по времени.
TIMEOUT_BIN=$(command -v timeout 2>/dev/null || true)
run_t() { _t=$1; shift; if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$_t" "$@"; else "$@"; fi; }

OPKG=/opt/bin/opkg
[ -x "$OPKG" ] || fail "Нужен Entware на роутере (см. документацию Keenetic OPKG)."

pkg_installed() { "$OPKG" list-installed 2>/dev/null | grep -q "^$1 "; }
pkg_version()   { "$OPKG" list-installed 2>/dev/null | awk -v p="$1" '$1==p{print $3; exit}'; }

# ── 1. HTTPS для opkg ───────────────────────────────────────────────────────────
# Фид на github.io отдаётся только по TLS, а opkg зовёт wget из PATH, где /opt/usr/bin идёт
# раньше /opt/bin → busybox-wget без SSL ("not an http or ftp url"). Ставим wget-ssl и
# подсовываем его opkg симлинком. Без этого шага `opkg update` по нашему фиду падает
# с `wget returned 1` — воспроизводилось на живых роутерах.
info "Проверяю, умеет ли opkg ходить по HTTPS..."
if ! pkg_installed wget-ssl; then
  info "Ставлю wget-ssl и корневые сертификаты..."
  run_t 180 "$OPKG" update >/dev/null 2>&1 || warn "opkg update по фидам Entware не прошёл — продолжаю"
  run_t 300 "$OPKG" install wget-ssl ca-bundle ca-certificates >/dev/null 2>&1 \
    || warn "не удалось поставить wget-ssl — если фид не подтянется, поставь его вручную"
fi
if [ -x /opt/bin/wget ]; then
  mkdir -p /opt/usr/bin
  ln -sf /opt/bin/wget /opt/usr/bin/wget
  ok "opkg использует wget с поддержкой TLS"
else
  warn "/opt/bin/wget не найден — HTTPS-фид может не заработать"
fi

# ── 2. Фид ──────────────────────────────────────────────────────────────────────
mkdir -p /opt/etc/opkg
printf 'src/gz invnet %s\n' "$FEED_URL" > "$FEED_CONF"
ok "Фид обновлений прописан: $FEED_CONF"

info "opkg update..."
if run_t 180 "$OPKG" update 2>&1 | grep -qi "opkg-lists/invnet"; then FEED_OK=yes; else FEED_OK=no; fi

# `opkg update` мог отчитаться по кэшу — проверяем, что пакет реально виден.
if [ "$FEED_OK" = yes ] && ! "$OPKG" list invnet 2>/dev/null | grep -q '^invnet '; then
  FEED_OK=no
fi

# ── 3. Установка/обновление пакетом ─────────────────────────────────────────────
if [ "$FEED_OK" = yes ]; then
  WAS=$(pkg_version invnet)
  if [ -n "$WAS" ]; then
    info "Установлен invnet $WAS → проверяю обновление..."
    run_t 600 "$OPKG" upgrade invnet 2>&1 | grep -viE "no valid architecture" | tail -5 || true
  else
    # Сюда попадают и tarball-установки: файлы панели уже лежат в /opt, но ни одному пакету
    # не принадлежат. --force-overwrite отдаёт их под управление opkg; пользовательские данные
    # (профили, meta, маршруты) в манифест пакета не входят и не трогаются.
    if [ -f /opt/share/invnet/index.html ] || [ -x /opt/sbin/invnetctl ]; then
      info "Найдена установка без пакета (старый способ) — перевожу на пакетное обновление..."
    else
      info "Ставлю invnet..."
    fi
    run_t 600 "$OPKG" install --force-overwrite invnet 2>&1 | grep -viE "no valid architecture" | tail -8
  fi
  NOW=$(pkg_version invnet)
  [ -n "$NOW" ] || fail "Установка пакета invnet не удалась. Повтори вручную и посмотри вывод: $OPKG install --force-overwrite invnet"
  if [ -n "$WAS" ] && [ "$WAS" = "$NOW" ]; then
    ok "invnet $NOW — уже актуальная версия"
  else
    ok "invnet $NOW установлен"
  fi
else
  # ── 4. Запасной путь: tarball-релиз ───────────────────────────────────────────
  warn "Фид $FEED_URL недоступен — ставлю из релиза (пакетное обновление включится, когда появится доступ)."
  URL="https://github.com/$REPO/releases/latest/download/vpn-xor-install-clean.tar.gz"
  cd /tmp
  rm -f vpn-xor-install.tar.gz
  rm -rf vpn-xor-install
  info "Скачиваю последний релиз..."
  if command -v curl >/dev/null 2>&1; then
    run_t 300 curl -fSL "$URL" -o vpn-xor-install.tar.gz
  else
    run_t 300 /opt/bin/wget -O vpn-xor-install.tar.gz "$URL"
  fi
  info "Распаковка и установка..."
  tar xzf vpn-xor-install.tar.gz
  cd vpn-xor-install && sh install.sh
  exit $?
fi

# ── 5. Проверка, что панель жива ────────────────────────────────────────────────
if command -v curl >/dev/null 2>&1 && curl -s -o /dev/null --max-time 5 http://127.0.0.1:8888/ 2>/dev/null; then
  ok "Веб-панель отвечает на порту 8888"
else
  warn "Веб-панель не ответила. Запусти:  /opt/etc/init.d/S31invnet-web start"
  warn "и загляни в лог:  /opt/var/log/invnet-web.err"
fi

echo
ok "Готово. Дальше обновление — одной командой:"
echo "    opkg update && opkg upgrade invnet"
