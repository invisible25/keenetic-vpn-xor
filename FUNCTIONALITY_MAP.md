# FUNCTIONALITY_MAP.md — Веб-панель OpenVPN+XOR (Invisible Net)

Карта функционала UI по состоянию v1.5.0 (аудит `src/index.html`, 2418 строк / 135 006 байт;
25 sh-CGI в `src/cgi-bin/`; статика `src/fonts/` + `logo.svg`/`logo-mark.svg`; `invnet.conf`;
ADR `docs/adr/0001-scheduler-design.md`).

**Назначение:** контрольный чек-лист редизайна фронтенда в ветке `beta` — функционал
сохраняется 1:1, контракт CGI неизменен. DOM id при полном переписе JS можно менять
(старый «замороженный ID-контракт» действовал только пока JS не переписывался);
ниже id перечислены как опись функционала старого UI, а не как обязательные имена.

---

## 1. Экраны/виды и навигация

**Оболочка (app shell):** флекс-контейнер `.app` = `<aside class="side">` + `.main`.
Один-единственный `<nav class="nav">` в DOM переиспользуется двумя способами через
CSS-медиазапрос на границе **960px**:
- **≥960px** — вертикальный сайдбар слева (224px, sticky, бренд сверху, подвал `Invisible Net · v1.5.0`);
- **<960px** — тот же `<nav>` репозиционируется в **нижний таб-бар** (fixed, `backdrop-filter: blur`,
  safe-area insets), бренд уезжает в топбар. Активный пункт: золотая «нить» слева (десктоп) / сверху (мобайл).

**6 разделов** (`.tab[data-tab]` ↔ `.section[data-section]`, показ через класс `.active`):
1. **overview** — «Обзор» (дашборд, стартовый)
2. **profiles** — «Профили»
3. **devices** — «Устройства»
4. **routes** — «Маршруты»
5. **log** — «Журнал» + бейдж непрочитанного `#nav-log-badge`
6. **settings** — «Настройки»

**Роутинг:** hash-синхронизация вида. `switchTab(name)` пишет `#/<name>` через
`history.replaceState`; слушатель `hashchange` + восстановление вида из hash при загрузке
(перезагрузка сохраняет открытый раздел). Валидация имени против `VALID_TABS`, дефолт `overview`.
Побочки переключения: вход в `log` → `startLogAuto()`+`loadPingLog()`+сброс бейджа;
выход → `stopLogAuto()`; вход в `settings` → `loadSysinfo()`.

**Модалки/шторки:**
- `#profile-modal` — редактор профиля; на <600px превращается в **нижнюю шторку**
  (анимация `sheet-up`, radius сверху, safe-area). Закрытие: клик по фону, крестик, Esc.
- `#theme-picker` — мини-поповер выбора темы в топбаре (7 цветных точек), закрывается кликом вне.
- Расписание — не модалка, а **инлайн-аккордеон** (`.sched-box`) под карточкой профиля.
- Нативные `confirm()` — удаление профиля и очистка логов.

**Доступность:** роли `tablist/tab`, `aria-selected`, стрелки ←/→ по вкладкам,
Enter/Space для div-интерактива, `:focus-visible`, `.sr-only`-заголовок, `prefers-reduced-motion`.

---

## 2. Функционал по экранам (опись контролов старого UI, ~70 id)

### Топбар (глобальный)
| id | назначение |
|----|----|
| `theme-btn` | кнопка открытия мини-пикера тем |
| `theme-picker` | поповер с 7 точками-темами |
| `header-pill` | бейдж online/offline (класс `.pill on/off`) |
| `icons` | скрытый SVG-спрайт всех иконок |
| `toast` | контейнер стека тостов (`role=status`, `aria-live=polite`) |

Кнопка «Обновить» (`onclick=loadAll()`) — без id.

