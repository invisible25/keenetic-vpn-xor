# ADR 0002 — Установка/обновление через opkg-фид на GitHub Pages

Статус: принято (реализовано в ветке `beta`, 2026-07-20). Заменяет tarball-схему как основной путь.

## Контекст

Раньше установка/перенос = собрать `vpn-xor-install.tar.gz` (`pack.sh`) и вручную прогнать
`install.sh` на роутере. Минусы: нет версионирования пакета, обновление = ручная пересборка+копия,
нельзя `opkg upgrade`. Цель — стандартный путь Entware: `opkg install invnet` / `opkg upgrade invnet`
из репозитория, отдаваемого GitHub Pages.

## Решение

Один **opkg-фид** на GitHub Pages (`https://invisible25.github.io/keenetic-vpn-xor`), в нём:
- `invnet_<v>_all.ipk` — панель (sh+html, **Architecture: all**, компиляции нет → ставится на любой Keenetic);
- `openvpn-openssl_1:2.6.14-4_<arch>.ipk` — XOR-openvpn для 3 арх (aarch64-3.10, mips-3.4, mipsel-3.4);
- `Packages` + `Packages.gz` — индекс.

Роутер: `src/gz invnet https://…` в `/opt/etc/opkg/invnet.conf` → `opkg install invnet` тянет панель
+ XOR-openvpn + зависимости (jq, lighttpd, iptables, ip-full, curl, tar) из общего фида Entware.

## Ключевые факты (проверено на живом роутере 7.1, а не по докам)

1. **Формат .ipk на этих Keenetic — gzip'нутый tar** с членами `./debian-binary`, `./data.tar.gz`,
   `./control.tar.gz` (НЕ `ar`, как в .deb/современном opkg-utils). Сверено с рабочим openvpn .ipk
   (magic `1f 8b`). Поэтому сборка — только `tar`+`gzip`, **без `ar`** → билд идёт и на Windows/Git Bash.
2. **XOR-openvpn пакуется как пакет `openvpn-openssl`** (не `-xor`), перекрывая стоковый: `Package:
   openvpn-openssl`, `Provides: openvpn openvpn-crypto`. На 7.1 установлен именно `openvpn-openssl 2.6.14-4`
   с активным scramble.
3. **Epoch-бамп обязателен.** У стока из Entware та же базовая версия `2.6.14-4` → без epoch opkg мог бы
   выбрать сток (без XOR). Поднимаем нашу до **`1:2.6.14-4`** (`repack-openvpn.sh`, бинарь не трогаем),
   а `invnet` зависит от `openvpn-openssl (>= 1:2.6.14-4)` → наш XOR детерминированно ставится/апгрейдится.
4. **`arch all 100`** уже настроен в `/opt/etc/opkg.conf` → пакет `all` принимается.
5. Общий (мульти-арч) фид даёт на роутере предупреждения `openvpn-openssl … has no valid architecture,
   ignoring` для НЕ его арх — это норма, opkg берёт правильный вариант (проверено `--noaction`).

## Данные vs код (переживание upgrade)

Пакет несёт **только код**. Профили, `profile-meta`, `invnet-*.conf`, маршруты создаются в **postinst**
с дефолтами лишь при отсутствии и **не входят в манифест** → `opkg upgrade`/`remove` их не трогает.
`conffiles: /opt/etc/lighttpd/invnet.conf` — opkg не перетрёт правленый конфиг. `prerm` останавливает
службы и туннели; `postinst` идемпотентно (пере)запускает и делает `invnetctl reconcile`.

## Сборка

`opkg/build-feed.sh` → `build-ipk.sh` (панель) + `repack-openvpn.sh` (epoch) + `make-index.sh` (индекс).
CI `.github/workflows/opkg-feed.yml`: на тег `vX.Y.Z` собирает фид (версия invnet = тег) и публикует
Pages. Локально проверяется `--noaction` через `file://`-фид на роутере (без интернета и мутации).

## Trade-offs

| Решение | Плюс | Минус |
|---|---|---|
| Пакет `all` | один artifact на все Keenetic | арх-специфику несёт только openvpn |
| Epoch `1:` на openvpn | XOR всегда побеждает сток | `opkg upgrade` не откатит на сток без ручного вмешательства (это и нужно) |
| Мульти-арч в одном фиде | простой публикатор | безвредные предупреждения об арх на роутере |
| openvpn-бинарники в репе (`opkg/openvpn/`) | самодостаточный CI | ~840КБ бинарей в git (`*.ipk binary`, путь разрешён в `.gitignore`) |
| GitHub Pages (HTTPS) | бесплатно, CDN | роутеру нужен TLS (`ca-bundle`); *.github.io только https |

## Что пересмотреть

- **HTTPS на роутере**: если у части роутеров нет TLS в opkg — рассмотреть зеркало на http-хосте или
  свой домен с http. Пока — документируем `opkg install ca-bundle`.
- **Подпись фида** (`opkg` usign/Release.sig) — сейчас без подписи (доверяем HTTPS+GitHub). Добавить, если
  фид станет публичным для third-party.
- **Разделить фид по арх** (подкаталоги + отдельные Packages) — уберёт предупреждения, ценой сложности
  публикатора. Пока не нужно.
- tarball-схема (`pack.sh`/`install.sh`) остаётся для офлайн-переноса; opkg — основной путь.
