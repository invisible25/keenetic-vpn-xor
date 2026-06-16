# keenetic-vpn-xor

Веб-панель управления **VPN (OpenVPN + XOR/scramble, обход DPI)** для роутеров **Keenetic** поверх Entware.
Несколько туннелей одновременно (мульти-профиль), привязка устройств/маршрутов к профилю, выбор WAN-канала,
расписание работы (как в Keenetic), системная карточка и темы оформления. Лёгкая (lighttpd + sh-CGI) панель на порту **8888**.

## Установка одной командой

На роутере с установленным Entware (SSH, порт 222):

```sh
wget -qO- https://raw.githubusercontent.com/invisible25/keenetic-vpn-xor/main/boot.sh | sh
```

Скрипт скачает последний релиз, **сам определит архитектуру** (`opkg print-architecture`),
поставит нужный `openvpn+XOR`, зависимости и поднимет панель. После установки откройте `http://<IP-роутера>:8888/`.

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
## OpenVPN + XOR

`openvpn` 2.6.14 собран с патчем Tunnelblick **scramble** (`scramble obfuscate <key>` / `scramble xormask <key>`)
для обфускации трафика и обхода DPI. Сборка — Entware buildroot, по одному `.ipk` на архитектуру.