### Обзор (overview)
| id | назначение |
|----|----|
| `big-status` | герой-статус: «Активно N профилей» / «Соединение не активно»; при переключении — спиннер «запуск/остановка · имя…» |
| `active-profile` | имена работающих профилей через запятую |
| `tiles` | грид плиток туннелей; класс `.ready` — анимация появления играет один раз |
| `rx-rate` / `tx-rate` | текущая скорость ↓/↑ (последняя точка буфера) |
| `chart-wrap` | обёртка графика (hover/тач-перекрестие) |
| `traffic-chart` | inline-`<svg>` график rx/tx (viewBox 600×130) |
| `chart-max` | подпись потолка шкалы «до X/с» |
| `chart-tip` | всплывающее значение точки при hover |
| `chart-empty` | оверлей пустого состояния («собираю данные…» / «туннели не активны») |
| `rx` / `tx` | всего получено/отправлено (кумулятив) |
| `checkip-profile` | `<select>` «через какой туннель проверять» (только running; «нет активных» → disabled) |
| `checkip-box` | панель результата проверки IP (`.show`) |
| `ci-ip`,`ci-country`,`ci-city`,`ci-org` | поля результата checkip (спиннер / иконка ошибки) |
| `wd-feed` | лента последних 5 перезапусков watchdog |

Плитка туннеля (динамическая): точка-статус (`.dot live/pending`), имя, мини-тумблер,
«нить» маршрута `WAN → remote`, мета (работает/запуск/выключен · N устр./весь LAN · расписание).
Клик по плитке → `openDevicesFor(name)`; тумблер → `profileToggle`.

### Профили (profiles)
| id | назначение |
|----|----|
| `profiles-hint` | подсказка «клик — выбрать · ✎ — редактировать · тумблер — вкл/выкл» |
| `profile-list` | список карточек (или empty-state) |
| `new-name` | имя нового профиля (maxlength 32) |
| `ovpn-drop` | dropzone (`.dragover`) для .ovpn |
| `new-content` | textarea конфига |
| `ovpn-file` | скрытый `<input type=file>` (accept `.ovpn,.conf,.txt`) |

Карточка профиля (динамическая): `.profile-info` (клик → устройства), точка `.dot`,
бейджи (`via <wan>`, «N устр.»/«весь LAN»/«нет устр.», «расписание»), state-label,
кнопка ⏰ (`toggleSchedule`), кнопка ✎ (`editProfile`), тумблер (`profileToggle`).

**Редактор — модалка `#profile-modal`:**
| id | назначение |
|----|----|
| `m-remote` | remote-адрес (read-only мета) |
| `m-mode` | режим (весь LAN/выбранные) |
| `m-devcount` | число устройств в политике |
| `m-state` | статус (подключено/запуск…/выключен) |
| `m-name` | редактируемое имя (переименование) |
| `m-wan-select` | `<select>` WAN-интерфейса профиля |
| `m-content` | textarea .ovpn (валидация: обязательна строка `remote`) |

Кнопки: «Удалить профиль» (`deleteFromEditor`), «Отмена», «Сохранить»
(`saveProfileEdit` — сначала `profile-wan`, потом `profile`).

### Устройства (devices)
| id | назначение |
|----|----|
| `dev-count` | счётчик «N устр.» |
| `dev-profile` | `<select>` цели: optgroup «VPN-профили» + optgroup «Прямые WAN-каналы» (значения `wan:<iface>`) |
| `dev-wan-note` | предупреждение при выборе прямого WAN (нет автоотката) |
| `mode-devices` / `mode-all` | переключатель «Выбранные»/«Весь LAN» (скрыт для WAN-цели) |
| `devices-section` | обёртка списка (класс `.muted-section` при «весь LAN») |
| `dev-search` | поиск по имени/IP/MAC/iface/политике |
| `dev-list` | список чекбоксов устройств (или empty-state) |

Кнопка «Сохранить выбор» → `saveDevs()` (шлёт `save-devices` или `save-wan-policy`).

