# keenetic-vpn-xor

Веб-панель управления **VPN (OpenVPN + XOR/scramble, обход DPI)** для роутеров **Keenetic** поверх Entware.
Несколько туннелей одновременно (мульти-профиль), привязка устройств/маршрутов к профилю, выбор WAN-канала,
расписание работы (как в Keenetic), системная карточка и темы оформления. Лёгкая (lighttpd + sh-CGI) панель на порту **8888**.

## Установка одной командой

На роутере с установленным Entware (SSH, порт 222):

```sh
opkg update && opkg install curl ca-bundle
curl -fsSL https://raw.githubusercontent.com/invisible25/keenetic-vpn-xor/main/boot.sh | sh
```

Скрипт скачает последний релиз, **сам определит архитектуру** (`opkg print-architecture`),
поставит нужный `openvpn+XOR`, зависимости и поднимет панель. После установки откройте `http://<IP-роутера>:8888/`.

> **Почему не `wget`?** Встроенный в прошивку BusyBox-`wget` часто собран без HTTPS (на `https://`-ссылку
> отвечает `wget: not an http or ftp url`). Поэтому качаем через `curl`. Если предпочитаете `wget` —
> поставьте полный из Entware: `opkg install wget-ssl ca-bundle` и вызывайте его явно по пути `/opt/bin/wget`.

## Поддерживаемые архитектуры

| Архитектура | Чип | Модели Keenetic |
|---|---|---|
| `aarch64-3.10` | MT7981 / 7986 / 7988 (ARM64) | Giga (KN-1012), Ultra, Peak, Hopper и новее |
| `mipsel-3.4` | MT7621 / MT7628 (MIPS LE) | Giga (KN-1010), Lite, City и др. |
| `mips-3.4` | EcoNet EN751x (MIPS BE) | Giga SE / Hero DSL (KN-2410), DSL (KN-2010), Duo (KN-2110) |

## Требования

- Keenetic с установленным **Entware/OPKG** (обычно на USB-накопитель — см. документацию Keenetic).
- SSH-доступ к Entware (`root`, порт 222).
- Интернет на роутере (для `opkg`).

## Что внутри

- `boot.sh` — бутстрап-установщик (этот one-liner).
- `install.sh` — установщик (выбирает `.ipk` по архитектуре, ставит панель и сервисы).
- `pack.sh` — пересборка переносимого архива на уже настроенном роутере.
- `src/` — исходники панели (`index.html`, `invnetctl`, `cgi-bin/`, `init.d/` и др.).
- [Releases](../../releases) — собранные `.ipk` под 3 архитектуры + `vpn-xor-install-clean.tar.gz` + `SHA256SUMS.txt`.

## Ручная установка

Скачайте `vpn-xor-install-clean.tar.gz` из [Releases](../../releases), затем на роутере:

```sh
cd /tmp && tar xzf vpn-xor-install-clean.tar.gz && cd vpn-xor-install && sh install.sh
```

## Управление сервисом

По SSH (`root`, порт 222). Кроме веб-панели, всё управляется init-скриптами в `/opt/etc/init.d/`.

**VPN-туннели** (`S30invnet` поднимает все профили с `enabled=true`):

```sh
/opt/etc/init.d/S30invnet start      # запустить
/opt/etc/init.d/S30invnet stop       # остановить все туннели
/opt/etc/init.d/S30invnet restart    # перезапустить
/opt/etc/init.d/S30invnet status     # состояние профилей/туннелей
/opt/etc/init.d/S30invnet apply      # переналожить ip rule / маршруты / firewall
```

**Веб-панель** (lighttpd:8888), **watchdog** и **планировщик** — `start|stop|restart|status`:

```sh
/opt/etc/init.d/S31invnet-web      restart
/opt/etc/init.d/S40invnet-pingcheck restart
/opt/etc/init.d/S41invnet-sched     restart
```

**Перезапустить всё разом:**

```sh
for s in S30invnet S31invnet-web S40invnet-pingcheck S41invnet-sched; do /opt/etc/init.d/$s restart; done
```

**Отдельный профиль** (менеджер `invnetctl`):

```sh
invnetctl enable  <профиль>   # включить (enabled=true) и поднять
invnetctl disable <профиль>   # выключить и опустить туннель
invnetctl status              # сводка по всем профилям
invnetctl reconcile           # привести факт к желаемому состоянию
invnetctl stopall             # остановить все туннели
```

**Логи:**

```sh
tail -f /opt/var/log/invnet-<профиль>.log   # лог OpenVPN по профилю
tail -f /opt/var/log/invnet-web.err         # ошибки веб-панели
```

## OpenVPN + XOR

`openvpn` 2.6.14 собран с патчем Tunnelblick **scramble** (`scramble obfuscate <key>` / `scramble xormask <key>`)
для обфускации трафика и обхода DPI. Сборка — Entware buildroot, по одному `.ipk` на архитектуру.
