# Floorp Horizontal Tabs

Кастомизация браузера [Floorp](https://floorp.app/) (форк Firefox), преобразующая вертикальную панель вкладок в горизонтальную многострочную сетку над адресной строкой.

![layout](https://img.shields.io/badge/layout-3_rows_×_N_columns-blue)
![method](https://img.shields.io/badge/method-autoconfig.cfg-orange)

## Что это делает

Floorp по умолчанию отображает вкладки вертикально в боковой панели. Данная кастомизация:

- Переносит панель вкладок наверх (над адресной строкой)
- Располагает обычные вкладки в сетке **3 строки × N колонок** (количество колонок адаптируется к ширине окна)
- Располагает закреплённые (pinned) вкладки в отдельной сетке слева (иконки без текста)
- Переносит кнопки sidebar (расширения, история и т.д.) в правую часть панели вкладок
- Добавляет drag-and-drop перемещение вкладок внутри сетки

## Варианты установки

В проекте два варианта, различающихся способом загрузки:

| | Variant 1 (profile) | Variant 2 (system) |
|---|---|---|
| **Директория** | `variant-1-profile/` | `variant-2-system/` |
| **Куда ставится** | Профиль пользователя (`~/.floorp/*/chrome/`) | Системная директория (`/usr/lib/floorp/`) |
| **Загрузка CSS** | `nsIStyleSheetService` (AGENT_SHEET) | Чтение файла + инжекция `<style>` |
| **Загрузка JS** | `Services.scriptloader.loadSubScript` | Встроен в `autoconfig.cfg` |
| **Сетка** | Фиксированная (6 колонок × 3 строки) | Адаптивная (`auto-fill`) |
| **Статус** | Устаревший, не развивается | **Актуальный** |

**Рекомендуется variant-2-system** — он содержит все последние исправления.

Файлы в корне проекта (`horizontal_tabs.js`, `horizontal_tabs.css`, `autoconfig.cfg`, `autoconfig.js`) — копии variant-1, сохранены для истории.

## Установка (variant-2-system)

### Требования

- Floorp (тестировалось на 11.x)
- Включённые вертикальные вкладки: `about:config` → `sidebar.verticalTabs` = `true`
- Права root (для записи в `/usr/lib/floorp/`)

### Автоматический деплой

```bash
sudo bash deploy-variant-2.sh
```

Скрипт копирует три файла в `/usr/lib/floorp/`:

| Исходный файл | Назначение |
|---|---|
| `variant-2-system/autoconfig.js` | `/usr/lib/floorp/defaults/pref/autoconfig.js` |
| `variant-2-system/autoconfig.cfg` | `/usr/lib/floorp/autoconfig.cfg` |
| `variant-2-system/horizontal_tabs.css` | `/usr/lib/floorp/horizontal_tabs.css` |

### Ручная установка

1. Скопировать `autoconfig.js` в `<floorp>/defaults/pref/`
2. Скопировать `autoconfig.cfg` и `horizontal_tabs.css` в `<floorp>/`
3. Убедиться, что права на файлы `644`
4. Перезапустить Floorp

### Удаление

Удалить три файла из `/usr/lib/floorp/` и перезапустить браузер:

```bash
sudo rm /usr/lib/floorp/autoconfig.cfg
sudo rm /usr/lib/floorp/horizontal_tabs.css
sudo rm /usr/lib/floorp/defaults/pref/autoconfig.js
```

## Настройка

CSS-переменные в `horizontal_tabs.css` (секция `:root`):

| Переменная | По умолчанию | Описание |
|---|---|---|
| `--htabs-panel-height` | `120px` | Высота всей панели вкладок |
| `--htabs-tab-width` | `150px` | Ширина обычной вкладки |
| `--htabs-tab-height` | `40px` | Высота обычной вкладки |
| `--htabs-pinned-cell` | `40px` | Размер ячейки закреплённой вкладки |
| `--htabs-pinned-icon` | `28px` | Размер иконки закреплённой вкладки |
| `--htabs-selected` | `rgba(100, 140, 110, 0.30)` | Фон выделенной вкладки |
| `--htabs-hover` | `rgba(180, 170, 100, 0.20)` | Фон при наведении |
| `--htabs-border` | `rgba(128, 128, 128, 0.3)` | Цвет границ между вкладками |
| `--htabs-border-accent` | `rgba(128, 128, 128, 0.5)` | Цвет акцентных разделителей |

## Ограничения

- **Максимум вкладок** — кнопка «+» скрывается, когда сетка заполнена (3 строки × N колонок в зависимости от ширины окна). Новые вкладки всё ещё можно открывать через Ctrl+T или контекстное меню.
- **Привязка к внутренним API Floorp/Firefox** — код использует monkey-patching внутренних объектов (`tabDragAndDrop`) и обращается к внутренним DOM-элементам (`#tabbrowser-tabs`, `#pinned-tabs-container`, Shadow DOM). Обновления Floorp могут сломать кастомизацию.
- **Только Linux** — деплой-скрипт рассчитан на `/usr/lib/floorp/`. На других ОС пути отличаются.
- **Требует `sidebar.verticalTabs = true`** — если настройка выключена, скрипт не инициализируется (feature detection). Это не баг: кастомизация трансформирует именно вертикальные вкладки в горизонтальные.
- **Drag-and-drop** — работает для одиночных вкладок. Перетаскивание группы вкладок (multi-select drag) не поддерживается полноценно.
- **Не плагин** — WebExtensions API не предоставляет доступ к XUL DOM браузера, поэтому реализация невозможна в виде расширения.

## Диагностика

При старте скрипт записывает диагностические флаги в `about:config`:

| Ключ | Значение | Описание |
|---|---|---|
| `htabs.diag.1_start` | `true` | autoconfig.cfg начал выполнение |
| `htabs.diag.2_css_read` | `true` | CSS-файл прочитан |
| `htabs.diag.2_css_missing` | `true` | CSS-файл не найден |
| `htabs.diag.3_observer` | `true` | Window observer зарегистрирован |
| `htabs.diag.4_verticalTabs_enabled` | `true` | `sidebar.verticalTabs = true`, инициализация запущена |
| `htabs.diag.4_verticalTabs_disabled` | `true` | `sidebar.verticalTabs = false`, инициализация пропущена |
| `htabs.diag.5_init_done` | `true` | Все модули выполнены |

Ошибки модулей выводятся в Browser Console (`Ctrl+Shift+J`) с префиксом `htabs`.

## Структура проекта

```
floorp-custom/
├── README.md                    # Этот файл
├── ARCHITECTURE.md              # Техническая архитектура
├── deploy-variant-2.sh          # Скрипт деплоя
├── variant-2-system/            # Актуальный вариант
│   ├── autoconfig.js            # Указатель на autoconfig.cfg
│   ├── autoconfig.cfg           # JS: модули, оркестратор, DnD
│   └── horizontal_tabs.css      # CSS: сетка, стили вкладок
├── variant-1-profile/           # Устаревший вариант (profile-based)
│   ├── autoconfig.cfg
│   ├── autoconfig.js
│   ├── horizontal_tabs.js
│   └── horizontal_tabs.css
├── horizontal_tabs.js           # Копия variant-1 (legacy)
├── horizontal_tabs.css          # Копия variant-1 (legacy)
├── autoconfig.cfg               # Копия variant-1 (legacy)
└── autoconfig.js                # Копия variant-1 (legacy)
```