### Маршруты (routes)
| id | назначение |
|----|----|
| `routes-count` | счётчик «N маршрут.» |
| `new-cidr` | ввод CIDR/IP |
| `new-comment` | комментарий |
| `keenetic-routes-import` | контейнер импорта из Keenetic (data-атрибут `routes` с JSON) |
| `routes-list` | список: тумблер вкл/выкл, CIDR, комментарий, `<select>` направления («Через VPN»/«↗ напрямую <канал>»), удаление |

Кнопки: «Добавить» (`addRoute`), «Импорт из Keenetic» (`loadKeeneticRoutes`),
в импорте — чекбоксы `.keenetic-route-check` + «Импортировать выбранные»
(`importKeeneticRoutes`, атомарный bulk).

### Журнал (log)
| id | назначение |
|----|----|
| `log-auto` | чекбокс автообновления лога openvpn |
| `log-box` | `<pre>` лог openvpn |
| `watchdog-status` | статус демона watchdog (точка live + «работает»/«остановлен») |
| `pinglog-box` | `<pre>` лог watchdog/переподключений |
| `nav-log-badge` | бейдж непрочитанных событий на вкладке |

Кнопки: «Обновить»/«Очистить лог» (openvpn), «Обновить»/«Очистить» (watchdog).

### Настройки (settings)
| id | назначение |
|----|----|
| `sys-arch` | архитектура (в заголовке карточки) |
| `sysinfo` | контейнер системной карточки |
| `sys-model`,`sys-os`,`sys-cpu`,`sys-mem`,`sys-uptime`,`sys-load` | поля sysinfo |
| `custom-row` | строка кастомной темы (3 color-пикера) |
| `cu-accent`,`cu-bg`,`cu-text` | пикеры акцент/фон/текст |
| `autostart-toggle` | тумблер автозапуска VPN при загрузке роутера |

Сетка тем `.theme-grid` (7 свотчей + Custom), кнопка «Применить» кастома (`applyCustomFromPickers`).

### Динамические id (создаются в рантайме)
`sched-grid` (недельная сетка), `sched-enabled` (тумблер расписания), `sched-next`
(подсказка «сейчас/следующее событие»), `chart-cross` (перекрестие в SVG).

### Состояния UI (общая механика)
- **loading:** `.spinner` (операции >300мс), `.skel`-скелетоны плиток при недоступном CGI, «загрузка…» в checkip.
- **empty:** блоки `.empty` (нет профилей / устройств / маршрутов / событий watchdog); `chart-empty`.
- **error:** тосты `.toast.error`, инлайн «Ошибка»/иконка в checkip и списках.
- **success:** тосты `.toast.ok`.
- **тосты:** `toast(msg, kind)` — стек, автоскрытие 2800мс, kinds `ok`/`error`/дефолт.
- **бейджи статусов:** `header-pill` (on/off), точки `.dot live/pending`, `.pill`, `.daemon-badge`, `.iface-badge`, `.policy-badge`, «● работает».
- **бейдж непрочитанного:** `nav-log-badge` (макс «99», сброс при входе в Журнал).

---

## 3. Контракт API (fetch → CGI) — НЕИЗМЕНЕН

Все запросы — `/cgi-bin/<endpoint>`. Фактически **25 скриптов**: `activate-profile, autostart,
checkip, clearlog, connect, delete-profile, devices, keenetic-routes, log, mode, pinglog,
profile, profile-wan, profiles, routes, save-devices, save-wan-policy, schedule, start, stats,
status, stop, sysinfo, upload-profile, wans`.

> Примечание: `pingcheck` как CGI не существует — это имя демона (`S40invnet-pingcheck`)
> и лог-файла; данные watchdog отдаёт эндпоинт `pinglog`.

### Периодический опрос
| таймер | что | период |
|----|----|----|
| главный `setInterval` | `loadStatus` + `loadStats` + `loadProfiles` | **5000 мс** |
| watchdog | `pollWatchdog` (`pinglog`) | **30000 мс** |
| лог openvpn | `loadLog` (только на вкладке Журнал при `log-auto`) | **3000 мс** |
| poll после тумблера | `profiles` до `running`==цель или 16 попыток | старт +1500мс, шаг **1200 мс** (~20с) |

