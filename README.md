# Keenetic Routers OpenVPN + XOR/scramble поверх Entware

Веб-панель управления **VPN (OpenVPN + XOR/scramble, обход DPI)** для роутеров **Keenetic** поверх Entware.
Несколько туннелей одновременно (мульти-профиль), привязка устройств/маршрутов к профилю, выбор WAN-канала,
расписание работы (как в Keenetic), системная карточка и темы оформления. Лёгкая (lighttpd + sh-CGI) панель на порту **8888**.

**Новое в v1.3.0:** вывод устройства/подсети **напрямую через физический WAN, минуя VPN** — как политики
доступа и статические маршруты-исключения в Keenetic (у каждого маршрута выбор «через VPN ↔ напрямую»);
перетаскивание `.ovpn` в форму добавления профиля.

## Установка и обновление — одна команда

На роутере с установленным Entware (SSH, порт 222):

```sh
opkg update && opkg install curl ca-bundle
curl -fsSL https://raw.githubusercontent.com/invisible25/keenetic-vpn-xor/main/boot.sh | sh
```

Команда идемпотентна и годится в любом состоянии роутера: ставит панель с нуля, обновляет
уже установленную и **чинит роутеры, где панель ставили старым способом** (из tarball) —
переводит их на пакетное обновление. Она же настраивает HTTPS для `opkg` и прописывает фид.

После установки откройте `http://<IP-роутера>:8888/`. Дальше обновляйтесь как любым пакетом Entware:

```sh
opkg update && opkg upgrade invnet
```

Профили, привязки устройств, маршруты и настройки при обновлении сохраняются (не входят в пакет).

> Если `opkg upgrade invnet` отвечает `Unknown package 'invnet'` — панель ставилась до появления
> фида и в базе `opkg` её нет. Запустите команду с `boot.sh` выше: она перенимает уже лежащие
> файлы под управление пакета, ничего не теряя.

### Вручную, без boot.sh

```sh
# 1) opkg должен уметь HTTPS: фид на github.io отдаётся только по TLS, а встроенный
#    busybox-wget его НЕ тянет ("not an http or ftp url"). Ставим wget-ssl и направляем на него:
opkg install wget-ssl ca-bundle ca-certificates
ln -sf /opt/bin/wget /opt/usr/bin/wget       # opkg берёт wget из /opt/usr/bin — пусть это будет SSL-версия

# 2) подключаем фид и ставим пакет (--force-overwrite нужен, если панель уже лежит из tarball)
mkdir -p /opt/etc/opkg
echo 'src/gz invnet https://invisible25.github.io/keenetic-vpn-xor' > /opt/etc/opkg/invnet.conf
opkg update
opkg install --force-overwrite invnet
```

> В выводе `opkg` строки `Package openvpn-openssl … has no valid architecture, ignoring` — это норма,
> а не ошибка: в общем индексе фида лежат пакеты всех трёх архитектур, и `opkg` отбрасывает чужие.

> **Почему шаг 1?** opkg вызывает `wget`, а в `PATH` первым идёт `/opt/usr/bin/wget` → busybox
> (без TLS). `wget-ssl` ставится как `/opt/bin/wget`; симлинк выше отдаёт opkg именно его. Проверено
> на живом роутере: без этого `opkg update` по нашему фиду падает с `wget returned 1`.

## Установка из tarball (офлайн-перенос)

Нужна, когда до `github.io` не достучаться. `boot.sh` откатывается на этот путь сам, но можно и вручную:
скачайте `vpn-xor-install-clean.tar.gz` из [релизов](https://github.com/invisible25/keenetic-vpn-xor/releases/latest),
положите на роутер и распакуйте:

```sh
tar xzf vpn-xor-install-clean.tar.gz && cd vpn-xor-install && sh install.sh
```

`install.sh` **сам определит архитектуру** (`opkg print-architecture`), поставит нужный `openvpn+XOR`,
зависимости, поднимет панель — и настроит обновление через `opkg`, если до фида есть доступ.

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

## 💚 Поддержать проект

Панель бесплатна и развивается в свободное время. Самый простой способ сказать спасибо — поставить
репозиторию ⭐. А поддержать разработку новых функций можно по желанию: отсканируйте QR или скопируйте адрес.

<table>
  <tr>
    <td align="center" width="25%"><b>USDT</b><br><sub>BEP20 · BSC</sub></td>
    <td align="center" width="25%"><b>ETH</b><br><sub>BEP20 · BSC</sub></td>
    <td align="center" width="25%"><b>LTC</b><br><sub>Litecoin</sub></td>
    <td align="center" width="25%"><b>ЮMoney</b><br><sub>карта/кошелёк</sub></td>
  </tr>
  <tr>
    <td align="center"><img src=".github/assets/donate/usdt-bep20.png" width="150" alt="USDT BEP20"></td>
    <td align="center"><img src=".github/assets/donate/eth-bep20.png" width="150" alt="ETH BEP20"></td>
    <td align="center"><img src=".github/assets/donate/ltc.png" width="150" alt="LTC"></td>
    <td align="center"><img src=".github/assets/donate/yoomoney.png" width="150" alt="ЮMoney"></td>
  </tr>
  <tr>
    <td align="center"><sub><code>0xd4a0…5591</code></sub></td>
    <td align="center"><sub><code>0xd4a0…5591</code></sub></td>
    <td align="center"><sub><code>LeRAW…HPdr</code></sub></td>
    <td align="center"><sub><a href="https://yoomoney.ru/to/4100117590955780">yoomoney.ru/to/…</a></sub></td>
  </tr>
</table>

Полные реквизиты для копирования:

| Способ | Сеть | Реквизиты |
|---|---|---|
| **USDT** | BEP20 (BSC) | `0xd4a069e3a31393c3c1389961e0df238bb0eb5591` |
| **ETH** | BEP20 (BSC) | `0xd4a069e3a31393c3c1389961e0df238bb0eb5591` |
| **LTC** | Litecoin | `LeRAWs9u1Gd1kr9AZdGYS8AnvSXL6FHPdr` |
| **ЮMoney** | — | `4100117590955780` |

> ⚠️ USDT и ETH принимаются **только в сети BEP20 (BSC)**. Отправка в другой сети (ERC20, TRC20 и т.п.)
> приведёт к потере средств.

Спасибо, что пользуетесь! 🙏