### Таблица эндпоинтов
| Эндпоинт | Метод / параметры | Ответ | Кто вызывает |
|----|----|----|----|
| `status` | GET | text: строка1 `ACTIVE`/`INACTIVE`, `count=N`, `running=имена` | `loadStatus` (5с) |
| `stats` | GET | JSON `{rx,tx,up}` (сумма по всем `tun_invnet*`) | `loadStats` (5с) |
| `profiles` | GET | JSON-массив `{name,enabled,running,slot,ip,remote,wan,mode,devices_count,sched}` | `loadProfiles`, poll тумблера |
| `profile` | GET `?name=` → `{name,content,remote,mode,wan,devices_count}`; POST `name=&content=` → `{ok,name,restarted}` (rename+рестарт если запущен) | JSON | `editProfile`, `saveProfileEdit` |
| `profile-wan` | GET `?name=` → мета; POST `?name=` body `wan=` | text/JSON | `saveProfileEdit` |
| `upload-profile` | POST `name=&content=` (валидация client+remote) | text «Сохранён профиль…» | `uploadProfile` |
| `delete-profile` | GET `?name=` (блок при running) | text | `deleteFromEditor` |
| `connect` | GET `?name=&on=1|0` (фон enable/disable, мгновенный ответ) | JSON `{ok,status,profile}` | `profileToggle` |
| `activate-profile` | GET `?name=` (выбор без коннекта + apply) | text | (в старом UI не привязан) |
| `wans` | GET | JSON `[{iface,label,ndm,ip,type,default,connected}]` (NDM RCI + маппинг IP→eth) | `loadWans` |
| `devices` | GET `?profile=` или `?wan=&label=&ndm=` | JSON `[{ip,mac,name,iface,selected,policy_name?}]` | `loadDevs` |
| `save-devices` | POST `?profile=` body `ip=&ip=…` | text | `saveDevs` (VPN-цель) |
| `save-wan-policy` | POST `?wan=&label=&ndm=` body `ip=…` | text | `saveDevs` (WAN-цель) |
| `mode` | GET `?profile=` → `devices`/`all`; POST body `all|devices` | text | `loadMode`,`setMode` |
| `routes` | GET → JSON `[{cidr,comment,enabled,direct?,wan?}]`; POST body `action=add|import|delete|deleteall|toggle|setdir` (+`cidr/comment/index/wan/data`) | JSON | `loadRoutes`,`addRoute`,`deleteRoute`,`toggleRoute`,`setRouteDir`,`importKeeneticRoutes` |
| `keenetic-routes` | GET | JSON `[{cidr,gateway,interface,interface_label,metric,comment,existing}]` (только `proto=static`) | `loadKeeneticRoutes` |
| `schedule` | GET `?profile=` → `{enabled,actions:[{do,hh,mm,dow[]}]}`; POST `?profile=` body=JSON | JSON | `toggleSchedule`,`saveSchedule` |
| `checkip` | GET `?profile=` (через `tun_invnet<slot>`, curl ifconfig.co→ipinfo.io) | JSON `{ip,country,city,region,org,dev}` или `{error}` | `checkIp` |
| `sysinfo` | GET (NDM RCI + /proc) | JSON `{model,os_title,os_release,arch,cpu,cputemp,cpuload,memtotal,memfree,memused,uptime,loadavg}` | `loadSysinfo` |
| `log` | GET (агрегат по слотам) | text | `loadLog` (3с) |
| `pinglog` | GET → `{watchdog:"running/stopped",lines:[…]}`; POST `action=clear` | JSON | `loadPingLog`,`pollWatchdog`(30с),`clearPingLog` |
| `clearlog` | GET (обнуляет invnet-*.log) | text | `clearLog` |
| `autostart` | GET → `yes/no`; POST body `yes/no` | text | `loadAutostart`,`setAutostart` |
| `start` / `stop` | GET (общий S30 start/stop в фоне) | JSON | **не вызываются UI** |

**Мёртвый/несвязанный код старого UI (в новый не переносить):** JS-функции `selectProfile()`,
`activate()`, `del()` ни к чему не привязаны; эндпоинт `activate-profile` достижим только через
них. CGI при этом не трогать.

**Порядок загрузки (`loadAll`):** последовательно `wans → status → profiles`, затем
`loadDevProfiles`, параллельно `stats+autostart+routes`, затем `mode+devs`. При старте сразу
`renderChart()` (буфер из sessionStorage виден до первого полла) и `pollWatchdog()`.

**Лимиты тел CGI (`head -c`):** profile 200 КБ, upload 512 КБ, routes 64 КБ, devices/save 8 КБ;
лимит .ovpn на клиенте — 500 КБ.

---

## 4. Темизация и ассеты (старый UI; в редизайне пересобирается)

**Модель токенов — двухслойная:**
1. **Входной слой (~20 переменных на тему)** в `:root`/`[data-theme=…]`: `--bg,--bg-alt,--surface,
   --ink,--ink-2,--muted,--gold,--gold-deep,--gold-soft,--line,--charcoal,--on-charcoal,--on-gold,
   --ok,--live,--bad,--warn,--info,--shadow-rgb` + шрифты/радиусы.
2. **Производный (semantic) слой** — вычисляется из входных через `color-mix()` и НЕ
   переопределяется в темах: `--surface-2/-raised`, `--overlay`, `--elev-1/2/3`, `--accent*`,
   `--hairline-gold`, шкалы `--space-*`, `--text-*`, `--dur-*`, `--ease-*`.

**7 готовых тем:** `light` (дефолт), `dark`, `noir`, `tokyonight`, `neo`, `mint`, `catppuccin` + **`custom`**.

**Custom-движок:** 3 цвета (акцент/фон/текст) → `applyCustom()` инлайн ставит на
`documentElement` полный набор `CUSTOM_VARS` (16 переменных) через `color-mix()`, определяя
тёмность фона по `_lum()`. `clearCustom()` снимает при переключении на пресет.

**Цвета графика — отдельная валидированная пара** (не акцент бренда): `--chart-rx`/`--chart-tx`,
разные для светлых/тёмных поверхностей (CVD ΔE≥60, контраст ≥3:1).

**Хранение:** `localStorage['vpn-xor-theme-v2'] = {theme, custom}`; миграция со старого ключа
`vpn-xor-theme`; фолбэк `prefers-color-scheme`. При смене темы обновляется
`<meta name=theme-color>` (карта `THEME_BG`).

**Шрифты (self-host, офлайн, сабсеты latin+cyrillic, `font-display: swap`):**
Inter variable (latin 48 256 B + cyr 18 748 B), Playfair Display 600 (23 228 + 12 224 B),
Playfair italic 500 (23 076 + 13 308 B).

**Иконки — единый SVG-спрайт** (`<symbol>` в `#icons`, `currentColor`, штрих 1.6, ~30 символов).
**Логотипы:** `logo-mark.svg` (815 B, favicon+бренд), `logo.svg` (5 167 B).
**Общий вес статики:** ≈280 КБ, всё inline в одном HTML, без внешних JS/CSS.

---

## 5. Особые механизмы (ОБЯЗАНЫ сохраниться в новом UI)

1. **Demo-режим `?demo=1`** — IIFE подменяет `window.fetch` фикстурами (4 профиля, 4 устройства,
   3 маршрута, sysinfo, checkip→Финляндия…). «Живые» stats синусоидой; через 25с добавляется
   свежий рестарт watchdog (проверка тоста/бейджа). Полное превью без роутера.
   Незамоканные POST → `ok`.

2. **Ring-buffer графика rx/tx** — максимум **120 точек** (~10 мин при 5с-полле),
   `sessionStorage['invnet-stats-buf']`. Дельта байт/время с **клампом отрицательных дельт**
   (счётчики `/sys/class/net` сбрасываются при рестарте туннеля). При загрузке буфер фильтруется
   по возрасту. График — inline-SVG (`niceMax` — степень двойки), hover-перекрестие + тач.

3. **Watchdog-дедуп через watermark** — `pollWatchdog()` (30с) парсит `pinglog.lines`.
   Последняя обработанная строка — `localStorage['invnet-wd-seen']`; тосты только для строк
   ПОСЛЕ watermark. Первый запуск — тихо; watermark не найден (лог очищен/ротирован) — без
   тостов. >3 событий → один сводный тост. Бейдж `nav-log-badge` растёт вне вкладки Журнал.

4. **Расписание профилей (сетка 7×24)** — аккордеон под карточкой. Рисование протяжкой
   (pointer events + `elementFromPoint` для тача). Конвертация «сетка ↔ события»
   (`actionsToGrid`/`gridToActions`) в «минутах недели» по кругу (0..10079), edge-triggered.
   Подсказка «сейчас/следующее событие». Бэкенд хранит только события `{do,hh,mm,dow[]}`;
   демон `S41invnet-sched` тикает 30с. Детали — ADR-0001.

5. **Hash-синхронизация вида** — см. §1.

6. **Анти-мерцание при 5с-полле** — сигнатура `PROFILES_SIG` (`JSON.stringify(arr)+SCHED_OPEN`),
   без перерисовки при отсутствии изменений; анимация плиток только до `.ready`; при открытом
   редакторе расписания или активном тумблере (`TOGGLE_BUSY`) перерисовка списка блокируется.

7. **Оптимистичный тумблер** — `profileToggle` шлёт `connect`, спиннер в `big-status`, затем
   поллит `profiles` (1.2с×16) до целевого `running`, блокируя фоновые перерисовки.

8. **Drag&drop .ovpn** — dropzone: перетаскивание/выбор файла (лимит 500 КБ), автоимя из имени
   файла, `FileReader`.

9. **«Одно устройство — одна цель»** — `save-devices`/`save-wan-policy` взаимоисключают привязку
   IP (VPN-профиль ↔ прямой WAN); UI отражает раздельными optgroup и предупреждением.

---

## 6. Ограничения платформы (диктует роутер)

- **lighttpd + sh-CGI**, порт 8888, document-root `/opt/share/invnet`, `^/cgi-bin/ → /bin/sh`.
  CGI отвечают мгновенно, тяжёлое форкают в фон — UI опрашивает статус (иначе браузер висит
  на XOR-handshake 10–20с).
- **Нет сборки/бандлера/npm, нет CDN** — весь фронт = один статический `index.html`
  с inline CSS+JS, работает офлайн.
- **Self-hosted шрифты** — woff2 с кириллическими сабсетами в `/fonts`.
- **`jq` на роутере без regex** — фронт учитывает: bulk-импорт маршрутов одним атомарным
  запросом (гонки записи ломали `invnet-routes.conf`).
- **Источник истины — файл, не процесс** (`enabled` в meta + `invnetctl reconcile`):
  UI отражает `enabled` (тумблер) и `running` (зелёная точка) раздельно.
- **Мульти-профиль:** каждый профиль = отдельный openvpn на `tun_invnet<slot>` (slots 0–7);
  `stats` суммирует все туннели, `checkip` ходит через конкретный слот. UI поддерживает
  N одновременных туннелей.
- **NDM RCI** (`http://127.0.0.1:79/rci/...`, только с роутера): имена WAN, устройства hotspot,
  статические маршруты, sysinfo. Возможны задержки и fallback `[]`/`{}` — фронт обязан переживать
  (скелетоны/empty/«нет данных»).
- **Sysinfo-температура может отсутствовать** (EcoNet без thermal sysfs) — поля деградируют до «—»/`null`.
- **Логи ротируются watchdog'ом** — watermark-дедуп обязан корректно вести себя при обрезанном логе.
- Основная сборка — только **aarch64-3.10** (Keenetic Giga+).
